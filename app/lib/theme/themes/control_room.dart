import 'package:flutter/material.dart';

import '../lowsys_theme.dart';

/// T-2 Control Room, "DCS" (SCOPE.md 7.2, ISA-101 rules). The theme's point is that colour means something is
/// wrong: vessels, pipes and normal values are grey, live values are ink, cyan marks what the operator can change.
/// Rajdhani and JetBrains Mono are not bundled (no downloads, docs/DEVIATIONS.md A1): the fallbacks apply.
const LowsysTheme controlRoomTheme = LowsysTheme(
  id: 'controlRoom',
  name: 'Control Room',
  palette: ThemePalette(
    bg: Color(0xFF0B0F14),
    bgAlt: Color(0xFF0F151C),
    surface: Color(0xFF121A22),
    surfaceAlt: Color(0xFF18222C),
    ink: Color(0xFFCFE3F1),
    inkMuted: Color(0xFF7F93A3),
    inkFaint: Color(0xFF3C4A57),
    grid: Color(0xFF1C2733),
    gridMajor: Color(0xFF263442),
    accent: Color(0xFF31C4F3),
    accent2: Color(0xFF9B7BFF),
    steel: Color(0xFF8A99A6),
    liquidLight: Color(0xFF2BD9FE),
    liquidHeavy: Color(0xFF1E6FD9),
    froth: Color(0xFF7FE9FF),
    vapor: Color(0xFFB4F1FF),
    hot: Color(0xFFFF8A3D),
    cold: Color(0xFF31C4F3),
    ok: Color(0xFF34C759),
    warn: Color(0xFFFFCC00),
    alarm: Color(0xFFFF3B30),
    info: Color(0xFF5AC8FA),
    selection: Color(0xFF31C4F3),
    eqCurve: Color(0xFFCFE3F1),
    opLine: Color(0xFF31C4F3),
    opLineCmo: Color(0xFF31C4F3),
    qLine: Color(0xFFFF8A3D),
    stepLine: Color(0xFF2BD9FE),
    diagonal: Color(0xFF3C4A57),
    pseudoEq: Color(0xFF7F93A3),
    marker: Color(0xFFFFFFFF),
    seriesDash: kSolidDash,
    series: [
      Color(0xFF31C4F3),
      Color(0xFFE6E6E6),
      Color(0xFF9B7BFF),
      Color(0xFFFF8A3D),
      Color(0xFF7FD4A8),
      Color(0xFFF2C14E),
    ],
  ),
  type: ThemeTypography(
    display: TypeToken('Rajdhani', ['Bahnschrift', 'Segoe UI Semibold', 'Roboto Condensed', 'sans-serif'], weight: FontWeight.w600, letterSpacing: 0.6),
    label: TypeToken('Rajdhani', ['Bahnschrift', 'Segoe UI', 'Roboto', 'sans-serif'], weight: FontWeight.w500, letterSpacing: 0.3),
    number: TypeToken('JetBrains Mono', ['Share Tech Mono', 'Consolas', 'Cascadia Mono', 'Roboto Mono', 'monospace'], tabularFigures: true),
    math: TypeToken('STIX Two Math', ['Cambria Math', 'Cambria', 'Times New Roman', 'serif']),
  ),
  column: ColumnStyle(
    vesselStyle: VesselStyle.flat,
    liquidStyle: LiquidStyle.gradient,
    vaporStyle: VaporStyle.glowDots,
    gaugeStyle: GaugeStyle.bargraph,
    strokeWidth: 1.6,
    trayStrokeWidth: 1.1,
  ),
  chart: ChartStyle(lineStyle: LineStyle.glow, dashOn: 6, dashOff: 4),
  effects: EffectStyle(alarmBlink: true, glowStrokesMax: 8),
);
