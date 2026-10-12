import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';

/// xD, xB, D, B, R, drum %, sump % (SCOPE.md 8 M1). Values update through small listeners only.
class KpiStrip extends StatelessWidget {
  final bool scroll;
  const KpiStrip({super.key, this.scroll = true});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    String frac(double v) => Fmt.value(Quantity.fraction, v);
    String flow(double v) => Fmt.value(Quantity.molarFlow, v);
    final items = <(String, String Function(Kpis), String)>[
      ('xD', (k) => frac(k.xD), ''),
      ('xB', (k) => frac(k.xB), ''),
      ('D', (k) => flow(k.d), 'kmol/h'),
      ('B', (k) => flow(k.b), 'kmol/h'),
      ('R', (k) => k.refluxRatio.isNaN ? '—' : k.refluxRatio.toStringAsFixed(2), ''),
      ('Drum', (k) => k.drumLevelPct.toStringAsFixed(1), '%'),
      ('Sump', (k) => k.sumpLevelPct.toStringAsFixed(1), '%'),
    ];
    final chips = [
      for (final it in items)
        ValueListenableBuilder<SimSnapshot?>(
          valueListenable: sim.snapshot,
          builder: (_, s, __) => _Kpi(label: it.$1, value: s == null ? '—' : it.$2(s.kpis), unit: it.$3, t: t),
        ),
    ];
    final decoration = BoxDecoration(
      color: p.bgAlt.withValues(alpha: 0.7),
      border: Border.symmetric(horizontal: BorderSide(color: p.gridMajor)),
    );
    if (scroll) {
      return Container(
        height: 54,
        decoration: decoration,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6), children: chips),
      );
    }
    return Container(
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Wrap(alignment: WrapAlignment.spaceBetween, children: chips),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value, unit;
  final LowsysTheme t;
  const _Kpi({required this.label, required this.value, required this.unit, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.type.label.style(12, p.inkMuted)),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: t.type.number.style(16, p.accent, weight: FontWeight.w700)),
              if (unit.isNotEmpty) Text(' $unit', style: t.type.label.style(12, p.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
