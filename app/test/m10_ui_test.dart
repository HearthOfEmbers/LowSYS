// M10 app: onboarding tutorial, Library, semantics labels, text scaling to 130 % without overflow.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/l10n/strings.dart';
import 'package:lowsys_app/theme/themes/registry.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

Future<SimController> _boot(WidgetTester tester, GlobalKey key, {Size size = const Size(1440, 900), bool first = false, String theme = 'blueprint'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = MemorySaveStore();
  if (!first) await store.write('onboarding.done', '1');
  final sim = SimController()..saveStore = store;
  await tester.runAsync(sim.restoreSettings);
  sim.themeId.value = theme;
  await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim, theme: themeById(theme))));
  await tester.pump(const Duration(milliseconds: 500));
  await frames(tester, 10);
  return sim;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });

  testWidgets('onboarding opens on the first run, steps through and is not shown again', (tester) async {
    final key = GlobalKey();
    final sim = await _boot(tester, key, first: true, size: const Size(1024, 768));
    expect(find.byKey(const ValueKey('onboarding-card')), findsOneWidget);
    expect(find.text(S.tutorialSteps[0].title), findsOneWidget);
    await snap(tester, key, 'tutorial_1024x768', dir: 'm10', ratio: 0.8);
    for (var i = 1; i < S.tutorialSteps.length; i++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await frames(tester, 3);
      expect(find.text(S.tutorialSteps[i].title), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await frames(tester, 3);
    expect(find.byKey(const ValueKey('onboarding-card')), findsNothing);
    expect(await tester.runAsync(() => sim.saveStore!.read('onboarding.done')), '1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library lists every concept and each card links to a real scenario', (tester) async {
    final key = GlobalKey();
    await _boot(tester, key, size: const Size(1024, 768));
    for (final c in S.libraryCards) {
      expect(() => Scenarios.byId(c.scenarioId), returnsNormally, reason: c.id);
    }
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await frames(tester, 30);
    await tester.tap(find.text(S.menuLibrary));
    await frames(tester, 30);
    expect(find.text(S.libraryTitle), findsOneWidget);
    await snap(tester, key, 'library_1024x768', dir: 'm10', ratio: 0.8);
    expect(find.byKey(ValueKey('library-${S.libraryCards.first.id}')), findsOneWidget);
    await tester.tap(find.text(S.libraryCards.first.title));
    await frames(tester, 30);
    expect(find.text(S.libraryCards.first.body), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('library-open-${S.libraryCards.first.id}')));
    await frames(tester, 30);
    expect(find.text(S.start), findsOneWidget); // the briefing of the linked scenario
    expect(tester.takeException(), isNull);
  });

  testWidgets('every lever and every KPI has a semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    final key = GlobalKey();
    final sim = await _boot(tester, key);
    final labels = <String>[];
    void walk(SemanticsNode n) {
      labels.add(n.label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(Scaffold).first));
    final s = sim.snapshot.value!;
    expect(sim.levers.isNotEmpty, true);
    // every lever tile of the open tab announces its label, value and unit
    final announced = sim.levers.where((l) => labels.any((x) => x.startsWith('${l.label}: '))).length;
    expect(announced, greaterThanOrEqualTo(4), reason: 'lever labels: $labels');
    expect(labels.any((x) => x.startsWith('xD: ')), true, reason: 'KPI xD label in $labels');
    expect(s.kpis.xD.isFinite, true);
    handle.dispose();
  });

  for (final size in const [Size(360, 800), Size(800, 360), Size(1024, 768), Size(1440, 900)]) {
    testWidgets('text scale 1.3 at ${size.width.toInt()}x${size.height.toInt()}: no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final key = GlobalKey();
      await _boot(tester, key, size: size);
      await frames(tester, 20);
      expect(tester.takeException(), isNull);
    });
  }
}
