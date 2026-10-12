import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';
import 'column_geometry.dart';

/// UI clock for animation that must run at wall speed whatever the simulation speed is
/// (SCOPE.md 7.3: particle positions advance on the UI clock).
class ColumnAnimation extends ChangeNotifier {
  double time = 0;
  double bubblePhase = 0;
  double flowPhase = 0;

  /// [vaporFactor] ~ boilup / nominal, drives the rise speed; [paused] freezes bubbles.
  void tick(double dt, double vaporFactor, {bool paused = false}) {
    time += dt;
    if (!paused) {
      bubblePhase += dt * (0.25 + 0.55 * vaporFactor.clamp(0.0, 2.0));
      flowPhase += dt;
    }
    notifyListeners();
  }
}

TextPainter _tp(String text, TextStyle style, {double maxWidth = double.infinity, TextAlign align = TextAlign.left}) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
}

void _drawText(Canvas c, String text, Offset at, TextStyle style, {Alignment anchor = Alignment.topLeft, double maxWidth = double.infinity}) {
  final tp = _tp(text, style, maxWidth: maxWidth);
  final o = Offset(at.dx - tp.width * (anchor.x + 1) / 2, at.dy - tp.height * (anchor.y + 1) / 2);
  tp.paint(c, o);
}

void _arrowHead(Canvas c, Offset tip, Offset dir, double size, Paint p) {
  final d = dir / dir.distance;
  final n = Offset(-d.dy, d.dx);
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx - d.dx * size + n.dx * size * 0.4, tip.dy - d.dy * size + n.dy * size * 0.4)
    ..lineTo(tip.dx - d.dx * size - n.dx * size * 0.4, tip.dy - d.dy * size - n.dy * size * 0.4)
    ..close();
  c.drawPath(path, p..style = PaintingStyle.fill);
}

void _hatch(Canvas c, Rect r, Color color, double gap, double width, {double alpha = 1}) {
  if (r.width <= 0 || r.height <= 0) return;
  c.save();
  c.clipRect(r);
  final p = Paint()
    ..color = color.withValues(alpha: alpha)
    ..strokeWidth = width
    ..isAntiAlias = true;
  final h = r.height, w = r.width;
  for (var x = -h; x < w; x += gap) {
    c.drawLine(Offset(r.left + x, r.bottom), Offset(r.left + x + h, r.top), p);
  }
  c.restore();
}

void _dashedLine(Canvas c, Offset a, Offset b, Paint p, double on, double off, {double phase = 0}) {
  final total = (b - a).distance;
  if (total <= 0) return;
  final d = (b - a) / total;
  var s = -(phase % (on + off));
  while (s < total) {
    final s0 = math.max(0.0, s), s1 = math.min(total, s + on);
    if (s1 > s0) c.drawLine(a + d * s0, a + d * s1, p);
    s += on + off;
  }
}

/// Static line-art of the vessel (shell, trays, downcomers, overhead and bottom equipment, dimension
/// lines). Painted once per size/theme/tray count inside a RepaintBoundary.
class ColumnVesselPainter extends CustomPainter {
  final LowsysTheme theme;
  final int trays;
  final int feedStage;
  final double trayHeightM, diameterM;

  /// Broken trays: stage to open fraction s (F04), drawn as a deck with a gap and bent ends.
  final Map<int, double> broken;

  ColumnVesselPainter({required this.theme, required this.trays, required this.feedStage, this.trayHeightM = 0.6, this.diameterM = 1.2, this.broken = const {}});

