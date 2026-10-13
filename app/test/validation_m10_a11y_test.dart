// M10 acceptance (validator, read-only check of the app): SCOPE.md M10 accessibility, "semantics labels for every lever
// and KPI" and "text scaling to 130 %" (VALIDATION.md §U1 "no clipping at 1.3"), on cases m10_ui_test.dart does not
// cover: every lever tile and KPI chip of the whole scrolled lever list (B-T and crude), the segmented levers, and 130 %
// on the crude unit in Brass and on Phosphor (VT323).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/theme/themes/registry.dart';
import 'package:lowsys_app/widgets/kpi_strip.dart';
import 'package:lowsys_app/widgets/lever_panel.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

Future<SimController> _boot(WidgetTester tester, {Size size = const Size(1440, 900), String theme = 'blueprint', bool crude = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = MemorySaveStore();
  await store.write('onboarding.done', '1');
  final sim = SimController()..saveStore = store;
  await tester.runAsync(sim.restoreSettings);
  sim.themeId.value = theme;
  await tester.pumpWidget(LowsysApp(controller: sim, theme: themeById(theme)));
  await tester.pump(const Duration(milliseconds: 500));
  await frames(tester, 10);
  if (crude) {
    await tester.runAsync(() => sim.load(Presets.crude));
    await tester.runAsync(() => sim.setTheme(theme));
    await frames(tester, 30);
  }
  return sim;
}

/// Scrolls the lever list from top to bottom; returns (lever label, semantics label) of every LeverTile built on the way.
Future<Map<String, String>> _leverLabels(WidgetTester tester) async {
  final out = <String, String>{};
  final scroll = find.descendant(of: find.byType(LeverPanel), matching: find.byType(Scrollable)).first;
  for (var pass = 0; pass < 40; pass++) {
    final before = out.length;
    for (final e in find.byType(LeverTile).evaluate()) {
      final w = e.widget as LeverTile;
      out[w.spec.label] = tester.getSemantics(find.byWidget(w)).label;
    }
    await tester.drag(scroll, const Offset(0, -250));
    await frames(tester, 3);
    if (out.length == before && pass > 3) break;
  }
  return out;
}

/// (number of KPI chips, semantics labels of the labelled containers in the strip); each chip is an InkWell.
(int, List<String>) _kpiLabels(WidgetTester tester) {
  final chips = find.descendant(of: find.byType(KpiStrip), matching: find.byType(InkWell)).evaluate().length;
  final sem = find.descendant(
      of: find.byType(KpiStrip), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label != null));
  return (chips, [for (final e in sem.evaluate()) tester.getSemantics(find.byWidget(e.widget)).label]);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });

  for (final crude in [false, true]) {
    testWidgets('semantics (${crude ? 'crude, Brass' : 'B-T, Blueprint'}): every lever tile of the scrolled list and every '
        'KPI chip announces "label: value unit"', (tester) async {
      final handle = tester.ensureSemantics();
      final sim = await _boot(tester, theme: crude ? 'brass' : 'blueprint', crude: crude);
      final levers = await _leverLabels(tester);
      final (chips, kpis) = _kpiLabels(tester);
      // ignore: avoid_print
      print('a11y ${crude ? 'crude' : 'B-T'}: ${levers.length} lever tiles, $chips KPI chips with ${kpis.length} labels; e.g. '
          '"${levers.values.first}", "${kpis.isEmpty ? '-' : kpis.first}"');
      expect(kpis.length, chips, reason: 'one semantics label per KPI chip');
      expect(levers.length, greaterThanOrEqualTo(crude ? 12 : 8));
      levers.forEach((label, sem) {
        expect(sem, startsWith(label), reason: 'lever tile "$label" semantics "$sem"');
        expect(sem, contains(': '), reason: 'lever tile "$label" has no value in "$sem"');
      });
      expect(kpis.length, greaterThanOrEqualTo(crude ? 12 : 5));
      for (final k in kpis) {
        expect(RegExp(r'^\S.*: \S').hasMatch(k), isTrue, reason: 'KPI chip semantics "$k"');
      }
      expect(sim.loaded, isTrue);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }

  testWidgets('semantics: segmented levers (Hydraulics Ideal / Full) carry the lever name and a selected state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _boot(tester);
    final scroll = find.descendant(of: find.byType(LeverPanel), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Full'), 250, scrollable: scroll);
    await frames(tester, 3);
    final rows = <String>[];
    var named = 0, selectable = 0;
    for (final opt in ['Ideal', 'Full']) {
      final node = tester.getSemantics(find.text(opt).first);
      final d = node.getSemanticsData();
      rows.add('"$opt": label "${d.label}", hasSelectedState ${d.hasFlag(SemanticsFlag.hasSelectedState)}, '
          'button ${d.hasFlag(SemanticsFlag.isButton)}');
      if (d.label.contains('Hydraulics')) named++;
      if (d.hasFlag(SemanticsFlag.hasSelectedState)) selectable++;
    }
    // ignore: avoid_print
    print('a11y segments: ${rows.join('; ')}');
    handle.dispose();
    // lever_panel.dart _Segments: an InkWell per option with the option text only; a screen reader hears "Ideal" /
    // "Full" without the lever name or which option is on (the same for condenser, reboiler, TC-101, internals, tray
    // type, antifoam, noise, view and bad-signal levers)
    expect(named + selectable, greaterThan(0), reason: rows.join('; '));
  });

  for (final (size, theme, crude) in const [
    (Size(360, 800), 'brass', true),
    (Size(1024, 768), 'brass', true),
    (Size(800, 360), 'phosphor', false),
  ]) {
    testWidgets('text scale 1.3, ${crude ? 'crude' : 'B-T'} in $theme at ${size.width.toInt()}x${size.height.toInt()}: '
        'no overflow, the KPI text is scaled', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // keep the full error details (the overflowing widget and its file) for the report
      final errs = <FlutterErrorDetails>[];
      final onError = FlutterError.onError;
      FlutterError.onError = errs.add;
      try {
        await _boot(tester, size: size, theme: theme, crude: crude);
        await frames(tester, 20);
      } finally {
        FlutterError.onError = onError;
      }
      for (final d in errs) {
        final where = d.toString().split('\n').where((l) => l.contains('lib/') || l.contains('overflowed')).take(4);
        // ignore: avoid_print
        print('a11y 1.3 ${size.width.toInt()}x${size.height.toInt()} $theme: ${where.join(' | ')}');
      }
      expect(errs, isEmpty, reason: 'layout errors at text scale 1.3');
      final kpiText = find.descendant(of: find.byType(KpiStrip), matching: find.byType(RichText));
      // ignore: avoid_print
      print('a11y 1.3 ${size.width.toInt()}x${size.height.toInt()} $theme: KPI strip texts built ${kpiText.evaluate().length}');
      final para = tester.renderObject<RenderParagraph>(kpiText.evaluate().isEmpty ? find.byType(RichText).first : kpiText.first);
      expect(para.textScaler.scale(10), closeTo(13, 1e-9), reason: 'text is drawn at 130 %');
      // the levers stay reachable: the lever list scrolls to its end without an exception
      final scroll = find.descendant(of: find.byType(LeverPanel), matching: find.byType(Scrollable));
      if (scroll.evaluate().isNotEmpty) {
        await tester.drag(scroll.first, const Offset(0, -3000));
        await frames(tester, 5);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
