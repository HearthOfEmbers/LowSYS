// VC-11 Tier-2 steady state, VC-5.4 energy closure, VC-18.3 non-CMO locus,
// VC-27.1 methanol–water, VC-27.2 pressure sweep (against this suite's
// independent MESH reference where the doc is inconsistent), VC-27.3 limits.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m4.dart';
import 'reference/cmo_steady_reference.dart';
import 'reference/thermo_reference.dart' as ref;
import 'reference/tier2_steady_reference.dart';
import 'reference/validation_expectations_m4.dart';

Tier2Result _refBt(
    {double l0 = 100,
    double d = 50,
    int feed = 10,
    double p = ref.atm,
    double e = 1.0}) {
  Tier2Result solve(double dd, List<double> g) => solveTier2(
      Tier2Column(
          sys: ref.bt,
          nTrays: 20,
          feedTray: feed,
          f: 100 * kmolh,
          z: 0.5,
          l0: l0 * kmolh,
          d: dd * kmolh,
          p: p,
          e: e),
      xGuess: g);
  final g = solveNewton(CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: feed,
          f: 100,
          z: 0.5,
          q: 1,
          l0: l0,
          vB: l0 + 50 - 9,
          e: e))
      .x;
  // Continuation in D from D = F z: the CMO guess alone does not converge
  // far from it (at D 55 the Newton stalled on xD 0.9964, xB 1e-12, which
  // breaks the light-component balance, xD ≤ 50/55).
  var r = solve(50, g);
  final steps = ((d - 50).abs() / 0.5).ceil();
  for (var k = 1; k <= steps; k++) {
    r = solve(50 + (d - 50) * k / steps, r.x);
  }
  expect(r.maxResidual, lessThan(1e-8), reason: 'MESH reference converged');
  return r;
}

/// CW inlet temperature at which the default condenser (UA 29.9 kW/K,
/// 41.54 kg/s at 100 %) needs 50 % CW for the reference Q_C at the reference
/// T_D: the §7.2 design rule, standing in for the "perfect condenser" the
/// VC-11 / VC-27.2 references assume (P held exactly). With the default
/// 30 °C CW the condenser cannot hold P for L0 150 (1707 kW > 1391 kW,
/// VC-27.3) or at 0.5 bar(a).
double _cwInletFor(Tier2Result r) {
  const ua = 29900.0, mHalf = 0.5 * 41.54, cp = 4180.0;
  return r.t[0] - r.qC * (1 + ua / (2 * mHalf * cp)) / ua;
}

