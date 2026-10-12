import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';

class _Item {
  final String label;
  final String Function(Kpis, UnitSystem) value;
  final String Function(UnitSystem) unit;
  final ExplainTarget? target;
  final Color? Function(Kpis, ThemePalette)? tone;
  const _Item(this.label, this.value, this.unit, {this.target, this.tone});
}

/// xD, xB, D, B, R, drum %, sump % and, with full hydraulics, column dP and max flood % (SCOPE.md 3.2, 8 M1/M2).
/// Every tappable value opens the math overlay.
class KpiStrip extends StatelessWidget {
  final bool scroll;
  const KpiStrip({super.key, this.scroll = true});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    String frac(double v) => Fmt.value(Quantity.fraction, v);
    String flow(UnitSystem u, double v) => u.fromSI(Quantity.molarFlow, v).toStringAsFixed(1);
    final items = <_Item>[
      _Item('xD', (k, u) => frac(k.xD), (u) => '', target: const ExplainStream(StreamId.distillate)),
      _Item('xB', (k, u) => frac(k.xB), (u) => '', target: const ExplainStream(StreamId.bottoms)),
      _Item('D', (k, u) => flow(u, k.d), (u) => u.symbol(Quantity.molarFlow), target: const ExplainStream(StreamId.distillate)),
      _Item('B', (k, u) => flow(u, k.b), (u) => u.symbol(Quantity.molarFlow), target: const ExplainStream(StreamId.bottoms)),
      _Item('R', (k, u) => k.refluxRatio.isNaN ? '—' : k.refluxRatio.toStringAsFixed(2), (u) => '', target: const ExplainCondenser()),
      _Item('Drum', (k, u) => k.drumLevelPct.toStringAsFixed(1), (u) => '%', target: const ExplainCondenser()),
      _Item('Sump', (k, u) => k.sumpLevelPct.toStringAsFixed(1), (u) => '%', target: const ExplainReboiler()),
      _Item('dP', (k, u) => k.columnDp <= 0 ? '—' : u.fromSI(Quantity.pressureDelta, k.columnDp).toStringAsFixed(u == UnitSystem.si ? 2 : 2), (u) => u.symbol(Quantity.pressureDelta)),
      _Item('Flood', (k, u) => k.maxFloodPct <= 0 ? '—' : k.maxFloodPct.toStringAsFixed(0), (u) => '%',
          tone: (k, pal) => k.maxFloodPct >= 100 ? pal.alarm : (k.maxFloodPct >= 90 ? pal.warn : null)),
    ];
    final decoration = BoxDecoration(
      color: p.bgAlt.withValues(alpha: 0.7),
      border: Border.symmetric(horizontal: BorderSide(color: p.gridMajor)),
    );
    final chips = ValueListenableBuilder<UnitSystem>(
      valueListenable: sim.units,
      builder: (context, u, _) => ValueListenableBuilder<SimSnapshot?>(
        valueListenable: sim.snapshot,
        builder: (_, s, __) {
          final k = s?.kpis;
          final kids = [
            for (final it in items)
              if (!(it.label == 'dP' || it.label == 'Flood') || (s != null && s.hydraulics == HydraulicsMode.full))
                InkWell(
                  onTap: it.target == null ? null : () => sim.openMath(it.target!),
                  child: _Kpi(
                    label: it.label,
                    value: k == null ? '—' : it.value(k, u),
                    unit: it.unit(u),
                    color: k == null ? null : it.tone?.call(k, p),
                    t: t,
                  ),
                ),
          ];
          return scroll
              ? ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6), children: kids)
              : Wrap(alignment: WrapAlignment.spaceEvenly, children: kids);
        },
      ),
    );
    if (scroll) return Container(height: 54, decoration: decoration, child: chips);
    return Container(decoration: decoration, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: chips);
  }
}

class _Kpi extends StatelessWidget {
  final String label, value, unit;
  final Color? color;
  final LowsysTheme t;
  const _Kpi({required this.label, required this.value, required this.unit, required this.t, this.color});

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
              Text(value, style: t.type.number.style(16, color ?? p.accent, weight: FontWeight.w700)),
              if (unit.isNotEmpty) Text(' $unit', style: t.type.label.style(12, p.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
