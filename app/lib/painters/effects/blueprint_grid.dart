import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/lowsys_theme.dart';

/// Static drafting-paper backdrop: minor/major ruled grid, paper grain and vignette.
/// Cheap by construction: lines only, painted once into a RepaintBoundary and re-painted only when
/// the size or theme changes (SCOPE.md 7.3).
class BlueprintBackdropPainter extends CustomPainter {
  final LowsysTheme theme;
  BlueprintBackdropPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final p = theme.palette;
    canvas.drawRect(Offset.zero & size, Paint()..color = p.bg);
    if (theme.effects.blueprintGrid) {
      const step = 16.0;
      final minor = Paint()
        ..color = p.grid.withValues(alpha: 0.30)
        ..strokeWidth = 0.5;
      final major = Paint()
        ..color = p.gridMajor.withValues(alpha: 0.38)
        ..strokeWidth = 0.9;
      var i = 0;
      for (var x = 0.0; x <= size.width; x += step, i++) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
      }
      i = 0;
      for (var y = 0.0; y <= size.height; y += step, i++) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? major : minor);
      }
    }
    if (theme.effects.paperGrain) {
      // deterministic speckle, a few hundred points
      final rnd = math.Random(7);
      final dot = Paint()..color = p.ink.withValues(alpha: 0.035);
      final n = (size.width * size.height / 1800).clamp(40, 900).toInt();
      for (var k = 0; k < n; k++) {
        canvas.drawCircle(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height), 0.7, dot);
      }
    }
    if (theme.effects.vignette) {
      final shader = RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: [Colors.transparent, p.bgAlt.withValues(alpha: 0.55)],
        stops: const [0.55, 1.0],
      ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(BlueprintBackdropPainter old) => old.theme != theme;
}

/// Drafting-sheet frame with corner ticks and a hand-lettered title, used around panels.
class SheetFramePainter extends CustomPainter {
  final LowsysTheme theme;
  final String title;
  SheetFramePainter(this.theme, this.title);

  @override
  void paint(Canvas canvas, Size size) {
    final p = theme.palette;
    final outer = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    canvas.drawRect(
        outer,
        Paint()
          ..color = p.gridMajor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    final inner = outer.deflate(3);
    canvas.drawRect(
        inner,
        Paint()
          ..color = p.gridMajor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6);
    final tick = Paint()
      ..color = p.ink
      ..strokeWidth = 1.3;
    const t = 9.0;
    for (final c in [outer.topLeft, outer.topRight, outer.bottomLeft, outer.bottomRight]) {
      final sx = c.dx < size.width / 2 ? 1.0 : -1.0, sy = c.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawLine(c, c + Offset(sx * t, 0), tick);
      canvas.drawLine(c, c + Offset(0, sy * t), tick);
    }
  }

  @override
  bool shouldRepaint(SheetFramePainter old) => old.theme != theme || old.title != title;
}
