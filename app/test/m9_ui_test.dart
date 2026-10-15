// M9 app: the crude flowsheet, the Products tab, the Brass theme, G16 / H8 in the lists, the lever, KPI and fault panels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/painters/crude_geometry.dart';
import 'package:lowsys_app/theme/themes/brass.dart';
import 'package:lowsys_app/theme/themes/registry.dart';
import 'package:lowsys_app/widgets/drill_ui.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

Future<SimController> _boot(WidgetTester tester, GlobalKey key, {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d, forceReport: true);
  final sim = SimController()..saveStore = MemorySaveStore();
  await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
  await tester.pump(const Duration(milliseconds: 500));
  await frames(tester, 10);
  return sim;
}

Future<void> _tapAt(WidgetTester tester, Offset local) async {
  final tl = tester.getTopLeft(find.byKey(const ValueKey('crude-flowsheet')));
  await tester.tapAt(tl + local);
  await frames(tester, 6);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });

  testWidgets('crude unit: flowsheet, Products tab, levers, KPI strip, Brass', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    await tester.runAsync(() => sim.load(Presets.crude));
    await tester.runAsync(() => sim.setTheme('brass'));
    await frames(tester, 30);
    expect(tester.takeException(), isNull);
    expect(sim.themeId.value, 'brass');
    expect(kThemes.map((t) => t.id), contains('brass'));
    expect(find.byKey(const ValueKey('crude-flowsheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('crude-products')), findsOneWidget);
    expect(find.byKey(const ValueKey('tbp-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('d86-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('gap-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('gap-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('yield-4')), findsOneWidget);
    final s = sim.snapshot.value!;
    expect(s.strippers.length, 3);
    expect(s.crudeProducts!.tbp.length, 6);
    expect(s.crudeProducts!.d86.length, 4);
    expect(s.crudeProducts!.gaps.length, 3);
    expect(sim.diagramTabOrder, [3, 1]);
    // levers: the crude groups, no B-T levers
    expect(find.text('Crude rate'), findsNothing); // label is rendered with its unit by the tile
    expect(find.textContaining('Furnace outlet'), findsOneWidget);
    expect(find.textContaining('Pumparound duty'), findsNothing); // below the fold of the lever list
    // KPI strip
    expect(find.text('Kero D86 95'), findsOneWidget);
    expect(find.text('D–K gap'), findsOneWidget);
    // Brass: the theme palette
    expect(brassTheme.palette.bg, const Color(0xFF1B120B));
    expect(brassTheme.palette.accent, const Color(0xFFC89B3C));
    expect(brassTheme.palette.liquidLight, const Color(0xFFE8B04B));
    expect(tester.takeException(), isNull);
    await snap(tester, key, 'desktop_1440x900_crude_brass', dir: 'm9', ratio: 0.5);
  });

  testWidgets('taps on stages, strippers, the PA and products open the math overlay; the other tabs build', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    await tester.runAsync(() => sim.load(Presets.crude));
    await frames(tester, 20);
    await snap(tester, key, 'desktop_1440x900_crude_blueprint', dir: 'm9', ratio: 0.4);
    final size = tester.getSize(find.byKey(const ValueKey('crude-flowsheet')));
    final g = CrudeGeometry(size);
    Future<void> expectTap(Offset local, bool Function(ExplainTarget) ok) async {
      sim.closeMath();
      await _tapAt(tester, local);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      final t = sim.mathTarget.value;
      expect(t != null && ok(t), isTrue, reason: 'tap $local gave $t');
      expect(sim.mathResult.value, isNotNull);
    }

    await expectTap(Offset((g.shellL + g.shellR) / 2, g.stageY(12)), (t) => t is ExplainStage && t.stage == 12);
    expect(sim.selectedStage.value, 12);
    await expectTap(g.ssTop(1).center, (t) => t is ExplainStripper && t.stripper == 1 && !t.bottom);
    await expectTap(g.ssBoot(2).center, (t) => t is ExplainStripper && t.stripper == 2 && t.bottom);
    await expectTap(g.cooler + const Offset(0, 0), (t) => t is ExplainPumparound);
    await expectTap(Offset(g.ssR + 12, g.productY(2)), (t) => t is ExplainProduct && t.product == 2);
    await expectTap(g.drum.center, (t) => t is ExplainStage && t.stage == 0);
    final r = sim.mathResult.value!;
    expect(r.groups, isNotEmpty);
    sim.closeMath();
    // every control tab and the Profiles tab build without an exception
    for (final i in [1, 2, 3, 4, 5, 0]) {
      sim.controlTab.value = i;
      await frames(tester, 8);
      expect(tester.takeException(), isNull, reason: 'control tab $i');
    }
    sim.diagramTab.value = 1;
    await frames(tester, 10);
    expect(tester.takeException(), isNull);
    sim.diagramTab.value = 3;
    await frames(tester, 5);
  });

  testWidgets('crude faults tab, G16 and H8 in the lists, the drill vocabulary, the lab note in the plant view', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    await tester.runAsync(() => sim.load(Presets.crude));
    await frames(tester, 10);
    sim.controlTab.value = 4;
    await frames(tester, 6);
    expect(find.byKey(const ValueKey('fault-f24')), findsOneWidget);
    expect(find.byKey(const ValueKey('fault-f25')), findsOneWidget);
    expect(find.byKey(const ValueKey('fault-f26')), findsOneWidget);
    expect(Scenarios.allIds, containsAll(['G16_crude_gaps', 'H8_crude_drift']));
    expect(diagnosisLabel('steamLoss'), 'Stripping steam loss');
    expect(diagnosisLabel('steam:bottom'), 'Bottom stripping steam (FC-321)');
    expect(diagnosisLabel('steam:ss2'), 'Diesel stripper steam (FC-323)');
    expect(diagnosisLabel('furnace'), 'Furnace / COT');
    // H8: plantCalc, the Products tab shows the lab result with its sample time
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('H8_crude_drift'), seed: 4));
    sim.setSpeed(1);
    await frames(tester, 20);
    final s = sim.snapshot.value!;
    expect(s.view, SimView.plantCalc);
    expect(s.crudeProducts!.labSampleTime.isNaN, isFalse);
    expect(find.byKey(const ValueKey('lab-note')), findsOneWidget);
    final dg = sim.scenarioDef!.diagnosis!;
    final locs = expandLocations(dg, s);
    expect(locs, containsAll(['steam:bottom', 'steam:ss1', 'steam:ss2', 'steam:ss3', 'pumparound', 'furnace']));
    expect(tester.takeException(), isNull);
    // G16
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G16_crude_gaps'), seed: 4));
    await frames(tester, 20);
    final g16 = sim.snapshot.value!;
    expect(g16.view, SimView.model);
    expect(g16.scenario!.objectives.length, 3);
    expect(find.byKey(const ValueKey('lab-note')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SPD theme: setTheme(spd) renders the sim screen', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    await tester.runAsync(() => sim.setTheme('spd'));
    await frames(tester, 20);
    expect(tester.takeException(), isNull);
    expect(sim.themeId.value, 'spd');
    expect(themeById('spd').name, 'SPD');
  });
  for (final sz in [const Size(360, 800), const Size(800, 360), const Size(900, 700)]) {
    testWidgets('crude unit lays out without overflow at ${sz.width.toInt()}x${sz.height.toInt()}', (tester) async {
      final key = GlobalKey();
      final sim = await _boot(tester, key, size: sz);
      await tester.runAsync(() => sim.load(Presets.crude));
      await tester.runAsync(() => sim.setTheme('brass'));
      await frames(tester, 20);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('crude-flowsheet')), findsOneWidget);
    });
  }
}
