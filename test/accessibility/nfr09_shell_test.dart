import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixtures.dart';
import 'a11y_harness.dart';

/// NFR-09 accessibility of the navigation shell and its four destinations,
/// with the bottom bar (phone) and the side rail (tablet and Windows)
/// (FR-UI-11, ADR-052) [P1-39].
void main() {
  Future<A11yHarness> open(
    WidgetTester tester,
    ShellDestination initial, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    ThemeData? theme,
    bool sample = true,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(size, textScale: textScale);
    if (sample) await h.io(() => SampleConference.build(h.t));
    await tester.pumpWidget(h.app(AppShell(initial: initial), theme: theme));
    await h.settle();
    return h;
  }

  group('NFR-09 navigation shell', () {
    for (final d in ShellDestination.values) {
      for (final size in A11ySize.values) {
        for (final (themeName, theme) in [
          ('light', AppTheme.light()),
          ('dark', AppTheme.dark()),
        ]) {
          testWidgets('NFR-09 ${d.label} on ${size.name} ($themeName) meets '
              'tap target, label and contrast guidelines', (tester) async {
            final handle = tester.ensureSemantics();
            await open(tester, d, size: size, theme: theme);
            await expectMeetsGuidelines(tester);
            handle.dispose();
          });
        }

        testWidgets('NFR-09 ${d.label} at 200% text on ${size.name} has no '
            'overflow', (tester) async {
          final h = await open(tester, d, size: size, textScale: 2);
          await scrollThrough(tester, h);
        });
      }
    }

    testWidgets('NFR-09 Record with no conference at 200% text on a phone '
        'has no overflow', (tester) async {
      final h = await open(
        tester,
        ShellDestination.record,
        textScale: 2,
        sample: false,
      );
      expect(find.byKey(const Key('record-no-conference')), findsOneWidget);
      await scrollThrough(tester, h);
    });

    testWidgets('NFR-09 every destination has a label for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, ShellDestination.conferences);
      for (final d in ShellDestination.values) {
        expect(
          find.bySemanticsLabel(RegExp('^${d.label}')),
          findsWidgets,
          reason: d.label,
        );
      }
      handle.dispose();
    });
  });
}
