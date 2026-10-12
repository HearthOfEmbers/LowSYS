// VC-12.4 fault and operating-condition symptoms (v1.1, TS 0.9 m), the
// full-hydraulics direction checks VC-8.15 / 8.16 and the dumping law
// VC-12.6. Prototype values are informative; the "must hold" column is
// asserted.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m2.dart';
import 'reference/validation_expectations_m2.dart';

/// Design steady state, then returns (sim, base ΔP, base xD, base xB).
(Simulator, double, double, double) _design(
    {SimOptions options = const SimOptions()}) {
  final sim = newSim(btFull(), options: options);
  final p = runSteady(sim);
  return (sim, hyd(sim).columnDp, p.xD, p.xB);
}

bool _floodAlarm(SimSnapshot s) =>
    s.alarms.any((a) => a.id.toLowerCase().contains('flood'));

/// Runs 10 min then to 4 h, asserting robustness at every sample.
({
  Hyd at10,
  Hyd at4h,
  double maxPhi,
  double maxWeep,
  double maxFill,
  int maxDc,
  bool floodAlarm
}) _run(Simulator sim, String where) {
  Hyd? at10;
  var maxPhi = 0.0, maxWeep = 0.0, maxFill = 0.0, maxDc = 0;
  var flood = false;
  advanceSampling(sim, 4 * 3600, 60, (t, s) {
    expectHydraulicallySane(s, where: '$where @ $t');
    final h = Hyd(s);
    maxPhi =
        [maxPhi, h.maxOverTrays(h.jetFlood)].reduce((a, b) => a > b ? a : b);
    maxWeep =
        [maxWeep, h.maxOverTrays(h.weepFrac)].reduce((a, b) => a > b ? a : b);
    maxFill =
        [maxFill, h.maxOverTrays(h.frothFill)].reduce((a, b) => a > b ? a : b);
    maxDc = [maxDc, h.countTrays(h.dcLimited)].reduce((a, b) => a > b ? a : b);
    if (_floodAlarm(s)) flood = true;
    if ((t - 600).abs() < 1) at10 = h;
  });
  return (
    at10: at10!,
    at4h: hyd(sim),
    maxPhi: maxPhi,
    maxWeep: maxWeep,
    maxFill: maxFill,
    maxDc: maxDc,
    floodAlarm: flood
  );
}

