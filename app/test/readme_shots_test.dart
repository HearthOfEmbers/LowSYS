// README screenshots. Skipped unless LOWSYS_SHOTS=1; writes to docs/screenshots/readme/.
// Run: LOWSYS_SHOTS=1 flutter test test/readme_shots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/l10n/strings.dart';
import 'package:lowsys_app/theme/themes/registry.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);
const _themes = ['blueprint', 'controlRoom', 'phosphor', 'paper', 'brass', 'spd'];

Future<SimController> _boot(WidgetTester tester, GlobalKey key, {Size size = _desktop, String theme = 'blueprint'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = MemorySaveStore();
  await store.write('onboarding.done', '1');
  final sim = SimController()..saveStore = store;
  await tester.runAsync(sim.restoreSettings);
  sim.themeId.value = theme;
  await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim, theme: themeById(theme))));
  await tester.pump(const Duration(milliseconds: 500));
  await frames(tester, 10);
  return sim;
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name, {double ratio = 1.5}) =>
    snap(tester, key, name, dir: 'readme', ratio: ratio);

/// Scales feed, reflux and boilup together, as G11 asks.
Future<void> _throughput(SimController sim, double factor) async {
  for (final id in ['feedFlow', 'refluxFlow', 'boilup']) {
    final v = sim.leverValues.value[id];
    if (v != null) await sim.setLever(id, v * factor);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });

  for (final theme in _themes) {
    testWidgets('theme $theme', (tester) async {
      final key = GlobalKey();
      final sim = await _boot(tester, key, theme: theme);
      sim.setSpeed(30);
      await frames(tester, 120);
      sim.selectStage(10);
      await frames(tester, 5);
      await _shot(tester, key, 'theme_$theme');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, skip: !shots);
  }

  testWidgets('hero: Control Room, Tier 2, energy panel', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key, theme: 'controlRoom');
    await tester.runAsync(() => sim.setTier(ThermoTier.t2));
    sim.setSpeed(100);
    await frames(tester, 150);
    await _throughput(sim, 1.15);
    await frames(tester, 60);
    sim.controlTab.value = 5;
    await frames(tester, 5);
    await _shot(tester, key, 'hero_control_room');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('G11 flooding', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G11_flooding')));
    await frames(tester, 20);
    await _throughput(sim, 1.75);
    sim.setSpeed(100);
    await frames(tester, 400);
    await _shot(tester, key, 'g11_flooding');
    sim.diagramTab.value = 1;
    sim.profileKind.value = 1;
    await frames(tester, 5);
    await _shot(tester, key, 'g11_flooding_profiles');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('G9 azeotrope wall, T-x-y', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key, theme: 'paper');
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G9_azeotrope_wall')));
    sim.setSpeed(30);
    await frames(tester, 60);
    await tester.tap(find.byIcon(Icons.expand_less).first);
    await frames(tester, 20);
    await _shot(tester, key, 'g9_azeotrope_mccabe');
    sim.diagramTab.value = 2;
    await frames(tester, 10);
    await _shot(tester, key, 'g9_azeotrope_txy');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('math overlay on a tray', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    sim.setSpeed(30);
    await frames(tester, 60);
    sim.selectStage(7);
    await tester.runAsync(() => sim.openMath(const ExplainStage(7)));
    await frames(tester, 10);
    await _shot(tester, key, 'math_overlay');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('H9 drill in plant view', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key, theme: 'controlRoom');
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('H9_dont_trust_the_gauge'), seed: 7));
    sim.setSpeed(100);
    await frames(tester, 300);
    sim.controlTab.value = 3;
    await frames(tester, 10);
    await _shot(tester, key, 'h9_drill');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('crude unit in Brass', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key, theme: 'brass');
    await tester.runAsync(() => sim.load(Presets.crude));
    sim.setSpeed(30);
    await frames(tester, 60);
    await _shot(tester, key, 'crude_brass');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('Library', (tester) async {
    final key = GlobalKey();
    await _boot(tester, key, theme: 'spd');
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await frames(tester, 30);
    await tester.tap(find.text(S.menuLibrary));
    await frames(tester, 30);
    await _shot(tester, key, 'library');
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);

  testWidgets('phone, portrait', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key, size: _phone, theme: 'phosphor');
    sim.setSpeed(30);
    await frames(tester, 120);
    await _shot(tester, key, 'phone_phosphor', ratio: 2.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !shots);
}
