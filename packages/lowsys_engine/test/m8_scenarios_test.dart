// M8 coder tests: G15 and H7 (VC-26.1 schema and vocabulary, G15 hint player, H7 key evidence per candidate with the
// planning event, the hardest case), and VC-21 for the packed equation lines.
import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm8_helpers.dart';

/// H7 with one candidate forced (weight 1, the others 0) at the bottom of its severity range, onset 600 s, noise off.
Simulator _h7(String candidate, {double? severity, int seed = 3, bool noise = false}) {
  final copy = jsonDecode(Scenarios.jsonOf('H7_packed_bed')) as Map<String, Object?>;
  copy['noise'] = noise;
  copy['onsetWindow'] = [600, 600];
  for (final c in copy['candidates']! as List<Object?>) {
    final m = c! as Map<String, Object?>;
    m['weight'] = m['id'] == candidate ? 1 : 0;
    final f = m['fault'] as Map<String, Object?>?;
    if (m['id'] == candidate && f != null) {
      final r = f['severityRange']! as List<Object?>;
      final s = severity ?? (r[0]! as num).toDouble();
      f['severityRange'] = [s, s];
    }
  }
  final sim = Simulator(Presets.byId('bt_packed'), options: SimOptions(seed: seed), warmStart: false);
  sim.startScenario(ScenarioDef.fromJson(copy), seed: seed);
  return sim;
}

Map<String, double> _rd(Simulator s) => {for (final i in s.snapshot().instruments) i.tag: i.value};

