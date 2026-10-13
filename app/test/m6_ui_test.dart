// M6 app: Equipment tab for the thermosyphon (model view and plantCalc "calc" labels), drill list entries, drill HUD and
// the Diagnose dialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/widgets/lever_panel.dart';
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
  });  testWidgets('M6 app 2: loop schematic, pause-gated reboiler switch, drill timer, field checks, saved seeds, view 2',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(LowsysApp(controller: sim));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 10);

    // sandbox: the view toggle offers plant + calculations; the reboiler switch needs a pause
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G14_thermosyphon')));
    await frames(tester, 20);
    sim.controlTab.value = 5;
    await frames(tester, 10);
    expect(find.byKey(const ValueKey('ts-schematic')), findsOneWidget);
    await tester.runAsync(() => sim.finishScenario());
    sim.leaveScenario();
    await frames(tester, 10);
    await tester.runAsync(() => sim.setTier(ThermoTier.t2));
    await frames(tester, 20);
    sim.controlTab.value = 0;
    await frames(tester, 10);
    final lp = find.descendant(of: find.byType(LeverPanel), matching: find.byType(Scrollable));
    expect(lp, findsWidgets);
    await tester.scrollUntilVisible(find.text('Plant + calculations'), 300,
        scrollable: lp.first, maxScrolls: 40);
    expect(find.text('Plant + calculations'), findsOneWidget);
    await tester.runAsync(() => sim.setLever('view', 2));
    await frames(tester, 5);
    expect(sim.snapshot.value!.view, SimView.plantCalc);
    await tester.runAsync(() => sim.setLever('view', 0));

    sim.setSpeed(1);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('lever-reboiler-type')), -300,
        scrollable: lp.first, maxScrolls: 40);
    await frames(tester, 3);
    expect(find.textContaining('pause to switch'), findsOneWidget);
    sim.setSpeed(0);
    await frames(tester, 3);
    expect(find.textContaining('pause to switch'), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('lever-reboiler-type')), matching: find.text('Thermosyphon')));
    await frames(tester, 10);
    expect(sim.snapshot.value!.reboiler.type, ReboilerType.thermosyphon);

    // drill HUD: countdown, field check, saved seed
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('H5_bottoms_swings'), seed: 4242));
    sim.setSpeed(1);
    await frames(tester, 20);
    expect(find.byKey(const ValueKey('drill-timer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drill-fc-LG-102')));
    await frames(tester, 10);
    expect(sim.snapshot.value!.fieldChecks.any((c) => c.gaugeTag == 'LG-102'), isTrue);
    expect(find.byKey(const ValueKey('drill-fc-result-LG-102')), findsOneWidget);
    await tester.runAsync(() => sim.finishScenario());
    final saved = await tester.runAsync(() => sim.savedAttempts('H5_bottoms_swings'));
    expect(saved!.single['seed'], 4242);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
