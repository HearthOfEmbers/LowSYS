// Independent steady-state solution of a Tier-1 (constant α, CMO) binary
// column with a total condenser, N Murphree trays and an equilibrium
// reboiler. Two methods that share no code with the engine or with each
// other:
//   1. Newton on the full set of stage component balances with a
//      finite-difference Jacobian and a line search (as VALIDATION.md VC-4
//      describes the physics lead's method);
//   2. a shooting method: guess x_B, sweep the stage balances upwards to
//      the drum and bisect on the drum residual.
// No engine imports.
library;

import 'dart:math' as math;

import 'dense_solve.dart';
import 'mccabe_thiele_reference.dart' show yEq;

/// Column specification (SI-free basis: any consistent flow unit).
class CmoColumn {
  final double alpha;
  final int nTrays; // N
  final int feedTray; // 1-based tray index of the feed (stage index)
  final double f, z, q; // feed flow, light-component mole fraction, q
  final double l0; // reflux flow
  final double vB; // boilup (vapour leaving the reboiler)
  final double e; // Murphree vapour efficiency (trays)

  const CmoColumn({
    required this.alpha,
    required this.nTrays,
    required this.feedTray,
    required this.f,
    required this.z,
    required this.q,
    required this.l0,
    required this.vB,
    required this.e,
  });

  int get nStages => nTrays + 2; // 0 = drum, 1..N trays, N+1 = sump

  /// V_j, j = 0..N+1 (V_0 unused = 0). CMO: V changes only at the feed.
  List<double> vapour() {
    final v = List<double>.filled(nStages, 0);
    v[nTrays + 1] = vB;
    for (var j = nTrays; j >= 1; j--) {
      v[j] = v[j + 1] + (j == feedTray ? (1 - q) * f : 0);
      if (v[j] < 0) v[j] = 0;
    }
    return v;
  }

  double get d =>
      vapour()[1] - l0; // distillate at steady state (level control)
  double get b => f - d;

  /// L_j leaving stage j, j = 0..N (L_0 = reflux).
  List<double> liquid() {
    final l = List<double>.filled(nStages, 0);
    l[0] = l0;
    for (var j = 1; j <= nTrays; j++) {
      l[j] = l[j - 1] + (j == feedTray ? q * f : 0);
    }
    return l;
  }

  /// Murphree recursion from the bottom: y_{N+1} = y*(x_{N+1}),
  /// y_j = y_{j+1} + E (y*(x_j) − y_{j+1}).
  List<double> vapourComposition(List<double> x) {
    final y = List<double>.filled(nStages, 0);
    y[nTrays + 1] = yEq(x[nTrays + 1], alpha);
    for (var j = nTrays; j >= 1; j--) {
      y[j] = y[j + 1] + e * (yEq(x[j], alpha) - y[j + 1]);
    }
    return y;
  }

  /// Component balance residuals of every stage, divided by F.
  List<double> residuals(List<double> x) {
    final v = vapour();
    final l = liquid();
    final y = vapourComposition(x);
    final dd = d;
    final bb = b;
    final r = List<double>.filled(nStages, 0);
    r[0] = (v[1] * y[1] - (l0 + dd) * x[0]) / f;
    for (var j = 1; j <= nTrays; j++) {
      r[j] = (l[j - 1] * x[j - 1] +
              v[j + 1] * y[j + 1] +
              (j == feedTray ? f * z : 0) -
              l[j] * x[j] -
              v[j] * y[j]) /
          f;
    }
    final n1 = nTrays + 1;
    r[n1] = (l[nTrays] * x[nTrays] - v[n1] * y[n1] - bb * x[n1]) / f;
    return r;
  }
}

class SteadyResult {
  final List<double> x; // stage liquid compositions 0..N+1
  final List<double> y; // vapour leaving each stage (y_0 unused)
  final double xD, xB, d, b;
  final double maxResidual;
  final int iterations;
  const SteadyResult(this.x, this.y, this.xD, this.xB, this.d, this.b,
      this.maxResidual, this.iterations);
}

double _maxAbs(List<double> v) {
  var m = 0.0;
  for (final a in v) {
    if (a.abs() > m) m = a.abs();
  }
  return m;
}

