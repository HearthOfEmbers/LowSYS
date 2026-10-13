import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'loops_panel.dart' show checkColor;

/// C6 (PHYSICS.md 14.6): the plant-view temperature profile. Dots at the instrumented trays, the reference profile as
/// a ghost line and a bar chart of the change since the reference per TI, flagged TIs in red. A lying TI is a lone
/// bar; a real process change is a smooth wave of bars.
class TrayTemperatureCard extends StatelessWidget {
  final List<CrossCheckResult> checks;
  const TrayTemperatureCard({super.key, required this.checks});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final live = checks.where((c) => c.status != CheckStatus.notAvailable).toList();
    final flagged = checks.where((c) => c.status == CheckStatus.fail).map((c) => c.id.substring(3)).toList();
    final worst = checks.fold<CheckStatus>(CheckStatus.ok, (a, c) {
      if (c.status == CheckStatus.notAvailable) return a;
      return c.status.index > a.index && c.status.index <= CheckStatus.fail.index ? c.status : a;
    });
    return Container(
      key: const ValueKey('c6-card'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.5),
        border: Border(left: BorderSide(color: checkColor(p, live.isEmpty ? null : worst), width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(S.c6TrayTemperatures, style: t.type.display.style(14, p.ink, weight: FontWeight.w700)),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(44, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: sim.setTemperatureReference,
                child: Text(S.setReference, style: t.type.label.style(13, p.accent, weight: FontWeight.w700)),
              ),
            ],
          ),
          if (live.isEmpty)
            Text(S.collectingData, style: t.type.label.style(12.5, p.inkFaint))
          else ...[
            SizedBox(
              height: 118,
              child: CustomPaint(
                size: Size.infinite,
                painter: _C6Painter(t, live),
              ),
            ),
            Text(
              flagged.isEmpty
                  ? 'Readings rise down the column and no TI stands out from its neighbours.'
                  : 'Flagged: ${flagged.join(', ')}. A lone bar is a lying TI; a smooth wave of bars is a real change.',
              style: t.type.label.style(12.5, flagged.isEmpty ? p.inkMuted : p.alarm),
            ),
          ],
        ],
      ),
    );
  }
}

class _C6Painter extends CustomPainter {
  final LowsysTheme t;
  final List<CrossCheckResult> cs;
  _C6Painter(this.t, this.cs);

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.palette;
    final n = cs.length;
    if (n < 2) return;
    final top = Rect.fromLTWH(34, 2, size.width - 40, 60);
    final bars = Rect.fromLTWH(34, 70, size.width - 40, 36);
    final means = [for (final c in cs) c.terms['mean'] ?? double.nan];
    final dT = [for (final c in cs) c.terms['dT'] ?? double.nan];
    final ref = [for (var k = 0; k < n; k++) means[k] - dT[k]];
    final all = [...means, ...ref.where((v) => v.isFinite)].where((v) => v.isFinite).toList();
    if (all.isEmpty) return;
    var lo = all.reduce((a, b) => a < b ? a : b), hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) {
      lo -= 0.5;
      hi += 0.5;
    }
    double xAt(int k) => top.left + top.width * (k + 0.5) / n;
    double yAt(double v) => top.bottom - top.height * (v - lo) / (hi - lo);
    final grid = Paint()
      ..color = p.gridMajor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRect(top, grid);
    canvas.drawRect(bars, grid);
    void label(String s, Offset o, {Alignment a = Alignment.centerRight, Color? c}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: t.type.number.style(10.5, c ?? p.inkMuted)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(o.dx - tp.width * (a.x + 1) / 2, o.dy - tp.height * (a.y + 1) / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    label((hi - 273.15).toStringAsFixed(0), Offset(top.left - 3, top.top + 6));
    label((lo - 273.15).toStringAsFixed(0), Offset(top.left - 3, top.bottom - 6));
    // reference ghost line
    final ghost = Path();
    var started = false;
    for (var k = 0; k < n; k++) {
      if (!ref[k].isFinite || dT[k].isNaN) continue;
      final o = Offset(xAt(k), yAt(ref[k]));
      if (!started) {
        ghost.moveTo(o.dx, o.dy);
        started = true;
      } else {
        ghost.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      ghost,
      Paint()
        ..color = p.inkFaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // readings
    final line = Path();
    for (var k = 0; k < n; k++) {
      final o = Offset(xAt(k), yAt(means[k]));
      k == 0 ? line.moveTo(o.dx, o.dy) : line.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = p.inkMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (var k = 0; k < n; k++) {
      final f = cs[k].status == CheckStatus.fail;
      canvas.drawCircle(Offset(xAt(k), yAt(means[k])), f ? 4.5 : 3.2, Paint()..color = f ? p.alarm : p.ink);
    }
    // bars of the change since the reference
    final maxD = dT.where((v) => v.isFinite).fold<double>(1.0, (m, v) => v.abs() > m ? v.abs() : m);
    final mid = bars.center.dy;
    canvas.drawLine(Offset(bars.left, mid), Offset(bars.right, mid), grid);
    for (var k = 0; k < n; k++) {
      if (!dT[k].isFinite) continue;
      final h = (bars.height / 2) * dT[k] / maxD;
      final f = cs[k].status == CheckStatus.fail;
      final w = (top.width / n) * 0.55;
      canvas.drawRect(
        Rect.fromLTRB(xAt(k) - w / 2, h >= 0 ? mid - h : mid, xAt(k) + w / 2, h >= 0 ? mid : mid - h),
        Paint()..color = f ? p.alarm : (cs[k].status == CheckStatus.check ? p.warn : p.inkMuted),
      );
    }
    label('+${maxD.toStringAsFixed(1)}', Offset(bars.left - 3, bars.top + 6));
    label('K', Offset(bars.left - 3, mid));
    for (var k = 0; k < n; k++) {
      label(cs[k].id.substring(6), Offset(xAt(k), size.height - 2), a: Alignment.bottomCenter);
    }
  }

  @override
  bool shouldRepaint(_C6Painter old) => old.cs != cs || old.t != t;
}