  @override
  void paint(Canvas canvas, Size size) {
    final g = ColumnGeometry(size, trays, feedStage);
    final p = theme.palette;
    final st = theme.column;
    final steel = Paint()
      ..color = p.steel
      ..style = PaintingStyle.stroke
      ..strokeWidth = st.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final thin = Paint()
      ..color = p.steel.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final fine = Paint()
      ..color = p.inkMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final wall = 4.0;

    // --- shell: double walls with section hatching, elliptical heads
    final top = g.headTop, bot = g.headBot;
    for (final side in [g.shellL, g.shellR]) {
      final dir = side == g.shellL ? -1.0 : 1.0;
      final r = Rect.fromLTRB(math.min(side, side + dir * wall), g.yT0 - 2, math.max(side, side + dir * wall), g.sumpBot + 2);
      _hatch(canvas, r, p.steel, 3.2, 0.7, alpha: 0.55);
      canvas.drawLine(Offset(side, g.yT0 - 2), Offset(side, g.sumpBot + 2), steel);
      canvas.drawLine(Offset(side + dir * wall, g.yT0 - 2), Offset(side + dir * wall, g.sumpBot + 2), thin);
    }
    final topHead = Path()
      ..moveTo(g.shellL, g.yT0 - 2)
      ..quadraticBezierTo(g.shellL, top, g.cx, top)
      ..quadraticBezierTo(g.shellR, top, g.shellR, g.yT0 - 2);
    final botHead = Path()
      ..moveTo(g.shellL, g.sumpBot + 2)
      ..quadraticBezierTo(g.shellL, bot, g.cx, bot)
      ..quadraticBezierTo(g.shellR, bot, g.shellR, g.sumpBot + 2);
    canvas.drawPath(topHead, steel);
    canvas.drawPath(botHead, steel);
    // flange ticks between shell and heads
    for (final y in [g.yT0 - 2, g.sumpBot + 2]) {
      canvas.drawLine(Offset(g.shellL - wall - 3, y), Offset(g.shellR + wall + 3, y), thin);
    }
    // skirt-free saddle marks: centre line (chain-dotted)
    final cl = Paint()
      ..color = p.inkFaint
      ..strokeWidth = 0.8;
    var y = top - 6;
    var dash = true;
    while (y < bot + 12) {
      final len = dash ? 10.0 : 3.0;
      if (dash) canvas.drawLine(Offset(g.cx, y), Offset(g.cx, math.min(y + len, bot + 12)), cl);
      y += len + 3;
      dash = !dash;
    }

    // --- trays: double lines, weirs and downcomer baffles
    final compact = g.spacing < 9;
    final trayP = Paint()
      ..color = p.steel
      ..strokeWidth = compact ? 1.0 : st.trayStrokeWidth
      ..style = PaintingStyle.stroke;
    for (var j = 1; j <= trays; j++) {
      final dy = g.deckY(j);
      final (x0, x1) = g.deckX(j);
      final bs = broken[j];
      if (bs == null) {
        canvas.drawLine(Offset(x0, dy), Offset(x1, dy), trayP);
        if (!compact) canvas.drawLine(Offset(x0, dy + 2.2), Offset(x1, dy + 2.2), trayP);
      } else {
        // broken deck: the middle is missing, both ends hang down in a jagged break
        final w = x1 - x0;
        final gapL = x0 + w * (0.62 - 0.30 * bs), gapR = x0 + w * 0.62;
        final bp = Paint()
          ..color = p.alarm
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(x0, dy), Offset(gapL, dy), trayP);
        canvas.drawLine(Offset(gapR + w * 0.1, dy), Offset(x1, dy), trayP);
        canvas.drawPath(
            Path()
              ..moveTo(gapL, dy)
              ..lineTo(gapL + 2, dy + 3)
              ..lineTo(gapL - 1, dy + 5)
              ..lineTo(gapL + 3, dy + 8),
            bp);
        canvas.drawPath(
            Path()
              ..moveTo(gapR + w * 0.1, dy)
              ..lineTo(gapR + w * 0.1 - 2, dy + 4)
              ..lineTo(gapR + w * 0.1 + 1, dy + 6),
            bp);
        // fallen plate
        canvas.drawLine(Offset(gapL + 3, dy + g.spacing * 0.5), Offset(gapR + 4, dy + g.spacing * 0.62), bp);
      }
      // weir (short upstand at the downcomer end) and downcomer baffle down to the next tray
      final right = g.dcRight(j);
      final wx = right ? x1 : x0;
      final weirH = math.min(g.spacing * 0.28, 7.0);
      canvas.drawLine(Offset(wx, dy), Offset(wx, dy - weirH), trayP);
      final nextY = j < trays ? g.deckY(j + 1) : g.sumpTop + g.spacing * 0.2;
      final baffleX = wx;
      canvas.drawLine(Offset(baffleX, dy), Offset(baffleX, nextY - g.spacing * 0.28), fine);
    }

