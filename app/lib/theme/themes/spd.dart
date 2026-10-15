import 'package:flutter/material.dart';

import '../lowsys_theme.dart';

/// T-6 SPD, "Royal Crimson": oxblood and burgundy surfaces, gold accents and warm ivory ink. Cinzel for the display
/// face, Source Serif 4 for labels, JetBrains Mono for numbers (all bundled). Alarm is a vivid hot magenta-pink and ok
/// a pale mint, so both stand apart from the red background and from each other (U3). The six series colours are
/// also told apart by dash pattern. Charts keep the dark plot fill with a soft glow on the lines.
const LowsysTheme spdTheme = LowsysTheme(
  id: 'spd',
  name: 'SPD',
  palette: ThemePalette(
    bg: Color(0xFF3A0F17),
    bgAlt: Color(0xFF2A0A10),
    surface: Color(0xFF531824),
    surfaceAlt: Color(0xFF6A2331),
    ink: Color(0xFFF7EBD2),
    inkMuted: Color(0xFFDDC49C),
    inkFaint: Color(0xFF9E7A6A),
    grid: Color(0xFF6B2C39),
    gridMajor: Color(0xFF8F4A55),
    accent: Color(0xFFE7B94C),
    accent2: Color(0xFFD4A05A),
    steel: Color(0xFFD9B35A),
    liquidLight: Color(0xFFF0C45A),
    liquidHeavy: Color(0xFFB3394A),
    froth: Color(0xFFF8E3A8),
    vapor: Color(0xFFF1E6D2),
    hot: Color(0xFFFF8A4D),
    cold: Color(0xFF7FC6D6),
    ok: Color(0xFF9BE8BE),
    warn: Color(0xFFFFA03A),
    alarm: Color(0xFFFF2E7E),
    info: Color(0xFF7FC6D6),
    selection: Color(0xFFE7B94C),
    eqCurve: Color(0xFFF7EBD2),
    opLine: Color(0xFFE7B94C),
    opLineCmo: Color(0xFFE7B94C),
    qLine: Color(0xFFFF8A4D),
    stepLine: Color(0xFF7FC6D6),
    diagonal: Color(0xFFB08C78),
    pseudoEq: Color(0xFFC9AA8C),
    marker: Color(0xFFF7EBD2),
    seriesDash: [
      [],
      [7, 3],
      [2, 3],
      [8, 3, 2, 3],
      [4, 2],
      [1.5, 2.5],
    ],
    series: [
      Color(0xFFE7B94C),
      Color(0xFF5CC8C0),
      Color(0xFFF7EBD2),
      Color(0xFFF28BA8),
      Color(0xFF8FB4F0),
      Color(0xFFF08A3E),
    ],
  ),
  type: ThemeTypography(
    display: TypeToken('Cinzel', ['Georgia', 'Cambria', 'Palatino Linotype', 'Times New Roman', 'serif'], weight: FontWeight.w700, letterSpacing: 0.4),
    label: TypeToken('Source Serif 4', ['Georgia', 'Cambria', 'Palatino Linotype', 'Times New Roman', 'serif']),
    number: TypeToken('JetBrains Mono', ['Consolas', 'Courier New', 'monospace'], tabularFigures: true),
    math: TypeToken('STIX Two Math', ['Cambria Math', 'Cambria', 'Times New Roman', 'serif']),
  ),
  column: ColumnStyle(
    vesselStyle: VesselStyle.flat,
    liquidStyle: LiquidStyle.gradient,
    vaporStyle: VaporStyle.glowDots,
    gaugeStyle: GaugeStyle.bargraph,
    strokeWidth: 1.8,
    trayStrokeWidth: 1.2,
  ),
  chart: ChartStyle(lineStyle: LineStyle.glow, dashOn: 6, dashOff: 4),
  effects: EffectStyle(vignette: true, alarmBlink: true, glowStrokesMax: 4),
);
