// M4 close-out (engine 1155f40): E50 partial condenser (PHYSICS.md 7.1–7.5,
// 10.7; VC-16.6b), V4 run to steady state with Tier 2 + full hydraulics +
// TC-101, and the Tier-1 display T* (PHYSICS.md 1.3).
//
// The partial-condenser runs use B-T Tier 2, ideal hydraulics and CW 30 %,
// the `condenser.cwOpPartial` default of PHYSICS.md 7.2 (2026-10-13; at 70 %
// the 50 %-design condenser condenses all of V1 and PV-102 shuts, which is
// correct behaviour). [engine] = engine value at 1155f40, a regression pin;
// everything else is checked against the equations. The M4 close-out
// re-checks of OPEN_ITEMS.md (spec 4ee46dd) are at the end of the E50 group.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m4.dart';

const double _pDesign = 101325;
const double _pDown = _pDesign - 30000; // 7.5: P_design − 30 kPa, 0.713 bar(a)
const double _dvMax = 50 * kmolh; // 7.5: the design D, 50 kmol/h

ColumnConfig _partial(double cwOp, {bool full = false}) {
  final cfg = btT2(full: full);
  return cfg.copyWith(
    condenser: CondenserConfig.fromJson(
        {...cfg.condenser.toJson(), 'type': 'partial'}),
    initialLevers: {...cfg.initialLevers, 'cwOP': cwOp},
  );
}

Simulator _steadyPartial(double cwOp,
    {void Function(Simulator)? before, SimOptions options = const SimOptions(seed: 3)}) {
  final sim = newSim(_partial(cwOp), options: options);
  before?.call(sim);
  runSteady(sim);
  return sim;
}

Float64List _xs(SimSnapshot s, int j) {
  final nc = s.stages.nc;
  return Float64List.fromList(s.stages.x.sublist(j * nc, (j + 1) * nc));
}

/// (7.5) with the PV-102 position of the snapshot (steady: mean = end position).
double _dvFormula(SimSnapshot s) {
  final pos = valveOf(s, 'PV-102').position;
  return pos / 100 *
      _dvMax *
      math.sqrt(math.max(s.kpis.pTop - _pDown, 0) / (_pDesign - _pDown));
}

/// Independent column energy balance (W): F h_F + Q_R − Q_C − D h_D − B h_B − D_V H_V,
/// all enthalpies from the Tier-2 model at the stream temperatures.
double _energyBalance(Simulator sim) {
  final s = sim.snapshot();
  final th = thermoOf(sim.config);
  final c = s.condenser!;
  final n = s.stages.n;
  final f = s.streams[StreamId.feed]!;
  final vp = s.streams[StreamId.vaporProduct];
  final hV = vp == null ? 0.0 : th.hV(vp.temperature, vp.composition);
  return f.flow * th.hL(f.temperature, f.composition) +
      s.kpis.qr -
      s.kpis.qc -
      s.kpis.d * th.hL(c.tReflux, _xs(s, 0)) -
      s.kpis.b * th.hL(s.stages.t[n - 1], _xs(s, n - 1)) -
      c.vaporProduct * hV;
}

