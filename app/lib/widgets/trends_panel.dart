import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../painters/effects/glow.dart';
import '../theme/lowsys_theme.dart';

/// Trends tab: auto-scaled strip charts of the 5-s trend bins. Each pixel column draws the min-max envelope of
/// its bins, so one-second spikes survive decimation, and the mean line on top (ENGINE_API.md 5.4).
class TrendsPanel extends StatefulWidget {
  final ScrollController? controller;
  final Widget? header;
  const TrendsPanel({super.key, this.controller, this.header});
  @override
  State<TrendsPanel> createState() => _TrendsPanelState();
}

class _TrendsPanelState extends State<TrendsPanel> {
  double spanSeconds = 1800;
  bool showOp = false;

  static const spans = [
    (600.0, '10 min'),
    (1800.0, '30 min'),
    (3600.0, '1 h'),
    (7200.0, '2 h'),
  ];

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([sim.snapshot, sim.units, sim.trendTags]),
      builder: (context, _) {
        final s = sim.snapshot.value;
        if (s == null) return const SizedBox();
        final tags = sim.trendTags.value;
        final u = sim.units.value;
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (widget.header != null) widget.header!,
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                for (final r in s.instruments)
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      r.tag,
                      style: t.type.label.style(
                        12,
                        tags.contains('PV:${r.tag}') ? p.bgAlt : p.ink,
                      ),
                    ),
                    selected: tags.contains('PV:${r.tag}'),
                    selectedColor: p.accent,
                    showCheckmark: false,
                    onSelected: (on) {
                      final cur = [...tags];
                      on ? cur.add('PV:${r.tag}') : cur.remove('PV:${r.tag}');
                      sim.trendTags.value = cur;
                    },
                  ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final sp in spans)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      sp.$2,
                      style: t.type.label.style(
                        12,
                        spanSeconds == sp.$1 ? p.bgAlt : p.ink,
                      ),
                    ),
                    selected: spanSeconds == sp.$1,
                    selectedColor: p.accent,
                    onSelected: (_) => setState(() => spanSeconds = sp.$1),
                  ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    'OP',
                    style: t.type.label.style(12, showOp ? p.bgAlt : p.ink),
                  ),
                  selected: showOp,
                  selectedColor: p.accent,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => showOp = v),
                ),
              ],
            ),
            for (var ci = 0; ci < tags.length; ci++)
              if (s.instruments.any((r) => 'PV:${r.tag}' == tags[ci]))
                _Chart(
                  name: tags[ci].substring(3),
                  color: p.series[ci % p.series.length],
                  snap: s,
                  trends: sim.trends,
                  span: spanSeconds,
                  showOp: showOp,
                  units: u,
                  t: t,
                ),
          ],
        );
      },
    );
  }
}

