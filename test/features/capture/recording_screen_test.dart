import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/one_active_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/domain/services/safety_prompt_service.dart';
import 'package:attenlume/features/capture/mic_test_sheet.dart';
import 'package:attenlume/features/capture/quick_thought_sheet.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/capture/recording_screen.dart';
import 'package:attenlume/platform/camera/photo_camera.dart';
import 'package:attenlume/platform/diagnostics/battery_probe.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_photo_camera.dart';
import '../../fixtures/fake_timers.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory tempDir;
  late FakeCaptureEngine fakeEngine;
  late FakePhotoCamera fakeCamera;
  late RecordingService recordingService;
  late OneActiveCoordinator oneActiveCoordinator;
  var mockTime = DateTime(2026, 10, 27, 10, 0);

  DateTime getClock() => mockTime;

  void advanceTime([Duration duration = const Duration(seconds: 1)]) {
    mockTime = mockTime.add(duration);
  }

  Future<void> settleAsync(
    WidgetTester tester, [
    Duration advance = const Duration(milliseconds: 100),
  ]) async {
    advanceTime(advance);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> disposeService(WidgetTester tester) async {
    var disposed = false;
    unawaited(recordingService.dispose().then((_) => disposed = true));
    for (var i = 0; i < 200 && !disposed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  setUp(() async {
    mockTime = DateTime(2026, 10, 27, 10, 0);
    t = TestData();
    tempDir = await Directory.systemTemp.createTemp('recording_screen_test_');
    fakeEngine = FakeCaptureEngine()..level = -20.0;
    fakeCamera = FakePhotoCamera();

    recordingService = RecordingService(
      engine: fakeEngine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => tempDir,
      platform: CapturePlatform.android,
      clock: () => mockTime.toUtc(),
      rollTimer: FakeTimers().call,
      hashFile: (_) async => 'hash',
    );

    oneActiveCoordinator = OneActiveCoordinator(
      recorder: recordingService,
      activities: t.activities,
      media: t.media,
      confirmations: InAppTriggerConfirmations(),
      clock: () => mockTime.toUtc(),
    );
  });

  tearDown(() async {
    await recordingService.dispose();
    await t.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildSubject({
    required String activityId,
    required WidgetTester tester,
    RecordingStatus? statusOverride,
    SafetyPromptService? safety,
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
        mediaRootProvider.overrideWithValue(() async => tempDir),
        audioCaptureEngineProvider.overrideWithValue(fakeEngine),
        photoCameraProvider.overrideWithValue(fakeCamera),
        capturePlatformProvider.overrideWithValue(CapturePlatform.android),
        mediaFreeBytesProvider.overrideWith((ref) async => 500 * 1024 * 1024),
        recordingServiceProvider.overrideWithValue(recordingService),
        oneActiveCoordinatorProvider.overrideWithValue(oneActiveCoordinator),
        if (safety != null)
          safetyPromptServiceProvider.overrideWithValue(safety),
        if (statusOverride != null)
          recordingStatusProvider.overrideWith(
            (ref) => Stream.value(statusOverride),
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.live(),
        home: RecordingScreen(
          activityId: activityId,
          clock: getClock,
          enableTicker: false,
        ),
      ),
    );
  }

  group('FR-UI-01 & FR-UI-02 RecordingScreen header and controls', () {
    testWidgets('FR-UI-02 displays conference title, activity title and room', (
      tester,
    ) async {
      final conf = await t.conference(name: 'DevFest London');
      final act = await t.activity(conf.id, title: 'Building with Flutter');
      await t.activities.update(
        act.id,
        const ActivitiesCompanion(room: Value('Room 101')),
      );

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recording-screen-title')), findsOneWidget);
      expect(find.text('Building with Flutter'), findsOneWidget);
      expect(
        find.byKey(const Key('recording-screen-subtitle')),
        findsOneWidget,
      );
      expect(find.text('DevFest London · Room 101'), findsOneWidget);
      expect(find.byKey(const Key('input-source-indicator')), findsOneWidget);
      expect(find.byKey(const Key('record-status-idle')), findsOneWidget);
      expect(find.byKey(const Key('record-button-start')), findsOneWidget);
    });

    testWidgets(
      'FR-UI-01 starts recording on Record tap and displays LIVE controls',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Keynote Session');

        await tester.pumpWidget(
          buildSubject(activityId: act.id, tester: tester),
        );
        await tester.pumpAndSettle();

        // Tap Record
        await tester.tap(find.byKey(const Key('record-button-start')));
        await settleAsync(tester);

        // Now recording
        expect(recordingService.status.state, equals(RecordingState.recording));
        expect(find.byKey(const Key('record-status-live')), findsOneWidget);
        expect(
          find.byKey(const Key('record-button-pause-resume')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('record-button-stop')), findsOneWidget);
        await disposeService(tester);
      },
    );

    testWidgets('FR-UI-01 Pause, Resume, and Stop controls work cleanly', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Session');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      // Start
      await tester.tap(find.byKey(const Key('record-button-start')));
      await settleAsync(tester, const Duration(milliseconds: 700));
      expect(recordingService.status.state, equals(RecordingState.recording));

      // Pause
      await tester.tap(find.byKey(const Key('record-button-pause-resume')));
      await settleAsync(tester, const Duration(milliseconds: 700));
      expect(recordingService.status.state, equals(RecordingState.paused));
      expect(find.text('Resume'), findsOneWidget);

      // Resume
      await tester.tap(find.byKey(const Key('record-button-pause-resume')));
      await settleAsync(tester, const Duration(milliseconds: 700));
      expect(recordingService.status.state, equals(RecordingState.recording));

      // Stop
      await tester.tap(find.byKey(const Key('record-button-stop')));
      await settleAsync(tester, const Duration(milliseconds: 700));
      expect(recordingService.status.state, equals(RecordingState.saved));

      // Saved SnackBar shown with Undo
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await disposeService(tester);
    });

    testWidgets(
      'FR-UI-01 says microphone access is needed when permission is refused',
      (tester) async {
        fakeEngine.permission = false;
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Session');

        await tester.pumpWidget(
          buildSubject(activityId: act.id, tester: tester),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('record-button-start')));
        await settleAsync(tester, const Duration(milliseconds: 700));

        expect(recordingService.status.state, isNot(RecordingState.recording));
        expect(
          find.textContaining('Attenlume needs microphone access'),
          findsOneWidget,
        );
        await disposeService(tester);
      },
    );
  });

  group('FR-UI-03 Photo capture', () {
    testWidgets(
      'FR-UI-03 Photo opens the camera, the shutter stays ready, and the count updates',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Panel Discussion');

        await tester.pumpWidget(
          buildSubject(activityId: act.id, tester: tester),
        );
        await tester.pumpAndSettle();

        // Photo opens the in-app camera with a viewfinder (P1-14)
        await tester.tap(find.byKey(const Key('record-action-photo')));
        await settleAsync(tester, const Duration(milliseconds: 700));
        expect(find.byKey(const Key('camera-screen')), findsOneWidget);
        expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);

        // Two shots in a row: the shutter is ready again after each
        await tester.tap(find.byKey(const Key('camera-shutter-button')));
        await settleAsync(tester, const Duration(milliseconds: 700));
        await tester.tap(find.byKey(const Key('camera-shutter-button')));
        await settleAsync(tester, const Duration(milliseconds: 700));
        expect(fakeCamera.shots, equals(2));
        expect(find.text('2 photos'), findsOneWidget);

        // Close returns to the recording screen
        await tester.tap(find.byKey(const Key('camera-close-button')));
        await settleAsync(tester, const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('camera-screen')), findsNothing);
        expect(await t.media.photosFor(act.id), hasLength(2));
        expect(find.text('2 photos saved'), findsOneWidget);
        expect(fakeCamera.closed, isTrue);
      },
    );

    testWidgets('FR-PRI-04 the camera explains when access is denied', (
      tester,
    ) async {
      fakeCamera.openError = const CameraAccessDeniedException();
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Panel Discussion');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-action-photo')));
      await settleAsync(tester, const Duration(milliseconds: 700));

      expect(
        find.textContaining('Attenlume needs camera access'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('camera-shutter-button')));
      await settleAsync(tester);
      expect(fakeCamera.shots, 0);
    });

    testWidgets('FR-PHO-01 the camera says when there is no camera', (
      tester,
    ) async {
      fakeCamera.lenses = const [];
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Panel Discussion');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-action-photo')));
      await settleAsync(tester, const Duration(milliseconds: 700));

      expect(find.text('No camera found on this device.'), findsOneWidget);
    });
  });

  group('FR-UI-04 Bookmark chips and button', () {
    testWidgets('FR-UI-04 tapping bookmark button creates default bookmark', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Workshop');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-action-bookmark')));
      await settleAsync(tester);

      final bookmarks = await t.media.bookmarksFor(act.id);
      expect(bookmarks, hasLength(1));
      expect(bookmarks.first.label, equals('Bookmark'));
    });

    testWidgets('FR-UI-04 tapping standard chips creates labeled bookmark', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Workshop');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      // Tap "Important moment" chip
      final chipFinder = find.byKey(
        const Key('bookmark-chip-Important moment'),
      );
      expect(chipFinder, findsOneWidget);

      await tester.tap(chipFinder);
      await settleAsync(tester, const Duration(milliseconds: 700));

      final bookmarks = await t.media.bookmarksFor(act.id);
      expect(bookmarks, hasLength(1));
      expect(bookmarks.first.label, equals('Important moment'));
      expect(find.text('Bookmarked: Important moment'), findsOneWidget);
    });
  });

  group('FR-UI-05 Quick thought note', () {
    testWidgets(
      'FR-UI-05 note button opens QuickThoughtSheet and saves text reflection',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Roundtable');

        await tester.pumpWidget(
          buildSubject(activityId: act.id, tester: tester),
        );
        await tester.pumpAndSettle();

        // Tap Note button
        await tester.tap(find.byKey(const Key('record-action-note')));
        await tester.pumpAndSettle();

        expect(find.byType(QuickThoughtSheet), findsOneWidget);
        expect(find.text('Quick Thought'), findsOneWidget);

        // Enter text
        await tester.enterText(
          find.byKey(const Key('quick-thought-input')),
          'Key insight on caching architectures',
        );

        // Save
        await tester.tap(find.byKey(const Key('quick-thought-save-button')));
        await settleAsync(tester);

        // Sheet closed
        expect(find.byType(QuickThoughtSheet), findsNothing);

        // Bookmark created with note
        final bookmarks = await t.media.bookmarksFor(act.id);
        expect(bookmarks, hasLength(1));
        expect(
          bookmarks.first.note,
          equals('Key insight on caching architectures'),
        );

        // Activity notes updated
        final updatedAct = await t.activities.get(act.id);
        expect(
          updatedAct?.notesMd,
          contains('Key insight on caching architectures'),
        );
      },
    );
  });

  group('FR-UI-06 Microphone test from recording screen', () {
    testWidgets('FR-UI-06 mic test button in app bar opens MicTestSheet', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Session');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recording-screen-mic-test')));
      await settleAsync(tester);

      expect(find.byType(MicTestSheet), findsOneWidget);
      expect(find.text('10-Second Microphone Test'), findsOneWidget);
    });
  });

  group('FR-UI-08 & ADR-021 Profile selector and interruption banner', () {
    testWidgets('FR-UI-08 profile selector is present on screen', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Session');

      await tester.pumpWidget(buildSubject(activityId: act.id, tester: tester));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('recording-screen-profile-selector')),
        findsOneWidget,
      );
      expect(find.text('Balanced'), findsOneWidget);
    });

    testWidgets(
      'ADR-021 displays interruption banner when recording is interrupted',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Session');

        final interruptedStatus = RecordingStatus(
          state: RecordingState.userResumeRequired,
          activityId: act.id,
          interruption: InterruptionReason.call,
          errorMessage: 'Recording paused for a call or another app.',
        );

        await tester.pumpWidget(
          buildSubject(
            activityId: act.id,
            tester: tester,
            statusOverride: interruptedStatus,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('recording-interruption-banner')),
          findsOneWidget,
        );
        expect(
          find.text('Recording paused for a call or another app.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('recording-resume-banner-button')),
          findsOneWidget,
        );
      },
    );
  });

  group('FR-REC-06 safety prompts [P1-13]', () {
    SafetyPromptService safetyFor(double level) => SafetyPromptService(
      recorder: recordingService,
      level: () async => level,
      battery: const UnknownBatteryProbe(),
      createTimer: (_, _) => Timer(const Duration(days: 365), () {}),
      clock: () => mockTime.toUtc(),
    )..start();

    testWidgets(
      'FR-REC-06 after 2 hours asks "Still in" and Keep recording dismisses it',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Keynote');
        final safety = safetyFor(-20);
        addTearDown(safety.dispose);

        await tester.pumpWidget(
          buildSubject(activityId: act.id, tester: tester, safety: safety),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('record-button-start')));
        await settleAsync(tester, const Duration(milliseconds: 700));

        mockTime = mockTime.add(const Duration(hours: 2, minutes: 1));
        await tester.runAsync(safety.check);
        await settleAsync(tester);

        expect(
          find.byKey(const Key('safety-prompt-longRecording')),
          findsOneWidget,
        );
        expect(find.textContaining("Still in 'Keynote'?"), findsOneWidget);

        await tester.tap(find.byKey(const Key('safety-prompt-keep')));
        await settleAsync(tester);
        expect(
          find.byKey(const Key('safety-prompt-longRecording')),
          findsNothing,
        );
        expect(recordingService.status.state, RecordingState.recording);
        await disposeService(tester);
      },
    );

    testWidgets(
      'FR-REC-06 after 10 minutes of silence the user can stop and save',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Breakout');
        final safety = safetyFor(-80);
        addTearDown(safety.dispose);

        await tester.pumpWidget(
          buildSubject(activityId: act.id, tester: tester, safety: safety),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('record-button-start')));
        await settleAsync(tester, const Duration(milliseconds: 700));

        mockTime = mockTime.add(const Duration(minutes: 10, seconds: 5));
        await tester.runAsync(safety.check);
        await settleAsync(tester);

        expect(
          find.text('No sound detected. Still in the session?'),
          findsOneWidget,
        );
        expect(recordingService.status.state, RecordingState.recording);

        await tester.tap(find.byKey(const Key('safety-prompt-stop')));
        await settleAsync(tester, const Duration(milliseconds: 700));
        expect(recordingService.status.state, RecordingState.saved);
        await disposeService(tester);
      },
    );
  });
}
