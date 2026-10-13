// M5 validation (validator, engine 9348b7c, re-run at fb33c07; spec 4ee46dd): Tier 3 columns.
// Every [I]/[P] number of VC-28.1–28.3, 28.6, 28.7 and VC-8.10/8.11 that the
// coder's m5_columns_test.dart does not pin, checked against the engine AND
// an independent MESH Newton (reference/tier3_reference.dart: NRTL or
// DePriester K, the §3.3 enthalpies, P held, specs L0 and D). Where a [P]
// row runs outside the default utilities (R 20, L0 300, 0.5 atm) the
// condenser and reboiler are scaled, standing in for the prototype's
// "perfect condenser" (VC-28 preamble).
library;

import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/thermo_reference.dart' as ref;
import 'reference/tier3_reference.dart' as t3;

const _kmolh = 1000 / 3600;
const _atm = 101325.0;
double _k(double v) => v / _kmolh;

Simulator _sim(String id,
    {ThermoTier? tier,
    double? e,
    Map<String, Object?> ov = const {},
    double utilityScale = 1,
    SimOptions options = const SimOptions(seed: 3)}) {
  var cfg = Presets.byId(id);
  if (tier != null) cfg = cfg.copyWith(tier: tier);
  if (e != null) cfg = cfg.copyWith(murphree: e);
  if (utilityScale != 1) {
    cfg = cfg.applyOverrides({
      'condenser.uaClean': cfg.condenser.uaClean * utilityScale,
      'condenser.cwMaxFlow': cfg.condenser.cwMaxFlow * utilityScale,
      'reboiler.uaClean': cfg.reboiler.uaClean * utilityScale,
    });
  }
  if (ov.isNotEmpty) cfg = cfg.applyOverrides(ov);
  return Simulator(cfg, options: options, warmStart: false);
}

SimSnapshot _steady(Simulator s, {bool fastForward = true}) {
  final r = s.runToSteadyState(maxSimSeconds: 600000, fastForward: fastForward);
  expect(r.reached, isTrue, reason: 'steady not reached (${r.simSeconds} s)');
  return s.snapshot();
}

double _tD(SimSnapshot s) => s.stages.t[0] - 273.15;
double _tB(SimSnapshot s) => s.stages.t[s.layout.nTrays + 1] - 273.15;
double _vB(SimSnapshot s) => _k(s.stages.vaporUp[s.layout.nTrays + 1]);
double _v1(SimSnapshot s) => _k(s.stages.vaporUp[1]);

Float64List _xs(SimSnapshot s, int j) {
  final nc = s.stages.nc;
  return Float64List.fromList(s.stages.x.sublist(j * nc, (j + 1) * nc));
}

/// Independent steady energy balance |F h_F + Q_R − Q_C − D h_D − B h_B| / Q_R
/// with the engine's Tier-2 enthalpies at the stream temperatures.
double _energyClosure(Simulator sim) {
  final s = sim.snapshot();
  final th = ThermoFactory.build(sim.config, ThermoTier.t2);
  final n = s.stages.n;
  final f = s.streams[StreamId.feed]!;
  return (f.flow * th.hL(f.temperature, f.composition) +
              s.kpis.qr -
              s.kpis.qc -
              s.kpis.d * th.hL(s.condenser!.tReflux, _xs(s, 0)) -
              s.kpis.b * th.hL(s.stages.t[n - 1], _xs(s, n - 1)))
          .abs() /
      s.kpis.qr;
}

const _ewH = ref.Binary(ref.ethanol, ref.water);
const _acH = ref.Binary(ref.acetone, ref.chloroform);

