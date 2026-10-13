import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';
import 'figure_write.dart';
import '../theme/themes/paper.dart';

/// Names of the diagram tabs by id (0 McCabe-Thiele, 1 Profiles, 2 T-x-y).
const Map<int, String> kDiagramNames = {0: 'McCabe–Thiele', 1: 'Profiles', 2: 'T-x-y', 3: 'Products'};

String _clock(double t) {
  final s = t.floor();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}';
}

/// Paper figure caption (SCOPE.md 7.2): "Figure n — <diagram>, <system>, Tier <k> (<model>), P = ..., t = hh:mm:ss".
String figureCaption(int n, String diagram, ColumnConfig cfg, SimSnapshot s, UnitSystem u) {
  final model = switch (s.tier) {
    ThermoTier.t1 => '',
    ThermoTier.t2 => ' (Raoult)',
    ThermoTier.t3 => switch (cfg.tier3Model) {
        Tier3Model.nrtl => ' (NRTL)',
        Tier3Model.dePriester => ' (DePriester)',
        Tier3Model.sameAsTier2 => ' (Raoult)',
      },
  };
  final p = s.kpis.pTop.isFinite ? s.kpis.pTop : cfg.condenser.pTopDesign;
  return 'Figure $n — $diagram, ${cfg.displayName.toLowerCase()}, Tier ${s.tier.index + 1}$model, '
      'P = ${u.fromSI(Quantity.pressure, p).toStringAsFixed(3)} ${u.symbol(Quantity.pressure)}, t = ${_clock(s.time)}';
}

/// The caption line under a Paper diagram, with the "transient" note in accent2.
class FigureCaption extends StatelessWidget {
  final String text;
  final bool transient;
  const FigureCaption({super.key, required this.text, this.transient = false});

  @override
  Widget build(BuildContext context) {
    final p = LowsysThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text, style: paperSerif(12, p.inkMuted)),
          if (transient) TextSpan(text: '  — transient: operating lines are not yet consistent', style: paperSerif(12, p.accent2)),
        ]),
      ),
    );
  }
}

/// Margin note of the selected tray (Paper): a 160 dp box, Source Serif 4 italic, ink on surface.
class MarginNote extends StatelessWidget {
  final SimSnapshot s;
  final int stage;
  final UnitSystem u;
  const MarginNote({super.key, required this.s, required this.stage, required this.u});

  static String sig4(double v) {
    if (!v.isFinite) return '—';
    if (v == 0) return '0';
    final e = (v.abs() == 0) ? 0 : (v.abs().toStringAsExponential(3).split('e')[1]);
    final ex = int.parse(e.toString());
    final dec = (3 - ex).clamp(0, 6);
    return v.toStringAsFixed(dec);
  }

  @override
  Widget build(BuildContext context) {
    final p = LowsysThemeScope.of(context).palette;
    final st = s.stages;
    final nc = st.nc;
    final j = stage;
    final rows = <String>[
      'Tray $j',
      if (st.t[j].isFinite) 'T = ${sig4(u.fromSI(Quantity.temperature, st.t[j]))} ${u.symbol(Quantity.temperature)}',
      'x = ${sig4(st.x[j * nc])}',
      'y = ${sig4(st.y[j * nc])}',
      'y* = ${sig4(st.yStar[j * nc])}',
      'L = ${sig4(u.fromSI(Quantity.molarFlow, st.liquidDown[j]))} ${u.symbol(Quantity.molarFlow)}',
      'V = ${sig4(u.fromSI(Quantity.molarFlow, st.vaporUp[j]))} ${u.symbol(Quantity.molarFlow)}',
    ];
    return Container(
      width: 160,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.inkFaint, width: 0.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final r in rows) Text(r, style: paperSerif(12, p.ink))],
      ),
    );
  }
}

/// Writes the figure PNG (Paper "Export figure", SCOPE.md 7.2). Without `path_provider` (no new downloads): Windows
/// uses the Downloads folder, falling back to Documents; Android the app's external files folder; others the temp dir.
Future<String> exportFigure(GlobalKey key, {required String preset, required String tab}) async {
  final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final size = b.size;
  var ratio = 3.0;
  final longest = size.longestSide * ratio;
  if (longest > 4096) ratio = 4096 / size.longestSide;
  final img = await b.toImage(pixelRatio: ratio);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final name = 'lowsys_${preset}_${tab}_${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
  return writeFigureBytes(bytes!.buffer.asUint8List(), name);
}
