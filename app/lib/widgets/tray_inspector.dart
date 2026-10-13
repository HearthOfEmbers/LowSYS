import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';

/// Tap a tray to see x, y, y*, L, V, holdup and E_MV, plus the hydraulic indicators with full hydraulics.
/// "Equations" opens the math overlay for the stage.
class TrayInspector extends StatelessWidget {
  /// Collapse to nothing when no stage is selected (used where space is tight).
  final bool hideWhenEmpty;
  const TrayInspector({super.key, this.hideWhenEmpty = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int?>(
      valueListenable: sim.selectedStage,
      builder: (context, sel, _) {
        if (sel == null && hideWhenEmpty) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: p.bgAlt.withValues(alpha: 0.97),
            border: Border.all(color: sel == null ? p.gridMajor : p.selection),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
          child: sel == null
              ? Center(
                  child: Text(
                    'Tap a tray on the column or a stage on the diagram to inspect it.',
                    style: t.type.label.style(12.5, p.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                )
              : ValueListenableBuilder<UnitSystem>(
                  valueListenable: sim.units,
                  builder: (context, u, _) =>
                      ValueListenableBuilder<SimSnapshot?>(
                        valueListenable: sim.snapshot,
                        builder: (context, s, _) => s == null
                            ? const SizedBox()
                            : _body(context, s, sel, sim, t, u),
                      ),
                ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    SimSnapshot s,
    int j,
    SimController sim,
    LowsysTheme t,
    UnitSystem u,
  ) {
    final p = t.palette;
    if (s.view == SimView.plant) {
      return Text(
        'Not observable on a real plant: tray compositions and flows are not measured. Use the Loops, Balance and Trends tabs.',
        style: t.type.label.style(13, p.inkMuted),
      );
    }
    final st = s.stages;
    final nc = st.nc;
    final N = s.layout.nTrays;
    final feed = s.layout.feedStages.first;
    final full = s.hydraulics == HydraulicsMode.full;
    String frac(double v) => v.toStringAsFixed(4);
    String flow(double v) =>
        '${u.fromSI(Quantity.molarFlow, v).toStringAsFixed(1)} ${u.symbol(Quantity.molarFlow)}';
    String section() {
      if (j == 0) return 'condenser drum';
      if (j == N + 1) return 'sump and reboiler (equilibrium stage)';
      if (j == feed) return 'feed tray';
      return j < feed ? 'rectifying section' : 'stripping section';
    }

    final title = j == 0
        ? 'Drum'
        : j == N + 1
        ? 'Sump'
        : 'Tray $j';
    final x = st.x[j * nc], y = st.y[j * nc], ys = st.yStar[j * nc];
    final t2 = s.tier != ThermoTier.t1 && !st.t[j].isNaN;
    final rows = <(String, String)>[
      if (t2)
        (
          'T',
          '${Fmt.value(Quantity.temperature, st.t[j], u)} ${u.symbol(Quantity.temperature)}',
        ),
      if (t2)
        (
          'P',
          '${Fmt.value(Quantity.pressure, st.p[j], u)} ${u.symbol(Quantity.pressure)}',
        ),
      ('x', frac(x)),
      if (j >= 1) ('y', frac(y)),
      if (j >= 1) ('y*', frac(ys)),
      if (j >= 1) ('L', flow(st.liquidDown[j])),
      if (j >= 1) ('V', flow(st.vaporUp[j])),
      (
        'holdup',
        '${u.fromSI(Quantity.molarAmount, st.holdup[j]).toStringAsFixed(3)} ${u.symbol(Quantity.molarAmount)}',
      ),
      if (j >= 1 && j <= N) ('E_MV', st.efficiency[j].toStringAsFixed(3)),
      if (full && j >= 1 && j <= N)
        (
          'dP',
          '${u.fromSI(Quantity.pressureDelta, st.dp[j]).toStringAsFixed(u == UnitSystem.si ? 2 : 3)} ${u.symbol(Quantity.pressureDelta)}',
        ),
      if (full && j >= 1 && j <= N)
        ('flood', '${(100 * st.jetFlood[j]).toStringAsFixed(0)} %'),
      if (full && j >= 1 && j <= N)
        ('downcomer', '${(100 * st.dcFlood[j]).toStringAsFixed(0)} %'),
      if (full && j >= 1 && j <= N && st.weepFrac[j] > 0)
        ('weeping', '${(100 * st.weepFrac[j]).toStringAsFixed(0)} %'),
      if (full && j >= 1 && j <= N)
        (
          'froth',
          '${u.fromSI(Quantity.smallLength, st.froth[j]).toStringAsFixed(u == UnitSystem.si ? 0 : 1)} ${u.symbol(Quantity.smallLength)}',
        ),
      if (j == 0) ('reflux L0', flow(s.streams[StreamId.reflux]!.flow)),
      if (j == 0) ('D', flow(s.kpis.d)),
      if (j == N + 1) ('B', flow(s.kpis.b)),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: t.type.display.style(
                        16,
                        p.selection,
                        weight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: '  ${section()}',
                      style: t.type.label.style(12.5, p.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 14,
                runSpacing: 2,
                children: [
                  for (final r in rows)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${r.$1} ',
                            style: t.type.label.style(12.5, p.inkMuted),
                          ),
                          TextSpan(
                            text: r.$2,
                            style: t.type.number.style(13.5, p.ink),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => sim.openMath(ExplainStage(j)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.functions, size: 18, color: p.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Equations',
                        style: t.type.label.style(
                          13.5,
                          p.accent,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Close',
            icon: Icon(Icons.close, size: 18, color: p.inkMuted),
            onPressed: () => sim.selectStage(null),
          ),
        ),
      ],
    );
  }
}