void main() {
  group('VC-11 B-T Tier 2, E = 1, duty 1301.477 kW, L0 100', () {
    late Simulator sim;
    late Profile p;
    setUpAll(() {
      sim = vc11Sim();
      p = runSteady(sim);
    });

    test('D 50 ± 0.001, xD 0.994946, xB 0.005054, T_D 80.201, T_B 110.386', () {
      expect(p.dKmolh, closeTo(50, 0.001));
      expect(p.xD, closeTo(vc11.xD, 5e-5));
      expect(p.xB, closeTo(vc11.xB, 5e-5));
      expect(tC(p.s, 0), closeTo(vc11.tD, 0.02));
      expect(tC(p.s, 21), closeTo(vc11.tB, 0.02));
    });
    test('Q_C 1281.2 ± 0.2 %, V1 150.000, V_B 141.118, L10 193.183 (± 0.1 %)',
        () {
      expect(p.s.kpis.qc / kw, closeTo(vc11.qC, 0.002 * vc11.qC));
      expect(p.s.kpis.qr / kw, closeTo(vc11.qR, 0.05));
      expect(toKmolh(p.vaporUp(1)), closeTo(vc11.v1, 0.001 * vc11.v1));
      expect(toKmolh(p.vaporUp(21)), closeTo(vc11.vB, 0.001 * vc11.vB));
      expect(toKmolh(p.liquidDown(10)), closeTo(vc11.l10, 0.001 * vc11.l10));
    });
    test('profile rows', () {
      for (final (j, x, t, v, l) in vc11Profile) {
        expect(p.x(j), closeTo(x, 1e-4), reason: 'x[$j]');
        expect(tC(p.s, j), closeTo(t, 0.02), reason: 'T[$j]');
        expect(toKmolh(p.vaporUp(j)), closeTo(v, 0.001 * v), reason: 'V[$j]');
        if (!l.isNaN)
          expect(toKmolh(p.liquidDown(j)), closeTo(l, 0.001 * l),
              reason: 'L[$j]');
      }
    });
    test('whole profile within 1e-4 of the independent MESH reference', () {
      final r = _refBt();
      for (var j = 0; j < p.n; j++) {
        expect(p.x(j), closeTo(r.x[j], 1e-4), reason: 'x[$j]');
        expect(p.s.stages.t[j], closeTo(r.t[j], 0.02), reason: 'T[$j]');
      }
    });
    test('VC-5.4 energy closure ≤ 1e-6 relative at steady state', () {
      expect(energyResidual(sim), lessThanOrEqualTo(1e-6));
    });
    test(
        'VC-18.3 non-CMO: operating locus deviates > 0.002 from the dashed CMO line in the rectifying section',
        () {
      final mt = McCabeThieleBuilder().build(p.s, thermoOf(sim.config));
      double dev(List<Point2> line, Point2 pt) {
        final a = line[0], b = line[1];
        return (pt.y - (a.y + (b.y - a.y) * (pt.x - a.x) / (b.x - a.x))).abs();
      }

      var maxDev = 0.0, maxDevS = 0.0;
      for (var j = 0; j < mt.operatingLocus.length; j++) {
        final pt = mt.operatingLocus[j];
        if (j < 10) {
          maxDev = math.max(maxDev, dev(mt.cmoRectifying, pt));
        } else {
          maxDevS = math.max(maxDevS, dev(mt.cmoStripping, pt));
        }
      }
      expect(maxDev, greaterThan(0.002));
      // [P] max 0.0064 rectifying, 0.0025 stripping
      expect(maxDev, closeTo(0.0064, 0.001), reason: 'rectifying');
      expect(maxDevS, closeTo(0.0025, 0.001), reason: 'stripping');
      expect(mt.equilibriumBottom, isNotNull);
    });
    test(
        'VC-6 Tier 2: same steady state at dt 2 and 30 s (x ≤ 1e-5, T ≤ 0.001 K)',
        () {
      for (final dt in [2.0, 30.0]) {
        final s2 = newSim(btT2(overrides: const {'murphree': 1.0}),
            options: SimOptions(dt: dt, dtFastForward: dt));
        s2.setLever('reboilerDuty', 1301.477 * kw);
        s2.setLever('refluxFlow', 100 * kmolh);
        final q = runSteady(s2, fastForward: false);
        expect(q.xD, closeTo(p.xD, 1e-5), reason: 'dt $dt');
        expect(tC(q.s, 21), closeTo(tC(p.s, 21), 0.001), reason: 'dt $dt T_B');
      }
    });
    test('VC-7.4 (Tier 2): steady from cold within 3–9 h (prototype 6.1 h)',
        () {
      final s2 = vc11Sim();
      final r = s2.runToSteadyState();
      expect(r.reached, isTrue);
      expect(r.simSeconds / 3600, inInclusiveRange(3, 9));
    });
  });

  group('VC-11 further references', () {
    for (final (name, l0, ft, d, xD, xB, qR, qC) in vc11Further) {
      test(name, () {
        final r = _refBt(l0: l0, d: d, feed: ft);
        expect(r.xD, closeTo(xD, 5e-5), reason: 'reference xD vs doc');
        expect(r.xB, closeTo(xB, 5e-5), reason: 'reference xB vs doc');
        expect(r.qR / 1000, closeTo(qR, 0.002 * qR),
            reason: 'reference duty vs doc');
        if (!qC.isNaN) {
          expect(r.qC / 1000, closeTo(qC, 0.002 * qC),
              reason: 'reference Q_C vs doc');
        }
        final sim = vc11Sim(duty: r.qR / 1000, l0: l0, overrides: {
          'murphree': 1.0,
          'feeds[0].stage': ft,
          'condenser.cwInletT': _cwInletFor(r)
        });
        final p = runSteady(sim);
        expect((p.s.kpis.pTop - 101325).abs(), lessThan(1),
            reason: 'P held at 1 atm');
        expect(p.dKmolh, closeTo(d, 0.01), reason: 'D at the reference duty');
        expect(p.xD, closeTo(xD, 5e-5));
        expect(p.xB, closeTo(xB, 5e-5));
        expect(tC(p.s, 21), closeTo(r.t[21] - 273.15, 0.02), reason: 'T_B');
      });
    }
  });

  group(
      'VC-27.1 methanol–water preset (Raoult, E 0.7, feed 12, z 0.3, L0 60, duty 890.4 kW)',
      () {
    late Simulator sim;
    late Profile p;
    setUpAll(() {
      sim = newSim(mwT2());
      sim.setLever('reboilerDuty', vc271.qR * kw);
      sim.setLever('refluxFlow', 60 * kmolh);
      p = runSteady(sim);
    });
    test('D 30.00, xD/xB, T_D/T_B, V1/V_B, L1/L19, Q_C', () {
      expect(p.dKmolh, closeTo(vc271.d, 0.06));
      expect(p.xD, closeTo(vc271.xD, 1e-4));
      expect(p.xB, closeTo(vc271.xB, 1e-4));
      expect(tC(p.s, 0), closeTo(vc271.tD, 0.05));
      expect(tC(p.s, 21), closeTo(vc271.tB, 0.05));
      expect(toKmolh(p.vaporUp(1)), closeTo(vc271.v1, 0.002 * vc271.v1));
      expect(toKmolh(p.vaporUp(21)), closeTo(vc271.vB, 0.002 * vc271.vB));
      expect(toKmolh(p.liquidDown(1)), closeTo(vc271.l1, 0.002 * vc271.l1));
      expect(toKmolh(p.liquidDown(19)), closeTo(vc271.l19, 0.002 * vc271.l19));
      expect(p.s.kpis.qc / kw, closeTo(vc271.qC, 0.002 * vc271.qC));
    });
    test('G7: boilup about 12 % below the top vapour', () {
      expect(1 - p.vaporUp(21) / p.vaporUp(1), closeTo(0.12, 0.01));
    });
    test(
        'utility design values: condenser UA 29.76 kW/K at 50 % CW, reboiler UA 30.65 kW/K',
        () {
      expect(sim.config.condenser.uaClean / kw, closeTo(vc271.uaCond, 0.05));
      expect(sim.config.reboiler.uaClean / kw, closeTo(vc271.uaReb, 0.05));
      expect(loopOf(sim.snapshot(), 'PC-101').op, closeTo(50, 2),
          reason: 'CW valve at design');
    });
    test('Tier 1 on the same column (α 3.5, V_B 90): xD 0.99046, xB 0.00407',
        () {
      final s1 = newSim(Presets.byId('mw')
          .copyWith(tier: ThermoTier.t1, hydraulics: HydraulicsMode.ideal));
      s1.setLever('boilup', 90 * kmolh);
      s1.setLever('refluxFlow', 60 * kmolh);
      final q = runSteady(s1);
      expect(q.xD, closeTo(vc271.tier1Xd, 1e-4));
      expect(q.xB, closeTo(vc271.tier1Xb, 1e-4));
    });
  });

  group(
      'VC-27.2 pressure sweep at L0 100, D 50 (E 0.7): engine vs the independent MESH reference',
      () {
    // Table re-pinned 2026-10-12 (perfect condenser): asserted at the doc's
    // tolerances (Q_R ± 0.3 %, x ± 2e-4, T ± 0.05 K, α ± 0.002) and against
    // this suite's MESH reference. The condenser is set to need 50 % CW at
    // each pressure so PC-101 holds P (the default 30 °C CW cannot at
    // 0.5 bar, VC-27.3).
    for (final (pBar, qRdoc, xDdoc, xBdoc, tDdoc, tBdoc, alDoc) in vc272) {
      test('P = $pBar bar(a)', () {
        final r = _refBt(p: pBar * 1e5, e: 0.7);
        expect(r.qR / kw, closeTo(qRdoc, 0.003 * qRdoc),
            reason: 'reference Q_R vs doc');
        expect(r.xD, closeTo(xDdoc, 2e-4), reason: 'reference xD vs doc');
        expect(r.xB, closeTo(xBdoc, 2e-4), reason: 'reference xB vs doc');
        final sim = newSim(btT2(overrides: {
          'reboiler.steamHeaderPressure': 1101325.0,
          'condenser.cwInletT': _cwInletFor(r)
        }));
        sim.setLever('pTop', pBar * 1e5);
        sim.setLever('reboilerDuty', r.qR);
        sim.setLever('refluxFlow', 100 * kmolh);
        final p = runSteady(sim);
        expect((p.s.kpis.pTop - pBar * 1e5).abs(), lessThan(1),
            reason: 'P held');
        expect(p.dKmolh, closeTo(50, 0.05), reason: 'D at the reference duty');
        expect(p.xD, closeTo(r.xD, 2e-4), reason: 'xD vs reference');
        expect(p.xB, closeTo(r.xB, 2e-4), reason: 'xB vs reference');
        expect(tC(p.s, 0), closeTo(r.t[0] - 273.15, 0.05),
            reason: 'T_D vs reference');
        expect(tC(p.s, 21), closeTo(r.t[21] - 273.15, 0.05),
            reason: 'T_B vs reference');
        expect(p.s.kpis.qr / kw, closeTo(qRdoc, 0.003 * qRdoc),
            reason: 'Q_R vs doc');
        expect(p.xD, closeTo(xDdoc, 2e-4), reason: 'xD vs doc');
        expect(p.xB, closeTo(xBdoc, 2e-4), reason: 'xB vs doc');
        expect(tC(p.s, 0), closeTo(tDdoc, 0.05), reason: 'T_D vs doc');
        expect(tC(p.s, 21), closeTo(tBdoc, 0.05), reason: 'T_B vs doc');
        expect(ref.bt.alpha(p.s.stages.t[10]), closeTo(alDoc, 0.002),
            reason: 'α feed tray vs doc');
      });
    }
    test(
        'VC-8.7 direction: 1 atm → 2 bar at fixed L0, D: α down, all T up (+24…26 K bottom), separation worse, Q_R slightly down',
        () {
      final a = _refBt(p: ref.atm, e: 0.7), b = _refBt(p: 2e5, e: 0.7);
      expect(b.qR, lessThan(a.qR));
      expect(b.t[21] - a.t[21], inInclusiveRange(24, 26));
      expect(b.xD, lessThan(a.xD));
    });
  });

  group('VC-27.3 utility limits', () {
    test(
        'reboiler Q_max = UA_R (T_st − T_B); 3.5 bar(g) cannot serve 2 bar(a), 10 bar(g) can',
        () {
      final tSt35 = ref.waterTsat(3.5e5 + ref.atm),
          tSt10 = ref.waterTsat(10e5 + ref.atm);
      final r2 = _refBt(p: 2e5, e: 0.7);
      final q35 = 57.5 * (tSt35 - r2.t[21]);
      final q10 = 57.5 * (tSt10 - r2.t[21]);
      expect(q35, lessThan(r2.qR / 1000),
          reason: '3.5 bar(g) at 2 bar: $q35 kW < needed');
      expect(q10, greaterThan(r2.qR / 1000));
      final sim = newSim(btT2());
      sim.setLever('pTop', 2e5);
      sim.setLever('reboilerDuty', r2.qR);
      sim.advance(2 * 3600);
      expect(sim.snapshot().kpis.qr / kw, lessThan(0.95 * r2.qR / 1000),
          reason: 'duty-limited at the 3.5 bar(g) header');
      // A clean exchanger short of ΔT shows as FC-103.OPSAT; model.dutyLimited
      // means a degraded exchanger only (PHYSICS.md §8.2, 2026-10-12).
      expect(hasAlarm(sim.snapshot(), 'FC-103.OPSAT'), isTrue);
      expect(hasAlarm(sim.snapshot(), 'model.dutyLimited'), isFalse);
    });
    test(
        'condenser: 0.5 bar(a) needs CW ≤ ≈ 10.7 °C (holds at 5 and 10 °C, not at 11.5 or 15 °C); 0.7 bar(a) holds with CW at 15 °C',
        () {
      // VALIDATION.md VC-27.3 note (corrected 2026-10-12): 27.53 kW/K ×
      // (59.02 − T_cw,in) must cover ≈ 1330 kW at 0.5 bar(a), so the limit
      // is T_cw,in ≈ 10.7 °C; at the 5 °C lever minimum the condenser gives
      // ≈ 1487 kW. Engine e1d4ae4: CW OP 95.3 % at 10.5 °C, saturated with
      // P +0.5 kPa at 11 °C. G8 starts at 0.7 bar(a) with CW at 15 °C.
      for (final (pBar, tCwC, ok) in [
        (0.5, 15.0, false),
        (0.5, 11.5, false),
        (0.5, 10.0, true),
        (0.5, 5.0, true),
        (0.7, 15.0, true)
      ]) {
        final sim = newSim(btT2(overrides: {
          'condenser.cwInletT': tCwC + 273.15,
          'reboiler.steamHeaderPressure': 1101325.0
        }));
        final r = _refBt(p: pBar * 1e5, e: 0.7);
        sim.setLever('reboilerDuty', r.qR);
        sim.setLever('pTop', pBar * 1e5);
        sim.advance(2 * 3600);
        final s = sim.snapshot();
        final op = loopOf(s, 'PC-101').op, dp = s.kpis.pTop - pBar * 1e5;
        final why = '$pBar bar, CW $tCwC °C: P − SP $dp Pa, CW OP $op';
        if (ok) {
          expect(op, lessThan(99.9), reason: 'CW valve has room: $why');
          expect(dp.abs(), lessThan(500), reason: 'P held: $why');
        } else {
          expect(op, greaterThanOrEqualTo(99.9), reason: 'CW saturated: $why');
          expect(dp, greaterThan(200), reason: 'P above SP: $why');
        }
      }
    });
  });
}