void main() {
  group('E50 partial condenser (B-T Tier 2, CW 30 %)', () {
    late Simulator sim;
    late SimSnapshot s;
    setUpAll(() {
      sim = _steadyPartial(30);
      s = sim.snapshot();
    });

    test(
        'key numbers: P_down 0.713 bar(a), D_V,max 50 kmol/h, PC-101 → PV-102 (Kc 2, Ti 30 s); D_V follows (7.5)',
        () {
      expect(sim.config.condenser.pDownEff, closeTo(_pDown, 1e-9));
      expect(sim.config.condenser.dvMax, closeTo(_dvMax, 1e-6));
      final c = s.condenser!;
      expect(c.partial, isTrue);
      expect(valveOf(s, 'PV-102').fMax, closeTo(_dvMax, 1e-6));
      final pc = loopOf(s, 'PC-101');
      expect(pc.mode, LoopMode.auto);
      expect(pc.kc, 2.0, reason: 'PHYSICS.md 10.7 (ratified 2026-10-13)');
      expect(pc.ti, 30.0);
      expect(c.cwOp, 30.0, reason: 'CW from its own lever cwOP');
      expect(s.kpis.pTop, closeTo(_pDesign, 0.01), reason: 'PC-101 holds P');
      expect(c.vaporProduct, closeTo(_dvFormula(s), 1e-9 * c.vaporProduct),
          reason: '(7.5) at the steady PV-102 position');
      // [engine] 1155f40
      expect(toKmolh(c.vaporProduct), closeTo(12.621, 0.01));
      expect(toKmolh(s.kpis.d), closeTo(37.178, 0.01));
      expect(toKmolh(s.kpis.b), closeTo(50.200, 0.01));
      expect(valveOf(s, 'PV-102').position, closeTo(25.243, 0.01));
      expect(s.kpis.qc / kw, closeTo(1174.79, 0.1));
      expectTier2Sane(s);
    });

    test(
        'the drum is an equilibrium stage: vapour product y_0 = K x_0 and T = bubble T of x_0 at P(1 − y_I)',
        () {
      final c = s.condenser!;
      final vp = s.streams[StreamId.vaporProduct]!;
      final x0 = _xs(s, 0);
      final y = Float64List(2), k = Float64List(2);
      final tb = thermoOf(sim.config).bubbleT(s.kpis.pTop * (1 - c.inertFraction),
          x0, c.tCond, y, k, SolverHealth());
      expect(c.tCond, closeTo(tb, 1e-6));
      expect(vp.temperature, closeTo(tb, 1e-6));
      expect(vp.composition[0], closeTo(y[0], 1e-9));
      expect(vp.flow, c.vaporProduct);
      // the vapour is richer in benzene than the liquid distillate
      expect(vp.composition[0], greaterThan(s.kpis.xD + 0.01));
      // the condensable inventory has the drum-vapour composition at steady state
      final inv = c.vaporInventory;
      expect(inv[0] / (inv[0] + inv[1]), closeTo(y[0], 1e-9));
      expect(c.tReflux, closeTo(c.tCond - c.subcooling, 1e-9));
      // D_V + N_cond = V1 (no vent, no relief)
      expect(c.vaporProduct + c.nCond, closeTo(s.stages.vaporUp[1], 1e-9 * s.stages.vaporUp[1]));
    });

    test(
        'steady closure: total and per-component mass ≤ 1e-9; energy with D_V H_V ≤ 1e-9 (independent) and Kpis.energyResidual ≤ 1e-6',
        () {
      final f = s.streams[StreamId.feed]!;
      final vp = s.streams[StreamId.vaporProduct]!;
      final dv = s.condenser!.vaporProduct;
      expect(((f.flow - s.kpis.d - dv - s.kpis.b) / f.flow).abs(), lessThan(1e-9));
      for (var i = 0; i < 2; i++) {
        final xd = _xs(s, 0)[i], xb = _xs(s, s.stages.n - 1)[i];
        final fz = f.flow * f.composition[i];
        expect(((fz - s.kpis.d * xd - dv * vp.composition[i] - s.kpis.b * xb) / fz).abs(),
            lessThan(1e-9), reason: 'component $i');
      }
      final e = _energyBalance(sim) / s.kpis.qr;
      expect(e.abs(), lessThan(1e-9), reason: 'independent closure $e');
      expect(s.kpis.energyResidual, lessThanOrEqualTo(1e-6));
      expect(s.kpis.energyResidual, closeTo(e.abs(), 1e-9));
    });

    test(
        'EnergySnapshot (Energy card) residual equals Kpis.energyResidual × Q_R (it must count D_V h_V)',
        () {
      // Coder item E50-a (DEVIATIONS.md "M4 validation", close-out): at 1155f40
      // the snapshot residual is D_V h_V = 135.4 kW (10.4 % of Q_R).
      final e = s.energy!;
      expect(e.residual.abs() / s.kpis.qr,
          closeTo(s.kpis.energyResidual, 1e-6),
          reason: 'EnergySnapshot.residual ${e.residual} W');
    });

    test(
        'VC-5.2 with a partial condenser: exact component conservation incl. n_V,i and the vapour product (1e-10), 3 h from cold with CW and SP steps',
        () {
      final m = newSim(_partial(30), options: const SimOptions(seed: 3));
      final nc = m.config.nc;
      double inv(int i) {
        final q = m.snapshot();
        var sum = 0.0;
        for (var j = 0; j < q.stages.n; j++) {
          sum += q.stages.holdup[j] * q.stages.x[j * nc + i];
        }
        return sum + q.condenser!.vaporInventory[i];
      }

      final inv0 = [inv(0), inv(1)];
      final fin = [0.0, 0.0], fout = [0.0, 0.0];
      var dvInt = 0.0;
      for (var k = 0; k < 3 * 7200; k++) {
        if (k == 7200) m.setLever('cwOP', 35);
        if (k == 14400) m.setLever('pTop', 106325);
        m.step();
        final d = m.debug;
        for (var i = 0; i < nc; i++) {
          fin[i] += d.feedRate[i] * d.dt;
          fout[i] +=
              (d.distillateRate[i] + d.bottomsRate[i] + d.ventRate[i]) * d.dt;
        }
        dvInt += m.snapshot().condenser!.vaporProduct * d.dt;
      }
      expect(dvInt / kmolh / 3600, greaterThan(10),
          reason: 'vapour product flowed (kmol)');
      for (var i = 0; i < nc; i++) {
        final c = ((inv(i) - inv0[i]) - fin[i] + fout[i]).abs() / fin[i];
        expect(c, lessThan(1e-10), reason: 'component $i closure $c');
      }
      expect(m.solverHealth.negativeClamps, 0);
    });

    test(
        'directions: more CW → less D_V, more D; more duty → more D_V; higher P SP → hotter condenser, more Q_C, less D_V',
        () {
      final base = s;
      final cw40 = _steadyPartial(40).snapshot();
      expect(cw40.kpis.pTop, closeTo(_pDesign, 0.01));
      expect(cw40.condenser!.vaporProduct, lessThan(base.condenser!.vaporProduct));
      expect(cw40.kpis.d, greaterThan(base.kpis.d));
      expect(cw40.kpis.qc, greaterThan(base.kpis.qc));
      // [engine] 4.61 kmol/h, D 45.22
      expect(toKmolh(cw40.condenser!.vaporProduct), closeTo(4.606, 0.01));

      final duty = _steadyPartial(30,
          before: (m) => m.setLever('reboilerDuty', 1.05 * 1301477)).snapshot();
      expect(duty.condenser!.vaporProduct, greaterThan(base.condenser!.vaporProduct));
      expect(duty.kpis.qc, greaterThan(base.kpis.qc));
      expect(duty.kpis.xB, lessThan(base.kpis.xB));

      final sp = _steadyPartial(30, before: (m) => m.setLever('pTop', 111325))
          .snapshot();
      expect(sp.kpis.pTop, closeTo(111325, 0.01));
      expect(sp.condenser!.tCond, greaterThan(base.condenser!.tCond + 2));
      expect(sp.kpis.qc, greaterThan(base.kpis.qc));
      expect(sp.condenser!.vaporProduct, lessThan(base.condenser!.vaporProduct));
      expect(sp.condenser!.vaporProduct, closeTo(_dvFormula(sp), 1e-9 * sp.condenser!.vaporProduct),
          reason: '(7.5) at P = 1.113 bar: √ term > 1');
    });

    test(
        'open loop (PC-101 MAN): CW 30 → 35 % lowers P, and D_V follows (7.5) with the √((P − P_down)/30 kPa) term',
        () {
      final m = _steadyPartial(30);
      final op = loopOf(m.snapshot(), 'PC-101').op;
      m.control.setMode('PC-101', LoopMode.man);
      m.setLever('cwOP', 35);
      runSteady(m);
      final q = m.snapshot();
      expect(loopOf(q, 'PC-101').op, closeTo(op, 1e-12));
      expect(q.kpis.pTop, lessThan(_pDesign - 2000));
      expect(q.kpis.pTop, greaterThan(_pDown));
      expect(q.condenser!.vaporProduct, closeTo(_dvFormula(q), 1e-9 * q.condenser!.vaporProduct));
      expect(q.condenser!.vaporProduct, lessThan(s.condenser!.vaporProduct));
      // [engine] P after 1 h 97.44 kPa; at the new steady state
      expect(q.kpis.pTop, inInclusiveRange(90000, 99000));
    });

    test('CW 70 % (above the total-condensation OP ≈ 48.5 %): the condenser takes all of V1, PV-102 shuts and P falls below SP',
        () {
      // PHYSICS.md 7.2 (2026-10-13): correct behaviour, not an error state.
      final q = _steadyPartial(70).snapshot();
      expect(q.condenser!.vaporProduct, lessThan(1e-6));
      expect(valveOf(q, 'PV-102').position, lessThan(1e-6));
      expect(q.kpis.pTop, lessThan(_pDesign - 3000));
    });

    test(
        'VC-16.6b: ±10 kPa SP steps settle within ±1 kPa in 10 min, overshoot ≤ 30 %, decay ratio ≤ 0.3',
        () {
      for (final step in [10000.0, -10000.0]) {
        final m = _steadyPartial(30);
        final p0 = m.snapshot().kpis.pTop;
        m.setLever('pTop', p0 + step);
        final e = <double>[];
        var lastOut = 0.0;
        for (var t = 5; t <= 1800; t += 5) {
          m.advance(5);
          final err = (m.snapshot().kpis.pTop - (p0 + step)) * step.sign;
          e.add(err);
          if (err.abs() > 1000) lastOut = t.toDouble();
        }
        // peaks beyond the SP (err > 0 after the first crossing)
        final peaks = <double>[];
        for (var k = 1; k < e.length - 1; k++) {
          if (e[k] > 0 && e[k] >= e[k - 1] && e[k] > e[k + 1]) peaks.add(e[k]);
        }
        final over = peaks.isEmpty ? 0.0 : peaks.first;
        final decay = peaks.length >= 2 ? peaks[1] / peaks[0] : 0.0;
        expect(lastOut, lessThanOrEqualTo(600), reason: 'step $step settle');
        expect(over, lessThanOrEqualTo(0.3 * step.abs()), reason: 'step $step overshoot');
        expect(decay, lessThanOrEqualTo(0.3), reason: 'step $step decay ratio');
      }
    });

    test('identical steady states at dt 0.5, 2 and 30 s (D_V, x_D, P)', () {
      final ref = <double>[];
      for (final dt in [0.5, 2.0, 30.0]) {
        final m = newSim(_partial(30),
            options: SimOptions(seed: 3, dt: dt, dtFastForward: dt));
        runSteady(m, fastForward: false);
        final q = m.snapshot();
        final v = [q.condenser!.vaporProduct, q.kpis.xD, q.kpis.pTop];
        if (ref.isEmpty) {
          ref.addAll(v);
        } else {
          expect(v[0], closeTo(ref[0], 1e-6 * ref[0]), reason: 'dt $dt D_V');
          expect(v[1], closeTo(ref[1], 1e-6), reason: 'dt $dt xD');
          expect(v[2], closeTo(ref[2], 0.01), reason: 'dt $dt P');
        }
      }
    });

    // ---- M4 close-out re-checks (OPEN_ITEMS.md "For validator", spec 4ee46dd)

    test('a partial condenser starts at condenser.cwOpPartial = 30 %, from the preset and from the condenserType switch',
        () {
      final cfg = btT2().applyOverrides({'condenser.type': 'partial'});
      final m = newSim(cfg, options: const SimOptions(seed: 3));
      expect(m.lever('cwOP'), closeTo(30, 1e-9), reason: 'preset load');
      final t = newSim(btT2(), options: const SimOptions(seed: 3));
      t.advance(10);
      t.setLever('condenserType', 1);
      expect(t.lever('cwOP'), closeTo(30, 1e-9), reason: 'condenserType switch');
    });

    test('balanceResidual counts the vapour product: |F z − D x_D − D_V y_V − B x_B| / F z ≤ 1e-9 at steady state',
        () {
      expect(s.kpis.balanceResidual, lessThanOrEqualTo(1e-9));
    });

    test('cross-checks with a partial condenser: C1, C2, C3b n/a; C3a and C5 (drum) ok; C4 on PV-101 (the CW valve), no C4 row for PV-102',
        () {
      // the default 30-min window: C2 needs ≥ 1800 s, which the steady run gives
      final m = _steadyPartial(30);
      m.advance(3600);
      final q = m.snapshot();
      final ids = [for (final c in q.crossChecks) '${c.id} ${c.status.name}'];
      for (final id in ['C1', 'C2', 'C3b']) {
        expect(checkOf(q, id)?.status, CheckStatus.notAvailable, reason: '$id; checks $ids');
      }
      for (final id in ['C3a', 'C5:drum']) {
        expect(checkOf(q, id)?.status, CheckStatus.ok, reason: '$id; checks $ids');
      }
      expect(checkOf(q, 'C4:PV-101')?.status, CheckStatus.ok, reason: 'checks $ids');
      expect(checkOf(q, 'C4:PV-102'), isNull, reason: 'checks $ids');
    });

    test('T1 → T2 switch: PC-101 starts at the 50 % design OP (PHYSICS.md 13.5, 2026-10-13)', () {
      final m = newSim(btConfig(), options: const SimOptions(seed: 3), warmStart: true);
      m.advance(60);
      m.setTier(ThermoTier.t2);
      final pc = loopOf(m.snapshot(), 'PC-101');
      expect(pc.op, closeTo(50, 1e-9));
      expect(pc.mode, LoopMode.auto);
    });
  });

  group('V4: run to steady state, Tier 2 + full hydraulics + TC-101', () {
    /// Runs one more hour after "reached" and returns the largest changes.
    ({double res, double dx, double dm, double dT, double dP, double dOp})
        hold(Simulator m) {
      final s0 = m.snapshot();
      final ops0 = {for (final l in s0.loops) l.tag: l.op};
      var res = 0.0;
      for (var k = 0; k < 60; k++) {
        m.advance(60);
        res = math.max(res, m.steadyResidual);
      }
      final s1 = m.snapshot();
      var dx = 0.0, dm = 0.0, dT = 0.0, dOp = 0.0;
      for (var i = 0; i < s0.stages.x.length; i++) {
        dx = math.max(dx, (s1.stages.x[i] - s0.stages.x[i]).abs());
      }
      for (var j = 0; j < s0.stages.n; j++) {
        dm = math.max(dm,
            (s1.stages.holdup[j] - s0.stages.holdup[j]).abs() / s0.stages.holdup[j]);
        dT = math.max(dT, (s1.stages.t[j] - s0.stages.t[j]).abs());
      }
      for (final l in s1.loops) {
        dOp = math.max(dOp, (l.op - ops0[l.tag]!).abs());
      }
      return (
        res: res,
        dx: dx,
        dm: dm,
        dT: dT,
        dP: (s1.kpis.pTop - s0.kpis.pTop).abs(),
        dOp: dOp
      );
    }

    void expectTrulySteady(Simulator m, String where) {
      final h = hold(m);
      expect(h.res, lessThanOrEqualTo(1e-11), reason: '$where residual for 1 h');
      expect(h.dx, lessThan(1e-10), reason: '$where x');
      expect(h.dm, lessThan(1e-9), reason: '$where holdup (rel)');
      expect(h.dT, lessThan(1e-8), reason: '$where T (K)');
      expect(h.dP, lessThan(1e-6), reason: '$where P_top (Pa)');
      expect(h.dOp, lessThan(1e-8), reason: '$where every loop OP incl. PC-101/TC-101 (%)');
      final q = m.snapshot();
      final tc = loopOf(q, 'TC-101');
      expect(tc.mode, LoopMode.auto, reason: where);
      expect(loopOf(q, 'FC-103').mode, LoopMode.cas, reason: where);
      expect(tc.pv, closeTo(tc.sp, 1e-6), reason: '$where TC-101 at SP');
      expect(q.kpis.pTop, closeTo(loopOf(q, 'PC-101').sp, 1e-3), reason: where);
      expect(m.solverHealth.pressureFallbacks, 0, reason: where);
    }

    test(
        'cold start, TC-101 on from t = 0 (seed 9): reached within 1.25 × the TC-101-off time (≈ 7 h), then holds for 1 h',
        () {
      final off = newSim(btT2(full: true), options: const SimOptions(seed: 9));
      final rOff = off.runToSteadyState();
      expect(rOff.reached, isTrue);

      final m = newSim(btT2(full: true), options: const SimOptions(seed: 9));
      m.setLever('tc101Enable', 1);
      final r = m.runToSteadyState();
      expect(r.reached, isTrue, reason: 'residual ${r.residual}');
      expect(r.residual, lessThanOrEqualTo(1e-11));
      // [engine] declared 15 540 s, polished 25 800 s (TC-101 off: 14 820 / 25 680 s)
      expect(r.totalSimSeconds, lessThanOrEqualTo(1.25 * rOff.totalSimSeconds));
      expect(r.totalSimSeconds, lessThanOrEqualTo(36000));
      expectTrulySteady(m, 'cold TC-101');
    });

    test(
        'warm start, TC-101 enabled, then feed z 0.50 → 0.55: TC-101 moves FC-103 and the run reaches a true steady state',
        () {
      final m = Simulator(btT2(full: true), options: const SimOptions(seed: 9));
      m.setLever('tc101Enable', 1);
      m.advance(120);
      final q0 = m.snapshot();
      final tsp = loopOf(q0, 'TC-101').sp;
      final duty0 = loopOf(q0, 'FC-103').sp;
      m.setLever('feedZ.benzene', 0.55);
      final r = m.runToSteadyState();
      expect(r.reached, isTrue, reason: 'residual ${r.residual}');
      // [engine] 24 180 s
      expect(r.totalSimSeconds, lessThanOrEqualTo(36000));
      final q = m.snapshot();
      expect(loopOf(q, 'TC-101').sp, closeTo(tsp, 1e-9), reason: 'SP held');
      expect(loopOf(q, 'FC-103').sp, greaterThan(duty0 + 10 * kw),
          reason: 'more light feed → TC-101 raises the duty');
      expectTrulySteady(m, 'warm TC-101 + feed z');
    });

    test(
        'VC-5.4 in full hydraulics with the (7.4) entrainment term e_1 (h_1 − h_0): closure ≤ 1e-6 at design and at +20 % load',
        () {
      // PHYSICS.md 7.2 (2026-10-13): only the new form is asserted. At engine
      // 1155f40/9348b7c the residual was exactly e_1 (h_1 − h_0): 6.8e-6
      // (design) and 1.9e-5 (+20 %).
      for (final load in [1.0, 1.2]) {
        // +20 %: L0 and duty × 1.2 with 20 °C water so that PC-101 still holds P
        final m = newSim(
            btT2(full: true, overrides: load == 1.0 ? const {} : const {'condenser.cwInletT': 293.15}),
            options: const SimOptions(seed: 9));
        m.setLever('refluxFlow', m.lever('refluxFlow') * load);
        m.setLever('reboilerDuty', m.lever('reboilerDuty') * load);
        runSteady(m);
        final s = m.snapshot();
        expect(s.stages.entrain[1], greaterThan(0), reason: 'full hydraulics entrains');
        final res = _energyBalance(m).abs() / s.kpis.qr;
        expect(res, lessThanOrEqualTo(1e-6), reason: 'load $load: independent closure $res');
        expect(s.kpis.energyResidual, lessThanOrEqualTo(1e-6), reason: 'load $load: KPI');
      }
    });
  });

  group('Display T* (Tier 1, PHYSICS.md 1.3)', () {
    test(
        'Tier 1: idealT, every T_j is the Raoult bubble point of x_j at p_j (1e-6 K); Tier 2: idealT false',
        () {
      final m = newSim(btConfig());
      runSteady(m);
      final s = m.snapshot();
      expect(s.stages.idealT, isTrue);
      final th = ThermoFactory.build(m.config, ThermoTier.t2);
      final y = Float64List(2), k = Float64List(2);
      for (var j = 0; j < s.stages.n; j++) {
        final tb = th.bubbleT(s.stages.p[j], _xs(s, j), 360, y, k, SolverHealth());
        expect(s.stages.t[j], closeTo(tb, 1e-6), reason: 'stage $j');
      }
      // drum ≈ 80 °C, sump ≈ 110 °C at the B-T default
      expect(s.stages.t[0] - 273.15, inInclusiveRange(79, 82));
      expect(s.stages.t[s.stages.n - 1] - 273.15, inInclusiveRange(105, 112));
      final m2 = newSim(btT2());
      expect(m2.snapshot().stages.idealT, isFalse);
    });

    test('T* is display-only: reading snapshots every step leaves the Tier-1 state bit-identical',
        () {
      final a = newSim(btConfig()), b = newSim(btConfig());
      a.setLever('refluxFlow', 110 * kmolh);
      b.setLever('refluxFlow', 110 * kmolh);
      for (var k = 0; k < 1200; k++) {
        a.step();
        b.step();
        a.snapshot();
      }
      // only the snapshot counter may differ
      String state(Simulator m) =>
          jsonEncode(Map<String, Object?>.of(m.saveState())..remove('serial'));
      expect(state(a), state(b));
    });
  });
}
