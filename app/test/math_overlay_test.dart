import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('every explain target renders at 360 px without overflow, in SI and US units', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d, forceReport: true);
    final sim = SimController();
    await tester.pumpWidget(LowsysApp(controller: sim));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 5);
    final targets = <ExplainTarget>[
      for (var j = 0; j <= 21; j += 3) ExplainStage(j),
      const ExplainStage(20),
      for (final id in [StreamId.feed, StreamId.reflux, StreamId.distillate, StreamId.bottoms, StreamId.boilup]) ExplainStream(id),
      const ExplainCondenser(),
      const ExplainReboiler(),
      const ExplainFeed(),
      const ExplainLoop('LC-101'),
      for (final e in McCabeElement.values) ExplainMcCabe(e),
    ];
    for (final u in [0, 1]) {
      if (u == 1) sim.toggleUnits();
      for (final t in targets) {
        await sim.openMath(t);
        await frames(tester, 2);
        expect(tester.takeException(), isNull, reason: '$t');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
