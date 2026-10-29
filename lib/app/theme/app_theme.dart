import 'package:flutter/material.dart';

import 'tokens.dart';

/// Colours and numeral styles that Material's [ColorScheme] and [TextTheme]
/// have no slot for. Read with `Theme.of(context).extension<AttenlumeColors>()!`.
@immutable
class AttenlumeColors extends ThemeExtension<AttenlumeColors> {
  const AttenlumeColors({
    required this.live,
    required this.onLive,
    required this.liveSurface,
    required this.liveRaised,
    required this.onLiveSurface,
    required this.onLiveSurfaceMuted,
    required this.stop,
    required this.success,
    required this.onSuccess,
    required this.warningFill,
    required this.onBrandLarge,
    required this.surfaceBrand,
    required this.link,
    required this.focus,
    required this.timer,
    required this.stat,
  });

  factory AttenlumeColors.from(TokenColors c) => AttenlumeColors(
    live: c.live,
    onLive: c.onLive,
    liveSurface: c.liveSurface,
    liveRaised: c.liveRaised,
    onLiveSurface: c.onLiveSurface,
    onLiveSurfaceMuted: c.onLiveSurfaceMuted,
    stop: c.stop,
    success: c.success,
    onSuccess: c.onSuccess,
    warningFill: c.warningFill,
    onBrandLarge: c.onBrandLarge,
    surfaceBrand: c.surfaceBrand,
    link: c.link,
    focus: c.focus,
    timer: _style(TokenType.timer)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    stat: _style(TokenType.stat),
  );

  final Color live;
  final Color onLive;
  final Color liveSurface;
  final Color liveRaised;
  final Color onLiveSurface;
  final Color onLiveSurfaceMuted;
  final Color stop;
  final Color success;
  final Color onSuccess;
  final Color warningFill;
  final Color onBrandLarge;
  final Color surfaceBrand;
  final Color link;
  final Color focus;

  /// Elapsed time on the recording screen, with tabular figures.
  final TextStyle timer;

  /// Totals on conference home and Storage Manager.
  final TextStyle stat;

  @override
  AttenlumeColors copyWith({
    Color? live,
    Color? onLive,
    Color? liveSurface,
    Color? liveRaised,
    Color? onLiveSurface,
    Color? onLiveSurfaceMuted,
    Color? stop,
    Color? success,
    Color? onSuccess,
    Color? warningFill,
    Color? onBrandLarge,
    Color? surfaceBrand,
    Color? link,
    Color? focus,
    TextStyle? timer,
    TextStyle? stat,
  }) => AttenlumeColors(
    live: live ?? this.live,
    onLive: onLive ?? this.onLive,
    liveSurface: liveSurface ?? this.liveSurface,
    liveRaised: liveRaised ?? this.liveRaised,
    onLiveSurface: onLiveSurface ?? this.onLiveSurface,
    onLiveSurfaceMuted: onLiveSurfaceMuted ?? this.onLiveSurfaceMuted,
    stop: stop ?? this.stop,
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    warningFill: warningFill ?? this.warningFill,
    onBrandLarge: onBrandLarge ?? this.onBrandLarge,
    surfaceBrand: surfaceBrand ?? this.surfaceBrand,
    link: link ?? this.link,
    focus: focus ?? this.focus,
    timer: timer ?? this.timer,
    stat: stat ?? this.stat,
  );

  @override
  AttenlumeColors lerp(AttenlumeColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AttenlumeColors(
      live: c(live, other.live),
      onLive: c(onLive, other.onLive),
      liveSurface: c(liveSurface, other.liveSurface),
      liveRaised: c(liveRaised, other.liveRaised),
      onLiveSurface: c(onLiveSurface, other.onLiveSurface),
      onLiveSurfaceMuted: c(onLiveSurfaceMuted, other.onLiveSurfaceMuted),
      stop: c(stop, other.stop),
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      warningFill: c(warningFill, other.warningFill),
      onBrandLarge: c(onBrandLarge, other.onBrandLarge),
      surfaceBrand: c(surfaceBrand, other.surfaceBrand),
      link: c(link, other.link),
      focus: c(focus, other.focus),
      timer: TextStyle.lerp(timer, other.timer, t)!,
      stat: TextStyle.lerp(stat, other.stat, t)!,
    );
  }
}

/// Light, dark and live (recording screen) themes built from
/// `design/tokens.json` via the generated `tokens.dart`.
abstract final class AppTheme {
  static ThemeData light() => _build(TokenColors.light, Brightness.light);

  static ThemeData dark() => _build(TokenColors.dark, Brightness.dark);

  /// The recording screen is navy in both light and dark modes
  /// (DESIGN_GUIDE "house lights down"). Lime only shows live status.
  static ThemeData live() {
    const c = TokenColors.dark;
    final base = _build(c, Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: c.liveSurface,
      colorScheme: base.colorScheme.copyWith(
        surface: c.liveSurface,
        onSurface: c.onLiveSurface,
        onSurfaceVariant: c.onLiveSurfaceMuted,
        surfaceContainer: c.liveRaised,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: c.onLiveSurface,
        displayColor: c.onLiveSurface,
      ),
      iconTheme: IconThemeData(color: c.onLiveSurface, size: TokenSize.iconMd),
    );
  }

  static ThemeData _build(TokenColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrandLarge,
      primaryContainer: c.brandTint,
      onPrimaryContainer: c.ink,
      secondary: c.brand,
      onSecondary: c.onBrand,
      error: c.danger,
      onError: c.onDanger,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainer: c.surfaceRaised,
      outline: c.lineStrong,
      outlineVariant: c.line,
    );

    final textTheme = TextTheme(
      displaySmall: _style(TokenType.display),
      headlineSmall: _style(TokenType.title),
      titleLarge: _style(TokenType.heading),
      bodyLarge: _style(TokenType.body),
      bodyMedium: _style(TokenType.bodySmall),
      labelLarge: _style(TokenType.label),
      labelSmall: _style(TokenType.caption),
    ).apply(bodyColor: c.ink, displayColor: c.ink);

    const mdShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusMd)),
    );
    const minSize = Size(TokenSize.tapMin, TokenSize.tapMin);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: TokenType.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      focusColor: c.focus.withValues(alpha: 0.24),
      cardTheme: CardThemeData(
        color: c.surfaceRaised,
        elevation: 0,
        shape: mdShape,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: mdShape,
          minimumSize: minSize,
          // Cream on blue only meets contrast as large text (19px Semibold+).
          textStyle: _style(TokenType.label).copyWith(fontSize: 19),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: mdShape,
          minimumSize: minSize,
          side: BorderSide(color: c.lineStrong),
          // ink, not Material's default brand blue, which is 3.15:1 on
          // cream and fails for 15px labels (NFR-09).
          foregroundColor: c.ink,
          textStyle: _style(TokenType.label),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minSize,
          foregroundColor: c.link,
          textStyle: _style(TokenType.label),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusSm),
          ),
          borderSide: BorderSide(color: c.lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusSm),
          ),
          borderSide: BorderSide(color: c.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusSm),
          ),
          borderSide: BorderSide(color: c.focus, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
      extensions: [AttenlumeColors.from(c)],
    );
  }
}

TextStyle _style(TokenTextStyle t) => TextStyle(
  fontFamily: TokenType.fontFamily,
  fontSize: t.fontSize,
  height: t.lineHeight / t.fontSize,
  fontWeight: t.fontWeight,
  letterSpacing: t.letterSpacing,
);
