// M8 app: packed-bed rendering (texture, wetting, rivulets, flooding, F21 bias rules), the Internals lever, the packed
// inspector, drill vocabulary, G15 / H7 in the lists.
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/painters/column_painter.dart';
import 'package:lowsys_app/theme/themes/registry.dart';
import 'package:lowsys_app/widgets/drill_ui.dart';
import 'package:lowsys_app/widgets/scenario_ui.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

/// The same snapshot with other bed records (what a drill or a plant view would hand the painter).
SimSnapshot _withBeds(SimSnapshot s, List<PackedBedSnapshot> beds) => SimSnapshot(
      serial: s.serial,
      time: s.time,
      tier: s.tier,
      hydraulics: s.hydraulics,
      layout: s.layout,
      components: s.components,
      stages: s.stages,
      streams: s.streams,
      condenser: s.condenser,
      reboiler: s.reboiler,
      loops: s.loops,
      alarms: s.alarms,
      kpis: s.kpis,
      steady: s.steady,
      solverHealth: s.solverHealth,
      visibleFaults: s.visibleFaults,
      levers: s.levers,
      feedQ: s.feedQ,
      murphree: s.murphree,
      view: s.view,
      instruments: s.instruments,
      valves: s.valves,
      crossChecks: s.crossChecks,
      fieldChecks: s.fieldChecks,
      scenario: s.scenario,
      energy: s.energy,
      beds: beds,
    );

PackedBedSnapshot _bed(PackedBedSnapshot b, {double? f}) => PackedBedSnapshot(
      bed: b.bed,
      firstStage: b.firstStage,
      lastStage: b.lastStage,
      packingId: b.packingId,
      height: b.height,
      diameter: b.diameter,
      dp: b.dp,
      maxFlood: b.maxFlood,
      nTheoretical: b.nTheoretical,
      eMal: f == null ? b.eMal : (f.isNaN ? double.nan : 0.6),
      maldistribution: f ?? b.maldistribution,
    );

Future<List<int>> _paint(SimSnapshot s, {Size size = const Size(420, 640)}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final painter = ColumnLivePainter(
    snapshot: ValueNotifier<SimSnapshot?>(s),
    selected: ValueNotifier<int?>(null),
    anim: ColumnAnimation()..tick(1.3, 1.0),
    theme: themeById('blueprint'),
    units: ValueNotifier(UnitSystem.si),
  );
  painter.paint(canvas, size);
  final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}

