import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../painters/txy_painter.dart';
import '../theme/lowsys_theme.dart';

/// The T-x-y tab (binaries only) with its x-y sub-view (SCOPE.md 7.2b, PHYSICS.md 14.4b).
class TxyChart extends StatelessWidget {
  final bool compact;
  const TxyChart({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ValueListenableBuilder<int>(
            valueListenable: sim.txySub,
            builder: (context, sub, _) => Row(
              children: [
                const SizedBox(width: 6),
                for (final (i, name) in [(0, S.txy), (1, S.xy)])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      key: ValueKey('txy-sub-$i'),
                      onTap: () => sim.txySub.value = i,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: sub == i
                              ? p.accent.withValues(alpha: 0.18)
                              : Colors.transparent,
                          border: Border.all(
                              color: sub == i ? p.accent : p.gridMajor),
                        ),
                        child: Text(name,
                            style: t.type.label.style(
                                13, sub == i ? p.accent : p.inkMuted)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final size = Size(c.maxWidth, c.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final v = sim.txy.value;
                  final s = sim.snapshot.value;
                  if (v == null || s == null) return;
                  // pick the nearest stage point (x_j, T_j) of the T-x-y view
                  if (sim.txySub.value != 0) return;
                  final plot = txyPlotRect(size);
                  final u = sim.units.value;
                  var tLo = double.infinity, tHi = double.negativeInfinity;
                  for (final dd in [v.top, ?v.bottom]) {
                    for (var i = 0; i < dd.x.length; i++) {
                      for (final tk in [dd.tBubble[i], dd.tDew[i]]) {
                        final tv = u.fromSI(Quantity.temperature, tk);
                        if (tv < tLo) tLo = tv;
                        if (tv > tHi) tHi = tv;
                      }
                    }
                  }
                  final step = u == UnitSystem.si ? 5.0 : 10.0;
                  tLo = (tLo / step).floor() * step - step;
                  tHi = (tHi / step).ceil() * step + step;
                  int? best;
                  var bestD = 22.0;
                  for (var j = 1; j <= s.layout.nTrays; j++) {
                    final tt = s.stages.t[j];
                    if (!tt.isFinite) continue;
                    final o = Offset(
                        plot.left + s.stages.x[j * s.stages.nc] * plot.width,
                        plot.bottom -
                            (u.fromSI(Quantity.temperature, tt) - tLo) /
                                (tHi - tLo) *
                                plot.height);
                    final dist = (o - d.localPosition).distance;
                    if (dist < bestD) {
                      bestD = dist;
                      best = j;
                    }
                  }
                  sim.selectStage(best == sim.selectedStage.value ? null : best);
                },
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: TxyPainter(
                      view: sim.txy,
                      snapshot: sim.snapshot,
                      mccabe: sim.mccabe,
                      selected: sim.selectedStage,
                      sub: sim.txySub,
                      units: sim.units,
                      theme: t,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
