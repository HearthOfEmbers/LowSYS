import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import '../theme/themes/brass.dart';

const List<String> kCrudeProductNames = ['Naphtha', 'Kerosene', 'Diesel', 'AGO', 'Residue'];

/// Products tab of the crude unit (ENGINE_API.md 13.5): TBP curves of the feed and the five products (with the ideal cut
/// temperatures as ticks), D86 curves of the four distillates, the three 5-95 gap bars, and the yield table. In the plant
/// views the tab draws the last lab result with its sample time.
class CrudeProductsPanel extends StatelessWidget {
  final bool compact;
  const CrudeProductsPanel({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (context, s, _) {
        final data = s?.crudeProducts;
        final k = s?.kpis.crude;
        if (s == null || data == null || k == null) return const SizedBox();
        final u = sim.units.value;
        final plant = s.view.isPlant;
        return ListView(
          key: const ValueKey('crude-products'),
          padding: const EdgeInsets.all(8),
          children: [
            if (plant)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Lab result, sampled at ${_clock(k.labSampleTime)} (every 30 min, published 15 min later). The TBP curves and the true D86 are not observable on the plant.',
                  key: const ValueKey('lab-note'),
                  style: t.type.label.style(12.5, t.palette.warn),
                ),
              ),
            _Titled(
              title: S.tbpCurves,
              child: SizedBox(
                height: compact ? 170 : 210,
                child: CustomPaint(
                  size: const Size(double.infinity, 210),
                  key: const ValueKey('tbp-chart'),
                  painter: _CurvePainter(
                    t: t,
                    u: u,
                    curves: [for (var i = 0; i < data.tbp.length; i++) if (data.tbp[i].isNotEmpty) (i == 0 ? 'Feed' : kCrudeProductNames[i - 1], i, data.tbp[i])],
                    ticks: data.idealCutT,
                    xLabel: S.volDistilled,
                    markers: false,
                  ),
                ),
              ),
            ),
            _Titled(
              title: plant ? 'D86 (lab: 5, 50, 95 %)' : 'D86 curves',
              child: SizedBox(
                height: compact ? 170 : 210,
                child: CustomPaint(
                  size: const Size(double.infinity, 210),
                  key: const ValueKey('d86-chart'),
                  painter: _CurvePainter(
                    t: t,
                    u: u,
                    curves: [for (var i = 0; i < data.d86.length; i++) (kCrudeProductNames[i], i + 1, data.d86[i])],
                    ticks: null,
                    xLabel: S.volEvaporated,
                    markers: plant,
                  ),
                ),
              ),
            ),
            _Titled(title: S.n595GapsD86, child: _GapBars(gaps: data.gaps, t: t, u: u)),
            _Titled(title: S.yieldsVolOfCrude, child: _YieldTable(k: k, data: data, t: t, u: u)),
          ],
        );
      },
    );
  }
}

String _clock(double s) {
  if (s.isNaN) return '—';
  final neg = s < 0;
  final a = s.abs().round();
  return '${neg ? '−' : ''}${(a ~/ 3600).toString().padLeft(2, '0')}:${((a % 3600) ~/ 60).toString().padLeft(2, '0')}';
}

