import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/widgets/fault_panel.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

void main() {
  setUpAll(loadFonts);

  final sizes = <String, Size>{
    'portrait_360x800': const Size(360, 800),
    'landscape_800x360': const Size(800, 360),
    'desktop_1440x900': const Size(1440, 900),
  };

  for (final e in sizes.entries) {
    testWidgets('M3 UI at ${e.key}: loops, balance, trends, alarms, plant view, scenario, save', (tester) async {
      tester.view.physicalSize = e.value;
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
      expect(sim.snapshot.value!.view, SimView.model);
      expect(sim.snapshot.value!.instruments, isNotEmpty);
      expect(sim.runner.config.hydraulics, HydraulicsMode.full);
      expect(sim.snapshot.value!.levers['noise'], 1, reason: 'noise is on in the sandbox');
      sim.setSpeed(30);
      await frames(tester, 60);

      // loops tab with an open faceplate
      sim.controlTab.value = 1;
      sim.selectedLoop.value = 'FC-102';
      await frames(tester, 5);
      expect(find.text('FC-102'), findsWidgets);
      await snap(tester, key, '${e.key}_loops', dir: 'm3');
      expect(tester.takeException(), isNull);

      // a bad signal: shed to MAN, BAD alarm in the banner
      await sim.injectFault(const FaultSpec(
          type: FaultType.transmitter, location: FaultLocation.tag('LT-101'), severity: 1, params: {'kind': 'signalLossLow'}));
      await frames(tester, 40);
      expect(sim.snapshot.value!.alarms.any((a) => a.id == 'LT-101.BAD'), isTrue);
      expect(find.textContaining('LT-101'), findsWidgets);
      sim.selectedLoop.value = 'LC-101';
      await frames(tester, 5);
      await snap(tester, key, '${e.key}_alarm_bad_pv', dir: 'm3');
      expect(tester.takeException(), isNull);

      // balance tab
      sim.controlTab.value = 2;
      await sim.setCheckWindow(300);
      await frames(tester, 5);
      await snap(tester, key, '${e.key}_balance_collecting', dir: 'm3');
      await sim.injectFault(const FaultSpec(
          type: FaultType.instrument, location: FaultLocation.tag('FT-102'), severity: 0.4, params: {'kind': 'bias', 'sign': 1}));
      sim.setSpeed(300);
      await frames(tester, 200);
      sim.setSpeed(30);
      await snap(tester, key, '${e.key}_balance', dir: 'm3');
      expect(tester.takeException(), isNull);

      // trends tab
      sim.controlTab.value = 3;
      sim.trendTags.value = const ['PV:FT-102', 'PV:LT-101', 'PV:LT-102'];
      await frames(tester, 10);
      await snap(tester, key, '${e.key}_trends', dir: 'm3');
      expect(tester.takeException(), isNull);

      // faults tab: instrument card
      sim.controlTab.value = 4;
      await frames(tester, 3);
      await tester.scrollUntilVisible(find.textContaining('Instrument fault'), 300, scrollable: find.descendant(of: find.byType(FaultPanel), matching: find.byType(Scrollable)).first);
      await frames(tester, 3);
      expect(find.textContaining('Instrument fault'), findsWidgets);
      await snap(tester, key, '${e.key}_faults_instrument', dir: 'm3');
      expect(tester.takeException(), isNull);

      // plant view
      sim.controlTab.value = 0;
      await sim.setLever('view', 1);
      await frames(tester, 30);
      expect(sim.snapshot.value!.view, SimView.plant);
      sim.selectStage(7);
      await frames(tester, 3);
      await snap(tester, key, '${e.key}_plant_view', dir: 'm3');
      expect(tester.takeException(), isNull);
      await sim.setLever('view', 0);

      // sandbox save and load
      await sim.saveSandbox(1);
      expect(await sim.saveStore!.read('sandbox.slot.1'), isNotNull);
      expect(await sim.loadSandbox(1), isTrue);
      await frames(tester, 10);
      expect(tester.takeException(), isNull);

      // scenario with an answer objective
      await sim.startScenario(Scenarios.byId('G3_total_reflux'));
      await frames(tester, 20);
      expect(find.text('Total reflux and Fenske'), findsWidgets);
      await snap(tester, key, '${e.key}_scenario_g3', dir: 'm3');
      await sim.finishScenario();
      await frames(tester, 10);
      expect(sim.scoreCard, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