    // --- overhead: vapour line, condenser, drum, pipes
    final pipe = Paint()
      ..color = p.steel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final vy = g.condCenter.dy;
    canvas.drawPath(
        Path()
          ..moveTo(g.cx, top)
          ..lineTo(g.cx, vy)
          ..lineTo(g.condCenter.dx - g.condR, vy),
        pipe);
    // condenser: circle with zig-zag tube
    canvas.drawCircle(g.condCenter, g.condR, steel);
    final zz = Path()..moveTo(g.condCenter.dx - g.condR * 0.7, g.condCenter.dy);
    for (var i = 0; i < 4; i++) {
      final x = g.condCenter.dx - g.condR * 0.7 + (i + 0.5) * g.condR * 1.4 / 4;
      zz.lineTo(x, g.condCenter.dy + (i.isEven ? -1 : 1) * g.condR * 0.42);
    }
    zz.lineTo(g.condCenter.dx + g.condR * 0.7, g.condCenter.dy);
    canvas.drawPath(zz, thin);
    // condensate down to the drum
    canvas.drawLine(Offset(g.condCenter.dx, g.condCenter.dy + g.condR), Offset(g.condCenter.dx, g.drum.top), pipe);
    // drum: horizontal capsule
    final drumRR = RRect.fromRectAndRadius(g.drum, Radius.circular(g.drum.height / 2));
    canvas.drawRRect(drumRR, steel);
    // reflux pump and line to the first tray
    final pumpC = Offset(g.drum.left + g.drum.width * 0.22, g.drum.bottom + (g.yT0 - g.drum.bottom) * 0.45);
    final refluxY = g.deckY(1) - g.spacing * 0.55;
    canvas.drawLine(Offset(pumpC.dx, g.drum.bottom), Offset(pumpC.dx, pumpC.dy - 6), pipe);
    canvas.drawCircle(pumpC, 6, thin);
    canvas.drawLine(pumpC + const Offset(-4.2, 4.2), pumpC + const Offset(0, -6), thin);
    canvas.drawPath(
        Path()
          ..moveTo(pumpC.dx, pumpC.dy + 6)
          ..lineTo(pumpC.dx, refluxY)
          ..lineTo(g.shellR + wall, refluxY),
        pipe);
    // distillate off the right drum end
    final dx = g.drum.right - g.drum.width * 0.18;
    canvas.drawLine(Offset(dx, g.drum.bottom), Offset(dx, g.yT0 - g.spacing * 0.2), pipe);
    canvas.drawLine(Offset(dx, g.yT0 - g.spacing * 0.2), Offset(size.width - 4, g.yT0 - g.spacing * 0.2), pipe);

    // --- feed line from the left
    final fy = g.deckY(feedStage.clamp(1, trays)) - g.spacing * 0.5;
    canvas.drawLine(Offset(6, fy), Offset(g.shellL - wall, fy), pipe);

    // --- bottom: bottoms draw, reboiler loop
    final by = g.sumpBot - (g.sumpBot - g.sumpTop) * 0.18;
    canvas.drawLine(Offset(g.shellL - wall, by), Offset(6, by), pipe);
    final rb = g.reboilerCenter;
    canvas.drawCircle(rb, g.reboilerR, steel);
    final coil = Path()..moveTo(rb.dx - g.reboilerR * 0.7, rb.dy);
    for (var i = 0; i < 4; i++) {
      final x = rb.dx - g.reboilerR * 0.7 + (i + 0.5) * g.reboilerR * 1.4 / 4;
      coil.lineTo(x, rb.dy + (i.isEven ? -1 : 1) * g.reboilerR * 0.42);
    }
    coil.lineTo(rb.dx + g.reboilerR * 0.7, rb.dy);
    canvas.drawPath(coil, thin);
    final outY = g.sumpBot - (g.sumpBot - g.sumpTop) * 0.12;
    final inY = g.sumpTop + (g.sumpBot - g.sumpTop) * 0.22;
    canvas.drawPath(
        Path()
          ..moveTo(g.shellR + wall, outY)
          ..lineTo(rb.dx, outY)
          ..lineTo(rb.dx, rb.dy + g.reboilerR),
        pipe);
    canvas.drawPath(
        Path()
          ..moveTo(rb.dx, rb.dy - g.reboilerR)
          ..lineTo(rb.dx, inY)
          ..lineTo(g.shellR + wall, inY),
        pipe);

