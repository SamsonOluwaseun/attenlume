import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const textMin = 4.5;
const largeTextMin = 3.0;
const graphicMin = 3.0;

void main() {
  group('NFR-09 theme colour pairs meet contrast rules', () {
    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('NFR-09 $name theme', (tester) async {
        late ThemeData t;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                t = Theme.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        final s = t.colorScheme;
        final x = t.extension<AttenlumeColors>()!;

        final pairs = <(String, Color, Color, double)>[
          ('ink on surface', s.onSurface, s.surface, textMin),
          ('ink on surface-raised', s.onSurface, s.surfaceContainer, textMin),
          ('ink-muted on surface', s.onSurfaceVariant, s.surface, textMin),
          (
            'ink-muted on surface-raised',
            s.onSurfaceVariant,
            s.surfaceContainer,
            textMin,
          ),
          (
            'ink on brand-tint',
            s.onPrimaryContainer,
            s.primaryContainer,
            textMin,
          ),
          ('on-brand-large on brand', s.onPrimary, s.primary, largeTextMin),
          ('on-brand on brand', s.onSecondary, s.secondary, textMin),
          ('danger on surface', s.error, s.surface, textMin),
          ('on-danger on danger', s.onError, s.error, textMin),
          ('link on surface', x.link, s.surface, textMin),
          ('ink on warning-fill', s.onSurface, x.warningFill, textMin),
          ('on-success on success', x.onSuccess, x.success, textMin),
          ('line-strong on surface', s.outline, s.surface, graphicMin),
          ('focus on surface', x.focus, s.surface, graphicMin),
          (
            'on-live-surface on live-surface',
            x.onLiveSurface,
            x.liveSurface,
            textMin,
          ),
          (
            'on-live-surface-muted on live-surface',
            x.onLiveSurfaceMuted,
            x.liveSurface,
            textMin,
          ),
          (
            'on-live-surface on live-raised',
            x.onLiveSurface,
            x.liveRaised,
            textMin,
          ),
          ('live on live-surface', x.live, x.liveSurface, textMin),
          ('on-live on live', x.onLive, x.live, textMin),
          ('stop on live-surface', x.stop, x.liveSurface, graphicMin),
        ];

        final failures = [
          for (final (label, fg, bg, min) in pairs)
            if (contrast(fg, bg) < min)
              '$label: ${contrast(fg, bg).toStringAsFixed(2)} < $min',
        ];
        expect(failures, isEmpty);
      });
    }
  });

  test('NFR-09 primary button labels are large enough for cream on blue', () {
    final style = AppTheme.light().filledButtonTheme.style!.textStyle!.resolve(
      {},
    )!;
    expect(style.fontSize, greaterThanOrEqualTo(19));
    expect(style.fontWeight!.value, greaterThanOrEqualTo(600));
  });

  test('NFR-09 recording screen is navy in both themes', () {
    final live = AppTheme.live();
    expect(live.scaffoldBackgroundColor, TokenColors.light.liveSurface);
    expect(live.scaffoldBackgroundColor, TokenColors.dark.liveSurface);
  });
}
