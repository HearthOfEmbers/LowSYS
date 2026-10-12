// VC-1 / VC-2 / VC-3.1: the engine's closed-form McCabe–Thiele utilities
// against the independent reference formulas and the VALIDATION.md numbers.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/mccabe_thiele_reference.dart' as ref;
import 'reference/validation_expectations.dart';

void main() {
  const alpha = 2.5, z = 0.5, xD = 0.95, xB = 0.05;

  group('VC-1 McCabe–Thiele textbook problem (q = 1)', () {
    test('VC-1 equilibrium curve y* = αx/(1+(α−1)x)', () {
      for (var i = 0; i <= 20; i++) {
        final x = i / 20;
        expect(
            McCabeThieleMath.yEq(x, alpha), closeTo(ref.yEq(x, alpha), 1e-12));
      }
      expect(McCabeThieleMath.yEq(0.5, alpha), closeTo(vc1.pinchY, 1e-5));
    });

    test('VC-1 q-line pinch', () {
      final p = McCabeThieleMath.qLinePinch(alpha, z, 1.0);
      expect(p.x, closeTo(vc1.pinchX, 1e-5));
      expect(p.y, closeTo(vc1.pinchY, 1e-5));
    });

    test('VC-1 R_min = 1.1000', () {
      expect(McCabeThieleMath.rMin(alpha, z, 1.0, xD), closeTo(vc1.rMin, 1e-4));
      expect(McCabeThieleMath.rMin(alpha, z, 1.0, xD),
          closeTo(ref.rMinFeedPinch(alpha, z, 1.0, xD), 1e-10));
    });

    test('VC-1 Fenske N_min = 6.4269 (stages incl. reboiler)', () {
      expect(
          McCabeThieleMath.fenskeNmin(alpha, xD, xB), closeTo(vc1.nMin, 1e-4));
    });

    test('VC-1 Gilliland–Molokanov and Eduljee', () {
      final rMin = McCabeThieleMath.rMin(alpha, z, 1.0, xD);
      final nMin = McCabeThieleMath.fenskeNmin(alpha, xD, xB);
      final r = 1.5 * rMin;
      expect(r, closeTo(vc1.r, 1e-12));
      final g = McCabeThieleMath.gilliland(nMin, r, rMin);
      expect(g.x, closeTo(vc1.gillilandX, 1e-5));
      expect(g.y, closeTo(vc1.molokanovY, 1e-5));
      expect(g.n, closeTo(vc1.nMolokanov, 1e-3));
      final e = McCabeThieleMath.gilliland(nMin, r, rMin, eduljee: true);
      expect(e.n, closeTo(vc1.nEduljee, 1e-3));
    });

    test('VC-1 stage stepping from the top, optimal feed switch', () {
      final s = McCabeThieleMath.stepStages(alpha, z, 1.0, xD, xB, vc1.r);
      expect(s.count, vc1.stages, reason: 'integer stage count');
      expect(s.fractional, closeTo(vc1.fractionalStages, 1e-3));
      expect(s.feedStage, vc1.feedStage);
      for (var i = 0; i < vc1.stageX.length; i++) {
        expect(s.stages[i].x, closeTo(vc1.stageX[i], 1e-5),
            reason: 'stage ${i + 1} x');
        expect(s.stages[i].y, closeTo(vc1.stageY[i], 1e-5),
            reason: 'stage ${i + 1} y');
      }
      // stripping/rectifying slopes
      final rr = ref.stepStages(alpha, z, 1.0, xD, xB, vc1.r);
      expect(rr.lOverV, closeTo(vc1.lOverV, 1e-5));
      expect(rr.lbarOverVbar, closeTo(vc1.lbarOverVbar, 1e-5));
    });
  });

  group('VC-2 feed condition variants', () {
    for (final row in vc2) {
      test('VC-2 q = ${row.q}', () {
        final p = McCabeThieleMath.qLinePinch(alpha, z, row.q);
        expect(p.x, closeTo(row.pinchX, 1e-5));
        expect(p.y, closeTo(row.pinchY, 1e-5));
        final rMin = McCabeThieleMath.rMin(alpha, z, row.q, xD);
        expect(rMin, closeTo(row.rMin, 1e-4));
        final nMin = McCabeThieleMath.fenskeNmin(alpha, xD, xB);
        expect(McCabeThieleMath.gilliland(nMin, 1.5 * rMin, rMin).n,
            closeTo(row.nMolokanov, 1e-3));
        final s =
            McCabeThieleMath.stepStages(alpha, z, row.q, xD, xB, 1.5 * rMin);
        expect(s.count, row.stages);
        expect(s.fractional, closeTo(row.fractional, 1e-3));
        expect(s.feedStage, row.feedStage);
      });
    }

    test('VC-2 q-line passes through (z, z); q = 0.5 gives y = −x + 1', () {
      // slope q/(q−1) = −1 at q = 0.5, intercept −z/(q−1) = 1
      final p = McCabeThieleMath.qLinePinch(alpha, z, 0.5);
      expect(p.y, closeTo(-p.x + 1, 1e-12));
    });
  });

  group('VC-3.1 Fenske identity (symmetric total reflux)', () {
    for (final row in vc31) {
      test('VC-3.1 N_s = ${row.n} → x_D = ${row.xD}', () {
        // Invert Fenske: with x_B = 1 − x_D the identity gives x_D directly.
        final xd = ref.fenskeSymmetricXd(alpha, row.n);
        expect(xd, closeTo(row.xD, 1e-6));
        // and the engine's Fenske recovers N_s from it
        expect(McCabeThieleMath.fenskeNmin(alpha, xd, 1 - xd),
            closeTo(row.n, 1e-6));
      });
    }
  });

  test('VC-1 Lewis E_O ↔ E_MV round trip', () {
    for (final (lambda, emv, eo) in [
      (0.5, 0.5, 0.41504),
      (1.5, 0.7, 0.74015),
      (2.0, 0.5, 0.58496)
    ]) {
      expect(McCabeThieleMath.lewisEo(emv, lambda), closeTo(eo, 1e-5));
      expect(
          McCabeThieleMath.lewisEmv(
              McCabeThieleMath.lewisEo(emv, lambda), lambda),
          closeTo(emv, 1e-9));
    }
  });
}