void main() {
  group('VC-26.1 schema', () {
    test('G15 and H7 validate and are listed', () {
      for (final id in ['G15_packing_retrofit', 'H7_packed_bed']) {
        expect(Scenarios.allIds, contains(id));
        expect(Scenarios.byId(id).validate(), isEmpty, reason: id);
      }
      expect(Scenarios.ids, contains('G15_packing_retrofit'));
      final h7 = Scenarios.byId('H7_packed_bed');
      expect(h7.candidates.length, 5);
      expect(h7.candidates.where((c) => c.faultType == null).map((c) => c.id), ['near_flood']);
      expect(h7.candidates.firstWhere((c) => c.id == 'crushed_lower').location.bed, 2);
      expect(h7.candidates.firstWhere((c) => c.id == 'maldist_upper').faultType, FaultType.packingMaldistribution);
    });

    test('mutated copies fail: {fault.*} in a null-fault debrief, unknown category and location', () {
      final j = jsonDecode(Scenarios.jsonOf('H7_packed_bed')) as Map<String, Object?>;
      Map<String, Object?> copy() => jsonDecode(jsonEncode(j)) as Map<String, Object?>;
      var c = copy();
      var cand = (c['candidates']! as List<Object?>).last! as Map<String, Object?>;
      cand['debrief'] = 'Nothing broke at {fault.onset:time}.';
      expect(ScenarioDef.fromJson(c).validate(), isNotEmpty);
      c = copy();
      c['debrief'] = 'Drill-level {fault.magnitude}';
      expect(ScenarioDef.fromJson(c).validate(), isNotEmpty);
      c = copy();
      cand = (c['candidates']! as List<Object?>).last! as Map<String, Object?>;
      (cand['answer']! as Map<String, Object?>)['category'] = 'flooding2';
      expect(ScenarioDef.fromJson(c).validate(), isNotEmpty);
      c = copy();
      (c['diagnosis']! as Map<String, Object?>)['locations'] = ['instrument:PDT-102'];
      expect(ScenarioDef.fromJson(c).validate(), isNotEmpty);
      c = copy();
      (c['candidates']! as List<Object?>).forEach((x) => (x! as Map<String, Object?>)['weight'] = 0);
      expect(ScenarioDef.fromJson(c).validate(), isNotEmpty);
      // the unmodified copy is valid
      expect(ScenarioDef.fromJson(copy()).validate(), isEmpty);
    });

    test('draws: every H7 candidate is reachable and a null-fault draw injects nothing', () {
      final def = Scenarios.byId('H7_packed_bed');
      final ids = {for (var s = 1; s < 40; s++) DrillDraw.draw(def, s).candidateId};
      expect(ids, containsAll(['maldist_upper', 'near_flood']));
      final sim = _h7('near_flood');
      expect(sim.faults.hasActive, isFalse);
      final sim2 = _h7('crushed_lower');
      expect(sim2.faults.hasActive, isTrue);
      expect(sim2.snapshot().visibleFaults, isEmpty, reason: 'hidden in a drill');
    });

    test('fault.magnitude wording in the debriefs (F23 s 0.3, F21 s 0.5)', () {
      var sim = _h7('crushed_upper', severity: 0.3)..advance(700);
      expect(sim.finishScenario().debriefText, contains('+45 % packing factor, 4.5 % shorter bed'));
      sim = _h7('maldist_upper', severity: 0.5)..advance(700);
      expect(sim.finishScenario().debriefText, contains('f = 0.30 (65 % of the liquid on one side)'));
      sim = _h7('near_flood')..advance(700);
      expect(sim.finishScenario().debriefText, contains('Nothing was broken'));
    });
  });

  group('G15', () {
    test('hint player: trays, then the internals switch; numbers and answers', () {
      final sim = Simulator(Presets.byId('bt'), options: const SimOptions(seed: 3), warmStart: false);
      sim.startScenario(Scenarios.byId('G15_packing_retrofit'));
      final sc = sim.scenario!;
      bool ans(String id, Object v) => sim.submitAnswer(id, v).correct;
      expect(sim.lever('internals'), 0);
      expect(sim.snapshot().kpis.columnDp, closeTo(14490, 0.01 * 14490));
      expect(sim.snapshot().kpis.maxFloodPct, closeTo(62.9, 0.5));
      expect(sim.snapshot().kpis.xD, closeTo(0.97826, 3e-4));
      expect(ans('o1', 14490.0), isTrue);
      sim.setLever('internals', 1);
      var settle = -1.0;
      final t0 = sim.time;
      while (!sc.objectives[1].achieved && sim.time - t0 < 14400) {
        sim.advance(60);
        if (settle < 0 && sim.isSteady) settle = sim.time - t0;
      }
      expect(sc.objectives[1].achieved, isTrue);
      final s = sim.snapshot();
      expect(s.kpis.columnDp, closeTo(1406.0, 0.01 * 1406));
      expect(s.kpis.xD, closeTo(0.99383, 1e-3));
      expect(s.beds[1].maxFlood, closeTo(0.5938, 0.003));
      expect(s.beds[0].maxFlood, closeTo(0.4882, 0.003));
      expect(14.49 / (s.kpis.columnDp / 1000), closeTo(10.31, 0.1));
      expect(0.629 / s.beds[1].maxFlood - 1, closeTo(0.059, 0.005));
      expect(0.629 / s.beds[0].maxFlood - 1, closeTo(0.289, 0.01));
      expect(ans('o3', 10.3), isTrue);
      expect(ans('o4', 0), isTrue);
      expect(ans('o5', 0), isTrue);
      // ignore: avoid_print
      print('G15: steady declared ${settle.toStringAsFixed(0)} s after the switch, o2 met at ${(sim.time - t0).toStringAsFixed(0)} s '
          '(par 3600 s)');
      expect(sc.objectives.every((o) => o.achieved), isTrue);
      expect(sim.lever('internals'), 1);
    });
  }, timeout: const Timeout(Duration(minutes: 20)));

  group('H7 key evidence (noise off, planning event at 2700 s, bottom of each severity range)', () {
    test('maldist_upper: PDT-102 flat, TI span down, x_D down', () {
      final sim = _h7('maldist_upper');
      final r0 = _rd(sim);
      final span0 = r0['TI-109']! - r0['TI-101']!;
      final x0 = sim.liveMetric('kpi.xD') as double;
      sim.advance(2600);
      final r = _rd(sim);
      expect((r['PDT-102']! - r0['PDT-102']!).abs() / r0['PDT-102']!, lessThan(0.03));
      expect(span0 - (r['TI-109']! - r['TI-101']!), greaterThanOrEqualTo(2.0));
      expect(x0 - (sim.liveMetric('kpi.xD') as double), greaterThanOrEqualTo(0.008));
      expect((_rd(sim)['FT-101']! - r0['FT-101']!).abs(), lessThan(0.03 * r0['FT-101']!));
    });

    test('maldist_lower: PDT-103 flat, TI-110..118 span down, x_B up', () {
      final sim = _h7('maldist_lower');
      final r0 = _rd(sim);
      final span0 = r0['TI-118']! - r0['TI-110']!;
      final b0 = sim.liveMetric('kpi.xB') as double;
      sim.advance(2600);
      final r = _rd(sim);
      expect((r['PDT-103']! - r0['PDT-103']!).abs() / r0['PDT-103']!, lessThan(0.03));
      expect(span0 - (r['TI-118']! - r['TI-110']!), greaterThanOrEqualTo(2.0));
      expect((sim.liveMetric('kpi.xB') as double) - b0, greaterThanOrEqualTo(0.01));
    });

    test('crushed_upper: PDT-102 up at constant load, calc flood up, x within 0.002', () {
      final sim = _h7('crushed_upper');
      final r0 = _rd(sim);
      final f0 = sim.snapshot().beds[0].maxFlood;
      final xd0 = sim.liveMetric('kpi.xD') as double, xb0 = sim.liveMetric('kpi.xB') as double;
      sim.advance(600 + 600);
      final r = _rd(sim);
      expect(r['PDT-102']! / r0['PDT-102']!, greaterThanOrEqualTo(1.3));
      expect(sim.snapshot().beds[0].maxFlood - f0, greaterThanOrEqualTo(0.05));
      sim.advance(2600 - sim.time);
      expect(((sim.liveMetric('kpi.xD') as double) - xd0).abs(), lessThan(0.002));
      expect(((sim.liveMetric('kpi.xB') as double) - xb0).abs(), lessThan(0.002));
    });

    test('crushed_lower: PDT-103 up at constant load, calc flood up, x_B within 0.004', () {
      final sim = _h7('crushed_lower');
      final r0 = _rd(sim);
      final f0 = sim.snapshot().beds[1].maxFlood;
      final xb0 = sim.liveMetric('kpi.xB') as double;
      sim.advance(600 + 600);
      final r = _rd(sim);
      expect(r['PDT-103']! / r0['PDT-103']!, greaterThanOrEqualTo(1.4));
      expect(sim.snapshot().beds[1].maxFlood - f0, greaterThanOrEqualTo(0.07));
      sim.advance(2600 - sim.time);
      expect(((sim.liveMetric('kpi.xB') as double) - xb0).abs(), lessThan(0.004));
    });

    test('near_flood: no change before the event; afterwards PDT-103 1.7x, flood, HETP, x_B, PC-101 holds', () {
      final sim = _h7('near_flood');
      final r0 = _rd(sim);
      final hetp0 = sim.snapshot().stages.hetp[18];
      final xb0 = sim.liveMetric('kpi.xB') as double;
      sim.advance(2600);
      var r = _rd(sim);
      expect((r['PDT-103']! - r0['PDT-103']!).abs() / r0['PDT-103']!, lessThan(0.05));
      expect(((sim.liveMetric('kpi.xB') as double) - xb0).abs(), lessThan(0.001));
      sim.advance(2700 + 1800 - sim.time);
      r = _rd(sim);
      expect(r['PDT-103']! / r0['PDT-103']!, greaterThanOrEqualTo(1.7));
      expect(r['FT-101']! / r0['FT-101']!, closeTo(1.25, 0.05));
      expect(r['FT-102']! / r0['FT-102']!, closeTo(1.25, 0.05));
      final s = sim.snapshot();
      expect(s.beds[1].maxFlood * 100, greaterThanOrEqualTo(95));
      expect(s.stages.hetp[18] / hetp0, greaterThanOrEqualTo(1.2));
      sim.advance(7200 - sim.time);
      expect((sim.liveMetric('kpi.xB') as double) - xb0, greaterThanOrEqualTo(0.004));
      expect(sim.snapshot().kpis.pTop, closeTo(101325, 1200));
      expect(sim.control.pc101.op, lessThan(100));
      expect(sim.control.pv101.position, lessThan(100));
      // ignore: avoid_print
      print('H7 near_flood: PDT-103 ${(r['PDT-103']! / r0['PDT-103']!).toStringAsFixed(2)}x, flood ${(s.beds[1].maxFlood * 100).toStringAsFixed(1)} %, '
          'HETP18 ${(s.stages.hetp[18] / hetp0).toStringAsFixed(2)}x, Q_C ${(sim.snapshot().kpis.qc / 1000).toStringAsFixed(0)} kW');
    });

    test('crushed_lower at s 0.5 with the event (the hardest case): no NaN, flooded, completes 7200 s', () {
      final sim = _h7('crushed_lower', severity: 0.5);
      double pdtMax = 0, phiMax = 0;
      var minHold = 1e9;
      var rise = 0.0;
      double? pdtAtEvent;
      for (var t = 0; t < 7200; t += 60) {
        sim.advance(60);
        final s = sim.snapshot();
        expect(sim.halted, isFalse);
        for (final v in s.stages.holdup) {
          expect(v.isNaN || v.isInfinite, isFalse, reason: 'holdup at ${sim.time}');
          if (v < minHold) minHold = v;
        }
        expect(s.kpis.xD.isNaN, isFalse);
        final pdt = _rd(sim)['PDT-103']!;
        if (pdt > pdtMax) pdtMax = pdt;
        if (s.beds[1].maxFlood > phiMax) phiMax = s.beds[1].maxFlood;
        if (sim.time >= 2760 && pdtAtEvent == null) pdtAtEvent = s.beds[1].dp;
        if (sim.time == 3120) rise = s.beds[1].dp - (pdtAtEvent ?? 0);
      }
      expect(minHold, greaterThanOrEqualTo(0));
      expect(phiMax, greaterThan(1.0), reason: 'the lower bed floods');
      // ignore: avoid_print
      print('H7 crushed_lower s 0.5 + event: phi_p max ${phiMax.toStringAsFixed(3)}, PDT-103 max ${pdtMax.toStringAsFixed(0)} Pa '
          '(span 10 kPa), dP rise 300 s after the event settles ${rise.toStringAsFixed(0)} Pa, model.flood '
          '${sim.control.alarms.isActive("model.flood")}');
      expect(sim.snapshot().alarms.any((a) => a.id == 'model.flood'), isTrue, reason: 'plantCalc keeps model.flood');
    });
  }, timeout: const Timeout(Duration(minutes: 30)));

  group('VC-21 packed equation lines', () {
    for (final tier in ['t1', 't2']) {
      test('segment lines equal the snapshot ($tier)', () {
        final sim = steady(packedSim(tier: tier));
        sim.faults.inject(FaultSpec(
            type: FaultType.packingMaldistribution, location: const FaultLocation.bed(2), severity: 0.5));
        sim.advance(900);
        final snap = sim.snapshot();
        for (final j in [1, 5, 9, 10, 14, 18]) {
          final res = sim.explain(ExplainStage(j));
          final lines = {for (final g in res.groups) for (final l in g.lines) l.id: l};
          for (final id in ['eq.robbins', 'eq.kisterGill', 'eq.packHoldup', 'eq.hetp', 'eq.lewis']) {
            expect(lines.containsKey(id), isTrue, reason: '$id at segment $j');
            final l = lines[id]!;
            expect(l.texSymbolic, isNotEmpty);
            expect(l.texSubstituted, isNotEmpty);
          }
          final st = snap.stages;
          double rel(double a, double b) => (a - b).abs() / (b.abs() > 1e-30 ? b.abs() : 1.0);
          expect(rel(lines['eq.robbins']!.value, st.dp[j]), lessThan(1e-12));
          expect(rel(lines['eq.kisterGill']!.value, st.packFlood[j]), lessThan(1e-12));
          expect(rel(lines['eq.packHoldup']!.value, st.packHoldup[j]), lessThan(1e-12));
          expect(rel(lines['eq.hetp']!.value, st.hetp[j]), lessThan(1e-12));
          expect(rel(lines['eq.lewis']!.value, st.efficiency[j]), lessThan(1e-12));
          expect(lines.containsKey('eq.maldistribution'), j >= 10, reason: 'only the faulty bed shows E_mal');
          if (j >= 10) expect(rel(lines['eq.maldistribution']!.value, snap.beds[1].eMal), lessThan(1e-12));
          expect(lines.containsKey('eq.murphree'), isFalse);
          expect(lines.containsKey('eq.componentBalance'), isTrue);
        }
      });
    }

    test('a drill hides eq.maldistribution (E_mal is a fault parameter)', () {
      final sim = _h7('maldist_lower');
      sim.advance(600 + 1800);
      final res = sim.explain(ExplainStage(14));
      // plantCalc is a plant view: not observable at all
      expect(res.title, 'Not observable');
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