/// Method 1: Newton with a finite-difference Jacobian and a backtracking
/// line search on the residual norm. Starts from a linear profile unless an
/// initial guess is given.
SteadyResult solveNewton(CmoColumn c,
    {List<double>? initial, double tol = 1e-13, int maxIter = 200}) {
  final n = c.nStages;
  var x = initial != null
      ? List<double>.from(initial)
      : [for (var j = 0; j < n; j++) 0.95 - 0.9 * j / (n - 1)];
  var r = c.residuals(x);
  var it = 0;
  while (_maxAbs(r) > tol && it < maxIter) {
    it++;
    // central-difference Jacobian
    final jac = List.generate(n, (_) => List<double>.filled(n, 0));
    for (var k = 0; k < n; k++) {
      final h = 1e-7 * math.max(1.0, x[k].abs());
      final xp = List<double>.from(x)..[k] += h;
      final xm = List<double>.from(x)..[k] -= h;
      final rp = c.residuals(xp);
      final rm = c.residuals(xm);
      for (var i = 0; i < n; i++) {
        jac[i][k] = (rp[i] - rm[i]) / (2 * h);
      }
    }
    final dx = solveDense(jac, [for (final v in r) -v]);
    // line search
    final norm0 = _maxAbs(r);
    var lam = 1.0;
    List<double>? xNew;
    List<double>? rNew;
    for (var ls = 0; ls < 40; ls++) {
      xNew = [
        for (var j = 0; j < n; j++) (x[j] + lam * dx[j]).clamp(1e-14, 1 - 1e-14)
      ];
      rNew = c.residuals(xNew);
      if (_maxAbs(rNew) < norm0 || lam < 1e-6) break;
      lam *= 0.5;
    }
    x = xNew!;
    r = rNew!;
  }
  final y = c.vapourComposition(x);
  return SteadyResult(x, y, x[0], x[n - 1], c.d, c.b, _maxAbs(r), it);
}

/// Method 2: shooting from the bottom. For a guessed x_B the sump balance
/// gives x_N, the Murphree relation gives y_N, the tray-N balance gives
/// x_{N−1}, and so on up to the drum, where the total condenser demands
/// x_0 = y_1. Bisect on g(x_B) = x_0 − y_1.
SteadyResult solveShooting(CmoColumn c, {int maxIter = 400}) {
  final n = c.nStages;
  final v = c.vapour();
  final l = c.liquid();
  final dd = c.d;
  final bb = c.b;
  final nT = c.nTrays;

  (double, List<double>, List<double>) sweep(double xB) {
    final x = List<double>.filled(n, double.nan);
    final y = List<double>.filled(n, double.nan);
    x[nT + 1] = xB;
    y[nT + 1] = yEq(xB, c.alpha);
    // sump: L_N x_N = V_{N+1} y_{N+1} + B x_B
    x[nT] = (v[nT + 1] * y[nT + 1] + bb * xB) / l[nT];
    for (var j = nT; j >= 1; j--) {
      y[j] = y[j + 1] + c.e * (yEq(x[j], c.alpha) - y[j + 1]);
      // tray j: L_{j-1} x_{j-1} = L_j x_j + V_j y_j − V_{j+1} y_{j+1} − F_j z
      final fz = j == c.feedTray ? c.f * c.z : 0.0;
      x[j - 1] =
          (l[j] * x[j] + v[j] * y[j] - v[j + 1] * y[j + 1] - fz) / l[j - 1];
    }
    // drum: V_1 y_1 = (L_0 + D) x_0 ; V_1 = L_0 + D so x_0 = y_1
    final g = x[0] - y[1];
    return (g, x, y);
  }

  // bracket: g(x_B) > 0 for every x_B above the physical root (a bottoms
  // richer than the balance allows makes the drum too rich); below the root
  // g < 0, but far below it the upward sweep leaves [0, 1] and g becomes
  // meaningless. So scan downward from z and take the first sign change.
  var hi = math.min(0.999999, c.z);
  var gHi = sweep(hi).$1;
  if (gHi.isNaN || gHi <= 0) {
    hi = 1 - 1e-9;
    gHi = sweep(hi).$1;
  }
  var lo = hi;
  var gLo = gHi;
  while (gLo > 0 && lo > 1e-12) {
    hi = lo;
    gHi = gLo;
    lo *= 0.97;
    gLo = sweep(lo).$1;
  }
  if (gLo.isNaN || gLo.sign == gHi.sign) {
    throw StateError('shooting: no sign change (g(lo)=$gLo g(hi)=$gHi)');
  }
  var it = 0;
  var mid = 0.5 * (lo + hi);
  while (it < maxIter) {
    it++;
    mid = 0.5 * (lo + hi);
    final gm = sweep(mid).$1;
    if (gm == 0 || (hi - lo) < 1e-16 * math.max(1, mid)) break;
    if (gm.sign == gLo.sign) {
      lo = mid;
      gLo = gm;
    } else {
      hi = mid;
    }
  }
  final (g, x, y) = sweep(mid);
  final res = c.residuals(x);
  var mr = g.abs();
  for (final r in res) {
    if (r.abs() > mr) mr = r.abs();
  }
  return SteadyResult(x, y, x[0], x[n - 1], dd, bb, mr, it);
}
