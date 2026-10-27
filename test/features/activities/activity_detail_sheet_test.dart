import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/activity_detail_sheet.dart';
import 'package:drift/drift.dart' show Value;
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

  Widget buildSubject({
    required Widget child,
    required WidgetTester tester,
    RecordingStatus? status,
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
        capturePlatformProvider.overrideWithValue(CapturePlatform.android),
        mediaFreeBytesProvider.overrideWith((ref) async => null),
        if (status != null)
          recordingStatusProvider.overrideWith((ref) => Stream.value(status)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  group('FR-ACT-04 & FR-ACT-08 ActivityDetailSheet', () {
    testWidgets(
      'FR-ACT-08 displays contact details and follow-up card when present',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activities.create(
          conferenceId: conf.id,
          typeId: builtinTypeId('business_conversation'),
          title: 'Networking chat with Alex',
          contactName: 'Alex Rivera',
          contactDetails: 'alex@example.org',
          followUpText: 'Follow up on collaborative research project',
          recordingPermissionStatus: RecordingPermissionStatus.participantAware,
        );

        final summary = (await t.activities.getSummary(act.id))!;

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Scaffold(
              body: ActivityDetailSheet(
                summary: summary,
                timezone: 'Europe/London',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Contact card is displayed
        expect(find.byKey(const Key('activity-contact-card')), findsOneWidget);
        expect(find.byKey(const Key('detail-contact-name')), findsOneWidget);
        expect(find.text('Alex Rivera'), findsOneWidget);
        expect(find.byKey(const Key('detail-contact-details')), findsOneWidget);
        expect(find.text('alex@example.org'), findsOneWidget);
        expect(find.byKey(const Key('detail-follow-up')), findsOneWidget);
        expect(
          find.text('Follow up on collaborative research project'),
          findsOneWidget,
        );

        // Permission status is displayed
        expect(find.text('Participant aware'), findsOneWidget);
      },
    );

    testWidgets(
      'FR-ACT-04 tapping Edit opens ActivityEditorScreen and updates details',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activities.create(
          conferenceId: conf.id,
          typeId: builtinTypeId('session'),
          title: 'Initial Title',
          room: 'Hall 1',
        );

        final summary = (await t.activities.getSummary(act.id))!;

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Scaffold(
              body: ActivityDetailSheet(
                summary: summary,
                timezone: 'Europe/London',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('activity-detail-title')), findsOneWidget);
        expect(find.text('Initial Title'), findsOneWidget);

        // Tap Edit
        await tester.tap(find.byKey(const Key('activity-detail-edit-button')));
        await tester.pumpAndSettle();

        // Should now be on ActivityEditorScreen
        expect(find.text('Edit activity'), findsOneWidget);

        // Change title
        await tester.enterText(
          find.byKey(const Key('activity-title-field')),
          'Updated Title After Edit',
        );

        // Save
        await tester.tap(find.byKey(const Key('save-activity-button')));
        await tester.pumpAndSettle();

        // Returned to ActivityDetailSheet with refreshed title
        expect(find.text('Updated Title After Edit'), findsOneWidget);
      },
    );

    testWidgets(
      'FR-ACT-04 delete button in details sheet confirms and deletes activity',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activities.create(
          conferenceId: conf.id,
          typeId: builtinTypeId('session'),
          title: 'Activity To Remove',
        );

        final summary = (await t.activities.getSummary(act.id))!;

        dynamic popResult;
        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  popResult = await ActivityDetailSheet.show(
                    context,
                    summary: summary,
                    timezone: 'Europe/London',
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Activity To Remove'), findsOneWidget);

        // Tap Delete in detail sheet
        await tester.tap(
          find.byKey(const Key('activity-detail-delete-button')),
        );
        await tester.pumpAndSettle();

        // Confirmation dialog
        expect(find.text('Delete "Activity To Remove"?'), findsOneWidget);
        await tester.tap(find.text('Delete permanently'));
        await tester.pumpAndSettle();

        // Sheet popped with deleted true
        expect(popResult, {'deleted': true});

        // Verify in DB
        expect(await t.activities.get(act.id), isNull);
      },
    );
  });

  group('FR-UI-08 quality selector on the activity sheet [P1-09]', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      String activityId, {
      RecordingStatus? status,
    }) async {
      final summary = (await t.activities.getSummary(activityId))!;
      await tester.pumpWidget(
        buildSubject(
          tester: tester,
          status: status,
          child: Scaffold(
            body: ActivityDetailSheet(
              summary: summary,
              timezone: 'Europe/London',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('FR-UI-08 FR-QUAL-02 before recording, picking a profile '
        'stores the activity override', (tester) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await pumpSheet(tester, act.id);

      expect(
        find.byKey(const Key('recording-profile-selector')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('profile-option-enhanced')),
      );
      await tester.tap(find.byKey(const Key('profile-option-enhanced')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      final stored = await tester.runAsync(() => t.activities.get(act.id));
      expect(stored!.recordingProfileOverride, RecordingProfile.enhanced);
    });

    testWidgets('FR-UI-08 hidden once recorded; the profile row stays', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await t.segment(
        act.id,
        start: t.clock.now,
        length: const Duration(minutes: 2),
      );
      await t.activities.update(
        act.id,
        const ActivitiesCompanion(status: Value(ActivityStatus.completed)),
      );
      await pumpSheet(tester, act.id);

      expect(find.byKey(const Key('recording-profile-selector')), findsNothing);
      expect(find.text('Recording profile'), findsOneWidget);
    });

    testWidgets('FR-UI-08 while recording, shows the profile in use', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await t.activities.update(
        act.id,
        const ActivitiesCompanion(status: Value(ActivityStatus.active)),
      );
      await pumpSheet(
        tester,
        act.id,
        status: RecordingStatus(
          state: RecordingState.recording,
          activityId: act.id,
          profile: RecordingProfile.economy,
        ),
      );

      expect(find.text('Recording quality: Economy'), findsOneWidget);
    });
  });
}
