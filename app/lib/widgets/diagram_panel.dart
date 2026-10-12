import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../painters/profile_painter.dart';
import '../theme/lowsys_theme.dart';
import 'column_view.dart';

/// DiagramPanel tabs (SCOPE.md 3.2): McCabe-Thiele and Profiles in M2.
class DiagramBody extends StatelessWidget {
  final bool compact;
  const DiagramBody({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int>(
      valueListenable: sim.diagramTab,
      builder: (context, tab, _) {
        Widget tabBtn(String label, int i) => Expanded(
              child: InkWell(
                onTap: () => sim.diagramTab.value = i,
                child: Container(
                  height: MediaQuery.sizeOf(context).height < 500 ? 30 : 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: tab == i ? p.accent : p.gridMajor, width: tab == i ? 2.5 : 1)),
                  ),
                  child: Text(label, style: t.type.display.style(13.5, tab == i ? p.accent : p.inkMuted, weight: FontWeight.w700)),
                ),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [tabBtn(compact ? 'McCabe' : 'McCabe–Thiele', 0), tabBtn('Profiles', 1)]),
            Expanded(child: tab == 0 ? McCabeChart(compact: compact) : const ProfilesChart()),
          ],
        );
      },
    );
  }
}

class ProfilesChart extends StatelessWidget {
  const ProfilesChart({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sim = scope.sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int>(
      valueListenable: sim.profileKind,
      builder: (context, ki, _) {
        final kind = ProfileKind.values[ki];
        return Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                children: [
                  for (final k in ProfileKind.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        onTap: () => sim.profileKind.value = k.index,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k == kind ? p.accent.withValues(alpha: 0.18) : Colors.transparent,
                            border: Border.all(color: k == kind ? p.accent : p.gridMajor),
                          ),
                          child: Text(k.label, style: t.type.label.style(13, k == kind ? p.accent : p.inkMuted)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final s = sim.snapshot.value;
                    if (s == null) return;
                    final plot = profilePlotRect(size);
                    final n = s.layout.nTrays;
                    final j = ((d.localPosition.dy - plot.top) / (plot.height / n)).floor() + 1;
                    if (j >= 1 && j <= n) sim.selectStage(sim.selectedStage.value == j ? null : j);
                  },
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: ProfilePainter(snapshot: sim.snapshot, selected: sim.selectedStage, units: sim.units, kind: kind, theme: t),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
