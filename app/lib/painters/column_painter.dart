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

  ColumnVesselPainter({required this.theme, required this.trays, required this.feedStage, this.trayHeightM = 0.6, this.diameterM = 1.2});

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
      canvas.drawLine(Offset(x0, dy), Offset(x1, dy), trayP);
      if (!compact) canvas.drawLine(Offset(x0, dy + 2.2), Offset(x1, dy + 2.2), trayP);
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
      if (size.width > 180) {
        _drawText(canvas, 'TS ${trayHeightM.toStringAsFixed(2)} m', Offset(dxv + 7, (ya + yb) / 2), theme.type.label.style(12, p.inkMuted), anchor: Alignment.centerLeft);
      }
    }
    // horizontal: diameter under the lower head
    final yd = g.headBot + size.height * 0.04;
    canvas.drawLine(Offset(g.shellL, yd), Offset(g.shellR, yd), dim);
    canvas.drawLine(Offset(g.shellL, yd - 5), Offset(g.shellL, yd + 5), dim);
    canvas.drawLine(Offset(g.shellR, yd - 5), Offset(g.shellR, yd + 5), dim);
    _arrowHead(canvas, Offset(g.shellL, yd), const Offset(-1, 0), 4.5, Paint()..color = p.inkMuted);
    _arrowHead(canvas, Offset(g.shellR, yd), const Offset(1, 0), 4.5, Paint()..color = p.inkMuted);
    _drawText(canvas, size.width > 250 ? 'Ø ${diameterM.toStringAsFixed(2)} m  ·  $trays trays' : 'Ø ${diameterM.toStringAsFixed(2)} m', Offset(g.cx, yd - 3), theme.type.label.style(12, p.inkMuted), anchor: Alignment.bottomCenter);
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
      old.theme != theme || old.trays != trays || old.feedStage != feedStage || old.trayHeightM != trayHeightM || old.diameterM != diameterM;
}

/// Everything that moves: liquid hatching, levels, vapour bubbles, flow dashes, labels, selection.
/// Repaints from the snapshot notifier and the UI clock, never from a widget rebuild.
class ColumnLivePainter extends CustomPainter {
  final ValueListenable<SimSnapshot?> snapshot;
  final ValueListenable<int?> selected;
  final ColumnAnimation anim;
  final LowsysTheme theme;
  final bool lowQuality;

  ColumnLivePainter({required this.snapshot, required this.selected, required this.anim, required this.theme, this.lowQuality = false})
      : super(repaint: Listenable.merge([snapshot, selected, anim]));

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

    // ---- liquid on trays and in downcomers
    final nominalHold = _median(st.holdup, 1, N);
    final hatchGapBase = g.spacing < 9 ? 3.2 : 5.0;
    for (var j = 1; j <= N; j++) {
      final col = compColor(j);
      final dy = g.deckY(j);
      final (x0, x1) = g.deckX(j);
      final frac = (st.hcl[j] / 0.06).clamp(0.0, 1.15);
      final hVis = math.max(1.5, frac * g.spacing * 0.62);
      final r = Rect.fromLTRB(x0 + 1, dy - hVis, x1 - 1, dy - 0.5);
      canvas.drawRect(r, Paint()..color = col.withValues(alpha: 0.16));
      final densify = nominalHold > 0 ? (st.holdup[j] / nominalHold).clamp(0.4, 1.8) : 1.0;
      _hatch(canvas, r, col, hatchGapBase / densify, 0.9, alpha: 0.9);
      // surface line with a little ripple
      final surf = Path()..moveTo(r.left, r.top);
      final steps = math.max(3, (r.width / 5).floor());
      for (var k = 1; k <= steps; k++) {
        final xx = r.left + r.width * k / steps;
        surf.lineTo(xx, r.top + math.sin(anim.time * 2.2 + k * 0.9 + j) * 0.7);
      }
      canvas.drawPath(
          surf,
          Paint()
            ..color = p.froth
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1);
      // downcomer: liquid column from the weir to the tray below
      final right = g.dcRight(j);
      final dcx0 = right ? x1 : g.shellL, dcx1 = right ? g.shellR : x0;
      final nextY = j < N ? g.deckY(j + 1) : g.sumpTop + g.spacing * 0.2;
      final dcRect = Rect.fromLTRB(dcx0 + 1.5, dy + 2.5, dcx1 - 1.5, nextY - g.spacing * 0.3);
      if (dcRect.height > 2 && dcRect.width > 2) {
        canvas.drawRect(dcRect, Paint()..color = col.withValues(alpha: 0.10));
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
    final labS = lab.style(12, p.ink);
    String kmolh(double v) => (v * 3.6).toStringAsFixed(1);
    // feed: value above the line, tray number below
    final fy = g.deckY(s.layout.feedStages.first) - g.spacing * 0.5;
    _dashedLine(canvas, Offset(6, fy), Offset(g.shellL - wall - 2, fy), flowP, 5, 4, phase: -anim.flowPhase * 24);
    _arrowHead(canvas, Offset(g.shellL - wall, fy), const Offset(1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, 'F ${kmolh(s.streams[StreamId.feed]!.flow)}', Offset(5, fy - 4), tag, anchor: Alignment.bottomLeft);
    _drawText(canvas, g.shellL < 90 ? 'tray ${s.layout.feedStages.first}' : 'feed tray ${s.layout.feedStages.first}', Offset(5, fy + 4), lab.style(12, p.inkMuted), anchor: Alignment.topLeft);
    // bottoms
    final by = g.sumpBot - (g.sumpBot - g.sumpTop) * 0.18;
    _dashedLine(canvas, Offset(g.shellL - wall - 2, by), Offset(8, by), flowP, 5, 4, phase: -anim.flowPhase * 24);
    _arrowHead(canvas, Offset(5, by), const Offset(-1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, 'B ${kmolh(s.kpis.b)}', Offset(5, by - 4), tag, anchor: Alignment.bottomLeft);
    // distillate (label above its line) and reflux (label below its line)
    final dyOut = g.yT0 - g.spacing * 0.2;
    _arrowHead(canvas, Offset(size.width - 3, dyOut), const Offset(1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, 'D ${kmolh(s.kpis.d)}', Offset(size.width - 6, dyOut - 3), tag, anchor: Alignment.bottomRight);
    final refluxY = g.deckY(1) - g.spacing * 0.55;
    _arrowHead(canvas, Offset(g.shellR + wall + 1, refluxY), const Offset(-1, 0), 6, Paint()..color = p.accent);
    _drawText(canvas, 'L₀ ${kmolh(s.streams[StreamId.reflux]!.flow)}', Offset(g.shellR + wall + 6, refluxY + 4), tag, anchor: Alignment.topLeft);
    // boilup label kept inside the panel
    final rb = g.reboilerCenter;
    final vbText = 'V_B ${kmolh(s.kpis.boilup)}';
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
