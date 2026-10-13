import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';
import 'effects/glow.dart';

/// Plot area of the McCabe-Thiele chart inside a panel of [size] (shared with tap picking).
Rect mccabePlotRect(Size size) {
  final reserve = size.height < 300 ? 32.0 : 56.0; // short panels (phone landscape): x label only
  final side = math.min(size.width - 52, size.height - reserve);
  final s = math.max(40.0, side);
  return Rect.fromLTWH(44 + (size.width - 52 - s).clamp(0.0, 1e9) / 2, 10, s, s);
}

/// Live McCabe-Thiele diagram in the Blueprint "hand-ruled" style (theme tokens only).
class McCabePainter extends CustomPainter {
  final ValueListenable<McCabeThieleData?> data;
  final ValueListenable<SimSnapshot?> snapshot;
  final ValueListenable<int?> selected;
  final LowsysTheme theme;
  final bool compact;

  McCabePainter({required this.data, required this.snapshot, required this.selected, required this.theme, this.compact = false})
      : super(repaint: Listenable.merge([data, snapshot, selected]));

  Offset _pt(Rect r, double x, double y) => Offset(r.left + x * r.width, r.bottom - y * r.height);

  @override
  void paint(Canvas canvas, Size size) {
    final d = data.value;
    final snap = snapshot.value;
    if (d == null || snap == null) return;
    final p = theme.palette;
    final ch = theme.chart;
    final plot = mccabePlotRect(size);
    final num = theme.type.number;
    final lab = theme.type.label;
    final tight = size.height < 300;
    final narrow = plot.width < 220; // phone portrait: thin the markers, one-line legend

    // --- paper: hand-ruled grid
    final minor = Paint()
      ..color = p.grid.withValues(alpha: 0.55)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = p.gridMajor
      ..strokeWidth = 0.9;
    canvas.drawRect(plot, Paint()..color = p.bgAlt.withValues(alpha: 0.55));
    final nMinor = (1 / ch.gridMinor).round();
    final perMajor = (ch.gridMajor / ch.gridMinor).round();
    for (var i = 0; i <= nMinor; i++) {
      final v = i / nMinor;
      final paint = i % perMajor == 0 ? major : minor;
      canvas.drawLine(_pt(plot, v, 0), _pt(plot, v, 1), paint);
      canvas.drawLine(_pt(plot, 0, v), _pt(plot, 1, v), paint);
    }
    canvas.drawRect(
        plot,
        Paint()
          ..color = p.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
    // tick labels
    for (var i = 0; i <= 5; i++) {
      final v = i / 5;
      _text(canvas, v.toStringAsFixed(1), _pt(plot, v, 0) + const Offset(0, 4), num.style(12, p.inkMuted), Alignment.topCenter);
      _text(canvas, v.toStringAsFixed(1), _pt(plot, 0, v) + const Offset(-4, 0), num.style(12, p.inkMuted), Alignment.centerRight);
    }
    _text(canvas, compact ? 'x  ${d.lightLabel.toLowerCase()}  \u00B7  t ${_clock(snap.time)}' : 'x  ${d.lightLabel.toLowerCase()}, liquid', Offset(plot.center.dx, plot.bottom + 19), lab.style(12, p.inkMuted), Alignment.topCenter);
    canvas.save();
    canvas.translate(8, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _text(canvas, 'y  vapour', Offset.zero, lab.style(12, p.inkMuted), Alignment.center);
    canvas.restore();

    canvas.save();
    canvas.clipRect(plot.inflate(2));

    // --- diagonal
    canvas.drawLine(
        _pt(plot, 0, 0),
        _pt(plot, 1, 1),
        Paint()
          ..color = p.diagonal
          ..strokeWidth = 1.2);

    // --- pseudo-equilibrium (dotted)
    _poly(canvas, plot, d.pseudoEquilibrium, Paint()
      ..color = p.pseudoEq
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3, dash: (1.5, 4.0));

    // --- q-line
    if (d.qLine != null) {
      canvas.drawLine(
          _pt(plot, d.qLine!.a.x, d.qLine!.a.y),
          _pt(plot, d.qLine!.b.x, d.qLine!.b.y),
          Paint()
            ..color = p.qLine
            ..strokeWidth = 1.6);
    }
    // --- CMO operating lines (dashed)
    final cmo = Paint()
      ..color = p.opLineCmo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    _poly(canvas, plot, d.cmoRectifying, cmo, dash: (ch.dashOn, ch.dashOff));
    _poly(canvas, plot, d.cmoStripping, cmo, dash: (ch.dashOn, ch.dashOff));

    // --- minimum reflux construction
    if (d.rmin != null) {
      final r = d.rmin!;
      canvas.drawLine(
          _pt(plot, r.from.x, r.from.y),
          _pt(plot, r.to.x, r.to.y),
          Paint()
            ..color = p.accent2
            ..strokeWidth = 1.2);
      canvas.drawCircle(
          _pt(plot, r.touch.x, r.touch.y),
          5,
          Paint()
            ..color = p.accent2
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }

    // --- Tier 2: the band between the curve at P_top and at P_bottom (a real column has no single curve)
    final tier2 = snap.tier != ThermoTier.t1;
    final glow = GlowBudget.of(theme);
    final bot = d.equilibriumBottom;
    if (bot != null && bot.length == d.equilibriumTop.length) {
      var width = 0.0;
      for (var i = 0; i < bot.length; i++) {
        width = math.max(width, (bot[i].y - d.equilibriumTop[i].y).abs());
      }
      if (width > 1e-4) {
        final band = Path();
        for (var i = 0; i < d.equilibriumTop.length; i++) {
          final o = _pt(plot, d.equilibriumTop[i].x, d.equilibriumTop[i].y);
          i == 0 ? band.moveTo(o.dx, o.dy) : band.lineTo(o.dx, o.dy);
        }
        for (var i = bot.length - 1; i >= 0; i--) {
          final o = _pt(plot, bot[i].x, bot[i].y);
          band.lineTo(o.dx, o.dy);
        }
        band.close();
        canvas.drawPath(band, Paint()..color = p.eqCurve.withValues(alpha: 0.2));
      }
    }

    // --- equilibrium curve
    final eqPaint = Paint()
      ..color = p.eqCurve
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (glow.left > 0) {
      final path = Path();
      for (var i = 0; i < d.equilibriumTop.length; i++) {
        final o = _pt(plot, d.equilibriumTop[i].x, d.equilibriumTop[i].y);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      strokeGlow(canvas, path, eqPaint, glow);
    } else {
      _poly(canvas, plot, d.equilibriumTop, eqPaint);
    }

    // --- Tier 2: local equilibrium points (x_j, y*_j) and the solid, curved operating locus
    if (tier2) {
      final loc = Paint()
        ..color = p.pseudoEq
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      for (var i = 0; i < d.localEquilibrium.length; i++) {
        if (narrow && i % 3 != 0) continue;
        final q = d.localEquilibrium[i];
        canvas.drawCircle(_pt(plot, q.x, q.y), narrow ? 1.8 : 2.4, loc);
      }
      final lp = Path();
      for (var i = 0; i < d.operatingLocus.length; i++) {
        final o = _pt(plot, d.operatingLocus[i].x, d.operatingLocus[i].y);
        i == 0 ? lp.moveTo(o.dx, o.dy) : lp.lineTo(o.dx, o.dy);
      }
      strokeGlow(
          canvas,
          lp,
          Paint()
            ..color = p.opLine
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeJoin = StrokeJoin.round,
          glow);
    }

    // --- actual operating locus (dots)
    final dot = Paint()..color = p.opLine;
    for (var i = 0; i < d.operatingLocus.length; i++) {
      if (narrow && i % 2 == 1) continue;
      final q = d.operatingLocus[i];
      canvas.drawCircle(_pt(plot, q.x, q.y), narrow ? 1.5 : 2.0, dot);
    }

    // --- staircase with arrowheads at the mid-point of each segment
    final stair = Paint()
      ..color = p.stepLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < d.staircase.length; i++) {
      final o = _pt(plot, d.staircase[i].x, d.staircase[i].y);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, stair);
    final arrow = Paint()..color = p.stepLine;
    for (var i = 1; i < d.staircase.length; i++) {
      final a = _pt(plot, d.staircase[i - 1].x, d.staircase[i - 1].y);
      final b = _pt(plot, d.staircase[i].x, d.staircase[i].y);
      final len = (b - a).distance;
      if (len < 9) continue;
      _arrow(canvas, a + (b - a) * 0.5 + (b - a) / len * 3, b - a, 4.5, arrow);
    }

    // --- stage corners: hollow circles (thinned on phones); the feed stage is a filled accent dot
    final cornerP = Paint()
      ..color = p.stepLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final selStage = selected.value;
    for (final c in d.corners) {
      final o = _pt(plot, c.x, c.y);
      if (c.isFeed) continue;
      if (narrow && c.stage % 4 != 0 && c.stage != selStage) continue;
      canvas.drawCircle(o, narrow ? 2.4 : 3.0, cornerP);
    }
    for (final c in d.corners) {
      if (!c.isFeed) continue;
      final o = _pt(plot, c.x, c.y);
      canvas.drawCircle(o, 8.5, Paint()..color = p.accent.withValues(alpha: 0.22));
      canvas.drawCircle(o, 4.6, Paint()..color = p.accent);
      canvas.drawCircle(
          o,
          8.5,
          Paint()
            ..color = p.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
      _text(canvas, narrow ? 'F' : 'feed tray ${c.stage}', o + const Offset(-11, 3), num.style(12, p.accent, weight: FontWeight.w700), Alignment.topRight);
    }
    // the pinch: where the q-line meets the equilibrium curve
    if (d.qLine != null) {
      final o = _pt(plot, d.qLine!.b.x, d.qLine!.b.y);
      final dm = Path()
        ..moveTo(o.dx, o.dy - 4.5)
        ..lineTo(o.dx + 4.5, o.dy)
        ..lineTo(o.dx, o.dy + 4.5)
        ..lineTo(o.dx - 4.5, o.dy)
        ..close();
      canvas.drawPath(
          dm,
          Paint()
            ..color = p.qLine
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
      if (!narrow) {
        final tip = o + const Offset(22, -22);
        canvas.drawLine(o + const Offset(3, -3), tip, Paint()
          ..color = p.qLine
          ..strokeWidth = 0.9);
        _text(canvas, 'pinch', tip + const Offset(2, 0), lab.style(12, p.qLine), Alignment.bottomLeft);
      }
    }

    // --- Murphree gap markers + highlight for the selected tray
    final sel = selected.value;
    final N = snap.layout.nTrays;
    if (sel != null && sel >= 1 && sel <= N) {
      final st = snap.stages;
      final x = st.x[sel * st.nc];
      final y = st.y[sel * st.nc];
      final yb = st.y[(sel + 1) * st.nc];
      final ys = st.yStar[sel * st.nc];
      final hl = Paint()
        ..color = p.selection
        ..strokeWidth = 2.4;
      canvas.drawLine(_pt(plot, x + 0.012, yb), _pt(plot, x + 0.012, y), hl);
      canvas.drawLine(
          _pt(plot, x - 0.012, yb),
          _pt(plot, x - 0.012, ys),
          Paint()
            ..color = p.selection.withValues(alpha: 0.7)
            ..strokeWidth = 1.6);
      canvas.drawCircle(
          _pt(plot, x, y),
          7.5,
          Paint()
            ..color = p.selection
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      _text(canvas, '$sel', _pt(plot, x, y) + const Offset(-9, -5), num.style(12, p.selection, weight: FontWeight.w700), Alignment.bottomRight);
    }

    canvas.restore();

    // --- product and feed compositions on the diagonal (outside the clip so labels are never cut)
    void marker(double x, String name, Alignment a, Offset off) {
      final o = _pt(plot, x, x);
      final tri = Path()
        ..moveTo(o.dx, o.dy + 1)
        ..lineTo(o.dx - 5, o.dy + 9)
        ..lineTo(o.dx + 5, o.dy + 9)
        ..close();
      canvas.drawPath(tri, Paint()..color = p.marker);
      _text(canvas, name, o + off, num.style(12, p.marker), a);
    }

    marker(d.xB, 'xB ${d.xB.toStringAsFixed(3)}', Alignment.bottomLeft, const Offset(8, -6));
    marker(d.xF, 'xF', Alignment.topCenter, const Offset(0, 11));
    // xD sits at the plot's corner: label above the frame with a leader line, clear of the stair markers
    {
      final o = _pt(plot, d.xD, d.xD);
      final lead = Paint()
        ..color = p.marker.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(o.dx, o.dy - 2), Offset(o.dx - 6, o.dy - 12), lead);
      final tri = Path()
        ..moveTo(o.dx, o.dy + 1)
        ..lineTo(o.dx - 5, o.dy + 9)
        ..lineTo(o.dx + 5, o.dy + 9)
        ..close();
      canvas.drawPath(tri, Paint()..color = p.marker);
      _text(canvas, 'xD ${d.xD.toStringAsFixed(3)}', Offset(o.dx - 8, o.dy - 12), num.style(12, p.marker), Alignment.bottomRight);
    }

    // --- legend (top-left inside the plot, wide layouts only) (top-left inside the plot, wide layouts only)
    if (narrow && !tight) {
      var lx = plot.left;
      final ly = plot.bottom + 52;
      for (final (name, color, dashed) in [('eq', p.eqCurve, false), ('op', p.opLineCmo, true), ('q', p.qLine, false), ('stages', p.stepLine, false)]) {
        final pn = Paint()
          ..color = color
          ..strokeWidth = 1.6;
        if (dashed) {
          canvas.drawLine(Offset(lx, ly), Offset(lx + 5, ly), pn);
          canvas.drawLine(Offset(lx + 8, ly), Offset(lx + 13, ly), pn);
        } else {
          canvas.drawLine(Offset(lx, ly), Offset(lx + 13, ly), pn);
        }
        final tp = TextPainter(text: TextSpan(text: name, style: lab.style(12, p.inkMuted)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(lx + 16, ly - tp.height / 2));
        lx += 16 + tp.width + 9;
      }
    }
    if (!compact) {
      final items = [
        ('equilibrium', p.eqCurve, false),
        (tier2 ? 'textbook CMO lines' : 'operating (CMO)', p.opLineCmo, true),
        if (tier2) ('actual operating locus', p.opLine, false),
        ('q-line', p.qLine, false),
        ('stages', p.stepLine, false),
      ];
      var y = plot.top + 8;
      for (final (name, color, dashed) in items) {
        final a = Offset(plot.left + 8, y + 6), b = Offset(plot.left + 30, y + 6);
        final pn = Paint()
          ..color = color
          ..strokeWidth = 1.6;
        if (dashed) {
          canvas.drawLine(a, a + const Offset(8, 0), pn);
          canvas.drawLine(a + const Offset(13, 0), b, pn);
        } else {
          canvas.drawLine(a, b, pn);
        }
        _text(canvas, name, Offset(plot.left + 35, y + 6), lab.style(12, p.inkMuted), Alignment.centerLeft);
        y += 15;
      }
    }

    // --- title block (lower right, drafting-sheet style); a one-line caption when space is tight
    if (!compact) _titleBlock(canvas, plot, d, snap, compact);

    // --- transient stamp (inside the plot, top centre, on a backing pill)
    if (d.transient) {
      var msg = 'transient: stairs from live compositions, dashed lines from current flows';
      final tp = TextPainter(text: TextSpan(text: msg, style: lab.style(12, p.warn)), textDirection: TextDirection.ltr)..layout();
      if (tp.width > plot.width - 12) msg = 'transient';
      final w = TextPainter(text: TextSpan(text: msg, style: lab.style(12, p.warn)), textDirection: TextDirection.ltr)..layout();
      final r = Rect.fromCenter(center: Offset(plot.right - (w.width + 12) / 2 - 6, plot.top + 30), width: w.width + 12, height: w.height + 4);
      canvas.drawRect(r, Paint()..color = p.bg.withValues(alpha: 0.85));
      canvas.drawRect(
          r,
          Paint()
            ..color = p.warn
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9);
      _text(canvas, msg, r.center, lab.style(12, p.warn), Alignment.center);
    }
  }

  void _titleBlock(Canvas canvas, Rect plot, McCabeThieleData d, SimSnapshot s, bool compact) {
    final p = theme.palette;
    final lab = theme.type.label;
    final num = theme.type.number;
    final w = math.min(plot.width * (compact ? 0.78 : 0.62), 218.0);
    final rows = <(String, TextStyle)>[
      ('${d.lightLabel.toUpperCase()}–${d.heavyLabel.toUpperCase()}', lab.style(12, p.ink, weight: FontWeight.w700)),
      ('Tier ${s.tier.name.substring(1)}  ·  E = ${s.murphree.toStringAsFixed(2)}', num.style(12, p.inkMuted)),
      ('t ${_clock(s.time)} · P ${(s.stages.p[1] / 1e5).toStringAsFixed(3)} bar', num.style(12, p.inkMuted)),
    ];
    final rowH = 15.0;
    final h = rowH * rows.length + 6;
    final box = Rect.fromLTWH(plot.right - w - 6, plot.bottom - h - 6, w, h);
    canvas.drawRect(box, Paint()..color = p.bg.withValues(alpha: 0.88));
    final line = Paint()
      ..color = p.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawRect(box, line);
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) canvas.drawLine(Offset(box.left, box.top + 3 + rowH * i), Offset(box.right, box.top + 3 + rowH * i), Paint()
        ..color = p.gridMajor
        ..strokeWidth = 0.7);
      _text(canvas, rows[i].$1, Offset(box.left + 5, box.top + 3 + rowH * i + rowH / 2), rows[i].$2, Alignment.centerLeft, maxWidth: w - 8);
    }
  }

  static String _clock(double t) {
    final s = t.floor();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}';
  }

  void _poly(Canvas c, Rect plot, List<Point2> pts, Paint paint, {(double, double)? dash}) {
    if (pts.length < 2) return;
    if (dash == null) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = _pt(plot, pts[i].x, pts[i].y);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, paint);
      return;
    }
    final (on, off) = dash;
    for (var i = 1; i < pts.length; i++) {
      final a = _pt(plot, pts[i - 1].x, pts[i - 1].y), b = _pt(plot, pts[i].x, pts[i].y);
      final total = (b - a).distance;
      if (total < 0.01) continue;
      final dir = (b - a) / total;
      var s = 0.0;
      while (s < total) {
        c.drawLine(a + dir * s, a + dir * math.min(total, s + on), paint);
        s += on + off;
      }
    }
  }

  void _arrow(Canvas c, Offset at, Offset dir, double size, Paint p) {
    final d = dir / dir.distance;
    final n = Offset(-d.dy, d.dx);
    final path = Path()
      ..moveTo(at.dx + d.dx * size * 0.5, at.dy + d.dy * size * 0.5)
      ..lineTo(at.dx - d.dx * size * 0.7 + n.dx * size * 0.45, at.dy - d.dy * size * 0.7 + n.dy * size * 0.45)
      ..lineTo(at.dx - d.dx * size * 0.7 - n.dx * size * 0.45, at.dy - d.dy * size * 0.7 - n.dy * size * 0.45)
      ..close();
    c.drawPath(path, p..style = PaintingStyle.fill);
  }

  void _text(Canvas c, String t, Offset at, TextStyle st, Alignment a, {double maxWidth = double.infinity}) {
    final tp = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxWidth);
    tp.paint(c, Offset(at.dx - tp.width * (a.x + 1) / 2, at.dy - tp.height * (a.y + 1) / 2));
  }

  @override
  bool shouldRepaint(McCabePainter old) => old.theme != theme || old.compact != compact;
}
