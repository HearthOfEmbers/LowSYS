import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';
import '../theme/themes/brass.dart';
import 'column_painter.dart' show ColumnAnimation;
import 'crude_geometry.dart';
import '../theme/painter_text.dart';

final CrudeThermo _th = CrudeThermo();

/// Mean boiling point (K) of the liquid on a stage, from the stage composition.
double meanTb(Float64List x, int stage, int nc) {
  var t = 0.0, s = 0.0;
  for (var i = 0; i < 9; i++) {
    final xi = x[stage * nc + i];
    if (xi.isNaN) return double.nan;
    t += xi * _th.tb[i];
    s += xi;
  }
  return s > 0 ? t / s : double.nan;
}

/// Crude flowsheet (ENGINE_API.md 13.5): the 30-stage column with its swaged stripping section, three side strippers,
/// the pumparound, the furnace, the steam inlets and the drum. Liquid colour follows the mean boiling point of the stage
/// liquid. Brass adds the bevelled shell with rivets, steam puffs, a flame sprite and a dial with a damped needle.
class CrudeFlowsheetPainter extends CustomPainter {
  final ValueListenable<SimSnapshot?> snapshot;
  final ValueListenable<int?> selected;
  final ColumnAnimation anim;
  final LowsysTheme theme;
  final ValueListenable<UnitSystem> units;
  final BrassNeedle needle;

  CrudeFlowsheetPainter({
    required this.snapshot,
    required this.selected,
    required this.anim,
    required this.theme,
    required this.units,
    required this.needle,
  }) : super(repaint: Listenable.merge([snapshot, selected, anim, units]));

  double _lastAnim = 0;

  TextStyle _num(double s, Color c) => theme.type.number.style(s, c);

  void _text(Canvas c, String text, Offset at, TextStyle st, {Alignment anchor = Alignment.topLeft, double maxWidth = 200}) {
    final tp = TextPainter(text: TextSpan(text: text, style: st), textDirection: TextDirection.ltr, textScaler: PainterText.scaler, maxLines: 1, ellipsis: '…')
      ..layout(maxWidth: maxWidth);
    tp.paint(c, Offset(at.dx - tp.width * (anchor.x + 1) / 2, at.dy - tp.height * (anchor.y + 1) / 2));
  }

  String _t(double k) => k.isNaN ? '—' : units.value.fromSI(Quantity.temperature, k).toStringAsFixed(0);

