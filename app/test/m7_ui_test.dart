// M7 app: Phosphor theme tokens, Products tab (FUG panel, GC lists), component profile chart, G13 / H6 in the lists.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/painters/profile_painter.dart';
import 'package:lowsys_app/widgets/scenario_ui.dart';
import 'package:lowsys_app/theme/themes/registry.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _pow(double a, double b) => math.pow(a, b).toDouble();

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(loadFonts);

  test('every theme fills seriesDash for six series; Phosphor tokens and contrast (U2)', () {
    for (final th in kThemes) {
      expect(th.palette.seriesDash.length, 6, reason: th.id);
      expect(th.palette.series.length, 6, reason: th.id);
    }
    final ph = themeById('phosphor');
    expect(ph.id, 'phosphor');
    for (final b in [themeById('blueprint'), themeById('controlRoom'), themeById('paper')]) {
      expect(b.palette.seriesDash.every((d) => d.isEmpty), isTrue, reason: b.id);
    }
    final p = ph.palette;
    expect(p.bg, const Color(0xFF031A09));
    expect(p.selection, const Color(0xFFFFB000));
    expect(p.seriesDash[1], [6, 3]);
    expect(p.seriesDash[3], [1.5, 3]);
    expect(p.seriesDash[4], [6, 3, 1.5, 3]);
    expect(ph.effects.scanlines, isTrue);
    // contrast on bg: ink 13.5, inkMuted 4.9, accent 15.0, amber 9.9 (VALIDATION.md U2)
    expect(_contrast(p.ink, p.bg), closeTo(13.5, 1.0));
    expect(_contrast(p.inkMuted, p.bg), closeTo(4.9, 0.6));
    expect(_contrast(p.accent, p.bg), closeTo(15.0, 1.2));
    expect(_contrast(p.selection, p.bg), closeTo(9.9, 0.8));
    for (final c in p.series) {
      expect(_contrast(c, p.bg), greaterThanOrEqualTo(3.0));
    }
  });

  testWidgets('Products tab on the debutanizer: FUG panel, GC lists, component profile chart, Phosphor', (tester) async {
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
    // binary: no Products tab
    expect(sim.diagramTabOrder, isNot(contains(3)));
    expect(find.text('Products'), findsNothing);

    await tester.runAsync(() => sim.load(Presets.debut));
    sim.setTheme('phosphor');
    await frames(tester, 20);
    expect(sim.diagramTabOrder, contains(3));
    expect(sim.snapshot.value!.hydraulics, HydraulicsMode.ideal);
    expect(find.text('Products'), findsOneWidget);
    await tester.tap(find.text('Products'));
    await frames(tester, 20);
    expect(find.byKey(const ValueKey('fug-panel')), findsOneWidget);
    final r = sim.fug.value!;
    expect(r.valid, isTrue);
    expect(r.nMin, greaterThan(8));
    expect(r.nActual, closeTo(32 * 0.7 + 1, 1e-6));
    expect(find.byKey(const ValueKey('gc-AT-100')), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-AT-101')), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-AT-102')), findsOneWidget);
    expect(find.textContaining('(LK)'), findsWidgets);
    expect(find.textContaining('(HK)'), findsWidgets);
    // target mode reproduces the FUG design (VC-9.1: R_min 1.3073 with 98 % recoveries)
    await tester.tap(find.byKey(const ValueKey('fug-target-k')));
    await frames(tester, 5);
    expect(sim.fug.value!.rMin, closeTo(1.307, 0.12));
    expect(sim.fug.value!.r, closeTo(1.3 * sim.fug.value!.rMin, 1e-6));
    await tester.tap(find.byKey(const ValueKey('fug-live')));
    await frames(tester, 5);
    expect(sim.fugTargets.value, isNull);
    await snap(tester, key, 'desktop_1440x900_phosphor_products', dir: 'm7');

    // component profile chart
    sim.diagramTab.value = 1;
    await frames(tester, 10);
    expect(find.text('x(i)'), findsOneWidget);
    sim.profileKind.value = ProfileKind.components.index;
    await frames(tester, 10);
    expect(tester.takeException(), isNull);
    await snap(tester, key, 'desktop_1440x900_phosphor_components', dir: 'm7');
  });

  testWidgets('presets and scenarios G13 / H6 are reachable from the menus', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(LowsysApp(controller: sim));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 10);
    await tester.tap(find.byTooltip('Presets and options').first);
    await frames(tester, 5);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Debutanizer (6 components)'), findsOneWidget);
    expect(find.text('Depropanizer (6 components)'), findsOneWidget);
    expect(find.text('Theme: Phosphor'), findsOneWidget);
    // the menu is a long scrolling list in the test viewport: close it and drive the loads directly
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester, 5);
    await tester.runAsync(() => sim.load(Presets.debut));
    await frames(tester, 10);
    expect(sim.presetId, Presets.debut);
    expect(Scenarios.allIds, containsAll(['G13_debutanizer_fug', 'H6_offspec_overhead']));
    final ctx = tester.element(find.byType(Scaffold).first);
    showScenarioList(ctx, sim);
    await frames(tester, 10);
    await tester.scrollUntilVisible(find.textContaining('G13'), 200, scrollable: find.byType(Scrollable).last);
    await tester.scrollUntilVisible(find.textContaining('H6'), 200, scrollable: find.byType(Scrollable).last);
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G13_debutanizer_fug')));
    await frames(tester, 30);
    expect(sim.scenarioDef?.id, 'G13_debutanizer_fug');
    expect(sim.presetId, Presets.debut);
    expect(tester.takeException(), isNull);
  });
}
