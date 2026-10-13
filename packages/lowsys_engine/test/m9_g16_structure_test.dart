// M9: VC-15.6 G16, VC-15.7 structure and robustness, VC-26.1 on G16 and H8, VC-21 equation ids.
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm9_helpers.dart';

void main() {
  group('VC-15.6 G16', () {
    bool meets(CrudeProductKpis k) => c(k.d86p95[1]) <= 235 && k.gapDieselKero >= 0 && c(k.residueTbp5) >= 355;
    test('the start fails; PA 3 MW and SS2 steam alone meet; a cut-point shift alone does not', () {
      var k = kpiOf(crudeSim());
      expect(meets(k), isFalse);
      expect(c(k.d86p95[1]), closeTo(238.2, 3));
      k = kpiOf(steadyC(crudeSim(levers: {'paDuty': 3e6})));
      expect(meets(k), isTrue);
      expect(c(k.d86p95[1]), closeTo(231.1, 3));
      expect(k.gapDieselKero, closeTo(6.5, 3));
      expect(c(k.residueTbp5), closeTo(358.4, 2));
      k = kpiOf(steadyC(crudeSim(levers: {'steam.ss2': 1000 / 3600})));
      expect(meets(k), isTrue);
      expect(c(k.d86p95[1]), closeTo(232.3, 3));
      expect(k.gapDieselKero, closeTo(12.6, 3));
      k = kpiOf(steadyC(crudeSim(levers: {'drawRate.kero': 0.107 * crudeRate0, 'drawRate.diesel': 0.177 * crudeRate0})));
      expect(meets(k), isFalse);
      expect(c(k.d86p95[1]), closeTo(231.0, 3));
      expect(k.gapDieselKero, closeTo(-7.1, 3));
      k = kpiOf(steadyC(crudeSim(levers: {'paDuty': 3e6, 'steam.ss2': 1000 / 3600})));
      expect(k.gapDieselKero, closeTo(12.9, 3));
      // bottom steam 1000 kg/h fails the residue term (351.1 C)
      k = kpiOf(steadyC(crudeSim(levers: {'paDuty': 3e6, 'steam.bottom': 1000 / 3600})));
      expect(c(k.residueTbp5), lessThan(355));
    });

    test('scenario: starts steady, hint values complete it, the debrief carries the required text', () {
      final def = Scenarios.byId('G16_crude_gaps');
      expect(def.validate(), isEmpty);
      final sim = Simulator(Presets.byId('crude'));
      sim.startScenario(def);
      var snap = sim.snapshot();
      expect(snap.scenario!.objectives.first.met, isFalse);
      // locked levers cannot be moved by the app; the engine still enforces ranges
      sim.setLever('paDuty', 3e6);
      sim.setLever('steam.ss2', 1000 / 3600);
      sim.runToSteadyState(maxSimSeconds: 8 * 3600);
      sim.advance(900);
      snap = sim.snapshot();
      expect(snap.scenario!.objectives.first.met, isTrue);
      expect(def.debrief, contains('Draw rates set cut points; fractionation and stripping set gaps.'));
    });
  });

  group('VC-15.7 structure', () {
    test('configuration: tier, levers, validate() rejections, tags', () {
      final cfg = Presets.byId('crude');
      expect(cfg.availableTiers, {ThermoTier.t2});
      final sim = Simulator(cfg);
      final ids = sim.levers.map((l) => l.id).toSet();
      for (final bad in ['murphree', 'nTrays', 'feedStage', 'internals', 'refluxFlow', 'boilup', 'tier']) {
        expect(ids.contains(bad), isFalse, reason: bad);
      }
      expect(ids, containsAll(['crudeRate', 'cot', 'pTop', 'topTSp', 'drawRate.kero', 'paDuty', 'steam.bottom', 'drumTSp']));
      expect(() => sim.setTier(ThermoTier.t1), throwsA(isA<UnsupportedError>()));
      final json = cfg.toJson();
      ColumnConfig mod(void Function(Map<String, Object?>) f) {
        final j = ColumnConfig.fromJson(json).toJson();
        f(j);
        return ColumnConfig.fromJson(j);
      }

      expect(mod((j) => (j['sideDraws'] as List)[0]['drawStage'] = 31).validate(), isNotEmpty);
      expect(mod((j) => (j['sideDraws'] as List)[1]['returnStage'] = 10).validate(), isNotEmpty);
      expect(mod((j) => (j['pumparounds'] as List)[0]['returnStage'] = 17).validate(), isNotEmpty);
      expect(mod((j) => (j['strippers'] as List)[0]['stages'] = 3).validate(), isNotEmpty);
      expect(cfg.validate(), isEmpty);
      final tags = sim.control.instruments.map((i) => i.spec.tag).toSet();
      for (final t in ['TI-341', 'TI-350', 'TI-351', 'TI-353', 'TI-320', 'TI-314', 'FI-314', 'FT-321', 'FT-324', 'LT-301', 'LT-302']) {
        expect(tags.contains(t), isTrue, reason: t);
      }
      final loops = sim.control.loops.map((l) => l.tag).toSet();
      expect(loops, containsAll(['TC-301', 'FC-301', 'LC-301', 'LC-302', 'FC-311', 'FC-312', 'FC-313', 'FC-314', 'TC-320', 'FC-321', 'FC-324']));
      for (final bad in ['TI-201', 'TI-202', 'FT-201', 'PT-201']) {
        expect(tags.contains(bad), isFalse, reason: bad);
      }
    });

    test('lever extremes for 6 h: no NaN, no negative holdup', () {
      final cases = <String, double>{
        'crudeRate:min': 0.009167,
        'crudeRate:max': 0.073611,
        'cot:min': 603.15,
        'cot:max': 663.15,
        'paDuty:min': 0,
        'paDuty:max': 10e6,
        'drawRate.kero:min': 0,
        'drawRate.kero:max': 0.25 * crudeRate0,
        'drawRate.diesel:min': 0,
        'drawRate.diesel:max': 0.30 * crudeRate0,
        'drawRate.ago:min': 0,
        'drawRate.ago:max': 0.15 * crudeRate0,
        'steam.bottom:min': 0,
        'steam.bottom:max': 1.3889,
        'topTSp:min': 363.15,
        'topTSp:max': 433.15,
        'pTop:min': 100000,
        'pTop:max': 250000,
      };
      for (final e in cases.entries) {
        final lever = e.key.split(':').first;
        final sim = crudeSim();
        sim.setLever(lever, e.value);
        sim.advance(6 * 3600);
        final s = sim.snapshot();
        for (final v in [...s.stages.t, ...s.stages.holdup, ...s.stages.x]) {
          expect(v.isFinite, isTrue, reason: e.key);
        }
        for (final h in s.stages.holdup) {
          expect(h, greaterThanOrEqualTo(0), reason: e.key);
        }
        expect(sim.halted, isFalse, reason: e.key);
      }
    });

    test('fault extremes and no alternation after an onset', () {
      for (final f in [(0, 1.0), (1, 1.0), (2, 1.0)]) {
        final sim = crudeSim();
        switch (f.$1) {
          case 0:
            injectF24(sim, 'bottom', 1.0);
          case 1:
            injectF25(sim, 1.0);
          default:
            injectF26(sim, 1.0);
        }
        // sign changes of the stage temperature step between consecutive steps, over 20 steps after the onset
        final prev = List<double>.from(sim.snapshot().stages.t);
        final lastSign = List<int>.filled(prev.length, 0);
        var alternations = 0;
        for (var i = 0; i < 20; i++) {
          sim.step();
          final t = sim.snapshot().stages.t;
          for (var j = 1; j <= 30; j++) {
            final d = t[j] - prev[j];
            final sg = d.abs() < 1e-6 ? 0 : (d > 0 ? 1 : -1);
            if (sg != 0 && lastSign[j] != 0 && sg != lastSign[j]) alternations++;
            if (sg != 0) lastSign[j] = sg;
            prev[j] = t[j];
          }
        }
        expect(alternations, lessThan(60), reason: 'fault ${f.$1}');
        sim.advance(3 * 3600);
        expect(sim.solverHealth.bubbleFallbacks, 0);
        expect(sim.solverHealth.negativeLatent, 0);
        expect(sim.halted, isFalse);
      }
    });
  });

  group('VC-26.1 and VC-21', () {
    test('G16 and H8 parse and validate; vocabulary and magnitudes', () {
      final h8 = Scenarios.byId('H8_crude_drift');
      expect(h8.validate(), isEmpty);
      expect(Scenarios.byId('G16_crude_gaps').validate(), isEmpty);
      expect(h8.candidates.map((c) => c.id), ['steam_loss', 'pa_trip', 'cot_low']);
      expect(ScenarioDef.diagnosisCategories, containsAll(['steamLoss', 'pumparound', 'furnace']));
      final sim = Simulator(Presets.byId('crude'));
      final host = SimulatorHost(sim);
      expect(host.faultMagnitude(h8.candidates[0], 0.85, 1), 'steam −85 % (300 of 2000 kg/h left)');
      expect(host.faultMagnitude(h8.candidates[1], 0.85, 1), 'PA circulation at 15 % (18 m³/h)');
      expect(host.faultMagnitude(h8.candidates[2], 0.8, 1), 'COT −12 K');
    });

    test('H8 starts as a drill and draws a candidate', () {
      final h8 = Scenarios.byId('H8_crude_drift');
      final sim = Simulator(Presets.byId('crude'));
      sim.startScenario(h8, seed: 5);
      expect(sim.snapshot().scenario!.kind, ScenarioKind.drill);
      sim.advance(2000);
      expect(sim.snapshot().view, SimView.plantCalc);
      expect(sim.snapshot().kpis.crude!.cot.isNaN, isTrue);
    });

    test('equation ids on a main stage, a stripper stage, the PA, a product and the overflash', () {
      final sim = crudeSim();
      final snap = sim.snapshot();
      Set<String> ids(ExplainTarget t) => {for (final g in sim.explain(t).groups) for (final l in g.lines) l.id};
      expect(ids(const ExplainStage(10)), containsAll(['eq.steamPartialPressure', 'eq.crudeEnthalpy']));
      expect(ids(const ExplainStripper(1)), containsAll(['eq.steamPartialPressure', 'eq.crudeEnthalpy', 'eq.stripperDraw']));
      expect(ids(const ExplainPumparound()), {'eq.paDuty'});
      expect(ids(const ExplainCondenser()), {'eq.crudeCondenser'});
      expect(ids(const ExplainProduct(2)), {'eq.productTbp', 'eq.daubert', 'eq.gap'});
      expect(ids(const ExplainOverflash()), {'eq.overflash'});
      double val(ExplainTarget t, String id) =>
          sim.explain(t).groups.expand((g) => g.lines).firstWhere((l) => l.id == id).value;
      final k = snap.kpis.crude!;
      expect(val(const ExplainCondenser(), 'eq.crudeCondenser'), closeTo(k.qc, k.qc * 1e-6));
      expect(val(const ExplainPumparound(), 'eq.paDuty'), closeTo(k.qPa, k.qPa * 1e-6));
      expect(val(const ExplainProduct(2), 'eq.daubert'), closeTo(k.d86p5[2], 1e-6));
      expect(val(const ExplainProduct(3), 'eq.gap'), closeTo(k.gapAgoDiesel, 1e-6));
      expect(val(const ExplainOverflash(), 'eq.overflash'), closeTo(k.overflashVolPct, 1e-9));
      expect(math.max(1, 1), 1);
    });

    test('save and restore a crude run', () {
      final sim = crudeSim();
      injectF25(sim, 0.7);
      sim.advance(600);
      final saved = sim.saveState();
      final back = Simulator.restore(saved);
      expect(back.time, sim.time);
      sim.advance(300);
      back.advance(300);
      expect(kpiOf(back).qc, closeTo(kpiOf(sim).qc, kpiOf(sim).qc * 1e-5));
    });
  });
}
