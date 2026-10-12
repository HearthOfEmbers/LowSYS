// VC-6 time-step robustness: the steady state is the same for dt = 0.25,
// 0.5, 2, 5, 30 s and for murphreePasses = 1; no negative-holdup clamps, no NaN.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const xDRef = 0.981183, xBRef = 0.018817;

  for (final dt in [0.25, 0.5, 2.0, 5.0, 30.0]) {
    test('VC-6 dt = $dt s gives xD 0.981183 / xB 0.018817 ± 1e-6', () {
      final sim =
          newSim(btConfig(), options: SimOptions(dt: dt, dtFastForward: dt));
      final p = runSteady(sim, fastForward: false);
      expectPhysical(p.s, where: 'dt=$dt');
      expect(p.xD, closeTo(xDRef, 1e-6), reason: 'xD at dt=$dt');
      expect(p.xB, closeTo(xBRef, 1e-6), reason: 'xB at dt=$dt');
      expect(sim.solverHealth.negativeClamps, 0,
          reason: 'negative-holdup clamps');
      expect(sim.solverHealth.fatal, isFalse);
    });
  }

  test('VC-6 murphreePasses = 1 gives the same steady state', () {
    final sim =
        newSim(btConfig(), options: const SimOptions(murphreePasses: 1));
    final p = runSteady(sim);
    expect(p.xD, closeTo(xDRef, 1e-6));
    expect(p.xB, closeTo(xBRef, 1e-6));
  });

  test('VC-6 dt = 2 s transient stays within 1 % of the dt = 0.5 s transient',
      () {
    // PHYSICS.md 12.5: fast-forward transients differ by under 1 % in composition.
    final a = newSim(btConfig(), options: const SimOptions(dt: 0.5));
    final b = newSim(btConfig(), options: const SimOptions(dt: 2.0));
    runSteady(a);
    runSteady(b);
    a.setLever('refluxFlow', 110 * kmolh);
    b.setLever('refluxFlow', 110 * kmolh);
    for (var t = 0; t < 3600; t += 300) {
      a.advance(300);
      b.advance(300);
      final pa = prof(a), pb = prof(b);
      expect(pb.xD, closeTo(pa.xD, 0.01), reason: 'xD at ${t + 300} s');
      expect(pb.xB, closeTo(pa.xB, 0.01), reason: 'xB at ${t + 300} s');
    }
  });
}
