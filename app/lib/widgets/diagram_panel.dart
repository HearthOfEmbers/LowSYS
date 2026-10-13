import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../painters/profile_painter.dart';
import '../theme/lowsys_theme.dart';
import 'diagram_head.dart';

/// DiagramPanel body: the tab shell (diagram_head.dart) around the Profiles chart.
class DiagramBody extends StatelessWidget {
  final bool compact;
  const DiagramBody({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) =>
      DiagramShell(compact: compact, profiles: const ProfilesChart());
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
                            color: k == kind
                                ? p.accent.withValues(alpha: 0.18)
                                : Colors.transparent,
                            border: Border.all(
                              color: k == kind ? p.accent : p.gridMajor,
                            ),
                          ),
                          child: Text(
                            k.label,
                            style: t.type.label.style(
                              13,
                              k == kind ? p.accent : p.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final s = sim.snapshot.value;
                      if (s == null) return;
                      final plot = profilePlotRect(size);
                      final n = s.layout.nTrays;
                      final j =
                          ((d.localPosition.dy - plot.top) / (plot.height / n))
                              .floor() +
                          1;
                      if (j >= 1 && j <= n)
                        sim.selectStage(
                          sim.selectedStage.value == j ? null : j,
                        );
                    },
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: ProfilePainter(
                          snapshot: sim.snapshot,
                          selected: sim.selectedStage,
                          units: sim.units,
                          kind: kind,
                          theme: t,
                          ghost: sim.tierGhost,
                        ),
                      ),
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
