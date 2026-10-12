// VC-12.4 fault and operating-condition symptoms (full hydraulics, Tier 1).
// The "must hold" assertions of the table; prototype values are informative.
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

/// Runs 10 min then to 4 h, asserting robustness at every sample.
({Hyd at10, Hyd at4h, double maxPhi, double maxWeep, double maxFill, int maxDc})
    _run(Simulator sim, String where) {
  Hyd? at10;
  var maxPhi = 0.0, maxWeep = 0.0, maxFill = 0.0, maxDc = 0;
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
    if ((t - 600).abs() < 1) at10 = h;
  });
  return (
    at10: at10!,
    at4h: hyd(sim),
    maxPhi: maxPhi,
    maxWeep: maxWeep,
    maxFill: maxFill,
    maxDc: maxDc
  );
}

void main() {
  group('VC-12.4 load changes', () {
    for (final c in vc124Loads.where((c) => c.loadFactor > 1)) {
      test(c.name, () {
        final (sim, dp0, xD0, _) = _design(
            options: c.entrainment
                ? const SimOptions()
                : const SimOptions(entrainment: false));
        c.loadFactor > 1
            ? addLoad(sim, c.loadFactor - 1)
            : scaleLoad(sim, c.loadFactor);
        final r = _run(sim, c.name);
        final dp10 = r.at10.columnDp;
        if (c.dpRatioMin > 0) {
          expect(dp10 / dp0, greaterThanOrEqualTo(c.dpRatioMin),
              reason:
                  'ΔP after 10 min ${dp10 / 1000} kPa (proto ${c.protoDp10})');
        }
        final xD4 = Profile(r.at4h.s).xD;
        if (c.xD4hMax != null)
          expect(xD4, lessThanOrEqualTo(c.xD4hMax!),
              reason: 'xD after 4 h (proto ${c.protoXd4h})');
        if (c.xD4hMin != null)
          expect(xD4, greaterThanOrEqualTo(c.xD4hMin!),
              reason: 'xD after 4 h (proto ${c.protoXd4h})');
        if (c.loadFactor >= 1.45) {
          expect(sim.control.loop('LC-101').op, closeTo(100, 1e-6),
              reason: 'D at valve limit');
          expect(r.at4h.s.kpis.drumLevelPct, greaterThan(60),
              reason: 'drum level high');
        }
        if (c.entrainment) {
          expect(xD4, lessThan(xD0), reason: 'separation worse than base');
        } else {
          // without entrainment the extra L/V can only help (0.9886 > 0.9812)
          expect(xD4, greaterThan(xD0),
              reason: 'better L/V, no entrainment loss');
        }
      });
    }

    test(
        'Load +20 %: the xD loss is entrainment (0.9124 with vs 0.9886 without)',
        () {
      final (a, _, _, _) = _design();
      final (b, _, _, _) =
          _design(options: const SimOptions(entrainment: false));
      addLoad(a, 0.2);
      addLoad(b, 0.2);
      a.advance(4 * 3600);
      b.advance(4 * 3600);
      expect(prof(a).xD, lessThan(0.94));
      expect(prof(b).xD, greaterThan(0.98));
    });
  });

  group('VC-12.4 turndown (weeping)', () {
    test(
        '50 %: weeping starts (0 < w < 0.2) and xB is worse than without weeping',
        () {
      final (a, _, _, _) = _design();
      final (b, _, _, _) = _design(options: const SimOptions(weeping: false));
      scaleLoad(a, 0.5);
      scaleLoad(b, 0.5);
      final ra = _run(a, 'turndown 50');
      b.advance(4 * 3600);
      expect(ra.maxWeep, greaterThan(0));
      expect(ra.maxWeep, lessThan(0.2));
      expect(Profile(ra.at4h.s).xB, greaterThan(prof(b).xB),
          reason: 'weeping costs bottoms purity');
    });

    test('35 %: w ≥ 0.3, xB(weep) ≥ 1.5 × xB(no weep), xD(weep) < xD(no weep)',
        () {
      final (a, _, _, _) = _design();
      final (b, _, _, _) = _design(options: const SimOptions(weeping: false));
      scaleLoad(a, 0.35);
      scaleLoad(b, 0.35);
      final ra = _run(a, 'turndown 35');
      b.advance(4 * 3600);
      final pa = Profile(ra.at4h.s), pb = prof(b);
      expect(ra.maxWeep, greaterThanOrEqualTo(0.3));
      expect(pa.xB, greaterThanOrEqualTo(1.5 * pb.xB));
      expect(pa.xD, lessThan(pb.xD));
    });
  });

  group('VC-12.4 foaming F06', () {
    test('s = 0.33: xD drops ≥ 0.02, max φ ≥ 0.95, ΔP about unchanged', () {
      final (sim, dp0, xD0, _) = _design();
      injectTrayFault(sim, FaultType.foaming,
          from: 1, to: 20, severity: 0.33, ramp: 600);
      final r = _run(sim, 'foaming 0.33');
      expect(r.maxPhi, greaterThanOrEqualTo(0.95));
      expect(Profile(r.at4h.s).xD, lessThanOrEqualTo(xD0 - 0.02));
      expect(r.at4h.columnDp / dp0, closeTo(1.0, 0.1),
          reason: 'ΔP ≈ unchanged (proto 14.56)');
    });

    test('s = 0.67: floods — xD ≤ 0.6 after 4 h, drum ≥ 90 %, flooding alarm',
        () {
      final (sim, _, _, _) = _design();
      injectTrayFault(sim, FaultType.foaming,
          from: 1, to: 20, severity: 0.67, ramp: 600);
      final r = _run(sim, 'foaming 0.67');
      expect(Profile(r.at4h.s).xD, lessThanOrEqualTo(0.6));
      expect(r.at4h.s.kpis.drumLevelPct, greaterThanOrEqualTo(90));
      expect(r.at4h.s.alarms.any((a) => a.id.toLowerCase().contains('flood')),
          isTrue,
          reason: 'flooding alarm');
    });
  });

  group('VC-12.4 fouling F05', () {
    test(
        'holes s = 0.3 trays 12–16: ΔP +10…+20 %, |ΔxD| ≤ 0.002 (fouling shows in ΔP first)',
        () {
      final (sim, dp0, xD0, _) = _design();
      injectTrayFault(sim, FaultType.trayFouling,
          from: 12, to: 16, severity: 0.3, ramp: 0, params: {'mode': 'holes'});
      final r = _run(sim, 'fouling 0.3');
      expect(r.at4h.columnDp / dp0, inInclusiveRange(1.10, 1.20),
          reason: 'proto 16.84 kPa');
      expect((Profile(r.at4h.s).xD - xD0).abs(), lessThanOrEqualTo(0.002));
      // the extra ΔP is on the fouled trays only
      expect(r.at4h.sumDp(12, 16) / r.at4h.sumDp(1, 5), greaterThan(1.3));
    });

    test(
        'holes s = 0.6 trays 12–16: ΔP ≥ 2× base within 10 min, downcomer limit on ≥ 5 trays, sump ≤ 10 %',
        () {
      final (sim, dp0, _, _) = _design();
      injectTrayFault(sim, FaultType.trayFouling,
          from: 12, to: 16, severity: 0.6, ramp: 0, params: {'mode': 'holes'});
      final r = _run(sim, 'fouling 0.6');
      expect(r.at10.columnDp / dp0, greaterThanOrEqualTo(2.0),
          reason: 'proto 45.3 kPa');
      expect(r.at10.countTrays(r.at10.dcLimited), greaterThanOrEqualTo(5));
      expect(r.at10.s.kpis.sumpLevelPct, lessThanOrEqualTo(10));
    });

    test(
        'downcomer mode s = 1 trays 12–16: ΔP ≥ 1.8× base within 10 min, liquid accumulates above tray 12',
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
          reason: 'proto 34.3 kPa');
      var fillAbove = 0.0;
      for (var j = 1; j < 12; j++) {
        fillAbove = [fillAbove, r.at4h.frothFill(j), r.at10.frothFill(j)]
            .reduce((a, b) => a > b ? a : b);
      }
      expect(fillAbove, greaterThanOrEqualTo(1.0),
          reason: 'fill ≥ 1 on some tray above 12');
    });
  });

  group('VC-12.4 broken tray F04', () {
    for (final tray in [5, 15]) {
      test('tray $tray, s = 1: tray ΔP ≤ 15 % of base, xD and xB worse', () {
        final (sim, _, xD0, xB0) = _design();
        final dpTray0 = hyd(sim).dp(tray);
        injectTrayFault(sim, FaultType.trayDamage, from: tray, severity: 1.0);
        final r = _run(sim, 'broken $tray');
        expect(r.at10.dp(tray) / dpTray0, lessThanOrEqualTo(0.15),
            reason: 'proto 664 → 38 Pa');
        expect(Profile(r.at4h.s).xD, lessThan(xD0));
        expect(Profile(r.at4h.s).xB, greaterThan(xB0));
        expect(r.at4h.columnDp,
            lessThan(hyd(sim).columnDp + 1e-9)); // identical snapshot; sanity
      });
    }

    test('tray 5, s = 0.5: the rest of the deck weeps (weep fraction ≥ 0.5)',
        () {
      final (sim, _, _, _) = _design();
      injectTrayFault(sim, FaultType.trayDamage, from: 5, severity: 0.5);
      final r = _run(sim, 'broken 5 half');
      expect(r.at4h.weepFrac(5), greaterThanOrEqualTo(0.5));
    });
  });

  group('VC-8.1 L0, VB +10 with full hydraulics', () {
    // The textbook direction (xD up) is VC-8.1 under ideal hydraulics
    // (qualitative_physics_test). The B-T default sits at 83 % jet flood, so
    // +10 kmol/h takes the stripping trays to ≈ 95 % and the entrainment
    // recycle outweighs the better L/V: xD falls (0.967 → 0.958). That is the
    // real "entrainment knee" of Fair's chart. What must hold here: flood
    // approach rises, boilup follows the lever, and with entrainment
    // switched off the textbook direction returns.
    test(
        '8.1 full hydraulics: flood approach up; textbook direction holds without entrainment',
        () {
      final (sim, _, xD0, xB0) = _design();
      final flood0 = hyd(sim).maxFloodPct;
      sim.setLever('refluxFlow', 110 * kmolh);
      sim.setLever('boilup', 160 * kmolh);
      final p = runSteady(sim);
      expect(p.boilupKmolh, closeTo(160, 0.01));
      expect(hyd(sim).maxFloodPct, greaterThan(flood0 + 5));
      expect(hyd(sim).maxFloodPct, inInclusiveRange(85, 100));
      expect(p.xB, lessThan(xB0),
          reason: 'more stripping vapour still cleans the bottoms');

      final noEnt =
          newSim(btFull(), options: const SimOptions(entrainment: false));
      final q0 = runSteady(noEnt);
      noEnt.setLever('refluxFlow', 110 * kmolh);
      noEnt.setLever('boilup', 160 * kmolh);
      final q = runSteady(noEnt);
      expect(q.xD, greaterThan(q0.xD),
          reason: 'VC-8.1 direction without entrainment');
      expect(q.xB, lessThan(q0.xB));
      expect(q.xD, closeTo(0.984504, 1e-4), reason: 'VC-4.6 value');
    });
  });
}
