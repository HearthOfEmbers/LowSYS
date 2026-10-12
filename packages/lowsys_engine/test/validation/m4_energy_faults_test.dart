// VC-5.2 component conservation with the overhead vapour inventory,
// VC-5.4 energy closure, the VC-27.4 severity floors and the H2/H4 fault
// symptoms of F08–F15 (noise off, Tier 2).
library;

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
        '5.2 exact component conservation including the overhead inventory n_V,i (1e-8) over 4 h with a reflux step',
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
        expect(c, lessThan(1e-8), reason: 'component $i closure $c');
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
      for (final (s, pBar, tSt, qMax) in f15) {
        final sim = _steady();
        _equip(sim, FaultType.steamHeaderLoss, 'reboiler', severity: s);
        sim.advance(300);
        final st = sim.snapshot();
        expect(reading(st, 'PT-201').value / 1e5, closeTo(pBar - 1.01325, 0.02),
            reason: 's=$s header gauge pressure');
        expect(st.reboiler.steamT - 273.15, closeTo(tSt, 0.2),
            reason: 's=$s T_st');
        expect(st.reboiler.qMax / kw, closeTo(qMax, 0.02 * qMax),
            reason: 's=$s Q_max');
        final limited =
            hasAlarm(st, 'model.dutyLimited') || st.kpis.qr < 0.98 * 1300 * kw;
        expect(limited, s >= f15LimitS, reason: 's=$s limited?');
      }
    });
    test(
        'F11 non-condensables s 1: ≈ 10 mol inert/h into a ≈ 104 mol overhead; y_I ≈ 0.09, extra subcooling ≈ 5 K after 1 h; vent restores P within 10 min',
        () {
      final sim = _steady();
      final t0 = reading(sim.snapshot(), 'TI-100').value;
      _equip(sim, FaultType.nonCondensables, 'condenser');
      sim.advance(3600);
      final s = sim.snapshot();
      expect(s.condenser!.inertFraction, closeTo(f11.yI1h, 0.02));
      expect(s.condenser!.vaporMoles, closeTo(f11.overheadMol, 15));
      expect(t0 - reading(s, 'TI-100').value, closeTo(f11.subcool1h, 1.5),
          reason: 'subcooling up (H2 ≥ 5 K)');
      expect(s.kpis.pTop, greaterThan(101325 + 500),
          reason: 'P up while the CW valve is not saturated at first');
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
        'F12 partial reflux loss (s 0.5): reflux below SP with FC-102 at 100 %, top T up, drum level up',
        () {
      final sim = _steady();
      final t1 = tC(sim.snapshot(), 1);
      _equip(sim, FaultType.refluxPumpTrip, 'reflux', severity: 0.5);
      sim.advance(1800);
      final s = sim.snapshot();
      expect(loopOf(s, 'FC-102').op, closeTo(100, 0.5));
      expect(reading(s, 'FT-102').value,
          lessThan(loopOf(s, 'FC-102').sp - 5 * kmolh));
      expect(tC(s, 1), greaterThan(t1 + 0.5));
      expect(s.kpis.drumLevelPct, greaterThan(55));
    });
    test(
        'F13 reboiler fouling (ramp 6 h): steam valve rises over ≥ 30 min then saturates; duty below SP after',
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
    });
    test(
        'F14 condensate backup (s 0.75): duty below SP within 5 min with the steam valve at 100 %',
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
    });
    test(
        'F15 steam header loss (s 0.85): header reading down, duty limited, T_st down',
        () {
      final sim = _steady();
      final pt0 = reading(sim.snapshot(), 'PT-201').value,
          tst0 = sim.snapshot().reboiler.steamT;
      _equip(sim, FaultType.steamHeaderLoss, 'reboiler',
          severity: 0.85, ramp: 120);
      sim.advance(900);
      final s = sim.snapshot();
      expect(reading(s, 'PT-201').value, lessThan(pt0 - 1e5));
      expect(s.reboiler.steamT, lessThan(tst0 - 5));
      expect(hasAlarm(s, 'model.dutyLimited') || hasAlarm(s, 'FC-103.OPSAT'),
          isTrue);
      expect(s.kpis.qr, lessThan(0.9 * 1300 * kw));
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
