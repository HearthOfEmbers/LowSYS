// VC-18 McCabe–Thiele data invariants (M1 parts: 18.1, 18.2, 18.4 Tier 1,
// 18.5) plus the staircase-ordering sanity check.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'reference/mccabe_thiele_reference.dart' as ref;

McCabeThieleData _build(Simulator sim, {bool showRmin = false}) {
  final thermo = ThermoFactory.build(sim.config, ThermoTier.t1);
  return McCabeThieleBuilder()
      .build(sim.snapshot(), thermo, showRmin: showRmin);
}

/// Point on a 2-point line segment at x.
double _lineY(List<Point2> line, double x) {
  final (a, b) = (line[0], line[1]);
  return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
}

void main() {
  group('VC-18.1 Tier 1, E = 1 (VC-4.2 steady state)', () {
    late Simulator sim;
    late Profile p;
    late McCabeThieleData mt;
    setUpAll(() {
      sim = newSim(btConfig(overrides: {'murphree': 1.0}));
      p = runSteady(sim);
      mt = _build(sim);
    });

    test('operating-locus points lie on the CMO lines (1e-8)', () {
      final feed = sim.lever('feedStage').round();
      expect(mt.operatingLocus.length, p.nTrays + 1,
          reason: '(x_j, y_{j+1}) for j = 0..N');
      for (var j = 0; j <= p.nTrays; j++) {
        final pt = mt.operatingLocus[j];
        final line = j < feed ? mt.cmoRectifying : mt.cmoStripping;
        expect(pt.y, closeTo(_lineY(line, pt.x), 1e-8), reason: 'stage $j');
      }
    });

    test('staircase corners lie on the equilibrium curve (1e-8)', () {
      for (final c in mt.corners) {
        expect(c.y, closeTo(ref.yEq(c.x, 2.5), 1e-8),
            reason: 'stage ${c.stage}');
      }
    });

    test('the CMO lines intersect on the q-line (1e-8)', () {
      // q = 1: the q-line is vertical at x = z, so both lines pass x = z at
      // the same y.
      final z = sim.lever('feedZ.benzene');
      final yr = _lineY(mt.cmoRectifying, z);
      final ys = _lineY(mt.cmoStripping, z);
      expect(yr, closeTo(ys, 1e-8));
      expect(mt.qLine, isNotNull);
      expect(mt.qLine!.a.x, closeTo(z, 1e-12));
      expect(mt.qLine!.b.x, closeTo(z, 1e-12));
    });

    test('markers', () {
      expect(mt.xF, closeTo(0.5, 1e-12));
      expect(mt.xD, closeTo(p.xD, 1e-12));
      expect(mt.xB, closeTo(p.xB, 1e-12));
      expect(mt.pseudoBinary, isFalse);
    });
  });

  group('VC-18.2 Tier 1, E = 0.7 (VC-4.1 steady state)', () {
    late Simulator sim;
    late Profile p;
    late McCabeThieleData mt;
    setUpAll(() {
      sim = newSim(btConfig());
      p = runSteady(sim);
      mt = _build(sim);
    });

    test(
        'corners lie on the pseudo-equilibrium curve y_op + 0.7 (y* − y_op) (1e-6)',
        () {
      final feed = sim.lever('feedStage').round();
      for (final c in mt.corners) {
        if (c.stage < 1 || c.stage > p.nTrays)
          continue; // reboiler is an equilibrium stage
        final line = c.stage < feed ? mt.cmoRectifying : mt.cmoStripping;
        final yOp = _lineY(line, c.x);
        final yPe = yOp + 0.7 * (ref.yEq(c.x, 2.5) - yOp);
        expect(c.y, closeTo(yPe, 1e-6), reason: 'stage ${c.stage}');
      }
    });

    test('(y_j − y_{j+1})/(y*_j − y_{j+1}) = 0.7 on every tray (1e-8)', () {
      for (var j = 1; j <= p.nTrays; j++) {
        final ratio = (p.y(j) - p.y(j + 1)) / (p.yStar(j) - p.y(j + 1));
        expect(ratio, closeTo(0.7, 1e-8), reason: 'tray $j');
      }
    });

    test('reboiler is an equilibrium stage: y_{N+1} = y*(x_{N+1})', () {
      final n1 = p.nTrays + 1;
      expect(p.y(n1), closeTo(ref.yEq(p.x(n1), 2.5), 1e-10));
      expect(p.yStar(n1), closeTo(ref.yEq(p.x(n1), 2.5), 1e-10));
    });

    test('staircase polyline has the PHYSICS.md 14.1 shape', () {
      // (x_0,x_0) → (x_0,y_1) → (x_1,y_1) → (x_1,y_2) → … → (x_{N+1},y_{N+1}) → (x_{N+1},x_{N+1})
      final st = mt.staircase;
      expect(st.first.x, closeTo(p.x(0), 1e-12));
      expect(st.first.y, closeTo(p.x(0), 1e-12));
      expect(st.last.x, closeTo(p.x(p.n - 1), 1e-12));
      expect(st.last.y, closeTo(p.x(p.n - 1), 1e-12));
      // every segment is horizontal or vertical
      for (var i = 1; i < st.length; i++) {
        final dx = (st[i].x - st[i - 1].x).abs();
        final dy = (st[i].y - st[i - 1].y).abs();
        expect(dx < 1e-12 || dy < 1e-12, isTrue,
            reason: 'segment $i is diagonal');
      }
      expect(mt.corners.length, p.nTrays + 1,
          reason: 'one corner per tray + reboiler');
    });
  });

  group('Staircase ordering (physical sense)', () {
    test(
        'corners sit between the operating locus and the equilibrium curve, x decreasing',
        () {
      final sim = newSim(btConfig());
      final p = runSteady(sim);
      final feed = sim.lever('feedStage').round();
      for (var j = 1; j <= p.nTrays; j++) {
        // x_j ≤ y_{j+1} ≤ y_j ≤ y*(x_j): operating line above the diagonal,
        // Murphree point between the operating line and equilibrium.
        expect(p.y(j + 1), greaterThanOrEqualTo(p.x(j) - 1e-12),
            reason: 'op line below diagonal, tray $j');
        expect(p.y(j), greaterThanOrEqualTo(p.y(j + 1) - 1e-12),
            reason: 'y_j < y_{j+1}, tray $j');
        expect(p.yStar(j), greaterThanOrEqualTo(p.y(j) - 1e-12),
            reason: 'y_j above equilibrium, tray $j');
        if (j != feed) {
          expect(p.x(j), lessThanOrEqualTo(p.x(j - 1) + 1e-12),
              reason: 'x rises on tray $j (not the feed tray)');
        }
      }
      expect(p.x(0), greaterThan(p.x(p.n - 1)));
    });

    test('ordering holds during a transient too (reflux slam)', () {
      final sim = newSim(btConfig());
      runSteady(sim);
      sim.setLever('refluxFlow', 140 * kmolh);
      advanceSampling(sim, 1800, 60, (t, s) {
        final p = Profile(s);
        for (var j = 1; j <= p.nTrays; j++) {
          expect(p.y(j),
              greaterThanOrEqualTo(math.min(p.y(j + 1), p.yStar(j)) - 1e-9),
              reason: 'tray $j at $t s');
          expect(p.y(j),
              lessThanOrEqualTo(math.max(p.y(j + 1), p.yStar(j)) + 1e-9),
              reason: 'tray $j at $t s');
        }
      });
    });
  });

  group('VC-18.4 R_min construction', () {
    test('McCabeThieleMath.rMin for the VC-1 configuration = 1.1000', () {
      expect(McCabeThieleMath.rMin(2.5, 0.5, 1.0, 0.95), closeTo(1.1, 1e-4));
    });

    test('builder R_min at the default steady state equals the scan reference',
        () {
      final sim = newSim(btConfig());
      final p = runSteady(sim);
      final mt = _build(sim, showRmin: true);
      expect(mt.rmin, isNotNull);
      final expected = ref.rMinScan(2.5, 0.5, 1.0, p.xD);
      expect(mt.rmin!.rMin, closeTo(expected, 1e-4));
      // and the column runs above minimum reflux
      expect(sim.snapshot().kpis.refluxRatio, greaterThan(mt.rmin!.rMin));
    });
  });

  group('VC-18.5 transient flag', () {
    test('false at steady state, true in the first minute after a lever change',
        () {
      final sim = newSim(btConfig());
      runSteady(sim);
      expect(_build(sim).transient, isFalse);
      sim.setLever('refluxFlow', 105 * kmolh);
      sim.advance(30);
      expect(_build(sim).transient, isTrue);
    });
  });
}