  @override
  void paint(Canvas canvas, Size size) {
    final s = snapshot.value;
    if (s == null || s.strippers.isEmpty || size.isEmpty) return;
    final p = theme.palette;
    final brass = theme.id == 'brass';
    final g = CrudeGeometry(size);
    final k = s.kpis.crude!;
    final nc = s.stages.nc;
    final fs = math.max(9.0, math.min(12.0, size.width / 34));
    final stroke = Paint()
      ..color = p.steel
      ..style = PaintingStyle.stroke
      ..strokeWidth = theme.column.strokeWidth;
    final thin = Paint()
      ..color = p.steel.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = theme.column.trayStrokeWidth;
    final pipe = Paint()
      ..color = p.inkMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final dt = (anim.time - _lastAnim).clamp(0.0, 0.1);
    _lastAnim = anim.time;
    final cotFrac = k.cot.isNaN ? 0.5 : ((k.cot - 603.15) / 60).clamp(0.0, 1.0);
    needle.step(cotFrac, dt == 0 ? 0.016 : dt);

    // ---- shell: wide trays above stage 26, swaged stripping section below
    final swage = g.shellW * 0.14;
    final sY = g.yT0 + 26 * g.spacing;
    final shell = Path()
      ..moveTo(g.shellL, g.yT0 - 6)
      ..lineTo(g.shellR, g.yT0 - 6)
      ..lineTo(g.shellR, sY)
      ..lineTo(g.shellR - swage, sY + g.spacing * 0.6)
      ..lineTo(g.shellR - swage, g.yT1)
      ..lineTo(g.shellR - swage, g.sumpBot)
      ..lineTo(g.shellL + swage, g.sumpBot)
      ..lineTo(g.shellL + swage, sY + g.spacing * 0.6)
      ..lineTo(g.shellL, sY)
      ..close();
    if (brass) {
      final rect = Rect.fromLTRB(g.shellL, g.yT0 - 6, g.shellR, g.sumpBot);
      canvas.drawPath(
        shell,
        Paint()
          ..shader = LinearGradient(
            colors: [p.accent2.withValues(alpha: 0.55), p.accent.withValues(alpha: 0.30), p.accent2.withValues(alpha: 0.55)],
            stops: const [0, 0.5, 1],
          ).createShader(rect),
      );
      final rivet = Paint()..color = p.accent.withValues(alpha: 0.9);
      for (var y = g.yT0 + 4; y < g.sumpBot - 4; y += g.spacing * 3) {
        canvas.drawCircle(Offset(g.shellL + 3, y), 1.5, rivet);
        canvas.drawCircle(Offset(g.shellR - 3, y), 1.5, rivet);
      }
    }
    // ---- stage liquid and decks
    for (var j = 1; j <= 30; j++) {
      final y = g.yT0 + j * g.spacing;
      final inStrip = j > 26;
      final l = g.shellL + (inStrip ? swage : 0), r = g.shellR - (inStrip ? swage : 0);
      final tb = meanTb(s.stages.x, j, nc);
      final f = tb.isNaN ? 0.5 : ((tb - 330) / 280).clamp(0.0, 1.0);
      final liquid = Color.lerp(p.liquidLight, p.liquidHeavy, f)!;
      final hcl = s.stages.hcl[j];
      final hFrac = hcl.isNaN ? 0.3 : (hcl / 0.09).clamp(0.12, 0.75);
      canvas.drawRect(Rect.fromLTRB(l + 1, y - g.spacing * hFrac, r - 1, y), Paint()..color = liquid.withValues(alpha: 0.85));
      canvas.drawLine(Offset(l, y), Offset(r, y), thin);
    }
    canvas.drawPath(shell, stroke);
    // sump
    final sumpL = g.shellL + swage + 1, sumpR = g.shellR - swage - 1;
    final sTop = g.yT1 + 2;
    final lvl = (s.kpis.sumpLevelPct.isNaN ? 50 : s.kpis.sumpLevelPct) / 100;
    final sf = meanTb(s.stages.x, 31, nc);
    canvas.drawRect(
      Rect.fromLTRB(sumpL, g.sumpBot - (g.sumpBot - sTop) * lvl, sumpR, g.sumpBot - 1),
      Paint()..color = Color.lerp(p.liquidLight, p.liquidHeavy, sf.isNaN ? 0.9 : ((sf - 330) / 280).clamp(0.0, 1.0))!,
    );

    // ---- stage temperature labels (instrumented stages) and draw/flash markers
    const tiStages = [1, 4, 8, 11, 15, 18, 21, 24, 26, 30];
    for (var i = 0; i < tiStages.length; i++) {
      final j = tiStages[i];
      _text(canvas, _t(s.stages.t[j]), Offset(g.shellR - 3 - (j > 26 ? swage : 0), g.yT0 + (j - 0.5) * g.spacing), _num(fs - 1, p.ink),
          anchor: Alignment.centerRight);
    }

    // ---- selection
    final sel = selected.value;
    if (sel != null && sel >= 1 && sel <= 30) {
      canvas.drawRect(
        Rect.fromLTRB(g.shellL - 3, g.yT0 + (sel - 1) * g.spacing, g.shellR + 3, g.yT0 + sel * g.spacing),
        Paint()
          ..color = p.selection
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // ---- overhead: condenser, drum, reflux, naphtha
    canvas.drawLine(Offset(g.condenser.dx, g.yT0 - 6), Offset(g.condenser.dx, g.condenser.dy + g.condR), pipe);
    canvas.drawCircle(g.condenser, g.condR, stroke);
    canvas.drawPath(
        Path()
          ..moveTo(g.condenser.dx - g.condR * 0.7, g.condenser.dy + g.condR * 0.3)
          ..lineTo(g.condenser.dx - g.condR * 0.3, g.condenser.dy - g.condR * 0.3)
          ..lineTo(g.condenser.dx + g.condR * 0.3, g.condenser.dy + g.condR * 0.3)
          ..lineTo(g.condenser.dx + g.condR * 0.7, g.condenser.dy - g.condR * 0.3),
        thin);
    canvas.drawLine(Offset(g.condenser.dx + g.condR, g.condenser.dy), Offset(g.drum.left, g.condenser.dy), pipe);
    final dl = (s.kpis.drumLevelPct.isNaN ? 50 : s.kpis.drumLevelPct) / 100;
    canvas.drawRect(
        Rect.fromLTWH(g.drum.left + 1, g.drum.bottom - g.drum.height * dl, g.drum.width - 2, g.drum.height * dl - 1), Paint()..color = p.liquidLight.withValues(alpha: 0.85));
    canvas.drawRRect(RRect.fromRectAndRadius(g.drum, const Radius.circular(10)), stroke);
    final refluxY = g.stageY(1);
    canvas.drawPath(
        Path()
          ..moveTo(g.drum.left + 12, g.drum.bottom)
          ..lineTo(g.drum.left + 12, refluxY)
          ..lineTo(g.shellR, refluxY),
        pipe);
    _text(canvas, 'Naphtha ${k.yieldVolPct[0].toStringAsFixed(1)} %', Offset(g.drum.right + 4, g.drum.center.dy), _num(fs, p.ink),
        anchor: Alignment.centerLeft);
    _text(canvas, S.reflux, Offset(g.drum.left + 14, (g.drum.bottom + refluxY) / 2), _num(fs - 1, p.inkMuted));
    _text(canvas, '${_t(s.kpis.crude!.topT)} ${units.value.symbol(Quantity.temperature)} · ${(k.qc / 1e6).toStringAsFixed(1)} MW', Offset(g.condenser.dx, 2),
        _num(fs - 1, p.inkMuted), anchor: Alignment.topCenter);
    if (k.condenserLimited) _text(canvas, S.qcLimit, Offset(g.condenser.dx - g.condR - 4, g.condenser.dy), _num(fs - 1, p.alarm), anchor: Alignment.centerRight);

    // ---- strippers
    const names = ['Kero', 'Diesel', 'AGO'];
    for (var i = 0; i < 3; i++) {
      final d = CrudeGeometry.drawStages[i], rS = CrudeGeometry.returnStages[i];
      final top = g.ssTop(i), boot = g.ssBoot(i);
      final yd = g.stageY(d), yr = g.stageY(rS);
      final st = s.strippers[i];
      canvas.drawLine(Offset(g.shellR, yd), Offset(top.left + top.width * 0.3, yd), pipe);
      canvas.drawLine(Offset(top.left + top.width * 0.3, yd), Offset(top.left + top.width * 0.3, top.top), pipe);
      canvas.drawPath(
          Path()
            ..moveTo(top.left + top.width * 0.75, top.top)
            ..lineTo(top.left + top.width * 0.75, yr)
            ..lineTo(g.shellR, yr),
          pipe);
      for (final r in [top, boot]) {
        canvas.drawRect(r, stroke);
      }
      final tbT = meanTb(s.stages.x, 0, nc);
      final fTop = ((st.t[0] - 330) / 280).clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTRB(top.left + 1.5, top.bottom - top.height * 0.35, top.right - 1.5, top.bottom - 1.5), Paint()..color = Color.lerp(p.liquidLight, p.liquidHeavy, fTop)!.withValues(alpha: 0.85));
      final lv = (st.levelPct.isNaN ? 50 : st.levelPct) / 100;
      canvas.drawRect(Rect.fromLTRB(boot.left + 1.5, boot.bottom - boot.height * lv.clamp(0.0, 1.0), boot.right - 1.5, boot.bottom - 1.5),
          Paint()..color = Color.lerp(p.liquidLight, p.liquidHeavy, ((st.t[1] - 330) / 280).clamp(0.0, 1.0))!.withValues(alpha: 0.9));
      if (tbT.isNaN) {}
      // sight glass on the boot
      final sg = Offset(boot.right - 7, boot.top + 8);
      canvas.drawCircle(sg, 5, Paint()..color = p.bgAlt);
      canvas.drawCircle(sg, 5, brass ? (Paint()..color = p.accent..style = PaintingStyle.stroke..strokeWidth = 1.6) : thin);
      canvas.drawLine(top.bottomLeft + Offset(0, 0), top.bottomLeft + Offset(top.width, 0), thin);
      // product and steam
      final dry = k.drawDry[i];
      canvas.drawLine(Offset(boot.right, boot.center.dy), Offset(size.width - 2, boot.center.dy), dry ? (Paint()..color = p.alarm..strokeWidth = 2) : pipe);
      _text(canvas, '${names[i]} ${k.yieldVolPct[i + 1].toStringAsFixed(1)} %', Offset(boot.right + 3, boot.center.dy - 3),
          _num(fs, dry ? p.alarm : p.ink), anchor: Alignment.bottomLeft, maxWidth: size.width - boot.right - 4);
      _text(canvas, dry ? 'draw dry' : '${_t(st.t[1])} ${units.value.symbol(Quantity.temperature)}', Offset(boot.right + 3, boot.center.dy + 2),
          _num(fs - 1, dry ? p.alarm : p.inkMuted), anchor: Alignment.topLeft, maxWidth: size.width - boot.right - 4);
      _steam(canvas, g.steamPoint(i + 1), Offset(0, -1), p, brass, fs, st.steam * 0.018015 * 3600);
      canvas.drawLine(Offset((g.ssL + g.ssR) / 2, boot.bottom), g.steamPoint(i + 1), pipe);
    }

    // ---- bottom steam, residue
    _steam(canvas, g.steamPoint(0), const Offset(1, 0), p, brass, fs, s.levers['steam.bottom']! * 3600);
    canvas.drawLine(g.steamPoint(0), Offset(g.shellL + swage, g.steamPoint(0).dy), pipe);
    canvas.drawLine(Offset(sumpR, g.sumpBot - 6), Offset(size.width - 2, g.sumpBot - 6), pipe);
    _text(canvas, 'Residue ${k.yieldVolPct[4].toStringAsFixed(1)} %', Offset(g.shellR + 4, g.sumpBot - 8), _num(fs, p.ink), anchor: Alignment.bottomLeft);
    _text(canvas, 'bottom ${_t(k.bottomT)} ${units.value.symbol(Quantity.temperature)}', Offset(g.shellR + 4, g.sumpBot - 4), _num(fs - 1, p.inkMuted));

    // ---- pumparound loop
    final y16 = g.stageY(16), y14 = g.stageY(14);
    final hot = Paint()
      ..color = p.accent2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(
        Path()
          ..moveTo(g.shellL, y16)
          ..lineTo(g.paX, y16)
          ..lineTo(g.paX, g.cooler.dy + 9)
          ..moveTo(g.paX, g.cooler.dy - 9)
          ..lineTo(g.paX, y14)
          ..lineTo(g.shellL, y14),
        hot);
    canvas.drawCircle(g.cooler, 9, stroke);
    canvas.drawLine(g.cooler + const Offset(-6, 6), g.cooler + const Offset(6, -6), thin);
    final lim = k.paDutyLimited;
    _text(canvas, 'PA ${(k.qPa / 1e6).toStringAsFixed(1)} MW', Offset(g.paX - 12, g.cooler.dy - 12), _num(fs, lim ? p.warn : p.ink), anchor: Alignment.bottomRight);
    _text(canvas, '${_t(k.paReturnT)} ${units.value.symbol(Quantity.temperature)}${lim ? ' limit' : ''}', Offset(g.paX - 12, g.cooler.dy + 12),
        _num(fs - 1, lim ? p.warn : p.inkMuted), anchor: Alignment.topRight);

    // ---- furnace on the feed line
    final f = g.furnace;
    canvas.drawRect(f, stroke);
    canvas.drawLine(Offset(f.right, f.center.dy), Offset(g.shellL, f.center.dy), pipe);
    _text(canvas, 'COT ${_t(k.cot)}', Offset(f.center.dx, f.top + 2), _num(fs, p.ink), anchor: Alignment.topCenter);
    _text(canvas, 'FZ ${_t(k.flashZoneT)} · OF ${k.overflashVolPct.toStringAsFixed(1)} %', Offset(f.left, f.bottom + 2), _num(fs - 1, p.inkMuted), maxWidth: g.shellL - f.left);
    if (brass) {
      final h = (0.35 + 0.65 * cotFrac) * f.height * 1.1;
      final fx = f.left + f.width * 0.5;
      final flame = Path()
        ..moveTo(fx - 7, f.bottom)
        ..quadraticBezierTo(fx - 5, f.bottom - h * 0.6, fx, f.bottom - h)
        ..quadraticBezierTo(fx + 5, f.bottom - h * 0.6, fx + 7, f.bottom)
        ..close();
      canvas.drawPath(flame, Paint()..color = p.hot.withValues(alpha: 0.85));
      canvas.drawPath(
          Path()
            ..moveTo(fx - 3, f.bottom)
            ..quadraticBezierTo(fx, f.bottom - h * 0.55, fx + 3, f.bottom)
            ..close(),
          Paint()..color = p.warn);
      // dial with a damped needle (COT)
      final c0 = Offset(f.center.dx, f.top - size.height * 0.07);
      final r = math.min(size.width * 0.07, size.height * 0.05);
      canvas.drawCircle(c0, r, Paint()..color = p.bgAlt);
      canvas.drawCircle(c0, r, Paint()..color = p.accent..style = PaintingStyle.stroke..strokeWidth = 2);
      final ang = math.pi * (0.8 + 1.4 * needle.value);
      canvas.drawLine(c0, c0 + Offset(math.cos(ang), math.sin(ang)) * (r - 3), Paint()..color = p.hot..strokeWidth = 2);
      _text(canvas, S.cot, c0 + Offset(0, r * 0.45), _num(fs - 2, p.inkMuted), anchor: Alignment.center);
    }
  }

  void _steam(Canvas c, Offset at, Offset dir, ThemePalette p, bool brass, double fs, double kgh) {
    final col = p.vapor;
    c.drawCircle(at, 3, Paint()..color = col);
    if (brass) {
      // puffs rise with the UI clock
      for (var i = 0; i < 3; i++) {
        final ph = ((anim.time * 0.5) + i / 3) % 1.0;
        c.drawCircle(at + dir * (6 + 14 * ph) + Offset(0, 4 * ph), 2 + 3 * ph, Paint()..color = col.withValues(alpha: 0.6 * (1 - ph)));
      }
    }
    final isBottom = dir.dx > 0;
    _text(c, '${kgh.round()} kg/h', at + Offset(isBottom ? -6 : 0, isBottom ? 6 : 6), _num(fs - 2, p.inkMuted),
        anchor: isBottom ? Alignment.topRight : Alignment.topCenter);
  }

  @override
  bool shouldRepaint(CrudeFlowsheetPainter old) => old.theme != theme;
}
