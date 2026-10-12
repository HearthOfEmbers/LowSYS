// Qualitative "does this make physical sense" checks for M1 (Tier 1, ideal
// hydraulics): monotone lever responses, bounded and positive state under
// slams and large steps, path independence of the steady state, and
// VC-8 direction checks that are computable in Tier 1.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'reference/cmo_steady_reference.dart';
import 'reference/validation_expectations.dart';

Profile _steadyWith(void Function(Simulator) setup,
    {Map<String, Object?> overrides = const {}}) {
  final sim = newSim(btConfig(overrides: overrides));
  setup(sim);
  return runSteady(sim);
}

void main() {
  group('Monotone responses to levers (steady states)', () {
    test(
        'xD rises and xB falls with reflux when boilup rises by the same amount (D constant)',
        () {
      var prevXd = -1.0, prevXb = 2.0;
      for (final dl in [0.0, 10.0, 25.0, 50.0]) {
        final p = _steadyWith((s) {
          s.setLever('refluxFlow', (100 + dl) * kmolh);
          s.setLever('boilup', (150 + dl) * kmolh);
        });
        expect(p.xD, greaterThan(prevXd), reason: 'xD at +$dl');
        expect(p.xB, lessThan(prevXb), reason: 'xB at +$dl');
        expect(p.dKmolh, closeTo(50, 0.05));
        prevXd = p.xD;
        prevXb = p.xB;
      }
    });

    test('VC-8.2 raising reflux only: D down, xD up, xB up', () {
      final base = _steadyWith((_) {});
      final up = _steadyWith((s) => s.setLever('refluxFlow', 110 * kmolh));
      expect(up.dKmolh, lessThan(base.dKmolh));
      expect(up.xD, greaterThan(base.xD));
      expect(up.xB, greaterThan(base.xB));
    });

    test('VC-8.3 raising boilup only: D up, boilup KPI up, xD down, xB down',
        () {
      final base = _steadyWith((_) {});
      final up = _steadyWith((s) => s.setLever('boilup', 155 * kmolh));
      expect(up.dKmolh, greaterThan(base.dKmolh));
      expect(up.boilupKmolh, greaterThan(base.boilupKmolh));
      expect(up.boilupKmolh, closeTo(155, 0.01));
      expect(up.xD, lessThan(base.xD));
      expect(up.xB, lessThan(base.xB));
    });

    test('VC-8.4 xD rises monotonically with Murphree efficiency', () {
      var prev = -1.0;
      for (final e in [0.3, 0.5, 0.7, 0.85, 1.0]) {
        final p = _steadyWith((_) {}, overrides: {'murphree': e});
        expect(p.xD, greaterThan(prev), reason: 'E = $e');
        prev = p.xD;
      }
    });

    test('VC-8.5 moving the feed away from the optimum (tray 11) lowers xD',
        () {
      final opt = _steadyWith((s) => s.setLever('feedStage', 11));
      for (final ft in [5, 8, 14, 17]) {
        final p = _steadyWith((s) => s.setLever('feedStage', ft.toDouble()));
        expect(p.xD, lessThan(opt.xD), reason: 'feed tray $ft');
      }
    });

    test(
        'VC-8.6 lighter feed (z 0.6) at fixed L0, VB: xD up, xB up a lot (0.2075)',
        () {
      final base = _steadyWith((_) {});
      final p = _steadyWith((s) => s.setLever('feedZ.benzene', 0.6));
      expect(p.xD, greaterThan(base.xD));
      expect(p.xB, greaterThan(base.xB + 0.15));
      expect(p.xB, closeTo(0.207547, 1e-4));
    });

    test('more trays → better separation at fixed flows', () {
      var prev = -1.0;
      for (final (n, f) in [(10, 5), (20, 10), (30, 15), (40, 20)]) {
        final sim = newSim(
            btConfig(overrides: {'sections[0].trays': n, 'feeds[0].stage': f}));
        // At N = 40 the high-purity slow mode keeps the monitor residual just
        // above 1e-7 for more than 48 h, so do not require `reached` there;
        // the ordering holds regardless.
        final r = sim.runToSteadyState();
        if (n < 40)
          expect(r.reached, isTrue, reason: 'N = $n not steady: ${r.residual}');
        final p = prof(sim);
        expect(p.xD, greaterThan(prev), reason: 'N = $n');
        expect(
            p.xD,
            closeTo(solveNewton(btDefault.copyWith(nTrays: n, feedTray: f)).xD,
                1e-4),
            reason: 'N = $n vs reference');
        prev = p.xD;
      }
    });

    test('feed q: liquid vs vapour feed changes V above the feed by (1−q)F',
        () {
      final p = _steadyWith((s) {
        s.setLever('feedQ', 0.5);
        s.setLever('boilup', 100 * kmolh);
      });
      // VC-4.8: V_B = 100, V above the feed = 150
      expect(toKmolh(p.vaporUp(p.nTrays)), closeTo(100, 0.01));
      expect(toKmolh(p.vaporUp(1)), closeTo(150, 0.01));
      expect(p.xD, closeTo(0.966910, 1e-5));
    });
  });

  group('Bounded, positive state under abuse', () {
    test(
        'lever slams at dt = 0.5: no negative holdups, compositions in [0,1], no NaN',
        () {
      final sim = newSim(btConfig());
      runSteady(sim);
      // slam 1: reflux above the overhead vapour (drum must empty, pump limited)
      sim.setLever('refluxFlow', 250 * kmolh);
      advanceSampling(sim, 1800, 30,
          (t, s) => expectPhysical(s, where: 'slam reflux 250 @ $t'));
      // slam 2: boilup to the max with reflux back to normal (D far above F z)
      sim.setLever('refluxFlow', 100 * kmolh);
      sim.setLever('boilup', 300 * kmolh);
      advanceSampling(sim, 1800, 30,
          (t, s) => expectPhysical(s, where: 'slam boilup 300 @ $t'));
      // slam 3: no boilup at all (column drains into the sump)
      sim.setLever('boilup', 0);
      advanceSampling(
          sim, 1800, 30, (t, s) => expectPhysical(s, where: 'boilup 0 @ $t'));
      // slam 4: no feed
      sim.setLever('boilup', 150 * kmolh);
      sim.setLever('feedFlow', 0);
      advanceSampling(
          sim, 1800, 30, (t, s) => expectPhysical(s, where: 'feed 0 @ $t'));
      expect(sim.solverHealth.negativeClamps, 0,
          reason: 'negative-holdup clamps');
      expect(sim.solverHealth.fatal, isFalse);
    });

    test('same slams at the fast-forward step dt = 2.0 s stay bounded', () {
      final sim = newSim(btConfig(),
          options: const SimOptions(dt: 2.0, dtFastForward: 2.0));
      runSteady(sim);
      for (final (lever, value) in [
        ('refluxFlow', 250.0),
        ('refluxFlow', 100.0),
        ('boilup', 300.0),
        ('boilup', 0.0),
        ('boilup', 150.0),
        ('feedFlow', 0.0),
        ('feedFlow', 100.0),
      ]) {
        sim.setLever(lever, value * kmolh);
        advanceSampling(sim, 1200, 60,
            (t, s) => expectPhysical(s, where: '$lever=$value dt=2 @ $t'));
      }
      expect(sim.solverHealth.fatal, isFalse);
    });

    test(
        'fast-forward from cold with a composition step keeps compositions bounded',
        () {
      final sim = newSim(btConfig(), options: const SimOptions(dt: 2.0));
      sim.setLever('feedZ.benzene', 0.95);
      advanceSampling(sim, 3 * 3600, 300,
          (t, s) => expectPhysical(s, where: 'z=0.95 @ $t'));
      sim.setLever('feedZ.benzene', 0.05);
      advanceSampling(sim, 3 * 3600, 300,
          (t, s) => expectPhysical(s, where: 'z=0.05 @ $t'));
      // extreme feeds: x everywhere between the two feed values eventually
      final p = runSteady(sim);
      expect(p.xD, inInclusiveRange(0.05, 1.0));
      expect(p.xB, inInclusiveRange(0.0, 0.05 + 1e-9));
    });

    test('tray-count rebuild while running keeps the state sane', () {
      final sim = newSim(btConfig());
      runSteady(sim);
      sim.rebuild(sim.config.withTrays(30, feedStage: 15));
      final s = sim.snapshot();
      expect(s.stages.n, 32);
      expectPhysical(s, where: 'after rebuild');
      advanceSampling(
          sim, 600, 60, (t, s) => expectPhysical(s, where: 'post-rebuild $t'));
      final p = runSteady(sim);
      expect(
          p.xD,
          closeTo(solveNewton(btDefault.copyWith(nTrays: 30, feedTray: 15)).xD,
              1e-5));
    });
  });

  group('Steady state is independent of the path taken', () {
    test('cold start, E-detour and slam excursion all land on the same state',
        () {
      final a = newSim(btConfig());
      final pa = runSteady(a);

      final b = newSim(btConfig(overrides: {'murphree': 0.5}));
      runSteady(b);
      b.setLever('murphree', 0.7);
      final pb = runSteady(b);

      final c = newSim(btConfig());
      c.setLever('refluxFlow', 200 * kmolh);
      c.setLever('boilup', 60 * kmolh);
      c.advance(3600);
      c.setLever('refluxFlow', 100 * kmolh);
      c.setLever('boilup', 150 * kmolh);
      final pc = runSteady(c);

      final d = newSim(btConfig());
      d.setLever('feedZ.benzene', 0.8);
      runSteady(d);
      d.setLever('feedZ.benzene', 0.5);
      final pd = runSteady(d);

      for (final (name, p) in [
        ('E-detour', pb),
        ('slam', pc),
        ('z-detour', pd)
      ]) {
        expect(p.xD, closeTo(pa.xD, 1e-6), reason: '$name xD');
        expect(p.xB, closeTo(pa.xB, 1e-6), reason: '$name xB');
        expect(maxAbsDiff(p.s.stages.x, pa.s.stages.x), lessThan(1e-6),
            reason: '$name profile');
        for (var j = 0; j < p.n; j++) {
          expect(p.holdup(j), closeTo(pa.holdup(j), 1e-6 * pa.holdup(j)),
              reason: '$name holdup $j');
        }
      }
    });
  });

  group('Hydraulics in ideal mode', () {
    test('tray holdups and lags are in the Bennett range (~160–200 mol, 1–3 s)',
        () {
      final sim = newSim(btConfig());
      final p = runSteady(sim);
      for (var j = 1; j <= p.nTrays; j++) {
        expect(p.holdup(j), inInclusiveRange(120, 260),
            reason: 'tray $j holdup ${p.holdup(j)} mol');
      }
      // stripping trays hold more liquid than rectifying trays (L is 2×)
      expect(p.holdup(15), greaterThan(p.holdup(5)));
      // liquid flows: L0 above the feed, L0 + F below; V flat
      expect(toKmolh(p.liquidDown(5)), closeTo(100, 0.01));
      expect(toKmolh(p.liquidDown(15)), closeTo(200, 0.01));
      for (var j = 1; j <= p.nTrays + 1; j++) {
        expect(toKmolh(p.vaporUp(j)), closeTo(150, 0.01),
            reason: 'V on stage $j');
      }
    });
  });
}
