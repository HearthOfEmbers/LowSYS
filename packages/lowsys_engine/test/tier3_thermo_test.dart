// Tier 3 thermo (M5): NRTL gamma-infinity, azeotropes, VLE spot values, DePriester K (VC-10.4 to 10.6, 10.9).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

Float64List _v(List<double> a) => Float64List.fromList(a);

(double, double) _bub(Tier2Raoult m, double p, double x) {
  final y = Float64List(2), k = Float64List(2);
  final t = m.bubbleT(p, _v([x, 1 - x]), 360, y, k, SolverHealth());
  return (t, y[0]);
}

/// Azeotrope x by sign change of y - x on a 1e-4 grid, bisection to 1e-8.
double? _azeo(Tier2Raoult m, double p) {
  double f(double x) => _bub(m, p, x).$2 - x;
  var prev = f(1e-4);
  for (var i = 2; i < 10000; i++) {
    final x = i * 1e-4;
    final v = f(x);
    if (prev * v < 0) {
      var lo = x - 1e-4, hi = x;
      for (var k = 0; k < 60; k++) {
        final mid = 0.5 * (lo + hi);
        if (f(lo) * f(mid) <= 0) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      return 0.5 * (lo + hi);
    }
    prev = v;
  }
  return null;
}

Tier3Nrtl _nrtl(List<String> ids) => Tier3Nrtl.fromIds(ids);

void main() {
  test('VC-10.4 NRTL infinite-dilution activity coefficients', () {
    double ginf(List<String> ids, double t, int i) {
      final m = _nrtl(ids);
      final x = i == 0 ? _v([1e-9, 1 - 1e-9]) : _v([1 - 1e-9, 1e-9]);
      return m.gammas(t, x)[i];
    }

    expect(ginf(['ethanol', 'water'], 351.4, 0), closeTo(5.401, 1e-3));
    expect(ginf(['ethanol', 'water'], 351.4, 1), closeTo(2.575, 1e-3));
    expect(ginf(['methanol', 'water'], 337.7, 0), closeTo(2.041, 1e-3));
    expect(ginf(['methanol', 'water'], 337.7, 1), closeTo(1.663, 1e-3));
    expect(ginf(['acetone', 'chloroform'], 334, 0), closeTo(0.449, 1e-3));
    expect(ginf(['acetone', 'chloroform'], 334, 1), closeTo(0.551, 1e-3));
  });

  test('VC-10.5 azeotropes', () {
    final ew = _nrtl(['ethanol', 'water']);
    final ac = _nrtl(['acetone', 'chloroform']);
    final mw = _nrtl(['methanol', 'water']);
    final a = _azeo(ew, 101325)!;
    expect(a, closeTo(0.8956, 1e-3));
    expect(_bub(ew, 101325, a).$1 - 273.15, closeTo(78.141, 0.02));
    for (final (p, x) in [(0.2, 0.9292), (0.5, 0.9105), (3.0, 0.8713)]) {
      expect(_azeo(ew, p * 101325)!, closeTo(x, 2e-3), reason: 'ew $p atm');
    }
    final b = _azeo(ac, 101325)!;
    expect(b, closeTo(0.3335, 2e-3));
    expect(_bub(ac, 101325, b).$1 - 273.15, closeTo(64.610, 0.05));
    expect(_azeo(ac, 0.5 * 101325)!, closeTo(0.3594, 2e-3));
    expect(_azeo(ac, 3 * 101325)!, closeTo(0.2460, 2e-3));
    expect(_azeo(mw, 101325), isNull);
  });

  test('VC-10.6 methanol-water and ethanol-water VLE at 1 atm', () {
    final mw = _nrtl(['methanol', 'water']);
    final ew = _nrtl(['ethanol', 'water']);
    for (final (x, t, y) in [
      (0.02, 96.52, 0.1358),
      (0.10, 87.77, 0.4223),
      (0.20, 81.88, 0.5812),
      (0.50, 73.11, 0.7893),
      (0.90, 66.05, 0.9598),
    ]) {
      final r = _bub(mw, 101325, x);
      expect(r.$1 - 273.15, closeTo(t, 0.01), reason: 'MeOH x=$x');
      expect(r.$2, closeTo(y, 1e-4), reason: 'MeOH x=$x');
    }
    for (final (x, t, y) in [
      (0.10, 86.26, 0.4464),
      (0.50, 79.73, 0.6580),
      (0.80, 78.26, 0.8190),
    ]) {
      final r = _bub(ew, 101325, x);
      expect(r.$1 - 273.15, closeTo(t, 0.01), reason: 'EtOH x=$x');
      expect(r.$2, closeTo(y, 1e-4), reason: 'EtOH x=$x');
    }
  });

  test('VC-10.9 DePriester K-values', () {
    final m = Tier3DePriester.fromIds(['isobutane', 'nbutane']);
    final k = Float64List(2);
    for (final (t, p, k1, k2) in [
      (323.15, 7e5, 1.01756, 0.74715),
      (335.15, 7e5, 1.29686, 0.97500),
      (338.71, 100 * 6894.757, 1.40630, 1.06489),
    ]) {
      m.kValues(t, p, _v([0.5, 0.5]), k);
      expect(k[0], closeTo(k1, 1e-5 * k1));
      expect(k[1], closeTo(k2, 1e-5 * k2));
    }
  });

  test('VC-10.8 bubble-point robustness (NRTL and DePriester): converges, |sum Kx - 1| < 1e-9, no fallback', () {
    final rng = math.Random(7);
    for (final ids in [
      ['methanol', 'water'],
      ['ethanol', 'water'],
      ['acetone', 'chloroform'],
    ]) {
      final m = _nrtl(ids);
      final h = SolverHealth();
      for (var i = 0; i < 1000; i++) {
        final x = rng.nextDouble();
        final p = (0.3 + 4.5 * rng.nextDouble()) * 101325;
        final y = Float64List(2), k = Float64List(2);
        final xs = _v([x, 1 - x]);
        m.bubbleT(p, xs, m.coldGuess(xs, 0), y, k, h);
        expect((k[0] * x + k[1] * (1 - x) - 1).abs(), lessThan(1e-9));
      }
      expect(h.bubbleFallbacks, 0, reason: ids.join('-'));
    }
    final dp = Tier3DePriester.fromIds(['isobutane', 'nbutane']);
    final h = SolverHealth();
    for (var i = 0; i < 1000; i++) {
      final x = rng.nextDouble();
      final p = (3 + 8 * rng.nextDouble()) * 1e5;
      final y = Float64List(2), k = Float64List(2);
      final xs = _v([x, 1 - x]);
      dp.bubbleT(p, xs, dp.coldGuess(xs, 0), y, k, h);
      expect((k[0] * x + k[1] * (1 - x) - 1).abs(), lessThan(1e-9));
    }
    expect(h.bubbleFallbacks, 0);
  });

  test('dew point and flash are consistent with the bubble point (NRTL)', () {
    final m = _nrtl(['ethanol', 'water']);
    final z = _v([0.3, 0.7]);
    final y = Float64List(2), k = Float64List(2), x = Float64List(2);
    final h = SolverHealth();
    final tb = m.bubbleT(101325, z, 350, y, k, h);
    final td = m.dewT(101325, z, tb + 5, x, h);
    expect(td, greaterThan(tb));
    final fl = m.flashTP(0.5 * (tb + td), 101325, z);
    expect(fl.beta, inExclusiveRange(0, 1));
    for (var i = 0; i < 2; i++) {
      expect(fl.beta * fl.y[i] + (1 - fl.beta) * fl.x[i], closeTo(z[i], 1e-7));
    }
    // the bubble composition of the dew liquid reproduces the dew point
    final yb = Float64List(2), kb = Float64List(2);
    final t2 = m.bubbleT(101325, x, td, yb, kb, h);
    expect(t2, closeTo(td, 1e-6));
    expect(yb[0], closeTo(z[0], 1e-6));
  });
}
