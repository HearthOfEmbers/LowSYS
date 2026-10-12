import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';

/// Tap a tray to see x, y, y*, L, V, holdup and E_MV (numbers only; the math overlay is M2).
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
          decoration: BoxDecoration(color: p.bgAlt.withValues(alpha: 0.75), border: Border.all(color: sel == null ? p.gridMajor : p.selection)),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
          child: sel == null
              ? Center(
                  child: Text('Tap a tray on the column or a stage on the diagram to inspect it.', style: t.type.label.style(12.5, p.inkMuted), textAlign: TextAlign.center),
                )
              : ValueListenableBuilder<SimSnapshot?>(
                  valueListenable: sim.snapshot,
                  builder: (context, s, _) => s == null ? const SizedBox() : _body(context, s, sel, sim, t),
                ),
        );
      },
    );
  }

  Widget _body(BuildContext context, SimSnapshot s, int j, SimController sim, LowsysTheme t) {
    final p = t.palette;
    final st = s.stages;
    final nc = st.nc;
    final N = s.layout.nTrays;
    final feed = s.layout.feedStages.first;
    String frac(double v) => v.toStringAsFixed(4);
    String kmolh(double v) => (v * 3.6).toStringAsFixed(1);
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
    final rows = <(String, String)>[
      ('x', frac(x)),
      if (j >= 1) ('y', frac(y)),
      if (j >= 1) ('y*', frac(ys)),
      if (j >= 1) ('L', '${kmolh(st.liquidDown[j])} kmol/h'),
      if (j >= 1) ('V', '${kmolh(st.vaporUp[j])} kmol/h'),
      ('holdup', '${(st.holdup[j] / 1000).toStringAsFixed(3)} kmol'),
      if (j >= 1 && j <= N) ('E_MV', st.efficiency[j].toStringAsFixed(3)),
      if (j == 0) ('reflux L₀', '${kmolh(s.streams[StreamId.reflux]!.flow)} kmol/h'),
      if (j == 0) ('D', '${kmolh(s.kpis.d)} kmol/h'),
      if (j == N + 1) ('B', '${kmolh(s.kpis.b)} kmol/h'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: title, style: t.type.display.style(16, p.selection, weight: FontWeight.w700)),
                TextSpan(text: '  ${section()}', style: t.type.label.style(12.5, p.inkMuted)),
              ])),
              const SizedBox(height: 4),
              Wrap(
                spacing: 14,
                runSpacing: 2,
                children: [
                  for (final r in rows)
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${r.$1} ', style: t.type.label.style(12.5, p.inkMuted)),
                      TextSpan(text: r.$2, style: t.type.number.style(13.5, p.ink)),
                    ])),
                ],
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
