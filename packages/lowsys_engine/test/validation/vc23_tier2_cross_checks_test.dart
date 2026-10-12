// VC-23 Tier-2 cross-checks: C2, C3a, C3b, C6, C7 exact closure, no false
// alarms with noise, and the Tier-2 detection rows (PT-101 bias, TI-114
// bias with TC-101, F07 decoy).
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m4.dart';

Simulator _t2({bool noise = false, int seed = 1, int view = 0}) {
  final sim = newSim(btT2(), options: SimOptions(seed: seed));
  runSteady(sim);
  if (noise) sim.setLever('noise', 1);
  if (view != 0) sim.setLever('view', view.toDouble());
  sim.setCheckWindow(600);
  return sim;
}

void main() {
  test(
      'VC-23.1 Tier 2 exact closure (noise off): |r3a|, |r3b| ≤ 0.1 band; C7 |r7| ≤ 0.05 K; C2 after 1800 s ≤ 0.02 kmol/h',
      () {
    final sim = vc11Sim();
    runSteady(sim);
    sim.setCheckWindow(600);
    sim.advance(700);
    final s = sim.snapshot();
    for (final id in ['C3a', 'C3b']) {
      final c = checkOf(s, id)!;
      expect(c.residual.abs(), lessThanOrEqualTo(0.1 * c.band),
          reason: '$id r=${c.residual} band=${c.band}');
      expect(c.status, CheckStatus.ok);
    }
    for (final id in ['C7:top', 'C7:bottom']) {
      final c = checkOf(s, id)!;
      expect(c.residual.abs(), lessThanOrEqualTo(0.05), reason: id);
    }
    sim.setCheckWindow(1800);
    sim.advance(1900);
    final c2 = checkOf(sim.snapshot(), 'C2')!;
    expect(c2.residual.abs() / kmolh, lessThanOrEqualTo(0.02));
    expect(c2.status, CheckStatus.ok);
  });

  test(
      'VC-23.2 Tier 2 no false alarms with noise (2 h, W 600): no fail, check < 2 %',
      () {
    final sim = _t2(noise: true, seed: 7);
    sim.advance(700);
    var n = 0, checks = 0;
    advanceSampling(sim, 7200, 5, (t, s) {
      for (final c in s.crossChecks) {
        if (c.status == CheckStatus.notAvailable ||
            c.status == CheckStatus.transient) continue;
        n++;
        expect(c.status, isNot(CheckStatus.fail), reason: '${c.id} at $t');
        if (c.status == CheckStatus.check) checks++;
      }
    });
    expect(checks / n, lessThan(0.02));
  });

  group('VC-23.3 Tier-2 detection (noise on, W 600, onset 600 s)', () {
    test(
        'PT-101 bias +, s 0.5 (10.1 kPa): r7a and r7b ≥ 2.7 K, same sign, within 15 min; C6 flags no TI',
        () {
      final sim = _t2(noise: true);
      sim.advance(600);
      injectInstrumentFault(sim, 'PT-101', 'bias', severity: 0.5, sign: 1);
      double? tHit;
      var c6Flag = false;
      advanceSampling(sim, 900, 5, (t, s) {
        final a = checkOf(s, 'C7:top')!.residual,
            b = checkOf(s, 'C7:bottom')!.residual;
        if (tHit == null &&
            a.abs() >= 2.7 &&
            b.abs() >= 2.7 &&
            a.sign == b.sign) tHit = t;
        if (s.crossChecks
            .any((c) => c.id.startsWith('C6:') && c.status == CheckStatus.fail))
          c6Flag = true;
      });
      expect(tHit, isNotNull);
      expect(c6Flag, isFalse);
    });
    test(
        'TI-114 bias +, s 0.25 (5 K) with TC-101 on: C6 flags TI-114 within 20 min and no other TI',
        () {
      final sim = _t2(noise: true);
      sim.setLever('tc101Enable', 1);
      sim.advance(900);
      sim.setTemperatureReference();
      injectInstrumentFault(sim, 'TI-114', 'bias', severity: 0.25, sign: 1);
      double? tHit;
      var other = false;
      advanceSampling(sim, 1200, 5, (t, s) {
        for (final c in s.crossChecks) {
          if (!c.id.startsWith('C6:')) continue;
          if (c.status == CheckStatus.fail) {
            if (c.id == 'C6:TI-114') {
              tHit ??= t;
            } else {
              other = true;
            }
          }
        }
      });
      expect(tHit, isNotNull);
      expect(other, isFalse);
    });
    test(
        'F07 feed +0.08 benzene (ramp 900 s): no C1/C3/C4/C5 fail; C6 flags nothing (else widen 0.5 → 0.75 per the doc)',
        () {
      final sim = _t2(noise: true);
      sim.advance(900);
      sim.setTemperatureReference();
      sim.faults.inject(FaultSpec(
          type: FaultType.feedComposition,
          location: FaultLocation.feed(0),
          severity: 1.0,
          onset: sim.time,
          ramp: 900,
          params: const {
            'dz': {'benzene': 0.08},
            'sign': 1
          }));
      advanceSampling(sim, 7200, 5, (t, s) {
        for (final c in s.crossChecks) {
          if (c.id == 'C2') continue;
          expect(c.status, isNot(CheckStatus.fail), reason: '${c.id} at $t');
        }
      });
    });
  });
}
