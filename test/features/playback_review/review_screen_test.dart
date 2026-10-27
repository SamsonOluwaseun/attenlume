import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/waveform_summary.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/activity_detail_sheet.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_playback_engine.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakePlaybackEngine engine;

  setUp(() async {
    t = TestData();
    root = Directory.systemTemp.createTempSync('review_screen_test_');
    engine = FakePlaybackEngine();
  });

  tearDown(() async {
    await t.close();
    root.deleteSync(recursive: true);
  });

  Widget subject(WidgetTester tester, Widget child) {
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
        mediaRootProvider.overrideWithValue(() async => root),
        audioPlaybackEngineFactoryProvider.overrideWithValue(() => engine),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('FR-REV-01 to 03 review screen [P1-17]', () {
    testWidgets('FR-REV-02 shows segments, gaps, interruptions, photos and '
        'bookmarks on the timeline', (tester) async {
      final sample = await tester.runAsync(() => SampleConference.build(t));
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: sample!.keynote.id)),
      );
      await settle(tester);

      expect(find.text('Data Mesh in Practice'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Timeline: 2 segments, 1 gap, 1 bookmark, 1 photo, 1 interruption, '
          '1 cut',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'review-marker-interruption-',
              ),
        ),
        findsOneWidget,
      );
      expect(find.text('17 min recorded'), findsOneWidget);
      expect(find.text('Key slide'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('FR-REV-01 play, pause, skip, speed and jump to a key moment', (
      tester,
    ) async {
      final sample = await tester.runAsync(() => SampleConference.build(t));
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: sample!.keynote.id)),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('review-play')));
      await settle(tester);
      expect(engine.playing, isTrue);
      expect(find.byTooltip('Pause'), findsOneWidget);
      // FR-REV-04: playback starts after the 30 s intro cut.
      expect(engine.seekedTo, const Duration(seconds: 30));

      await tester.tap(find.byKey(const Key('review-skip-forward')));
      await settle(tester);
      expect(engine.seekedTo, const Duration(seconds: 45));
      expect(find.text('0:45'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-speed')));
      await settle(tester);
      expect(engine.speed, 1.25);
      expect(find.text('1.25×'), findsOneWidget);

      // The bookmark at 15:00 is 2 minutes into the second segment.
      await tester.tap(find.text('Key slide'));
      await settle(tester);
      expect(engine.openPath, endsWith('pending.m4a'));
      expect(engine.seekedTo, const Duration(minutes: 2));
      expect(find.text('15:00'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('review-play')));
      await settle(tester);
      expect(engine.playing, isFalse);
    });

    testWidgets('FR-REV-03 the waveform shows one page at a time', (
      tester,
    ) async {
      final sample = await tester.runAsync(() async {
        final s = await SampleConference.build(t);
        final first = (await t.media.segmentsFor(s.keynote.id)).first;
        final writer = WaveformSummaryWriter(
          MediaPaths.resolve(
            root,
            MediaPaths.waveform(s.conference.id, s.keynote.id, first.id),
          ),
        );
        for (var i = 0; i < 3000; i++) {
          writer.add(-20);
        }
        await writer.close();
        return s;
      });
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: sample!.keynote.id)),
      );
      await settle(tester);

      expect(find.text('0:00 to 2:00'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('page 1 of 10')), findsOneWidget);
      await tester.tap(find.byKey(const Key('waveform-next')));
      await settle(tester);
      expect(find.text('2:00 to 4:00'), findsOneWidget);

      // Jumping the playhead to 15:00 follows it to page 8.
      await tester.tap(find.text('Key slide'));
      await settle(tester);
      expect(find.text('14:00 to 16:00'), findsOneWidget);
    });

    testWidgets('FR-REV-01 without a recording the controls are off', (
      tester,
    ) async {
      final conf = await tester.runAsync(t.conference);
      final act = await tester.runAsync(() => t.activity(conf!.id));
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: act!.id)),
      );
      await settle(tester);

      expect(find.byKey(const Key('review-no-audio')), findsOneWidget);
      final play = tester.widget<IconButton>(
        find.byKey(const Key('review-play')),
      );
      expect(play.onPressed, isNull);
    });

    testWidgets('FR-REV-01 the activity details open the review screen', (
      tester,
    ) async {
      final sample = await tester.runAsync(() => SampleConference.build(t));
      final summary = await tester.runAsync(
        () => t.activities.getSummary(sample!.keynote.id),
      );
      await tester.pumpWidget(
        subject(
          tester,
          Scaffold(
            body: ActivityDetailSheet(
              summary: summary!,
              timezone: 'Europe/London',
            ),
          ),
        ),
      );
      await settle(tester);

      final review = find.byKey(const Key('activity-detail-review-button'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await settle(tester);
      expect(find.byType(ReviewScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byType(ReviewScreen), findsNothing);
      expect(engine.disposed, isTrue, reason: 'player released on close');
    });
  });

  group('FR-REV-04 and FR-REV-05 trim and split [P1-18]', () {
    Future<void> tapKey(WidgetTester tester, String key) async {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await settle(tester);
    }

    Future<void> seekToKeySlide(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Key slide'));
      await tester.tap(find.text('Key slide'));
      await settle(tester);
    }

    Future<SampleConference> open(WidgetTester tester) async {
      final sample = await tester.runAsync(() => SampleConference.build(t));
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: sample!.keynote.id)),
      );
      await settle(tester);
      return sample;
    }

    testWidgets('FR-REV-04 trim start to the playhead, then undo', (
      tester,
    ) async {
      final sample = await open(tester);
      expect(find.text('0:00 to 0:30'), findsOneWidget);
      expect(find.text('16 min after cuts'), findsOneWidget);

      await seekToKeySlide(tester);
      await tapKey(tester, 'trim-start');
      expect(find.text('0:00 to 15:00'), findsOneWidget);
      expect(find.text('5 min after cuts'), findsOneWidget);
      final cuts = await tester.runAsync(
        () => t.cuts.activeFor(sample.keynote.id),
      );
      expect(cuts, hasLength(2));

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('0:00 to 15:00'), findsNothing);
      expect(
        await tester.runAsync(() => t.cuts.activeFor(sample.keynote.id)),
        hasLength(1),
      );
    });

    testWidgets('FR-REV-04 trim end and a middle cut from two marks', (
      tester,
    ) async {
      await open(tester);
      await seekToKeySlide(tester);
      await tapKey(tester, 'trim-end');
      expect(find.text('15:00 to 20:00'), findsOneWidget);

      // Mark 15:00, move to the photo at 14:00, mark again.
      await tapKey(tester, 'trim-mark-cut');
      expect(find.byKey(const Key('trim-marking-hint')), findsOneWidget);
      expect(find.text('End cut here'), findsOneWidget);
      await tester.ensureVisible(find.byIcon(Icons.photo_camera_outlined));
      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await settle(tester);
      await tapKey(tester, 'trim-mark-cut');
      expect(find.text('14:00 to 15:00'), findsOneWidget);
      expect(find.text('Start cut here'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Timeline: .*, 2 cuts$')),
        findsOneWidget,
      );
    });

    testWidgets('FR-REV-04 removing a cut can be undone', (tester) async {
      final sample = await open(tester);
      final intro = (await tester.runAsync(
        () => t.cuts.activeFor(sample.keynote.id),
      ))!.single;
      await tapKey(tester, 'trim-remove-${intro.id}');
      expect(find.text('0:00 to 0:30'), findsNothing);
      expect(find.text('Cut removed.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('0:00 to 0:30'), findsOneWidget);
    });

    testWidgets('FR-REV-05 split at the playhead names and creates part 2', (
      tester,
    ) async {
      final sample = await open(tester);
      await seekToKeySlide(tester);
      await tapKey(tester, 'trim-split');
      expect(find.text('Split at 15:00?'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('split-title')), 'Q and A');
      await tapKey(tester, 'split-confirm');
      await settle(tester);

      expect(
        find.text('Split. "Q and A" is now in the activity list.'),
        findsOneWidget,
      );
      final activities = await tester.runAsync(
        () => t.activities.listForConference(sample.conference.id),
      );
      final part2 = activities!.singleWhere((a) => a.title == 'Q and A');
      final bookmarks = await tester.runAsync(
        () => t.media.bookmarksFor(part2.id),
      );
      expect(bookmarks!.single.label, 'Key slide');
      // The screen reloads the first part: the bookmark has gone from it.
      expect(find.text('Key slide'), findsNothing);
    });

    testWidgets('FR-REV-05 cancelling the split changes nothing', (
      tester,
    ) async {
      final sample = await open(tester);
      await seekToKeySlide(tester);
      await tapKey(tester, 'trim-split');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      final activities = await tester.runAsync(
        () => t.activities.listForConference(sample.conference.id),
      );
      expect(activities, hasLength(3));
      expect(find.text('Key slide'), findsOneWidget);
    });
  });
}
