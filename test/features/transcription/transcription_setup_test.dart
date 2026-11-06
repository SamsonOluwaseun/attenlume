import 'dart:io';

import 'package:attenlume/features/transcription/native_pilot.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:attenlume/features/transcription/transcription_screen.dart';
import 'package:attenlume/platform/transcription/transcription_exceptions.dart';
import 'package:attenlume/platform/transcription/whisper_cpu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Represents a platform-provided app directory with an OS-managed alias.
class _PlatformAlias implements Directory {
  _PlatformAlias(this.target);
  final Directory target;
  @override
  String get path => p.join(target.path, 'unresolved-platform-alias');
  @override
  Future<String> resolveSymbolicLinks() => target.resolveSymbolicLinks();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'P3-01c FR-TRN-10 unsupported CPU blocks setup before storage access',
    () async {
      await expectLater(
        createNativePilot(
          Directory('does-not-exist'),
          cpu: PlatformWhisperCpu(
            isWindows: true,
            featurePresent: (_) => false,
          ),
        ),
        throwsA(isA<UnsupportedWhisperCpuException>()),
      );
    },
  );

  testWidgets(
    'P3-01c FR-TRN-10 unsupported CPU shows reason without offering transcription',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transcriptionControllerProvider.overrideWith((ref) async {
              throw const UnsupportedWhisperCpuException();
            }),
          ],
          child: const MaterialApp(home: TranscriptionScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(UnsupportedWhisperCpuException.reason), findsOneWidget);
      expect(find.byKey(const Key('transcription-setup-retry')), findsNothing);
      expect(find.byKey(const Key('transcribe-recording')), findsNothing);
      expect(find.byKey(const Key('transcription-enabled')), findsNothing);
    },
  );

  test(
    'FR-TRN-01 P1-50 platform app-root alias permits fresh model setup',
    () async {
      final root = await Directory.systemTemp.createTemp('pilot-root-');
      try {
        final pilot = await createNativePilot(_PlatformAlias(root));
        expect(await pilot.models.isInstalled(), isFalse);
        expect(
          pilot.models.directory,
          startsWith(await root.resolveSymbolicLinks()),
        );
        expect(
          pilot.models.directory,
          isNot(contains('unresolved-platform-alias')),
        );
        // Setup does not install a model, create an engine or write any files.
        expect(await root.list().toList(), isEmpty);
      } finally {
        await root.delete();
      }
    },
  );

  test('FR-TRN-01 P1-50 owned model storage checks remain strict', () async {
    final root = await Directory.systemTemp.createTemp('pilot-owned-');
    final obstruction = File(p.join(root.path, 'transcription-models-v1'));
    try {
      await obstruction.writeAsString('preserve this unrelated file');
      final pilot = await createNativePilot(root);
      await expectLater(
        pilot.models.isInstalled(),
        throwsA(isA<WhisperStorageException>()),
      );
      expect(await obstruction.readAsString(), 'preserve this unrelated file');
    } finally {
      await obstruction.delete();
      await root.delete();
    }
  });

  testWidgets('FR-TRN-01 P1-50 setup storage error is private and retryable', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transcriptionControllerProvider.overrideWith((ref) async {
            attempts++;
            throw const FileSystemException(
              'sensitive path details',
              '/private/audio',
            );
          }),
        ],
        child: const MaterialApp(home: TranscriptionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('storage could not be opened safely'),
      findsOneWidget,
    );
    expect(find.textContaining('/private/audio'), findsNothing);
    expect(attempts, 1);
    await tester.tap(find.byKey(const Key('transcription-setup-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets(
    'FR-TRN-01 P1-50 unsupported ABI explains why model reinstall cannot help',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transcriptionControllerProvider.overrideWith((ref) async {
              throw UnsupportedError(
                'The transcription pilot needs a 64-bit device.',
              );
            }),
          ],
          child: const MaterialApp(home: TranscriptionScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('64-bit Android app and operating system'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reinstalling the model will not change this'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('transcription-setup-retry')), findsNothing);
    },
  );
}
