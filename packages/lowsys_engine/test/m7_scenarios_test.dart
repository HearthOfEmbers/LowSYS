// M7 coder tests: G13 and H6 (VC-26.1 schema, G13 hint player, H6 key evidence per candidate, noise-on rule 1).
import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const _kmolh = 1000 / 3600;

/// H6 with one candidate forced (weight 1, the others 0), severity fixed, onset 600 s. [candidate] 'none' keeps
/// every weight at 0 for the first candidate's fault, then the fault is cleared below (the healthy planning case).
Simulator _h6(String candidate, {double? severity, bool noise = false, int seed = 3}) {
  final j = jsonDecode(Scenarios.jsonOf('H6_offspec_overhead')) as Map<String, Object?>;
  final copy = jsonDecode(jsonEncode(j)) as Map<String, Object?>;
  copy['noise'] = noise;
  copy['onsetWindow'] = [600, 600];
  final cands = copy['candidates']! as List<Object?>;
  final pick = candidate == 'none' ? 'fv102_stuck' : candidate;
  for (final c in cands) {
    final m = c! as Map<String, Object?>;
    m['weight'] = m['id'] == pick ? 1 : 0;
    if (m['id'] == pick && severity != null) (m['fault']! as Map<String, Object?>)['severityRange'] = [severity, severity];
    if (candidate == 'none' && m['id'] == pick) {
      // a vanishing feed upset: no fault at all, only the planning event
      m['fault'] = {
        'type': 'feedComposition',
        'params': {'dz': {'propane': 0.0}, 'sign': 1},
        'severityRange': [0.0, 0.0],
        'ramp': 0
      };
      m['answer'] = {'category': 'feedUpset', 'location': 'feed'};
    }
  }
  final def = ScenarioDef.fromJson(copy);
  final sim = Simulator(Presets.byId('debut'), options: SimOptions(seed: seed), warmStart: false);
  sim.startScenario(def, seed: seed);
  return sim;
}

Map<String, InstrumentReading> _inst(Simulator s) => {for (final i in s.snapshot().instruments) i.tag: i};

