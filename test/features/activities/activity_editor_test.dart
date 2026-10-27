import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/activities/activity_editor_screen.dart';
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

  group('FR-ACT-04 & FR-ACT-05 Activity editor CRUD', () {
    testWidgets(
      'FR-ACT-04 creates a new activity with all session details populated',
      (tester) async {
        final conf = await t.conference();

        Activity? savedActivity;
        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  savedActivity = await Navigator.of(context).push<Activity>(
                    MaterialPageRoute(
                      builder: (context) =>
                          ActivityEditorScreen(conferenceId: conf.id),
                    ),
                  );
                },
                child: const Text('Open Editor'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Editor'));
        await tester.pumpAndSettle();

        expect(find.text('New activity'), findsOneWidget);

        // Enter Title
        await tester.enterText(
          find.byKey(const Key('activity-title-field')),
          'Data Architecture Keynote',
        );

        // Enter Speakers
        await tester.enterText(
          find.byKey(const Key('activity-speakers-field')),
          'Dr Ada Example, Sam Sample',
        );

        // Enter Organisation and Room
        await tester.enterText(
          find.byKey(const Key('activity-organisation-field')),
          'UK Health Security Agency',
        );
        await tester.enterText(
          find.byKey(const Key('activity-room-field')),
          'Hall B',
        );

        // Select Profile Override: Enhanced
        await tester.tap(
          find.byKey(const Key('activity-profile-override-dropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Enhanced').last);
        await tester.pumpAndSettle();

        // Toggle Private
        await tester.tap(find.byKey(const Key('activity-privacy-switch')));
        await tester.pumpAndSettle();

        // Notes and Tags
        await tester.enterText(
          find.byKey(const Key('activity-notes-field')),
          '# Keynote takeaways\n- Focus on data quality\n- Decentralised mesh',
        );
        await tester.enterText(
          find.byKey(const Key('activity-tags-field')),
          'data-mesh, architecture, keynote',
        );

        // Save
        await tester.tap(find.byKey(const Key('save-activity-button')));
        await tester.pumpAndSettle();

        expect(savedActivity, isNotNull);
        expect(savedActivity!.title, 'Data Architecture Keynote');
        expect(savedActivity!.speakerNames, ['Dr Ada Example', 'Sam Sample']);
        expect(savedActivity!.organisation, 'UK Health Security Agency');
        expect(savedActivity!.room, 'Hall B');
        expect(
          savedActivity!.recordingProfileOverride,
          RecordingProfile.enhanced,
        );
        expect(savedActivity!.isPrivate, isTrue);
        expect(
          savedActivity!.notesMd,
          '# Keynote takeaways\n- Focus on data quality\n- Decentralised mesh',
        );
        expect(savedActivity!.tags, ['data-mesh', 'architecture', 'keynote']);

        // Verify in DB
        final inDb = (await t.activities.get(savedActivity!.id))!;
        expect(inDb.title, 'Data Architecture Keynote');
        expect(inDb.room, 'Hall B');
      },
    );

    testWidgets(
      'FR-ACT-05 blank title generates default title: {Type} {n}, {HH:mm}',
      (tester) async {
        final conf = await t.conference(timezone: 'Europe/London');
        t.clock.set(DateTime.utc(2026, 11, 4, 14, 5)); // 14:05

        Activity? savedActivity;
        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  savedActivity = await Navigator.of(context).push<Activity>(
                    MaterialPageRoute(
                      builder: (context) =>
                          ActivityEditorScreen(conferenceId: conf.id),
                    ),
                  );
                },
                child: const Text('Open Editor'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Editor'));
        await tester.pumpAndSettle();

        // Leave title blank and save directly
        await tester.tap(find.byKey(const Key('save-activity-button')));
        await tester.pumpAndSettle();

        expect(savedActivity, isNotNull);
        expect(savedActivity!.title, 'Session 1, 14:05');
      },
    );

    testWidgets(
      'FR-ACT-05 editing existing activity renames it and preserves other fields',
      (tester) async {
        final conf = await t.conference();
        final a = await t.activities.create(
          conferenceId: conf.id,
          typeId: builtinTypeId('session'),
          title: 'Initial Title',
          room: 'Room 101',
          organisation: 'Acme Corp',
          speakerNames: ['Speaker One'],
        );

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: ActivityEditorScreen(activityId: a.id),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit activity'), findsOneWidget);
        expect(find.text('Initial Title'), findsOneWidget);
        expect(find.text('Room 101'), findsOneWidget);

        // Clear and change title
        await tester.enterText(
          find.byKey(const Key('activity-title-field')),
          'Renamed Title',
        );

        // Save
        await tester.tap(find.byKey(const Key('save-activity-button')));
        await tester.pumpAndSettle();

        final updated = (await t.activities.get(a.id))!;
        expect(updated.title, 'Renamed Title');
        expect(updated.room, 'Room 101');
        expect(updated.organisation, 'Acme Corp');
        expect(updated.speakerNames, ['Speaker One']);
      },
    );

    testWidgets(
      'FR-ACT-04 delete button in editor confirms and removes activity',
      (tester) async {
        final conf = await t.conference();
        final a = await t.activities.create(
          conferenceId: conf.id,
          typeId: builtinTypeId('session'),
          title: 'To Be Deleted',
        );

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: ActivityEditorScreen(activityId: a.id),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll to delete button
        await tester.ensureVisible(
          find.byKey(const Key('delete-activity-button')),
        );
        await tester.tap(find.byKey(const Key('delete-activity-button')));
        await tester.pumpAndSettle();

        // Confirmation dialog
        expect(find.text('Delete "To Be Deleted"?'), findsOneWidget);
        await tester.tap(find.text('Delete permanently'));
        await tester.pumpAndSettle();

        // Verify deleted from db
        expect(await t.activities.get(a.id), isNull);
      },
    );
  });

  group('FR-ACT-08 contact details and follow-up', () {
    testWidgets(
      'FR-ACT-08 contact fields and follow-up action persist and display manual etiquette note',
      (tester) async {
        final conf = await t.conference();

        Activity? savedActivity;
        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  savedActivity = await Navigator.of(context).push<Activity>(
                    MaterialPageRoute(
                      builder: (context) =>
                          ActivityEditorScreen(conferenceId: conf.id),
                    ),
                  );
                },
                child: const Text('Open Editor'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Editor'));
        await tester.pumpAndSettle();

        // Etiquette note check (FR-ACT-08)
        expect(
          find.text(
            'Manual entry only. No facial recognition or automatic identity extraction.',
          ),
          findsOneWidget,
        );

        // Enter contact name, details, follow-up
        await tester.enterText(
          find.byKey(const Key('activity-contact-name-field')),
          'Jane Doe',
        );
        await tester.enterText(
          find.byKey(const Key('activity-contact-details-field')),
          'jane.doe@example.org · +44 7700 900077',
        );
        await tester.enterText(
          find.byKey(const Key('activity-follow-up-field')),
          'Send architecture whitepaper and invite to advisory board',
        );

        // Save
        await tester.tap(find.byKey(const Key('save-activity-button')));
        await tester.pumpAndSettle();

        expect(savedActivity, isNotNull);
        expect(savedActivity!.contactName, 'Jane Doe');
        expect(
          savedActivity!.contactDetails,
          'jane.doe@example.org · +44 7700 900077',
        );
        expect(
          savedActivity!.followUpText,
          'Send architecture whitepaper and invite to advisory board',
        );

        final inDb = (await t.activities.get(savedActivity!.id))!;
        expect(inDb.contactName, 'Jane Doe');
        expect(inDb.contactDetails, 'jane.doe@example.org · +44 7700 900077');
        expect(
          inDb.followUpText,
          'Send architecture whitepaper and invite to advisory board',
        );
      },
    );
  });
}
