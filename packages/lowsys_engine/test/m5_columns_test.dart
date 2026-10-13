// M5 engine checks (coder): Tier 3 columns (VC-28.1 to 28.7 key numbers), conservation and energy on ew and ac,
// tier switching, T-x-y and the R_min azeotrope rules (VC-28.4, 28.5), the explain lines (VC-21 for eq.nrtl and
// eq.depriester).
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const kmolh = 1000 / 3600;

Simulator _sim(String id,
    {ThermoTier? tier, double? e, Map<String, Object?> overrides = const {}}) {
  var cfg = Presets.byId(id);
  if (tier != null) cfg = cfg.copyWith(tier: tier);
  if (e != null) cfg = cfg.copyWith(murphree: e);
  if (overrides.isNotEmpty) cfg = cfg.applyOverrides(overrides);
  return Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
}

SimSnapshot _steady(Simulator s) {
  final r = s.runToSteadyState(maxSimSeconds: 400000);
  expect(r.reached, isTrue);
  return s.snapshot();
}

double _kmolh(double v) => v / kmolh;

void main() {
  group('VC-28 steady states', () {
    test(
        '28.1 ew Tier 3, E 1: D 10, x_D 0.88693, x_B 0.01259, T_D 78.142, T_B 96.496, V1 110, V_B 104.37',
        () {
      final s = _steady(_sim('ew', e: 1.0));
      final N = s.layout.nTrays;
      expect(_kmolh(s.kpis.d), closeTo(10.0, 0.05));
      expect(s.kpis.xD, closeTo(0.88693, 2e-4));
      expect(s.kpis.xB, closeTo(0.012590, 2e-4));
      expect(s.stages.t[0] - 273.15, closeTo(78.142, 0.05));
      expect(s.stages.t[N + 1] - 273.15, closeTo(96.496, 0.05));
      expect(_kmolh(s.stages.vaporUp[1]), closeTo(110.0, 0.05));
      expect(_kmolh(s.stages.vaporUp[N + 1]), closeTo(104.37, 0.05));
      expect(s.kpis.energyResidual, lessThan(1e-6));
      expect(s.condenser!.nRelief, 0);
    });

    test(
        '28.2 ac Tier 3, E 1: x_D 0.96153, x_B 0.37842 (never below the azeotrope 0.3334)',
        () {
      final s = _steady(_sim('ac', e: 1.0));
      expect(s.kpis.xD, closeTo(0.96153, 2e-4));
      expect(s.kpis.xB, closeTo(0.37842, 2e-4));
      expect(s.kpis.xB, greaterThan(0.3334));
      expect(s.kpis.energyResidual, lessThan(1e-6));
    });

    test(
        '28.3 c4: Tier 2 numbers, then Tier 3 at the Tier-2 duty (what a T2 to T3 switch converges to)',
        () {
      final sim = _sim('c4');
      var s = _steady(sim);
      expect(s.tier, ThermoTier.t2);
      expect(s.kpis.xD, closeTo(0.92993, 5e-4));
      expect(s.kpis.xB, closeTo(0.04670, 5e-4));
      expect(s.reboiler.qDelivered / 1000, closeTo(1542.6, 2));
      sim.setTier(ThermoTier.t3);
      var pMax = 0.0;
      for (var i = 0; i < 1800; i++) {
        sim.advance(1);
        final p = sim.snapshot().kpis.pTop;
        expect(p.isNaN, isFalse);
        pMax = pMax > (p - 700000).abs() ? pMax : (p - 700000).abs();
      }
      // Q_C-continuous CW valve at the switch (PHYSICS.md 13.5, 2026-10-13): VC-28.3 asks for +-0.5 kPa
      expect(pMax, lessThan(500));
      s = _steady(sim);
      expect(_kmolh(s.kpis.d), closeTo(38.12, 0.1));
      expect(s.kpis.xD, closeTo(0.93266, 5e-4));
      expect(s.kpis.xB, closeTo(0.07192, 5e-4));
      expect(s.kpis.pTop, closeTo(700000, 500));
    });

    test('28.7 mw: Tier 3 at the preset duty 890.4 kW', () {
      final s = _steady(_sim('mw', tier: ThermoTier.t3));
      expect(_kmolh(s.kpis.d), closeTo(29.05, 0.1));
      expect(s.kpis.xD, closeTo(0.99511, 5e-4));
      expect(s.kpis.xB, closeTo(0.0154, 1e-3));
      expect(s.reboiler.qDelivered / 1000, closeTo(890.4, 2));
    });

    test('8.13 mw Tier 1 (alpha 3.5) to Tier 3 by the top-vapour rule', () {
      final sim = _sim('mw', tier: ThermoTier.t1);
      sim.setLever('refluxFlow', 60 * kmolh);
      var s = _steady(sim);
      expect(s.kpis.xD, closeTo(0.99050, 1e-3));
      sim.setTier(ThermoTier.t3);
      for (var i = 0; i < 600; i++) {
        sim.advance(1);
        expect(sim.snapshot().kpis.xD.isNaN, isFalse);
      }
      s = _steady(sim);
      expect(_kmolh(s.kpis.d), closeTo(30, 0.3));
      expect(s.kpis.xD, closeTo(0.9946, 0.0015));
      expect(s.kpis.xB, lessThan(0.004));
      final n = s.layout.nTrays;
      expect(
          s.stages.vaporUp[n + 1] / s.stages.vaporUp[1], closeTo(0.886, 0.005));
    });
  });

  group('tier round trip on an azeotropic column (28.6)', () {
    test('ew T3 -> T1 -> T3: the false win, then back below the azeotrope', () {
      final sim = _sim('ew', e: 1.0);
      _steady(sim);
      sim.setTier(ThermoTier.t1);
      // the 40-tray Tier-1 column has a 5 h slow mode: march 40 h instead of polishing to 1e-11
      sim.advanceFast(40 * 3600);
      var s = sim.snapshot();
      expect(s.kpis.xD, greaterThan(0.98));
      sim.setTier(ThermoTier.t3);
      for (var i = 0; i < 300; i++) {
        sim.advance(1);
        expect(sim.snapshot().kpis.xD.isNaN, isFalse);
      }
      s = _steady(sim);
      expect(s.kpis.xD, lessThanOrEqualTo(0.8956 + 0.002));
      expect(_kmolh(s.kpis.d), inInclusiveRange(9.5, 10.5));
    });
  });

  group('conservation and availability', () {
    for (final id in ['ew', 'ac']) {
      test(
          'VC-5.2 on $id in Tier 3 (component closure 1e-10 over a reflux step)',
          () {
        final sim = _sim(id);
        final nc = sim.config.nc;
        double inv(int i) {
          final s = sim.snapshot();
          var sum = 0.0;
          for (var j = 0; j < s.stages.n; j++) {
            sum += s.stages.holdup[j] * s.stages.x[j * nc + i];
          }
          return sum + s.condenser!.vaporInventory[i];
        }

        final inv0 = [inv(0), inv(1)];
        final fin = [0.0, 0.0], fout = [0.0, 0.0];
        for (var k = 0; k < 2 * 7200; k++) {
          if (k == 3600) {
            sim.setLever('refluxFlow', sim.lever('refluxFlow') * 1.05);
          }
          sim.step();
          final d = sim.debug;
          for (var i = 0; i < nc; i++) {
            fin[i] += d.feedRate[i] * d.dt;
            fout[i] +=
                (d.distillateRate[i] + d.bottomsRate[i] + d.ventRate[i]) * d.dt;
          }
        }
        for (var i = 0; i < nc; i++) {
          final c = ((inv(i) - inv0[i]) - fin[i] + fout[i]).abs() / fin[i];
          expect(c, lessThan(1e-10), reason: 'component $i closure $c');
        }
      });
    }

    test('available tiers per preset', () {
      expect(Presets.byId('bt').availableTiers, {ThermoTier.t1, ThermoTier.t2});
      for (final id in ['mw', 'ew', 'ac', 'c4']) {
        expect(Presets.byId(id).availableTiers.length, 3, reason: id);
      }
      expect(Presets.byId('ac').tier1CannotRepresent, isTrue);
      expect(() => _sim('bt').setTier(ThermoTier.t3), throwsUnsupportedError);
    });
  });

  group('T-x-y and McCabe-Thiele with azeotropes', () {
    test(
        '28.5 T-x-y: one sweep makes both curves, markers equal VC-10.5, ideal flag in Tier 1',
        () {
      final ew = _sim('ew', e: 1.0);
      final th = ew.thermo as Tier2Raoult;
      final t = TxyData.build(th, 101325);
      expect(t.azeotropes.length, 1);
      expect(t.azeotropes.first.x, closeTo(0.8956, 1e-3));
      expect(t.azeotropes.first.t - 273.15, closeTo(78.141, 0.02));
      expect(t.azeotropes.first.maximumBoiling, isFalse);
      expect(t.x.first, 0);
      expect(t.x.last, 1);
      final y = Float64List(2), k = Float64List(2);
      for (var i = 0; i < t.x.length; i += 11) {
        final xs = Float64List.fromList([t.x[i], 1 - t.x[i]]);
        final tb = th.bubbleT(101325, xs, 350, y, k, SolverHealth());
        expect(tb, closeTo(t.tBubble[i], 1e-6));
      }
      final ac = TxyData.build(_sim('ac').thermo, 101325);
      expect(ac.azeotropes.single.maximumBoiling, isTrue);
      expect(ac.azeotropes.single.x, closeTo(0.3335, 2e-3));
      expect(
          TxyData.build(_sim('mw', tier: ThermoTier.t3).thermo, 101325)
              .azeotropes,
          isEmpty);
      final half = TxyData.build(th, 0.5 * 101325);
      expect(half.azeotropes.single.x, closeTo(0.9105, 2e-3));
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        TxyData.build(th, 101325);
      }
      expect(sw.elapsedMilliseconds / 5, lessThan(10));
      final b = TxyBuilder();
      final snap = ew.snapshot();
      final v1 = b.build(snap, th);
      final v2 = b.build(snap, th);
      expect(identical(v1.top, v2.top), isTrue);
      // Tier 1 view: Raoult curves flagged ideal, the stage points are the display T*
      final t1 = _sim('ew', tier: ThermoTier.t1);
      t1.advance(10);
      final s1 = t1.snapshot();
      final v = b.build(s1, t1.tier2Thermo);
      expect(v.top.ideal, isTrue);
      expect(v.top.azeotropes, isEmpty);
      expect(v.top.tBubble.first - 273.15, closeTo(100.018, 0.05));
      expect(v.top.tBubble.last - 273.15, closeTo(78.298, 0.05));
    });

    test(
        '28.4 R_min on ew: blocked at x_D 0.90, tangent pinch at 0.85 (1.873), feed pinch at 0.80 (1.021); ac bottoms banner',
        () {
      final sim = _sim('ew', e: 1.0);
      final snap = sim.snapshot();
      final b = McCabeThieleBuilder();
      final d90 =
          b.build(snap, sim.thermo, showRmin: true, xDTarget: 0.90).rmin!;
      expect(d90.rMin, isNull);
      expect(d90.line, isNull);
      expect(d90.blocked!.side, AzeotropeSide.distillate);
      expect(d90.blocked!.xAzeotrope, closeTo(0.8956, 1e-3));
      final d85 =
          b.build(snap, sim.thermo, showRmin: true, xDTarget: 0.85).rmin!;
      expect(d85.tangentPinch, isTrue);
      expect(d85.pinch!.x, closeTo(0.753, 0.003));
      expect(d85.rMin!, closeTo(1.873, 0.005));
      final d80 =
          b.build(snap, sim.thermo, showRmin: true, xDTarget: 0.80).rmin!;
      expect(d80.tangentPinch, isFalse);
      expect(d80.pinch!.x, closeTo(0.10, 1e-3));
      expect(d80.rMin!, closeTo(1.021, 0.005));
      final ac = _sim('ac', e: 1.0);
      final dac = b
          .build(ac.snapshot(), ac.thermo, showRmin: true, xBTarget: 0.30)
          .rmin!;
      expect(dac.blocked!.side, AzeotropeSide.bottoms);
      expect(dac.blocked!.xAzeotrope, closeTo(0.3335, 2e-3));
    });
  });

  group('explain lines', () {
    for (final (id, line) in [('ew', 'eq.nrtl'), ('c4', 'eq.depriester')]) {
      test('$id tray equilibrium line is $line and equals the snapshot y*', () {
        final sim = _sim(id, tier: ThermoTier.t3);
        sim.advance(30);
        final snap = sim.snapshot();
        final r = sim.explain(const ExplainStage(10));
        final lines = [for (final g in r.groups) ...g.lines];
        final l = lines.firstWhere((l) => l.id == line);
        expect(l.texSymbolic, isNotEmpty);
        expect(l.texSubstituted, isNotEmpty);
        expect((l.value - snap.stages.yStar[10 * snap.stages.nc]).abs(),
            lessThan(1e-12));
      });
    }
  });

  test('G9 and G10 build their Tier-3 configurations', () {
    for (final id in ['G9_azeotrope_wall', 'G10_other_azeotrope']) {
      final cfg = Scenarios.byId(id).buildConfig();
      expect(cfg.tier, ThermoTier.t3);
      expect(cfg.murphree, 1.0);
    }
  });
}
