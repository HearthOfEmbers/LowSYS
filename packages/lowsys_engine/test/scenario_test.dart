import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const kmolh = 1000 / 3600;

void main() {
  test('every shipped scenario validates', () {
    for (final id in Scenarios.ids) {
      expect(Scenarios.byId(id).validate(), isEmpty, reason: id);
    }
  });

  test('broken copies of H9 do not validate', () {
    final h9 = jsonDecode(Scenarios.jsonOf('H9_dont_trust_the_gauge')) as Map<String, Object?>;
    Map<String, Object?> copy() => jsonDecode(jsonEncode(h9)) as Map<String, Object?>;
    final badMetric = copy();
    (badMetric['offSpec'] as Map)['when'] = {'metric': 'kpi.nope', 'op': '<', 'value': 1};
    expect(ScenarioDef.fromJson(badMetric).validate(), isNotEmpty);
    final badLever = copy();
    ((badLever['levers'] as Map)['set'] as Map)['noSuchLever'] = 1;
    expect(ScenarioDef.fromJson(badLever).validate(), isNotEmpty);
    final zero = copy();
    for (final c in zero['candidates'] as List) {
      (c as Map)['weight'] = 0;
    }
    expect(ScenarioDef.fromJson(zero).validate(), isNotEmpty);
    final tpl = copy();
    tpl['debrief'] = 'x {result.noSuchThing}';
    expect(ScenarioDef.fromJson(tpl).validate(), isNotEmpty);
    final win = copy();
    win['onsetWindow'] = [600, 4000];
    expect(ScenarioDef.fromJson(win).validate(), isNotEmpty);
  });

  test('scoring arithmetic: 64, 96 and 20', () {
    final g = Scoring.guided(
      weights: const ScoringWeights(),
      objectiveWeights: [1, 1, 1],
      achieved: [true, true, false],
      tEnd: 30000,
      parTime: 10800,
      timeLimit: 43200,
      reliefLifted: false,
      levelViolationSeconds: 0,
      qualityFraction: 0.9,
      hintCost: 0,
    );
    expect(g.score, 64);
    const w = DrillScoringWeights(protectBonus: 0.1, modeBonus: 0.05);
    final d = Scoring.drill(
      weights: w,
      t0: 1200,
      attempts: const [
        DrillAttempt(time: 2100, categoryOk: true, locationOk: false),
        DrillAttempt(time: 2700, categoryOk: true, locationOk: true, modeOk: true),
      ],
      protectMetAt: 1500,
      offSpecAt: 2000,
      reliefLifted: false,
      levelViolationSeconds: 0,
      hintCost: 0.03,
      hasProtect: true,
    );
    expect(d.score, 96);
    final never = Scoring.drill(weights: w, t0: 1200, attempts: const [], protectMetAt: 1500, offSpecAt: 2000, reliefLifted: false, levelViolationSeconds: 0, hintCost: 0, hasProtect: true);
    expect(never.score, 20);
  });

  test('predicates', () {
    Predicate p(Map<String, Object?> j) => Predicate.fromJson(j);
    final ctx = FakeMetricContext({'a': 1.0, 'b': 2.0, 'q': 'good', 'n': double.nan}, start: {'a': 0.97});
    expect(p({'metric': 'q', 'op': '==', 'value': 'good'}).evaluate(ctx), isTrue);
    expect(p({'metric': 'n', 'op': '<', 'value': 1}).evaluate(ctx), isFalse);
    expect(p({'metric': 'n', 'op': '!=', 'value': 1}).evaluate(ctx), isTrue);
    final c2 = FakeMetricContext({'a': 0.955}, start: {'a': 0.97});
    expect(p({'metric': 'a', 'from': 'start', 'op': '<', 'value': -0.01}).evaluate(c2), isTrue);
  });

  test('G3 can be completed through the scenario engine', () {
    final sim = Simulator(Presets.byId('bt'));
    sim.startScenario(Scenarios.byId('G3_total_reflux'));
    expect(sim.time, 0);
    sim.control.setSp('FC-101', 0);
    sim.control.setMode('LC-101', LoopMode.man);
    sim.control.setOp('LC-101', 0);
    sim.control.setMode('LC-102', LoopMode.man);
    sim.control.setOp('LC-102', 0);
    sim.setLever('refluxFlow', sim.lever('boilup'));
    for (var i = 0; i < 400; i++) {
      sim.advance(60);
    }
    expect(sim.scenario!.objectives[0].achieved, isTrue);
    expect(sim.submitAnswer('o2', 6.0).correct, isTrue);
    final card = sim.finishScenario();
    expect(card.completed, isTrue);
  });

  test('drill draws are a pure function of the seed', () {
    final def = Scenarios.byId('H9_dont_trust_the_gauge');
    final a = DrillDraw.draw(def, 7), b = DrillDraw.draw(def, 7);
    expect(a.candidateId, b.candidateId);
    expect(a.onset, b.onset);
    expect(a.onset % 0.5, 0);
    expect(a.onset, inInclusiveRange(600, 1800));
  });
}
