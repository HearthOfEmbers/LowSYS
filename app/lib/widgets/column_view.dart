import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../painters/column_geometry.dart';
import '../painters/column_painter.dart';
import '../painters/mccabe_painter.dart';
import '../theme/lowsys_theme.dart';

/// Animated column: a static vessel layer (cached in a RepaintBoundary) under a live layer that repaints
/// from the snapshot notifier and the UI clock. Tap a tray to inspect it.
class ColumnView extends StatelessWidget {
  const ColumnView({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sim = scope.sim;
    final t = LowsysThemeScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final s = sim.snapshot.value;
          if (s == null) return;
          final g = ColumnGeometry(size, s.layout.nTrays, s.layout.feedStages.first);
          final stream = g.hitStream(d.localPosition);
          if (stream != null) {
            sim.openMath(ExplainStream(stream));
            return;
          }
          final hit = g.hitTest(d.localPosition);
          sim.selectStage(hit == sim.selectedStage.value ? null : hit);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: ListenableBuilder(
                listenable: Listenable.merge([sim.structure, sim.brokenStages]),
                builder: (_, __) => CustomPaint(
                  isComplex: true,
                  willChange: false,
                  painter: ColumnVesselPainter(
                    theme: t,
                    trays: sim.structure.value.trays,
                    feedStage: sim.structure.value.feed,
                    broken: sim.brokenStages.value,
                    trayHeightM: sim.config.traySection.geometry.traySpacing,
                    diameterM: sim.config.traySection.geometry.diameter,
                  ),
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: ColumnLivePainter(snapshot: sim.snapshot, selected: sim.selectedStage, anim: scope.anim, theme: t, units: sim.units, shading: sim.compositionShading),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// The McCabe-Thiele chart; tap near a stage corner to select that tray.
class McCabeChart extends StatelessWidget {
  final bool compact;
  const McCabeChart({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final data = sim.mccabe.value;
          if (data == null) return;
          final plot = mccabePlotRect(size);
          int? best;
          var bestD = 22.0;
          for (final corner in data.corners) {
            final o = Offset(plot.left + corner.x * plot.width, plot.bottom - corner.y * plot.height);
            final dist = (o - d.localPosition).distance;
            if (dist < bestD) {
              bestD = dist;
              best = corner.stage;
            }
          }
          sim.selectStage(best == sim.selectedStage.value ? null : best);
        },
        child: RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: McCabePainter(data: sim.mccabe, snapshot: sim.snapshot, selected: sim.selectedStage, theme: t, compact: compact),
          ),
        ),
      );
    });
  }
}
