import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixtures.dart';
import 'a11y_harness.dart';

/// NFR-09 accessibility of the session review screen, every tab, in light
/// and dark and at 200% text (ADR-050, ADR-053) [P1-26, P1-39].
void main() {
  Future<(A11yHarness, SampleConference)> open(
    WidgetTester tester, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(size, textScale: textScale);
    final sample = await h.io(() async {
      final s = await SampleConference.build(h.t);
      await h.t.activities.update(
        s.keynote.id,
        const ActivitiesCompanion(
          room: Value('Main Stage, Hall B'),
          notesMd: Value(
            '**[Quick thought]** Ask Samlytics Data Services about lineage '
            'tooling and how they version their data contracts.',
          ),
        ),
      );
      return s;
    });
    await tester.pumpWidget(
      h.app(ReviewScreen(activityId: sample.keynote.id), theme: theme),
    );
    await h.settle(20);
    return (h, sample);
  }

  final list = find
      .descendant(
        of: find.byKey(const Key('review-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the review list until [finder] is built and on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: list);
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
  }

  Future<void> showTab(WidgetTester tester, A11yHarness h, String tab) async {
    await reveal(tester, find.byKey(Key('review-tab-$tab-button')));
    await tester.tap(find.byKey(Key('review-tab-$tab-button')));
    await h.settle();
    expect(find.byKey(Key('review-tab-$tab')), findsOneWidget);
    // Back to the top so every part is laid out when scrolling through.
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await h.settle(2);
  }

  group('NFR-09 session review screen', () {
    for (final tab in ['highlights', 'timeline', 'photos', 'notes']) {
      for (final (themeName, theme) in [
        ('light', AppTheme.light()),
        ('dark', AppTheme.dark()),
      ]) {
        testWidgets('NFR-09 review $tab tab ($themeName) meets tap target, '
            'label and contrast guidelines', (tester) async {
          final handle = tester.ensureSemantics();
          final (h, _) = await open(tester, theme: theme);
          await showTab(tester, h, tab);
          await expectMeetsGuidelines(tester);
          handle.dispose();
        });
      }

      for (final size in A11ySize.values) {
        testWidgets('NFR-09 review $tab tab at 200% text on ${size.name} has '
            'no overflow', (tester) async {
          final (h, _) = await open(tester, size: size, textScale: 2);
          await showTab(tester, h, tab);
          await scrollThrough(tester, h);
        });
      }
    }

    testWidgets('NFR-09 review moment menu meets the guidelines at 200% '
        'text', (tester) async {
      final handle = tester.ensureSemantics();
      final (h, sample) = await open(tester, textScale: 2);
      final bookmark = (await h.io(
        () => h.t.media.bookmarksFor(sample.keynote.id),
      )).single;
      final menu = find.byKey(Key('review-moment-menu-${bookmark.id}'));
      await reveal(tester, menu);
      await tester.tap(menu);
      await h.settle();
      expect(find.text('Show on timeline'), findsOneWidget);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 review without photos (dark) shows the placeholder '
        'and meets the guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      final h = A11yHarness(tester);
      await h.setUp();
      addTearDown(h.tearDown);
      h.size(A11ySize.phone);
      final sample = await h.io(() => SampleConference.build(h.t));
      await tester.pumpWidget(
        h.app(
          ReviewScreen(activityId: sample.reflection.id),
          theme: AppTheme.dark(),
        ),
      );
      await h.settle(20);
      expect(find.byKey(const Key('review-hero-placeholder')), findsOneWidget);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });
  });
}
