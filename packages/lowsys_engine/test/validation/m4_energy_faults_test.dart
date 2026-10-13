// VC-5.2 component conservation with the overhead vapour inventory,
// VC-5.4 energy closure, the VC-27.4 severity floors and the H2/H4 fault
// symptoms of F08–F15 (noise off, Tier 2).
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m4.dart';
import 'reference/thermo_reference.dart' as ref;
import 'reference/validation_expectations_m4.dart';

Simulator _steady({Map<String, Object?> overrides = const {}}) {
  final sim = newSim(btT2(overrides: overrides));
  runSteady(sim);
  return sim;
}

FaultId _equip(Simulator sim, FaultType type, String id,
        {double severity = 1.0,
        double ramp = 0,
        Map<String, Object?> params = const {}}) =>
    sim.faults.inject(FaultSpec(
        type: type,
        location: FaultLocation.equipment(id),
        severity: severity,
        onset: sim.time,
        ramp: ramp,
        params: params));

void main() {
  group('VC-5 Tier 2', () {
    test(
        '5.2 exact component conservation including the overhead inventory n_V,i (1e-10) over 4 h with a reflux step',
        () {
      final sim = newSim(btT2());
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
      for (var k = 0; k < 4 * 7200; k++) {
        if (k == 7200) sim.setLever('refluxFlow', 110 * kmolh);
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
    test(
        '5.4 energy closure ≤ 1e-6 at the VC-11 steady state and at the mw preset',
        () {
      expect(energyResidual(vc11Sim()..runToSteadyState()),
          lessThanOrEqualTo(1e-6));
      final m = newSim(mwT2());
      m.setLever('reboilerDuty', vc271.qR * kw);
      m.setLever('refluxFlow', 60 * kmolh);
      runSteady(m);
      expect(energyResidual(m), lessThanOrEqualTo(1e-6));
    });
  });

  group('VC-27.4 severity floors and F11/F15 numbers', () {
    test(
        'F15 s 0.5: header 3.16 bar(a), T_st 135.4 °C, Q_max 1437 kW (no limit); limit starts at s ≈ 0.58; s 0.7 limits',
        () {
      // The §11 Q_max figures are UA_R (T_st − 110.4 °C): the VC-11 design
      // point (E = 1, duty 1301.5 kW) at which §8.2 sizes UA_R, so the test
      // runs there (the E = 0.7 default has T_B 109.6 °C: Q_max 1490 kW at
      // s 0.5). Q_max is read in the first step after the fault (start-of-
      // step T_B); once the duty is limited T_B falls and Q_max recovers
      // (self-consistent), so "limited" is judged at onset: Q_max < SP.
      for (final (s, pBar, tSt, qMax) in [
        ...f15,
        (0.55, double.nan, double.nan, double.nan),
        (0.6, double.nan, double.nan, double.nan)
      ]) {
        final sim = vc11Sim()..runToSteadyState();
        final tB0 = sim.snapshot().reboiler.tSump;
        final sp = loopOf(sim.snapshot(), 'FC-103').sp;
        expect(tB0 - 273.15, closeTo(110.386, 0.02));
        _equip(sim, FaultType.steamHeaderLoss, 'reboiler', severity: s);
        sim.step();
        var st = sim.snapshot();
        final pHdr = (3.5e5 + 101325) * (1 - 0.6 * s);
        expect(st.reboiler.steamP, closeTo(pHdr, 1), reason: 's=$s P_hdr');
        expect(st.reboiler.qMax,
            closeTo(st.reboiler.uaEff * (st.reboiler.steamT - tB0),
                1e-4 * st.reboiler.qMax),
            reason: 's=$s Q_max = UA_R (T_st − T_B)');
        if (!pBar.isNaN) {
          expect(st.reboiler.steamP / 1e5, closeTo(pBar, 0.01),
              reason: 's=$s header bar(a)');
          expect(st.reboiler.steamT - 273.15, closeTo(tSt, 0.1),
              reason: 's=$s T_st');
          expect(st.reboiler.qMax / kw, closeTo(qMax, 0.01 * qMax),
              reason: 's=$s Q_max');
        }
        expect(st.reboiler.qMax < sp, s >= f15LimitS,
            reason: 's=$s limited at onset? Q_max ${st.reboiler.qMax / kw} kW');
        sim.advance(300);
        st = sim.snapshot();
        expect(reading(st, 'PT-201').value, closeTo(pHdr - 101325, 2000),
            reason: 's=$s PT-201 header gauge pressure');
        if (s >= f15LimitS) {
          expect(loopOf(st, 'FC-103').op, greaterThanOrEqualTo(99.9),
              reason: 's=$s steam valve wide open');
          expect(st.kpis.qr, lessThan(sp - 2 * kw), reason: 's=$s duty < SP');
        } else {
          expect(st.kpis.qr, closeTo(sp, 0.005 * sp),
              reason: 's=$s FC-103 recovers the SP');
        }
      }
    });
    test(
        'H2 / F11 non-condensables s 1 (transient): CW valve rises with P at SP, saturates within 30 min, then P rises (1 h ≈ 139 kPa, y_I ≈ 0.072); subcooling up ≥ 3 K within 1 h (≈ 4.3 K); vent restores P within 10 min',
        () {
      final sim = _steady();
      final s0 = sim.snapshot();
      final nTot0 = s0.condenser!.vaporMoles;
      final op0 = loopOf(s0, 'PC-101').op;
      expect(nTot0, closeTo(f11.overheadMol, 1.5),
          reason: 'overhead at 1 atm (ideal gas, 3 m³)');
      _equip(sim, FaultType.nonCondensables, 'condenser');
      // PHYSICS.md §11 F11 / VALIDATION.md H2 (restated 2026-10-12): PC-101
      // first holds P by opening the CW valve; blanketing (f = 3 y_I) and the
      // lower condensable partial pressure use up the +7.9 % reserve of the
      // 50 % design at y_I ≈ 0.02, so the valve saturates (engine ≈ 17 min)
      // and P then rises.
      double? tSat, pAtSat, tSub3;
      var dpBeforeSat = 0.0;
      advanceSampling(sim, 3600, 5, (t, s) {
        final op = loopOf(s, 'PC-101').op;
        if (tSat == null) {
          dpBeforeSat = math.max(dpBeforeSat, (s.kpis.pTop - 101325).abs());
        }
        if (tSat == null && op >= 99.9) {
          tSat = t;
          pAtSat = s.kpis.pTop;
        }
        tSub3 ??= s.condenser!.subcooling >= f11.subcoolMinH2 ? t : null;
      });
      final s = sim.snapshot();
      final c = s.condenser!;
      final yI = c.inertFraction;
      final nI = c.vaporMoles * yI / (1 - yI);
      expect(nI, closeTo(f11.inertPerHour, 0.1),
          reason: 'ε_I F t = 1e-4 × 100 kmol/h × 1 h');
      expect(tSat, isNotNull, reason: 'CW valve saturates');
      expect(tSat!, lessThanOrEqualTo(f11.tSatMax),
          reason: 'valve saturates at ${tSat! / 60} min (P ${pAtSat! / 1000} kPa)');
      expect(tSat!, greaterThan(300), reason: 'the valve rises first (OP0 $op0)');
      // "P_top at SP" while the valve rises: PC-101 follows the growing load
      // with a PI ramp lag (engine 0.1 → 2.1 kPa above SP over the 17 min),
      // judged on the VC-8.1 Tier-2 transient bound of 5 kPa (wording item in
      // OPEN_ITEMS.md).
      expect(dpBeforeSat, lessThanOrEqualTo(5000),
          reason: 'P near SP while the valve rises: max |P − SP| $dpBeforeSat Pa');
      expect(s.kpis.pTop, closeTo(f11.pTop1h, 5000),
          reason: 'P rises once the valve is saturated (engine 139 kPa)');
      // the model relations behind the §11 1-h numbers
      expect((nI + c.vaporMoles) * 8.314462618 * c.tCond / 3.0,
          closeTo(s.kpis.pTop, 0.002 * s.kpis.pTop),
          reason: 'P = (n_V + n_I) R T_0 / V_ovh');
      expect(yI, closeTo(f11.yI1h, 0.005));
      expect(c.subcooling, closeTo(20 * 3 * yI, 0.01),
          reason: 'ΔT_sub = 20 f_blanket');
      expect(c.subcooling, closeTo(f11.subcool1h, 0.3));
      expect(c.tCond - reading(s, 'TI-100').value, closeTo(c.subcooling, 0.3),
          reason: 'TI-100 shows the subcooled reflux');
      expect(tSub3, isNotNull,
          reason: 'H2: subcooling up ≥ ${f11.subcoolMinH2} K within 1 h');
      sim.setLever('inertVent', 100);
      final tBack = firstTime(
          sim, 600, (st) => (st.kpis.pTop - 101325).abs() < 500,
          sample: 5);
      expect(tBack, isNotNull);
    });
  });

  group(
      'H2 / H4 fault symptoms (Tier 2, noise off, onset 600 s, mid-range severity)',
      () {
    test(
        'F09 CW temperature +15 K (s 1): P_top up, CW valve to 100 %, subcooling down',
        () {
      final sim = _steady();
      final sub0 = tC(sim.snapshot(), 0) -
          (reading(sim.snapshot(), 'TI-100').value - 273.15);
      _equip(sim, FaultType.coolingLoss, 'condenser',
          params: const {'mode': 'temperature'});
      sim.advance(1800);
      final s = sim.snapshot();
      expect(loopOf(s, 'PC-101').op, closeTo(100, 1));
      expect(s.kpis.pTop, greaterThan(101325 + 2000));
      expect(tC(s, 0) - (reading(s, 'TI-100').value - 273.15),
          lessThanOrEqualTo(sub0 + 0.1));
    });
    test(
        'F10 condenser fouling (ramp 6 h): P creeps up over ≥ 30 min, CW valve creeps up, subcooling down',
        () {
      final sim = _steady();
      _equip(sim, FaultType.condenserFouling, 'condenser',
          severity: 0.85, ramp: 6 * 3600);
      final ops = <double>[], ps = <double>[];
      advanceSampling(sim, 2 * 3600, 600, (t, s) {
        ops.add(loopOf(s, 'PC-101').op);
        ps.add(s.kpis.pTop);
      });
      for (var i = 1; i < ops.length; i++) {
        expect(ops[i], greaterThanOrEqualTo(ops[i - 1] - 0.5),
            reason: 'CW valve creeps up');
      }
      expect(ops.last - ops.first, greaterThan(5));
      expect(ps.last, greaterThan(ps.first),
          reason: 'P creeps once the valve saturates or nearly');
    });
    test(
        'F12 partial reflux loss (s 0.8): reflux at the cap 0.2 x F_max 300 = 60 kmol/h, below SP with FC-102 at 100 %, top T up, drum level up',
        () {
      final sim = _steady();
      final t1 = tC(sim.snapshot(), 1);
      // s 0.8 (spec ruling M7 close-out item 3): the cap is (1 - s) F_max of FV-102; B-T's F_max is 300 kmol/h (3 x the
      // design reflux), so s 0.6 leaves the cap (120) above the design reflux and gives no symptom
      _equip(sim, FaultType.refluxPumpTrip, 'reflux', severity: 0.8);
      sim.advance(1800);
      final s = sim.snapshot();
      expect(reading(s, 'FT-102').value / kmolh, closeTo(60, 1.2), reason: 'at the cap 0.2 x 300');
      expect(loopOf(s, 'FC-102').op, closeTo(100, 0.5));
      expect(reading(s, 'FT-102').value,
          lessThan(loopOf(s, 'FC-102').sp - 5 * kmolh));
      expect(tC(s, 1), greaterThan(t1 + 0.5));
      expect(s.kpis.drumLevelPct, greaterThan(55));
    });
    test(
        'F13 reboiler fouling (ramp 6 h): steam valve rises over ≥ 30 min then saturates; duty below SP after; model.dutyLimited raised',
        () {
      final sim = _steady();
      _equip(sim, FaultType.reboilerFouling, 'reboiler',
          severity: 1.0, ramp: 6 * 3600);
      final ops = <double>[];
      double? tSat;
      advanceSampling(sim, 6 * 3600, 300, (t, s) {
        ops.add(loopOf(s, 'FC-103').op);
        tSat ??= loopOf(s, 'FC-103').op >= 99.9 ? t : null;
      });
      expect(tSat, isNotNull);
      expect(tSat!, greaterThanOrEqualTo(1800), reason: 'rises over ≥ 30 min');
      final s = sim.snapshot();
      expect(s.kpis.qr, lessThan(loopOf(s, 'FC-103').sp - 20 * kw));
      // PHYSICS.md §8.2 (2026-10-12): the flag means a degraded exchanger
      expect(hasAlarm(s, 'model.dutyLimited'), isTrue,
          reason: 'F13 raises model.dutyLimited');
    });
    test(
        'F14 condensate backup (s 0.75): duty below SP within 5 min with the steam valve at 100 %; model.dutyLimited raised',
        () {
      final sim = _steady();
      _equip(sim, FaultType.condensateBackup, 'reboiler',
          severity: 0.75, ramp: 60);
      final tHit = firstTime(
          sim,
          600,
          (s) =>
              loopOf(s, 'FC-103').op >= 99.9 &&
              s.kpis.qr < loopOf(s, 'FC-103').sp - 20 * kw,
          sample: 5);
      expect(tHit, isNotNull);
      expect(tHit!, lessThanOrEqualTo(300));
      // the alarm needs the condition held 60 s (PHYSICS.md §8.2)
      final tFlag = firstTime(
          sim, 300, (s) => hasAlarm(s, 'model.dutyLimited'),
          sample: 5);
      expect(tFlag, isNotNull, reason: 'F14 raises model.dutyLimited');
    });
    test(
        'model.dutyLimited stays clear on a healthy exchanger with noise on and FC-103 at 100 % OP (SP above Q_max)',
        () {
      final sim = newSim(btT2(), options: const SimOptions(seed: 4));
      runSteady(sim);
      sim.setLever('noise', 1);
      sim.control.setSp('FC-103', 1.3 * sim.snapshot().reboiler.qMax);
      var raised = false;
      var opMin = 100.0;
      advanceSampling(sim, 3600, 5, (t, s) {
        raised |= s.reboiler.dutyLimited || hasAlarm(s, 'model.dutyLimited');
        if (t > 300) opMin = math.min(opMin, loopOf(s, 'FC-103').op);
      });
      expect(opMin, greaterThanOrEqualTo(99.9), reason: 'valve wide open');
      expect(hasAlarm(sim.snapshot(), 'FC-103.OPSAT'), isTrue);
      expect(raised, isFalse);
    });
    test(
        'H4 F15 steam header loss (s 0.85): header reading down, FC-103.OPSAT, T_st down; model.dutyLimited stays clear',
        () {
      final sim = _steady();
      final pt0 = reading(sim.snapshot(), 'PT-201').value,
          tst0 = sim.snapshot().reboiler.steamT;
      _equip(sim, FaultType.steamHeaderLoss, 'reboiler',
          severity: 0.85, ramp: 120);
      // VALIDATION.md H4 (2026-10-12): the symptom is FC-103.OPSAT; a header
      // loss lowers Q_v and Q_max together, so model.dutyLimited is not
      // expected (PHYSICS.md §8.2).
      var dutyLimited = false;
      advanceSampling(sim, 900, 5, (t, st) {
        dutyLimited |=
            st.reboiler.dutyLimited || hasAlarm(st, 'model.dutyLimited');
      });
      final s = sim.snapshot();
      expect(reading(s, 'PT-201').value, lessThan(pt0 - 1e5));
      expect(s.reboiler.steamT, lessThan(tst0 - 5));
      expect(hasAlarm(s, 'FC-103.OPSAT'), isTrue);
      expect(dutyLimited, isFalse, reason: 'model.dutyLimited raised by F15');
      // "Limited" is an onset statement: as the duty falls the bottoms get
      // lighter, T_B drops (≈ 103 °C) and Q_max = UA_R (T_st − T_B)
      // recovers, so the self-consistent duty is ≈ 1200 kW, below SP.
      expect(s.kpis.qr, lessThan(loopOf(s, 'FC-103').sp - 20 * kw));
      expect(s.reboiler.qMax,
          closeTo(s.reboiler.uaEff * (s.reboiler.steamT - s.reboiler.tSump),
              1e-3 * s.reboiler.qMax));
      expect(s.kpis.qr, lessThanOrEqualTo(s.reboiler.qMax * 1.001));
    });
    test(
        'F09 pressure levels [P] at the VC-11 point: flow s 0.6 → 1.070, s 0.7 → 1.167 bar(a); temperature s 0.6 → 1.180, s 1 → 1.389 bar(a); CW 100 %',
        () {
      // Independent check of s 0.7 flow: 0.3 × 41.54 kg/s gives 29.9/(1 +
      // 29.9/104.2) = 23.2 kW/K, so ≈ 1281 kW needs T_sat ≈ 85.2 °C, ≈ 1.165
      // bar(a) for x_D ≈ 0.98. Engine (validator run): 1.0698, 1.1668,
      // 1.1796, 1.3887.
      for (final (mode, s, pBar) in [
        ('flow', 0.6, 1.070),
        ('flow', 0.7, 1.167),
        ('temperature', 0.6, 1.180),
        ('temperature', 1.0, 1.389)
      ]) {
        final sim = vc11Sim()..runToSteadyState();
        _equip(sim, FaultType.coolingLoss, 'condenser',
            severity: s, params: {'mode': mode});
        sim.advance(4 * 3600);
        final st = sim.snapshot();
        expect(loopOf(st, 'PC-101').op, greaterThanOrEqualTo(99.9),
            reason: '$mode s=$s CW valve');
        expect(st.kpis.pTop / 1e5, closeTo(pBar, 0.005),
            reason: '$mode s=$s P_top');
      }
    });
    test(
        'H1 F07 feed +0.1 benzene in Tier 2 (LV, fixed duty): tray 10 T down ≥ 1 K; D up ≥ 0.3 kmol/h',
        () {
      final sim = _steady();
      final p0 = prof(sim);
      sim.faults.inject(FaultSpec(
          type: FaultType.feedComposition,
          location: FaultLocation.feed(0),
          severity: 1.0,
          onset: sim.time,
          ramp: 0,
          params: const {
            'dz': [0.1, -0.1]
          }));
      final p = runSteady(sim);
      // engine (validator run): D 49.84 → 51.02, T10 92.05 → 87.40 °C
      expect(tC(p.s, 10), lessThan(tC(p0.s, 10) - 1));
      expect(p.dKmolh, greaterThan(p0.dKmolh + 0.3));
      expect(p.s.kpis.qr, closeTo(p0.s.kpis.qr, 1), reason: 'duty fixed');
    });
    test(
        'F08 feed thermal upset (T_F −40 K): V and L change below the feed; q rises above 1',
        () {
      final sim = _steady();
      final p0 = prof(sim);
      _equip(sim, FaultType.feedThermal, 'feed');
      final p = runSteady(sim);
      expect(p.liquidDown(15), greaterThan(p0.liquidDown(15)),
          reason: 'subcooled feed condenses vapour → more liquid below');
      expect(p.vaporUp(5), lessThan(p0.vaporUp(5)),
          reason: 'less vapour above the feed at the same duty');
      expect(p.s.streams[StreamId.feed]!.q, greaterThan(1.0));
    });
  });

  test(
      'reboiler and condenser design numbers (PHYSICS.md §7.2, §8.2) are stored in the preset',
      () {
    final cfg = btT2();
    expect(cfg.condenser.uaClean / kw, closeTo(condenserDesign.ua, 0.1));
    expect(cfg.reboiler.uaClean / kw, closeTo(reboilerDesign.ua, 0.1));
    expect(ref.waterTsat(cfg.reboiler.steamHeaderPressure) - 273.15,
        closeTo(reboilerDesign.tSt, 0.05));
    expect(cfg.condenser.cwMaxFlow, closeTo(41.54, 0.05));
  });
}
