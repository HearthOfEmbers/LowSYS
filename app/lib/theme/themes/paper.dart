import 'package:flutter/material.dart';

import '../lowsys_theme.dart';

/// T-5 Paper, "Textbook" (SCOPE.md 7.2): a printed-figure look on warm paper. "Source Serif 4" and "Source Sans 3"
/// (OFL, github.com/google/fonts) are bundled; the platform serif and sans are the fallbacks. Selection yellow is only ever used as a fill behind ink.
const LowsysTheme paperTheme = LowsysTheme(
  id: 'paper',
  name: 'Paper',
  palette: ThemePalette(
    bg: Color(0xFFFBF8F1),
    bgAlt: Color(0xFFF3EEE3),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1ECE1),
    ink: Color(0xFF1F2328),
    inkMuted: Color(0xFF57606A),
    inkFaint: Color(0xFFA8A29A),
    grid: Color(0xFFE3DED3),
    gridMajor: Color(0xFFCFC8BA),
    accent: Color(0xFF2B6CB0),
    accent2: Color(0xFFC0392B),
    steel: Color(0xFF1F2328),
    liquidLight: Color(0xFF9CC9F5),
    liquidHeavy: Color(0xFF2B6CB0),
    froth: Color(0xFFD6E8FA),
    vapor: Color(0xFF9AA0A6),
    hot: Color(0xFFC0392B),
    cold: Color(0xFF2B6CB0),
    ok: Color(0xFF2E7D32),
    warn: Color(0xFFB7791F),
    alarm: Color(0xFFC0392B),
    info: Color(0xFF1F6F8B),
    selection: Color(0xFFF6D365),
    eqCurve: Color(0xFF1F2328),
    opLine: Color(0xFF2B6CB0),
    opLineCmo: Color(0xFF2B6CB0),
    qLine: Color(0xFFB7791F),
    stepLine: Color(0xFFC0392B),
    diagonal: Color(0xFFA8A29A),
    pseudoEq: Color(0xFF57606A),
    marker: Color(0xFF1F2328),
    seriesDash: kSolidDash,
    series: [
      Color(0xFF2B6CB0),
      Color(0xFF1F2328),
      Color(0xFF00796B),
      Color(0xFF6A3D9A),
      Color(0xFFB35C00),
      Color(0xFFC2185B),
    ],
  ),
  type: ThemeTypography(
    display: TypeToken('Source Sans 3', ['Segoe UI Semibold', 'Segoe UI', 'Roboto', 'sans-serif'], weight: FontWeight.w600),
    label: TypeToken('Source Sans 3', ['Segoe UI', 'Roboto', 'sans-serif']),
    number: TypeToken('Source Sans 3', ['Segoe UI', 'Roboto', 'sans-serif'], tabularFigures: true),
    math: TypeToken('STIX Two Math', ['Cambria Math', 'Cambria', 'Times New Roman', 'serif']),
  ),
  column: ColumnStyle(
    vesselStyle: VesselStyle.outline,
    liquidStyle: LiquidStyle.gradient,
    vaporStyle: VaporStyle.dots,
    gaugeStyle: GaugeStyle.numeric,
    strokeWidth: 1.25,
    trayStrokeWidth: 1.0,
  ),
  chart: ChartStyle(lineStyle: LineStyle.ink, dashOn: 6, dashOff: 4),
  effects: EffectStyle(paperGrain: true, figureCaptions: true, alarmBlink: true),
);

/// Text style of the serif captions and margin notes (Source Serif 4 italic, with serif fallbacks).
TextStyle paperSerif(double size, Color color, {bool italic = true}) => TextStyle(
      fontFamily: 'Source Serif 4',
      fontFamilyFallback: const ['Georgia', 'Cambria', 'Times New Roman', 'serif'],
      fontSize: size,
      color: color,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: 1.2,
    );
