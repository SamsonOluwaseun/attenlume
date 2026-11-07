import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/ai/language_model_providers.dart';
import 'package:attenlume/features/capture/recording_providers.dart'
    show freeSpaceProbeProvider;
import 'package:attenlume/features/settings/optional_ai_section.dart';
import 'package:attenlume/platform/ai/language_model_store.dart';
import 'package:attenlume/platform/device/device_memory_probe.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memory implements DeviceMemoryProbe {
  const _Memory(this.bytes);
  final int? bytes;
  @override
  Future<int?> totalBytes() async => bytes;
}

/// A download that only ends when cancelled, and whose cancel drains only
/// when [drain] completes.
class _SlowCancelStore extends LanguageModelStore {
  _SlowCancelStore(Directory dir) : super(baseDirectory: dir);
  final download = Completer<String>();
  final drain = Completer<void>();

  @override
  Future<String> install(
    VerifiedModelDescriptor descriptor, {
    void Function(double)? onProgress,
  }) => download.future;

  @override
  Future<void> cancelInstall({String? modelId}) async {
    await drain.future;
    if (!download.isCompleted) {
      download.completeError(const ModelStorageException('Download cancelled'));
    }
  }
}

class _PendingProbe implements FreeSpaceProbe {
  final answer = Completer<FreeSpace?>();
  @override
  Future<FreeSpace?> query(String path) => answer.future;
}

class _FakeFreeSpaceProbe implements FreeSpaceProbe {
  _FakeFreeSpaceProbe(this.freeBytes);
  int freeBytes;

  @override
  Future<FreeSpace?> query(String path) async {
    return FreeSpace(availableBytes: freeBytes, totalBytes: freeBytes * 2);
  }
}

class _HangingHttpClient extends Fake implements HttpClient {
  final completer = Completer<HttpClientRequest>();

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) => completer.future;

  @override
  void close({bool force = false}) {
    if (!completer.isCompleted) {
      completer.completeError(const HttpException('Cancelled'));
    }
  }
}

class _PendingInstalledModelStore extends LanguageModelStore {
  _PendingInstalledModelStore(Directory directory)
    : super(baseDirectory: directory);

  final check = Completer<String?>();
  int checks = 0;

  @override
  Future<String?> installedPath(VerifiedModelDescriptor descriptor) {
    checks++;
    return check.future;
  }
}

