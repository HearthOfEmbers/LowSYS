// VC-26 scenario engine: schema, predicates, scoring, completable guided
// scenarios, drill draws.
library;

import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';
import 'reference/validation_expectations_m3.dart';

void main() {
  test('VC-26.1 schema: every shipped scenario validates; broken copies do not',
      () {
    for (final id in Scenarios.ids) {
      expect(Scenarios.byId(id).validate(), isEmpty, reason: id);
    }
    final h9 = jsonDecode(Scenarios.jsonOf('H9_dont_trust_the_gauge'))
        as Map<String, Object?>;
    Map<String, Object?> copy() =>
        jsonDecode(jsonEncode(h9)) as Map<String, Object?>;
    final badMetric = copy();
    (badMetric['offSpec'] as Map)['when'] = {
      'metric': 'kpi.nope',
      'op': '<',
      'value': 1
    };
    expect(ScenarioDef.fromJson(badMetric).validate(), isNotEmpty);
    final badLever = copy();
    ((badLever['levers'] as Map)['set'] as Map)['noSuchLever'] = 1;
    expect(ScenarioDef.fromJson(badLever).validate(), isNotEmpty);
    final zeroWeights = copy();
    for (final c in zeroWeights['candidates'] as List) {
      (c as Map)['weight'] = 0;
    }
    expect(ScenarioDef.fromJson(zeroWeights).validate(), isNotEmpty);
    final badTemplate = copy();
    badTemplate['debrief'] = 'x {result.noSuchThing}';
    expect(ScenarioDef.fromJson(badTemplate).validate(), isNotEmpty);
    final badWindow = copy();
    badWindow['onsetWindow'] = [600, 4000];
    expect(ScenarioDef.fromJson(badWindow).validate(), isNotEmpty);
  });

  group('VC-26.2 predicates', () {
    Predicate p(Map<String, Object?> j) => Predicate.fromJson(j);
    test('all/any/not, between, == tolerance, strings, from start, NaN', () {
      final ctx = FakeMetricContext(
          {'a': 1.0, 'b': 2.0, 'q': 'good', 'n': double.nan},
          start: {'a': 0.97});
      expect(
          p({
            'all': [
              {'metric': 'a', 'op': '>', 'value': 0.5},
              {'metric': 'b', 'op': '<=', 'value': 2}
            ]
          }).evaluate(ctx),
          isTrue);
      expect(
          p({
            'any': [
              {'metric': 'a', 'op': '>', 'value': 5},
              {'metric': 'b', 'op': '==', 'value': 2 + 1e-10}
            ]
          }).evaluate(ctx),
          isTrue);
      expect(
          p({
            'not': {'metric': 'a', 'op': '>', 'value': 0.5}
          }).evaluate(ctx),
          isFalse);
      expect(
          p({'metric': 'b', 'op': 'between', 'lo': 1, 'hi': 3}).evaluate(ctx),
          isTrue);
      expect(p({'metric': 'q', 'op': '==', 'value': 'good'}).evaluate(ctx),
          isTrue);
      final ctx2 = FakeMetricContext({'a': 0.955}, start: {'a': 0.97});
      expect(
          p({'metric': 'a', 'from': 'start', 'op': '<', 'value': -0.01})
              .evaluate(ctx2),
          isTrue);
      expect(p({'metric': 'n', 'op': '<', 'value': 1}).evaluate(ctx), isFalse);
      expect(p({'metric': 'n', 'op': '!=', 'value': 1}).evaluate(ctx), isTrue);
    });
  });

  group('VC-26.3 scoring arithmetic', () {
    test('guided example scores 64', () {
      final s = Scoring.guided(
        weights: const ScoringWeights(
            objectives: 0.6, time: 0.2, safety: 0.1, quality: 0.1),
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
      expect(s.score, vc263.guided);
    });
    test('drill examples score 96 and 20', () {
      final w = const DrillScoringWeights(
          category: 0.5,
          location: 0.2,
          time: 0.2,
          safety: 0.1,
          timeFull: 600,
          timeZero: 3600,
          wrongPenalty: 0.1,
          protectBonus: 0.1,
          modeBonus: 0.05);
      final s = Scoring.drill(
        weights: w,
        t0: 1200,
        attempts: const [
          DrillAttempt(
              time: 2100, categoryOk: true, locationOk: false, modeOk: false),
          DrillAttempt(
              time: 2700, categoryOk: true, locationOk: true, modeOk: true)
        ],
        protectMetAt: 1500,
        offSpecAt: 2000,
        reliefLifted: false,
        levelViolationSeconds: 0,
        hintCost: 0.03,
        hasProtect: true,
      );
      expect(s.score, vc263.drill);
      final never = Scoring.drill(
          weights: w,
          t0: 1200,
          attempts: const [],
          protectMetAt: 1500,
          offSpecAt: 2000,
          reliefLifted: false,
          levelViolationSeconds: 0,
          hintCost: 0,
          hasProtect: true);
      expect(never.score, vc263.drillNever);
    });
  });

  group('VC-26.4 guided scenarios are completable (reference checkpoints)', () {
    test('G2 xD at R = 1.30 / 1.20 / 1.15 / 1.12', () {
      final sim = newSim(btConfig(overrides: {
        'sections[0].trays': 60,
        'feeds[0].stage': 30,
        'murphree': 1.0
      }));
      // the hint "boilup = 50 (R + 1)" keeps D = 50 on every step; at a
      // fixed 115 kmol/h and R = 1.2, D = 52.3 and x_D is capped at 0.9565
      // by the balance (the engine gives exactly that)
      sim.setLever('refluxMode', 1);
      for (final (r, xd) in [
        (1.30, 0.99279),
        (1.20, 0.97142),
        (1.15, 0.96071),
        (1.12, 0.95429)
      ]) {
        sim.setLever('boilup', 50 * (r + 1) * kmolh);
        sim.setLever('refluxRatio', r);
        final p = runSteady(sim);
        expect(p.xD, closeTo(xd, 1e-4), reason: 'R = $r');
      }
    });
    test(
        'G4 minimum boilup at each q (D = 50): specs met at 1.02 V_min, missed at 0.98 V_min',
        () {
      for (final (q, vMin, l0) in [
        (1.2, 129.0, 59.0),
        (1.0, 115.5, 65.5),
        (0.5, 87.05, 87.05),
        (0.0, 66.96, 116.96)
      ]) {
        for (final (f, ok) in [(1.02, true), (0.98, false)]) {
          final sim = newSim(btConfig());
          sim.setLever('feedQ', q);
          sim.setLever('boilup', f * vMin * kmolh);
          sim.setLever('refluxFlow', (f * vMin + (1 - q) * 100 - 50) * kmolh);
          final p = runSteady(sim);
          expect(p.dKmolh, closeTo(50, 0.05), reason: 'q=$q D');
          if (ok) {
            expect(p.xD >= 0.95 && p.xB <= 0.05, isTrue,
                reason: 'q=$q at 1.02 V_min: xD ${p.xD} xB ${p.xB}');
          } else {
            expect(p.xD < 0.95, isTrue,
                reason: 'q=$q at 0.98 V_min: xD ${p.xD}');
          }
          expect(l0, greaterThan(0));
        }
      }
    });
    test('G6 N = 28 → 0.98056, N = 27 → 0.97761 (E 0.5)', () {
      for (final (n, xd) in [(28, 0.98056), (27, 0.97761)]) {
        final sim = newSim(btConfig(overrides: {
          'sections[0].trays': n,
          'feeds[0].stage': n == 27
              ? 13
              : 14, // doc: 27 → feed 13 (floor of 13.5); 14 gives 0.97870
          'murphree': 0.5
        }));
        expect(runSteady(sim).xD, closeTo(xd, 1e-4), reason: 'N = $n');
      }
    });
  });

  group('VC-26.5 drill draws', () {
    test(
        'H9: pure function of the seed; frequencies within 3σ; onset a multiple of dt; nothing leaks',
        () {
      final def = Scenarios.byId('H9_dont_trust_the_gauge');
      final weights = <String, double>{};
      var total = 0.0;
      for (final c in def.candidates) {
        weights[c.id] = c.weight;
        total += c.weight;
      }
      final counts = <String, int>{};
      for (var seed = 1; seed <= 10000; seed++) {
        final d1 = DrillDraw.draw(def, seed), d2 = DrillDraw.draw(def, seed);
        expect(d1.candidateId, d2.candidateId);
        expect(d1.severity, d2.severity);
        expect(d1.onset, d2.onset);
        expect(d1.sign, d2.sign);
        counts[d1.candidateId] = (counts[d1.candidateId] ?? 0) + 1;
        expect((d1.onset / 0.5) - (d1.onset / 0.5).round(), closeTo(0, 1e-9));
        expect(d1.onset, inInclusiveRange(600, 1800));
      }
      for (final e in weights.entries) {
        final p = e.value / total;
        final sigma = (10000 * p * (1 - p)).clamp(1, double.infinity);
        expect(counts[e.key] ?? 0, closeTo(10000 * p, 3 * sigma.sqrt()),
            reason: e.key);
      }
    });
    test('during a drill no snapshot field names the fault',
        skip: 'H9/H10 need Tier 2 (DEVIATIONS E39); M4', () {
      final sim = newSim(btFull(), options: const SimOptions(seed: 3));
      runSteady(sim);
      sim.startScenario(Scenarios.byId('H10_valve_or_meter'));
      sim.advance(2400);
      final s = sim.snapshot();
      expect(s.visibleFaults, isEmpty);
      final text = jsonEncode(s.scenario!.toJson());
      expect(
          text.contains('stuck') ||
              text.contains('plugged') ||
              text.contains('bias') ||
              text.contains('drift'),
          isFalse);
    });
  });
}

extension on num {
  double sqrt() => toDouble() <= 0 ? 0 : (toDouble()).toDouble().sqrtImpl();
}

extension on double {
  double sqrtImpl() {
    var x = this;
    var r = x;
    for (var i = 0; i < 60; i++) {
      r = 0.5 * (r + x / r);
    }
    return r;
  }
}