    // --- dimension lines (drafting detail)
    final dim = Paint()
      ..color = p.inkMuted
      ..strokeWidth = 0.9;
    // vertical: tray spacing, between two trays near the middle, on the right side of the shell
    final mid = math.max(2, trays ~/ 2);
    final ya = g.deckY(mid), yb = g.deckY(math.min(trays, mid + 1));
    final dxv = g.shellR + wall + 11;
    if (yb - ya > 6) {
      canvas.drawLine(Offset(dxv, ya), Offset(dxv, yb), dim);
      canvas.drawLine(Offset(g.shellR + wall + 3, ya), Offset(dxv + 5, ya), dim);
      canvas.drawLine(Offset(g.shellR + wall + 3, yb), Offset(dxv + 5, yb), dim);
      _arrowHead(canvas, Offset(dxv, ya), const Offset(0, -1), 4.5, Paint()..color = p.inkMuted);
      _arrowHead(canvas, Offset(dxv, yb), const Offset(0, 1), 4.5, Paint()..color = p.inkMuted);
      final tsText = size.width > 220 ? 'TS ${trayHeightM.toStringAsFixed(2)} m' : '${trayHeightM.toStringAsFixed(1)} m';
      _drawText(canvas, tsText, Offset(dxv + 7, (ya + yb) / 2), theme.type.label.style(12, p.inkMuted), anchor: Alignment.centerLeft);
    }
    // horizontal: diameter under the lower head
    final yd = g.headBot + size.height * 0.04;
    canvas.drawLine(Offset(g.shellL, yd), Offset(g.shellR, yd), dim);
    canvas.drawLine(Offset(g.shellL, yd - 5), Offset(g.shellL, yd + 5), dim);
    canvas.drawLine(Offset(g.shellR, yd - 5), Offset(g.shellR, yd + 5), dim);
    _arrowHead(canvas, Offset(g.shellL, yd), const Offset(-1, 0), 4.5, Paint()..color = p.inkMuted);
    _arrowHead(canvas, Offset(g.shellR, yd), const Offset(1, 0), 4.5, Paint()..color = p.inkMuted);
    _drawText(canvas, size.width > 250 ? 'Ø ${diameterM.toStringAsFixed(2)} m  ·  $trays trays' : 'Ø ${diameterM.toStringAsFixed(2)} m', Offset(g.cx, yd + 3), theme.type.label.style(12, p.inkMuted), anchor: Alignment.topCenter);
    // cross-hair registration marks in the corners (drafting sheet)
    final reg = Paint()
      ..color = p.inkFaint
      ..strokeWidth = 0.8;
    for (final c in [Offset(5, 5), Offset(size.width - 5, 5), Offset(5, size.height - 5), Offset(size.width - 5, size.height - 5)]) {
      canvas.drawLine(c + const Offset(-4, 0), c + const Offset(4, 0), reg);
      canvas.drawLine(c + const Offset(0, -4), c + const Offset(0, 4), reg);
    }
  }

  @override
  bool shouldRepaint(ColumnVesselPainter old) =>
      old.theme != theme || old.trays != trays || old.feedStage != feedStage || !_sameMap(old.broken, broken) || old.trayHeightM != trayHeightM || old.diameterM != diameterM;
}

/// Everything that moves: liquid hatching, levels, vapour bubbles, flow dashes, labels, selection.
/// Repaints from the snapshot notifier and the UI clock, never from a widget rebuild.
class ColumnLivePainter extends CustomPainter {
  final ValueListenable<SimSnapshot?> snapshot;
  final ValueListenable<int?> selected;
  final ColumnAnimation anim;
  final LowsysTheme theme;
  final bool lowQuality;
  final ValueListenable<UnitSystem> units;

  ColumnLivePainter({required this.snapshot, required this.selected, required this.anim, required this.theme, required this.units, this.lowQuality = false})
      : super(repaint: Listenable.merge([snapshot, selected, anim, units]));

