import 'package:flutter/material.dart';

import '../lowsys_theme.dart';

/// T-4 Brass, "Steamworks Refinery" (SCOPE.md 7.1): walnut background, parchment ink, brass accents and a riveted
/// bevelled shell with dial gauges. Cinzel, IM Fell English and Courier Prime are bundled (M10, OFL). Charts sit on a parchment inset
/// ([brassParchment], [brassSepia]) with a thin brass frame.
const LowsysTheme brassTheme = LowsysTheme(
  id: 'brass',
  name: 'Brass',
  palette: ThemePalette(
    bg: Color(0xFF1B120B),
    bgAlt: Color(0xFF140D08),
    surface: Color(0xFF2B1D12),
    surfaceAlt: Color(0xFF3A2818),
    ink: Color(0xFFF3E2C7),
    inkMuted: Color(0xFFC8B08A),
    inkFaint: Color(0xFF7A6448),
    grid: Color(0xFF4A3622),
    gridMajor: Color(0xFF6B4F30),
    accent: Color(0xFFC89B3C),
    accent2: Color(0xFFB87333),
    steel: Color(0xFFC89B3C),
    liquidLight: Color(0xFFE8B04B),
    liquidHeavy: Color(0xFF7A3E12),
    froth: Color(0xFFF6D58E),
    vapor: Color(0xFFEDE6DA),
    hot: Color(0xFFE2572B),
    cold: Color(0xFF6FA8A0),
    ok: Color(0xFF8DB255),
    warn: Color(0xFFE8B04B),
    alarm: Color(0xFFD7263D),
    info: Color(0xFF6FA8A0),
    selection: Color(0xFFE8B04B),
    eqCurve: Color(0xFFF0D9A8),
    opLine: Color(0xFFE58A4B),
    opLineCmo: Color(0xFFE58A4B),
    qLine: Color(0xFF9A5B24),
    stepLine: Color(0xFF7FC4BC),
    diagonal: Color(0xFFA08C70),
    pseudoEq: Color(0xFFA89070),
    marker: Color(0xFFF3E2C7),
    seriesDash: kSolidDash,
    series: [
      Color(0xFFE8B04B),
      Color(0xFF6FA8A0),
      Color(0xFFB87333),
      Color(0xFF8DB255),
      Color(0xFFD9C7A3),
      Color(0xFFE2572B),
    ],
  ),
  type: ThemeTypography(
    display: TypeToken('Cinzel', ['Georgia', 'Cambria', 'Palatino Linotype', 'Times New Roman', 'serif'], weight: FontWeight.w700, letterSpacing: 0.3),
    label: TypeToken('IM Fell English', ['Georgia', 'Cambria', 'Palatino Linotype', 'Times New Roman', 'serif']),
    number: TypeToken('Courier Prime', ['Courier New', 'Consolas', 'monospace'], tabularFigures: true),
    math: TypeToken('STIX Two Math', ['Cambria Math', 'Cambria', 'Times New Roman', 'serif']),
  ),
  column: ColumnStyle(
    vesselStyle: VesselStyle.bevel,
    liquidStyle: LiquidStyle.amber,
    vaporStyle: VaporStyle.puffs,
    gaugeStyle: GaugeStyle.dial,
    strokeWidth: 2.0,
    trayStrokeWidth: 1.3,
  ),
  chart: ChartStyle(lineStyle: LineStyle.ink, dashOn: 6, dashOff: 4),
  effects: EffectStyle(rivets: true, needlePhysics: true, alarmBlink: true),
);

/// Parchment inset behind the charts and the sepia ink drawn on it (SCOPE.md 7.1, T-4).
const Color brassParchment = Color(0xFFE9D8B4);
const Color brassSepia = Color(0xFF3B2A1A);
const Color brassFrame = Color(0xFFC89B3C);

/// Damped spring of the gauge needles (zeta 0.6, 0.4 s natural period).
class BrassNeedle {
  double value, velocity = 0;
  BrassNeedle(this.value);

  /// Advances toward [target] by [dt] seconds.
  double step(double target, double dt) {
    const period = 0.4, zeta = 0.6;
    final w = 2 * 3.141592653589793 / period;
    var left = dt;
    while (left > 0) {
      final h = left > 0.01 ? 0.01 : left;
      final acc = w * w * (target - value) - 2 * zeta * w * velocity;
      velocity += acc * h;
      value += velocity * h;
      left -= h;
    }
    return value;
  }
}
