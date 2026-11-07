import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/data/transcription/transcript_store.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/activities/audio_import_providers.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/activity_detail_sheet.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:attenlume/features/playback_review/review_header.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:attenlume/features/transcription/transcription_controller.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:attenlume/features/transcription/transcription_screen.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_free_space_probe.dart';
import '../../fixtures/fake_playback_engine.dart';
import '../../fixtures/fixtures.dart';

class _FakePicker implements AudioFilePicker {
  _FakePicker([this.picked]);

  XFile? picked;
  int pickAudioCalls = 0;

  @override
  Future<XFile?> pickAudio() async {
    pickAudioCalls++;
    return picked;
  }
}

class _FakeInspector implements AudioFileInspector {
  const _FakeInspector({
    this.info = const InspectedAudioInfo(
      duration: Duration(minutes: 5),
      channelCount: 2,
      sampleRateHz: 44100,
      codec: 'mp3',
      container: 'mp3',
    ),
  });

  final InspectedAudioInfo info;

  @override
  Future<InspectedAudioInfo> inspect(File file) async => info;
}

class _MockPilotModelManager implements PilotModelManager {
  @override
  String get name => 'Mock Model';
  @override
  int get downloadBytes => 1000;
  @override
  String get directory => 'mock_dir';
  @override
  Future<bool> isInstalled() async => true;
  @override
  Future<bool> hasFiles() async => true;
  @override
  Future<void> install(void Function(double) onProgress) async {}
  @override
  Future<void> cancelInstall() async {}
  @override
  Future<void> remove() async {}
}

