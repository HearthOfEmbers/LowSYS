import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
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
    testWidgets('M2 UI at ${e.key}: hydraulics, faults, math overlay, profiles, units, scenario', (tester) async {
      tester.view.physicalSize = e.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d, forceReport: true);
      final key = GlobalKey();
      final sim = SimController();
      await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await frames(tester, 10);
      expect(sim.loaded, isTrue);
      expect(sim.snapshot.value!.hydraulics, HydraulicsMode.full);
      sim.setSpeed(30);

      // faults: broken tray, foaming, fouling and a feed upset, all visible in the animation
      await sim.injectFault(const FaultSpec(type: FaultType.trayDamage, location: FaultLocation.stages(6, 6), severity: 1.0));
      await sim.injectFault(const FaultSpec(type: FaultType.foaming, location: FaultLocation.stages(12, 18), severity: 0.5, ramp: 60));
      await sim.injectFault(const FaultSpec(type: FaultType.trayFouling, location: FaultLocation.stages(2, 4), severity: 0.5));
      await frames(tester, 200);
      expect(sim.brokenStages.value.containsKey(6), isTrue);
      await snap(tester, key, '${e.key}_faults', dir: 'm2');
      expect(tester.takeException(), isNull);

      sim.selectStage(11);
      await frames(tester, 3);
      await snap(tester, key, '${e.key}_inspector', dir: 'm2');
      expect(tester.takeException(), isNull);

      // math overlay for a tray and a stream, opened in well under 100 ms
      final sw = Stopwatch()..start();
      await sim.openMath(const ExplainStage(7));
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(100));
      await frames(tester, 5);
      expect(find.textContaining('Tray 7'), findsWidgets);
      await snap(tester, key, '${e.key}_math_tray', dir: 'm2');
      await sim.openMath(const ExplainStream(StreamId.distillate));
      await frames(tester, 3);
      expect(find.textContaining('Distillate'), findsWidgets);
      sim.closeMath();
      await frames(tester, 2);

      // units and profiles
      sim.toggleUnits();
      sim.selectStage(7);
      sim.diagramTab.value = 1;
      sim.profileKind.value = 1;
      await frames(tester, 5);
      await snap(tester, key, '${e.key}_profiles_us', dir: 'm2');
      expect(tester.takeException(), isNull);
      sim.toggleUnits();
      sim.diagramTab.value = 0;
      sim.controlTab.value = 1;
      await frames(tester, 3);
      await snap(tester, key, '${e.key}_faults_tab', dir: 'm2');
      sim.controlTab.value = 0;

      // scenario flow
      await sim.startScenario(ScenarioLibrary.byId('G11_flooding'));
      await frames(tester, 20);
      expect(find.text('Flooding'), findsWidgets);
      await snap(tester, key, '${e.key}_scenario_g11', dir: 'm2');
      sim.finishScenario();
      await frames(tester, 10);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
