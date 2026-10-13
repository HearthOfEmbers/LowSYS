import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../painters/crude_geometry.dart';
import '../painters/crude_painter.dart';
import '../theme/lowsys_theme.dart';
import '../theme/themes/brass.dart';

/// The crude flowsheet in the ColumnView slot (ENGINE_API.md 13.5). Pinch to zoom and pan; tap a stage, a stripper stage
/// or a stream to open the math overlay.
class CrudeFlowsheet extends StatefulWidget {
  const CrudeFlowsheet({super.key});
  @override
  State<CrudeFlowsheet> createState() => _CrudeFlowsheetState();
}

class _CrudeFlowsheetState extends State<CrudeFlowsheet> {
  final BrassNeedle _needle = BrassNeedle(0.5);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sim = scope.sim;
    final t = LowsysThemeScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return InteractiveViewer(
        maxScale: 4,
        minScale: 1,
        child: GestureDetector(
          key: const ValueKey('crude-flowsheet'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final hit = CrudeGeometry(size).hit(d.localPosition);
            switch (hit) {
              case CrudeHitStage(:final stage):
                if (stage >= 1 && stage <= 30) sim.selectStage(stage);
                sim.openMath(ExplainStage(stage));
              case CrudeHitStripper(:final stripper, :final bottom):
                sim.openMath(ExplainStripper(stripper, bottom: bottom));
              case CrudeHitProduct(:final product):
                sim.openMath(ExplainProduct(product));
              case CrudeHitPumparound():
                sim.openMath(const ExplainPumparound());
              case CrudeHitOverflash():
                sim.openMath(const ExplainOverflash());
              case CrudeHitSteam(:final point):
                sim.openMath(point == 0 ? const ExplainStage(30) : ExplainStripper(point - 1, bottom: true));
              case CrudeHitFurnace():
                sim.openMath(const ExplainStage(26));
              case null:
                sim.selectStage(null);
            }
          },
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: CrudeFlowsheetPainter(
                snapshot: sim.snapshot,
                selected: sim.selectedStage,
                anim: scope.anim,
                theme: t,
                units: sim.units,
                needle: _needle,
              ),
            ),
          ),
        ),
      );
    });
  }
}