  @override
  void paint(Canvas canvas, Size size) {
    final s = snapshot.value;
    if (s == null) return;
    final st = s.stages;
    final N = s.layout.nTrays;
    final nc = st.nc;
    final g = ColumnGeometry(size, N, s.layout.feedStages.first);
    final p = theme.palette;
    final num = theme.type.number;
    final lab = theme.type.label;
    const wall = 4.0;
    final sel = selected.value;

    Color compColor(int stage) => p.composition(1 - st.x[stage * nc]);

    // ---- liquid on trays and in downcomers (full hydraulics adds froth, spray, drips, flooding, foam)
    final full = s.hydraulics == HydraulicsMode.full;
    final foam = <int, double>{};
    final fouled = <int, double>{};
    final broken = <int, double>{};
    for (final f in s.visibleFaults) {
      final loc = f.location;
      if (loc.stageFrom == null) continue;
      for (var j = loc.stageFrom!; j <= math.min(loc.stageTo!, N); j++) {
        switch (f.type) {
          case FaultType.foaming:
            foam[j] = f.severity;
          case FaultType.trayFouling:
            fouled[j] = f.severity;
          case FaultType.trayDamage:
            broken[j] = f.severity;
          default:
            break;
        }
      }
    }
    final nominalHold = _median(st.holdup, 1, N);
    final hatchGapBase = g.spacing < 9 ? 3.2 : 5.0;
    final tAnim = anim.time;
    final sprayPaint = Paint()..color = p.liquidLight.withValues(alpha: 0.9);
    final dripPaint = Paint()
      ..color = p.liquidLight
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var j = 1; j <= N; j++) {
      final col = compColor(j);
      final dy = g.deckY(j);
      final (x0, x1) = g.deckX(j);
      final isBroken = broken.containsKey(j);
      final flooded = full && (st.frothFill[j] >= 1 || st.jetFlood[j] >= 1 || (st.flags[j] & 16) != 0);
      final frac = (st.hcl[j] / 0.06).clamp(0.0, 1.15);
      var hVis = math.max(1.5, frac * g.spacing * 0.62);
      if (st.hcl[j] < 0.002 && full) hVis = 1.0; // dry or dumped tray
      var hFroth = hVis;
      if (full) {
        final fr = (st.froth[j] / 0.06).clamp(0.0, 1.6) * g.spacing * 0.62;
        hFroth = math.max(hVis, math.min(fr, g.spacing * 0.98));
      }
      if (flooded) {
        hFroth = g.spacing * 0.98;
        hVis = math.max(hVis, g.spacing * 0.7);
      }
      final xa = isBroken ? x0 + (x1 - x0) * 0.62 : x0;
      final r = Rect.fromLTRB(x0 + 1, dy - hVis, (isBroken ? xa : x1) - 1, dy - 0.5);
      if (r.width > 1) {
        canvas.drawRect(r, Paint()..color = col.withValues(alpha: 0.16));
        final densify = nominalHold > 0 ? (st.holdup[j] / nominalHold).clamp(0.4, 1.8) : 1.0;
        _hatch(canvas, r, col, hatchGapBase / densify, 0.9, alpha: 0.9);
      }
      // froth layer above the clear liquid: stippled
      final fr = Rect.fromLTRB(x0 + 1, dy - hFroth, (isBroken ? xa : x1) - 1, dy - hVis);
      if (full && fr.height > 1.5 && fr.width > 1) {
        canvas.drawRect(fr, Paint()..color = p.froth.withValues(alpha: flooded ? 0.22 : 0.10));
        final dots = Paint()..color = p.froth.withValues(alpha: 0.55);
        final cols = math.max(2, (fr.width / 7).floor());
        for (var c = 0; c < cols; c++) {
          for (var rr = 0; rr < math.max(1, (fr.height / 6).floor()); rr++) {
            final u1 = _hash(j * 5.1 + c * 1.3 + rr * 7.7), u2 = _hash(j * 2.9 + c * 3.1 + rr * 1.9);
            canvas.drawCircle(Offset(fr.left + (c + u1) * fr.width / cols, fr.bottom - (rr + u2) * 6.0 - 1), 0.9 + u2 * 1.1, dots);
          }
        }
      }
      // foaming (F06): dense scalloped bubbles on the froth surface
      final foamS = foam[j] ?? 0.0;
      if (foamS > 0 && r.width > 1) {
        final topY = dy - math.max(hFroth, hVis);
        final fp = Paint()
          ..color = p.froth.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9;
        final n = (r.width / 4.5).floor();
        for (var k = 0; k < n; k++) {
          final u = _hash(j * 3.3 + k * 1.7);
          canvas.drawCircle(Offset(r.left + (k + 0.5) * r.width / n, topY - 1 - u * 2.5 * (0.5 + foamS)), 1.6 + u * 1.6 * (0.5 + foamS), fp);
        }
      }
      // surface line with a little ripple
      final topSurf = (flooded || foamS > 0) ? dy - hFroth : r.top;
      final surf = Path()..moveTo(r.left, topSurf);
      final steps = math.max(3, (r.width / 5).floor());
      for (var k = 1; k <= steps; k++) {
        final xx = r.left + r.width * k / steps;
        surf.lineTo(xx, topSurf + math.sin(tAnim * 2.2 + k * 0.9 + j) * 0.7);
      }
      canvas.drawPath(
          surf,
          Paint()
            ..color = flooded ? p.alarm : p.froth
            ..style = PaintingStyle.stroke
            ..strokeWidth = flooded ? 1.6 : 1.1);
      // entrainment spray (psi above 2 %) rising from the froth to the tray above
      if (full && j > 1) {
        final l = st.liquidDown[j], e = st.entrain[j];
        final psi = (l + e) > 0 ? e / (l + e) : 0.0;
        if (psi > 0.02) {
          final count = (3 + 40 * psi.clamp(0.0, 0.6)).round();
          final yTop = g.deckY(j - 1) + 3;
          final yBot = dy - hFroth;
          for (var k = 0; k < count; k++) {
            final u1 = _hash(j * 9.1 + k * 2.3), u2 = _hash(j * 4.7 + k * 6.1), u3 = _hash(j * 1.3 + k * 3.7);
            final ph = (u3 + anim.bubblePhase * (0.8 + u2)) % 1.0;
            final yy = yBot - ph * (yBot - yTop);
            canvas.drawCircle(Offset(x0 + 4 + u1 * (x1 - x0 - 8), yy), 0.8 + u2 * 0.7, sprayPaint);
          }
        }
      }
      // weeping drips through the deck
      final w = full ? st.weepFrac[j] : 0.0;
      final dumping = full && (st.flags[j] & 2) != 0;
      if (w > 0.05 || dumping || isBroken) {
        final count = dumping ? 8 : (2 + 10 * (isBroken ? math.max(w, broken[j]!) : w)).round();
        final nextY = j < N ? g.deckY(j + 1) - hVis - 1 : g.sumpTop;
        for (var k = 0; k < count; k++) {
          final u1 = _hash(j * 6.1 + k * 1.9), u3 = _hash(j * 2.3 + k * 4.3);
          final ph = (u3 + anim.flowPhase * 0.9) % 1.0;
          final xx = isBroken ? xa + 2 + u1 * (x1 - xa - 4) : x0 + 3 + u1 * (x1 - x0 - 6);
          final y0 = dy + 3 + ph * (nextY - dy - 6);
          canvas.drawLine(Offset(xx, y0), Offset(xx, y0 + 2.5), dripPaint);
        }
      }
      // fouling (F05): plugged holes drawn as dark ticks on the deck
      final fouledS = fouled[j] ?? 0.0;
      if (fouledS > 0 && !isBroken) {
        final fp = Paint()
          ..color = p.accent2
          ..strokeWidth = 2.0;
        final n = (4 + 8 * fouledS).round();
        for (var k = 0; k < n; k++) {
          final xx = x0 + (k + 0.5) * (x1 - x0) / n;
          canvas.drawLine(Offset(xx, dy - 1.5), Offset(xx, dy + 3.5), fp);
        }
      }
      // downcomer: liquid column from the weir to the tray below, backed up when the limit nears
      final right = g.dcRight(j);
      final dcx0 = right ? x1 : g.shellL, dcx1 = right ? g.shellR : x0;
      final nextY = j < N ? g.deckY(j + 1) : g.sumpTop + g.spacing * 0.2;
      final dcRect = Rect.fromLTRB(dcx0 + 1.5, dy + 2.5, dcx1 - 1.5, nextY - g.spacing * 0.3);
      if (dcRect.height > 2 && dcRect.width > 2) {
        canvas.drawRect(dcRect, Paint()..color = col.withValues(alpha: 0.10));
        final back = full ? st.dcFlood[j].clamp(0.0, 1.0) : 0.0;
        if (back > 0.15) {
          final level = Rect.fromLTRB(dcRect.left, dcRect.bottom - dcRect.height * back, dcRect.right, dcRect.bottom);
          _hatch(canvas, level, back > 0.95 ? p.alarm : col, 3.0, 0.9, alpha: 0.9);
        }
        final flow = Paint()
          ..color = col.withValues(alpha: 0.85)
          ..strokeWidth = 1.2;
        final cxd = (dcRect.left + dcRect.right) / 2;
        _dashedLine(canvas, Offset(cxd, dcRect.top), Offset(cxd, dcRect.bottom), flow, 4, 4, phase: -anim.flowPhase * 14);
      }
    }

