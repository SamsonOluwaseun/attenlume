import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/conferences/activity_detail_sheet.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/conferences/conference_wizard_screen.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixtures.dart';
import 'a11y_harness.dart';

/// NFR-09 accessibility of welcome, My conferences, the conference wizard,
/// conference home, the start activity sheet and activity details [P1-26].
/// Returns the screen to show for the sample conference.
typedef Screen = Widget Function(SampleConference s);

void main() {
  final screens = <String, Screen>{
    'welcome': (_) => const WelcomeScreen(),
    'My conferences': (_) => const ConferenceListScreen(),
    'conference wizard': (_) => const ConferenceWizardScreen(),
    'conference wizard (edit)': (s) =>
        ConferenceWizardScreen(conferenceId: s.conference.id),
    'conference home': (s) => ConferenceHomeScreen(
      conferenceId: s.conference.id,
      openRecorder: (_, _) async {},
    ),
  };

  Future<(A11yHarness, SampleConference)> open(
    WidgetTester tester,
    Screen screen, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(size, textScale: textScale);
    final sample = await h.io(() => SampleConference.build(h.t));
    await tester.pumpWidget(h.app(screen(sample), theme: theme));
    await h.settle();
    return (h, sample);
  }

  group('NFR-09 conference screens', () {
    screens.forEach((name, screen) {
      for (final (themeName, theme) in [
        ('light', AppTheme.light()),
        ('dark', AppTheme.dark()),
      ]) {
        testWidgets('NFR-09 $name ($themeName) meets tap target, label and '
            'contrast guidelines', (tester) async {
          final handle = tester.ensureSemantics();
          await open(tester, screen, theme: theme);
          await expectMeetsGuidelines(tester);
          handle.dispose();
        });
      }

      for (final size in A11ySize.values) {
        testWidgets('NFR-09 $name at 200% text on ${size.name} has no '
            'overflow', (tester) async {
          final (h, _) = await open(tester, screen, size: size, textScale: 2);
          await scrollThrough(tester, h);
        });
      }
    });

    testWidgets('NFR-09 conference home marks the conference name as a '
        'heading', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, screens['conference home']!);
      final headers = tester.semantics
          .simulatedAccessibilityTraversal()
          .where((n) => n.flagsCollection.isHeader)
          .map((n) => n.label)
          .toList();
      expect(headers, contains('Samlytics Conference 2026'));
      handle.dispose();
    });
  });

  group('NFR-09 conference sheets', () {
    Future<void> startSheet(WidgetTester tester, {double textScale = 1}) async {
      final (h, s) = await open(
        tester,
        screens['conference home']!,
        textScale: textScale,
      );
      final context = tester.element(find.byType(ConferenceHomeScreen));
      // ignore: unawaited_futures
      StartActivitySheet.show(context, conferenceId: s.conference.id);
      await h.settle();
    }

    Future<void> detailSheet(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      final h = A11yHarness(tester);
      await h.setUp();
      addTearDown(h.tearDown);
      h.size(A11ySize.phone, textScale: textScale);
      final summary = await h.io(() async {
        final s = await SampleConference.build(h.t);
        return (await h.t.activities.getSummary(s.keynote.id))!;
      });
      await tester.pumpWidget(
        h.app(
          Scaffold(
            body: ActivityDetailSheet(
              summary: summary,
              timezone: 'Europe/London',
            ),
          ),
        ),
      );
      await h.settle();
    }

    testWidgets('NFR-09 start activity sheet meets the guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await startSheet(tester);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 start activity sheet at 200% text has no overflow', (
      tester,
    ) async {
      await startSheet(tester, textScale: 2);
    });

    testWidgets('NFR-09 activity details meet the guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await detailSheet(tester);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 activity details at 200% text have no overflow', (
      tester,
    ) async {
      await detailSheet(tester, textScale: 2);
      await scrollThrough(tester, A11yHarness(tester));
    });
  });
}
