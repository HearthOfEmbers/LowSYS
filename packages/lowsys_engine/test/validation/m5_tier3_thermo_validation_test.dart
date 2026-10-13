// M5 validation (validator, engine 9348b7c, re-run at fb33c07): Tier 3 thermodynamics against an
// independent re-implementation (reference/tier3_reference.dart): VC-10.4,
// 10.5 (the full table through TxyData.findAzeotropes), 10.6 against
// experiment, 10.8 over each preset's pressure lever range with the
// iteration count of PHYSICS.md 3.6.1, 10.9 and the DePriester values of
// VC-9.4/9.5 (the K model ships in M5), and the 852 °R validity limit.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/thermo_reference.dart' as ref;
import 'reference/tier3_reference.dart' as t3;

Float64List _v(List<double> a) => Float64List.fromList(a);

const _atm = 101325.0;
const _psi = 6894.757;
double _f2k(double f) => (f - 32) / 1.8 + 273.15;

/// Iteration count of PHYSICS.md 3.6.1 (Newton on ln Σ K x, |ΔT| ≤ 30 K,
/// stop at |ΔT| < 1e-6 K or |g| < 1e-10) driven by the engine's K and
/// d ln K/dT from [t0]. Returns (iterations, T); iterations > 20 = failed.
(int, double) _newton(ThermoModel m, double p, Float64List x, double t0) {
  final n = x.length;
  final k = Float64List(n), dl = Float64List(n);
  var t = t0;
  for (var it = 1; it <= 20; it++) {
    m.kValues(t, p, x, k);
    m.dLnKdT(t, p, x, dl);
    var s = 0.0, den = 0.0;
    for (var i = 0; i < n; i++) {
      s += k[i] * x[i];
      den += k[i] * x[i] * dl[i];
    }
    final g = math.log(s);
    if (g.abs() < 1e-10) return (it, t);
    final dT = (-g * s / den).clamp(-30.0, 30.0);
    t += dT;
    if (dT.abs() < 1e-6) return (it, t);
  }
  return (21, t);
}

/// The cold guess Σ x_i T_sat,i(P) of PHYSICS.md 3.6.1, T_sat,i from the
/// model's own K of the pure component (K_i(T, P, e_i) = 1).
double _coldGuess(ThermoModel m, double p, Float64List x) {
  final n = x.length;
  var t = 0.0;
  for (var i = 0; i < n; i++) {
    final e = Float64List(n)..[i] = 1.0;
    final k = Float64List(n);
    final ts = ref.bisect((tt) {
      m.kValues(tt, p, e, k);
      return k[i] - 1;
    }, 120, 900);
    t += x[i] * ts;
  }
  return t;
}