void main() {
  late TestData t;
  late Directory tempDir;
  late Directory mediaRoot;
  late Directory sourceDir;

  setUp(() async {
    t = TestData();
    tempDir = await Directory.systemTemp.createTemp('audio_import_ui_test');
    mediaRoot = Directory(p.join(tempDir.path, 'media'))..createSync();
    sourceDir = Directory(p.join(tempDir.path, 'source'))..createSync();
  });

  tearDown(() async {
    await t.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget wrapWithScope({
    required Widget child,
    required WidgetTester tester,
    RecordingStatus recordingStatus = RecordingStatus.idle,
    List<Override> additionalOverrides = const [],
  }) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        cutRangeRepositoryProvider.overrideWithValue(t.cuts),
        mediaRootProvider.overrideWithValue(() async => mediaRoot),
        mediaFreeBytesProvider.overrideWith((ref) async => null),
        capturePlatformProvider.overrideWithValue(CapturePlatform.android),
        audioCaptureEngineProvider.overrideWithValue(FakeCaptureEngine()),
        freeSpaceProbeProvider.overrideWithValue(FakeFreeSpaceProbe(64 << 30)),
        recordingStatusProvider.overrideWith(
          (ref) => Stream.value(recordingStatus),
        ),
        audioPlaybackEngineFactoryProvider.overrideWithValue(
          FakePlaybackEngine.new,
        ),
        ...additionalOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('P2-13 FR-TRN-03 Audio Import UI', () {
    testWidgets(
      'P2-13 FR-TRN-03 import audio button on conference home triggers import and opens review',
      (tester) async {
        final conf = await t.conference(name: 'Samlytics Conference 2026');
        final audioFile = File(p.join(sourceDir.path, 'imported_keynote.m4a'))
          ..writeAsBytesSync(List.filled(1024, 0x55));

        final fakePicker = _FakePicker(XFile(audioFile.path));
        const fakeInspector = _FakeInspector(
          info: InspectedAudioInfo(
            duration: Duration(minutes: 10),
            channelCount: 2,
            sampleRateHz: 48000,
            codec: 'aac_lc',
            container: 'm4a',
          ),
        );

        await tester.pumpWidget(
          wrapWithScope(
            tester: tester,
            additionalOverrides: [
              audioFilePickerProvider.overrideWithValue(fakePicker),
              audioFileInspectorProvider.overrideWithValue(fakeInspector),
            ],
            child: ConferenceHomeScreen(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        // Verify "Import audio" button is visible
        final importButton = find.byKey(const Key('import-audio-button'));
        expect(importButton, findsOneWidget);
        expect(find.text('Import audio'), findsOneWidget);

        // Tap the button
        await tester.tap(importButton);
        await settle(tester);

        // Verify picker was called
        expect(fakePicker.pickAudioCalls, 1);

        // Verify ReviewScreen was pushed and imported marker is displayed
        expect(find.byType(ReviewScreen), findsOneWidget);
        expect(find.byKey(const Key('review-imported-audio')), findsOneWidget);
        expect(find.text('Imported audio'), findsOneWidget);

        // Verify the source file remains untouched
        expect(audioFile.existsSync(), isTrue);
        expect(audioFile.lengthSync(), 1024);
      },
    );

    testWidgets(
      'P2-13 FR-TRN-03 imported marker shown on review screen and activity detail sheet',
      (tester) async {
        final conf = await t.conference(name: 'Samlytics Conference 2026');
        final act = await t.activities.create(
          conferenceId: conf.id,
          title: 'Guest Lecture',
          typeId: (await t.activities.types()).first.id,
          tags: ['imported'],
        );
        await t.media.addImportedSegment(
          activityId: act.id,
          filePath:
              'conferences/${conf.id}/activities/${act.id}/audio/segment-001.m4a',
          requestedProfile: conf.defaultRecordingProfile,
          codec: 'aac_lc',
          container: 'm4a',
          channelCount: 1,
          sampleRateHz: 48000,
          requestedBitrateBps: 96000,
          inputRoute: importedInputRoute,
          startUtc: DateTime.utc(2026, 11, 7, 10),
          endUtc: DateTime.utc(2026, 11, 7, 10, 1),
          durationMs: 60000,
          bytes: 1024,
          sha256: 'deadbeef',
        );

        // 1. Verify ReviewHeader shows 'Imported audio'
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ReviewHeader(
                title: act.title,
                place: 'Hall A · Samlytics Conference 2026',
                date: '7 Nov 2026',
                durationMs: 60000,
                isImported: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('review-imported-audio')), findsOneWidget);
        expect(find.text('Imported audio'), findsOneWidget);

        // 2. Verify ActivityDetailSheet shows 'Source' and 'Imported audio'
        final summaries = await t.activities.listSummariesForConference(
          conf.id,
        );
        expect(summaries, hasLength(1));

        await tester.pumpWidget(
          wrapWithScope(
            tester: tester,
            child: ActivityDetailSheet(
              summary: summaries.first,
              timezone: 'Europe/London',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Source'), findsOneWidget);
        expect(find.text('Imported audio'), findsOneWidget);
      },
    );

    testWidgets(
      'P2-13 FR-TRN-03 import blocked during recording with reason on conference home',
      (tester) async {
        final conf = await t.conference(name: 'Samlytics Conference 2026');

        const activeStatus = RecordingStatus(
          state: RecordingState.recording,
          activityId: 'dummy-activity',
        );

        await tester.pumpWidget(
          wrapWithScope(
            tester: tester,
            recordingStatus: activeStatus,
            child: ConferenceHomeScreen(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        final importButton = find.byKey(const Key('import-audio-button'));
        expect(importButton, findsOneWidget);

        await tester.tap(importButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Plain explanation shown in SnackBar
        expect(
          find.text(
            'Cannot import audio while a recording is in progress. Stop recording first to avoid interruptions.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'P2-13 FR-TRN-03 start activity sheet includes import audio button',
      (tester) async {
        final conf = await t.conference(name: 'Samlytics Conference 2026');
        final audioFile = File(p.join(sourceDir.path, 'sheet_import.wav'))
          ..writeAsBytesSync(List.filled(512, 0x12));

        final fakePicker = _FakePicker(XFile(audioFile.path));
        const fakeInspector = _FakeInspector(
          info: InspectedAudioInfo(
            duration: Duration(minutes: 2),
            channelCount: 1,
            sampleRateHz: 16000,
            codec: 'pcm_s16le',
            container: 'wav',
          ),
        );

        await tester.pumpWidget(
          wrapWithScope(
            tester: tester,
            additionalOverrides: [
              audioFilePickerProvider.overrideWithValue(fakePicker),
              audioFileInspectorProvider.overrideWithValue(fakeInspector),
            ],
            child: StartActivitySheet(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        final sheetImportButton = find.byKey(
          const Key('start-sheet-import-audio-button'),
        );
        expect(sheetImportButton, findsOneWidget);

        await tester.ensureVisible(sheetImportButton);
        await tester.pumpAndSettle();

        await tester.tap(sheetImportButton);
        await settle(tester);

        expect(fakePicker.pickAudioCalls, 1);
        final acts = await t.activities.listForConference(conf.id);
        expect(acts, hasLength(1));
        expect(acts.first.title, 'sheet_import');
        expect(acts.first.tags, contains('imported'));
      },
    );

    testWidgets(
      'P2-13 FR-TRN-03 transcription screen uses injectable audio file picker',
      (tester) async {
        final transcriptDir = Directory(p.join(tempDir.path, 'transcripts'))
          ..createSync();
        final fakePicker = _FakePicker();
        final controller = TranscriptionController(
          models: _MockPilotModelManager(),
          store: TranscriptStore(transcriptDir),
          createEngine: () => throw StateError('Not needed for picker test'),
          writeEnabled: (_) async {},
          recordingHeld: () => false,
          enabled: true,
        )..installed = true;
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          wrapWithScope(
            tester: tester,
            additionalOverrides: [
              transcriptionControllerProvider.overrideWith(
                (ref) async => controller,
              ),
              audioFilePickerProvider.overrideWithValue(fakePicker),
            ],
            child: const TranscriptionScreen(activityId: null),
          ),
        );
        await tester.pumpAndSettle();

        final transcribeButton = find.byKey(const Key('transcribe-recording'));
        expect(transcribeButton, findsOneWidget);

        await tester.ensureVisible(transcribeButton);
        await tester.pumpAndSettle();

        await tester.tap(transcribeButton);
        await tester.pumpAndSettle();

        expect(fakePicker.pickAudioCalls, 1);
      },
    );

    testWidgets(
      'P2-13 FR-TRN-03 import audio displays progress dialog and Cancel leaves no file, activity or segment',
      (tester) async {
        final conf = await t.conference(name: 'Samlytics Conference 2026');
        final sourceFile = File(p.join(sourceDir.path, 'Lecture_Progress.mp3'))
          ..writeAsBytesSync(List.filled(4096, 0x33));

        Stream<List<int>> slowRead(File f) async* {
          yield List.filled(1024, 0x33);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          yield List.filled(1024, 0x33);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          yield List.filled(1024, 0x33);
        }

        final fakePicker = _FakePicker(XFile(sourceFile.path));
        const fakeInspector = _FakeInspector(
          info: InspectedAudioInfo(
            duration: Duration(minutes: 5),
            channelCount: 2,
            sampleRateHz: 44100,
            codec: 'mp3',
            container: 'mp3',
          ),
        );

        final customImportService = AudioImportService(
          db: t.db,
          activities: t.activities,
          conferences: t.conferences,
          media: t.media,
          mediaRoot: () async => mediaRoot,
          picker: fakePicker,
          inspector: fakeInspector,
          openRead: slowRead,
        );

        await tester.pumpWidget(
          wrapWithScope(
            tester: tester,
            additionalOverrides: [
              audioImportServiceProvider.overrideWithValue(customImportService),
              audioFilePickerProvider.overrideWithValue(fakePicker),
              audioFileInspectorProvider.overrideWithValue(fakeInspector),
            ],
            child: ConferenceHomeScreen(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Import audio button
        final importButton = find.byKey(const Key('import-audio-button'));
        expect(importButton, findsOneWidget);
        await tester.tap(importButton);

        // Advance past picker to show dialog during slow read
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify progress dialog appears with file name, progress bar, and Cancel button
        expect(
          find.byKey(const Key('audio-import-progress-dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('audio-import-progress-filename')),
          findsOneWidget,
        );
        expect(find.text('Lecture_Progress.mp3'), findsOneWidget);
        expect(
          find.byKey(const Key('audio-import-progress-bar')),
          findsOneWidget,
        );

        final cancelButton = find.byKey(
          const Key('audio-import-cancel-button'),
        );
        expect(cancelButton, findsOneWidget);

        // Tap Cancel while copying is in progress
        await tester.tap(cancelButton);
        await tester.pump();
        await settle(tester);
        await settle(tester);

        // Verify dialog is dismissed
        expect(
          find.byKey(const Key('audio-import-progress-dialog')),
          findsNothing,
        );

        // Verify no files on disk
        final mediaFiles = mediaRoot
            .listSync(recursive: true)
            .whereType<File>()
            .toList();
        expect(mediaFiles, isEmpty);

        // Verify no activity created in DB
        final acts = await t.activities.listForConference(conf.id);
        expect(acts, isEmpty);

        // Verify no segment created in DB
        final segs = await t.media.segmentPaths();
        expect(segs, isEmpty);

        // Verify original source file untouched
        expect(sourceFile.existsSync(), isTrue);
        expect(sourceFile.lengthSync(), 4096);
      },
    );
  });
}
