// Independent steady state of a Tier-2 binary column (Raoult K, Murphree
// trays, energy balances with the §3.3 enthalpies, total condenser with
// saturated reflux, constant pressure, saturated-liquid feed at its bubble
// point) by Newton on the full MESH set with a finite-difference Jacobian
// and a line search — the method VALIDATION.md VC-11 describes. Specs are
// L0 and D; Q_R and Q_C are results. No engine imports. Flows in mol/s.
library;

import 'dart:math' as math;

import 'dense_solve.dart';
import 'thermo_reference.dart';

class Tier2Column {
  final Binary sys;
  final int nTrays, feedTray;
  final double f, z, l0, d, p, e;
  final double? tFeed; // null = saturated liquid at its bubble point
  const Tier2Column({
    required this.sys,
    required this.nTrays,
    required this.feedTray,
    required this.f,
    required this.z,
    required this.l0,
    required this.d,
    required this.p,
    this.e = 1.0,
    this.tFeed,
  });
  double get b => f - d;
  int get nStages => nTrays + 2;
}

class Tier2Result {
  final List<double> x,
      t,
      y,
      v,
      l; // per stage 0..N+1 (v[0] unused, l[N+1] unused)
  final double qR, qC, maxResidual;
  final int iterations;
  const Tier2Result(this.x, this.t, this.y, this.v, this.l, this.qR, this.qC,
      this.maxResidual, this.iterations);
  double get xD => x[0];
  double get xB => x[x.length - 1];
}

/// Unknown layout: x[0..N+1], T[0..N+1], V[2..N+1], L[1..N], Q_R.
class _Layout {
  final int n; // stages
  _Layout(this.n);
  int get nT => n - 2;
  int ix(int j) => j;
  int it(int j) => n + j;
  int iv(int j) => 2 * n + (j - 2); // j = 2..N+1
  int il(int j) => 2 * n + nT + (j - 1); // j = 1..N
  int get iq => 2 * n + 2 * nT;
  int get size => 2 * n + 2 * nT + 1;
}

List<double> _residuals(Tier2Column c, _Layout lay, List<double> u) {
  final n = c.nStages, nT = c.nTrays;
  final x = [for (var j = 0; j < n; j++) u[lay.ix(j)]];
  final t = [for (var j = 0; j < n; j++) u[lay.it(j)]];
  final v = List<double>.filled(n, 0);
  final l = List<double>.filled(n, 0);
  v[1] = c.l0 + c.d; // total condenser
  for (var j = 2; j <= nT + 1; j++) {
    v[j] = u[lay.iv(j)];
  }
  l[0] = c.l0;
  for (var j = 1; j <= nT; j++) {
    l[j] = u[lay.il(j)];
  }
  final qR = u[lay.iq];
  // vapour compositions: reboiler at equilibrium, trays by Murphree from below
  final y = List<double>.filled(n, 0);
  double yStar(int j) => x[j] * c.sys.a.psat(t[j]) / c.p;
  y[nT + 1] = yStar(nT + 1);
  for (var j = nT; j >= 1; j--) {
    y[j] = y[j + 1] + c.e * (yStar(j) - y[j + 1]);
  }
  final tF = c.tFeed ?? c.sys.bubbleT(c.p, c.z);
  final hF = c.sys.hL(tF, c.z);
  final res = List<double>.filled(lay.size, 0);
  var k = 0;
  final eScale = c.f * 30000; // W
  // drum: x0 = y1 ; bubble
  res[k++] = (v[1] * y[1] - (c.l0 + c.d) * x[0]) / c.f;
  res[k++] = c.sys.sumKx(t[0], c.p, x[0]) - 1;
  for (var j = 1; j <= nT; j++) {
    final fz = j == c.feedTray ? c.f * c.z : 0.0;
    final ff = j == c.feedTray ? c.f : 0.0;
    res[k++] = (l[j - 1] * x[j - 1] +
            v[j + 1] * y[j + 1] +
            fz -
            l[j] * x[j] -
            v[j] * y[j]) /
        c.f;
    res[k++] = c.sys.sumKx(t[j], c.p, x[j]) - 1;
    res[k++] = (l[j - 1] + v[j + 1] + ff - l[j] - v[j]) / c.f;
    res[k++] = (l[j - 1] * c.sys.hL(t[j - 1], x[j - 1]) +
            v[j + 1] * c.sys.hV(t[j + 1], y[j + 1]) +
            ff * hF -
            l[j] * c.sys.hL(t[j], x[j]) -
            v[j] * c.sys.hV(t[j], y[j])) /
        eScale;
  }
  final s = nT + 1;
  res[k++] = (l[nT] * x[nT] - v[s] * y[s] - c.b * x[s]) / c.f;
  res[k++] = c.sys.sumKx(t[s], c.p, x[s]) - 1;
  res[k++] = (l[nT] * c.sys.hL(t[nT], x[nT]) +
          qR -
          v[s] * c.sys.hV(t[s], y[s]) -
          c.b * c.sys.hL(t[s], x[s])) /
      eScale;
  assert(k == lay.size);
  return res;
}

