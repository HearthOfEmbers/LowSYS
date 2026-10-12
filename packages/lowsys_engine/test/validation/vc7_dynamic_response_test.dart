// VC-7 dynamic responses (Tier 1, ideal hydraulics). Prototype [P] values
// with the wide tolerances VALIDATION.md gives; the direction checks are
// strict.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'reference/validation_expectations.dart';

Simulator _steadyDefault() {
  final sim = newSim(btConfig());
  runSteady(sim);
  return sim;
}

void main() {
  group('VC-7.1 reflux step L0 100 → 110 kmol/h, VB fixed', () {
    test('VC-7.1 trajectory within tolerance and final state = VC-4.11', () {
      final sim = _steadyDefault();
      sim.setLever('refluxFlow', 110 * kmolh);
      final t0 = sim.time;
      var xDPrev = -1.0;
      var dMin = double.infinity;
      var xDMonotone = true;
      var xBRising = true;
      var xBPrev = -1.0;
      final samples = <double, Profile>{};
      final want = {for (final r in vc71) r.t: r};
      // sample every 60 s for 2 h
      advanceSampling(sim, 7200, 60, (t, s) {
        final p = Profile(s);
        expectPhysical(s, where: 't=$t');
        final tt = (t).roundToDouble();
        if (want.containsKey(tt)) samples[tt] = p;
        if (t >= 60) {
          if (xDPrev >= 0 && p.xD < xDPrev - 1e-7) xDMonotone = false;
          if (xBPrev >= 0 && p.xB < xBPrev - 1e-7) xBRising = false;
          xDPrev = p.xD;
          xBPrev = p.xB;
        }
        dMin = math.min(dMin, p.dKmolh);
      });
      expect(sim.time - t0, closeTo(7200, 1e-6));
      for (final r in vc71) {
        final p = samples[r.t]!;
        expect(p.xD, closeTo(r.xD, 0.002), reason: 'xD at ${r.t} s');
        expect(p.xB, closeTo(r.xB, 0.01), reason: 'xB at ${r.t} s');
        expect(p.dKmolh, closeTo(r.d, 1.0), reason: 'D at ${r.t} s');
      }
      expect(xDMonotone, isTrue, reason: 'xD rises monotonically after 60 s');
      expect(xBRising, isTrue, reason: 'xB rises');
      expect(dMin, lessThan(40),
          reason: 'D undershoots 40 (level-loop overshoot)');
      // final state (VC-4.11)
      final pf = runSteady(sim);
      expect(pf.xD, closeTo(0.993373, 1e-5));
      expect(pf.xB, closeTo(0.171085, 1e-5));
      expect(pf.dKmolh, closeTo(40, 0.01));
    });
  });

  group('VC-7.2 hydraulic lag', () {
    test('VC-7.2 liquid leaving tray 1 and tray 20 after L0 +10 kmol/h', () {
      // Amended VC-7.2 (2026-10-12): t63 of each tray is measured from
      // t63 of the DELIVERED reflux (streams[reflux].flow), so the test is
      // independent of the flow-loop speed (M1 1 s lag, M3 3 s loop).
      final sim = _steadyDefault();
      final p0 = prof(sim);
      final l0Zero = p0.s.streams[StreamId.reflux]!.flow;
      final l1Zero = p0.liquidDown(1);
      final l20Zero = p0.liquidDown(20);
      const step = 10 * kmolh;
      sim.setLever('refluxFlow', 110 * kmolh);
      double? t63L0, t63Tray1, t63Tray20;
      advanceSampling(sim, 120, 0.5, (t, s) {
        final p = Profile(s);
        final f0 = (s.streams[StreamId.reflux]!.flow - l0Zero) / step;
        final f1 = (p.liquidDown(1) - l1Zero) / step;
        final f20 = (p.liquidDown(20) - l20Zero) / step;
        t63L0 ??= f0 >= 0.63 ? t : null;
        t63Tray1 ??= f1 >= 0.63 ? t : null;
        t63Tray20 ??= f20 >= 0.63 ? t : null;
      });
      expect(t63L0, isNotNull, reason: 'delivered reflux never reached 63 %');
      expect(t63Tray1, isNotNull, reason: 'tray 1 never reached 63 %');
      expect(t63Tray20, isNotNull, reason: 'tray 20 never reached 63 %');
      expect(t63Tray1! - t63L0!, inInclusiveRange(1, 4),
          reason: 't63(L1) − t63(L0) (M1 engine 1.5 s)');
      expect(t63Tray20! - t63L0!, inInclusiveRange(20, 45),
          reason: 't63(L20) − t63(L0) (M1 engine 29.0 s)');
      // information only: lever → delivered reflux 63 % (M1 ≈ 2 s, M3 ≈ 3 s)
      expect(t63L0!, inInclusiveRange(0.5, 6));
    });
  });

  group('VC-7.3 level loops', () {
    test(
        'VC-7.3 drum level after the reflux step: deviation 2–6 points, back within 90 min',
        () {
      final sim = _steadyDefault();
      sim.setLever('refluxFlow', 110 * kmolh);
      var maxDev = 0.0;
      var tMax = 0.0;
      double? tBack;
      advanceSampling(sim, 4 * 3600, 30, (t, s) {
        final dev = (s.kpis.drumLevelPct - 50).abs();
        if (dev > maxDev) {
          maxDev = dev;
          tMax = t;
        }
        if (tBack == null && t > tMax + 60 && maxDev > 1 && dev < 1) tBack = t;
      });
      expect(maxDev, inInclusiveRange(2, 6),
          reason: 'max deviation (prototype 3.58 at 17 min)');
      expect(tBack, isNotNull);
      expect(tBack!, lessThan(90 * 60),
          reason: 'back within ±1 point (prototype 56 min)');
      final pf = runSteady(sim);
      expect(pf.drumLevel, closeTo(50, 0.01));
    });

    test(
        'VC-7.3 sump level after feed +10 %: deviation 2–6 points, final 50.00',
        () {
      final sim = _steadyDefault();
      sim.setLever('feedFlow', 110 * kmolh);
      var maxDev = 0.0;
      advanceSampling(sim, 4 * 3600, 30, (t, s) {
        maxDev = math.max(maxDev, (s.kpis.sumpLevelPct - 50).abs());
      });
      expect(maxDev, inInclusiveRange(2, 6),
          reason: 'max sump deviation (prototype 3.53)');
      final pf = runSteady(sim);
      expect(pf.sumpLevel, closeTo(50, 0.01));
    });
  });

  test('VC-7.4 time to steady state from cold between 2.5 and 6 h', () {
    final sim = newSim(btConfig(), warmStart: false);
    final r = sim.runToSteadyState();
    expect(r.reached, isTrue);
    expect(r.simSeconds, inInclusiveRange(2.5 * 3600, 6 * 3600),
        reason: 'steady declared at ${r.simSeconds / 3600} h');
    expect(sim.isSteady, isTrue);
    expect(sim.snapshot().steady.isSteady, isTrue);
  });
}
