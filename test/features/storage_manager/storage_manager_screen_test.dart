import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/storage_manager/storage_manager_screen.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/fixtures.dart';

class FakeFreeSpaceProbe implements FreeSpaceProbe {
  FakeFreeSpaceProbe({
    this.availableBytes = 50 * 1024 * 1024 * 1024,
    this.totalBytes = 128 * 1024 * 1024 * 1024,
  });

  int? availableBytes;
  int? totalBytes;

  @override
  Future<FreeSpace?> query(String path) async {
    if (availableBytes == null || totalBytes == null) return null;
    return FreeSpace(availableBytes: availableBytes!, totalBytes: totalBytes!);
  }
}

void main() {
  late TestData t;
  late Directory tempMediaDir;
  late FakeFreeSpaceProbe fakeProbe;

  setUp(() async {
    t = TestData();
    tempMediaDir = await Directory.systemTemp.createTemp(
      'attenlume_storage_widget_test_',
    );
    fakeProbe = FakeFreeSpaceProbe();
  });

  tearDown(() async {
    await t.close();
    if (tempMediaDir.existsSync()) {
      await tempMediaDir.delete(recursive: true);
    }
  });

  Widget createWidget({String? initialConferenceId}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        mediaRootProvider.overrideWithValue(() async => tempMediaDir),
        freeSpaceProbeProvider.overrideWithValue(fakeProbe),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: StorageManagerScreen(initialConferenceId: initialConferenceId),
      ),
    );
  }

  Future<void> createTestSegment(
    String activityId, {
    required String filePath,
    required int bytes,
  }) async {
    final now = DateTime.utc(2026, 11, 4, 9, 30);
    final seg = await t.media.startSegment(
      activityId: activityId,
      filePath: filePath,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      inputRoute: 'built_in',
      startUtc: now,
    );
    await t.media.finaliseSegment(
      seg.id,
      endUtc: now.add(const Duration(seconds: 30)),
      endReason: SegmentEndReason.userStop,
      durationMs: 30000,
      bytes: bytes,
      sha256: 'f' * 64,
      observedBitrateBps: 48000,
    );
  }

  testWidgets(
    'FR-STO-05 Storage Manager screen renders overview and category chips',
    (tester) async {
      final conf = await t.conference(name: 'Data Summit London');
      final act = await t.activity(conf.id, title: 'Keynote');

      final segPath = MediaPaths.segment(conf.id, act.id, 1);
      final segFile = MediaPaths.resolve(tempMediaDir, segPath);
      await segFile.parent.create(recursive: true);
      await segFile.writeAsBytes(List.filled(12 * 1024 * 1024, 1));
      await createTestSegment(
        act.id,
        filePath: segPath,
        bytes: 12 * 1024 * 1024,
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Storage Manager'), findsOneWidget);
      expect(find.byKey(const Key('storage-overview-card')), findsOneWidget);
      expect(find.text('Device storage'), findsOneWidget);
      expect(find.text('12 MB'), findsWidgets);
      expect(
        find.textContaining('Free space: 50 GB of 128 GB available'),
        findsOneWidget,
      );

      expect(find.text('Audio: 12 MB'), findsOneWidget);
      expect(find.text('Photos: 0 B'), findsOneWidget);
      expect(find.text('Models: 0 B'), findsOneWidget);

      expect(find.text('Data Summit London'), findsOneWidget);
      expect(find.text('Not exported'), findsOneWidget);
    },
  );

  testWidgets(
    'FR-STO-05 expanding conference card reveals activity tiles with sizes and export badges',
    (tester) async {
      final conf = await t.conference(name: 'Tech Horizon');
      final act1 = await t.activity(conf.id, title: 'Morning Keynote');
      final act2 = await t.activity(conf.id, title: 'Afternoon Workshop');

      final segPath1 = MediaPaths.segment(conf.id, act1.id, 1);
      final segFile1 = MediaPaths.resolve(tempMediaDir, segPath1);
      await segFile1.parent.create(recursive: true);
      await segFile1.writeAsBytes(List.filled(5 * 1024 * 1024, 1));
      await createTestSegment(
        act1.id,
        filePath: segPath1,
        bytes: 5 * 1024 * 1024,
      );

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap conference card to expand
      await tester.tap(find.text('Tech Horizon'));
      await tester.pumpAndSettle();

      expect(find.text('Morning Keynote'), findsOneWidget);
      expect(find.text('Afternoon Workshop'), findsOneWidget);
      expect(
        find.byKey(Key('activity-storage-tile-${act1.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('activity-storage-tile-${act2.id}')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FR-STO-05 kept originals card renders when kept originals exist and allows removal',
    (tester) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      final origDir = Directory(
        p.join(tempMediaDir.path, MediaPaths.originalsFolder(conf.id, act.id)),
      );
      await origDir.create(recursive: true);
      final origFile = File(p.join(origDir.path, 'trimmed.m4a'));
      await origFile.writeAsBytes(List.filled(2 * 1024 * 1024, 1));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Originals kept after trimming'), findsOneWidget);
      expect(find.text('1 file(s) • 2.0 MB'), findsOneWidget);

      // Tap remove
      await tester.tap(find.byKey(const Key('remove-kept-originals-button')));
      await tester.pumpAndSettle();

      expect(find.text('Remove kept originals'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('confirm-remove-kept-originals-dialog-button')),
      );
      await tester.pumpAndSettle();

      // Original is deleted, card disappears
      expect(origFile.existsSync(), isFalse);
      expect(find.text('Originals kept after trimming'), findsNothing);
    },
  );

  testWidgets(
    'FR-STO-06 "Delete local copies" button is disabled when conference export is not verified',
    (tester) async {
      final conf = await t.conference();
      await t.activity(conf.id);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(
        Key('delete-local-conference-${conf.id}'),
      );
      expect(buttonFinder, findsOneWidget);

      // Verify that the button is disabled (onPressed is null)
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: buttonFinder,
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'FR-STO-06 "Delete local copies" opens preview dialog when export is verified',
    (tester) async {
      final conf = await t.conference(name: 'Verified Conf');
      final act = await t.activity(conf.id, title: 'Talk');

      final segPath = MediaPaths.segment(conf.id, act.id, 1);
      final segFile = MediaPaths.resolve(tempMediaDir, segPath);
      await segFile.parent.create(recursive: true);
      await segFile.writeAsBytes(List.filled(3 * 1024 * 1024, 1));
      await createTestSegment(
        act.id,
        filePath: segPath,
        bytes: 3 * 1024 * 1024,
      );

      // Add verified export
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.complete(job.id, VerificationLevel.checksum);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Verified'), findsOneWidget);

      final buttonFinder = find.byKey(
        Key('delete-local-conference-${conf.id}'),
      );
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      // Preview dialog appears
      expect(find.text('Delete local copies'), findsOneWidget);
      expect(find.text('Files to delete:'), findsOneWidget);
      expect(find.text('Audio recordings'), findsOneWidget);
      expect(
        find.byKey(const Key('keep-lightweight-index-checkbox')),
        findsOneWidget,
      );

      // Confirm delete
      await tester.tap(find.byKey(const Key('confirm-delete-local-button')));
      await tester.pumpAndSettle();

      expect(segFile.existsSync(), isFalse);
    },
  );

  testWidgets(
    'FR-STO-06 "Clear temporary files" dialog opens and executes cleanup',
    (tester) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      final wavePath = MediaPaths.waveform(conf.id, act.id, 'seg1');
      final waveFile = MediaPaths.resolve(tempMediaDir, wavePath);
      await waveFile.parent.create(recursive: true);
      await waveFile.writeAsBytes(List.filled(1500, 1));

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear-safe-temp-button')));
      await tester.pumpAndSettle();

      expect(find.text('Clear safe temporary files'), findsOneWidget);
      expect(find.text('Derived & scratch files:'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-clear-temp-button')));
      await tester.pumpAndSettle();

      expect(waveFile.existsSync(), isFalse);
    },
  );

  testWidgets(
    'FR-STO-06 "Manage offline models" dialog opens and displays phase 2 info',
    (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manage-models-button')));
      await tester.pumpAndSettle();

      expect(find.text('Manage offline models'), findsOneWidget);
      expect(find.text('Phase 2 Feature'), findsOneWidget);
      expect(
        find.textContaining('Attenlume is strictly offline-first'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('close-models-dialog-button')));
      await tester.pumpAndSettle();

      expect(find.text('Manage offline models'), findsNothing);
    },
  );
}
