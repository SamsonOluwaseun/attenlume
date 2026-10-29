import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_banner.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/privacy/app_lock_controller.dart';
import 'package:attenlume/features/privacy/privacy_screen.dart';
import 'package:attenlume/features/privacy/recording_privacy_check.dart';
import 'package:attenlume/features/privacy/sensitive_export_warning.dart';
import 'package:attenlume/platform/device_auth/device_authenticator.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_device_authenticator.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late FakeDeviceAuthenticator auth;

  setUp(() {
    t = TestData();
    auth = FakeDeviceAuthenticator();
  });

  tearDown(() => t.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app(Widget home, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(t.db),
          settingsRepositoryProvider.overrideWithValue(t.settings),
          conferenceRepositoryProvider.overrideWithValue(t.conferences),
          activityRepositoryProvider.overrideWithValue(t.activities),
          deviceAuthenticatorProvider.overrideWithValue(auth),
          ...overrides,
        ],
        child: MaterialApp(home: home),
      );

  group('FR-PRI-03 FR-PRI-04 FR-PRI-06 Privacy screen', () {
    testWidgets('FR-PRI-03 Privacy opens from the conference list menu through Settings and '
        'says data stays on the device with no trackers', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const ConferenceListScreen(),
          overrides: [
            recordingStatusProvider.overrideWith(
              (ref) => Stream.value(RecordingStatus.idle),
            ),
          ],
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('conference-list-menu')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('menu-settings')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-privacy')));
      await settle(tester);

      expect(find.byType(PrivacyScreen), findsOneWidget);
      expect(find.text(PrivacyScreen.onDevicePromises.first), findsOneWidget);
      expect(
        find.text('No analytics, no adverts and no trackers.'),
        findsOneWidget,
      );
    });

    testWidgets('FR-PRI-04 every permission is listed with when it is asked '
        'and a plain reason', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const PrivacyScreen()));
      await settle(tester);

      for (final p in PrivacyScreen.permissions) {
        expect(find.text(p.name), findsOneWidget);
        expect(p.whenAsked, matches(RegExp(r'^(The first time|Only if)')));
        expect(p.why.length, greaterThan(20));
      }
      expect(find.textContaining('UK GDPR'), findsOneWidget);
    });

    testWidgets('FR-PRI-06 the switch is off by default and turns the lock on '
        'after the OS prompt', (tester) async {
      await tester.pumpWidget(app(const PrivacyScreen()));
      await settle(tester);

      final switchFinder = find.byKey(const Key('app-lock-switch'));
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
      expect(find.byKey(const Key('app-lock-grace')), findsNothing);

      await tester.tap(switchFinder);
      await settle(tester);

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(find.text('App lock is on.'), findsOneWidget);
      expect(auth.reasons, [AppLockController.enableReason]);
      expect(find.byKey(const Key('app-lock-grace')), findsOneWidget);
      expect(find.text('After 1 minute'), findsOneWidget);
      late bool stored;
      await tester.runAsync(
        () async => stored = await t.settings.appLockEnabled(),
      );
      expect(stored, isTrue);
    });

    testWidgets('FR-PRI-06 without a PIN or biometrics the lock stays off and '
        'the screen says why', (tester) async {
      auth.availabilityResult = DeviceAuthAvailability.notSetUp;
      await tester.pumpWidget(app(const PrivacyScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('app-lock-switch')));
      await settle(tester);

      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('app-lock-switch')))
            .value,
        isFalse,
      );
      expect(find.textContaining('Set one up in your device'), findsOneWidget);
    });
  });

  group('FR-PRI-01 privacy checks before recording', () {
    Widget harness() => app(const Scaffold(body: Text('noop')));

    /// Starts the check from a real context and returns its result once
    /// the test has answered the prompts.
    Future<RecordingPrivacyCheck> Function() startCheck(
      WidgetTester tester,
      String activityId,
    ) {
      final context = tester.element(find.text('noop'));
      final pending = checkRecordingPrivacy(
        context,
        conferences: t.conferences,
        activities: t.activities,
        activityId: activityId,
      );
      return () async {
        late RecordingPrivacyCheck result;
        await tester.runAsync(() async => result = await pending);
        return result;
      };
    }

    testWidgets('FR-PRI-01 the policy reminder shows before the first '
        'recording when the conference never acknowledged it', (tester) async {
      late String activityId;
      late String conferenceId;
      await tester.runAsync(() async {
        final conf = await t.conference();
        conferenceId = conf.id;
        activityId = (await t.activity(conf.id)).id;
      });
      await tester.pumpWidget(harness());
      await settle(tester);

      final result = startCheck(tester, activityId);
      await settle(tester);
      expect(find.byKey(const Key('policy-reminder-dialog')), findsOneWidget);
      expect(
        find.text(
          'Some events and speakers do not allow recording. Record only '
          'when permitted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('policy-reminder-acknowledge')));
      await settle(tester);
      expect(await result(), RecordingPrivacyCheck.proceed);

      late DateTime? acknowledged;
      await tester.runAsync(() async {
        acknowledged = (await t.conferences.get(conferenceId))!
            .policyAcknowledgedAt;
      });
      expect(acknowledged, isNotNull);

      // Only once per conference.
      final again = startCheck(tester, activityId);
      await settle(tester);
      expect(find.byKey(const Key('policy-reminder-dialog')), findsNothing);
      expect(await again(), RecordingPrivacyCheck.proceed);
    });

    testWidgets('FR-PRI-01 "Not now" holds the recording back and records '
        'nothing', (tester) async {
      late String activityId;
      await tester.runAsync(() async {
        final conf = await t.conference();
        activityId = (await t.activity(conf.id)).id;
      });
      await tester.pumpWidget(harness());
      await settle(tester);

      final result = startCheck(tester, activityId);
      await settle(tester);
      await tester.tap(find.byKey(const Key('policy-reminder-cancel')));
      await settle(tester);
      expect(await result(), RecordingPrivacyCheck.cancelled);
    });

    testWidgets('FR-PRI-01 FR-ACT-07 a conversation that was never checked '
        'asks whether the other person knows', (tester) async {
      late String activityId;
      await tester.runAsync(() async {
        final conf = await t.conference(policyAcknowledged: true);
        activityId = (await t.activity(
          conf.id,
          typeKey: 'business_conversation',
        )).id;
      });
      await tester.pumpWidget(harness());
      await settle(tester);

      final result = startCheck(tester, activityId);
      await settle(tester);
      expect(find.byKey(const Key('consent-check-dialog')), findsOneWidget);
      await tester.tap(find.text('Not recording audio'));
      await settle(tester);
      expect(await result(), RecordingPrivacyCheck.notRecordingAudio);

      late RecordingPermissionStatus stored;
      await tester.runAsync(() async {
        stored = (await t.activities.get(activityId))!
            .recordingPermissionStatus;
      });
      expect(stored, RecordingPermissionStatus.notPermitted);
    });

    testWidgets('FR-PRI-01 an answered conversation and a talk need no '
        'prompt', (tester) async {
      late String conversationId;
      late String talkId;
      await tester.runAsync(() async {
        final conf = await t.conference(policyAcknowledged: true);
        conversationId = (await t.activity(
          conf.id,
          typeKey: 'business_conversation',
        )).id;
        await t.activities.update(
          conversationId,
          const ActivitiesCompanion(
            recordingPermissionStatus: Value(
              RecordingPermissionStatus.participantAware,
            ),
          ),
        );
        talkId = (await t.activity(conf.id)).id;
      });
      await tester.pumpWidget(harness());
      await settle(tester);

      for (final id in [conversationId, talkId]) {
        final result = startCheck(tester, id);
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(await result(), RecordingPrivacyCheck.proceed);
      }
    });
  });

  group('FR-PRI-02 recording banner', () {
    Widget banner(RecordingStatus status) => app(
      const Scaffold(body: WithRecordingBanner(child: Text('Conferences'))),
      overrides: [
        recordingStatusProvider.overrideWith((ref) => Stream.value(status)),
      ],
    );

    testWidgets('FR-PRI-02 a held recording shows a banner with Stop on '
        'other screens', (tester) async {
      await tester.pumpWidget(
        banner(
          const RecordingStatus(
            state: RecordingState.recording,
            activityId: 'a1',
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('recording-banner')), findsOneWidget);
      expect(find.text('Recording'), findsOneWidget);
      expect(find.byKey(const Key('recording-banner-stop')), findsOneWidget);
      expect(find.byKey(const Key('recording-banner-open')), findsOneWidget);
    });

    testWidgets('FR-PRI-02 paused still shows, saved and idle do not', (
      tester,
    ) async {
      await tester.pumpWidget(
        banner(
          const RecordingStatus(state: RecordingState.paused, activityId: 'a1'),
        ),
      );
      await settle(tester);
      expect(find.text('Recording paused'), findsOneWidget);

      for (final state in [RecordingState.saved, RecordingState.idle]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          banner(RecordingStatus(state: state, activityId: 'a1')),
        );
        await settle(tester);
        expect(find.byKey(const Key('recording-banner')), findsNothing);
      }
    });
  });

  group('FR-PRI-05 warning before export or upload', () {
    testWidgets('FR-PRI-05 lists the sensitive kinds and the person\'s own '
        'obligations, and continues only on Continue', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answer = await SensitiveExportWarning.show(context),
              child: const Text('Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      for (final kind in SensitiveExportWarning.sensitiveKinds) {
        expect(find.text(kind), findsOneWidget);
      }
      expect(find.textContaining('identified'), findsOneWidget);
      expect(find.textContaining('Unpublished research'), findsOneWidget);
      expect(find.textContaining('Medical or financial'), findsOneWidget);
      expect(find.textContaining('UK GDPR'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sensitive-export-cancel')));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('sensitive-export-continue')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sensitive-export-continue')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    test('FR-PRI-05 the app never claims to make sharing legal or '
        'compliant', () {
      final texts = [
        SensitiveExportWarning.obligationsNote,
        ...SensitiveExportWarning.sensitiveKinds,
        ...PrivacyScreen.onDevicePromises,
      ].join(' ').toLowerCase();
      for (final claim in [
        'compliant',
        'compliance',
        'gdpr-ready',
        'legal advice',
        'guarantee',
      ]) {
        expect(texts, isNot(contains(claim)));
      }
      expect(
        SensitiveExportWarning.obligationsNote,
        contains('does not replace your own legal obligations'),
      );
    });
  });

  group('FR-PRI-03 FR-PRI-06 project configuration', () {
    test('FR-PRI-03 no analytics, advert or tracking package is in the '
        'build', () {
      final lock = File('pubspec.lock').readAsStringSync().toLowerCase();
      const banned = [
        'firebase_analytics',
        'firebase_crashlytics',
        'sentry',
        'google_mobile_ads',
        'facebook',
        'appsflyer',
        'amplitude',
        'mixpanel',
        'segment_analytics',
        'datadog',
        'posthog',
        'adjust_sdk',
        'app_tracking_transparency',
      ];
      for (final name in banned) {
        expect(lock, isNot(contains(name)), reason: name);
      }
    });

    test('FR-PRI-03 the Android release manifest asks for no internet '
        'access', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, isNot(contains('android.permission.INTERNET')));
      expect(manifest, isNot(contains('AD_ID')));
    });

    test('FR-PRI-06 the platforms are set up for the OS prompt', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android.permission.USE_BIOMETRIC'));
      final activity = File(
        'android/app/src/main/kotlin/com/samlytics/attenlume/MainActivity.kt',
      ).readAsStringSync();
      expect(
        activity,
        contains('class MainActivity : FlutterFragmentActivity()'),
      );
      for (final channel in [
        'ShortcutChannel.attach',
        'ForegroundServiceChannel.attach',
        'FreeSpaceChannel.attach',
        'BatteryChannel.attach',
      ]) {
        expect(activity, contains(channel));
      }
      for (final styles in [
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
      ]) {
        final text = File(styles).readAsStringSync();
        expect(
          RegExp('name="LaunchTheme" parent="Theme.AppCompat').hasMatch(text),
          isTrue,
          reason: styles,
        );
      }
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<key>NSFaceIDUsageDescription</key>'));
    });
  });
}
