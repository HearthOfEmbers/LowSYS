import 'package:flutter/material.dart';

import 'lowsys_theme.dart';

/// Maps theme tokens onto a Material [ThemeData] so standard widgets match.
ThemeData materialThemeFor(LowsysTheme t) {
  final p = t.palette;
  final scheme = ColorScheme.dark(
    primary: p.accent,
    onPrimary: p.bgAlt,
    secondary: p.accent2,
    onSecondary: p.bgAlt,
    surface: p.surface,
    onSurface: p.ink,
    error: p.alarm,
    onError: p.bgAlt,
    outline: p.gridMajor,
    surfaceContainerHighest: p.surfaceAlt,
  );
  TextStyle lab(double s, {FontWeight? w}) => t.type.label.style(s, p.ink, weight: w);
  final text = TextTheme(
    displayLarge: t.type.display.style(32, p.ink),
    titleLarge: t.type.display.style(20, p.ink),
    titleMedium: lab(16),
    titleSmall: lab(14),
    bodyLarge: lab(16),
    bodyMedium: lab(14),
    bodySmall: lab(12),
    labelLarge: lab(14),
    labelMedium: lab(13),
    labelSmall: lab(12),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bgAlt,
    textTheme: text,
    dividerColor: p.gridMajor,
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.gridMajor,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.18),
      trackHeight: 2.5,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      valueIndicatorTextStyle: t.type.number.style(12, p.bgAlt),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.ink, minimumSize: const Size(48, 48)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: BorderSide(color: p.gridMajor)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      textStyle: lab(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: BorderSide(color: p.gridMajor)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.bgAlt, border: Border.all(color: p.gridMajor)),
      textStyle: lab(12),
    ),
  );
}
