import 'package:flutter/material.dart';

import '../../theme/lowsys_theme.dart';

/// Control Room signature effect (SCOPE.md 7.2): a trend or curve gets one blurred stroke under a sharp stroke.
/// At most [LowsysTheme.effects].glowStrokesMax strokes per frame get the glow (Low quality: none).
class GlowBudget {
  int left;
  GlowBudget(this.left);
  factory GlowBudget.of(LowsysTheme t, {bool lowQuality = false}) =>
      GlowBudget(lowQuality || t.chart.lineStyle != LineStyle.glow ? 0 : t.effects.glowStrokesMax);
}

/// Draws [path] with [paint]; when the theme glows and the budget allows, a blurred copy is drawn first.
void strokeGlow(Canvas canvas, Path path, Paint paint, GlowBudget budget) {
  if (budget.left > 0 && paint.style == PaintingStyle.stroke) {
    budget.left--;
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color.withValues(alpha: 0.5 * paint.color.a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth + 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }
  canvas.drawPath(path, paint);
}

/// A dashed copy of [src] (on/off lengths in pixels).
Path dashedPath(Path src, double on, double off) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, (d + on).clamp(0.0, m.length)), Offset.zero);
      d += on + off;
    }
  }
  return out;
}
