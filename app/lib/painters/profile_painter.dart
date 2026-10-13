import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';

enum ProfileKind { dp, flood, weep, holdup, composition, temperature, vapour, liquid }

extension ProfileKindLabel on ProfileKind {
  String get label => switch (this) {
        ProfileKind.dp => 'dP',
        ProfileKind.flood => 'Flood',
        ProfileKind.weep => 'Weeping',
        ProfileKind.holdup => 'Holdup',
        ProfileKind.composition => 'x',
        ProfileKind.temperature => 'T',
        ProfileKind.vapour => 'V',
        ProfileKind.liquid => 'L',
      };
}

/// The V and L profiles of the tier the learner has just left, drawn as ticks on the V and L charts (PHYSICS.md 14.5).
class TierGhost {
  final String fromTier;
  final List<double> vapour, liquid;
  const TierGhost(this.fromTier, this.vapour, this.liquid);
}

/// Plot area for the profile chart (shared with tap picking).
Rect profilePlotRect(Size size) => Rect.fromLTRB(34, 22, size.width - 12, size.height - 34);

/// Per-tray profile as horizontal bars, trays from the top (PHYSICS.md 14.5; SCOPE.md 8 M2 Profiles tab).
class ProfilePainter extends CustomPainter {
  final ValueListenable<SimSnapshot?> snapshot;
  final ValueListenable<int?> selected;
  final ValueListenable<UnitSystem> units;
  final ProfileKind kind;
  final LowsysTheme theme;
  final ValueListenable<TierGhost?>? ghost;

  ProfilePainter({required this.snapshot, required this.selected, required this.units, required this.kind, required this.theme, this.ghost})
      : super(repaint: Listenable.merge([snapshot, selected, units, ?ghost]));

