import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/theme/themes/control_room.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(loadFonts);

  test('Control Room contrast (VALIDATION U2): info and selection on bg above 7:1, series above 3:1', () {
    final p = controlRoomTheme.palette;
    expect(_contrast(p.info, p.bg), greaterThan(7));
    expect(_contrast(p.selection, p.bg), greaterThan(7));
    for (final c in p.series) {
      expect(_contrast(c, p.bgAlt), greaterThan(3));
    }
  });

  final sizes = <String, Size>{
    'portrait_360x800': const Size(360, 800),
    'desktop_1440x900': const Size(1440, 900),
  };
  for (final e in sizes.entries) {
    testWidgets('M4 UI at ${e.key}: tier switch, energy panel, balance C6, faults, Control Room, G8', (tester) async {
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
      expect(sim.snapshot.value!.tier, ThermoTier.t1);

      // Energy tab in Tier 1 explains itself
      sim.controlTab.value = 5;
      await frames(tester, 3);
      expect(find.byKey(const ValueKey('energy-t1')), findsOneWidget);

      // switch to Tier 2 with the badge
      await tester.tap(find.byKey(const ValueKey('tier-badge')));
      await frames(tester, 10);
      expect(sim.snapshot.value!.tier, ThermoTier.t2);
      expect(find.text('T2'), findsWidgets);
      sim.setSpeed(100);
      await frames(tester, 120);
      expect(sim.snapshot.value!.condenser!.qC, greaterThan(0));
      await frames(tester, 3);
      expect(find.byKey(const ValueKey('energy-condenser')), findsOneWidget);
      if (e.value.width > 1000) {
        expect(find.byKey(const ValueKey('energy-reboiler')), findsOneWidget);
      }
      await snap(tester, key, '${e.key}_energy', dir: 'm4');
      expect(tester.takeException(), isNull);

      // levers, loops (PC-101, TC-101), profiles
      sim.controlTab.value = 0;
      await frames(tester, 3);
      expect(find.byKey(const ValueKey('feed-q')), findsOneWidget);
      sim.controlTab.value = 1;
      sim.selectedLoop.value = 'PC-101';
      await frames(tester, 5);
      expect(find.text('PC-101'), findsWidgets);
      sim.selectedLoop.value = 'TC-101';
      await frames(tester, 5);
      expect(find.text('TC-101'), findsWidgets);
      sim.diagramTab.value = 1;
      sim.profileKind.value = 6; // V
      await frames(tester, 3);
      await snap(tester, key, '${e.key}_profile_v', dir: 'm4');
      sim.profileKind.value = 5; // T
      await frames(tester, 3);
      sim.diagramTab.value = 0;
      expect(tester.takeException(), isNull);

      // faults tab: process faults and a flag on the column
      sim.controlTab.value = 4;
      await frames(tester, 3);
      expect(find.byKey(const ValueKey('process-faults')), findsOneWidget);
      await sim.injectFault(FaultSpec(
          type: FaultType.coolingLoss,
          location: FaultLocation.equipment('condenser'),
          severity: 0.7,
          onset: sim.snapshot.value!.time,
          params: const {'mode': 'flow'}));
      await frames(tester, 60);
      expect(sim.snapshot.value!.visibleFaults, isNotEmpty);
      await snap(tester, key, '${e.key}_f09', dir: 'm4');

      // balance tab with the C6 card
      sim.controlTab.value = 2;
      await frames(tester, 5);
      expect(find.byKey(const ValueKey('c6-card')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Control Room theme
      await sim.setTheme('controlRoom');
      await frames(tester, 10);
      sim.controlTab.value = 5;
      await frames(tester, 5);
      await snap(tester, key, '${e.key}_control_room', dir: 'm4');
      expect(tester.takeException(), isNull);

      // G8 scenario loads in Tier 2 with the 10 bar(g) header
      await sim.startScenario(Scenarios.byId('G8_pressure_volatility'));
      await frames(tester, 20);
      expect(sim.snapshot.value!.tier, ThermoTier.t2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