double _maxAbs(List<double> v) => v.fold(0.0, (m, a) => math.max(m, a.abs()));

/// Solves the column. [xGuess] (per stage) seeds the Newton; a CMO solution
/// or a linear profile works.
Tier2Result solveTier2(Tier2Column c,
    {List<double>? xGuess, double tol = 1e-10, int maxIter = 100}) {
  final n = c.nStages, nT = c.nTrays;
  final lay = _Layout(n);
  var u = List<double>.filled(lay.size, 0);
  for (var j = 0; j < n; j++) {
    final xg = xGuess != null
        ? xGuess[j]
        : (0.95 - 0.9 * j / (n - 1)).clamp(0.01, 0.99);
    u[lay.ix(j)] = xg;
    u[lay.it(j)] = c.sys.bubbleT(c.p, xg);
  }
  for (var j = 2; j <= nT + 1; j++) {
    u[lay.iv(j)] = c.l0 + c.d;
  }
  for (var j = 1; j <= nT; j++) {
    u[lay.il(j)] = c.l0 + (j >= c.feedTray ? c.f : 0);
  }
  u[lay.iq] = (c.l0 + c.d) * 32000;
  var res = _residuals(c, lay, u);
  var it = 0;
  while (_maxAbs(res) > tol && it < maxIter) {
    it++;
    final m = lay.size;
    final jac = List.generate(m, (_) => List<double>.filled(m, 0));
    for (var kk = 0; kk < m; kk++) {
      final h = 1e-6 * math.max(1.0, u[kk].abs());
      final up = List<double>.from(u)..[kk] += h;
      final um = List<double>.from(u)..[kk] -= h;
      final rp = _residuals(c, lay, up);
      final rm = _residuals(c, lay, um);
      for (var i = 0; i < m; i++) {
        jac[i][kk] = (rp[i] - rm[i]) / (2 * h);
      }
    }
    final du = solveDense(jac, [for (final v in res) -v]);
    final norm0 = _maxAbs(res);
    var lam = 1.0;
    List<double> uNew = u;
    List<double> rNew = res;
    for (var ls = 0; ls < 30; ls++) {
      uNew = [for (var i = 0; i < m; i++) u[i] + lam * du[i]];
      for (var j = 0; j < n; j++) {
        uNew[lay.ix(j)] = uNew[lay.ix(j)].clamp(1e-12, 1 - 1e-12);
      }
      rNew = _residuals(c, lay, uNew);
      if (_maxAbs(rNew) < norm0 || lam < 1e-5) break;
      lam *= 0.5;
    }
    u = List<double>.from(uNew);
    res = rNew;
  }
  final x = [for (var j = 0; j < n; j++) u[lay.ix(j)]];
  final t = [for (var j = 0; j < n; j++) u[lay.it(j)]];
  final v = List<double>.filled(n, 0);
  final l = List<double>.filled(n, 0);
  v[1] = c.l0 + c.d;
  for (var j = 2; j <= nT + 1; j++) {
    v[j] = u[lay.iv(j)];
  }
  l[0] = c.l0;
  for (var j = 1; j <= nT; j++) {
    l[j] = u[lay.il(j)];
  }
  final y = List<double>.filled(n, 0);
  double yStar(int j) => x[j] * c.sys.a.psat(t[j]) / c.p;
  y[nT + 1] = yStar(nT + 1);
  for (var j = nT; j >= 1; j--) {
    y[j] = y[j + 1] + c.e * (yStar(j) - y[j + 1]);
  }
  final qC = v[1] * (c.sys.hV(t[1], y[1]) - c.sys.hL(t[0], x[0]));
  return Tier2Result(x, t, y, v, l, u[lay.iq], qC, _maxAbs(res), it);
}

/// Overall energy closure |F h_F + Q_R − Q_C − D h_D − B h_B| (W).
double energyClosure(Tier2Column c, Tier2Result r) {
  final tF = c.tFeed ?? c.sys.bubbleT(c.p, c.z);
  final n = c.nStages;
  return (c.f * c.sys.hL(tF, c.z) +
          r.qR -
          r.qC -
          c.d * c.sys.hL(r.t[0], r.x[0]) -
          c.b * c.sys.hL(r.t[n - 1], r.x[n - 1]))
      .abs();
}
