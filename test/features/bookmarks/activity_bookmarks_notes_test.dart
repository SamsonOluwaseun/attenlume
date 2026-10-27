import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/bookmarks/activity_bookmarks_section.dart';
import 'package:attenlume/features/bookmarks/activity_notes_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget subject(Widget child) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(t.db),
      activityRepositoryProvider.overrideWithValue(t.activities),
      mediaAssetRepositoryProvider.overrideWithValue(t.media),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('FR-BMK-01 bookmarks in the activity details [P1-16]', () {
    testWidgets('FR-BMK-01 lists bookmarks with offset, label and note', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      // 10:00 UTC on 4 November is 10:00 in London (GMT).
      final start = DateTime.utc(2026, 11, 4, 10);
      await tester.runAsync(() async {
        await t.segment(
          act.id,
          start: start,
          length: const Duration(minutes: 10),
        );
        await t.media.addBookmark(
          activityId: act.id,
          source: BookmarkSource.ui,
          atUtc: start.add(const Duration(minutes: 4, seconds: 5)),
          label: 'Key slide',
          note: 'Replication diagram',
        );
      });

      await tester.pumpWidget(
        subject(
          ActivityBookmarksSection(
            activityId: act.id,
            timezone: 'Europe/London',
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Bookmarks (1)'), findsOneWidget);
      expect(find.text('Key slide'), findsOneWidget);
      expect(find.text('Replication diagram'), findsOneWidget);
      expect(find.text('4:05 · 10:04'), findsOneWidget);
    });

    testWidgets('FR-BMK-01 edits a label and note, then removes it', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      var changes = 0;
      final mark = await tester.runAsync(
        () => t.media.addBookmark(
          activityId: act.id,
          source: BookmarkSource.notification,
          label: 'Bookmark',
        ),
      );

      await tester.pumpWidget(
        subject(
          ActivityBookmarksSection(
            activityId: act.id,
            timezone: 'Europe/London',
            onChanged: () => changes++,
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(Key('activity-bookmark-${mark!.id}')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('bookmark-label-input')),
        'Question',
      );
      await tester.enterText(
        find.byKey(const Key('bookmark-note-input')),
        'Ask about funding',
      );
      await tester.tap(find.byKey(const Key('bookmark-save-button')));
      await settle(tester);

      expect(find.text('Question'), findsOneWidget);
      expect(find.text('Ask about funding'), findsOneWidget);
      final saved = (await tester.runAsync(() => t.media.bookmarksFor(act.id)))!
          .single;
      expect(saved.label, 'Question');
      expect(saved.note, 'Ask about funding');

      await tester.tap(find.byKey(Key('activity-bookmark-${mark.id}')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('bookmark-delete-button')));
      await settle(tester);
      expect(find.text('Remove this bookmark?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bookmark-delete-confirm')));
      await settle(tester);

      expect(
        await tester.runAsync(() => t.media.bookmarksFor(act.id)),
        isEmpty,
      );
      expect(find.textContaining('No bookmarks yet'), findsOneWidget);
      expect(changes, 2);
    });
  });

  group('FR-BMK-02 activity notes in plain Markdown [P1-16]', () {
    testWidgets('FR-BMK-02 adds notes and stores the Markdown as written', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      var saved = false;

      await tester.pumpWidget(
        subject(
          ActivityNotesSection(
            activityId: act.id,
            notesMd: null,
            onChanged: () => saved = true,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('No notes yet.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activity-notes-edit-button')));
      await settle(tester);
      const markdown = '- **Data mesh** needs ownership\n- Follow up with Ada';
      await tester.enterText(
        find.byKey(const Key('activity-notes-input')),
        markdown,
      );
      await tester.tap(find.byKey(const Key('activity-notes-save-button')));
      await settle(tester);

      final stored = await tester.runAsync(() => t.activities.get(act.id));
      expect(stored!.notesMd, markdown);
      expect(saved, isTrue);
    });

    testWidgets('FR-BMK-02 clearing the notes stores nothing', (tester) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      await tester.pumpWidget(
        subject(ActivityNotesSection(activityId: act.id, notesMd: 'Old note')),
      );
      await settle(tester);
      expect(find.text('Old note'), findsOneWidget);
      expect(find.text('Edit notes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activity-notes-edit-button')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('activity-notes-input')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('activity-notes-save-button')));
      await settle(tester);

      final stored = await tester.runAsync(() => t.activities.get(act.id));
      expect(stored!.notesMd, isNull);
    });
  });
}
