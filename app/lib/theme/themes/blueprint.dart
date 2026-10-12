import 'package:flutter/material.dart';

import '../lowsys_theme.dart';

/// T-1 Blueprint, "Drafting Table" (SCOPE.md 7.2). Fonts are listed with fallbacks; drop the OFL
/// font files into assets/fonts to bundle them (docs/DEVIATIONS.md A1).
const LowsysTheme blueprintTheme = LowsysTheme(
  id: 'blueprint',
  name: 'Blueprint',
  palette: ThemePalette(
    bg: Color(0xFF0E3A66),
    bgAlt: Color(0xFF0B2F54),
    surface: Color(0xFF12457A),
    surfaceAlt: Color(0xFF175089),
    ink: Color(0xFFEAF4FF),
    inkMuted: Color(0xFFA9C8E8),
    inkFaint: Color(0xFF6F95BD),
    grid: Color(0xFF2F6B9E),
    gridMajor: Color(0xFF4C87BA),
    accent: Color(0xFFFFD166),
    accent2: Color(0xFFFF9F6E),
    steel: Color(0xFFEAF4FF),
    liquidLight: Color(0xFF9BE7FF),
    liquidHeavy: Color(0xFF3FA7D6),
    froth: Color(0xFFCFF3FF),
    vapor: Color(0x8CFFFFFF),
    hot: Color(0xFFFF9F6E),
    cold: Color(0xFF9BE7FF),
    ok: Color(0xFF7CE0A3),
    warn: Color(0xFFFFD166),
    alarm: Color(0xFFFF6B6B),
    info: Color(0xFF9BE7FF),
    selection: Color(0xFFFFD166),
    eqCurve: Color(0xFFEAF4FF),
    opLine: Color(0xFFFFD166),
    opLineCmo: Color(0xFFFFD166),
    qLine: Color(0xFFFF9F6E),
    stepLine: Color(0xFF9BE7FF),
    diagonal: Color(0xFF6F95BD),
    pseudoEq: Color(0xFFA9C8E8),
    marker: Color(0xFFFFD166),
  ),
  type: ThemeTypography(
    display: TypeToken('Architects Daughter', ['Ink Free', 'Segoe Print', 'casual', 'cursive'], letterSpacing: 0.4),
    label: TypeToken('Architects Daughter', ['Ink Free', 'Segoe Print', 'casual', 'cursive'], letterSpacing: 0.2),
    number: TypeToken('Share Tech Mono', ['Consolas', 'Cascadia Mono', 'Roboto Mono', 'monospace'], tabularFigures: true),
    math: TypeToken('STIX Two Math', ['Cambria Math', 'Cambria', 'Times New Roman', 'serif']),
  ),
  column: ColumnStyle(
    vesselStyle: VesselStyle.outline,
    liquidStyle: LiquidStyle.hatch,
    vaporStyle: VaporStyle.circles,
    gaugeStyle: GaugeStyle.numeric,
  ),
  chart: ChartStyle(lineStyle: LineStyle.pen),
  effects: EffectStyle(blueprintGrid: true, paperGrain: true, vignette: true, figureCaptions: true),
);