void main() {
  test('G13 and H6 validate (VC-26.1) and are listed', () {
    for (final id in ['G13_debutanizer_fug', 'H6_offspec_overhead']) {
      expect(Scenarios.allIds, contains(id));
      expect(Scenarios.byId(id).validate(), isEmpty, reason: id);
    }
    final h6 = Scenarios.byId('H6_offspec_overhead');
    expect(h6.view, 'plantCalc');
    expect(h6.candidates.map((c) => c.answerCategory), contains('pump'));
    expect(h6.candidates.map((c) => c.answerLocation), contains('refluxPump'));
  });

  test('G13 hint player: 80 kmol/h and 698 kW at 600 s meet o1; the FUG answers are right', () {
    final sim = Simulator(Presets.byId('debut'), options: const SimOptions(seed: 3), warmStart: false);
    sim.startScenario(Scenarios.byId('G13_debutanizer_fug'));
    expect(sim.scenario!.objectives[0].achieved, isFalse);
    sim.advance(600);
    sim.setLever('refluxFlow', 80 * _kmolh);
    sim.setLever('reboilerDuty', 698000);
    while (!sim.scenario!.objectives[0].achieved && sim.time < 86400) {
      sim.advance(60);
    }
    expect(sim.scenario!.objectives[0].achieved, isTrue, reason: 'o1 at ${sim.time}');
    // ignore: avoid_print
    print('G13 hint player: o1 met at ${sim.time} s (limit 86400, par 21600)');
    final fug = const FugCalculator()
        .compute(sim.snapshot(), sim.config.effectiveKeys, targets: const FugTargets(0.98, 0.98), thermo: sim.thermo)!;
    expect(fug.rMin, closeTo(1.30, 0.03));
    expect(fug.nMin, closeTo(10.9, 0.4));
    expect(sim.submitAnswer('o2', fug.rMin).correct, isTrue);
    expect(sim.submitAnswer('o3', fug.nMin).correct, isTrue);
    expect(sim.submitAnswer('o4', 0).correct, isTrue);
    expect(sim.submitAnswer('o5', 0).correct, isTrue);
    expect(sim.finishScenario().score, greaterThanOrEqualTo(60));
  }, timeout: const Timeout(Duration(minutes: 15)));

  group('H6 key evidence (noise off, the drill events included)', () {
    test('F07 heavier keys', () {
      final sim = _h6('feed_heavy_keys', severity: 0.75);
      final a0 = _inst(sim)['AT-100']!.value;
      final fc0 = sim.control.fc102.op;
      final ft0 = _inst(sim)['FT-102']!.value;
      final d0 = sim.snapshot().kpis.d;
      final ti0 = _inst(sim)['TI-101']!.value;
      final x0 = sim.liveMetric('kpi.xDHeavy') as double;
      sim.advance(600 + 1500);
      expect(a0 - _inst(sim)['AT-100']!.value, greaterThanOrEqualTo(0.02), reason: 'AT-100 down within 25 min of onset');
      sim.advance(2600 - sim.time);
      final span = 2 * 76.4 * _kmolh;
      expect((_inst(sim)['FT-102']!.value - ft0).abs(), lessThanOrEqualTo(0.02 * span));
      expect((sim.control.fc102.op - fc0).abs(), lessThanOrEqualTo(2.0));
      // ruling: within 2.5 kmol/h throughout, within 1 at 2 h after onset (checked below)
      expect(((sim.snapshot().kpis.d - d0) / _kmolh).abs(), lessThan(2.5));
      sim.advance(7200 - sim.time);
      final healthyF07 = _h6("none")..advance(7200);
      expect(((sim.snapshot().kpis.d - (healthyF07.liveMetric("kpi.d") as double)) / _kmolh).abs(), lessThan(1.0), reason: "D within 1 kmol/h of the healthy run at 2 h (planning event included)");
      expect(_inst(sim)['TI-101']!.value - ti0, greaterThanOrEqualTo(2.0), reason: 'TI-101 up');
      expect((sim.liveMetric('kpi.xDHeavy') as double) - x0, greaterThanOrEqualTo(0.02));
      // ignore: avoid_print
      print('H6 F07: xDHeavy ${(sim.liveMetric('kpi.xDHeavy') as double).toStringAsFixed(4)}, AT-100 ${_inst(sim)['AT-100']!.value}, '
          'D ${(sim.snapshot().kpis.d / _kmolh).toStringAsFixed(2)}');
    });

    test('F12 reflux pump capacity loss', () {
      final sim = _h6('reflux_pump', severity: 0.585);
      final a0 = _inst(sim)['AT-100']!.value;
      final ti0 = _inst(sim)['TI-101']!.value;
      final x0 = sim.liveMetric('kpi.xDHeavy') as double;
      final d0 = sim.snapshot().kpis.d;
      final cap = (1 - 0.585) * 152.8 * _kmolh;
      sim.advance(600 + 90);
      expect(_inst(sim)['FT-102']!.value, lessThan(cap * 1.05));
      sim.advance(120);
      expect(sim.control.fc102.op, greaterThan(99));
      expect(sim.control.alarms.isActive('FC-102.OPSAT'), isTrue);
      sim.advance(1800);
      expect((sim.snapshot().kpis.d - d0) / _kmolh, greaterThanOrEqualTo(5.0));
      sim.advance(7200 - sim.time);
      expect(_inst(sim)['TI-101']!.value - ti0, greaterThanOrEqualTo(3.0));
      expect((sim.liveMetric('kpi.xDHeavy') as double) - x0, greaterThanOrEqualTo(0.05));
      expect((_inst(sim)['AT-100']!.value - a0).abs(), lessThan(0.005));
      // ignore: avoid_print
      print('H6 F12: xDHeavy ${(sim.liveMetric('kpi.xDHeavy') as double).toStringAsFixed(4)}, D ${(sim.snapshot().kpis.d / _kmolh).toStringAsFixed(2)}');
    });

    test('F20 FV-102 stuck + planning, and the healthy planning event', () {
      final stuck = _h6('fv102_stuck');
      final healthy = _h6('none');
      final x0 = stuck.liveMetric('kpi.xDHeavy') as double;
      final b0 = stuck.liveMetric('kpi.xBLight') as double;
      final span = 152.8 * _kmolh;
      stuck.advance(2690);
      healthy.advance(2690);
      final ft = _inst(stuck)['FT-102']!.value;
      final op = stuck.control.fc102.op;
      expect(((stuck.liveMetric('kpi.xDHeavy') as double) - x0).abs(), lessThan(0.005));
      stuck.advance(600 + 10);
      healthy.advance(600 + 10);
      expect(stuck.control.fc102.op - op, greaterThanOrEqualTo(10.0));
      expect((_inst(stuck)['FT-102']!.value - ft).abs(), lessThanOrEqualTo(0.01 * span));
      final c4 = stuck.snapshot().crossChecks.where((c) => c.id == 'C4:FV-102').toList();
      expect(c4.isNotEmpty && c4.first.status.name == 'fail', isTrue, reason: 'C4:FV-102 ${c4.map((c) => c.status.name)}');
      stuck.advance(7200 - stuck.time);
      healthy.advance(7200 - healthy.time);
      // ruling: C3a not fail from event + 60 min, ok or check at 2 h; C5 recorded
      expect(stuck.snapshot().crossChecks.firstWhere((c) => c.id == 'C3a').status.name, isNot('fail'));
      // ignore: avoid_print
      print('H6 F20 C5: ${stuck.snapshot().crossChecks.where((c) => c.id.startsWith("C5")).map((c) => "${c.id}=${c.status.name}").join(",")}');
      final dStuck = stuck.liveMetric('kpi.d') as double, dHealthy = healthy.liveMetric('kpi.d') as double;
      // ruling: >= 3.5 (engine 3.97 at 2 h)
      expect((dStuck - dHealthy) / _kmolh, greaterThanOrEqualTo(3.5));
      expect((stuck.liveMetric('kpi.xDHeavy') as double) - x0, greaterThanOrEqualTo(0.02));
      // healthy planning event: compositions unchanged, the off-spec predicate never holds
      expect(((healthy.liveMetric('kpi.xDHeavy') as double) - x0).abs(), lessThanOrEqualTo(0.005));
      expect(((healthy.liveMetric('kpi.xBLight') as double) - b0).abs(), lessThanOrEqualTo(0.005));
      // ignore: avoid_print
      print('H6 F20: D ${(dStuck / _kmolh).toStringAsFixed(2)} vs healthy ${(dHealthy / _kmolh).toStringAsFixed(2)}, '
          'xDHeavy ${(stuck.liveMetric('kpi.xDHeavy') as double).toStringAsFixed(4)}; healthy Q_C ${(healthy.snapshot().kpis.qc / 1000).toStringAsFixed(1)} kW');
    });
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('H6 rule 1: with noise on, C4:FV-102 leaves ok within 10 min of the planning event (seeds 1 to 3)', () {
    for (final seed in [1, 2, 3]) {
      final sim = _h6('fv102_stuck', noise: true, seed: seed);
      sim.advance(2700);
      var failedAt = double.nan;
      var minSigma = 9.0, maxSigma = 0.0;
      for (var t = 0; t < 600; t += 10) {
        sim.advance(10);
        final c4 = sim.snapshot().crossChecks.where((c) => c.id == 'C4:FV-102');
        if (failedAt.isNaN && c4.isNotEmpty && c4.first.status.name != 'ok') failedAt = sim.time - 2700;
        final r = _inst(sim)['FT-102']!;
        if (r.typicalSigma > 0) {
          final ratio = r.sigma5min / r.typicalSigma;
          if (ratio < minSigma) minSigma = ratio;
          if (ratio > maxSigma) maxSigma = ratio;
        }
      }
      // ignore: avoid_print
      print('H6 rule 1 seed $seed: C4:FV-102 left ok after ${failedAt.toStringAsFixed(0)} s; FT-102 sigma ratio $minSigma .. $maxSigma');
      expect(failedAt.isNaN, isFalse, reason: 'seed $seed');
      expect(failedAt, lessThanOrEqualTo(600));
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