    // ---- sump
    final sumpRect = Rect.fromLTRB(g.shellL + 1, g.sumpTop + g.spacing * 0.35, g.shellR - 1, g.sumpBot);
    final sumpLevel = (s.kpis.sumpLevelPct / 100).clamp(0.0, 1.0);
    final sumpLiq = Rect.fromLTRB(sumpRect.left, sumpRect.bottom - sumpRect.height * sumpLevel, sumpRect.right, sumpRect.bottom);
    final sc = compColor(N + 1);
    canvas.drawRect(sumpLiq, Paint()..color = sc.withValues(alpha: 0.2));
    _hatch(canvas, sumpLiq, sc, 4.5, 0.9, alpha: 0.9);
    canvas.drawLine(sumpLiq.topLeft, sumpLiq.topRight, Paint()
      ..color = p.froth
      ..strokeWidth = 1.3);
    _drawText(canvas, '${s.kpis.sumpLevelPct.toStringAsFixed(1)} %', Offset(sumpRect.center.dx, sumpRect.bottom - 6), num.style(12, p.ink, weight: FontWeight.w600), anchor: Alignment.bottomCenter);

    // ---- drum (horizontal capsule: fill from the bottom to the level)
    final drumLevel = (s.kpis.drumLevelPct / 100).clamp(0.0, 1.0);
    final dr = g.drum;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dr.deflate(1.2), Radius.circular(dr.height / 2)));
    final dLiq = Rect.fromLTRB(dr.left, dr.bottom - dr.height * drumLevel, dr.right, dr.bottom);
    final dc = compColor(0);
    canvas.drawRect(dLiq, Paint()..color = dc.withValues(alpha: 0.22));
    _hatch(canvas, dLiq, dc, 4.0, 0.9, alpha: 0.95);
    canvas.restore();
    _drawText(canvas, '${s.kpis.drumLevelPct.toStringAsFixed(0)}%', dr.center, num.style(12, p.ink, weight: FontWeight.w600), anchor: Alignment.center);

    // ---- vapour bubbles
    final maxParticles = lowQuality ? theme.column.maxParticlesLow : theme.column.maxParticlesHigh;
    final vNom = math.max(1e-9, st.vaporUp[N + 1]);
    final perGap = (maxParticles / (N + 1)).floor().clamp(1, 7);
    final bubble = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = p.vapor;
    for (var j = 1; j <= N; j++) {
      // vapour leaving tray j+1 rises through tray j's liquid into the space above it
      final vJ = st.vaporUp[j + 1];
      final count = (perGap * (vJ / vNom).clamp(0.0, 1.6)).round();
      if (count == 0) continue;
      final yLow = g.deckY(j) + 1;
      final yHigh = j > 1 ? g.deckY(j - 1) + 3 : g.yT0 - 4;
      final (x0, x1) = g.deckX(j);
      for (var i = 0; i < count; i++) {
        final u1 = _hash(j * 7.31 + i * 1.77), u2 = _hash(j * 3.17 + i * 5.13 + 9), u3 = _hash(j * 1.91 + i * 2.71 + 4);
        final ph = (u3 + anim.bubblePhase * (0.7 + 0.6 * u2)) % 1.0;
        final y = yLow - ph * (yLow - yHigh);
        final x = x0 + 4 + u1 * (x1 - x0 - 8) + math.sin(ph * 6.28 * 2 + u2 * 6) * 1.6;
        final r = (0.9 + u2 * 1.6) * (g.spacing < 12 ? 0.8 : 1.0);
        canvas.drawCircle(Offset(x, y), r, bubble);
      }
    }
    // boil-up bubbles in the sump
    final boil = (perGap * 1.2).round();
    for (var i = 0; i < boil; i++) {
      final u1 = _hash(100 + i * 1.3), u2 = _hash(200 + i * 2.1);
      final ph = (u2 + anim.bubblePhase * 0.9) % 1.0;
      final y = sumpLiq.bottom - ph * math.max(0.0, sumpLiq.height);
      if (sumpLiq.height > 3) canvas.drawCircle(Offset(sumpRect.left + 4 + u1 * (sumpRect.width - 8), y), 1.2 + u2, bubble);
    }

    // ---- flow arrows on pipes
    final flowP = Paint()
      ..color = p.accent
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final tag = num.style(12, p.accent);
    final narrow = size.width < 260; // phone portrait: tags only, values live in the KPI strip and inspector
    final labS = lab.style(12, p.ink);
    final uSys = units.value;
    String kmolh(double v) => uSys.fromSI(Quantity.molarFlow, v).toStringAsFixed(1);
    // feed: value above the line, tray number below
    final fy = g.deckY(s.layout.feedStages.first) - g.spacing * 0.5;
    _dashedLine(canvas, Offset(6, fy), Offset(g.shellL - wall - 2, fy), flowP, 5, 4, phase: -anim.flowPhase * 24);
    _arrowHead(canvas, Offset(g.shellL - wall, fy), const Offset(1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, narrow ? 'F' : 'F ${kmolh(s.streams[StreamId.feed]!.flow)}', Offset(5, fy - 4), tag, anchor: Alignment.bottomLeft);
    if (!narrow) _drawText(canvas, g.shellL < 90 ? 'tray ${s.layout.feedStages.first}' : 'feed tray ${s.layout.feedStages.first}', Offset(5, fy + 4), lab.style(12, p.inkMuted), anchor: Alignment.topLeft);
    // bottoms
    final by = g.sumpBot - (g.sumpBot - g.sumpTop) * 0.18;
    _dashedLine(canvas, Offset(g.shellL - wall - 2, by), Offset(8, by), flowP, 5, 4, phase: -anim.flowPhase * 24);
    _arrowHead(canvas, Offset(5, by), const Offset(-1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, narrow ? 'B' : 'B ${kmolh(s.kpis.b)}', Offset(5, by - 4), tag, anchor: Alignment.bottomLeft);
    // distillate (label above its line) and reflux (label below its line)
    final dyOut = g.yT0 - g.spacing * 0.2;
    _arrowHead(canvas, Offset(size.width - 3, dyOut), const Offset(1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, narrow ? 'D' : 'D ${kmolh(s.kpis.d)}', Offset(size.width - 6, dyOut - 3), tag, anchor: Alignment.bottomRight);
    final refluxY = g.deckY(1) - g.spacing * 0.55;
    _arrowHead(canvas, Offset(g.shellR + wall + 1, refluxY), const Offset(-1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, narrow ? 'L0' : 'L0 ${kmolh(s.streams[StreamId.reflux]!.flow)}', Offset(g.shellR + wall + 6, refluxY + 4), tag, anchor: Alignment.topLeft);
    // boilup label kept inside the panel
    final rb = g.reboilerCenter;
    final vbText = narrow ? 'V' : 'V_B ${kmolh(s.kpis.boilup)}';
    final vbW = _tp(vbText, tag).width;
    final vbX = (rb.dx - vbW / 2).clamp(g.shellR + wall + 4, size.width - vbW - 3).toDouble();
    _drawText(canvas, vbText, Offset(vbX, rb.dy + g.reboilerR + 5), tag, anchor: Alignment.topLeft);
    _drawText(canvas, 'Q', Offset(rb.dx, rb.dy - g.reboilerR - 3), labS, anchor: Alignment.bottomCenter);
    _drawText(canvas, 'CW', Offset(g.condCenter.dx, g.condCenter.dy - g.condR - 3), labS, anchor: Alignment.bottomCenter);

    // ---- selection highlight (pencil-yellow)
    if (sel != null) {
      Rect? r;
      if (sel >= 1 && sel <= N) {
        r = g.band(sel);
      } else if (sel == 0) {
        r = g.drum.inflate(3);
      } else if (sel == N + 1) {
        r = Rect.fromLTRB(g.shellL - 5, g.sumpTop, g.shellR + 5, g.sumpBot + 2);
      }
      if (r != null) {
        canvas.drawRect(r, Paint()..color = p.selection.withValues(alpha: 0.16));
        canvas.drawRect(
            r,
            Paint()
              ..color = p.selection
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
        if (sel >= 1 && sel <= N) {
          _drawText(canvas, '$sel', Offset(g.shellL - wall - 5, g.deckY(sel) - g.spacing / 2), num.style(12, p.selection, weight: FontWeight.w700), anchor: Alignment.centerRight);
        }
      }
    }
  }

  static double _hash(double v) {
    final x = math.sin(v * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  static double _median(List<double> a, int from, int to) {
    final l = <double>[for (var i = from; i <= to; i++) a[i]]..sort();
    return l.isEmpty ? 0 : l[l.length ~/ 2];
  }

  @override
  bool shouldRepaint(ColumnLivePainter old) => old.theme != theme || old.lowQuality != lowQuality;
}

bool _sameMap(Map<int, double> a, Map<int, double> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