class _Titled extends StatelessWidget {
  final String title;
  final Widget child;
  const _Titled({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.type.display.style(13.5, t.palette.accent, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// A line chart of temperature against volume percent; on Brass it sits on a parchment inset in sepia ink.
class _CurvePainter extends CustomPainter {
  final LowsysTheme t;
  final UnitSystem u;
  final List<(String, int, List<({double vol, double t})>)> curves;
  final Float64List? ticks;
  final String xLabel;
  final bool markers;
  _CurvePainter({required this.t, required this.u, required this.curves, required this.ticks, required this.xLabel, required this.markers});

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.palette;
    final brass = t.id == 'brass';
    final ink = brass ? brassSepia : p.ink;
    final muted = brass ? brassSepia.withValues(alpha: 0.6) : p.inkMuted;
    final plot = Rect.fromLTRB(46, 8, size.width - 8, size.height - 34);
    if (brass) {
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, size.height), Paint()..color = brassParchment);
      canvas.drawRect(Rect.fromLTRB(1, 1, size.width - 1, size.height - 1), Paint()..color = brassFrame..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    var lo = double.infinity, hi = -double.infinity;
    for (final c in curves) {
      for (final pt in c.$3) {
        lo = math.min(lo, u.fromSI(Quantity.temperature, pt.t));
        hi = math.max(hi, u.fromSI(Quantity.temperature, pt.t));
      }
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 100;
    }
    final step = (hi - lo) > 400 ? 100.0 : 50.0;
    final y0 = (lo / step).floor() * step, y1 = (hi / step).ceil() * step + (hi == (hi / step).ceil() * step ? step : 0);
    double px(double v) => plot.left + v / 100 * plot.width;
    double py(double v) => plot.bottom - (v - y0) / (y1 - y0) * plot.height;
    final grid = Paint()..color = (brass ? brassSepia : p.grid).withValues(alpha: brass ? 0.25 : 1)..strokeWidth = 1;
    final lab = TextStyle(fontFamily: t.type.number.family, fontFamilyFallback: t.type.number.fallback, fontSize: 10.5, color: muted);
    void txt(String s, Offset o, {Alignment a = Alignment.topLeft, TextStyle? st}) {
      final tp = TextPainter(text: TextSpan(text: s, style: st ?? lab), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(o.dx - tp.width * (a.x + 1) / 2, o.dy - tp.height * (a.y + 1) / 2));
    }

    for (var y = y0; y <= y1 + 1e-9; y += step) {
      canvas.drawLine(Offset(plot.left, py(y)), Offset(plot.right, py(y)), grid);
      txt(y.toStringAsFixed(0), Offset(plot.left - 4, py(y)), a: Alignment.centerRight);
    }
    for (var x = 0; x <= 100; x += 20) {
      canvas.drawLine(Offset(px(x.toDouble()), plot.top), Offset(px(x.toDouble()), plot.bottom), grid);
      txt('$x', Offset(px(x.toDouble()), plot.bottom + 3), a: Alignment.topCenter);
    }
    txt('$xLabel · ${u.symbol(Quantity.temperature)}', Offset(plot.center.dx, size.height - 2), a: Alignment.bottomCenter);
    canvas.drawRect(plot, Paint()..color = ink.withValues(alpha: 0.7)..style = PaintingStyle.stroke..strokeWidth = 1);
    // ideal cut temperatures as ticks on the right edge
    final tk = ticks;
    if (tk != null) {
      for (final v in tk) {
        final y = py(u.fromSI(Quantity.temperature, v));
        if (y >= plot.top && y <= plot.bottom) {
          canvas.drawLine(Offset(plot.right - 9, y), Offset(plot.right, y), Paint()..color = ink..strokeWidth = 2);
        }
      }
    }
    final names = <String>[];
    for (final c in curves) {
      final col = brass ? _brassSeries[c.$2 % _brassSeries.length] : p.series[(c.$2) % p.series.length];
      final path = Path();
      var first = true;
      for (final pt in c.$3) {
        final o = Offset(px(pt.vol), py(u.fromSI(Quantity.temperature, pt.t)));
        if (first) {
          path.moveTo(o.dx, o.dy);
          first = false;
        } else {
          path.lineTo(o.dx, o.dy);
        }
        if (markers) canvas.drawCircle(o, 3, Paint()..color = col);
      }
      canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = c.$2 == 0 ? 2.2 : 1.6);
      names.add(c.$1);
    }
    var lx = plot.left + 6;
    for (var i = 0; i < curves.length; i++) {
      final col = brass ? _brassSeries[curves[i].$2 % _brassSeries.length] : p.series[curves[i].$2 % p.series.length];
      canvas.drawLine(Offset(lx, plot.top + 8), Offset(lx + 12, plot.top + 8), Paint()..color = col..strokeWidth = 2.5);
      final tp = TextPainter(text: TextSpan(text: names[i], style: lab.copyWith(color: ink)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(lx + 15, plot.top + 2));
      lx += 15 + tp.width + 8;
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}

const List<Color> _brassSeries = [Color(0xFF3B2A1A), Color(0xFF2F4F4F), Color(0xFF9A5B24), Color(0xFF6B7A2A), Color(0xFF8B2E1F), Color(0xFF5A3E7A)];

class _GapBars extends StatelessWidget {
  final List<GapBar> gaps;
  final LowsysTheme t;
  final UnitSystem u;
  const _GapBars({required this.gaps, required this.t, required this.u});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    const names = ['Kero–Naphtha', 'Diesel–Kero', 'AGO–Diesel'];
    var span = 40.0;
    for (final g in gaps) {
      if (!g.gap.isNaN) span = math.max(span, g.gap.abs() * 1.1);
    }
    return Column(
      children: [
        for (var i = 0; i < gaps.length; i++)
          Padding(
            key: ValueKey('gap-${i + 1}'),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 98, child: Text(names[i], style: t.type.label.style(12.5, p.ink))),
                Expanded(
                  child: SizedBox(
                    height: 18,
                    child: CustomPaint(painter: _BarPainter(gap: gaps[i].gap, span: span, ok: p.ok, bad: p.alarm, ink: p.gridMajor)),
                  ),
                ),
                SizedBox(
                  width: 74,
                  child: Text(
                    gaps[i].gap.isNaN ? '—' : '${gaps[i].gap >= 0 ? '+' : '−'}${u.fromSI(Quantity.temperatureDelta, gaps[i].gap.abs()).toStringAsFixed(1)} ${u.symbol(Quantity.temperatureDelta)}',
                    textAlign: TextAlign.right,
                    style: t.type.number.style(12.5, gaps[i].gap >= 0 ? p.ok : p.alarm),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  final double gap, span;
  final Color ok, bad, ink;
  _BarPainter({required this.gap, required this.span, required this.ok, required this.bad, required this.ink});
  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    canvas.drawLine(Offset(mid, 0), Offset(mid, size.height), Paint()..color = ink..strokeWidth = 1.5);
    if (gap.isNaN) return;
    final w = (gap.abs() / span).clamp(0.0, 1.0) * mid;
    canvas.drawRect(gap >= 0 ? Rect.fromLTWH(mid, 2, w, size.height - 4) : Rect.fromLTWH(mid - w, 2, w, size.height - 4), Paint()..color = gap >= 0 ? ok : bad);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.gap != gap || old.span != span;
}

class _YieldTable extends StatelessWidget {
  final CrudeProductKpis k;
  final CrudeProductData data;
  final LowsysTheme t;
  final UnitSystem u;
  const _YieldTable({required this.k, required this.data, required this.t, required this.u});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    TextStyle n(Color c) => t.type.number.style(12.5, c);
    Widget cell(String s, {bool head = false, Color? c, TextAlign a = TextAlign.right}) => Expanded(
          child: Text(s, textAlign: a, style: head ? t.type.display.style(12, p.inkMuted, weight: FontWeight.w700) : n(c ?? p.ink)),
        );
    return Column(
      children: [
        Row(children: [cell('', head: true, a: TextAlign.left), cell(S.actual, head: true), cell(S.ideal, head: true), cell('cut ${u.symbol(Quantity.temperature)}', head: true)]),
        for (var i = 0; i < 5; i++)
          Row(
            key: ValueKey('yield-$i'),
            children: [
              cell(kCrudeProductNames[i], a: TextAlign.left),
              cell(k.yieldVolPct[i].toStringAsFixed(2)),
              cell(data.idealYieldVolPct[i].toStringAsFixed(2), c: p.inkMuted),
              cell(i < 4 ? u.fromSI(Quantity.temperature, data.idealCutT[i]).toStringAsFixed(0) : '', c: p.inkMuted),
            ],
          ),
        const SizedBox(height: 4),
        Row(children: [
          cell(S.overflash, a: TextAlign.left),
          cell('${k.overflashVolPct.toStringAsFixed(2)} %'),
          cell(S.residueTbp5, a: TextAlign.right),
          cell('${u.fromSI(Quantity.temperature, k.residueTbp5).toStringAsFixed(1)} ${u.symbol(Quantity.temperature)}'),
        ]),
      ],
    );
  }
}
