import 'dart:io';
import 'dart:ui' as ui;

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/transcription/transcript_store.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/settings/settings_screen.dart';
import 'package:attenlume/features/transcription/transcription_controller.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:attenlume/features/transcription/transcription_screen.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

class _Model implements PilotModelManager {
  @override
  String get name => 'Tiny English · pilot';
  @override
  int get downloadBytes => 32166155;
  @override
  String get directory => 'unused';
  @override
  Future<bool> isInstalled() async => false;
  @override
  Future<void> install(void Function(double) onProgress) async {}
  @override
  Future<void> cancelInstall() async {}
  @override
  Future<void> remove() async {}
}

void main() {
  late Directory temp;
  late TranscriptionController controller;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('transcription-ui-');
    controller = TranscriptionController(
      models: _Model(),
      store: TranscriptStore(temp),
      createEngine: () => throw StateError('UI must not create an engine'),
      writeEnabled: (_) async {},
      recordingHeld: () => false,
    );
  });
  tearDown(() async {
    await controller.cancel();
    controller.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
    bool private = false,
    String? activityId,
    bool hasCuts = false,
    Future<XFile?> Function()? picker,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transcriptionControllerProvider.overrideWith(
            (ref) async => controller,
          ),
          transcriptionEditsPresentProvider.overrideWith(
            (ref, id) async => hasCuts,
          ),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const Key('guide-capture'),
            child: TranscriptionScreen(
              activityId: private ? 'private-activity' : activityId,
              isPrivate: private,
              pickAudio: picker,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'FR-TRN-01/02 first visit is off and consent cancellation downloads nothing',
    (tester) async {
      await pump(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('transcription-enabled')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('transcribe-recording')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('transcription-enabled')));
      await tester.pumpAndSettle();
      expect(find.text('Enable optional transcription?'), findsOneWidget);
      expect(find.textContaining('Audio is not uploaded.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
    },
  );

  testWidgets(
    'FR-TRN-09 private transcript copy and share require explicit opt-in',
    (tester) async {
      controller.documents = [
        TranscriptDocument(
          activityId: 'private-activity',
          segmentId: 'segment',
          createdAt: DateTime.utc(2026),
          machineSpans: [
            TranscriptSpan(
              start: Duration.zero,
              end: const Duration(seconds: 1),
              text: 'Samlytics Data Services',
            ),
          ],
        ),
      ];
      await pump(tester, private: true);
      expect(
        find.byType(SelectableText),
        findsNothing,
        reason: 'private text selection cannot bypass copy opt-in',
      );
      await tester.scrollUntilVisible(find.text('Copy text'), 250);
      final copy = find.widgetWithText(TextButton, 'Copy text');
      expect(tester.widget<TextButton>(copy).onPressed, isNull);
      final include = find.widgetWithText(
        SwitchListTile,
        'Include private transcript in copy or share',
      );
      await tester.ensureVisible(include);
      await tester.tap(include);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(copy).onPressed, isNotNull);
    },
  );

  testWidgets(
    'FR-TRN-09 edited activity cannot transcribe or expose old original-audio text',
    (tester) async {
      controller.enabled = true;
      controller.installed = true;
      controller.documents = [
        TranscriptDocument(
          activityId: 'edited',
          segmentId: 'segment',
          createdAt: DateTime.utc(2026),
          machineSpans: [
            TranscriptSpan(
              start: Duration.zero,
              end: const Duration(seconds: 1),
              text: 'Original speech removed by a cut',
            ),
          ],
        ),
      ];
      await pump(tester, activityId: 'edited', hasCuts: true);
      await tester.scrollUntilVisible(
        find.byKey(const Key('transcribe-recording')),
        180,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('transcribe-recording')))
            .onPressed,
        isNull,
      );
      expect(find.text('Original speech removed by a cut'), findsNothing);
      expect(
        find.textContaining('Import its exported trimmed audio'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FR-TRN-08 selecting a second import preserves history when recognition fails',
    (tester) async {
      controller.enabled = true;
      controller.installed = true;
      controller.documents = [
        TranscriptDocument(
          activityId: 'import-previous',
          segmentId: 'audio',
          createdAt: DateTime.utc(2026),
          machineSpans: [
            TranscriptSpan(
              start: Duration.zero,
              end: const Duration(seconds: 1),
              text: 'Samlytics Data Services',
            ),
          ],
        ),
      ];
      await pump(tester, picker: () async => XFile('second-audio.wav'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('transcribe-recording')),
        180,
      );
      await tester.tap(find.byKey(const Key('transcribe-recording')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 200 && controller.busy; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(controller.documents.single.activityId, 'import-previous');
      expect(controller.busy, isFalse);
      expect(controller.message, contains('could not finish'));
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'NFR-09 transcription at 200% text has no overflow (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(540, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pump(tester, dark: dark, scale: 2);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('FR-UI-09 optional transcription guide capture shows off state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('CAPTURE_GUIDE')) {
      final fonts = FontLoader('Montserrat')
        ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await tester.runAsync(() async {
        await fonts.load();
        await icons.load();
      });
    }
    await pump(tester);
    expect(find.text('Not installed', findRichText: true), findsNothing);
    expect(find.textContaining('Not installed'), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_GUIDE')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('guide-capture')),
      );
      await tester.runAsync(() async {
        final capture = await boundary.toImage();
        final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
        await File('tool/logs/transcription-guide.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        capture.dispose();
      });
      await tester.pump();
    }
  });

  testWidgets('FR-TRN-01 Settings does not initialise optional transcription', (
    tester,
  ) async {
    final data = TestData();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(data.close);
    });
    tester.view.physicalSize = const Size(540, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(data.db),
          recordingStatusProvider.overrideWith(
            (ref) => Stream.value(RecordingStatus.idle),
          ),
          transcriptionControllerProvider.overrideWith(
            (ref) =>
                throw StateError('Settings must not initialise transcription'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RepaintBoundary(
            key: Key('settings-guide'),
            child: SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-transcription')),
      180,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_GUIDE')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('settings-guide')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tool/logs/transcription-settings-guide.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump();
    }
  });
}
