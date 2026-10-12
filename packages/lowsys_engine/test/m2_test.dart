import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Simulator fullSim() =>
    Simulator(Presets.byId('bt').copyWith(hydraulics: HydraulicsMode.full));

void main() {
  test('scenario JSON validates', () {
    for (final d in ScenarioLibrary.all) {
      expect(d.validate(), isEmpty, reason: d.id);
    }
  });

  test('G11 can be completed by following its hints', () {
    final def = ScenarioLibrary.byId('G11_flooding');
    final sim = Simulator(def.buildConfig());
    final run = ScenarioRunner.forSimulator(def, sim);
    run.update();
    // uniform scaling x1.7 of feed, reflux and boilup floods the column (TS 0.9 m: onset near x1.57)
    sim.setLever('feedFlow', kmolh(170));
    sim.setLever('refluxFlow', kmolh(170));
    sim.setLever('boilup', kmolh(255));
    for (var i = 0; i < 90; i++) {
      sim.advance(10);
      run.update();
    }
    expect(run.objectives[0].achieved, isTrue, reason: 'flooded');
    expect(run.objectives[1].achieved, isFalse);
    sim.setLever('feedFlow', kmolh(135));
    sim.setLever('refluxFlow', kmolh(135));
    sim.setLever('boilup', kmolh(202.5));
    for (var i = 0; i < 900 && !run.objectives[1].achieved; i++) {
      sim.advance(10);
      run.update();
    }
    expect(run.objectives[1].achieved, isTrue);
    expect(run.submitAnswer('o3', 160).correct, isTrue);
    final card = run.finish();
    expect(card.completed, isTrue);
    expect(card.total, greaterThan(60));
  });

  test('G12 can be completed: sieve weeps at 35 %, valve trays do not', () {
    final def = ScenarioLibrary.byId('G12_turndown');
    final sim = Simulator(def.buildConfig());
    final run = ScenarioRunner.forSimulator(def, sim);
    run.update();
    sim.setLever('feedFlow', kmolh(35));
    sim.setLever('refluxFlow', kmolh(35));
    sim.setLever('boilup', kmolh(52.5));
    for (var i = 0; i < 360; i++) {
      sim.advance(10);
      run.update();
    }
    expect(run.objectives[0].achieved, isTrue, reason: 'weeping seen');
    sim.setLever('trayType.0', 1);
    for (var i = 0; i < 360 && !run.objectives[1].achieved; i++) {
      sim.advance(10);
      run.update();
    }
    expect(run.objectives[1].achieved, isTrue);
  });

  test('VC-21 explain values equal the snapshot values of the same state', () {
    final sim = fullSim();
    sim.setLever('boilup', kmolh(170));
    sim.advance(300);
    final snap = sim.snapshot();
    final st = snap.stages;
    final sw = Stopwatch()..start();
    for (var j = 1; j <= 20; j++) {
      final r = sim.explain(ExplainStage(j));
      expect(r.time, snap.time);
      final byId = {
        for (final g in r.groups)
          for (final l in g.lines) l.id: l
      };
      for (final g in r.groups) {
        for (final l in g.lines) {
          expect(l.texSymbolic, isNotEmpty);
          expect(l.texSubstituted, isNotEmpty);
          expect(l.value.isFinite, isTrue, reason: l.id);
        }
      }
      double rel(double a, double b) =>
          (a - b).abs() / (b.abs() > 1e-300 ? b.abs() : 1);
      expect(rel(byId['eq.equilibrium.T1']!.value, st.yStar[j * 2]),
          lessThan(1e-12));
      expect(rel(byId['eq.murphree']!.value, st.y[j * 2]), lessThan(1e-12));
      expect(rel(byId['eq.vapourFlow.cmo']!.value, st.vaporUp[j]),
          lessThan(1e-12));
      expect(rel(byId['eq.bennett']!.value, st.hcl[j]), lessThan(1e-12));
      expect(rel(byId['eq.dryDP']!.value, st.dpDry[j]), lessThan(1e-12));
      expect(rel(byId['eq.trayDP']!.value, st.dp[j]), lessThan(1e-12));
      expect(rel(byId['eq.jetFlood']!.value, st.jetFlood[j]), lessThan(1e-12));
      expect(
          rel(byId['eq.entrainment']!.value, st.entrain[j]), lessThan(1e-12));
      expect(rel(byId['eq.downcomer']!.value, st.dcFlood[j]), lessThan(1e-12));
      expect(rel(byId['eq.weeping']!.value, st.weepFrac[j]), lessThan(1e-12));
    }
    final per = sw.elapsedMicroseconds / 20 / 1000;
    expect(per, lessThan(100), reason: 'explain + snapshot per tray in ms');
    for (final t in [
      const ExplainStage(0),
      const ExplainStage(21),
      const ExplainStream(StreamId.distillate),
      const ExplainStream(StreamId.bottoms),
      const ExplainStream(StreamId.feed),
      const ExplainCondenser(),
      const ExplainReboiler(),
      const ExplainFeed(),
      const ExplainLoop('LC-101'),
      const ExplainMcCabe(McCabeElement.rmin),
    ]) {
      final r = sim.explain(t);
      expect(r.groups, isNotEmpty);
      expect(r.title, isNotEmpty);
    }
  });

  test('explain in ideal hydraulics also works', () {
    final sim = btSim();
    final r = sim.explain(const ExplainStage(5));
    expect(r.groups.length, greaterThanOrEqualTo(3));
  });

  test('texNum formats 4 significant figures and scientific outside 1e-3..1e5',
      () {
    expect(texNum(0.0230), '0.02300');
    expect(texNum(185.7), '185.7');
    expect(texNum(1.064e-4), contains(r'\times10^{-4}'));
    expect(texNum(123456), contains(r'\times10^{5}'));
  });

  test('faults: save/restore keeps them and runs stay deterministic', () {
    String run() {
      final sim = fullSim();
      sim.faults.inject(const FaultSpec(
          type: FaultType.foaming,
          location: FaultLocation.whole(),
          severity: 0.3,
          onset: 100,
          ramp: 600));
      sim.advance(1500);
      return jsonEncode(sim.saveState());
    }

    expect(run(), run());
    final sim = fullSim();
    sim.faults.inject(const FaultSpec(
        type: FaultType.trayDamage,
        location: FaultLocation.stages(5, 5),
        severity: 1));
    sim.advance(200);
    final b = Simulator.restore(
        jsonDecode(jsonEncode(sim.saveState())) as Map<String, Object?>);
    sim.advance(100);
    b.advance(100);
    expect(jsonEncode(b.saveState()), jsonEncode(sim.saveState()));
    expect(b.faults.active.length, 1);
  });

  test('antifoam recovers a foaming column', () {
    final sim = fullSim();
    final id = sim.faults.inject(FaultSpec(
        type: FaultType.foaming,
        location: const FaultLocation.whole(),
        severity: 0.5,
        onset: sim.time,
        ramp: 60));
    sim.advance(1800);
    final bad = sim.snapshot().kpis.maxFloodPct;
    sim.setLever('antifoam', 1);
    sim.advance(3 * 3600);
    final good = sim.snapshot().kpis.maxFloodPct;
    expect(good, lessThan(bad));
    sim.faults.clear(id);
    expect(sim.faults.active, isEmpty);
  });

  test(
      'switching ideal to full hydraulics at steady state: no flow jumps above 5 %',
      () {
    final sim = btSim();
    final before = sim.snapshot();
    sim.setLever('hydraulics', 1);
    sim.advance(5);
    final after = sim.snapshot();
    for (var j = 1; j <= 20; j++) {
      final a = before.stages.liquidDown[j], b = after.stages.liquidDown[j];
      expect((b - a).abs() / a, lessThan(0.05), reason: 'L$j');
    }
    sim.setLever('hydraulics', 0);
    expect(sim.snapshot().kpis.columnDp, 0);
  });

  test('closed valves read exactly zero', () {
    final sim = btSim();
    sim.control.setMode('LC-101', LoopMode.man);
    sim.control.setOp('LC-101', 0);
    sim.advance(300);
    expect(sim.snapshot().kpis.d, 0.0);
  });
}