void main() {
  setUpAll(loadFonts);

  test('packed bed painter: the F21 side bias is drawn only from a finite maldistribution (never in drills or plant views)', () async {
    final sim = Simulator(
        Presets.byId('bt_packed').applyOverrides({'tier': 't1', 'hydraulics': 'full'}),
        warmStart: true);
    sim.faults.inject(FaultSpec(type: FaultType.packingMaldistribution, location: const FaultLocation.bed(1), severity: 0.5));
    sim.advance(120);
    final s = sim.snapshot();
    expect(s.beds[0].maldistribution, closeTo(0.3, 1e-9), reason: 'sandbox model view shows f');
    final healthy = [for (final b in s.beds) _bed(b, f: 0.0)];
    final hidden = [for (final b in s.beds) _bed(b, f: double.nan)];
    final shown = [for (final b in s.beds) _bed(b, f: 0.3)];
    final a = await _paint(_withBeds(s, healthy));
    final b = await _paint(_withBeds(s, hidden));
    final c = await _paint(_withBeds(s, shown));
    expect(b, a, reason: 'NaN (a drill or a plant view) paints exactly like f = 0');
    expect(c, isNot(a), reason: 'a visible f crowds the rivulets to one side');
  });

  test('flooding overlay, wetted shading and the plant-view rules reach the painter', () async {
    final sim = Simulator(
        Presets.byId('bt_packed').applyOverrides({'tier': 't1', 'hydraulics': 'full'}),
        warmStart: true);
    final s = sim.snapshot();
    final calm = await _paint(s);
    // push the lower bed past flood
    for (final lev in ['feedFlow', 'refluxFlow', 'boilup']) {
      sim.setLever(lev, sim.lever(lev) * 1.9);
    }
    sim.advance(1800);
    final f = sim.snapshot();
    expect(f.stages.packFlood.where((v) => v.isFinite && v >= 1).isNotEmpty, isTrue);
    expect(await _paint(f), isNot(calm));
    // plant view: packFlood is NaN, the holdup and wetted fraction stay
    sim.setLever('view', 1);
    final pl = sim.snapshot();
    expect(pl.stages.packFlood.every((v) => v.isNaN), isTrue);
    expect(pl.stages.packHoldup[3].isFinite, isTrue);
    final img = await _paint(pl);
    expect(img.isNotEmpty, isTrue);
  });

  test('drill vocabulary: packingDamage, flooding and bed:* labels', () {
    expect(diagnosisLabel('packingDamage'), 'Packing damage (crushed)');
    expect(diagnosisLabel('flooding'), 'Flooding (operating limit)');
    expect(diagnosisLabel('bed:1'), 'Upper bed (PDT-102)');
    expect(diagnosisLabel('bed:2'), 'Lower bed (PDT-103)');
    expect(bedLabel(3), 'Bed 3 (PDT-104)');
    final sim = Simulator(Presets.byId('bt_packed'), warmStart: false);
    final locs = expandLocations(Scenarios.byId('H7_packed_bed').diagnosis!, sim.snapshot());
    expect(locs, containsAll(['bed:1', 'bed:2', 'instrument:PDT-102', 'instrument:PDT-103']));
  });

  testWidgets('bt_packed in the app: column, Internals lever, inspector, fault cards, menus', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d, forceReport: true);
    final key = GlobalKey();
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 10);
    await tester.runAsync(() => sim.load(Presets.btPacked));
    await frames(tester, 30);
    final s = sim.snapshot.value!;
    expect(s.beds.length, 2);
    expect(sim.structure.value.beds, '1-9:struct250,10-18:struct250');
    expect(s.layout.kinds.where((k) => k == StageKind.packed).length, 18);
    expect(sim.levers.any((l) => l.id == 'nTrays'), isFalse);
    expect(sim.levers.any((l) => l.id == 'murphree'), isFalse);
    expect(sim.levers.any((l) => l.id == 'internals'), isTrue);
    expect(find.byType(CustomPaint), findsWidgets);

    await snap(tester, key, 'desktop_1000x700_packed_bt_packed', dir: 'm8', ratio: 0.8);

    // the preset and scenario menus
    await tester.tap(find.byTooltip('Presets and options').first);
    await frames(tester, 5);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Benzene–toluene, packed (2 × 4.5 m)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester, 5);
    expect(Scenarios.allIds, containsAll(['G15_packing_retrofit', 'H7_packed_bed']));
    final ctx = tester.element(find.byType(Scaffold).first);
    showScenarioList(ctx, sim);
    await frames(tester, 10);
    await tester.scrollUntilVisible(find.textContaining('G15'), 200, scrollable: find.byType(Scrollable).last);
    await tester.scrollUntilVisible(find.textContaining('H7'), 200, scrollable: find.byType(Scrollable).last);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester, 5);

    // inspector on a packed segment
    sim.selectStage(12);
    await frames(tester, 10);
    expect(find.textContaining('Segment 12'), findsWidgets);
    expect(find.textContaining('HETP'), findsWidgets);
    expect(find.textContaining('wetted'), findsWidgets);
    sim.selectStage(null);

    // the packed-bed faults are injectable in the sandbox
    await tester.runAsync(() => sim.injectFault(FaultSpec(type: FaultType.packingCrush, location: const FaultLocation.bed(2), severity: 0.3, onset: s.time)));
    await frames(tester, 10);
    expect(sim.snapshot.value!.visibleFaults.single.type, FaultType.packingCrush);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crushed lower bed pushed past flood shows the flooding overlay and the alarm (screenshot)', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 10);
    await tester.runAsync(() => sim.load(Presets.btPacked));
    await frames(tester, 20);
    for (final lev in ['feedFlow', 'refluxFlow', 'boilup']) {
      final v = sim.snapshot.value!.levers[lev]!;
      await tester.runAsync(() => sim.setLever(lev, v * 1.5));
    }
    // crushed lower packing (F23 s 0.5) as in the H7 hardest case
    await tester.runAsync(() => sim.injectFault(FaultSpec(
        type: FaultType.packingCrush, location: const FaultLocation.bed(2), severity: 0.5, onset: sim.snapshot.value!.time)));
    sim.setSpeed(300);
    await frames(tester, 300);
    sim.setSpeed(0);
    await frames(tester, 5);
    final s = sim.snapshot.value!;
    expect(s.beds[1].maxFlood, greaterThan(1.0));
    expect(s.alarms.any((a) => a.id == 'model.flood'), isTrue);
    expect(tester.takeException(), isNull);
    await snap(tester, key, 'desktop_1000x700_packed_flooding', dir: 'm8', ratio: 0.8);
  });

  testWidgets('H7 drill: plantCalc rendering, the Diagnose dialog offers the beds, the hidden fault is not painted', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(LowsysApp(controller: sim));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 10);
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('H7_packed_bed'), seed: 11));
    sim.setSpeed(1);
    await frames(tester, 20);
    final s = sim.snapshot.value!;
    expect(s.view, SimView.plantCalc);
    expect(s.beds.length, 2);
    expect(s.beds.every((b) => b.eMal.isNaN && b.maldistribution.isNaN), isTrue, reason: 'never visible in a drill');
    expect(s.visibleFaults, isEmpty);
    expect(s.instruments.map((i) => i.tag), containsAll(['PDT-102', 'PDT-103']));
    expect(find.byKey(const ValueKey('drill-timer')), findsOneWidget);
    final ctx = tester.element(find.byType(Scaffold).first);
    showDiagnoseDialog(ctx, sim);
    await frames(tester, 10);
    expect(find.text('Packing damage (crushed)'), findsWidgets);
    expect(find.text('Flooding (operating limit)'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('G15 starts on the trays; the Internals lever switches and the column is rebuilt', (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final sim = SimController()..saveStore = MemorySaveStore();
    await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
    await tester.pump(const Duration(milliseconds: 500));
    await frames(tester, 10);
    await tester.runAsync(() => sim.startScenario(Scenarios.byId('G15_packing_retrofit')));
    await frames(tester, 20);
    expect(sim.scenarioDef?.id, 'G15_packing_retrofit');
    expect(sim.snapshot.value!.beds, isEmpty);
    expect(sim.structure.value.trays, 20);
    await tester.runAsync(() => sim.setLever('internals', 1));
    await frames(tester, 20);
    expect(sim.snapshot.value!.beds.length, 2);
    expect(sim.structure.value.trays, 18);
    expect(sim.structure.value.beds, '1-9:struct250,10-18:struct250');
    expect(tester.takeException(), isNull);
  });
}