t3.Tier3Result _ewRef(double l0, {double p = _atm, double d = 10}) {
  var r = t3.solveTier3(t3.Tier3Column(
      k: t3.ewNrtl.k, h: _ewH, nTrays: 40, feedTray: 30, f: 100 * _kmolh,
      z: 0.1, l0: 100 * _kmolh, d: d * _kmolh, p: _atm));
  // continuation in L0, then in P
  for (var l = 100.0 + 20; l <= l0 + 1e-9; l += 20) {
    r = t3.solveTier3(
        t3.Tier3Column(k: t3.ewNrtl.k, h: _ewH, nTrays: 40, feedTray: 30,
            f: 100 * _kmolh, z: 0.1, l0: l * _kmolh, d: d * _kmolh, p: _atm),
        xGuess: r.x, tGuess: r.t);
  }
  if (p != _atm) {
    for (final pp in [0.9, 0.8, 0.7, 0.6, p / _atm]) {
      r = t3.solveTier3(
          t3.Tier3Column(k: t3.ewNrtl.k, h: _ewH, nTrays: 40, feedTray: 30,
              f: 100 * _kmolh, z: 0.1, l0: l0 * _kmolh, d: d * _kmolh, p: pp * _atm),
          xGuess: r.x, tGuess: r.t);
    }
  }
  expect(r.maxResidual, lessThan(1e-8), reason: 'reference converged');
  return r;
}

