import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/activities/consent_check_dialog.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() {
    t = TestData();
  });

  tearDown(() async {
    await t.close();
  });

  Widget buildSubject({required Widget child, required WidgetTester tester}) {
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
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  group('FR-ACT-07 consent check dialog', () {
    testWidgets(
      'FR-ACT-07 shows prompt wording and options: Yes and Not recording audio',
      (tester) async {
        RecordingPermissionStatus? result;

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ConsentCheckDialog.show(context);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('consent-check-dialog')), findsOneWidget);
        expect(
          find.text('Does the other person know you are recording?'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('consent-check-yes')), findsOneWidget);
        expect(find.byKey(const Key('consent-check-no-audio')), findsOneWidget);
        expect(find.byKey(const Key('consent-check-cancel')), findsOneWidget);

        // Tapping Yes returns participantAware
        await tester.tap(find.byKey(const Key('consent-check-yes')));
        await tester.pumpAndSettle();

        expect(result, RecordingPermissionStatus.participantAware);
      },
    );

    testWidgets('FR-ACT-07 tapping Not recording audio returns notPermitted', (
      tester,
    ) async {
      RecordingPermissionStatus? result;

      await tester.pumpWidget(
        buildSubject(
          tester: tester,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ConsentCheckDialog.show(context);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('consent-check-no-audio')));
      await tester.pumpAndSettle();

      expect(result, RecordingPermissionStatus.notPermitted);
    });

    testWidgets('FR-ACT-07 tapping Cancel returns null without selection', (
      tester,
    ) async {
      RecordingPermissionStatus? result = RecordingPermissionStatus.unknown;

      await tester.pumpWidget(
        buildSubject(
          tester: tester,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ConsentCheckDialog.show(context);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('consent-check-cancel')));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  group('FR-ACT-07 & FR-PRI-01 quick-start conversation awareness check', () {
    testWidgets(
      'FR-ACT-07 quick-start Conversation shows consent check and records participantAware on Yes',
      (tester) async {
        final conf = await t.conference();

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: ConferenceHomeScreen(
              conferenceId: conf.id,
              openRecorder: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Conversation quick-start button
        await tester.tap(find.byKey(const Key('quick-start-conversation')));
        await tester.pumpAndSettle();

        // Consent check dialog should be visible
        expect(find.byKey(const Key('consent-check-dialog')), findsOneWidget);

        // Tap Yes
        await tester.tap(find.byKey(const Key('consent-check-yes')));
        await tester.pumpAndSettle();

        // Activity should be created with participantAware status
        final activities = await t.activities.listForConference(conf.id);
        expect(activities, hasLength(1));
        expect(
          activities.first.recordingPermissionStatus,
          RecordingPermissionStatus.participantAware,
        );
      },
    );

    testWidgets(
      'FR-ACT-07 quick-start Conversation records notPermitted on Not recording audio',
      (tester) async {
        final conf = await t.conference();

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: ConferenceHomeScreen(
              conferenceId: conf.id,
              openRecorder: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('quick-start-conversation')));
        await tester.pumpAndSettle();

        // Tap Not recording audio
        await tester.tap(find.byKey(const Key('consent-check-no-audio')));
        await tester.pumpAndSettle();

        final activities = await t.activities.listForConference(conf.id);
        expect(activities, hasLength(1));
        expect(
          activities.first.recordingPermissionStatus,
          RecordingPermissionStatus.notPermitted,
        );
      },
    );

    testWidgets(
      'FR-ACT-07 cancelling consent check does not create an activity',
      (tester) async {
        final conf = await t.conference();

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: ConferenceHomeScreen(
              conferenceId: conf.id,
              openRecorder: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('quick-start-conversation')));
        await tester.pumpAndSettle();

        // Cancel
        await tester.tap(find.byKey(const Key('consent-check-cancel')));
        await tester.pumpAndSettle();

        final activities = await t.activities.listForConference(conf.id);
        expect(activities, isEmpty);
      },
    );

    testWidgets(
      'FR-ACT-07 start activity sheet shows consent check when choosing Conversation',
      (tester) async {
        final conf = await t.conference();

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: StartActivitySheet(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Conversation chip
        await tester.tap(
          find.byKey(const Key('activity-type-chip-business_conversation')),
        );
        await tester.pumpAndSettle();

        // Consent check dialog appears
        expect(find.byKey(const Key('consent-check-dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('consent-check-yes')));
        await tester.pumpAndSettle();

        final activities = await t.activities.listForConference(conf.id);
        expect(activities, hasLength(1));
        expect(
          activities.first.recordingPermissionStatus,
          RecordingPermissionStatus.participantAware,
        );
      },
    );
  });
}
