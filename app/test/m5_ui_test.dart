import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/widgets/figure_chrome.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

void main() {
  setUpAll(loadFonts);

  test('figure caption follows the Paper pattern', () {
    final sim = Simulator(Presets.byId('ew').copyWith(tier: ThermoTier.t3),
        warmStart: false);
    sim.advance(10);
    final c = figureCaption(2, 'T-x-y', sim.config, sim.snapshot(), UnitSystem.si);
    expect(c, startsWith('Figure 2 — T-x-y, ethanol–water, Tier 3 (NRTL), P = 1.0'));
  });

  final sizes = <String, Size>{
    'portrait_360x800': const Size(360, 800),
    'desktop_1440x900': const Size(1440, 900),
  };
  for (final e in sizes.entries) {
    testWidgets('M5 UI at ${e.key}: T-x-y tab, x-y view, tier badge, ac banner, Paper theme', (tester) async {
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

      // B-T: T1 -> T2 only (no Tier 3)
      expect(sim.config.availableTiers, {ThermoTier.t1, ThermoTier.t2});
      await tester.tap(find.byKey(const ValueKey('tier-badge')));
      await frames(tester, 10);
      expect(sim.snapshot.value!.tier, ThermoTier.t2);
      await tester.tap(find.byKey(const ValueKey('tier-badge')));
      await frames(tester, 10);
      expect(sim.snapshot.value!.tier, ThermoTier.t1);

      // ethanol-water: three tiers, T-x-y tab
      await tester.runAsync(() => sim.load('ew', config: Presets.byId('ew')));
      await frames(tester, 10);
      expect(sim.snapshot.value!.tier, ThermoTier.t3);
      expect(sim.config.availableTiers.length, 3);
      sim.setSpeed(30);
      sim.diagramTab.value = 2;
      await frames(tester, 30);
      expect(sim.txy.value, isNotNull);
      expect(sim.txy.value!.top.azeotropes.length, 1);
      expect(tester.takeException(), isNull);
      sim.selectStage(30);
      await frames(tester, 5);
      await snap(tester, key, '${e.key}_txy_ew_t3', dir: 'm5');
      sim.txySub.value = 1;
      await frames(tester, 5);
      await snap(tester, key, '${e.key}_xy_ew_t3', dir: 'm5');
      sim.txySub.value = 0;
      expect(tester.takeException(), isNull);

      // Tier 1 on ethanol-water: ideal curves, display T*
      await sim.setTier(ThermoTier.t1);
      await frames(tester, 20);
      expect(sim.txy.value!.top.ideal, isTrue);
      await snap(tester, key, '${e.key}_txy_ew_t1_ideal', dir: 'm5');

      // acetone-chloroform in Tier 1: the banner
      await tester.runAsync(() => sim.load('ac', config: Presets.byId('ac').copyWith(tier: ThermoTier.t1)));
      await frames(tester, 10);
      expect(find.byKey(const ValueKey('tier1-cannot')), findsOneWidget);
      await snap(tester, key, '${e.key}_ac_tier1_banner', dir: 'm5');
      await sim.setTier(ThermoTier.t3);
      await frames(tester, 20);
      expect(find.byKey(const ValueKey('tier1-cannot')), findsNothing);
      sim.diagramTab.value = 2;
      await frames(tester, 20);
      expect(sim.txy.value!.top.azeotropes.single.maximumBoiling, isTrue);
      await snap(tester, key, '${e.key}_txy_ac_t3', dir: 'm5');

      // Paper theme: captions, margin note, export button
      await sim.setTheme('paper');
      await frames(tester, 10);
      sim.selectStage(10);
      sim.diagramTab.value = 0;
      await frames(tester, 10);
      expect(find.byKey(const ValueKey('export-figure')), findsOneWidget);
      expect(find.textContaining('Figure 1 —'), findsOneWidget);
      await snap(tester, key, '${e.key}_paper_mccabe', dir: 'm5');
      sim.diagramTab.value = 2;
      await frames(tester, 20);
      expect(find.textContaining('Figure 2 —'), findsOneWidget);
      await snap(tester, key, '${e.key}_paper_txy', dir: 'm5');
      expect(tester.takeException(), isNull);

      // scenarios G9 and G10 start
      await sim.setTheme('blueprint');
      await tester.runAsync(() => sim.startScenario(Scenarios.byId('G9_azeotrope_wall')));
      await frames(tester, 20);
      expect(sim.snapshot.value!.tier, ThermoTier.t3);
      expect(sim.presetId, 'ew');
      await tester.runAsync(() => sim.startScenario(Scenarios.byId('G10_other_azeotrope')));
      await frames(tester, 20);
      expect(sim.presetId, 'ac');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