class _Chart extends StatelessWidget {
  final String name;
  final Color color;
  final SimSnapshot snap;
  final TrendBuffer trends;
  final double span;
  final bool showOp;
  final UnitSystem units;
  final LowsysTheme t;
  const _Chart({
    required this.name,
    required this.color,
    required this.snap,
    required this.trends,
    required this.span,
    required this.showOp,
    required this.units,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    final r = snap.instruments.firstWhere((x) => x.tag == name);
    final loop = r.loopTag;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.5),
        border: Border.all(color: p.gridMajor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: t.type.display.style(
                  14,
                  p.accent,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${Fmt.value(r.quantity, r.value, units)} ${units.symbol(r.quantity)}',
                style: t.type.number.style(13, p.ink),
              ),
              const Spacer(),
              if (r.quality != Quality.good)
                Text(
                  r.qualityText ?? r.quality.name,
                  style: t.type.number.style(
                    12,
                    p.alarm,
                    weight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 110,
            child: CustomPaint(
              size: Size.infinite,
              painter: TrendPainter(
                color: color,
                t: t,
                trends: trends,
                reading: r,
                loop: loop,
                span: span,
                showOp: showOp,
                units: units,
                now: snap.time,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrendPainter extends CustomPainter {
  final LowsysTheme t;
  final TrendBuffer trends;
  final InstrumentReading reading;
  final String? loop;
  final double span, now;
  final bool showOp;
  final UnitSystem units;
  final Color color;
  TrendPainter({
    required this.color,
    required this.t,
    required this.trends,
    required this.reading,
    required this.loop,
    required this.span,
    required this.showOp,
    required this.units,
    required this.now,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.palette;
    final tb = trends;
    final i = tb.indexOf('PV:${reading.tag}');
    if (i == null || tb.count < 2) return;
    final sp = loop == null ? null : tb.indexOf('SP:$loop');
    final op = loop == null || !showOp ? null : tb.indexOf('OP:$loop');
    final bins = math.min(tb.count, (span / TrendBuffer.binSeconds).round());
    final first = tb.count - bins;
    // y range: data min/max, at least 10 sigma_disp (healthy fuzz fills about a fifth of the plot)
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var k = first; k < tb.count; k++) {
      lo = math.min(lo, tb.minAt(i, k));
      hi = math.max(hi, tb.maxAt(i, k));
      if (sp != null) {
        lo = math.min(lo, tb.mean(sp, k));
        hi = math.max(hi, tb.mean(sp, k));
      }
    }
    final minRange = 10 * reading.typicalSigma;
    if (hi - lo < minRange) {
      final mid = 0.5 * (hi + lo);
      lo = mid - minRange / 2;
      hi = mid + minRange / 2;
    }
    final pad = 0.05 * (hi - lo);
    lo -= pad;
    hi += pad;
    const left = 40.0;
    final area = Rect.fromLTWH(
      left,
      2,
      size.width - left - 2,
      size.height - 16,
    );
    double x(int k) =>
        area.left + area.width * (k - first) / math.max(1, bins - 1);
    double y(double v) =>
        area.bottom - area.height * ((v - lo) / (hi - lo)).clamp(-0.1, 1.1);
    final grid = Paint()
      ..color = p.grid
      ..style = PaintingStyle.stroke;
    canvas.drawRect(area, grid);
    // BAD / OOS bins
    final badPaint = Paint()..color = p.alarm.withValues(alpha: 0.18);
    for (var k = first; k < tb.count; k++) {
      if (tb.qualityAt(i, k) >= Quality.bad.index) {
        canvas.drawRect(
          Rect.fromLTRB(x(k) - 0.5, area.top, x(k) + 1.5, area.bottom),
          badPaint,
        );
      }
    }
    // envelope per pixel column
    final env = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final cols = area.width.floor().clamp(1, 2000);
    for (var c = 0; c < cols; c++) {
      final k0 = first + (c * bins / cols).floor();
      final k1 = math.min(
        tb.count - 1,
        first + (((c + 1) * bins) / cols).ceil() - 1,
      );
      var mn = double.infinity, mx = double.negativeInfinity;
      for (var k = k0; k <= math.max(k0, k1); k++) {
        mn = math.min(mn, tb.minAt(i, k));
        mx = math.max(mx, tb.maxAt(i, k));
      }
      final cx = area.left + c + 0.5;
      canvas.drawLine(Offset(cx, y(mn)), Offset(cx, y(mx)), env);
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var k = first; k < tb.count; k++) {
      final pt = Offset(x(k), y(tb.mean(i, k)));
      k == first ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    strokeGlow(canvas, path, line, GlowBudget.of(t));
    final isa = t.chart.lineStyle == LineStyle.glow;
    if (sp != null) {
      final spPath = Path();
      for (var k = first; k < tb.count; k++) {
        final pt = Offset(x(k), y(tb.mean(sp, k)));
        k == first ? spPath.moveTo(pt.dx, pt.dy) : spPath.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        isa ? dashedPath(spPath, t.chart.dashOn, t.chart.dashOff) : spPath,
        Paint()
          ..color = isa ? p.ink : p.ok
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
    if (op != null) {
      final opPath = Path();
      for (var k = first; k < tb.count; k++) {
        final pt = Offset(
          x(k),
          area.bottom - area.height * (tb.mean(op, k) / 100).clamp(0.0, 1.0),
        );
        k == first ? opPath.moveTo(pt.dx, pt.dy) : opPath.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        opPath,
        Paint()
          ..color = isa ? p.inkMuted : p.warn
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }
    void label(String s, Offset o) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: t.type.number.style(10, p.inkMuted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    label(Fmt.value(reading.quantity, hi, units), Offset(2, area.top));
    label(Fmt.value(reading.quantity, lo, units), Offset(2, area.bottom - 12));
    label(
      '-${(bins * TrendBuffer.binSeconds / 60).round()} min',
      Offset(area.left, size.height - 12),
    );
    label('now', Offset(area.right - 22, size.height - 12));
  }

  @override
  bool shouldRepaint(TrendPainter old) => true;
}
