import 'package:flutter/material.dart';

/// Every colour token of SCOPE.md 7.1. Themes are pure data; painters read only tokens.
@immutable
class ThemePalette {
  final Color bg, bgAlt, surface, surfaceAlt, ink, inkMuted, inkFaint, grid, gridMajor;
  final Color accent, accent2, steel, liquidLight, liquidHeavy, froth, vapor, hot, cold;
  final Color ok, warn, alarm, info, selection;
  final Color eqCurve, opLine, opLineCmo, qLine, stepLine, diagonal, pseudoEq, marker;

  /// Six trend and multi-variable colours (SCOPE.md 7.1, added for the M3 Trends tab).
  final List<Color> series;

  const ThemePalette({
    required this.bg,
    required this.bgAlt,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.grid,
    required this.gridMajor,
    required this.accent,
    required this.accent2,
    required this.steel,
    required this.liquidLight,
    required this.liquidHeavy,
    required this.froth,
    required this.vapor,
    required this.hot,
    required this.cold,
    required this.ok,
    required this.warn,
    required this.alarm,
    required this.info,
    required this.selection,
    required this.eqCurve,
    required this.opLine,
    required this.opLineCmo,
    required this.qLine,
    required this.stepLine,
    required this.diagonal,
    required this.pseudoEq,
    required this.marker,
    required this.series,
  });

  /// Composition colour: light component end to heavy component end.
  Color composition(double xHeavy) => Color.lerp(liquidLight, liquidHeavy, xHeavy.clamp(0.0, 1.0))!;
}

/// One typography token: family with fallbacks for platforms where the font is not bundled.
@immutable
class TypeToken {
  final String family;
  final List<String> fallback;
  final FontWeight weight;
  final double letterSpacing;
  final bool tabularFigures;
  const TypeToken(this.family, this.fallback, {this.weight = FontWeight.w400, this.letterSpacing = 0, this.tabularFigures = false});

  TextStyle style(double size, Color color, {FontWeight? weight, FontStyle? fontStyle}) => TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        color: color,
        fontWeight: weight ?? this.weight,
        letterSpacing: letterSpacing,
        fontStyle: fontStyle,
        fontFeatures: tabularFigures ? const [FontFeature.tabularFigures()] : null,
        height: 1.15,
      );
}

@immutable
class ThemeTypography {
  final TypeToken display, label, number, math;
  const ThemeTypography({required this.display, required this.label, required this.number, required this.math});
}

enum VesselStyle { outline, flat, bevel, vector }

enum LiquidStyle { hatch, gradient, glyph, amber }

enum VaporStyle { circles, glowDots, glyphs, puffs, dots }

enum GaugeStyle { numeric, bargraph, dial }

enum LineStyle { pen, glow, vector, ink }

@immutable
class ColumnStyle {
  final VesselStyle vesselStyle;
  final LiquidStyle liquidStyle;
  final VaporStyle vaporStyle;
  final GaugeStyle gaugeStyle;
  final double strokeWidth, trayStrokeWidth;

  /// Vapour particle cap on screen (High / Low quality).
  final int maxParticlesHigh, maxParticlesLow;
  const ColumnStyle({
    required this.vesselStyle,
    required this.liquidStyle,
    required this.vaporStyle,
    required this.gaugeStyle,
    this.strokeWidth = 2,
    this.trayStrokeWidth = 1.4,
    this.maxParticlesHigh = 400,
    this.maxParticlesLow = 120,
  });
}

@immutable
class ChartStyle {
  final LineStyle lineStyle;

  /// Grid spacing in axis units.
  final double gridMinor, gridMajor;
  final double dashOn, dashOff;
  const ChartStyle({required this.lineStyle, this.gridMinor = 0.05, this.gridMajor = 0.1, this.dashOn = 7, this.dashOff = 5});
}

@immutable
class EffectStyle {
  final bool blueprintGrid, paperGrain, scanlines, bloom, vignette, rivets, needlePhysics, figureCaptions, alarmBlink;
  final int glowStrokesMax;
  const EffectStyle({
    this.blueprintGrid = false,
    this.paperGrain = false,
    this.scanlines = false,
    this.bloom = false,
    this.vignette = false,
    this.rivets = false,
    this.needlePhysics = false,
    this.figureCaptions = false,
    this.alarmBlink = false,
    this.glowStrokesMax = 0,
  });
}

/// A complete theme: tokens plus painter style switches. No theme has its own widgets or layout.
@immutable
class LowsysTheme {
  final String id, name;
  final ThemePalette palette;
  final ThemeTypography type;
  final ColumnStyle column;
  final ChartStyle chart;
  final EffectStyle effects;
  const LowsysTheme({
    required this.id,
    required this.name,
    required this.palette,
    required this.type,
    required this.column,
    required this.chart,
    required this.effects,
  });
}

/// Provides the active theme to painters and widgets.
class LowsysThemeScope extends InheritedWidget {
  final LowsysTheme theme;
  const LowsysThemeScope({super.key, required this.theme, required super.child});

  static LowsysTheme of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<LowsysThemeScope>();
    assert(s != null, 'No LowsysThemeScope above this context');
    return s!.theme;
  }

  @override
  bool updateShouldNotify(LowsysThemeScope old) => old.theme != theme;
}
