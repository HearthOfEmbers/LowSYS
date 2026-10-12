import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group(
      'VC-1 McCabe-Thiele textbook problem (alpha 2.5, z 0.5, q 1, xD 0.95, xB 0.05)',
      () {
    const a = 2.5, z = 0.5, xd = 0.95, xb = 0.05;
    test('pinch, Rmin, Fenske, Gilliland', () {
      final p = McCabeThieleMath.qLinePinch(a, z, 1);
      expect(p.x, closeTo(0.5, 1e-5));
      expect(p.y, closeTo(0.71429, 1e-5));
      final rmin = McCabeThieleMath.rMin(a, z, 1, xd);
      expect(rmin, closeTo(1.1, 1e-4));
      final nmin = McCabeThieleMath.fenskeNmin(a, xd, xb);
      expect(nmin, closeTo(6.4269, 1e-4));
      final g = McCabeThieleMath.gilliland(nmin, 1.5 * rmin, rmin);
      expect(g.x, closeTo(0.20755, 1e-5));
      expect(g.y, closeTo(0.45404, 1e-5));
      expect(g.n, closeTo(12.603, 1e-3));
      expect(
          McCabeThieleMath.gilliland(nmin, 1.5 * rmin, rmin, eduljee: true).n,
          closeTo(12.319, 1e-3));
    });
    test('stage stepping reproduces the table', () {
      final r = McCabeThieleMath.stepStages(a, z, 1, xd, xb, 1.65);
      expect(r.count, 12);
      expect(r.fractional, closeTo(11.675, 1e-3));
      expect(r.feedStage, 6);
      const xs = [
        0.88372,
        0.79931,
        0.70424,
        0.61093,
        0.53093,
        0.46991,
        0.40345,
        0.31676,
        0.22276,
        0.13924,
        0.07717,
        0.03691
      ];
      const ys = [
        0.95000,
        0.90873,
        0.85617,
        0.79698,
        0.73888,
        0.68907,
        0.62836,
        0.53683,
        0.41742,
        0.28795,
        0.17291,
        0.08742
      ];
      for (var i = 0; i < 12; i++) {
        expect(r.stages[i].x, closeTo(xs[i], 1e-5), reason: 'x$i');
        expect(r.stages[i].y, closeTo(ys[i], 1e-5), reason: 'y$i');
      }
    });
  });

  test('VC-2 feed condition variants', () {
    const a = 2.5, z = 0.5, xd = 0.95, xb = 0.05;
    final cases = [
      (1.2, 0.54112, 0.74671, 0.9888, 12.785, 12, 11.798),
      (1.0, 0.5, 0.71429, 1.1, 12.603, 12, 11.675),
      (0.5, 0.38743, 0.61257, 1.4987, 12.140, 11, 10.946),
      (0.0, 0.28571, 0.5, 2.1, 11.736, 10, 9.950),
    ];
    for (final c in cases) {
      final p = McCabeThieleMath.qLinePinch(a, z, c.$1);
      expect(p.x, closeTo(c.$2, 1e-5), reason: 'q ${c.$1}');
      expect(p.y, closeTo(c.$3, 1e-5));
      final rmin = McCabeThieleMath.rMin(a, z, c.$1, xd);
      expect(rmin, closeTo(c.$4, 1e-4));
      final n = McCabeThieleMath.gilliland(
              McCabeThieleMath.fenskeNmin(a, xd, xb), 1.5 * rmin, rmin)
          .n;
      expect(n, closeTo(c.$5, 1e-3));
      final st = McCabeThieleMath.stepStages(a, z, c.$1, xd, xb, 1.5 * rmin);
      expect(st.count, c.$6);
      expect(st.fractional, closeTo(c.$7, 1e-3));
      expect(st.feedStage, 6);
    }
  });

  test('VC-3.1 Fenske identity values', () {
    double xdFor(int n) {
      // (xD / (1 - xD))^2 = alpha^n for xB = 1 - xD
      final s = math.sqrt(math.pow(2.5, n) as double);
      return s / (1 + s);
    }

    expect(xdFor(6), closeTo(0.939850, 1e-6));
    expect(xdFor(10), closeTo(0.989864, 1e-6));
    expect(xdFor(20), closeTo(0.999895, 1e-6));
  });

  test('Lewis relation round trip', () {
    expect(McCabeThieleMath.lewisEmv(McCabeThieleMath.lewisEo(0.7, 1.4), 1.4),
        closeTo(0.7, 1e-12));
    expect(McCabeThieleMath.lewisEo(0.7, 1.0), 0.7);
  });

  group('VC-18 builder invariants', () {
    final builder = McCabeThieleBuilder();

    test(
        '18.1 E = 1 steady state: locus on CMO lines, corners on the equilibrium curve',
        () {
      final sim =
          btSteady({}, config: Presets.byId('bt').copyWith(murphree: 1.0));
      final snap = sim.snapshot();
      final d = builder.build(snap, sim.thermo);
      final sR = (d.cmoRectifying[1].y - d.cmoRectifying[0].y) /
          (d.cmoRectifying[1].x - d.cmoRectifying[0].x);
      final sS = (d.cmoStripping[1].y - d.cmoStripping[0].y) /
          (d.cmoStripping[1].x - d.cmoStripping[0].x);
      final feed = snap.layout.feedStages.first;
      for (var j = 0; j < d.operatingLocus.length; j++) {
        final p = d.operatingLocus[j];
        final onRect =
            (p.y - (d.cmoRectifying[0].y + sR * (p.x - d.cmoRectifying[0].x)))
                .abs();
        final onStrip =
            (p.y - (d.cmoStripping[0].y + sS * (p.x - d.cmoStripping[0].x)))
                .abs();
        if (j < feed) {
          expect(onRect, lessThan(1e-8), reason: 'locus $j');
        } else {
          expect(onStrip, lessThan(1e-8), reason: 'locus $j');
        }
      }
      for (final c in d.corners) {
        expect((c.y - McCabeThieleMath.yEq(c.x, 2.5)).abs(), lessThan(1e-8),
            reason: 'corner ${c.stage}');
      }
      expect(d.operatingIntersection.x, closeTo(0.5, 1e-8));
      expect(d.transient, isFalse);
    });

    test(
        '18.2 E = 0.7: exact Murphree ratio on every tray; pseudo-equilibrium curve',
        () {
      final sim = btSim();
      final snap = sim.snapshot();
      final d = builder.build(snap, sim.thermo);
      final st = snap.stages;
      for (var j = 1; j <= snap.layout.nTrays; j++) {
        final r = (st.y[j * 2] - st.y[(j + 1) * 2]) /
            (st.yStar[j * 2] - st.y[(j + 1) * 2]);
        expect(r, closeTo(0.7, 1e-8), reason: 'tray $j');
      }
      expect(d.pseudoEquilibrium.length, 101);
      // corners (x_j, y_j) lie on y_op + E (y* - y_op) with y_op the CMO operating line at x_j
      final sR = (d.cmoRectifying[1].y - d.cmoRectifying[0].y) /
          (d.cmoRectifying[1].x - d.cmoRectifying[0].x);
      final sS = (d.cmoStripping[1].y - d.cmoStripping[0].y) /
          (d.cmoStripping[1].x - d.cmoStripping[0].x);
      final feed = snap.layout.feedStages.first;
      for (final c in d.corners.take(snap.layout.nTrays)) {
        final j = c.stage;
        final yop = j < feed
            ? d.cmoRectifying[0].y + sR * (c.x - d.cmoRectifying[0].x)
            : d.cmoStripping[0].y + sS * (c.x - d.cmoStripping[0].x);
        final pe = yop + 0.7 * (McCabeThieleMath.yEq(c.x, 2.5) - yop);
        expect((c.y - pe).abs(), lessThan(1e-6), reason: 'tray $j');
      }
    });

    test('18.5 transient flag after a lever change', () {
      final sim = btSim();
      sim.setLever('refluxFlow', kmolh(105));
      sim.advance(30);
      expect(builder.build(sim.snapshot(), sim.thermo).transient, isTrue);
    });

    test('staircase size, corners, Rmin construction and q-line', () {
      final sim = btSim();
      final snap = sim.snapshot();
      final d = builder.build(snap, sim.thermo, showRmin: true);
      expect(d.corners.length, 21);
      expect(d.staircase.length, 2 * 21 + 2);
      expect(d.rmin, isNotNull);
      expect(d.rmin!.rMin,
          closeTo(McCabeThieleMath.rMin(2.5, 0.5, 1, d.xD), 2e-3));
      expect(d.xF, 0.5);
      expect(d.qLine!.b.x, closeTo(0.5, 1e-12));
    });
  });
}
