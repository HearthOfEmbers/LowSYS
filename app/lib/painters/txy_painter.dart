import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';
import '../theme/painter_text.dart';

/// Plot area of the T-x-y chart (shared with tap picking).
Rect txyPlotRect(Size size) {
  final bottom = size.height < 300 ? 30.0 : 44.0;
  return Rect.fromLTRB(54, 14, math.max(120.0, size.width - 14), math.max(80.0, size.height - bottom));
}

/// T-x-y and x-y diagrams of a binary (PHYSICS.md 14.4b, SCOPE.md 7.2b); theme tokens only.
class TxyPainter extends CustomPainter {
  final ValueListenable<TxyView?> view;
  final ValueListenable<SimSnapshot?> snapshot;
  final ValueListenable<McCabeThieleData?> mccabe;
  final ValueListenable<int?> selected;
  final ValueListenable<int> sub;
  final ValueListenable<UnitSystem> units;
  final LowsysTheme theme;

  TxyPainter({
    required this.view,
    required this.snapshot,
    required this.mccabe,
    required this.selected,
    required this.sub,
    required this.units,
    required this.theme,
  }) : super(repaint: Listenable.merge([view, snapshot, mccabe, selected, sub, units]));


  @override
  void paint(Canvas canvas, Size size) {
    final v = view.value;
    final s = snapshot.value;
    if (v == null || s == null) return;
    final p = theme.palette;
    final num = theme.type.number;
    final lab = theme.type.label;
    final u = units.value;
    final plot = txyPlotRect(size);
    final paper = theme.id == 'paper';
    final xy = sub.value == 1;
    final ideal = v.top.ideal;
    final azs = v.top.azeotropes;
    final nc = s.stages.nc;
    final N = s.layout.nTrays;

    double disp(double tK) => u.fromSI(Quantity.temperature, tK);
    // ---- axis range
    var tLo = double.infinity, tHi = double.negativeInfinity;
    for (final d in [v.top, ?v.bottom]) {
      for (var i = 0; i < d.x.length; i++) {
        tLo = math.min(tLo, disp(d.tBubble[i]));
        tHi = math.max(tHi, disp(d.tBubble[i]));
        tLo = math.min(tLo, disp(d.tDew[i]));
        tHi = math.max(tHi, disp(d.tDew[i]));
      }
    }
    final step = u == UnitSystem.si ? 5.0 : 10.0;
    tLo = (tLo / step).floor() * step - (xy ? 0 : step);
    tHi = (tHi / step).ceil() * step + (xy ? 0 : step);
    double px(double x) => plot.left + x * plot.width;
    double pyT(double tDisp) => plot.bottom - (tDisp - tLo) / (tHi - tLo) * plot.height;
    double pyY(double y) => plot.bottom - y * plot.height;
    final unitSym = u.symbol(Quantity.temperature);

    // ---- frame and grid
    canvas.drawRect(plot, Paint()..color = p.bgAlt.withValues(alpha: 0.55));
    final minor = Paint()
      ..color = p.grid.withValues(alpha: 0.6)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = p.gridMajor
      ..strokeWidth = 0.9;
    for (var i = 0; i <= 20; i++) {
      final x = i / 20;
      canvas.drawLine(Offset(px(x), plot.top), Offset(px(x), plot.bottom), i % 5 == 0 ? major : minor);
    }
    if (xy) {
      for (var i = 0; i <= 20; i++) {
        final y = i / 20;
        canvas.drawLine(Offset(plot.left, pyY(y)), Offset(plot.right, pyY(y)), i % 5 == 0 ? major : minor);
      }
    } else {
      var t = tLo;
      while (t <= tHi + 1e-9) {
        canvas.drawLine(Offset(plot.left, pyT(t)), Offset(plot.right, pyT(t)), major);
        t += step;
      }
    }
    canvas.drawRect(
      plot,
      Paint()
        ..color = p.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    for (var i = 0; i <= 5; i++) {
      final x = i / 5;
      _text(canvas, x.toStringAsFixed(1), Offset(px(x), plot.bottom + 4), num.style(12, p.inkMuted), Alignment.topCenter);
    }
    if (xy) {
      for (var i = 0; i <= 5; i++) {
        final y = i / 5;
        _text(canvas, y.toStringAsFixed(1), Offset(plot.left - 4, pyY(y)), num.style(12, p.inkMuted), Alignment.centerRight);
      }
    } else {
      var t = tLo;
      final every = ((tHi - tLo) / step > 8) ? 2 : 1;
      var k = 0;
      while (t <= tHi + 1e-9) {
        if (k % every == 0) {
          _text(canvas, t.toStringAsFixed(0), Offset(plot.left - 4, pyT(t)), num.style(12, p.inkMuted), Alignment.centerRight);
        }
        t += step;
        k++;
      }
    }
    final light = s.components.first;
    _text(canvas, xy ? 'x ${_cap(light)}, liquid' : 'x, y  ${_cap(light)}', Offset(plot.center.dx, plot.bottom + 19), lab.style(12, p.inkMuted), Alignment.topCenter);
    canvas.save();
    canvas.translate(10, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _text(canvas, xy ? 'y vapour' : 'T / $unitSym', Offset.zero, lab.style(12, p.inkMuted), Alignment.center);
    canvas.restore();

    canvas.save();
    canvas.clipRect(plot.inflate(2));
    final sel = selected.value;
    final st = s.stages;

    if (!xy) {
      void curve(List<Offset> pts, Color c, {double w = 2.0, bool dashed = false}) {
        if (pts.length < 2) return;
        final paint = Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeJoin = StrokeJoin.round;
        if (!dashed) {
          final path = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (final o in pts.skip(1)) {
            path.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(path, paint);
        } else {
          for (var i = 1; i < pts.length; i++) {
            final a = pts[i - 1], b = pts[i];
            final len = (b - a).distance;
            if (len < 0.01) continue;
            final dir = (b - a) / len;
            var q = 0.0;
            while (q < len) {
              canvas.drawLine(a + dir * q, a + dir * math.min(len, q + 6), paint);
              q += 10;
            }
          }
        }
      }

      for (final (d, alpha, dashed) in [(v.bottom, 0.5, true), (v.top, 1.0, false)]) {
        if (d == null) continue;
        curve([for (var i = 0; i < d.x.length; i++) Offset(px(d.x[i]), pyT(disp(d.tBubble[i])))], p.cold.withValues(alpha: alpha), dashed: dashed);
        curve([for (var i = 0; i < d.yDew.length; i++) Offset(px(d.yDew[i]), pyT(disp(d.tDew[i])))], p.hot.withValues(alpha: alpha), dashed: dashed);
      }
      // curve labels near the light end
      final tb = v.top;
      final iL = (tb.x.length * 0.18).round().clamp(1, tb.x.length - 2);
      _text(canvas, paper ? 'bubble-point curve' : 'liquid', Offset(px(tb.x[iL]) + 6, pyT(disp(tb.tBubble[iL])) + 4), lab.style(12, p.cold), Alignment.topLeft);
      _text(canvas, paper ? 'dew-point curve' : 'vapour', Offset(px(tb.yDew[iL]) - 6, pyT(disp(tb.tDew[iL])) - 4), lab.style(12, p.hot), Alignment.bottomRight);
      // azeotropes
      for (final a in azs) {
        _diamond(canvas, Offset(px(a.x), pyT(disp(a.t))), p.marker);
        final lead = Offset(px(a.x) + (a.x > 0.5 ? -26 : 26), pyT(disp(a.t)) + (a.maximumBoiling ? -22 : 22));
        canvas.drawLine(Offset(px(a.x), pyT(disp(a.t))), lead, Paint()
          ..color = p.inkMuted
          ..strokeWidth = 0.9);
        _text(canvas, '${a.maximumBoiling ? 'maximum-boiling azeotrope' : 'azeotrope'} x = ${a.x.toStringAsFixed(4)}, ${disp(a.t).toStringAsFixed(2)} $unitSym', lead, num.style(12, p.ink), a.x > 0.5 ? Alignment.centerRight : Alignment.centerLeft);
      }
      // column overlay: stages, drum and sump
      final ring = Paint()
        ..color = p.stepLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var j = 1; j <= N; j++) {
        final x = st.x[j * nc], tt = st.t[j];
        if (!tt.isFinite) continue;
        if (j == sel) continue;
        canvas.drawCircle(Offset(px(x), pyT(disp(tt))), 2.8, ring);
      }
      if (sel != null && sel >= 1 && sel <= N && st.t[sel].isFinite) {
        final o = Offset(px(st.x[sel * nc]), pyT(disp(st.t[sel])));
        final oy = Offset(px(st.y[sel * nc]), o.dy);
        canvas.drawLine(o, oy, Paint()
          ..color = p.accent
          ..strokeWidth = 1.4);
        canvas.drawCircle(oy, 2.4, Paint()..color = p.accent);
        canvas.drawCircle(o, 5, Paint()..color = p.selection);
        canvas.drawCircle(
          o,
          5,
          Paint()
            ..color = p.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        _text(canvas, '$sel', o + const Offset(-8, -6), num.style(12, p.ink, weight: FontWeight.w700), Alignment.bottomRight);
      }
      for (final (pt, name) in [(v.d, 'D'), (v.b, 'B')]) {
        if (!pt.y.isFinite) continue;
        final o = Offset(px(pt.x), pyT(disp(pt.y)));
        canvas.drawCircle(o, 4.2, Paint()..color = p.accent);
        _text(canvas, name, o + const Offset(6, -4), num.style(12, p.accent, weight: FontWeight.w700), Alignment.bottomLeft);
      }
    } else {
      canvas.drawLine(
        Offset(px(0), pyY(0)),
        Offset(px(1), pyY(1)),
        Paint()
          ..color = p.diagonal
          ..strokeWidth = 1.2,
      );
      final m = mccabe.value;
      final eq = m?.equilibriumTop ?? const <Point2>[];
      if (eq.length > 1) {
        final path = Path()..moveTo(px(eq.first.x), pyY(eq.first.y));
        for (final q in eq.skip(1)) {
          path.lineTo(px(q.x), pyY(q.y));
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = p.eqCurve
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
      for (final a in azs) {
        _diamond(canvas, Offset(px(a.x), pyY(a.x)), p.marker);
        _text(canvas, 'azeotrope x = ${a.x.toStringAsFixed(4)}', Offset(px(a.x) + (a.x > 0.5 ? -10 : 10), pyY(a.x) + (a.x > 0.5 ? 12 : -12)), num.style(12, p.ink), a.x > 0.5 ? Alignment.centerRight : Alignment.centerLeft);
      }
      final ring = Paint()
        ..color = p.stepLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var j = 1; j <= N; j++) {
        canvas.drawCircle(Offset(px(st.x[j * nc]), pyY(st.y[j * nc])), j == sel ? 5 : 2.8, j == sel ? (Paint()..color = p.selection) : ring);
      }
    }
    canvas.restore();

    // ---- banners
    final banners = <String>[
      if (ideal && !xy) 'ideal (Raoult): constant alpha has no temperatures',
      if (ideal && xy) 'curve: the constant-alpha equilibrium the column actually uses',
    ];
    var by = plot.top + 6;
    for (final b in banners) {
      final tp = TextPainter(text: TextSpan(text: b, style: lab.style(12, p.warn)), textDirection: TextDirection.ltr, textScaler: PainterText.scaler, maxLines: 1, ellipsis: '…')..layout(maxWidth: plot.width - 16);
      final r = Rect.fromLTWH(plot.left + 8, by, tp.width + 10, tp.height + 4);
      canvas.drawRect(r, Paint()..color = p.bg.withValues(alpha: 0.88));
      canvas.drawRect(
        r,
        Paint()
          ..color = p.warn
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
      tp.paint(canvas, Offset(r.left + 5, r.top + 2));
      by += r.height + 4;
    }
  }

  static String _cap(String id) => id.isEmpty ? id : id[0].toUpperCase() + id.substring(1);

  void _diamond(Canvas c, Offset o, Color color) {
    final dm = Path()
      ..moveTo(o.dx, o.dy - 6)
      ..lineTo(o.dx + 6, o.dy)
      ..lineTo(o.dx, o.dy + 6)
      ..lineTo(o.dx - 6, o.dy)
      ..close();
    c.drawPath(dm, Paint()..color = color);
  }

  void _text(Canvas c, String t, Offset at, TextStyle st, Alignment a, {double maxWidth = double.infinity}) {
    final tp = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, textScaler: PainterText.scaler, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxWidth);
    tp.paint(c, Offset(at.dx - tp.width * (a.x + 1) / 2, at.dy - tp.height * (a.y + 1) / 2));
  }

  @override
  bool shouldRepaint(TxyPainter old) => old.theme != theme;
}
