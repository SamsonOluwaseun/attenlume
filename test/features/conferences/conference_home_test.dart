import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/conferences/activity_detail_sheet.dart';
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

  Widget createSubject(String conferenceId, WidgetTester tester) {
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
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ConferenceHomeScreen(conferenceId: conferenceId),
      ),
    );
  }

  group('FR-ACT-01 conference home display', () {
    testWidgets(
      'FR-ACT-01 displays name, dates, stats, and dominant start activity button',
      (tester) async {
        final sample = await SampleConference.build(t);

        await tester.pumpWidget(createSubject(sample.conference.id, tester));
        await tester.pumpAndSettle();

        // Name and Dates
        expect(
          find.text('Data Summit London'),
          findsWidgets,
        ); // App bar and card
        expect(find.text('4–5 Nov 2026'), findsOneWidget);

        // Stats row: 3 activities, 17 min, storage used > 0
        expect(
          find.text('Activities'),
          findsWidgets,
        ); // stats label and section header
        expect(
          find.text('3'),
          findsWidgets,
        ); // stat card and activities count badge

        expect(find.text('Recorded'), findsOneWidget);
        expect(find.text('17 min'), findsOneWidget);

        expect(find.text('Storage used'), findsOneWidget);
        expect(find.text('6.2 MB'), findsOneWidget);

        // Single dominant "Start activity" action
        final startButton = find.byKey(const Key('start-activity-button'));
        expect(startButton, findsOneWidget);
        expect(
          find.descendant(
            of: startButton,
            matching: find.text('Start activity'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: startButton,
            matching: find.byIcon(Icons.mic_rounded),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FR-ACT-01 empty conference displays zero stats and empty state message',
      (tester) async {
        final conf = await t.conference(name: 'Empty Summit');

        await tester.pumpWidget(createSubject(conf.id, tester));
        await tester.pumpAndSettle();

        expect(find.text('Empty Summit'), findsWidgets);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('0 min'), findsOneWidget);
        expect(find.text('0 B'), findsOneWidget);

        // Empty state message per DESIGN_GUIDE
        expect(
          find.text(
            'Nothing captured yet. Start your first activity when the session begins.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('FR-ACT-02 quick-start buttons', () {
    testWidgets(
      'FR-ACT-02 offers Session, Conversation, Exhibit, Reflection quick-start buttons',
      (tester) async {
        final conf = await t.conference();

        await tester.pumpWidget(createSubject(conf.id, tester));
        await tester.pumpAndSettle();

        expect(find.text('Quick start'), findsOneWidget);
        expect(find.byKey(const Key('quick-start-session')), findsOneWidget);
        expect(
          find.byKey(const Key('quick-start-conversation')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('quick-start-exhibit')), findsOneWidget);
        expect(find.byKey(const Key('quick-start-reflection')), findsOneWidget);
      },
    );

    testWidgets(
      'FR-ACT-02 tapping quick-start button creates activity and refreshes timeline',
      (tester) async {
        final conf = await t.conference();
        t.clock.set(DateTime.utc(2026, 11, 4, 14, 15));

        await tester.pumpWidget(createSubject(conf.id, tester));
        await tester.pumpAndSettle();

        // Tap quick start Session
        await tester.tap(find.byKey(const Key('quick-start-session')));
        await tester.pumpAndSettle();

        // Confirms creation via SnackBar
        expect(find.text('Started Session 1, 14:15'), findsOneWidget);

        // Activity appears in the list
        expect(find.text('Session 1, 14:15'), findsOneWidget);

        // Stat updates from 0 to 1
        expect(find.text('1'), findsWidgets);
      },
    );

    testWidgets(
      'FR-ACT-02 tapping dominant start activity button opens type selection sheet',
      (tester) async {
        final conf = await t.conference();
        t.clock.set(DateTime.utc(2026, 11, 4, 11, 0));

        await tester.pumpWidget(createSubject(conf.id, tester));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('start-activity-button')));
        await tester.pumpAndSettle();

        expect(find.byType(StartActivitySheet), findsOneWidget);
        expect(find.text('Start activity'), findsWidgets);
        expect(
          find.byKey(const Key('activity-type-chip-keynote')),
          findsOneWidget,
        );

        // Tap Keynote chip in sheet
        await tester.tap(find.byKey(const Key('activity-type-chip-keynote')));
        await tester.pumpAndSettle();

        // Bottom sheet dismissed, activity created
        expect(find.byType(StartActivitySheet), findsNothing);
        expect(find.text('Keynote 1, 11:00'), findsOneWidget);
        expect(find.text('Started Keynote 1, 11:00'), findsOneWidget);
      },
    );
  });

  group('FR-ACT-03 activity list and ordering', () {
    testWidgets(
      'FR-ACT-03 lists activities with type, title, start time, profile and counts',
      (tester) async {
        final sample = await SampleConference.build(t);

        await tester.pumpWidget(createSubject(sample.conference.id, tester));
        await tester.pumpAndSettle();

        // Keynote card present
        expect(find.text('Data Mesh in Practice'), findsOneWidget);
        expect(find.text('Keynote'), findsOneWidget);
        expect(find.text('09:30 · 17 min'), findsOneWidget);
        expect(find.text('Saved'), findsOneWidget);
        expect(find.text('Balanced'), findsWidgets);

        // Private reflection card present
        expect(
          find.text('Reflection'),
          findsWidgets,
        ); // quick-start button and card
        expect(find.text('Private'), findsWidgets);
      },
    );

    testWidgets(
      'FR-ACT-03 actively recording activity is elevated to the top',
      (tester) async {
        final c = await t.conference();
        t.clock.set(DateTime.utc(2026, 11, 4, 9));

        // Activity 1: completed
        final act1 = await t.activity(c.id, title: 'Finished Opening');
        await t.segment(
          act1.id,
          start: DateTime.utc(2026, 11, 4, 9),
          length: const Duration(minutes: 20),
        );

        // Activity 2: actively recording
        t.clock.set(DateTime.utc(2026, 11, 4, 10));
        final act2 = await t.activity(c.id, title: 'Live Now Recording');
        await t.media.startSegment(
          activityId: act2.id,
          filePath: 'live.m4a',
          requestedProfile: RecordingProfile.balanced,
          codec: 'aac_lc',
          container: 'm4a',
          channelCount: 1,
          sampleRateHz: 48000,
          requestedBitrateBps: 48000,
        );

        await tester.pumpWidget(createSubject(c.id, tester));
        await tester.pumpAndSettle();

        // Find all activity titles in order
        final cards = tester
            .widgetList<Text>(find.textContaining('Live Now Recording'))
            .toList();
        expect(cards, isNotEmpty);

        // Live recording card is present with Recording status pill
        expect(find.text('Recording'), findsOneWidget);

        // Actively recording activity appears before Finished Opening
        final liveTop = tester.getTopLeft(find.text('Live Now Recording')).dy;
        final finishedTop = tester.getTopLeft(find.text('Finished Opening')).dy;
        expect(liveTop, lessThan(finishedTop));
      },
    );

    testWidgets('FR-ACT-03 tapping activity card opens ActivityDetailSheet', (
      tester,
    ) async {
      final sample = await SampleConference.build(t);

      await tester.pumpWidget(createSubject(sample.conference.id, tester));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Data Mesh in Practice'));
      await tester.pumpAndSettle();

      // Detail sheet opens
      expect(find.byType(ActivityDetailSheet), findsOneWidget);
      expect(find.text('Recorded duration'), findsOneWidget);
      expect(find.text('17 min'), findsWidgets);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Segments'), findsOneWidget);

      // Close sheet
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ActivityDetailSheet), findsNothing);
    });
  });
}
