// Engine-free regression of the M3 reference calculators against the
// VALIDATION.md numbers (`reference_main_m3.dart` prints the full set).
library;

import 'package:test/test.dart';

import 'reference/cmo_steady_reference.dart';
import 'reference/instrument_reference.dart';
import 'reference/pid_reference.dart';
import 'reference/prng_reference.dart';
import 'reference/validation_expectations.dart';
import 'reference/validation_expectations_m3.dart';

void main() {
  test('reference: VC-16.1 PID', () {
    final p = RefPid(kc: 2, ti: 10, action: RefAction.direct, sp: 50, op: 50);
    p.execute(50, 1);
    expect(p.execute(51, 1), closeTo(vc161.op1, 1e-12));
    for (var k = 2; k <= 10; k++) {
      p.execute(51, 1);
    }
    expect(p.op, closeTo(vc161.op10, 1e-12));
  });
  test('reference: VC-16.4 flow loop t63 3.0 s', () {
    final ft = Transmitter(ft102, 100);
    final pid = RefPid(
        kc: 0.6,
        ti: 2.0,
        action: RefAction.reverse,
        lo: 0,
        hi: 300,
        sp: 100,
        op: 100 / 3);
    final loop =
        RefFlowLoop(valve: RefValve(300, 100 / 3), ft: ft, pid: pid, flow: 100);
    for (var k = 0; k < 100; k++) {
      loop.subStep();
    }
    loop.pid.setSp(110);
    double? t63;
    for (var k = 1; k <= 100; k++) {
      loop.subStep();
      t63 ??= loop.flow - 100 >= 6.3 ? k * 0.1 : null;
      if (k == 30) expect(loop.flow, closeTo(106.432, 0.01));
    }
    expect(t63, closeTo(3.0, 0.1));
  });
  test('reference: VC-20.3 PRNG vectors', () {
    expect(fnv1a32('FT-102'), vc203.fnvFt102);
    final g = Xoshiro128ss.stream(1, 'FT-102');
    for (final v in vc203.next32) {
      expect(g.next32(), v);
    }
    final g2 = Xoshiro128ss.stream(1, 'FT-102');
    expect(g2.uniform(), closeTo(vc203.uniform, 1e-15));
    expect(g2.normal(), closeTo(vc203.normal1, 1e-15));
  });
  test('reference: VC-26.4 G6 rows (independent CMO Newton and shooting, E 0.5)',
      () {
    for (final (n, feed, xd) in vc264G6) {
      // the feed tray of a rebuild from 20 / 10 (PHYSICS.md §13.4)
      expect(feed, (0.5 * n + 1e-9).floor());
      final col = btDefault.copyWith(nTrays: n, feedTray: feed, e: 0.5);
      expect(solveNewton(col).xD, closeTo(xd, 1e-4), reason: 'N $n');
      expect(solveShooting(col).xD, closeTo(xd, 1e-4), reason: 'N $n');
    }
    // the old round-half-up feed tray 14 at N 27 misses the G6 row
    expect(
        solveNewton(btDefault.copyWith(nTrays: 27, feedTray: 14, e: 0.5)).xD,
        isNot(closeTo(0.97761, 1e-4)));
  });
  test('reference: σ_disp table', () {
    expect(ft102.sigmaDisp, closeTo(0.409, 0.001));
    expect(lt101.sigmaDisp, closeTo(0.423, 0.001));
    expect(lt102.sigmaDisp, closeTo(0.775, 0.001));
    expect(pt101.sigmaDisp, closeTo(0.046, 0.001));
    expect(pdt101.sigmaDisp, closeTo(0.845, 0.001));
    expect(tiTray.sigmaDisp, closeTo(0.062, 0.001));
  });
}
