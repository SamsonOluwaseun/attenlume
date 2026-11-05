import 'dart:io';

import 'package:attenlume/app/app.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/crash_recovery_service.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/capture/recording_screen.dart';
import 'package:attenlume/features/conferences/conference_wizard_screen.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
import 'package:attenlume/features/shortcuts/shortcut_coordinator.dart';
import 'package:attenlume/features/shortcuts/shortcut_providers.dart';
import 'package:attenlume/platform/shortcuts/shortcut_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_shortcut_bridge.dart';
import '../../fixtures/fake_timers.dart';
import '../../fixtures/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestData t;
  late Directory tempDir;
  late FakeCaptureEngine fakeEngine;
  late RecordingService recordingService;
  late FakeShortcutBridge fakeBridge;
  final navKey = GlobalKey<NavigatorState>();

  setUp(() async {
    t = TestData();
    tempDir = await Directory.systemTemp.createTemp('shortcut_coord_test_');
    fakeEngine = FakeCaptureEngine()..level = -20.0;
    fakeBridge = FakeShortcutBridge();

    recordingService = RecordingService(
      engine: fakeEngine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => tempDir,
      platform: CapturePlatform.android,
      clock: () => DateTime.utc(2026, 11, 4, 9, 30),
      rollTimer: FakeTimers().call,
      hashFile: (_) async => 'hash',
    );
  });

  tearDown(() async {
    await recordingService.dispose();
    await fakeBridge.close();
    await t.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('P2-03 ShortcutCoordinator routing', () {
    test(
      'P2-03 coalesces concurrent starts through pending screen outcome',
      () async {
        final conf = await t.conference();
        final screens = <RecordingScreen>[];
        final coordinator = ShortcutCoordinator(
          navigatorKey: navKey,
          conferenceRepository: t.conferences,
          activityRepository: t.activities,
          mediaRepository: t.media,
          recordingService: recordingService,
          onNavigate: (screen) => screens.add(screen as RecordingScreen),
        );
        final command = ShortcutCommand.parse(Uri.parse('attenlume://record'))!;
        await Future.wait(
          List.generate(5, (_) => coordinator.handleCommand(command)),
        );
        expect(screens, hasLength(1));
        // Repository queries finished, but screen loading/privacy is still pending.
        await coordinator.handleCommand(command);
        expect(screens, hasLength(1));
        expect(
          await t.activities.listSummariesForConference(conf.id),
          hasLength(1),
        );

        // Cancellation permits a later attempt; a stale callback cannot release it.
        screens.first.onAutoStartComplete!();
        await coordinator.handleCommand(command);
        expect(screens, hasLength(2));
        screens.first.onAutoStartComplete!();
        await coordinator.handleCommand(command);
        expect(screens, hasLength(2));
        screens.last.onAutoStartComplete!();
        await recordingService.start(screens.last.activityId);
        await coordinator.handleCommand(command);
        expect(screens.last.activityId, screens[1].activityId);
        expect(
          await t.activities.listSummariesForConference(conf.id),
          hasLength(2),
        );
      },
    );

    test(
      'P2-03 startRecording with no conference opens ConferenceWizardScreen',
      () async {
        Widget? navigatedScreen;
        final coordinator = ShortcutCoordinator(
          navigatorKey: navKey,
          conferenceRepository: t.conferences,
          activityRepository: t.activities,
          mediaRepository: t.media,
          recordingService: recordingService,
          onNavigate: (s) => navigatedScreen = s,
        );

        final cmd = ShortcutCommand.parse(
          Uri.parse('attenlume://record/start?source=app_shortcut'),
        )!;
        await coordinator.handleCommand(cmd);

        expect(navigatedScreen, isA<ConferenceWizardScreen>());
      },
    );

    test('P2-03 startRecording with existing conference creates activity in most recent conference and opens RecordingScreen with autoStart', () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      Widget? navigatedScreen;
      final coordinator = ShortcutCoordinator(
        navigatorKey: navKey,
        conferenceRepository: t.conferences,
        activityRepository: t.activities,
        mediaRepository: t.media,
        recordingService: recordingService,
        onNavigate: (s) => navigatedScreen = s,
      );

      final cmd = ShortcutCommand.parse(
        Uri.parse('attenlume://record?source=tile'),
      )!;
      await coordinator.handleCommand(cmd);

      expect(navigatedScreen, isA<RecordingScreen>());
      final screen = navigatedScreen as RecordingScreen;
      expect(screen.autoStart, isTrue);

      // Verify the created activity belongs to the most recent conference
      final activity = await t.activities.get(screen.activityId);
      expect(activity, isNotNull);
      expect(activity!.conferenceId, conf.id);
    });

    test('P2-03 startRecording when recording already running opens held RecordingScreen with autoStart false', () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      final act = await t.activity(conf.id, title: 'Keynote');
      await recordingService.start(act.id);
      expect(recordingService.status.state.holdsActivity, isTrue);

      Widget? navigatedScreen;
      final coordinator = ShortcutCoordinator(
        navigatorKey: navKey,
        conferenceRepository: t.conferences,
        activityRepository: t.activities,
        mediaRepository: t.media,
        recordingService: recordingService,
        onNavigate: (s) => navigatedScreen = s,
      );

      final cmd = ShortcutCommand.parse(
        Uri.parse('attenlume://record/toggle?source=tile'),
      )!;
      await coordinator.handleCommand(cmd);

      expect(navigatedScreen, isA<RecordingScreen>());
      final screen = navigatedScreen as RecordingScreen;
      expect(screen.activityId, act.id);
      expect(screen.autoStart, isFalse);
    });

    test('P2-03 startRecording with explicit activityId opens RecordingScreen for that activity', () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      final act = await t.activity(conf.id, title: 'Workshop');

      Widget? navigatedScreen;
      final coordinator = ShortcutCoordinator(
        navigatorKey: navKey,
        conferenceRepository: t.conferences,
        activityRepository: t.activities,
        mediaRepository: t.media,
        recordingService: recordingService,
        onNavigate: (s) => navigatedScreen = s,
      );

      final cmd = ShortcutCommand.parse(
        Uri.parse('attenlume://record/start?activity=${act.id}'),
      )!;
      await coordinator.handleCommand(cmd);

      expect(navigatedScreen, isA<RecordingScreen>());
      final screen = navigatedScreen as RecordingScreen;
      expect(screen.activityId, act.id);
      expect(screen.autoStart, isTrue);
    });

    test('P2-03 stopRecording when recording active stops recorder and opens RecordingScreen', () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      final act = await t.activity(conf.id, title: 'Session 1');
      await recordingService.start(act.id);
      expect(recordingService.status.state.holdsActivity, isTrue);

      Widget? navigatedScreen;
      final coordinator = ShortcutCoordinator(
        navigatorKey: navKey,
        conferenceRepository: t.conferences,
        activityRepository: t.activities,
        mediaRepository: t.media,
        recordingService: recordingService,
        onNavigate: (s) => navigatedScreen = s,
      );

      final cmd = ShortcutCommand.parse(
        Uri.parse('attenlume://record/stop?source=app_shortcut'),
      )!;
      await coordinator.handleCommand(cmd);

      expect(recordingService.status.state.holdsActivity, isFalse);
      expect(navigatedScreen, isA<RecordingScreen>());
      final screen = navigatedScreen as RecordingScreen;
      expect(screen.activityId, act.id);
    });

    test('P2-03 bookmark when recording active inserts bookmark with source shortcut', () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      final act = await t.activity(conf.id, title: 'Session 1');
      await recordingService.start(act.id);

      final coordinator = ShortcutCoordinator(
        navigatorKey: navKey,
        conferenceRepository: t.conferences,
        activityRepository: t.activities,
        mediaRepository: t.media,
        recordingService: recordingService,
      );

      final cmd = ShortcutCommand.parse(
        Uri.parse('attenlume://bookmark?source=app_shortcut'),
      )!;
      await coordinator.handleCommand(cmd);

      final bookmarks = await t.media.bookmarksFor(act.id);
      expect(bookmarks.length, 1);
      expect(bookmarks.first.source, BookmarkSource.shortcut);
    });

    test('P2-03 newConversation creates conversation activity in most recent conference', () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      Widget? navigatedScreen;
      final coordinator = ShortcutCoordinator(
        navigatorKey: navKey,
        conferenceRepository: t.conferences,
        activityRepository: t.activities,
        mediaRepository: t.media,
        recordingService: recordingService,
        onNavigate: (s) => navigatedScreen = s,
      );

      final cmd = ShortcutCommand.parse(
        Uri.parse('attenlume://conversation/new'),
      )!;
      await coordinator.handleCommand(cmd);

      expect(navigatedScreen, isA<RecordingScreen>());
      final screen = navigatedScreen as RecordingScreen;
      expect(screen.autoStart, isTrue);

      final activity = await t.activities.get(screen.activityId);
      expect(activity, isNotNull);
      expect(activity!.conferenceId, conf.id);
      final types = await t.activities.types();
      final convType = types.firstWhere(
        (t) => t.key == 'business_conversation',
      );
      expect(activity.typeId, convType.id);
    });
  });

  group('P2-03 AttenlumeApp end-to-end shortcut processing', () {
    testWidgets(
      'P2-03 pending start coalesces repeated taps during privacy prompt and releases on cancellation',
      (tester) async {
        final conf = await t.conference();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(t.db),
              shortcutBridgeProvider.overrideWithValue(fakeBridge),
              crashRecoveryReportProvider.overrideWith(
                (ref) async => RecoveryReport.empty,
              ),
            ],
            child: const AttenlumeApp(),
          ),
        );
        await tester.pumpAndSettle();
        final command = ShortcutCommand.parse(Uri.parse('attenlume://record'))!;
        fakeBridge.send(command);
        fakeBridge.send(command);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('policy-reminder-dialog')), findsOneWidget);
        fakeBridge.send(command);
        await tester.pumpAndSettle();
        expect(
          find.byType(RecordingScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          await t.activities.listSummariesForConference(conf.id),
          hasLength(1),
        );

        await tester.tap(find.byKey(const Key('policy-reminder-cancel')));
        await tester.pumpAndSettle();
        fakeBridge.send(command);
        await tester.pumpAndSettle();
        expect(
          await t.activities.listSummariesForConference(conf.id),
          hasLength(2),
        );
        expect(find.byKey(const Key('policy-reminder-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('policy-reminder-cancel')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'P2-03 cold start with initial shortcut command opens ConferenceWizardScreen when no conference exists',
      (tester) async {
        fakeBridge.initial = ShortcutCommand.parse(
          Uri.parse('attenlume://record?source=tile'),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(t.db),
              shortcutBridgeProvider.overrideWithValue(fakeBridge),
              crashRecoveryReportProvider.overrideWith(
                (ref) async => RecoveryReport.empty,
              ),
            ],
            child: const AttenlumeApp(),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(ConferenceWizardScreen), findsOneWidget);
      },
    );

    testWidgets('P2-03 warm trigger delivers shortcut command to running app', (
      tester,
    ) async {
      await t.conference(name: 'Samlytics Conference 2026');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(t.db),
            shortcutBridgeProvider.overrideWithValue(fakeBridge),
            crashRecoveryReportProvider.overrideWith(
              (ref) async => RecoveryReport.empty,
            ),
          ],
          child: const AttenlumeApp(),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);

      // Send warm trigger via shortcut stream
      fakeBridge.send(
        ShortcutCommand.parse(
          Uri.parse('attenlume://record/start?source=assistant'),
        )!,
      );

      await tester.pumpAndSettle();
      expect(find.byType(RecordingScreen), findsOneWidget);
    });

    testWidgets('P2-03 repeated trigger for the same recording does not stack '
        'a second screen', (tester) async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      final act = await t.activity(conf.id, title: 'Keynote');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(t.db),
            shortcutBridgeProvider.overrideWithValue(fakeBridge),
            crashRecoveryReportProvider.overrideWith(
              (ref) async => RecoveryReport.empty,
            ),
          ],
          child: const AttenlumeApp(),
        ),
      );
      await tester.pumpAndSettle();

      final link = Uri.parse('attenlume://record/start?activity=${act.id}');
      fakeBridge.send(ShortcutCommand.parse(link)!);
      await tester.pumpAndSettle();
      fakeBridge.send(ShortcutCommand.parse(link)!);
      await tester.pumpAndSettle();

      expect(find.byType(RecordingScreen, skipOffstage: false), findsOneWidget);
    });
  });
}
