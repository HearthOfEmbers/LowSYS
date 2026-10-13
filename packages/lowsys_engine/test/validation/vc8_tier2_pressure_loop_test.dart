// VC-8 Tier-2 direction checks (8.1 T2, 8.7, 8.8, 8.9, 8.14), VC-16.6
// pressure loop (incl. 16.6c flash stability) and VC-16.7 cascade.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m4.dart';
import 'reference/validation_expectations_m4.dart';

/// VC-11-like Tier-2 steady state at E 0.7 (the default), duty from the lever.
Simulator _t2Steady({Map<String, Object?> overrides = const {}}) {
  final sim = newSim(btT2(overrides: overrides));
  runSteady(sim);
  return sim;
}

void main() {
  group('VC-8 Tier 2', () {
    test(
        '8.1 (T2): L0 and boilup +10: xD up, xB down, Q_R up; P held ± 0.2 kPa with CW < 95 %',
        () {
      final sim = _t2Steady();
      final p0 = prof(sim);
      final qr0 = p0.s.kpis.qr;
      sim.setLever('refluxFlow', 110 * kmolh);
      sim.setLever('reboilerDuty', qr0 * 160 / 150);
      var pMax = 0.0, cwMax = 0.0;
      advanceSampling(sim, 2 * 3600, 60, (t, s) {
        pMax = math.max(pMax, (s.kpis.pTop - 101325).abs());
        cwMax = math.max(cwMax, loopOf(s, 'PC-101').op);
      });
      final p = runSteady(sim);
      expect(p.xD, greaterThan(p0.xD));
      expect(p.xB, lessThan(p0.xB));
      expect(p.s.kpis.qr, greaterThan(qr0));
      expect(pMax, lessThan(200), reason: 'P within ±0.2 kPa');
      expect(cwMax, lessThan(95), reason: 'CW below 95 % (proto 89.5)');
    });

    test(
        '8.7 P_top 1.013 → 2 bar at fixed L0, D with 10 bar(g) steam: α down, T up ≈ +25 K, separation worse, Q_R slightly down',
        () {
      final sim =
          _t2Steady(overrides: {'reboiler.steamHeaderPressure': 1101325.0});
      final p0 = runSteady(sim);
      final qr0 = p0.s.kpis.qr,
          tB0 = tC(p0.s, 21),
          al0 = p0.yStar(10) / p0.x(10) * (1 - p0.x(10)) / (1 - p0.yStar(10));
      sim.setLever('pTop', 2e5);
      // hold D = 50: trim the duty until D is back (secant on D vs duty)
      var duty = qr0;
      for (var it = 0; it < 6; it++) {
        sim.setLever('reboilerDuty', duty);
        final d = runSteady(sim).dKmolh;
        if ((d - 50).abs() < 0.02) break;
        duty -=
            (d - 50) * kmolh * 32000; // ≈ latent heat per mol of extra vapour
      }
      final p = runSteady(sim);
      final al = p.yStar(10) / p.x(10) * (1 - p.x(10)) / (1 - p.yStar(10));
      expect(p.dKmolh, closeTo(50, 0.05));
      expect(al, lessThan(al0), reason: 'α on the feed tray falls');
      expect(tC(p.s, 21) - tB0, inInclusiveRange(23, 27),
          reason: 'bottom T up (doc +24.3, reference +25.1)');
      expect(p.xD, lessThan(p0.xD));
      expect(p.xB, greaterThan(p0.xB));
      expect(p.s.kpis.qr, lessThan(qr0),
          reason: 'Q_R slightly down (latent heats fall with T)');
      expect(p.s.kpis.qr / qr0, greaterThan(0.93));
      for (var j = 0; j < p.n; j++) {
        expect(p.s.stages.t[j], greaterThan(p0.s.stages.t[j] + 15),
            reason: 'all T up, stage $j');
      }
    });

    test('8.8 subcool the reflux by 20 K: V1 < V2, xD up, Q_C up', () {
      final sim = _t2Steady();
      final p0 = runSteady(sim);
      sim.setLever('refluxSubcooling', 20);
      final p = runSteady(sim);
      expect(p.vaporUp(1), lessThan(p.vaporUp(2)),
          reason: 'extra condensation on tray 1');
      expect(p.xD, greaterThan(p0.xD));
      expect(p.s.kpis.qc, greaterThan(p0.s.kpis.qc));
    });

    test(
        '8.9 switch T1 → T2 at the B-T default steady state: V1 and D continuous, V_B steps to ≈ 141.9, no NaN; new steady xD 0.97838, D 49.96; back to T1 within 5e-4',
        () {
      for (final dt in [0.5, 2.0, 30.0]) {
        final sim =
            newSim(btConfig(), options: SimOptions(dt: dt, dtFastForward: dt));
        final p1 = runSteady(sim, fastForward: false);
        final v1 = p1.vaporUp(1),
            d1 = p1.dKmolh,
            l1 = [for (var j = 1; j <= 20; j++) p1.liquidDown(j)];
        sim.setTier(ThermoTier.t2);
        sim.step();
        final s = sim.snapshot();
        expectTier2Sane(s, where: 'first T2 step dt $dt');
        final pp = Profile(s);
        expect(pp.vaporUp(1), closeTo(v1, 0.005 * v1),
            reason: 'V1 within 0.5 % (dt $dt)');
        expect(pp.dKmolh, closeTo(d1, 0.2), reason: 'D within 0.2 kmol/h');
        expect(toKmolh(pp.vaporUp(21)), inInclusiveRange(141.0, 144.0),
            reason: 'V_B steps −4…−6 %');
        for (var j = 1; j <= 20; j++) {
          expect(pp.liquidDown(j), closeTo(l1[j - 1], 0.15 * l1[j - 1]),
              reason: 'L[$j] step ≤ 15 %');
        }
        expect((s.kpis.pTop - 101325).abs(), lessThan(500),
            reason: 'P within 0.5 kPa');
        final p2 = runSteady(sim, fastForward: false);
        expect(p2.xD, closeTo(vc89.xDNewSteady, 0.0005),
            reason: 'new steady xD (dt $dt)');
        expect(p2.dKmolh, closeTo(vc89.dNewSteady, 0.05));
        sim.setTier(ThermoTier.t1);
        expect(
            toKmolh(sim.lever('boilup')), closeTo(toKmolh(p2.vaporUp(1)), 0.05),
            reason: 'V_B lever = V1 − (1−q)F');
        final p3 = runSteady(sim, fastForward: false);
        expect(p3.xD, closeTo(p1.xD, 5e-4),
            reason: 'back to T1 (proto 0.981411 vs 0.981183)');
      }
    });

    test(
        '8.14 cut CW capacity to 50 % (F09 flow, s 0.5): absorbed with the valve near 100 %; s 0.7: PC saturates, P rises, all T rise',
        () {
      for (final (s, saturates) in [(0.5, false), (0.7, true)]) {
        final sim = _t2Steady();
        final p0 = prof(sim);
        sim.faults.inject(FaultSpec(
            type: FaultType.coolingLoss,
            location: FaultLocation.equipment('condenser'),
            severity: s,
            onset: sim.time,
            ramp: 0,
            params: const {'mode': 'flow'}));
        double? tSat;
        advanceSampling(sim, 1800, 5,
            (t, st) => tSat ??= loopOf(st, 'PC-101').op >= 99.9 ? t : null);
        final p = prof(sim);
        if (saturates) {
          expect(tSat, isNotNull, reason: 'CW to 100 % (proto 72 s at s 0.7)');
          expect(tSat!, lessThanOrEqualTo(120));
          expect(p.s.kpis.pTop, greaterThan(101325 + 5000),
              reason: 'P rises (proto 1.167 bar)');
          for (var j = 0; j < p.n; j++) {
            expect(p.s.stages.t[j], greaterThan(p0.s.stages.t[j] + 0.5),
                reason: 'T[$j] up');
          }
        } else {
          expect((p.s.kpis.pTop - 101325).abs(), lessThan(1000),
              reason: 'P stays at SP at s 0.5');
          expect(loopOf(p.s, 'PC-101').op, greaterThan(85),
              reason: 'valve near 100 %');
        }
      }
    });
  });

  group('VC-16.6 pressure loop (PC-101 Kc 10, Ti 120 s)', () {
    test('condenser design point: CW OP 50 ± 1 %, outlet 44.7 ± 0.3 °C', () {
      final sim = vc11Sim();
      final p = runSteady(sim);
      expect(loopOf(p.s, 'PC-101').op, closeTo(50, 1));
      expect(reading(p.s, 'TI-202').value - 273.15,
          closeTo(condenserDesign.tOut, 0.3));
      expect(
          sim.config.condenser.uaClean / kw, closeTo(condenserDesign.ua, 0.1));
    });
    test(
        'open loop: CW OP 50 → 40 % raises P by 5.8 ± 0.6 kPa with t63 150–230 s',
        () {
      final sim = vc11Sim();
      runSteady(sim);
      sim.control.setMode('PC-101', LoopMode.man);
      sim.control.setOp('PC-101', 40);
      final p0 = sim.snapshot().kpis.pTop;
      double? t63;
      var pEnd = p0;
      advanceSampling(sim, 2400, 5, (t, s) {
        pEnd = s.kpis.pTop;
      });
      final rise = pEnd - p0;
      expect(rise / 1000, closeTo(pc101.openLoopGainKpaPer10Pct, 0.6));
      final sim2 = vc11Sim();
      runSteady(sim2);
      sim2.control.setMode('PC-101', LoopMode.man);
      sim2.control.setOp('PC-101', 40);
      advanceSampling(sim2, 600, 1,
          (t, s) => t63 ??= s.kpis.pTop - p0 >= 0.63 * rise ? t : null);
      expect(t63, isNotNull);
      expect(t63!, inInclusiveRange(150, 230));
    });
    for (final step in [10000.0, -10000.0]) {
      test(
          'SP step ${step > 0 ? '+' : '−'}10 kPa: within ±1 kPa in < 10 min, overshoot ≤ 30 %, decay ratio ≤ 0.3',
          () {
        final sim = vc11Sim();
        runSteady(sim);
        final sp = 101325 + step;
        sim.control.setSp('PC-101', sp);
        double? tIn;
        var overshoot = 0.0;
        final excursions = <double>[];
        advanceSampling(sim, 1800, 5, (t, s) {
          final e = (s.kpis.pTop - sp) * (step > 0 ? 1 : -1);
          if (tIn == null && e.abs() < 1000) tIn = t;
          if (tIn != null && e.abs() >= 1000) tIn = null;
          overshoot = math.max(overshoot, e);
          excursions.add(e);
        });
        expect(tIn, isNotNull);
        expect(tIn!, lessThanOrEqualTo(600),
            reason:
                'proto ${step > 0 ? pc101.settlePlus : pc101.settleMinus} s');
        expect(overshoot / step.abs(), lessThanOrEqualTo(0.30));
        // decay ratio: second positive peak / first
        final peaks = <double>[];
        for (var i = 1; i < excursions.length - 1; i++) {
          if (excursions[i] > excursions[i - 1] &&
              excursions[i] > excursions[i + 1] &&
              excursions[i] > 50) peaks.add(excursions[i]);
        }
        if (peaks.length >= 2)
          expect(peaks[1] / peaks[0], lessThanOrEqualTo(0.3));
      });
    }
    test(
        '16.6c flash stability: CW OP 70 → 100 % (PC in MAN) at dt 0.5, 2, 30: P → 0.966 ± 0.005 bar, V1 ≤ 1.1× its steady value in every step',
        () {
      for (final dt in [0.5, 2.0, 30.0]) {
        final sim = newSim(btT2(overrides: const {'murphree': 1.0}),
            options: SimOptions(dt: dt, dtFastForward: dt));
        sim.setLever('reboilerDuty', 1301.477 * kw);
        sim.setLever('refluxFlow', 100 * kmolh);
        final p0 = runSteady(sim, fastForward: false);
        final v1 = p0.vaporUp(1);
        sim.control.setMode('PC-101', LoopMode.man);
        sim.control.setOp('PC-101', 70);
        sim.advance(600);
        sim.control.setOp('PC-101', 100);
        var v1Max = 0.0;
        advanceSampling(sim, 3600, dt, (t, s) {
          expectTier2Sane(s, where: 'flash dt $dt @ $t');
          v1Max = math.max(v1Max, Profile(s).vaporUp(1));
        });
        expect(sim.snapshot().kpis.pTop / 1e5, closeTo(0.966, 0.005),
            reason: 'dt $dt');
        expect(v1Max / v1, lessThanOrEqualTo(1.1),
            reason: 'dt $dt V1 (proto 1.025–1.029)');
      }
    });
    test('F09 s = 1: P rises until the relief valve lifts (alarm, event)', () {
      final sim = vc11Sim();
      runSteady(sim);
      sim.faults.inject(FaultSpec(
          type: FaultType.coolingLoss,
          location: FaultLocation.equipment('condenser'),
          severity: 1.0,
          onset: sim.time,
          ramp: 0,
          params: const {'mode': 'flow'}));
      final tRelief =
          firstTime(sim, 1200, (s) => hasAlarm(s, 'model.relief'), sample: 5);
      expect(tRelief, isNotNull, reason: 'proto 471 s to 3.5 bar(a)');
      expect(sim.snapshot().kpis.pTop, greaterThan(3.3e5));
    });
  });

  test(
      'VC-16.7 cascade: TC-101 on tray 14 holds TI-114 within ±0.5 K after a +0.1 feed step; FC-103 SP within 20–65 %',
      () {
    final sim = _t2Steady();
    sim.setLever('tc101Enable', 1);
    sim.advance(600);
    final ti0 = reading(sim.snapshot(), 'TI-114').value;
    expect(loopOf(sim.snapshot(), 'TC-101').mode, LoopMode.auto);
    expect(loopOf(sim.snapshot(), 'FC-103').mode, LoopMode.cas);
    sim.faults.inject(FaultSpec(
        type: FaultType.feedComposition,
        location: FaultLocation.feed(0),
        severity: 1.0,
        onset: sim.time,
        ramp: 0,
        params: const {
          'dz': [0.1, -0.1]
        }));
    sim.advance(3600);
    final s = sim.snapshot();
    expect(reading(s, 'TI-114').value, closeTo(ti0, 0.5));
    expect(loopOf(s, 'TC-101').op, inInclusiveRange(20, 65));
    expect(loopOf(s, 'FC-103').sp,
        isNot(closeTo(s.kpis.qr, 0))); // the SP moved; sanity only
  });

  test(
      'VC-16.3(c) enabling TC-101 at a Tier 2 steady state: SP = TI-114 reading, FC-103 SP moves < 0.1 kW in 60 s; disabling holds FC-103 SP',
      () {
    final sim = _t2Steady(); // noise off
    final ti = reading(sim.snapshot(), 'TI-114').value;
    final sp0 = loopOf(sim.snapshot(), 'FC-103').sp;
    sim.setLever('tc101Enable', 1);
    sim.step();
    expect(loopOf(sim.snapshot(), 'TC-101').sp, closeTo(ti, 1e-6),
        reason: 'TC-101 SP tracks the TI-114 reading at the switch');
    var maxMove = (loopOf(sim.snapshot(), 'FC-103').sp - sp0).abs();
    advanceSampling(sim, 60, 0.5, (t, s) {
      maxMove = math.max(maxMove, (loopOf(s, 'FC-103').sp - sp0).abs());
    });
    expect(maxMove, lessThan(0.1 * kw), reason: 'FC-103 SP bump in 60 s');
    // move the cascade so that "holds" is distinguishable from "reverts"
    sim.control.setSp('TC-101', loopOf(sim.snapshot(), 'TC-101').sp + 0.5);
    sim.advance(600);
    final spCas = loopOf(sim.snapshot(), 'FC-103').sp;
    expect((spCas - sp0).abs(), greaterThan(0.1 * kw),
        reason: 'TC-101 moved the duty SP');
    sim.setLever('tc101Enable', 0);
    advanceSampling(sim, 300, 5, (t, s) {
      expect(loopOf(s, 'FC-103').sp, closeTo(spCas, 1e-6 * spCas.abs()),
          reason: 'FC-103 SP held at $t s after disabling');
    });
  });
}
