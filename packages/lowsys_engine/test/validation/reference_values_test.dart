// Regression test for the independent reference calculators themselves
// (no engine import): they must keep reproducing the VALIDATION.md numbers
// and the two steady-state methods must agree. `reference/reference_main.dart`
// prints the full comparison; this is the `dart test` form.
library;

import 'package:test/test.dart';

import 'reference/cmo_steady_reference.dart';
import 'reference/mccabe_thiele_reference.dart';
import 'reference/validation_expectations.dart';

void main() {
  group('reference: VC-1', () {
    test('closed-form numbers', () {
      final rMin = rMinFeedPinch(2.5, 0.5, 1.0, 0.95);
      expect(rMin, closeTo(vc1.rMin, 1e-4));
      expect(fenskeNmin(2.5, 0.95, 0.05), closeTo(vc1.nMin, 1e-4));
      final g = gilliland(fenskeNmin(2.5, 0.95, 0.05), 1.5 * rMin, rMin);
      expect(g.n, closeTo(vc1.nMolokanov, 1e-3));
      final s = stepStages(2.5, 0.5, 1.0, 0.95, 0.05, 1.65);
      expect(s.stages, vc1.stages);
      expect(s.fractional, closeTo(vc1.fractionalStages, 1e-3));
      expect(s.feedStage, vc1.feedStage);
      for (var i = 0; i < vc1.stageX.length; i++) {
        expect(s.x[i], closeTo(vc1.stageX[i], 1e-5));
        expect(s.y[i], closeTo(vc1.stageY[i], 1e-5));
      }
    });
  });

  group('reference: VC-4 Newton = shooting = VALIDATION.md', () {
    for (final c in vc4) {
      test(c.id, () {
        final n = solveNewton(c.column);
        final s = solveShooting(c.column);
        expect(n.maxResidual, lessThan(1e-11));
        expect(n.xD, closeTo(s.xD, 1e-9));
        expect(n.xB, closeTo(s.xB, 1e-9));
        expect(n.xD, closeTo(c.xD, 1e-5));
        expect(n.xB, closeTo(c.xB, 1e-5));
        expect(n.d, closeTo(c.d, 1e-9));
        final mb = (c.column.f * c.column.z - n.d * n.xD - n.b * n.xB) /
            (c.column.f * c.column.z);
        expect(mb.abs(), lessThan(1e-12));
      });
    }
    test('4.14 feed scan', () {
      for (var i = 0; i < vc414FeedTrays.length; i++) {
        expect(solveNewton(btDefault.copyWith(feedTray: vc414FeedTrays[i])).xD,
            closeTo(vc414Xd[i], 1e-5),
            reason: 'feed tray ${vc414FeedTrays[i]}');
      }
    });
  });

  test('reference: VC-3.1 Fenske symmetric', () {
    for (final r in vc31) {
      expect(fenskeSymmetricXd(2.5, r.n), closeTo(r.xD, 1e-6));
    }
  });
}
