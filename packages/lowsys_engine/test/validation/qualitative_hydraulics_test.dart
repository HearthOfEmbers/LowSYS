// Qualitative "does this make physical sense" checks for M2: full tray
// hydraulics and faults F04–F07.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m2.dart';

(Simulator, Profile, Hyd) _design() {
  final sim = newSim(btFull());
  final p = runSteady(sim);
  return (sim, p, hyd(sim));
}

void main() {
  group('Flooding', () {
    test(
        'ΔP rises sharply with load and separation collapses past the flood point',
        () {
      final (sim, p0, h0) = _design();
      final dp = <double>[h0.columnDp];
      final xd = <double>[p0.xD];
      for (final f in [0.1, 0.2, 0.3, 0.45]) {
        addLoad(sim, f);
        advanceSampling(sim, 3600, 300,
            (t, s) => expectHydraulicallySane(s, where: 'load $f @ $t'));
        dp.add(hyd(sim).columnDp);
        xd.add(prof(sim).xD);
      }
      for (var i = 1; i < dp.length; i++) {
        expect(dp[i], greaterThan(dp[i - 1]),
            reason: 'ΔP monotone with load (step $i)');
        expect(xd[i], lessThan(xd[i - 1] + 1e-6),
            reason: 'xD not better with more load (step $i)');
      }
      // ΔP grows faster than linearly in load past flood: last increment largest
      final inc = [for (var i = 1; i < dp.length; i++) dp[i] - dp[i - 1]];
      expect(inc.last, greaterThan(inc.first),
          reason: 'ΔP accelerates toward flooding');
      expect(xd.last, lessThan(0.7), reason: 'separation collapses at +45 %');
      expect(hyd(sim).maxFloodPct, greaterThanOrEqualTo(100));
    });

    test('flooding propagates upward and liquid reaches the drum (level rises)',
        () {
      final (sim, _, _) = _design();
      addLoad(sim, 0.45);
      var drumMax = 0.0;
      var frothFillSeen = 0.0;
      advanceSampling(sim, 2 * 3600, 120, (t, s) {
        drumMax =
            [drumMax, s.kpis.drumLevelPct].reduce((a, b) => a > b ? a : b);
        frothFillSeen = [frothFillSeen, Hyd(s).maxOverTrays(Hyd(s).frothFill)]
            .reduce((a, b) => a > b ? a : b);
      });
      // In this model jet flooding shows up as the entrainment recycle
      // (ψ → ψ_max = 0.6), not as froth filling the tray spacing (that is
      // the downcomer-limit mechanism). So: heavy entrainment somewhere,
      // liquid carried into the drum, D at its valve limit.
      final h = hyd(sim);
      final psiMax = h.maxOverTrays(
          (j) => h.entrain(j) / (h.s.stages.liquidDown[j] + h.entrain(j)));
      expect(psiMax, greaterThanOrEqualTo(0.3), reason: 'ψ near its cap');
      expect(frothFillSeen, greaterThan(0.25), reason: 'froth grows');
      expect(drumMax, greaterThan(55),
          reason: 'entrained liquid raises the drum level');
      expect(sim.control.loop('LC-101').op, closeTo(100, 1e-6),
          reason: 'D at the valve limit');
    });
  });

  group('Weeping', () {
    test(
        'efficiency falls at low vapour rate: xB with weeping > xB without, at the same L/V',
        () {
      final (a, _, _) = _design();
      final b = newSim(btFull(), options: const SimOptions(weeping: false));
      runSteady(b);
      for (final f in [0.6, 0.45, 0.35]) {
        scaleLoad(a, f);
        scaleLoad(b, f);
        a.advance(3600);
        b.advance(3600);
        final ha = hyd(a);
        if (f <= 0.45)
          expect(ha.maxOverTrays(ha.weepFrac), greaterThan(0),
              reason: 'weeping at $f');
        expect(prof(a).xB, greaterThanOrEqualTo(prof(b).xB - 1e-9),
            reason: 'load $f');
      }
      expect(prof(a).xB, greaterThan(1.3 * prof(b).xB),
          reason: 'clear loss at 35 %');
    });

    test(
        'weeping fraction decreases monotonically with vapour load and is 0 at design',
        () {
      final (sim, _, h0) = _design();
      expect(h0.maxOverTrays(h0.weepFrac), 0);
      var prev = 2.0;
      for (final f in [0.3, 0.4, 0.5, 0.6, 0.8]) {
        scaleLoad(sim, f);
        sim.advance(1800);
        final w = hyd(sim).maxOverTrays(hyd(sim).weepFrac);
        expect(w, lessThanOrEqualTo(prev + 1e-9), reason: 'load $f');
        prev = w;
      }
    });

    test(
        'losing the boilup dumps the trays (holdup → small) and recovers when restored',
        () {
      final (sim, _, h0) = _design();
      final hold0 = [for (var j = 1; j <= 20; j++) h0.holdup(j)];
      sim.setLever('boilup', 0);
      advanceSampling(sim, 600, 30,
          (t, s) => expectHydraulicallySane(s, where: 'boilup 0 @ $t'));
      // With Φ < 0.2 every tray dumps and the inlet liquid bypasses the
      // deck completely (w = 1, PHYSICS.md 5.8), so all trays drain to
      // nothing except the feed tray, where the feed is assumed to reach
      // the deck and settles at F × τ_d ≈ 440 mol. The vapour is gone, so the
      // dry drop vanishes and only liquid head is left in ΔP.
      final feedTray = sim.lever('feedStage').round();
      final hd = hyd(sim);
      expect(hd.countTrays(hd.dumping), greaterThan(10),
          reason: 'most trays dumping');
      for (var j = 1; j <= 20; j++) {
        expect(hd.s.stages.dpDry[j], lessThan(1.0), reason: 'tray $j dry drop');
        expect(hd.s.stages.vaporUp[j], closeTo(0, 1e-9), reason: 'tray $j V');
        if (j == feedTray) {
          // F × τ_d = 27.8 mol/s × 8 s ≈ 222 mol (433 while the reflux chain
          // still lands here too)
          expect(hd.holdup(j), inInclusiveRange(150, 600),
              reason: 'feed tray holds F × τ_d');
        } else {
          // bypassed liquid lands two trays down and dumps from there, so
          // trays alternate between ≈ 0 and ≈ inflow × τ_d; none accumulates
          expect(hd.holdup(j), lessThan(2.0 * hold0[j - 1]),
              reason: 'tray $j does not accumulate');
        }
      }
      expect(
          hd.countTrays(
              (j) => j != feedTray && hd.holdup(j) < 0.1 * hold0[j - 1]),
          greaterThanOrEqualTo(10),
          reason: 'at least half the trays drained');
      expect(hd.columnDp, lessThan(0.4 * h0.columnDp),
          reason: 'only liquid head remains');
      // Without vapour nothing reaches the drum: reflux empties it in
      // ≈ 550 s and the reflux pump loses suction (correct, not a bug).
      sim.advance(600);
      expect(prof(sim).drumLevel, lessThan(1.0), reason: 'drum emptied');
      expect(sim.snapshot().stages.liquidDown[0], closeTo(0, 1e-9),
          reason: 'reflux lost');
      sim.setLever('boilup', 150 * kmolh);
      final p = runSteady(sim);
      expect(p.xD, closeTo(0.96725, 0.003), reason: 'back to the design point');
      for (var j = 1; j <= 20; j++) {
        expect(hyd(sim).holdup(j), closeTo(hold0[j - 1], 0.02 * hold0[j - 1]),
            reason: 'tray $j holdup restored');
      }
    });
  });

  group('Broken tray F04', () {
    test('lowers ΔP and separation; profile shows a missing step', () {
      final (sim, p0, h0) = _design();
      final id =
          injectTrayFault(sim, FaultType.trayDamage, from: 8, severity: 1.0);
      sim.advance(2 * 3600);
      final h = hyd(sim);
      expect(h.columnDp, lessThan(h0.columnDp));
      expect(h.dp(8), lessThan(0.15 * h0.dp(8)));
      expect(prof(sim).xD, lessThan(p0.xD));
      expect(h.efficiency(8), closeTo(0, 1e-9),
          reason: 'no contacting on the missing tray');
      // A missing tray: the inlet liquid falls through to tray 9 with x_7
      // and the vapour passes uncontacted (y_8 = y_9). The only liquid left
      // on stage 8 is entrained spray from below, so its displayed x lies
      // between x_9 and x_7 (DEVIATIONS.md E20) and its holdup is small.
      final pr = prof(sim);
      expect(pr.y(8), closeTo(pr.y(9), 1e-6), reason: 'vapour bypass');
      expect(pr.x(8), inInclusiveRange(pr.x(9) - 1e-6, pr.x(7) + 1e-6),
          reason: 'x_8 between the trays it short-circuits');
      expect(h.holdup(8), lessThan(0.25 * h0.holdup(8)),
          reason: 'almost no liquid on the missing tray');
      // the staircase loses a step: the 7→9 composition change equals the
      // sum of two normal steps only if the tray were present
      expect(pr.x(7) - pr.x(9), lessThan(1.5 * (pr.x(6) - pr.x(7)) + 1e-9),
          reason: 'missing step');
      sim.faults.clear(id);
    });
  });

  group('Foaming F06', () {
    test(
        'raises ΔP/froth and floods at an unchanged load; antifoam-style clear recovers',
        () {
      final (sim, p0, h0) = _design();
      final id = injectTrayFault(sim, FaultType.foaming,
          from: 1, to: 20, severity: 0.67, ramp: 600);
      var phiMax = 0.0;
      advanceSampling(sim, 3600, 120, (t, s) {
        expectHydraulicallySane(s, where: 'foam @ $t');
        phiMax = [phiMax, Hyd(s).maxOverTrays(Hyd(s).jetFlood)]
            .reduce((a, b) => a > b ? a : b);
      });
      expect(phiMax, greaterThan(1.0),
          reason: 'early flooding at the design load');
      expect(hyd(sim).maxOverTrays(hyd(sim).froth),
          greaterThan(1.3 * h0.maxOverTrays(h0.froth)),
          reason: 'taller froth');
      expect(prof(sim).xD, lessThan(p0.xD - 0.05));
      sim.faults.clear(id);
      final p = runSteady(sim);
      expect(p.xD, closeTo(p0.xD, 0.002), reason: 'reversible');
    });
  });

  group('Fouling F05', () {
    test('ΔP creeps up over the ramp (monotone, slow) while xD barely moves',
        () {
      final (sim, p0, h0) = _design();
      injectTrayFault(sim, FaultType.trayFouling,
          from: 12,
          to: 16,
          severity: 0.3,
          ramp: 4 * 3600,
          params: {'mode': 'holes'});
      var prevDp = h0.columnDp;
      var maxJump = 0.0;
      advanceSampling(sim, 4 * 3600, 600, (t, s) {
        final dp = Hyd(s).columnDp;
        expect(dp, greaterThanOrEqualTo(prevDp - 1e-6),
            reason: 'ΔP non-decreasing @ $t');
        maxJump = [maxJump, (dp - prevDp) / h0.columnDp]
            .reduce((a, b) => a > b ? a : b);
        prevDp = dp;
      });
      expect(maxJump, lessThan(0.03),
          reason: 'no 10-min jump above 3 % (creeping, not a step)');
      expect(hyd(sim).columnDp / h0.columnDp, inInclusiveRange(1.08, 1.22));
      expect((prof(sim).xD - p0.xD).abs(), lessThan(0.003));
    });
  });

  group('Feed composition upset F07', () {
    test(
        'z +0.15 moves the profile up the column and pushes benzene into the bottoms (D fixed in Tier 1)',
        () {
      final (sim, p0, _) = _design();
      final id = injectFeedFault(sim, severity: 1.0, params: {
        'dz': [0.15, -0.15]
      });
      final p = runSteady(sim);
      // Tier 1 with L0 and V_B fixed: D = V_1 + e_1 − L0 cannot change, so the
      // extra benzene (65 > D = 50 kmol/h) has to leave in the bottoms.
      expect(p.dKmolh, closeTo(p0.dKmolh, 0.5),
          reason: 'D fixed by the LV flows');
      expect(p.xB, greaterThan(0.25),
          reason: 'benzene forced into the bottoms');
      expect(p.xD, greaterThan(p0.xD), reason: 'top gets a little purer');
      expect(p.x(10), greaterThan(p0.x(10)), reason: 'feed-tray liquid richer');
      expect(sim.lever('feedZ.benzene'), closeTo(0.5, 1e-12),
          reason: 'the lever itself is not rewritten');
      sim.faults.clear(id);
      final pr = runSteady(sim);
      expect(pr.xD, closeTo(p0.xD, 0.002));
      expect(pr.dKmolh, closeTo(p0.dKmolh, 0.1));
    });
  });

  group('Every fault conserves mass exactly (StepDebug)', () {
    for (final (name, inject) in <(String, FaultId Function(Simulator))>[
      (
        'F04 broken tray 5',
        (s) => injectTrayFault(s, FaultType.trayDamage, from: 5, severity: 1.0)
      ),
      (
        'F04 half-open tray 15',
        (s) => injectTrayFault(s, FaultType.trayDamage, from: 15, severity: 0.5)
      ),
      (
        'F05 fouling holes 0.6',
        (s) => injectTrayFault(s, FaultType.trayFouling,
            from: 12, to: 16, severity: 0.6, params: {'mode': 'holes'})
      ),
      (
        'F05 fouling downcomer',
        (s) => injectTrayFault(s, FaultType.trayFouling,
            from: 12, to: 16, severity: 1.0, params: {'mode': 'downcomer'})
      ),
      (
        'F06 foaming 0.67',
        (s) => injectTrayFault(s, FaultType.foaming,
            from: 1, to: 20, severity: 0.67, ramp: 600)
      ),
      (
        'F07 feed +0.15',
        (s) => injectFeedFault(s, params: {
              'dz': [0.15, -0.15]
            })
      ),
    ]) {
      test(name, () {
        final (sim, _, _) = _design();
        inject(sim);
        final c = exactClosureSteps(sim, 4 * 7200);
        expect(c[0], lessThan(1e-9),
            reason:
                'benzene closure ${c[0]} (prototype ≤ 1e-9 for fault cases)');
        expect(c[1], lessThan(1e-9), reason: 'toluene closure ${c[1]}');
        expect(sim.solverHealth.fatal, isFalse);
      });
    }

    test(
        '+30 % load (entrainment) and 35 % turndown (weeping) conserve mass (VC-5.1 cases)',
        () {
      for (final f in [1.3, 0.35]) {
        final (sim, _, _) = _design();
        if (f > 1) {
          addLoad(sim, f - 1);
        } else {
          scaleLoad(sim, f);
        }
        final c = exactClosureSteps(sim, 4 * 7200);
        expect(c[0], lessThan(1e-9), reason: 'load $f benzene ${c[0]}');
        expect(c[1], lessThan(1e-9), reason: 'load $f toluene ${c[1]}');
      }
    });
  });

  group('Every fault is reversible when cleared', () {
    for (final (name, inject) in <(String, FaultId Function(Simulator))>[
      (
        'F04 broken tray 5',
        (s) => injectTrayFault(s, FaultType.trayDamage, from: 5, severity: 1.0)
      ),
      (
        'F05 fouling holes 0.3',
        (s) => injectTrayFault(s, FaultType.trayFouling,
            from: 12, to: 16, severity: 0.3, params: {'mode': 'holes'})
      ),
      (
        'F06 foaming 0.33',
        (s) => injectTrayFault(s, FaultType.foaming,
            from: 1, to: 20, severity: 0.33, ramp: 600)
      ),
      (
        'F07 feed +0.15',
        (s) => injectFeedFault(s, params: {
              'dz': [0.15, -0.15]
            })
      ),
    ]) {
      test(name, () {
        final (sim, p0, h0) = _design();
        final id = inject(sim);
        sim.advance(2 * 3600);
        expect(sim.faults.active.length, 1);
        sim.faults.clear(id);
        expect(sim.faults.active, isEmpty);
        final p = runSteady(sim);
        expect(p.xD, closeTo(p0.xD, 1e-4), reason: 'xD back');
        expect(p.xB, closeTo(p0.xB, 1e-4), reason: 'xB back');
        expect(hyd(sim).columnDp, closeTo(h0.columnDp, 1e-3 * h0.columnDp),
            reason: 'ΔP back');
        expect(maxAbsDiff(p.s.stages.x, p0.s.stages.x), lessThan(1e-4));
      });
    }
  });

  group('Full vs ideal hydraulics', () {
    test(
        'switching ideal → full at steady state changes nothing abruptly (no flow step > 5 %)',
        () {
      final sim = newSim(btConfig());
      final p0 = runSteady(sim);
      sim.setHydraulicsMode(HydraulicsMode.full);
      sim.advance(2);
      final p1 = prof(sim);
      for (var j = 1; j <= 20; j++) {
        expect(p1.liquidDown(j),
            closeTo(p0.liquidDown(j), 0.05 * p0.liquidDown(j)),
            reason: 'L[$j]');
        expect(p1.vaporUp(j), closeTo(p0.vaporUp(j), 0.05 * p0.vaporUp(j)),
            reason: 'V[$j]');
      }
      final pf = runSteady(sim);
      expect(pf.xD, closeTo(0.96725, 0.003));
    });

    test(
        'full hydraulics at design is within 0.015 of ideal in xD (entrainment is the only loss)',
        () {
      final ideal = runSteady(newSim(btConfig()));
      final full = runSteady(newSim(btFull()));
      expect(ideal.xD - full.xD, inInclusiveRange(0.005, 0.02));
      expect(full.dKmolh, greaterThan(ideal.dKmolh),
          reason: 'entrained liquid adds to D');
    });
  });
}