void main() {
  late Directory tempDir;
  late Uint8List testModelBytes;
  late String testSha256;
  late LanguageModelDescriptor testDescriptor;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('optional_ai_section_test_');
    testModelBytes = Uint8List.fromList(
      utf8.encode('mock-gemma-bytes-for-ui-test'),
    );
    testSha256 = sha256.convert(testModelBytes).toString();
    testDescriptor = LanguageModelDescriptor(
      id: 'test-gemma',
      name: 'Gemma 4 E2B, Fast',
      sizeBytes: testModelBytes.length,
      sha256: testSha256,
      downloadUrl: 'https://example.com/gemma.gguf',
      fileName: 'test-gemma.gguf',
      licence: 'Apache 2.0',
      deviceNotice: 'Runs on this device. Nothing you record is sent anywhere.',
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget pumpSection({
    required LanguageModelStore store,
    required FreeSpaceProbe probe,
    LanguageModelController? controller,
    double textScale = 1.0,
    bool dark = false,
    int? memoryBytes,
  }) {
    final ctrl =
        controller ??
        LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
    return ProviderScope(
      overrides: [
        languageModelStoreProvider.overrideWith((ref) async => store),
        freeSpaceProbeProvider.overrideWithValue(probe),
        activeLanguageModelDescriptorProvider.overrideWith(
          (ref) async => testDescriptor,
        ),
        languageModelControllerProvider.overrideWith((ref) async => ctrl),
        deviceMemoryProbeProvider.overrideWithValue(_Memory(memoryBytes)),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: OptionalAiSection()),
        ),
      ),
    );
  }

  group('P3-11 FR-AI-01: model choice', () {
    testWidgets('both models are offered; a 4 GB device is pointed to the '
        'small one, whose terms show before download', (tester) async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: LanguageModelDescriptor.gemma3_1B,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        pumpSection(
          store: store,
          probe: probe,
          controller: controller,
          memoryBytes: 3865470566, // a 4 GB phone reports about 3.6 GiB
        ),
      );
      await tester.pumpAndSettle();

      const small = LanguageModelDescriptor.gemma3_1B;
      const big = LanguageModelDescriptor.gemma4E2B;
      expect(find.text('${big.name} · 2.65 GB'), findsOneWidget);
      expect(find.text('${small.name} · 769 MB'), findsOneWidget);
      final smallTile = find.byKey(Key('optional-ai-choice-${small.id}'));
      expect(
        find.descendant(
          of: smallTile,
          matching: find.textContaining('Recommended for this device.'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Recommended for this device.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('https://ai.google.dev/gemma/terms'),
        findsOneWidget,
      );
      expect(find.text('Copy link'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('optional-ai-download-button')));
      await tester.pumpAndSettle();
      expect(find.text('Download ${small.name}?'), findsOneWidget);
      expect(find.textContaining('769 MB'), findsWidgets);
      expect(
        find.textContaining(
          'By downloading you agree to the Gemma Terms of Use and the '
          'Gemma Prohibited Use Policy.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('optional-ai-confirm-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('the choice is locked from the space check onwards', (
      tester,
    ) async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final probe = _PendingProbe();
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        pumpSection(store: store, probe: probe, controller: controller),
      );
      await tester.pumpAndSettle();
      bool enabled(LanguageModelDescriptor m) => tester
          .widget<RadioListTile<String>>(
            find.byKey(Key('optional-ai-choice-${m.id}')),
          )
          .enabled!;
      expect(enabled(LanguageModelDescriptor.gemma3_1B), isTrue);

      await tester.tap(find.byKey(const Key('optional-ai-download-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('optional-ai-confirm-download')));
      await tester.pump();
      expect(controller.state.status, LanguageModelStatus.checkingSpace);
      expect(enabled(LanguageModelDescriptor.gemma3_1B), isFalse);
      expect(enabled(LanguageModelDescriptor.gemma4E2B), isFalse);

      // Not enough space ends the attempt and unlocks the choice.
      probe.answer.complete(const FreeSpace(availableBytes: 1, totalBytes: 2));
      await tester.pumpAndSettle();
      expect(enabled(LanguageModelDescriptor.gemma3_1B), isTrue);
    });

    testWidgets('the choice stays locked until a cancel has finished', (
      tester,
    ) async {
      final store = _SlowCancelStore(tempDir);
      final probe = _FakeFreeSpaceProbe(100 * 1024 * 1024 * 1024);
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        pumpSection(store: store, probe: probe, controller: controller),
      );
      await tester.pumpAndSettle();
      bool enabled() => tester
          .widget<RadioListTile<String>>(
            find.byKey(
              Key('optional-ai-choice-${LanguageModelDescriptor.gemma3_1B.id}'),
            ),
          )
          .enabled!;

      unawaited(controller.startDownload());
      await tester.pump();
      expect(controller.state.isDownloading, isTrue);
      unawaited(controller.cancelDownload());
      await tester.pump();
      // Shown as not installed, but the old download is still draining.
      expect(controller.busy, isTrue);
      expect(enabled(), isFalse);

      store.drain.complete();
      await tester.pumpAndSettle();
      expect(controller.busy, isFalse);
      expect(enabled(), isTrue);
    });

    test('a storage shortfall names the chosen model and its size', () async {
      final controller = LanguageModelController(
        store: LanguageModelStore(baseDirectory: tempDir),
        freeSpaceProbe: _FakeFreeSpaceProbe(1024),
        descriptor: LanguageModelDescriptor.gemma3_1B,
      );
      addTearDown(controller.dispose);
      expect(await controller.startDownload(), isFalse);
      expect(
        controller.state.errorMessage,
        'Not enough storage to download this model. Gemma 3 1B, Small needs '
        '769 MB plus 1 GB free space.',
      );
    });

    testWidgets(
      'unknown memory recommends nothing; Gemma 4 has no terms step',
      (tester) async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
        await tester.pumpWidget(pumpSection(store: store, probe: probe));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Recommended for this device.'),
          findsNothing,
        );
        expect(find.text('Copy link'), findsNothing);
      },
    );
  });

  group('P3-10 FR-AI-01: Optional AI Settings UI states', () {
    testWidgets(
      'iOS explains summaries are unavailable and offers no download',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              languageModelControllerProvider.overrideWith(
                (ref) => throw StateError('iOS must not open model storage'),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(body: OptionalAiSection(isIos: true)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(OptionalAiSection.iosUnavailableMessage),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('optional-ai-download-button')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('pending storage discovery settles without offering Download', (
      tester,
    ) async {
      final directory = Completer<Directory>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            languageModelDirectoryProvider.overrideWith(
              (ref) => directory.future,
            ),
            installedLanguageModelPathProvider.overrideWith(
              (ref) =>
                  throw StateError('Settings must not request an AI model'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: OptionalAiSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Checking installed model…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(directory.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending installed-file check settles then shows Download', (
      tester,
    ) async {
      final store = _PendingInstalledModelStore(tempDir);
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        pumpSection(store: store, probe: probe, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(find.text('Checking installed model…'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(store.checks, 1);

      store.check.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Checking installed model…'), findsNothing);
      expect(
        find.byKey(const Key('optional-ai-download-button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'displays model name, size, licence, privacy notice and Download button by default',
      (tester) async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await controller.refresh();

        await tester.pumpWidget(
          pumpSection(store: store, probe: probe, controller: controller),
        );
        await tester.pumpAndSettle();

        expect(find.text('Gemma 4 E2B, Fast'), findsOneWidget);
        expect(find.text(testDescriptor.sizeLabel), findsOneWidget);
        expect(find.text('Apache 2.0'), findsOneWidget);
        expect(
          find.text(
            'Runs on this device. Nothing you record is sent anywhere.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('optional-ai-download-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('optional-ai-delete-button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tapping Download confirms with size and note to use Wi-Fi; cancel does not download',
      (tester) async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await controller.refresh();

        await tester.pumpWidget(
          pumpSection(store: store, probe: probe, controller: controller),
        );
        await tester.pumpAndSettle();

        // Tap Download
        await tester.tap(find.byKey(const Key('optional-ai-download-button')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Download Gemma 4 E2B, Fast?'), findsOneWidget);
        expect(find.textContaining('2.65 GB'), findsWidgets);
        expect(find.textContaining('Wi-Fi'), findsOneWidget);

        // Cancel dialog
        await tester.tap(find.byKey(const Key('optional-ai-confirm-cancel')));
        await tester.pumpAndSettle();

        // Still in not installed state; no file on disk
        expect(
          find.byKey(const Key('optional-ai-download-button')),
          findsOneWidget,
        );
        expect(
          File(
            '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
          ).existsSync(),
          isFalse,
        );
      },
    );

    testWidgets(
      'refuses download with plain reason when storage is less than model size plus 1 GB',
      (tester) async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final probe = _FakeFreeSpaceProbe(1024); // Short of space
        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await controller.refresh();

        await tester.pumpWidget(
          pumpSection(store: store, probe: probe, controller: controller),
        );
        await tester.pumpAndSettle();

        // Tap Download and confirm
        await tester.tap(find.byKey(const Key('optional-ai-download-button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('optional-ai-confirm-download')));
        await tester.pumpAndSettle();

        // Refuses with plain reason
        expect(
          find.byKey(const Key('optional-ai-error-message')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Not enough storage to download this model'),
          findsOneWidget,
        );
        expect(
          find.textContaining('plus 1 GB free space'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'confirmed download shows progress bar with Cancel button; Cancel aborts',
      (tester) async {
        final fakeClient = _HangingHttpClient();
        final store = LanguageModelStore(
          baseDirectory: tempDir,
          freeSpaceProbe: _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024),
          httpClientFactory: () => fakeClient,
        );
        final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await controller.refresh();

        await tester.pumpWidget(
          pumpSection(store: store, probe: probe, controller: controller),
        );
        await tester.pumpAndSettle();

        // Tap Download and confirm dialog
        await tester.tap(find.byKey(const Key('optional-ai-download-button')));
        await tester.pumpAndSettle();

        // Confirm download in dialog
        await tester.tap(find.byKey(const Key('optional-ai-confirm-download')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Progress bar and Cancel button are visible
        expect(
          find.byKey(const Key('optional-ai-progress-bar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('optional-ai-cancel-button')),
          findsOneWidget,
        );

        // Tap Cancel
        await tester.tap(find.byKey(const Key('optional-ai-cancel-button')));
        await tester.pumpAndSettle();

        // Returns to Download button state; partial removed
        expect(
          find.byKey(const Key('optional-ai-download-button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'verified installed state shows Delete model; Delete removes files and restores Download state',
      (tester) async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);

        // Pre-install model
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
        );
        file.writeAsBytesSync(testModelBytes);
        File('${file.path}.sha256').writeAsStringSync(testSha256);

        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await tester.runAsync(() async {
          await controller.refresh();
        });

        await tester.pumpWidget(
          pumpSection(store: store, probe: probe, controller: controller),
        );
        await tester.pumpAndSettle();

        expect(find.text('Installed and verified'), findsOneWidget);
        expect(
          find.byKey(const Key('optional-ai-delete-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('optional-ai-download-button')),
          findsNothing,
        );

        // Tap Delete model and confirm
        await tester.tap(find.byKey(const Key('optional-ai-delete-button')));
        await tester.pumpAndSettle();

        expect(find.text('Delete model?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('optional-ai-delete-confirm')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        // Model is deleted and Download button is back
        expect(file.existsSync(), isFalse);
        expect(
          find.byKey(const Key('optional-ai-download-button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FR-AI-01 NFR-09 installed status wraps at phone width and 200 percent text',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = LanguageModelStore(baseDirectory: tempDir);
        final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
        final file = store.targetFile(testDescriptor);
        file.writeAsBytesSync(testModelBytes);
        File('${file.path}.sha256').writeAsStringSync(testSha256);
        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await controller.refresh();
        await tester.pumpWidget(
          pumpSection(
            store: store,
            probe: probe,
            controller: controller,
            textScale: 2.0,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Installed and verified'), findsOneWidget);
        expect(
          find.byKey(const Key('optional-ai-delete-button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('NFR-09 200 percent text scale fits without layout overflow', (
      tester,
    ) async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      await controller.refresh();

      await tester.pumpWidget(
        pumpSection(
          store: store,
          probe: probe,
          controller: controller,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Gemma 4 E2B, Fast'), findsOneWidget);
      expect(
        find.byKey(const Key('optional-ai-download-button')),
        findsOneWidget,
      );
    });
  });
}
