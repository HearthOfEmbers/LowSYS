// Engine-free regression of the M4 reference calculators: the VC-10 spot
// values, the VC-11 MESH steady state, VC-27.1 and this reference's own
// VC-27.2 sweep values (the doc's sweep T columns are inconsistent with its
// x columns; see reference_main_m4.dart).
library;

import 'package:test/test.dart';

import 'reference/cmo_steady_reference.dart';
import 'reference/thermo_reference.dart';
import 'reference/tier2_steady_reference.dart';
import 'reference/validation_expectations_m4.dart';

const kmolh = 1000 / 3600;

void main() {
  test('reference: VC-10.1 / 10.3 spot values', () {
    expect(benzene.tbModel() - 273.15, closeTo(80.100, 0.005));
    expect(toluene.tbModel() - 273.15, closeTo(110.625, 0.005));
    expect(water.tbModel() - 273.15, closeTo(100.018, 0.005));
    final t = bt.bubbleT(atm, 0.5);
    expect(t - 273.15, closeTo(92.112, 0.002));
    expect(bt.alpha(t), closeTo(2.4920, 1e-4));
    expect(bt.alpha(bt.bubbleT(2e5, 0.5)), closeTo(2.3040, 1e-4));
  });

  test('reference: VC-11 MESH steady state', () {
    const col = Tier2Column(
        sys: bt,
        nTrays: 20,
        feedTray: 10,
        f: 100 * kmolh,
        z: 0.5,
        l0: 100 * kmolh,
        d: 50 * kmolh,
        p: atm,
        e: 1.0);
    final guess = solveNewton(const CmoColumn(
            alpha: 2.5,
            nTrays: 20,
            feedTray: 10,
            f: 100,
            z: 0.5,
            q: 1,
            l0: 100,
            vB: 141,
            e: 1.0))
        .x;
    final r = solveTier2(col, xGuess: guess);
    expect(r.maxResidual, lessThan(1e-9));
    expect(r.xD, closeTo(vc11.xD, 5e-5));
    expect(r.xB, closeTo(vc11.xB, 5e-5));
    expect(r.qR / 1000, closeTo(vc11.qR, 1.5));
    expect(r.v[21] / kmolh, closeTo(vc11.vB, 0.15));
    expect(r.l[10] / kmolh, closeTo(vc11.l10, 0.2));
    expect(energyClosure(col, r), lessThan(1.0));
  });

  test('reference: VC-27.1 methanol–water', () {
    const col = Tier2Column(
        sys: mw,
        nTrays: 20,
        feedTray: 12,
        f: 100 * kmolh,
        z: 0.3,
        l0: 60 * kmolh,
        d: 30 * kmolh,
        p: atm,
        e: 0.7);
    final guess = solveNewton(const CmoColumn(
            alpha: 3.5,
            nTrays: 20,
            feedTray: 12,
            f: 100,
            z: 0.3,
            q: 1,
            l0: 60,
            vB: 80,
            e: 0.7))
        .x;
    final r = solveTier2(col, xGuess: guess);
    expect(r.qR / 1000, closeTo(vc271.qR, 2.7));
    expect(r.xD, closeTo(vc271.xD, 1e-4));
    expect(r.v[21] / kmolh, closeTo(vc271.vB, 0.16));
  });

  test(
      'reference: own VC-27.2 sweep values (1 atm and 2 bar, E 0.7, L0 100, D 50)',
      () {
    for (final (p, xD, xB, tD, tB, qR) in [
      (1.01325e5, 0.97808, 0.02192, 80.54, 109.60, 1303.1),
      (2.0e5, 0.96299, 0.03701, 104.75, 134.66, 1247.7),
    ]) {
      final col = Tier2Column(
          sys: bt,
          nTrays: 20,
          feedTray: 10,
          f: 100 * kmolh,
          z: 0.5,
          l0: 100 * kmolh,
          d: 50 * kmolh,
          p: p,
          e: 0.7);
      final guess = solveNewton(const CmoColumn(
              alpha: 2.5,
              nTrays: 20,
              feedTray: 10,
              f: 100,
              z: 0.5,
              q: 1,
              l0: 100,
              vB: 141,
              e: 0.7))
          .x;
      final r = solveTier2(col, xGuess: guess);
      expect(r.xD, closeTo(xD, 2e-4));
      expect(r.xB, closeTo(xB, 2e-4));
      expect(r.t[0] - 273.15, closeTo(tD, 0.05));
      expect(r.t[21] - 273.15, closeTo(tB, 0.05));
      expect(r.qR / 1000, closeTo(qR, 1.5));
      // the table's T_D at this pressure is below the bubble point of its own x_D
      expect(bt.bubbleT(p, xD) - 273.15, closeTo(tD, 0.05));
    }
  });
}
