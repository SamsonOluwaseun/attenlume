import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/review_timeline.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/playback_review/review_header.dart';
import 'package:attenlume/features/playback_review/review_moments.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_playback_engine.dart';
import '../../fixtures/fixtures.dart';

/// The review screen laid out as the screens board's "Session review":
/// hero, header, Highlights, Timeline, Photos and Notes tabs (ADR-053)
/// [P1-39].
void main() {
  late TestData t;
  late Directory root;
  late FakePlaybackEngine engine;

  setUp(() async {
    t = TestData();
    root = Directory.systemTemp.createTempSync('review_tabs_test_');
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

  Future<void> showTab(WidgetTester tester, String name) async {
    final tab = find.byKey(Key('review-tab-$name-button'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
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

  Photo photo(String id, int minute, PhotoSource source) => Photo(
    id: id,
    activityId: 'a',
    filePath: 'photos/$id.jpg',
    takenUtc: DateTime.utc(2026, 11, 4, 9, minute),
    offsetMs: (minute - 30) * 60000,
    source: source,
    originalKept: true,
    createdAt: DateTime.utc(2026, 11, 4),
    updatedAt: DateTime.utc(2026, 11, 4),
  );

  group('P1-39 session review layout', () {
    test('FR-REV-02 the hero is the first photo taken in the app', () {
      expect(reviewHeroPhoto(const []), isNull);
      final imported = photo('imported', 31, PhotoSource.galleryImport);
      final second = photo('second', 45, PhotoSource.inApp);
      final first = photo('first', 40, PhotoSource.inApp);
      expect(reviewHeroPhoto([imported, second, first])!.id, 'first');
      expect(reviewHeroPhoto([imported])!.id, 'imported');
    });

    test('FR-REV-02 the date is on the conference calendar', () {
      // 23:30 UTC on 3 Nov is 4 Nov in Tokyo.
      expect(
        reviewDate(DateTime.utc(2026, 11, 3, 23, 30), 'Asia/Tokyo'),
        '4 Nov 2026',
      );
      expect(
        reviewDate(DateTime.utc(2026, 11, 3, 23, 30), 'Europe/London'),
        '3 Nov 2026',
      );
    });

    testWidgets('FR-REV-02 header shows the hero, title, place, date and '
        'duration, with Highlights selected', (tester) async {
      final sample = await tester.runAsync(() async {
        final s = await SampleConference.build(t);
        await t.activities.update(
          s.keynote.id,
          const ActivitiesCompanion(room: Value('Main Stage')),
        );
        return s;
      });
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: sample!.keynote.id)),
      );
      await settle(tester);

      expect(find.text('Session review'), findsOneWidget);
      expect(find.byKey(const Key('review-hero-photo')), findsOneWidget);
      expect(find.text('Data Mesh in Practice'), findsOneWidget);
      expect(
        find.text('Main Stage · Samlytics Conference 2026'),
        findsOneWidget,
      );
      expect(find.text('4 Nov 2026 · 17 min'), findsOneWidget);
      for (final tab in ['Highlights', 'Timeline', 'Photos', 'Notes']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.byKey(const Key('review-tab-highlights')), findsOneWidget);
      expect(find.text('Key moments'), findsOneWidget);
      expect(find.text('Session start'), findsOneWidget);
    });

    testWidgets('FR-REV-02 a session without photos shows the branded '
        'placeholder', (tester) async {
      final conf = await tester.runAsync(t.conference);
      final act = await tester.runAsync(() => t.activity(conf!.id));
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: act!.id)),
      );
      await settle(tester);

      expect(find.byKey(const Key('review-hero-placeholder')), findsOneWidget);
      expect(find.byKey(const Key('review-hero-photo')), findsNothing);
      expect(find.byKey(const Key('review-no-moments')), findsOneWidget);
      await showTab(tester, 'photos');
      expect(find.byKey(const Key('review-no-photos')), findsOneWidget);
    });

    test('FR-BMK-01 key moments give bookmarks the slide shown before '
        'them', () {
      Bookmark bookmark(String id, int minute, String? label) => Bookmark(
        id: id,
        activityId: 'a',
        atUtc: DateTime.utc(2026, 11, 4, 9, minute),
        offsetMs: (minute - 30) * 60000,
        label: label,
        source: BookmarkSource.ui,
        createdAt: DateTime.utc(2026, 11, 4),
        updatedAt: DateTime.utc(2026, 11, 4),
      );
      final slide = photo('p1', 40, PhotoSource.inApp);
      final timeline = ReviewTimeline.build(
        segments: const [],
        photos: [slide],
        bookmarks: [bookmark('b1', 30, 'Opening'), bookmark('b2', 45, null)],
      );
      final moments = keyMoments(timeline, [slide]);
      // No audio, so no "Session start" row.
      expect(moments.map((m) => m.id), ['b1', 'p1', 'b2']);
      expect(moments[0].thumbnail, isNull);
      expect(moments[1].label, 'Photo');
      expect(moments[2].thumbnail?.id, 'p1');
      expect(moments[2].label, 'Bookmark');
    });

    test('FR-PHO-06 a cleared caption is not brought back from the '
        'timeline', () {
      final old = photo('p1', 40, PhotoSource.inApp);
      final captioned = Photo(
        id: old.id,
        activityId: old.activityId,
        filePath: old.filePath,
        takenUtc: old.takenUtc,
        offsetMs: old.offsetMs,
        caption: 'Old caption',
        source: old.source,
        originalKept: true,
        createdAt: old.createdAt,
        updatedAt: old.updatedAt,
      );
      final timeline = ReviewTimeline.build(
        segments: const [],
        photos: [captioned],
      );
      // The timeline was built with the caption; the photo row now has none.
      expect(keyMoments(timeline, [old]).single.label, 'Photo');
    });
  });

  group('P1-39 Highlights tab', () {
    testWidgets('FR-REV-01 the moment menu plays from a bookmark and shows '
        'it on the timeline', (tester) async {
      final sample = await open(tester);
      final bookmark = (await tester.runAsync(
        () => t.media.bookmarksFor(sample.keynote.id),
      ))!.single;

      await tester.tap(find.byKey(Key('review-moment-menu-${bookmark.id}')));
      await tester.pumpAndSettle();
      expect(find.text('View photo'), findsNothing);
      await tester.tap(find.text('Play from here'));
      await settle(tester);
      expect(engine.seekedTo, const Duration(minutes: 2));
      expect(engine.playing, isTrue, reason: 'Play from here starts it');

      await tester.tap(find.byKey(Key('review-moment-menu-${bookmark.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show on timeline'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const Key('review-tab-timeline')), findsOneWidget);
      expect(find.byKey(const Key('review-position')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('review-position'))).data,
        '15:00',
      );
    });

    testWidgets('FR-REV-01 tapping a moment moves the playhead to it', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Photo'));
      await settle(tester);
      // The photo at 14:00 is 1 minute into the second segment.
      expect(engine.openPath, endsWith('pending.m4a'));
      expect(engine.seekedTo, const Duration(minutes: 1));
    });
  });

  group('P1-39 Photos tab', () {
    testWidgets('FR-PHO-06 photos play from their time and open for '
        'captions', (tester) async {
      final sample = await open(tester);
      final p = (await tester.runAsync(
        () => t.media.photosFor(sample.keynote.id),
      ))!.single;
      await showTab(tester, 'photos');
      expect(find.text('Photos (1)'), findsOneWidget);

      await tester.tap(find.byKey(Key('review-photo-play-${p.id}')));
      await settle(tester);
      expect(engine.seekedTo, const Duration(minutes: 1));
      expect(engine.playing, isTrue, reason: 'play from a photo starts it');

      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Photo at 14:00'), findsOneWidget);
      handle.dispose();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(Key('review-photo-${p.id}')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-detail-sheet')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('photo-caption-input')),
        'Architecture overview',
      );
      await tester.tap(find.byKey(const Key('photo-save-button')));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('14:00 · Architecture overview'), findsOneWidget);
      await showTab(tester, 'highlights');
      expect(find.text('Architecture overview'), findsOneWidget);
    });
  });

  group('P1-39 Notes tab', () {
    testWidgets('FR-BMK-02 notes show and can be edited from review', (
      tester,
    ) async {
      final sample = await tester.runAsync(() async {
        final s = await SampleConference.build(t);
        await t.activities.update(
          s.keynote.id,
          const ActivitiesCompanion(
            notesMd: Value('**[Quick thought]** Ask about lineage'),
          ),
        );
        return s;
      });
      await tester.pumpWidget(
        subject(tester, ReviewScreen(activityId: sample!.keynote.id)),
      );
      await settle(tester);
      await showTab(tester, 'notes');

      expect(
        find.textContaining('Ask about lineage', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('activity-notes-edit-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('activity-notes-input')),
        'Follow up with Samlytics Data Services',
      );
      await tester.tap(find.byKey(const Key('activity-notes-save-button')));
      await settle(tester);
      await tester.pumpAndSettle();

      final saved = await tester.runAsync(
        () => t.activities.get(sample.keynote.id),
      );
      expect(saved!.notesMd, 'Follow up with Samlytics Data Services');
      expect(
        find.textContaining(
          'Follow up with Samlytics Data Services',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });
  });
}
