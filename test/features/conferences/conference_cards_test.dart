import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/conference_card.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/shared/utilities/date_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

/// My conferences as on the screens board: search, cover photos and counts
/// (FR-UI-10, ADR-052) [P1-39].
void main() {
  group('FR-UI-10 card data', () {
    late TestData t;
    setUp(() => t = TestData());
    tearDown(() => t.close());

    test('FR-UI-10 counts activities and photos, and the cover is the first '
        'photo taken outside private activities', () async {
      final conf = await t.conference();
      final empty = await t.conference();
      final keynote = await t.activity(conf.id, typeKey: 'keynote');
      final reflection = await t.activities.create(
        conferenceId: conf.id,
        typeId: builtinTypeId('session'),
        isPrivate: true,
      );
      // The private photo is the earliest: it counts but is never a cover.
      await t.media.addPhoto(
        activityId: reflection.id,
        filePath: 'private.jpg',
        takenUtc: DateTime.utc(2026, 11, 4, 9),
        source: PhotoSource.inApp,
      );
      await t.media.addPhoto(
        activityId: keynote.id,
        filePath: 'later.jpg',
        takenUtc: DateTime.utc(2026, 11, 4, 11),
        source: PhotoSource.inApp,
      );
      await t.media.addPhoto(
        activityId: keynote.id,
        filePath: 'first.jpg',
        thumbnailPath: 'first-thumb.jpg',
        takenUtc: DateTime.utc(2026, 11, 4, 10),
        source: PhotoSource.inApp,
      );

      final info = await t.conferences.cardInfo();

      expect(info[conf.id]!.activityCount, 2);
      expect(info[conf.id]!.photoCount, 3);
      expect(info[conf.id]!.coverPhotoPath, 'first-thumb.jpg');
      expect(info[empty.id]!.activityCount, 0);
      expect(info[empty.id]!.photoCount, 0);
      expect(info[empty.id]!.coverPhotoPath, isNull);
    });

    test('FR-UI-10 counts read naturally in the singular and plural', () {
      expect(
        conferenceCountsLabel(
          const ConferenceCardInfo(activityCount: 1, photoCount: 1),
        ),
        '1 activity · 1 photo',
      );
      expect(
        conferenceCountsLabel(
          const ConferenceCardInfo(activityCount: 3, photoCount: 12),
        ),
        '3 activities · 12 photos',
      );
    });
  });

  group('FR-UI-10 My conferences', () {
    late TestData t;
    late Directory root;

    setUp(() {
      t = TestData();
      root = Directory.systemTemp.createTempSync('attenlume_cards_');
    });
    tearDown(() async {
      await t.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Widget subject() => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        mediaRootProvider.overrideWithValue(() async => root),
        recordingStatusProvider.overrideWith(
          (ref) => Stream.value(RecordingStatus.idle),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ConferenceListScreen(),
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<(Conference, Conference)> twoConferences(WidgetTester tester) async {
      final result = await tester.runAsync(() async {
        final london = await t.conferences.create(
          name: 'Samlytics Conference 2026',
          timezone: 'Europe/London',
          venue: 'ExCeL London',
          startDate: DateTime.utc(2026, 11, 4),
          endDate: DateTime.utc(2026, 11, 5),
        );
        final manchester = await t.conferences.create(
          name: 'Samlytics Conference 2026',
          timezone: 'Europe/London',
          venue: 'Manchester Central',
        );
        final keynote = await t.activity(london.id, typeKey: 'keynote');
        await t.activity(london.id);
        await t.media.addPhoto(
          activityId: keynote.id,
          filePath: 'photos/slide-01.jpg',
          takenUtc: DateTime.utc(2026, 11, 4, 10),
          source: PhotoSource.inApp,
        );
        return (london, manchester);
      });
      return result!;
    }

    Finder card(Conference c) => find.byKey(Key('conference-card-${c.id}'));

    testWidgets('FR-UI-10 cards show place, dates, counts, a cover and a '
        'chevron', (tester) async {
      final (london, manchester) = await twoConferences(tester);
      await tester.pumpWidget(subject());
      await settle(tester);

      expect(card(london), findsOneWidget);
      expect(card(manchester), findsOneWidget);
      expect(find.text('ExCeL London'), findsOneWidget);
      expect(
        find.text(formatDateRange(london.startDate, london.endDate)),
        findsOneWidget,
      );
      expect(find.text('2 activities · 1 photo'), findsOneWidget);
      expect(find.text('0 activities · 0 photos'), findsOneWidget);
      expect(
        find.descendant(
          of: card(london),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
      // London has a photo, so its cover is the photo file (the file is
      // missing in this test, so the image falls back when decoded).
      expect(
        find.descendant(
          of: card(london),
          matching: find.byKey(const Key('conference-cover-photo')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card(manchester),
          matching: find.byKey(const Key('conference-cover-placeholder')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('FR-UI-10 the cover is the conference photo file from the '
        'media folder, never a network image', (tester) async {
      final (london, _) = await twoConferences(tester);
      await tester.pumpWidget(subject());
      await settle(tester);

      final image = tester.widget<Image>(
        find.descendant(
          of: card(london),
          matching: find.byKey(const Key('conference-cover-photo')),
        ),
      );
      expect(image.image, isA<ResizeImage>());
      final file = (image.image as ResizeImage).imageProvider as FileImage;
      expect(file.file.path, endsWith('slide-01.jpg'));
      expect(file.file.path, startsWith(root.path));
    });

    testWidgets('FR-UI-10 search filters by name and place, and says when '
        'nothing matches', (tester) async {
      final (london, manchester) = await twoConferences(tester);
      await tester.pumpWidget(subject());
      await settle(tester);

      expect(find.text(ConferenceListScreen.searchHint), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('conference-search-field')),
        'manchester',
      );
      await tester.pump();
      expect(card(manchester), findsOneWidget);
      expect(card(london), findsNothing);

      await tester.enterText(
        find.byKey(const Key('conference-search-field')),
        'SAMLYTICS',
      );
      await tester.pump();
      expect(card(manchester), findsOneWidget);
      expect(card(london), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('conference-search-field')),
        'Berlin',
      );
      await tester.pump();
      expect(card(manchester), findsNothing);
      expect(card(london), findsNothing);
      expect(find.text('No conferences match "Berlin".'), findsOneWidget);

      await tester.tap(find.byKey(const Key('conference-search-clear')));
      await tester.pump();
      expect(card(manchester), findsOneWidget);
      expect(card(london), findsOneWidget);
    });

    testWidgets('FR-UI-10 a card reads as one button with everything it '
        'shows and can be activated (NFR-09)', (tester) async {
      final handle = tester.ensureSemantics();
      final (london, _) = await twoConferences(tester);
      await tester.pumpWidget(subject());
      await settle(tester);

      final label = tester.getSemantics(card(london)).label;
      expect(label, contains('Samlytics Conference 2026'));
      expect(label, contains('ExCeL London'));
      expect(label, contains('2 activities · 1 photo'));
      // The card can be activated by a screen reader, not only announced.
      final data = tester.getSemantics(card(london)).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  test('FR-UI-10 search ignores case and surrounding spaces', () {
    final conf = Conference(
      id: 'c1',
      name: 'Samlytics Conference 2026',
      timezone: 'Europe/London',
      venue: 'ExCeL London',
      requestedOutputs: const [],
      defaultRecordingProfile: RecordingProfile.balanced,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(conferenceMatchesSearch(conf, ''), isTrue);
    expect(conferenceMatchesSearch(conf, '  excel '), isTrue);
    expect(conferenceMatchesSearch(conf, 'samlytics'), isTrue);
    expect(conferenceMatchesSearch(conf, 'Berlin'), isFalse);
  });
}