void main() {
  group('VC-28.1 ew Tier 3, E = 1 (40 trays, feed 30, z 0.10, L0 100, 1206.8 kW)',
      () {
    late Simulator sim;
    late SimSnapshot s;
    late t3.Tier3Result r;
    setUpAll(() {
      sim = _sim('ew', e: 1.0);
      s = _steady(sim);
      r = _ewRef(100);
    });

    test('table: D 10.00, x_D 0.88693, x_B 0.012590, T_D 78.142, T_B 96.496, V1 110.00, V_B 104.37',
        () {
      expect(_k(s.kpis.d), closeTo(10.0, 0.05));
      expect(s.kpis.xD, closeTo(0.88693, 2e-4));
      expect(s.kpis.xB, closeTo(0.012590, 2e-4));
      expect(_tD(s), closeTo(78.142, 0.05));
      expect(_tB(s), closeTo(96.496, 0.05));
      expect(_v1(s), closeTo(110.00, 0.05));
      expect(_vB(s), closeTo(104.37, 0.05));
      expect(s.kpis.pTop, closeTo(_atm, 1));
      expect(s.solverHealth.thermoOutOfRange, isFalse);
    });

    test('x_B 0.012590 [P] vs 0.012564 [I] reconciled: the table duty 1206.8 kW gives D 9.997; D 10.000 needs 1206.84 kW',
        () {
      // OPEN_ITEMS.md "VC-28.1 x_B": the independent MESH solve at D = 10
      expect(r.xB, closeTo(0.012564, 2e-6));
      expect(r.tB - 273.15, closeTo(96.502, 0.002));
      expect(r.qR / 1000, closeTo(1206.84, 0.01));
      // engine at the table duty: D 9.997 (the [P] row)
      expect(_k(s.kpis.d), closeTo(9.997, 0.001));
      expect(s.kpis.xB, closeTo(0.012592, 5e-6));
      // engine at the reference duty: D 10.000 and the [I] x_B
      final m = _sim('ew', e: 1.0);
      m.setLever('reboilerDuty', r.qR);
      final q = _steady(m);
      expect(_k(q.kpis.d), closeTo(10.0, 1e-3));
      expect(q.kpis.xD, closeTo(r.xD, 2e-5));
      expect(q.kpis.xB, closeTo(r.xB, 2e-6));
      expect(_tB(q), closeTo(r.tB - 273.15, 0.002));
      expect(_vB(q), closeTo(_k(r.vB), 0.01));
    });

    test('CW at steady state: (7.3) with the reference Q_C gives 49.9 %, the engine 49.9 % (VC-28.1 says 45.5 %)',
        () {
      const ua = 28830.0, cp = 4180.0, mMax = 41.54;
      final mCw = ua / (2 * cp * (ua * (r.tD - 303.15) / r.qC - 1));
      final cwRef = 100 * mCw / mMax;
      expect(cwRef, closeTo(49.91, 0.05));
      expect(s.condenser!.cwOp, closeTo(cwRef, 0.2));
      expect(s.kpis.qc / 1000, closeTo(r.qC / 1000, 1.0));
    });

    test('dt robustness: the steady state at dt 2 s is steady at dt 0.5 s, and dt 30 s gives the same x_D (1e-6)',
        () {
      final x0 = s.kpis.xD;
      expect(x0, closeTo(0.886926, 5e-6));
      // continue the dt-2 steady state at dt 0.5 for 2 h: nothing moves
      sim.advance(7200);
      expect(sim.snapshot().kpis.xD, closeTo(x0, 1e-9));
      final m30 = _sim('ew',
          e: 1.0, options: const SimOptions(seed: 3, dt: 30, dtFastForward: 30));
      final q = _steady(m30);
      expect(q.kpis.xD, closeTo(x0, 1e-6));
      expect(q.kpis.xB, closeTo(s.kpis.xB, 1e-6));
    });

    test('VC-5.4 on ew Tier 3: independent energy closure ≤ 1e-6 and the KPI agrees', () {
      final e = _energyClosure(sim);
      expect(e, lessThan(1e-6));
      expect(s.kpis.energyResidual, lessThan(1e-6));
    });

    test('the staircase pinches near the top: ≥ 3 consecutive steps advance x by < 0.002 (pinch shading on)',
        () {
      final mt = McCabeThieleBuilder().build(s, sim.thermo);
      expect(mt.pinchZones, isNotEmpty);
      final xs = [for (final c in mt.corners) c.x];
      var run = 0, best = 0, where = -1;
      for (var j = 1; j < xs.length; j++) {
        if ((xs[j - 1] - xs[j]).abs() < 0.002) {
          run++;
          if (run > best) {
            best = run;
            where = j;
          }
        } else {
          run = 0;
        }
      }
      expect(best, greaterThanOrEqualTo(3));
      expect(where, lessThan(30), reason: 'in the rectifying section');
      expect(mt.pinchZones.any((z) => z.hi > 0.8), isTrue,
          reason: 'a shaded zone near x_D');
    });
  });

  group('VC-8.10 / VC-28.1 further rows (the azeotrope wall)', () {
    test('R 20 at D 10: x_D 0.89074 [P]; reference 0.89074; engine at the reference duty', () {
      final r = _ewRef(200);
      expect(r.xD, closeTo(0.89074, 2e-4));
      final m = _sim('ew', e: 1.0, utilityScale: 210 / 110);
      m.setLever('refluxFlow', 200 * _kmolh);
      m.setLever('reboilerDuty', r.qR);
      final q = _steady(m);
      expect(_k(q.kpis.d), closeTo(10.0, 0.05));
      expect(q.kpis.xD, closeTo(0.89074, 2e-4));
      expect(q.kpis.xD, lessThanOrEqualTo(0.8956 + 0.002));
      expect(q.kpis.pTop, closeTo(_atm, 50));
    });
    test('R 40 at D 10: x_D 0.89229 [P] (reference only: L0 400 kmol/h is outside the ew reflux lever)',
        () {
      final r = _ewRef(400);
      expect(r.xD, closeTo(0.89229, 2e-4));
      expect(r.xD, lessThan(0.8956));
      expect(r.qR / 1000, closeTo(4450.5, 1));
    });
    test('Tier 1, α 2.4, L0 100, V_B 110: x_D 0.98306 > 0.95 (the false win)', () {
      final q = _steady(_sim('ew', tier: ThermoTier.t1, e: 1.0));
      expect(q.kpis.xD, closeTo(0.98306, 2e-4));
      expect(_k(q.kpis.d), closeTo(10.0, 1e-3));
    });
    test('0.5 atm(a), R 10: x_D 0.90021, T_D 61.62 °C, Q_R 1247 kW; passes the 1-atm azeotrope', () {
      final r = _ewRef(100, p: 0.5 * _atm);
      expect(r.xD, closeTo(0.90021, 2e-4));
      expect(r.tD - 273.15, closeTo(61.62, 0.05));
      expect(r.qR / 1000, closeTo(1247, 2));
      // 15 °C water so that the default condenser holds 0.5 atm (VC-27.3)
      final m = _sim('ew', e: 1.0, ov: {'condenser.cwInletT': 288.15});
      m.setLever('pTop', 0.5 * _atm);
      m.setLever('reboilerDuty', r.qR);
      final q = _steady(m);
      expect(q.kpis.pTop, closeTo(0.5 * _atm, 1));
      expect(_k(q.kpis.d), closeTo(10.0, 0.05));
      expect(q.kpis.xD, closeTo(0.90021, 2e-4));
      expect(q.kpis.xD, greaterThan(0.8956));
      expect(_tD(q), closeTo(61.62, 0.05));
      final az = TxyData.findAzeotropes(m.thermo, q.kpis.pTop).single;
      expect(q.kpis.xD, lessThan(az.x), reason: 'below the 0.5-atm azeotrope');
    });
  });

  group('VC-28.2 / VC-8.11 ac Tier 3, E = 1 (30 trays, feed 15, z 0.60, D 38)', () {
    test('L0 150: T_D 56.917, T_B 64.551 °C; engine = reference; VC-5.4', () {
      final m = _sim('ac', e: 1.0);
      final q = _steady(m);
      final r = t3.solveTier3(t3.Tier3Column(
          k: t3.acNrtl.k, h: _acH, nTrays: 30, feedTray: 15, f: 100 * _kmolh,
          z: 0.6, l0: 150 * _kmolh, d: 38 * _kmolh, p: _atm));
      expect(_tD(q), closeTo(56.917, 0.05));
      expect(_tB(q), closeTo(64.551, 0.05));
      expect(q.kpis.xD, closeTo(r.xD, 1e-4));
      expect(q.kpis.xB, closeTo(r.xB, 1e-4));
      expect(q.kpis.qr / 1000, closeTo(r.qR / 1000, 2));
      expect(_energyClosure(m), lessThan(1e-6));
    });
    test('L0 300: Q_R 2725.9 kW, x_D 0.99993, x_B 0.35488; x_B stays above the azeotrope throughout',
        () {
      var r = t3.solveTier3(t3.Tier3Column(
          k: t3.acNrtl.k, h: _acH, nTrays: 30, feedTray: 15, f: 100 * _kmolh,
          z: 0.6, l0: 150 * _kmolh, d: 38 * _kmolh, p: _atm));
      for (var l = 160.0; l <= 300; l += 10) {
        r = t3.solveTier3(
            t3.Tier3Column(k: t3.acNrtl.k, h: _acH, nTrays: 30, feedTray: 15,
                f: 100 * _kmolh, z: 0.6, l0: l * _kmolh, d: 38 * _kmolh, p: _atm),
            xGuess: r.x, tGuess: r.t);
      }
      expect(r.maxResidual, lessThan(1e-8));
      expect(r.qR / 1000, closeTo(2725.9, 2));
      expect(r.xD, closeTo(0.99993, 2e-4));
      expect(r.xB, closeTo(0.35488, 2e-4));
      final m = _sim('ac', e: 1.0, utilityScale: 338 / 188);
      _steady(m);
      m.setLever('refluxFlow', 300 * _kmolh);
      m.setLever('reboilerDuty', r.qR);
      final azX = TxyData.findAzeotropes(m.thermo, _atm).single.x;
      var minXb = 1.0;
      for (var t = 0; t < 12 * 3600; t += 60) {
        m.advance(60);
        final xb = m.snapshot().kpis.xB;
        if (xb < minXb) minXb = xb;
      }
      final q = _steady(m);
      expect(_k(q.kpis.d), closeTo(38.0, 0.1));
      expect(q.kpis.xD, closeTo(0.99993, 2e-4));
      expect(q.kpis.xB, closeTo(0.35488, 2e-4));
      expect(minXb, greaterThan(azX), reason: 'x_B never crosses $azX');
      expect(q.kpis.energyResidual, lessThan(1e-6));
    });
  });

  group('VC-28.3 c4 (60 trays, feed 30, z 0.40, 7 bar, E 0.7)', () {
    test('Tier 2 (Lee–Kesler): T_D 51.43, T_B 62.81 °C, V1 320.0, V_B 305.0; = independent MESH', () {
      final q = _steady(_sim('c4'));
      expect(_tD(q), closeTo(51.43, 0.05));
      expect(_tB(q), closeTo(62.81, 0.05));
      expect(_v1(q), closeTo(320.0, 0.1));
      expect(_vB(q), closeTo(305.0, 0.1));
      final r = t3.solveTier3(t3.Tier3Column(
          k: t3.kC4LeeKesler, h: t3.c4Enthalpy, nTrays: 60, feedTray: 30,
          f: 100 * _kmolh, z: 0.4, l0: 280 * _kmolh, d: 40 * _kmolh, p: 7e5,
          e: 0.7));
      expect(r.xD, closeTo(0.92993, 5e-4));
      expect(r.xB, closeTo(0.04670, 5e-4));
      expect(r.qR / 1000, closeTo(1542.6, 2));
      expect(q.kpis.xD, closeTo(r.xD, 2e-4), reason: 'engine D ${_k(q.kpis.d)}');
    });
    test('Tier 3 (DePriester) at L0 280 and D 40: x_D 0.91129, x_B 0.05914, Q_R 1554.0, T_D 50.30, T_B 62.29, V_B 306.9',
        () {
      final r = t3.solveTier3(t3.Tier3Column(
          k: t3.kC4DePriester, h: t3.c4Enthalpy, nTrays: 60, feedTray: 30,
          f: 100 * _kmolh, z: 0.4, l0: 280 * _kmolh, d: 40 * _kmolh, p: 7e5,
          e: 0.7));
      expect(r.xD, closeTo(0.91129, 5e-4));
      expect(r.xB, closeTo(0.05914, 5e-4));
      expect(r.qR / 1000, closeTo(1554.0, 2));
      final m = _sim('c4', tier: ThermoTier.t3);
      m.setLever('reboilerDuty', r.qR);
      final q = _steady(m);
      expect(_k(q.kpis.d), closeTo(40.0, 0.1));
      expect(q.kpis.xD, closeTo(0.91129, 5e-4));
      expect(q.kpis.xB, closeTo(0.05914, 5e-4));
      expect(_tD(q), closeTo(50.30, 0.05));
      expect(_tB(q), closeTo(62.29, 0.05));
      expect(_vB(q), closeTo(306.9, 0.1));
      expect(q.solverHealth.thermoOutOfRange, isFalse);
      expect(q.kpis.energyResidual, lessThan(1e-6));
    });
    test('Tier 3 at the Tier-2 duty 1542.6 kW: T_D 50.03, T_B 62.09 °C, V_B 304.8', () {
      final q = _steady(_sim('c4', tier: ThermoTier.t3));
      expect(_k(q.kpis.d), closeTo(38.12, 0.1));
      expect(_tD(q), closeTo(50.03, 0.05));
      expect(_tB(q), closeTo(62.09, 0.05));
      expect(_vB(q), closeTo(304.8, 0.1));
    });
    test('Tier 1 (α 1.35) starts at the table V_B 320 kmol/h: x_D 0.92631, x_B 0.04913', () {
      // PHYSICS.md 2.3 "Lever ranges": every non-B-T preset runs its flow
      // and duty levers from 0 to 2 × its default (c4 boilup up to 640)
      final m = _sim('c4', tier: ThermoTier.t1);
      expect(_k(m.lever('boilup')), closeTo(320, 1e-9));
      final q = _steady(m);
      expect(_k(q.kpis.d), closeTo(40.0, 1e-3));
      expect(q.kpis.xD, closeTo(0.92631, 2e-4));
      expect(q.kpis.xB, closeTo(0.04913, 2e-4));
    });
    test('T2 → T3 switch: P within ±0.5 kPa of SP throughout, with the Q_C-continuous CW initialisation (≈ 59 %)',
        () {
      final m = _sim('c4');
      _steady(m);
      final cw0 = m.snapshot().condenser!.cwOp;
      m.setTier(ThermoTier.t3);
      final cwAfter = m.snapshot().condenser!.cwOp;
      var peak = 0.0;
      for (var t = 0; t < 2 * 3600; t++) {
        m.advance(1);
        final p = m.snapshot().kpis.pTop;
        expect(p.isNaN, isFalse);
        if ((p - 7e5).abs() > peak) peak = (p - 7e5).abs();
      }
      // record (VALIDATION.md VC-28.3, 2026-10-13)
      print('c4 T2 → T3: CW OP before ${cw0.toStringAsFixed(2)} %, right after the switch '
          '${cwAfter.toStringAsFixed(2)} %, peak |P − SP| ${peak.toStringAsFixed(0)} Pa');
      expect(cwAfter, closeTo(59, 1.5), reason: 'Q_C-continuous CW OP after the switch');
      expect(peak, lessThanOrEqualTo(500), reason: 'peak |P − SP| $peak Pa');
    });
  });

  group('VC-28.7 mw Tier 3 (20 trays, feed 12, z 0.30, L0 60, E 0.7)', () {
    test('at D 30: x_D 0.99461, x_B 0.00231, Q_R 902.4, V_B 79.71, T 64.59 / 99.57 °C (engine at the reference duty)',
        () {
      final r = t3.solveTier3(t3.Tier3Column(
          k: t3.mwNrtl.k, h: ref.mw, nTrays: 20, feedTray: 12, f: 100 * _kmolh,
          z: 0.3, l0: 60 * _kmolh, d: 30 * _kmolh, p: _atm, e: 0.7));
      expect(r.xD, closeTo(0.99461, 5e-4));
      expect(r.xB, closeTo(0.00231, 5e-4));
      expect(r.qR / 1000, closeTo(902.4, 2));
      final m = _sim('mw', tier: ThermoTier.t3);
      m.setLever('reboilerDuty', r.qR);
      final q = _steady(m);
      expect(_k(q.kpis.d), closeTo(30, 0.1));
      expect(q.kpis.xD, closeTo(0.99461, 5e-4));
      expect(q.kpis.xB, closeTo(0.00231, 5e-4));
      expect(_vB(q), closeTo(79.71, 0.1));
      expect(_tD(q), closeTo(64.59, 0.05));
      expect(_tB(q), closeTo(99.57, 0.05));
    });
    test('at the preset duty 890.4 kW: T_D 64.58, T_B 97.25 °C, V_B 78.48; Tier 1 row x_B 0.00407', () {
      final q = _steady(_sim('mw', tier: ThermoTier.t3));
      expect(_tD(q), closeTo(64.58, 0.05));
      expect(_tB(q), closeTo(97.25, 0.05));
      expect(_vB(q), closeTo(78.48, 0.1));
      final t1 = _sim('mw', tier: ThermoTier.t1);
      t1.setLever('refluxFlow', 60 * _kmolh);
      final q1 = _steady(t1);
      expect(q1.kpis.xD, closeTo(0.99050, 5e-4));
      expect(q1.kpis.xB, closeTo(0.00407, 5e-4));
    });
  });

  test('VC-28.6 [P] ew T3 → T1 → T3: T1 x_D 0.98335; back in T3 duty 1202.1 kW, D 9.67, x_D 0.88720',
      () {
    final m = _sim('ew', e: 1.0);
    _steady(m);
    m.setTier(ThermoTier.t1);
    expect(_k(m.lever('boilup')), closeTo(109.997, 0.01));
    final q1 = _steady(m);
    expect(q1.kpis.xD, closeTo(0.98335, 5e-4));
    m.setTier(ThermoTier.t3);
    final duty = m.lever('reboilerDuty') / 1000;
    final q3 = _steady(m);
    printOnFailure('duty $duty kW, D ${_k(q3.kpis.d)}, x_D ${q3.kpis.xD}');
    expect(duty, closeTo(1202.1, 1.0));
    expect(_k(q3.kpis.d), closeTo(9.67, 0.1));
    expect(q3.kpis.xD, closeTo(0.88720, 5e-4));
    expect(q3.kpis.xD, lessThanOrEqualTo(0.8956 + 0.002));
  });

  test('dt 30 s after a large step (ac E 1, condenser ×2, L0 150 → 300, duty ×1.8) reaches the dt-2 steady state; no false "reached"',
      () {
    // PHYSICS.md 12.7 / 13.3: identical steady states at dt 0.5, 2 and 30 s;
    // negativeClamps stays 0 in normal operation
    final res = <double, (bool, double, double, double, int)>{};
    for (final dt in [2.0, 30.0]) {
      final m = _sim('ac',
          e: 1.0,
          ov: {
            'condenser.uaClean': 2 * 83700.0,
            'condenser.cwMaxFlow': 2 * 41.54,
          },
          options: SimOptions(seed: 3, dt: dt, dtFastForward: dt));
      m.runToSteadyState(fastForward: false);
      final c0 = m.snapshot().solverHealth.negativeClamps;
      m.setLever('refluxFlow', 300 * _kmolh);
      m.setLever('reboilerDuty', 1.8 * m.lever('reboilerDuty'));
      final r = m.runToSteadyState(fastForward: false, maxSimSeconds: 300000);
      final q = m.snapshot();
      res[dt] = (r.reached, _k(q.kpis.d), q.kpis.pTop, q.kpis.energyResidual,
          q.solverHealth.negativeClamps - c0);
    }
    printOnFailure('dt 2: ${res[2.0]}; dt 30: ${res[30.0]} (reached, D, P, energy residual, clamps)');
    final a = res[2.0]!, b = res[30.0]!;
    expect(a.$1, isTrue);
    expect(a.$4, lessThan(1e-6));
    if (b.$1) {
      expect(b.$4, lessThan(1e-6), reason: 'a reached state must close the energy balance');
    }
    expect(b.$5, 0, reason: 'negative clamps at dt 30');
    expect(b.$2, closeTo(a.$2, 1e-3), reason: 'D at dt 30 vs dt 2');
    expect(b.$3, closeTo(a.$3, 1), reason: 'P at dt 30 vs dt 2');
  });

  test('lever ranges of the M5 presets: flow and duty levers run 0–2 × the preset default (PHYSICS.md 2.3)',
      () {
    for (final id in ['ew', 'ac', 'c4']) {
      final cfg = Presets.byId(id);
      final m = Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
      final t1 = Simulator(cfg.copyWith(tier: ThermoTier.t1),
          options: const SimOptions(seed: 3), warmStart: false);
      double maxOf(Simulator s, String l) =>
          s.levers.firstWhere((x) => x.id == l).max;
      expect(maxOf(m, 'refluxFlow'),
          closeTo(2 * cfg.initialLevers['refluxFlow']!, 1e-6), reason: '$id L0');
      expect(maxOf(m, 'reboilerDuty'),
          closeTo(2 * cfg.initialLevers['reboilerDuty']!, 1e-3), reason: '$id duty');
      expect(maxOf(t1, 'boilup'),
          closeTo(2 * cfg.initialLevers['boilup']!, 1e-6), reason: '$id V_B');
      expect(maxOf(m, 'feedFlow'),
          closeTo(2 * cfg.initialLevers['feedFlow']!, 1e-6), reason: '$id F');
    }
  });
}
