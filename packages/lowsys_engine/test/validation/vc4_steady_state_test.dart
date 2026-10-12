// VC-4: the dynamic steady state equals the independent steady-state
// solution (Newton on the CMO stage balances, plus a shooting method; see
// reference/cmo_steady_reference.dart) and the numbers in VALIDATION.md.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'reference/cmo_steady_reference.dart';
import 'reference/validation_expectations.dart';

Map<String, Object?> _overrides(CmoColumn c) => {
      'sections[0].trays': c.nTrays,
      'feeds[0].stage': c.feedTray,
      'murphree': c.e,
    };

void _applyLevers(Simulator sim, CmoColumn c) {
  sim.setLever('feedFlow', c.f * kmolh);
  sim.setLever('feedZ.benzene', c.z);
  sim.setLever('feedQ', c.q);
  sim.setLever('refluxFlow', c.l0 * kmolh);
  sim.setLever('boilup', c.vB * kmolh);
}

void main() {
  group('VC-4 dynamic steady state matches Newton (Tier 1, ideal hydraulics)',
      () {
    for (final c in vc4) {
      test('VC-${c.id}: xD ${c.xD}, xB ${c.xB}, D ${c.d}', () {
        final sim = newSim(btConfig(overrides: _overrides(c.column)));
        _applyLevers(sim, c.column);
        final p = runSteady(sim);
        expectPhysical(p.s, where: c.id);
        // engine vs VALIDATION.md
        expect(p.xD, closeTo(c.xD, 1e-5), reason: 'xD (doc)');
        expect(p.xB, closeTo(c.xB, 1e-5), reason: 'xB (doc)');
        expect(p.dKmolh, closeTo(c.d, 0.01), reason: 'D kmol/h');
        // engine vs independent reference solved here
        final refN = solveNewton(c.column);
        final refS = solveShooting(c.column);
        expect(refN.xD, closeTo(refS.xD, 1e-9),
            reason: 'reference self-consistency');
        expect(p.xD, closeTo(refN.xD, 1e-5),
            reason: 'xD (Newton ref ${refN.xD})');
        expect(p.xB, closeTo(refN.xB, 1e-5),
            reason: 'xB (Newton ref ${refN.xB})');
        // whole liquid profile, not just the ends
        for (var j = 0; j < p.n; j++) {
          expect(p.x(j), closeTo(refN.x[j], 2e-5), reason: 'x on stage $j');
        }
        // levels at setpoint, balance closed
        expect(p.drumLevel, closeTo(50, 0.01));
        expect(p.sumpLevel, closeTo(50, 0.01));
        expect(balanceResidual(sim), lessThan(1e-6));
      });
    }
  });

  group('VC-4.14 feed-tray scan (E = 0.7)', () {
    for (var i = 0; i < vc414FeedTrays.length; i++) {
      final ft = vc414FeedTrays[i];
      test('VC-4.14 feed tray $ft → xD ${vc414Xd[i]}', () {
        final sim = newSim(btConfig());
        sim.setLever('feedStage', ft.toDouble());
        final p = runSteady(sim);
        expect(p.xD, closeTo(vc414Xd[i], 1e-5));
        expect(p.xD,
            closeTo(solveNewton(btDefault.copyWith(feedTray: ft)).xD, 1e-5));
      });
    }

    test('VC-4.14 optimum is tray 11', () {
      // Direct consequence of the scan: tray 11 beats both neighbours.
      final i11 = vc414FeedTrays.indexOf(11);
      expect(vc414Xd[i11], greaterThan(vc414Xd[i11 - 1]));
      expect(vc414Xd[i11], greaterThan(vc414Xd[i11 + 1]));
    });
  });

  test('VC-4.15 steady cache: warm start reproduces runToSteadyState from cold',
      () {
    final cold = newSim(btConfig(), warmStart: false);
    final pc = runSteady(cold);
    final warm = newSim(btConfig(), warmStart: true);
    final pw = prof(warm);
    expect(maxAbsDiff(pw.s.stages.x, pc.s.stages.x), lessThan(1e-6));
    for (var j = 0; j < pc.n; j++) {
      expect(pw.holdup(j), closeTo(pc.holdup(j), 1e-6 * pc.holdup(j)),
          reason: 'holdup stage $j');
    }
  });
}