void main() {
  final ew = Tier3Nrtl.fromIds(['ethanol', 'water']);
  final mw = Tier3Nrtl.fromIds(['methanol', 'water']);
  final ac = Tier3Nrtl.fromIds(['acetone', 'chloroform']);
  final c4 = Tier3DePriester.fromIds(['isobutane', 'nbutane']);

  group('VC-10.4 NRTL', () {
    test('engine gamma equals the independent binary NRTL on a grid (1e-12 rel)',
        () {
      for (final (m, r) in [(ew, t3.ewNrtl), (mw, t3.mwNrtl), (ac, t3.acNrtl)]) {
        for (var t = 300.0; t <= 420; t += 15) {
          for (var x = 0.0; x <= 1.0; x += 0.05) {
            final g = m.gammas(t, _v([x, 1 - x]));
            final (g1, g2) = r.gammas(t, x);
            expect(g[0], closeTo(g1, 1e-12 * g1), reason: '$t K, x $x');
            expect(g[1], closeTo(g2, 1e-12 * g2), reason: '$t K, x $x');
          }
        }
      }
    });
    test('infinite dilution: 5.401 / 2.575, 2.041 / 1.663, 0.449 / 0.551', () {
      for (final (m, t, g1, g2) in [
        (ew, 351.4, 5.401, 2.575),
        (mw, 337.7, 2.041, 1.663),
        (ac, 334.0, 0.449, 0.551)
      ]) {
        expect(m.gammas(t, _v([0, 1]))[0], closeTo(g1, 1e-3));
        expect(m.gammas(t, _v([1, 0]))[1], closeTo(g2, 1e-3));
      }
    });
  });

  group('VC-10.5 azeotropes through TxyData.findAzeotropes', () {
    for (final (name, m, pAtm, x, tC, dx, dT, maxB) in [
      ('ew', ew, 1.0, 0.8956, 78.141, 0.0010, 0.02, false),
      ('ew', ew, 0.2, 0.9292, 42.349, 0.002, 0.05, false),
      ('ew', ew, 3.0, 0.8713, 108.586, 0.002, 0.05, false),
      ('ew', ew, 0.5, 0.9105, 61.623, 0.002, 0.05, false),
      ('ew', ew, 0.1, 0.9421, 29.397, 0.003, 0.1, false),
      ('ew', ew, 0.08, 0.9459, 25.488, 0.003, 0.1, false),
      ('ac', ac, 1.0, 0.3335, 64.610, 0.002, 0.05, true),
      ('ac', ac, 0.5, 0.3594, 45.365, 0.002, 0.05, true),
      ('ac', ac, 3.0, 0.2460, 101.517, 0.002, 0.05, true),
    ]) {
      test('$name at $pAtm atm: x $x, $tC °C', () {
        final az = TxyData.findAzeotropes(m, pAtm * _atm);
        expect(az.length, 1);
        expect(az.single.x, closeTo(x, dx));
        expect(az.single.t - 273.15, closeTo(tC, dT));
        expect(az.single.maximumBoiling, maxB);
        // the engine finds the same point as the independent scan
        final r = t3.azeotropes((t, p, xx) {
          final (k1, k2) = (name == 'ew' ? t3.ewNrtl : t3.acNrtl).k(t, p, xx);
          return (k1, k2);
        }, pAtm * _atm);
        expect(az.single.x, closeTo(r.single.$1, 1e-6));
        expect(az.single.t, closeTo(r.single.$2, 1e-5));
      });
    }
    test('methanol–water: none on (0, 1)', () {
      expect(TxyData.findAzeotropes(mw, _atm), isEmpty);
    });
    test('the model sits inside the literature bands (ew x ± 0.005, T ± 0.1 K; ac x ± 0.02, T ± 0.3 K)',
        () {
      final e = TxyData.findAzeotropes(ew, _atm).single;
      expect(e.x, closeTo(0.894, 0.005));
      expect(e.t - 273.15, closeTo(78.15, 0.1));
      final a = TxyData.findAzeotropes(ac, _atm).single;
      expect(a.x, closeTo(0.34, 0.02));
      // Horsley 64.4–64.7 °C (PHYSICS.md 3.4.1); VC-10.5's 64.4–64.5 °C
      // band is met to 0.3 K
      expect(a.t - 273.15, closeTo(64.45, 0.3));
    });
    test('pressure moves both azeotropes the documented way', () {
      double xe(double p) => TxyData.findAzeotropes(ew, p * _atm).single.x;
      double xa(double p) => TxyData.findAzeotropes(ac, p * _atm).single.x;
      expect(xe(0.2), greaterThan(xe(0.5)));
      expect(xe(0.5), greaterThan(xe(1.0)));
      expect(xe(1.0), greaterThan(xe(3.0)));
      expect(xa(0.5), greaterThan(xa(1.0)));
      expect(xa(1.0), greaterThan(xa(3.0)));
    });
  });

  test('VC-10.6 against experiment (T ± 0.5 K, y ± 0.015) and the independent bubble point (1e-6 K)',
      () {
    for (final (m, r, x, tExp, yExp) in [
      (mw, t3.mwNrtl, 0.02, 96.4, 0.134),
      (mw, t3.mwNrtl, 0.10, 87.7, 0.418),
      (mw, t3.mwNrtl, 0.20, 81.7, 0.579),
      (mw, t3.mwNrtl, 0.50, 73.1, 0.779),
      (mw, t3.mwNrtl, 0.90, 66.0, 0.958),
      (ew, t3.ewNrtl, 0.0966, 86.4, 0.437),
      (ew, t3.ewNrtl, 0.50, 79.8, 0.652),
      (ew, t3.ewNrtl, 0.80, 78.4, 0.818),
    ]) {
      final y = Float64List(2), k = Float64List(2);
      final t = m.bubbleT(_atm, _v([x, 1 - x]), 350, y, k, SolverHealth());
      expect(t - 273.15, closeTo(tExp, 0.5), reason: 'x $x');
      expect(y[0], closeTo(yExp, 0.015), reason: 'x $x');
      final (tr, yr) = t3.bubbleTY(r.k, _atm, x);
      expect(t, closeTo(tr, 1e-6), reason: 'x $x');
      expect(y[0], closeTo(yr, 1e-9), reason: 'x $x');
    }
  });

  group('VC-10.8 bubble-point robustness over each preset pressure range', () {
    // SCOPE.md 4.1 P_top: 0.2–5.0 bar (B-T, alcohols; ac taken the same),
    // 3–25 bar (light HC)
    for (final (name, m, pLo, pHi, maxIt) in [
      ('mw', mw, 0.2e5, 5.0e5, 6),
      ('ew', ew, 0.2e5, 5.0e5, 6),
      ('ac', ac, 0.2e5, 5.0e5, 7),
      ('c4', c4 as ThermoModel, 3e5, 25e5, 6),
    ]) {
      test('$name: ≤ $maxIt iterations from Σ x T_sat(P) in ≥ 99 %, engine converges without fallback, |ΣKx − 1| < 1e-9',
          () {
        final rng = math.Random(20261013);
        var within = 0, worst = 0;
        final h = SolverHealth();
        for (var i = 0; i < 1000; i++) {
          final x = rng.nextDouble();
          final p = pLo + (pHi - pLo) * rng.nextDouble();
          final xs = _v([x, 1 - x]);
          final t0 = _coldGuess(m, p, xs);
          final (it, tn) = _newton(m, p, xs, t0);
          if (it <= maxIt) within++;
          worst = math.max(worst, it);
          final y = Float64List(2), k = Float64List(2);
          final t = m.bubbleT(p, xs, t0, y, k, h);
          expect((k[0] * x + k[1] * (1 - x) - 1).abs(), lessThan(1e-9),
              reason: 'x $x p $p');
          expect(t, closeTo(tn, 1e-5), reason: 'x $x p $p');
          // the engine's own cold start (tGuess outside 150–900 K) as well
          final t2 = m.bubbleT(p, xs, double.nan, y, k, h);
          expect(t2, closeTo(t, 1e-6), reason: 'cold start x $x p $p');
        }
        expect(h.bubbleFallbacks, 0);
        expect(within, greaterThanOrEqualTo(990),
            reason: '$within of 1000 within $maxIt iterations (worst $worst)');
        expect(worst, lessThanOrEqualTo(20));
      });
    }
  });

  group('VC-10.9 and VC-9.4/9.5 DePriester (McWilliams, PHYSICS.md 3.9)', () {
    test('K at 50 °C / 62 °C, 7 bar and 150 °F, 100 psia (1e-5 rel); engine = independent formula',
        () {
      final k = Float64List(2);
      for (final (t, p, k1, k2, a) in [
        (323.15, 7e5, 1.01756, 0.74715, 1.36192),
        (335.15, 7e5, 1.29686, 0.97500, 1.33011),
        (338.71, 100 * _psi, 1.40630, 1.06489, 1.32060),
      ]) {
        c4.kValues(t, p, _v([0.5, 0.5]), k);
        expect(k[0], closeTo(k1, 1e-5 * k1));
        expect(k[1], closeTo(k2, 1e-5 * k2));
        expect(k[0] / k[1], closeTo(a, 1e-5 * a));
        expect(k[0], closeTo(t3.kDePriester('isobutane', t, p), 1e-12));
        expect(k[1], closeTo(t3.kDePriester('nbutane', t, p), 1e-12));
      }
    });
    test('DePriester α 1.36 / 1.33 at the c4 top / bottom against Lee–Kesler 1.379 / 1.354 (PHYSICS.md 2.3)',
        () {
      // at the Tier-3 temperatures of VC-28.3 (50.30 / 62.29 °C, 7 bar)
      for (final (t, aDp, aLk) in [(323.45, 1.36, 1.379), (335.44, 1.33, 1.354)]) {
        final aD = t3.kDePriester('isobutane', t, 7e5) /
            t3.kDePriester('nbutane', t, 7e5);
        expect(aD, closeTo(aDp, 0.005));
        final aL = t3.lkIsobutane.psat(t) / t3.lkNbutane.psat(t);
        expect(aL, closeTo(aLk, 1e-3));
        // the engine's Tier-2 c4 model is that Lee–Kesler Raoult
        final m = ThermoFactory.build(Presets.byId('c4'), ThermoTier.t2);
        final k = Float64List(2);
        m.kValues(t, 7e5, _v([0.5, 0.5]), k);
        expect(k[0] / k[1], closeTo(aL, 1e-9));
        expect(aD, lessThan(aL), reason: 'DePriester splits the pair harder');
      }
    });
    test('VC-9.4 spot values (1e-4), within 10 % of Lee–Kesler Raoult; the clamped value would be 0.5711',
        () {
      final ids = ['propane', 'isobutane', 'nbutane', 'isopentane', 'npentane', 'nhexane'];
      final m = Tier3DePriester.fromIds(ids);
      final k = Float64List(6);
      for (final (id, tF, pPsia, kRef, kLk) in [
        ('nbutane', 150.0, 100.0, 1.0648, 1.066),
        ('isopentane', 200.0, 100.0, 0.8922, 0.911),
        ('npentane', 200.0, 100.0, 0.7572, 0.744),
        ('propane', 100.0, 200.0, 1.0073, 0.946),
        ('isobutane', 100.0, 100.0, 0.7826, 0.731),
        ('nhexane', 250.0, 100.0, 0.6301, 0.597),
      ]) {
        m.kValues(_f2k(tF), pPsia * _psi, Float64List(6), k);
        final v = k[ids.indexOf(id)];
        expect(v, closeTo(kRef, 1e-4), reason: id);
        expect((v / kLk - 1).abs(), lessThan(0.10), reason: '$id vs Lee–Kesler');
      }
      // 250 °F = 709.7 °R: above v1.0's 700 °R, inside 852 °R; not clamped
      expect(t3.kDePriester('nhexane', 700 / 1.8, 100 * _psi),
          closeTo(0.5711, 1e-4));
    });
    test('VC-9.5 bubble and dew points at 100 / 250 psia (± 0.05 K)', () {
      final ids = ['propane', 'isobutane', 'nbutane', 'isopentane', 'npentane', 'nhexane'];
      final m = Tier3DePriester.fromIds(ids);
      final h = SolverHealth();
      final y = Float64List(6), k = Float64List(6), x = Float64List(6);
      double bub(List<double> z, double p) =>
          m.bubbleT(p, _v(z), 350, y, k, h) - 273.15;
      double dew(List<double> z, double p) =>
          m.dewT(p, _v(z), 330, x, h) - 273.15;
      // debutanizer (VC-9.1 table): feed, FUG distillate, FUG bottoms
      const zDb = [0.05, 0.15, 0.25, 0.20, 0.20, 0.15];
      const dDb = [5.0, 14.9806, 24.5, 0.4, 0.0631, 0.0];
      const bDb = [0.0, 0.0194, 0.5, 19.6, 19.9369, 15.0];
      List<double> norm(List<double> v) {
        final s = v.fold(0.0, (a, b) => a + b);
        return [for (final e in v) e / s];
      }

      expect(bub(zDb, 100 * _psi), closeTo(75.10, 0.05));
      expect(dew(norm(dDb), 100 * _psi), closeTo(55.25, 0.05));
      expect(bub(norm(bDb), 100 * _psi), closeTo(112.77, 0.05));
      // depropanizer (VC-9.2): Fenske split at N_min, LK propane 99 % to D,
      // HK isobutane 95 % to B
      const zDp = [0.30, 0.20, 0.25, 0.10, 0.10, 0.05];
      const al = [2.172, 1.000, 0.747, 0.378, 0.330, 0.157];
      final nMin = math.log((0.99 / 0.01) * (0.95 / 0.05)) / math.log(2.172);
      expect(nMin, closeTo(9.7203, 1e-4));
      final d = <double>[], b = <double>[];
      for (var i = 0; i < 6; i++) {
        final r = (0.05 / 0.95) * math.pow(al[i], nMin);
        final f = 100 * zDp[i];
        d.add(f * r / (1 + r));
        b.add(f / (1 + r));
      }
      expect(bub(zDp, 250 * _psi), closeTo(89.53, 0.05));
      expect(dew(norm(d), 250 * _psi), closeTo(49.52, 0.05));
      final tB = bub(norm(b), 250 * _psi);
      expect(tB, closeTo(123.84, 0.05));
      expect(h.bubbleFallbacks, 0);
      // 123.84 °C = 714.6 °R: above v1.0's 700 °R, inside 852 °R
      expect(1.8 * (tB + 273.15), inInclusiveRange(700, 852));
      // hand check of VC-9.5 at 49.52 °C, 250 psia
      m.kValues(49.52 + 273.15, 250 * _psi, Float64List(6), k);
      expect(k[0], closeTo(1.05137, 1e-4)); // hand-check precision
      expect(k[1], closeTo(0.43877, 1e-4));
      expect(k[2], closeTo(0.30977, 1e-4));
    });
  });

  group('DePriester validity 365–852 °R (PHYSICS.md 3.4.2, M7 correction)', () {
    test('the c4 bubble points over its whole lever range (3–25 bar) lie inside the range, with no fallback',
        () {
      final h = SolverHealth();
      final y = Float64List(2), k = Float64List(2);
      for (final pBar in [3.0, 7.0, 15.0, 25.0]) {
        for (var x = 0.0; x <= 1.0001; x += 0.1) {
          c4.outOfRange = false;
          final t = c4.bubbleT(pBar * 1e5, _v([x, 1 - x]), double.nan, y, k, h);
          expect(1.8 * t, inInclusiveRange(365, 852), reason: '$pBar bar x $x');
          expect(c4.outOfRange, isFalse, reason: '$pBar bar x $x');
        }
      }
      expect(h.bubbleFallbacks, 0);
    });
    test('at 7 bar DePriester and Lee–Kesler bubble points differ by ≈ 1 K (VC-28.3 T_D 50.30 vs 51.43 °C)',
        () {
      final lk = ThermoFactory.build(Presets.byId('c4'), ThermoTier.t2);
      final y = Float64List(2), k = Float64List(2);
      for (var x = 0.0; x <= 1.0001; x += 0.25) {
        final td = c4.bubbleT(7e5, _v([x, 1 - x]), 330, y, k, SolverHealth());
        final tl = lk.bubbleT(7e5, _v([x, 1 - x]), 330, y, k, SolverHealth());
        expect((td - tl).abs(), lessThan(2.0), reason: 'x $x');
        expect(td, lessThan(tl), reason: 'x $x: DePriester runs colder');
      }
    });
    test('no runaway beyond 852 °R: n-heptane at 25 bar boils above the range, unclamped, flagged',
        () {
      final m = Tier3DePriester.fromIds(['nhexane', 'nheptane']);
      final y = Float64List(2), k = Float64List(2);
      final h = SolverHealth();
      final t = m.bubbleT(25e5, _v([0, 1]), double.nan, y, k, h);
      final tRef = t3.tKEqualsOne('nheptane', 25e5);
      expect(t, closeTo(tRef, 1e-6));
      expect(1.8 * t, greaterThan(852));
      expect(t, lessThan(700), reason: 'finite, no runaway');
      expect(h.bubbleFallbacks, 0);
      expect(m.outOfRange, isTrue);
      // K keeps rising with T past the limit (g' ≠ 0): no clamp
      final k1 = Float64List(2), k2 = Float64List(2);
      m.kValues(860 / 1.8, 25e5, _v([0, 1]), k1);
      m.kValues(900 / 1.8, 25e5, _v([0, 1]), k2);
      expect(k2[1], greaterThan(k1[1] * 1.05));
    });
  });
}
