// M6 app: Equipment tab for the thermosyphon (model view and plantCalc "calc" labels), drill list entries, drill HUD and
// the Diagnose dialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('M6 UI at 1440x900: G14 thermosyphon card, H5 drill HUD with plantCalc labels and the Diagnose dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d, forceReport: true);
    final key = GlobalKey();
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await frames(tester, 10);
    expect(sim.loaded, isTrue);

    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G14_thermosyphon')));
    await frames(tester, 20);
    sim.controlTab.value = 5;
    sim.setSpeed(10);
    await frames(tester, 60);
    expect(sim.snapshot.value!.reboiler.type, ReboilerType.thermosyphon);
    expect(find.byKey(const ValueKey('energy-thermosyphon')), findsOneWidget);
    expect(find.textContaining('Surge index'), findsOneWidget);
    await snap(tester, key, 'desktop_1440x900_g14_equipment', dir: 'm6');
    expect(tester.takeException(), isNull);

    // the drill list offers the new drills
    expect(Scenarios.allIds, contains('H5_bottoms_swings'));

    await tester.runAsync(() => sim.startScenario(Scenarios.byId('H5_bottoms_swings')));
    await frames(tester, 20);
    sim.controlTab.value = 5;
    await frames(tester, 10);
    expect(sim.snapshot.value!.view, SimView.plantCalc);
    expect(find.byKey(const ValueKey('energy-thermosyphon')), findsOneWidget);
    expect(find.textContaining('(calc)'), findsWidgets);
    expect(find.byKey(const ValueKey('drill-attempts')), findsOneWidget);
    await snap(tester, key, 'desktop_1440x900_h5_equipment_calc', dir: 'm6');

    await tester.tap(find.byKey(const ValueKey('drill-diagnose')));
    await frames(tester, 5);
    expect(find.byKey(const ValueKey('diag-cat-restriction')), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-loc-tsInletLine')), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-loc-instrument:LT-102')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diag-cat-restriction')));
    await tester.tap(find.byKey(const ValueKey('diag-loc-tsInletLine')));
    await frames(tester, 2);
    await tester.tap(find.byKey(const ValueKey('diag-submit')));
    await frames(tester, 5);
    expect(sim.scenario!.diagnosisAttemptsLeft, lessThan(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
