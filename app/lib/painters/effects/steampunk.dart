import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/lowsys_theme.dart';
import '../../theme/themes/brass.dart';

/// Brass ("Steamworks Refinery") ornaments: domed rivets, gear outlines and dial gauges. Static strokes and fills
/// only, so they cost nothing per frame beyond the painters that already repaint.

/// A domed rivet: dark rim, brass body, a small highlight up and to the left.
void drawRivet(Canvas canvas, Offset c, double r, ThemePalette p) {
  canvas.drawCircle(c + Offset(r * 0.25, r * 0.3), r, Paint()..color = Colors.black.withValues(alpha: 0.45));
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.45),
        colors: [p.froth, p.accent, p.accent2, p.liquidHeavy],
        stops: const [0, 0.35, 0.8, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
}

/// A slotted screw head, for frame corners.
void drawScrew(Canvas canvas, Offset c, double r, ThemePalette p, {double angle = 0.6}) {
  drawRivet(canvas, c, r, p);
  final d = Offset(math.cos(angle), math.sin(angle)) * (r * 0.7);
  canvas.drawLine(
    c - d,
    c + d,
    Paint()
      ..color = p.bgAlt
      ..strokeWidth = math.max(1.0, r * 0.28)
      ..strokeCap = StrokeCap.round,
  );
}

/// Outline of a spur gear with [teeth] teeth, a hub and four spokes.
Path gearPath(Offset c, double r, int teeth) {
  final path = Path();
  final root = r * 0.84, step = 2 * math.pi / teeth;
  for (var i = 0; i < teeth; i++) {
    final a = i * step;
    final pts = [
      (root, a),
      (r, a + step * 0.12),
      (r, a + step * 0.42),
      (root, a + step * 0.54),
    ];
    for (var k = 0; k < pts.length; k++) {
      final (rr, aa) = pts[k];
      final o = c + Offset(math.cos(aa), math.sin(aa)) * rr;
      if (i == 0 && k == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
  }
  path.close();
  path.addOval(Rect.fromCircle(center: c, radius: r * 0.62));
  path.addOval(Rect.fromCircle(center: c, radius: r * 0.16));
  for (var k = 0; k < 4; k++) {
    final a = k * math.pi / 2 + math.pi / 4;
    final u = Offset(math.cos(a), math.sin(a));
    path.moveTo((c + u * r * 0.16).dx, (c + u * r * 0.16).dy);
    path.lineTo((c + u * r * 0.62).dx, (c + u * r * 0.62).dy);
  }
  return path;
}

/// Walnut grain and faint gear silhouettes behind the panels.
void paintBrassBackdrop(Canvas canvas, Size size, ThemePalette p) {
  final rnd = math.Random(11);
  final grain = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1;
  for (var y = 0.0; y < size.height; y += 5 + rnd.nextDouble() * 6) {
    grain.color = (rnd.nextBool() ? p.surface : p.bgAlt).withValues(alpha: 0.55);
    final path = Path()..moveTo(0, y);
    final amp = 1 + rnd.nextDouble() * 2.5, len = 140 + rnd.nextDouble() * 220, phase = rnd.nextDouble() * 6;
    for (var x = 0.0; x <= size.width; x += 12) {
      path.lineTo(x, y + amp * math.sin(x / len * 2 * math.pi + phase));
    }
    canvas.drawPath(path, grain);
  }
  final gear = Paint()
    ..color = p.gridMajor.withValues(alpha: 0.26)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final big = size.shortestSide * 0.42;
  canvas.drawPath(gearPath(Offset(size.width * 0.06, size.height * 0.98), big, 18), gear);
  canvas.drawPath(gearPath(Offset(size.width * 0.06 + big * 1.45, size.height * 0.98 - big * 0.62), big * 0.58, 12), gear);
  canvas.drawPath(gearPath(Offset(size.width * 0.97, size.height * 0.04), big * 0.7, 14), gear);
}

/// Riveted brass plate frame around a panel, with slotted screws at the corners.
void paintBrassFrame(Canvas canvas, Size size, ThemePalette p) {
  final outer = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
  canvas.drawRect(
    outer,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.froth, p.accent, p.accent2, p.liquidHeavy],
        stops: const [0, 0.3, 0.7, 1],
      ).createShader(outer),
  );
  canvas.drawRect(
    outer.deflate(3),
    Paint()
      ..color = p.liquidHeavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8,
  );
  const inset = 6.0, gap = 46.0, r = 1.9;
  final inner = outer.deflate(inset);
  void edge(Offset a, Offset b) {
    final len = (b - a).distance;
    final n = math.max(1, (len / gap).floor());
    for (var i = 1; i < n; i++) {
      drawRivet(canvas, Offset.lerp(a, b, i / n)!, r, p);
    }
  }

  edge(inner.topLeft, inner.topRight);
  edge(inner.bottomLeft, inner.bottomRight);
  edge(inner.topLeft, inner.bottomLeft);
  edge(inner.topRight, inner.bottomRight);
  for (final c in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
    drawScrew(canvas, c, 3.2, p, angle: c.dx * 0.37 + c.dy * 0.11);
  }
}

