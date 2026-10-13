import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'column_view.dart';
import 'figure_chrome.dart';
import 'txy_chart.dart';

/// DiagramPanel tabs (SCOPE.md 3.2): McCabe-Thiele, T-x-y (binaries only, M5) and Profiles; the Profiles chart is
/// built by the caller through [profiles]. Paper adds figure captions, the margin note and "Export figure".
class DiagramShell extends StatefulWidget {
  final bool compact;
  final Widget profiles;
  const DiagramShell({super.key, this.compact = false, required this.profiles});
  @override
  State<DiagramShell> createState() => _DiagramShellState();
}

class _DiagramShellState extends State<DiagramShell> {
  final GlobalKey _fig = GlobalKey();

  Future<void> _export(BuildContext context, int tab) async {
    final sim = AppScope.of(context).sim;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await exportFigure(_fig,
          preset: sim.presetId,
          tab: (kDiagramNames[tab] ?? 'figure')
              .toLowerCase()
              .replaceAll('–', '-'));
      messenger.showSnackBar(SnackBar(content: Text('Figure saved: $path')));
    } on Object catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not save the figure: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final paper = t.id == 'paper';
    return ListenableBuilder(
      listenable: Listenable.merge([sim.diagramTab, sim]),
      builder: (context, _) {
        final order = sim.diagramTabOrder;
        final cur = order.contains(sim.diagramTab.value)
            ? sim.diagramTab.value
            : 0;
        Widget tabBtn(String label, int i) => Expanded(
              child: InkWell(
                onTap: () => sim.diagramTab.value = i,
                child: Container(
                  height: MediaQuery.sizeOf(context).height < 500 ? 30 : 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: cur == i ? p.accent : p.gridMajor,
                        width: cur == i ? 2.5 : 1,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: t.type.display.style(
                      13.5,
                      cur == i ? p.accent : p.inkMuted,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
        String label(int id) => switch (id) {
              0 => compact ? 'McCabe' : 'McCabe–Thiele',
              2 => 'T-x-y',
              _ => 'Profiles',
            };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final id in order) tabBtn(label(id), id),
                if (paper)
                  IconButton(
                    key: const ValueKey('export-figure'),
                    tooltip: 'Export figure (PNG)',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.image_outlined,
                        color: p.inkMuted, size: 20),
                    onPressed: () => _export(context, cur),
                  ),
              ],
            ),
            ValueListenableBuilder<SimSnapshot?>(
              valueListenable: sim.snapshot,
              builder: (context, s, _) {
                if (s != null &&
                    s.tier == ThermoTier.t1 &&
                    sim.config.tier1CannotRepresent) {
                  return Container(
                    key: const ValueKey('tier1-cannot'),
                    margin: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration:
                        BoxDecoration(border: Border.all(color: p.warn, width: 1)),
                    child: Text(
                      'Tier 1 cannot represent this system: constant alpha has no azeotrope. Switch to Tier 3.',
                      style: t.type.label.style(12, p.warn),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            Expanded(
              child: ValueListenableBuilder<SimSnapshot?>(
                valueListenable: sim.snapshot,
                builder: (context, s, _) {
                  if (s?.view.isPlant == true) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Not available on a real plant. The analysers show xD and xB, and the Balance tab checks the meters against each other.',
                          textAlign: TextAlign.center,
                          style: t.type.label.style(14, p.inkMuted),
                        ),
                      ),
                    );
                  }
                  final chart = switch (cur) {
                    0 => McCabeChart(compact: compact),
                    2 => TxyChart(compact: compact),
                    _ => widget.profiles,
                  };
                  if (!paper || s == null) return chart;
                  final n = order.indexOf(cur) + 1;
                  return ValueListenableBuilder<int?>(
                    valueListenable: sim.selectedStage,
                    builder: (context, sel, _) => Stack(
                      children: [
                        RepaintBoundary(
                          key: _fig,
                          child: Container(
                            color: p.surface,
                            child: Column(
                              children: [
                                Expanded(child: chart),
                                FigureCaption(
                                  text: figureCaption(n, kDiagramNames[cur]!,
                                      sim.config, s, sim.units.value),
                                  transient: cur == 0 && !s.steady.isSteady,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (sel != null &&
                            sel >= 1 &&
                            sel <= s.layout.nTrays &&
                            !compact)
                          Positioned(
                              right: 8,
                              top: 8,
                              child: MarginNote(
                                  s: s, stage: sel, u: sim.units.value)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