  @override
  void paint(Canvas canvas, Size size) {
    final s = snapshot.value;
    if (s == null) return;
    final p = theme.palette;
    final num = theme.type.number;
    final lab = theme.type.label;
    final u = units.value;
    final st = s.stages;
    final N = s.layout.nTrays;
    final plot = profilePlotRect(size);
    final full = s.hydraulics == HydraulicsMode.full;
    // values per tray and the scale
    final vals = List<double>.filled(N + 1, 0);
    final vals2 = List<double>.filled(N + 1, 0);
    String unit;
    double axisMax;
    double axisMin = 0;
    double Function(double) show = (v) => v;
    switch (kind) {
      case ProfileKind.dp:
        unit = u.symbol(Quantity.pressureDelta);
        for (var j = 1; j <= N; j++) {
          vals[j] = st.dp[j];
          vals2[j] = st.dpDry[j];
        }
        show = (v) => u.fromSI(Quantity.pressureDelta, v);
        axisMax = math.max(200.0, (vals.fold(0.0, math.max) * 1.15));
      case ProfileKind.flood:
        unit = '% of limit';
        for (var j = 1; j <= N; j++) {
          vals[j] = 100 * math.max(st.jetFlood[j], st.frothFill[j]);
          vals2[j] = 100 * st.dcFlood[j];
        }
        axisMax = math.max(120.0, vals.fold(0.0, math.max) * 1.1);
      case ProfileKind.weep:
        unit = '% of inlet liquid';
        for (var j = 1; j <= N; j++) {
          vals[j] = 100 * st.weepFrac[j];
        }
        axisMax = 100;
      case ProfileKind.holdup:
        unit = u.symbol(Quantity.molarAmount);
        for (var j = 1; j <= N; j++) {
          vals[j] = st.holdup[j];
        }
        show = (v) => u.fromSI(Quantity.molarAmount, v);
        axisMax = math.max(1.0, vals.fold(0.0, math.max) * 1.15);
      case ProfileKind.composition:
        unit = 'mole fraction ${s.components.first}';
        for (var j = 1; j <= N; j++) {
          vals[j] = st.x[j * st.nc];
          vals2[j] = st.y[j * st.nc];
        }
        axisMax = 1;
      case ProfileKind.temperature:
        unit = u.symbol(Quantity.temperature);
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var j = 1; j <= N; j++) {
          vals[j] = st.t[j];
          if (vals[j].isFinite) {
            if (vals[j] < lo) lo = vals[j];
            if (vals[j] > hi) hi = vals[j];
          }
        }
        if (!lo.isFinite) {
          lo = 300;
          hi = 400;
        }
        // axis in kelvin steps of 10 so the labels are round in either unit system
        axisMin = (lo - 5).floorToDouble();
        axisMax = math.max(axisMin + 10, (hi + 5).ceilToDouble());
        show = (v) => u.fromSI(Quantity.temperature, v);
      case ProfileKind.vapour:
      case ProfileKind.liquid:
        final isV = kind == ProfileKind.vapour;
        unit = u.symbol(Quantity.molarFlow);
        final g = ghost?.value;
        for (var j = 1; j <= N; j++) {
          vals[j] = isV ? st.vaporUp[j] : st.liquidDown[j];
          final gv = g == null ? null : (isV ? g.vapour : g.liquid);
          vals2[j] = gv != null && j < gv.length ? gv[j] : double.nan;
        }
        show = (v) => u.fromSI(Quantity.molarFlow, v);
        axisMax = math.max(1e-6, vals.fold(0.0, math.max) * 1.15);
        for (final v in vals2) {
          if (v.isFinite && v * 1.15 > axisMax) axisMax = v * 1.15;
        }
    }
    canvas.drawRect(plot, Paint()..color = p.bgAlt.withValues(alpha: 0.55));
    // grid
    final grid = Paint()
      ..color = p.grid.withValues(alpha: 0.6)
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 4; i++) {
      final x = plot.left + plot.width * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      final v = show(axisMin + (axisMax - axisMin) * i / 4);
      final txt = v >= 100 ? v.toStringAsFixed(0) : (v >= 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(2));
      _text(canvas, txt, Offset(x, plot.bottom + 3), num.style(12, p.inkMuted), Alignment.topCenter);
    }
    canvas.drawRect(
        plot,
        Paint()
          ..color = p.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    _text(canvas, unit, Offset(plot.center.dx, plot.bottom + 20), lab.style(12, p.inkMuted), Alignment.topCenter);
    if (kind == ProfileKind.flood) {
      final x100 = plot.left + plot.width * 100 / axisMax;
      canvas.drawLine(
          Offset(x100, plot.top),
          Offset(x100, plot.bottom),
          Paint()
            ..color = p.alarm
            ..strokeWidth = 1.4);
      _text(canvas, '100 %', Offset(x100, plot.top - 2), lab.style(12, p.alarm), Alignment.bottomCenter);
    }
    if ((kind == ProfileKind.dp || kind == ProfileKind.flood || kind == ProfileKind.weep) && !full) {
      _text(canvas, 'ideal hydraulics: no tray hydraulics (switch to Full)', plot.center, lab.style(13, p.warn), Alignment.center, maxWidth: plot.width - 12);
      return;
    }
    final rowH = plot.height / N;
    final barH = math.max(1.2, math.min(rowH * 0.7, 12.0));
    for (var j = 1; j <= N; j++) {
      final cy = plot.top + (j - 0.5) * rowH;
      final w = ((vals[j] - axisMin) / (axisMax - axisMin)).clamp(0.0, 1.0) * plot.width;
      Color c = p.liquidLight;
      if (kind == ProfileKind.flood) c = vals[j] >= 100 ? p.alarm : (vals[j] >= 90 ? p.warn : p.liquidLight);
      if (kind == ProfileKind.weep) c = p.accent2;
      canvas.drawRect(Rect.fromLTWH(plot.left, cy - barH / 2, w, barH), Paint()..color = c.withValues(alpha: 0.85));
      if (kind == ProfileKind.temperature) c = p.hot;
      if ((kind == ProfileKind.vapour || kind == ProfileKind.liquid) && vals2[j].isFinite) {
        final w2 = (vals2[j] / axisMax).clamp(0.0, 1.0) * plot.width;
        canvas.drawLine(
            Offset(plot.left + w2, cy - barH / 2 - 1),
            Offset(plot.left + w2, cy + barH / 2 + 1),
            Paint()
              ..color = p.accent
              ..strokeWidth = 2);
      }
      if (kind == ProfileKind.dp || kind == ProfileKind.flood || kind == ProfileKind.composition) {
        final w2 = (vals2[j] / axisMax).clamp(0.0, 1.0) * plot.width;
        canvas.drawLine(
            Offset(plot.left + w2, cy - barH / 2 - 1),
            Offset(plot.left + w2, cy + barH / 2 + 1),
            Paint()
              ..color = p.accent
              ..strokeWidth = 2);
      }
      if (j == s.layout.feedStages.first) {
        canvas.drawLine(Offset(plot.left - 5, cy), Offset(plot.left, cy), Paint()
          ..color = p.accent
          ..strokeWidth = 2);
      }
    }
    // row labels every 5 trays and the selection
    for (var j = 1; j <= N; j++) {
      if (j == 1 || j % 5 == 0 || j == N) {
        _text(canvas, '$j', Offset(plot.left - 8, plot.top + (j - 0.5) * rowH), num.style(12, p.inkMuted), Alignment.centerRight);
      }
    }
    final sel = selected.value;
    if (sel != null && sel >= 1 && sel <= N) {
      final r = Rect.fromLTRB(plot.left - 2, plot.top + (sel - 1) * rowH, plot.right, plot.top + sel * rowH);
      canvas.drawRect(r, Paint()..color = p.selection.withValues(alpha: 0.18));
      canvas.drawRect(
          r,
          Paint()
            ..color = p.selection
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    final key = switch (kind) {
      ProfileKind.dp => 'bar = total dP, tick = dry dP',
      ProfileKind.flood => 'bar = jet flood / froth fill, tick = downcomer',
      ProfileKind.composition => 'bar = liquid x, tick = vapour y',
      ProfileKind.temperature => s.tier == ThermoTier.t1 ? 'T*, ideal (Raoult) bubble point, display only: constant alpha has no temperatures' : 'bubble-point temperature of each tray',
      ProfileKind.vapour || ProfileKind.liquid => ghost?.value == null
          ? (s.tier == ThermoTier.t1 ? 'constant molar overflow: V and L are flat in each section' : 'Tier 2: V and L change with the latent heats')
          : 'bar = now, tick = ${ghost!.value!.fromTier} just before the switch',
      _ => '',
    };
    if (key.isNotEmpty) _text(canvas, key, Offset(plot.left, plot.top - 4), lab.style(12, p.inkMuted), Alignment.bottomLeft, maxWidth: plot.width);
    _text(canvas, 'tray', Offset(plot.left - 8, plot.top - 4), lab.style(12, p.inkMuted), Alignment.bottomRight);
  }

  void _text(Canvas c, String t, Offset at, TextStyle st, Alignment a, {double maxWidth = double.infinity}) {
    final tp = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxWidth);
    tp.paint(c, Offset(at.dx - tp.width * (a.x + 1) / 2, at.dy - tp.height * (a.y + 1) / 2));
  }

  @override
  bool shouldRepaint(ProfilePainter old) => old.kind != kind || old.theme != theme;
}