/// Brass shell plating for a column wall strip [r]: a rolled-metal gradient and a row of rivets.
void paintBrassWall(Canvas canvas, Rect r, double rivetStep, ThemePalette p) {
  canvas.drawRect(
    r,
    Paint()
      ..shader = LinearGradient(
        colors: [p.accent2, p.froth.withValues(alpha: 0.9), p.accent, p.liquidHeavy],
        stops: const [0, 0.35, 0.6, 1],
      ).createShader(r),
  );
  for (var y = r.top + rivetStep / 2; y < r.bottom - 2; y += rivetStep) {
    drawRivet(canvas, Offset(r.center.dx, y), 1.3, p);
  }
}

/// A brass-bezel dial gauge on a parchment face, 0-100 % over 270 degrees, with a red zone above 85 %.
void paintDialGauge(Canvas canvas, Offset c, double r, double pct, ThemePalette p, {String? label}) {
  canvas.drawCircle(c + const Offset(0.8, 1.2), r + 2.2, Paint()..color = Colors.black.withValues(alpha: 0.4));
  canvas.drawCircle(
    c,
    r + 2.2,
    Paint()
      ..shader = SweepGradient(colors: [p.accent, p.froth, p.accent2, p.liquidHeavy, p.accent])
          .createShader(Rect.fromCircle(center: c, radius: r + 2.2)),
  );
  canvas.drawCircle(c, r, Paint()..color = brassParchment);
  const a0 = 0.75 * math.pi, sweep = 1.5 * math.pi;
  final face = Rect.fromCircle(center: c, radius: r * 0.78);
  canvas.drawArc(
    face,
    a0 + sweep * 0.85,
    sweep * 0.15,
    false,
    Paint()
      ..color = p.alarm.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16,
  );
  final tick = Paint()
    ..color = brassSepia
    ..strokeWidth = 0.8;
  for (var i = 0; i <= 10; i++) {
    final a = a0 + sweep * i / 10;
    final u = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(c + u * r * (i.isEven ? 0.62 : 0.72), c + u * r * 0.88, tick);
  }
  if (label != null && r >= 9) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: brassSepia, fontSize: r * 0.42, fontFamily: 'Courier Prime')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c + Offset(-tp.width / 2, r * 0.3));
  }
  final v = pct.isFinite ? (pct / 100).clamp(0.0, 1.0) : 0.0;
  final a = a0 + sweep * v;
  final u = Offset(math.cos(a), math.sin(a));
  canvas.drawLine(
    c - u * r * 0.18,
    c + u * r * 0.82,
    Paint()
      ..color = brassSepia
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round,
  );
  drawRivet(canvas, c, math.max(1.4, r * 0.14), p);
}

/// Rivets around a round vessel (condenser, reboiler) and a faint brass fill behind its stroke.
void paintRivetRing(Canvas canvas, Offset c, double r, ThemePalette p, {int n = 10}) {
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        colors: [p.accent.withValues(alpha: 0.35), p.surfaceAlt.withValues(alpha: 0.6)],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
  for (var i = 0; i < n; i++) {
    final a = i * 2 * math.pi / n;
    drawRivet(canvas, c + Offset(math.cos(a), math.sin(a)) * (r - 3), 1.2, p);
  }
}

/// A riveted collar where two shell courses meet, standing out from both walls.
void paintCollar(Canvas canvas, double left, double right, double y, ThemePalette p) {
  for (final r in [Rect.fromLTRB(left - 3, y - 2, left + 1, y + 2), Rect.fromLTRB(right - 1, y - 2, right + 3, y + 2)]) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.froth, p.accent, p.liquidHeavy],
        ).createShader(r),
    );
  }
}