void main() {
  group('VC-12.4 load changes (F fixed, L0 and V_B + x·150)', () {
    for (final c in vc124Loads) {
      test(c.name, () {
        final (sim, dp0, xD0, xB0) = _design(
            options: c.entrainment
                ? const SimOptions()
                : const SimOptions(entrainment: false));
        addLoad(sim, c.fraction);
        final r = _run(sim, c.name);
        final dp10 = r.at10.columnDp;
        final p4 = Profile(r.at4h.s);
        if (c.dpRatioMin > 0) {
          expect(dp10 / dp0, greaterThanOrEqualTo(c.dpRatioMin),
              reason:
                  'ΔP after 10 min ${dp10 / 1000} kPa (proto ${c.protoDp10})');
        }
        if (c.xD4hMax != null)
          expect(p4.xD, lessThanOrEqualTo(c.xD4hMax!),
              reason: 'xD after 4 h (proto ${c.protoXd4h})');
        if (c.xD4hExact != null)
          expect(p4.xD, closeTo(c.xD4hExact!, c.xD4hTol!),
              reason: 'xD after 4 h = ideal value');
        if (c.xBBelowBase)
          expect(p4.xB, lessThan(xB0), reason: 'xB after 4 h (proto 0.0039)');
        if (c.noFloodAlarm)
          expect(r.floodAlarm, isFalse,
              reason:
                  'no flooding alarm (max flood proto ${c.protoFlood4h} %)');
        if (c.floodAlarm)
          expect(r.floodAlarm, isTrue,
              reason: 'flooding alarm (max flood > 90 %)');
        if (c.maxFlood100)
          expect(r.at4h.maxFloodPct, greaterThanOrEqualTo(100),
              reason: 'flood onset');
        // informative agreement with the prototype
        if (!c.protoDp10.isNaN)
          expect(dp10 / 1000, closeTo(c.protoDp10, 0.05 * c.protoDp10),
              reason: 'ΔP 10 min vs proto');
        if (!c.protoXd4h.isNaN && c.entrainment)
          expect(p4.xD, closeTo(c.protoXd4h, 0.01), reason: 'xD 4 h vs proto');
        if (c.entrainment) expect(xD0, closeTo(vc123.xD, 0.002));
      });
    }

    test('+30 % separates worse than +20 %; x_D ordering with load is monotone',
        () {
      final xds = <double>[];
      for (final f in [0.2, 0.3, 0.45, 0.6, 0.75]) {
        final (sim, _, _, _) = _design();
        addLoad(sim, f);
        sim.advance(4 * 3600);
        xds.add(prof(sim).xD);
      }
      for (var i = 1; i < xds.length; i++) {
        expect(xds[i], lessThan(xds[i - 1]), reason: 'load step $i');
      }
    });
  });

  group('VC-12.4 turndown (weeping)', () {
    for (final (f, w, xd, xb, xdNo, xbNo) in vc124Turndown) {
      test('turndown ${(100 * f).round()} %: w ≈ $w; xB(weep) vs no-weep', () {
        final (a, _, _, _) = _design();
        final (b, _, _, _) = _design(options: const SimOptions(weeping: false));
        scaleLoad(a, f);
        scaleLoad(b, f);
        final ra = _run(a, 'turndown $f');
        b.advance(4 * 3600);
        final pa = Profile(ra.at4h.s), pb = prof(b);
        if (f >= 0.5) {
          expect(ra.maxWeep, greaterThan(0));
          expect(ra.maxWeep, lessThan(0.2));
          expect(pa.xB, greaterThan(pb.xB));
        } else {
          expect(ra.maxWeep, greaterThanOrEqualTo(0.3));
          expect(pa.xB, greaterThanOrEqualTo(1.5 * pb.xB));
          expect(pa.xD, lessThan(pb.xD));
        }
        expect(ra.at10.maxOverTrays(ra.at10.weepFrac), closeTo(w, 0.08),
            reason: 'w vs proto');
        expect(pa.xD, closeTo(xd, 0.005), reason: 'xD vs proto');
        expect(pa.xB, closeTo(xb, 0.005), reason: 'xB vs proto');
        expect(pb.xD, closeTo(xdNo, 0.005), reason: 'no-weep xD vs proto');
        expect(pb.xB, closeTo(xbNo, 0.005), reason: 'no-weep xB vs proto');
      });
    }
  });

  group(
      'VC-12.4 foaming F06 (ΔP stays within ±10 %: foam floods without a ΔP rise)',
      () {
    for (final (s, _, _, phi10, xd4, dp4) in vc124Foam) {
      test('s = $s', () {
        final (sim, dp0, xD0, _) = _design();
        injectTrayFault(sim, FaultType.foaming,
            from: 1, to: 20, severity: s, ramp: 600);
        final r = _run(sim, 'foaming $s');
        final p4 = Profile(r.at4h.s);
        expect(r.at4h.columnDp / dp0, closeTo(1.0, 0.10),
            reason: 'ΔP within ±10 % (proto $dp4 kPa)');
        if (s < 0.5) {
          expect(r.maxPhi, greaterThanOrEqualTo(0.70),
              reason: 'proto max φ $phi10');
          expect(r.floodAlarm, isFalse, reason: 'headroom absorbs it');
        } else if (s < 0.9) {
          expect(p4.xD, lessThanOrEqualTo(xD0 - 0.015));
          expect(r.maxPhi, greaterThanOrEqualTo(0.85));
        } else {
          expect(r.floodAlarm, isTrue);
          expect(p4.xD, lessThanOrEqualTo(0.90), reason: 'proto xD $xd4');
        }
      });
    }
  });

  group('VC-12.4 fouling F05', () {
    for (final (s, dp10, ratio) in vc124FoulHoles) {
      test('holes s = $s trays 12–16: ΔP × $ratio (proto $dp10 kPa)', () {
        final (sim, dp0, xD0, _) = _design();
        injectTrayFault(sim, FaultType.trayFouling,
            from: 12, to: 16, severity: s, ramp: 0, params: {'mode': 'holes'});
        final r = _run(sim, 'fouling $s');
        if (s < 0.5) {
          expect(r.at4h.columnDp / dp0, inInclusiveRange(1.10, 1.20));
          expect((Profile(r.at4h.s).xD - xD0).abs(), lessThanOrEqualTo(0.002));
          expect(r.at4h.sumDp(12, 16) / r.at4h.sumDp(1, 5), greaterThan(1.3),
              reason: 'extra ΔP on the fouled trays');
        } else if (s < 0.7) {
          expect(r.at4h.columnDp / dp0, greaterThanOrEqualTo(1.4));
          expect((Profile(r.at4h.s).xD - xD0).abs(), lessThanOrEqualTo(0.002));
          expect(r.maxDc, 0, reason: 'no downcomer limit (headroom)');
        } else {
          expect(r.at10.columnDp / dp0, greaterThanOrEqualTo(2.0));
          expect(r.at10.countTrays(r.at10.dcLimited), greaterThanOrEqualTo(5));
          expect(r.at10.s.kpis.sumpLevelPct, lessThanOrEqualTo(10));
        }
      });
    }

    test(
        'downcomer mode s = 1 trays 12–16: ΔP ≥ 1.8× within 10 min, liquid accumulates above tray 12',
        () {
      final (sim, dp0, _, _) = _design();
      injectTrayFault(sim, FaultType.trayFouling,
          from: 12,
          to: 16,
          severity: 1.0,
          ramp: 0,
          params: {'mode': 'downcomer'});
      final r = _run(sim, 'dc fouling');
      expect(r.at10.columnDp / dp0, greaterThanOrEqualTo(1.8),
          reason: 'proto ${vc124FoulDc.dp10} kPa');
      var fillAbove = 0.0;
      for (var j = 1; j < 12; j++) {
        fillAbove = [fillAbove, r.at4h.frothFill(j), r.at10.frothFill(j)]
            .reduce((a, b) => a > b ? a : b);
      }
      expect(fillAbove, greaterThanOrEqualTo(1.0));
    });
  });

  group(
      'VC-12.4 broken tray F04 (rows unchanged by the dumping law: Φ ≈ 0.25 > 0.2)',
      () {
    for (final (tray, xd, xb) in [(5, 0.9743, 0.0186), (15, 0.9753, 0.0176)]) {
      test(
          'tray $tray, s = 1: tray ΔP ≤ 15 % of base, xD and xB worse (proto $xd / $xb)',
          () {
        final (sim, _, xD0, xB0) = _design();
        final dpTray0 = hyd(sim).dp(tray);
        injectTrayFault(sim, FaultType.trayDamage, from: tray, severity: 1.0);
        final r = _run(sim, 'broken $tray');
        expect(r.at10.dp(tray) / dpTray0, lessThanOrEqualTo(0.15));
        final p4 = Profile(r.at4h.s);
        expect(p4.xD, lessThan(xD0));
        expect(p4.xB, greaterThan(xB0));
        expect(p4.xD, closeTo(xd, 0.003));
        expect(p4.xB, closeTo(xb, 0.003));
        expect(r.at4h.dumping(tray), isFalse,
            reason: 'a broken tray at normal load does not dump');
      });
    }
    test('tray 5, s = 0.5: the rest of the deck weeps (w ≥ 0.5, proto 0.68)',
        () {
      final (sim, _, _, _) = _design();
      injectTrayFault(sim, FaultType.trayDamage, from: 5, severity: 0.5);
      final r = _run(sim, 'broken 5 half');
      expect(r.at4h.weepFrac(5), greaterThanOrEqualTo(0.5));
    });
  });

  group('VC-12.6 dumping (orifice drainage, PHYSICS.md (5.15))', () {
    test(
        'sieve: dumping trays hold ≤ 2 mol after 600 s without boilup; same at dt 2 and 30 s',
        () {
      final holds = <double, List<double>>{};
      for (final dt in [0.5, 2.0, 30.0]) {
        final sim =
            newSim(btFull(), options: SimOptions(dt: dt, dtFastForward: dt));
        runSteady(sim, fastForward: false);
        sim.setLever('boilup', 0);
        advanceSampling(sim, 600, dt,
            (t, s) => expectHydraulicallySane(s, where: 'dt $dt @ $t'));
        final h = hyd(sim);
        final list = <double>[];
        for (var j = 1; j <= 20; j++) {
          list.add(h.holdup(j));
          if (h.dumping(j)) {
            expect(h.holdup(j), lessThanOrEqualTo(2.0),
                reason: 'dt $dt tray $j dumping holdup');
          } else {
            expect(h.holdup(j), lessThanOrEqualTo(20.0),
                reason: 'dt $dt tray $j not dumping but ≤ 20 mol');
          }
        }
        // trays that receive nothing run dry (flag bit 3) rather than dumping
        final dry = h.countTrays((j) => (h.s.stages.flags[j] & 8) != 0);
        expect(h.countTrays(h.dumping), greaterThanOrEqualTo(5),
            reason: 'dt $dt dumping trays');
        expect(h.countTrays(h.dumping) + dry, greaterThanOrEqualTo(15),
            reason: 'dt $dt dumping or dry trays');
        expect(sim.solverHealth.stepRetries, 0,
            reason:
                "no dt halvings (the engine exposes no iteration count yet)");
        holds[dt] = list;
      }
      for (var j = 0; j < 20; j++) {
        expect(holds[2.0]![j], closeTo(holds[0.5]![j], 0.5),
            reason: 'tray ${j + 1} dt 2 vs 0.5');
        expect(holds[30.0]![j], closeTo(holds[0.5]![j], 0.5),
            reason: 'tray ${j + 1} dt 30 vs 0.5');
      }
      // trays receiving the feed chain: 1.1–1.4 mol → h_cl 0.14–0.17 mm
      final h = hyd(newSim(btFull())..setLever('boilup', 0));
      expect(h.nTrays, 20);
    });
    test('valve trays: dumping holdup ≤ 15 mol (h_cl ≈ 1.4–1.7 mm)', () {
      final sim = newSim(btFull(overrides: {'sections[0].type': 'valve'}));
      runSteady(sim);
      sim.setLever('boilup', 0);
      sim.advance(600);
      final h = hyd(sim);
      var dumpingWithLiquid = 0;
      var maxHcl = 0.0;
      for (var j = 1; j <= 20; j++) {
        if (h.dumping(j)) {
          expect(h.holdup(j), lessThanOrEqualTo(15.0), reason: 'tray $j');
          if (h.holdup(j) > 1) {
            dumpingWithLiquid++;
            // h_cl ∝ (inflow)²: 1.4–1.7 mm at the full feed, less on trays
            // fed by a partial chain
            expect(1000 * h.hcl(j), inInclusiveRange(0.1, 2.0),
                reason: 'tray $j h_cl mm');
            maxHcl = [maxHcl, 1000 * h.hcl(j)].reduce((a, b) => a > b ? a : b);
          }
        }
      }
      expect(dumpingWithLiquid, greaterThan(0));
      expect(maxHcl, inInclusiveRange(1.0, 2.0),
          reason: 'full-feed trays 1.4–1.7 mm (prototype)');
    });
    test(
        'fully broken tray 5: identical steady state at dt 0.5, 2 and 30 s (proto xD 0.974315)',
        () {
      final xds = <double>[];
      for (final dt in [0.5, 2.0, 30.0]) {
        final sim =
            newSim(btFull(), options: SimOptions(dt: dt, dtFastForward: dt));
        runSteady(sim, fastForward: false);
        injectTrayFault(sim, FaultType.trayDamage, from: 5, severity: 1.0);
        xds.add(runSteady(sim, fastForward: false).xD);
      }
      expect(xds[1], closeTo(xds[0], 1e-6));
      expect(xds[2], closeTo(xds[0], 1e-6));
      expect(xds[0], closeTo(0.974315, 1e-3));
    });
  });

  group('VC-8.15 / 8.16 full-hydraulics direction checks (TS 0.9)', () {
    test(
        '8.15 L0 and V_B +10 under LV control: xD 0.97826 → 0.98001, xB down, max flood 62.9 → 67.1, no alarm',
        () {
      final (sim, _, xD0, xB0) = _design();
      expect(xD0, closeTo(vc815.xD0, 0.0005));
      expect(hyd(sim).maxFloodPct, closeTo(vc815.flood0, 2));
      sim.setLever('refluxFlow', 110 * kmolh);
      sim.setLever('boilup', 160 * kmolh);
      var alarm = false;
      advanceSampling(
          sim, 2 * 3600, 60, (t, s) => alarm = alarm || _floodAlarm(s));
      final p = runSteady(sim);
      expect(p.xD, closeTo(vc815.xD10, 0.0005));
      expect(p.xB, closeTo(vc815.xB10, 0.0005));
      expect(p.xB, lessThan(xB0));
      expect(hyd(sim).maxFloodPct, closeTo(vc815.flood10, 2));
      expect(alarm, isFalse);
    });
    test(
        '8.16 D held at 50: xD rises monotonically 0.9810 → 0.9896 with +0…+40',
        () {
      var prev = 0.0;
      for (final (add, xd) in vc816) {
        final sim = newSim(btFull());
        sim.setLever('boilup', (150 + add) * kmolh);
        // adjust L0 until D = 50 ± 0.01 (secant on the steady D)
        var l0 = 100 + add;
        for (var it = 0; it < 6; it++) {
          sim.setLever('refluxFlow', l0 * kmolh);
          final d = runSteady(sim).dKmolh;
          if ((d - 50).abs() <= 0.01) break;
          l0 += d -
              50; // D = V1 + e1 − L0: raising L0 by the excess brings D down
        }
        final p = runSteady(sim);
        expect(p.dKmolh, closeTo(50, 0.02), reason: '+$add D');
        expect(p.xD, closeTo(xd, 0.0005), reason: '+$add xD');
        expect(p.xD, greaterThan(prev), reason: 'monotone at +$add');
        prev = p.xD;
      }
    });
  });
}
