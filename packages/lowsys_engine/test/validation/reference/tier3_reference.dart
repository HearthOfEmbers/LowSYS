// Independent Tier-3 thermodynamics and steady column (M5 validation):
// binary NRTL (PHYSICS.md 3.4.1, Renon–Prausnitz binary form), the
// McWilliams DePriester fit (3.9), Lee–Kesler vapour pressures (2.2) for the
// C4 pair, bubble points by bisection, the azeotrope scan of VC-10.5, and a
// full MESH Newton (finite-difference Jacobian, as tier2_steady_reference.dart)
// with a pluggable K model. Pure Dart, no engine imports. Units: K, Pa, J/mol,
// mol/s.
library;

import 'dart:math' as math;

import 'dense_solve.dart';
import 'thermo_reference.dart';

/// K-values (light, heavy) at (T, P) for the light liquid fraction x.
typedef KFun = (double, double) Function(double t, double p, double x);

// ------------------------------------------------------------------ NRTL

class NrtlBinary {
  final Comp a, b; // a = component 1 (light, first in the table row)
  final double a12, a21, b12, b21, alpha;
  const NrtlBinary(
      this.a, this.b, this.a12, this.a21, this.b12, this.b21, this.alpha);

  /// (gamma1, gamma2) at T and x1.
  (double, double) gammas(double t, double x1) {
    final x2 = 1 - x1;
    final t12 = a12 + b12 / t, t21 = a21 + b21 / t;
    final g12 = math.exp(-alpha * t12), g21 = math.exp(-alpha * t21);
    final d1 = x1 + x2 * g21, d2 = x2 + x1 * g12;
    final l1 = x2 * x2 * (t21 * (g21 / d1) * (g21 / d1) + t12 * g12 / (d2 * d2));
    final l2 = x1 * x1 * (t12 * (g12 / d2) * (g12 / d2) + t21 * g21 / (d1 * d1));
    return (math.exp(l1), math.exp(l2));
  }

  (double, double) k(double t, double p, double x) {
    final (g1, g2) = gammas(t, x);
    return (g1 * a.psat(t) / p, g2 * b.psat(t) / p);
  }
}

const ewNrtl = NrtlBinary(ethanol, water, -0.801, 3.458, 246.2, -586.1, 0.3);
const mwNrtl = NrtlBinary(methanol, water, -0.693, 2.732, 173.0, -617.3, 0.3);
const acNrtl =
    NrtlBinary(acetone, chloroform, 0.965, 0.538, -590.0, -106.4, 0.3);

// ------------------------------------------------------------------ DePriester

/// McWilliams constants (a_T1, a_T2, a_T6, a_p1, a_p2, a_p3), PHYSICS.md 3.4.2.
const Map<String, List<double>> mcWilliams = {
  'propane': [-970688.5625, 0, 7.15059, -0.76984, 0, 6.90224],
  'isobutane': [-1166846, 0, 7.72668, -0.92213, 0, 0],
  'nbutane': [-1280557, 0, 7.94986, -0.96455, 0, 0],
  'isopentane': [-1481583, 0, 7.58071, -0.93159, 0, 0],
  'npentane': [-1524891, 0, 7.33129, -0.89143, 0, 0],
  'nhexane': [-1778901, 0, 6.96783, -0.84634, 0, 0],
  'nheptane': [-2013803, 0, 6.52914, -0.79543, 0, 0],
};

/// DePriester K of [id] at T (K) and P (Pa), evaluated as is (no clamping).
double kDePriester(String id, double t, double p) {
  final c = mcWilliams[id]!;
  final tr = 1.8 * t, pp = p / 6894.757;
  return math.exp(c[0] / (tr * tr) +
      c[1] / tr +
      c[2] +
      c[3] * math.log(pp) +
      c[4] / (pp * pp) +
      c[5] / pp);
}

/// Temperature (K) at which K_i = 1 (bisection on the monotone fit).
double tKEqualsOne(String id, double p) =>
    bisect((t) => kDePriester(id, t, p) - 1, 120, 1200);

// ------------------------------------------------------------------ Lee–Kesler

class LkComp {
  final double tc, pc, omega;
  const LkComp(this.tc, this.pc, this.omega);
  double psat(double t) {
    final tr = t / tc;
    final lt = math.log(tr), t6 = math.pow(tr, 6).toDouble();
    final f0 = 5.92714 - 6.09648 / tr - 1.28862 * lt + 0.169347 * t6;
    final f1 = 15.2518 - 15.6875 / tr - 13.4721 * lt + 0.43577 * t6;
    return pc * math.exp(f0 + omega * f1);
  }
}

// PHYSICS.md 2.1 rows (Psat unused through Comp: Lee–Kesler above)
const isobutane = Comp('isobutane', 58.12, 261.40, 407.80, 36.40e5, 0.184,
    21300, 140.0, 0.35, 551.0, VpKind.antoineLog10MmHgC, []);
const nbutane = Comp('nbutane', 58.12, 272.70, 425.12, 37.96e5, 0.200, 22440,
    140.9, 0.35, 573.0, VpKind.antoineLog10MmHgC, []);
const lkIsobutane = LkComp(407.80, 36.40e5, 0.184);
const lkNbutane = LkComp(425.12, 37.96e5, 0.200);
const c4Enthalpy = Binary(isobutane, nbutane);

(double, double) kC4DePriester(double t, double p, double x) =>
    (kDePriester('isobutane', t, p), kDePriester('nbutane', t, p));
(double, double) kC4LeeKesler(double t, double p, double x) =>
    (lkIsobutane.psat(t) / p, lkNbutane.psat(t) / p);

// ------------------------------------------------------------------ bubble point, azeotropes

/// Bubble T (K) by bisection on Σ K x − 1 over [lo, hi].
double bubbleTK(KFun k, double p, double x,
    {double lo = 150, double hi = 700}) {
  double g(double t) {
    final (k1, k2) = k(t, p, x);
    return x * k1 + (1 - x) * k2 - 1;
  }

  return bisect(g, lo, hi);
}

/// (T, y*) at the bubble point.
(double, double) bubbleTY(KFun k, double p, double x,
    {double lo = 150, double hi = 700}) {
  final t = bubbleTK(k, p, x, lo: lo, hi: hi);
  final (k1, k2) = k(t, p, x);
  return (t, x * k1 / (x * k1 + (1 - x) * k2));
}

/// VC-10.5: sign changes of y* − x on a 1e-4 grid, bisection to 1e-8.
List<(double, double)> azeotropes(KFun k, double p,
    {double lo = 150, double hi = 700}) {
  double f(double x) => bubbleTY(k, p, x, lo: lo, hi: hi).$2 - x;
  final out = <(double, double)>[];
  var xPrev = 1e-4, fPrev = f(xPrev);
  for (var i = 2; i < 10000; i++) {
    final x = i * 1e-4, v = f(x);
    if (fPrev * v < 0) {
      var a = xPrev, b = x, fa = fPrev;
      while (b - a > 1e-9) {
        final m = 0.5 * (a + b), fm = f(m);
        if ((fm < 0) == (fa < 0)) {
          a = m;
          fa = fm;
        } else {
          b = m;
        }
      }
      final xa = 0.5 * (a + b);
      out.add((xa, bubbleTK(k, p, xa, lo: lo, hi: hi)));
    }
    xPrev = x;
    fPrev = v;
  }
  return out;
}

// ------------------------------------------------------------------ MESH column

class Tier3Column {
  final KFun k;
  final Binary h; // enthalpies (PHYSICS.md 3.3, the Tier-2 ones)
  final int nTrays, feedTray;
  final double f, z, l0, d, p, e;
  const Tier3Column({
    required this.k,
    required this.h,
    required this.nTrays,
    required this.feedTray,
    required this.f,
    required this.z,
    required this.l0,
    required this.d,
    required this.p,
    this.e = 1.0,
  });
  double get b => f - d;
  int get nStages => nTrays + 2;
}

class Tier3Result {
  final List<double> x, t, v, l;
  final double qR, qC, maxResidual;
  const Tier3Result(this.x, this.t, this.v, this.l, this.qR, this.qC,
      this.maxResidual);
  double get xD => x[0];
  double get xB => x[x.length - 1];
  double get tD => t[0];
  double get tB => t[t.length - 1];
  double get vB => v[v.length - 1];
}

class _Lay {
  final int n;
  _Lay(this.n);
  int get nT => n - 2;
  int ix(int j) => j;
  int it(int j) => n + j;
  int iv(int j) => 2 * n + (j - 2);
  int il(int j) => 2 * n + nT + (j - 1);
  int get iq => 2 * n + 2 * nT;
  int get size => 2 * n + 2 * nT + 1;
}

double _sumKx(Tier3Column c, double t, double x) {
  final (k1, k2) = c.k(t, c.p, x);
  return x * k1 + (1 - x) * k2;
}

double _yStar(Tier3Column c, double t, double x) => x * c.k(t, c.p, x).$1;

List<double> _res(Tier3Column c, _Lay lay, List<double> u, double tF) {
  final n = c.nStages, nT = c.nTrays;
  final x = [for (var j = 0; j < n; j++) u[lay.ix(j)]];
  final t = [for (var j = 0; j < n; j++) u[lay.it(j)]];
  final v = List<double>.filled(n, 0), l = List<double>.filled(n, 0);
  v[1] = c.l0 + c.d;
  for (var j = 2; j <= nT + 1; j++) {
    v[j] = u[lay.iv(j)];
  }
  l[0] = c.l0;
  for (var j = 1; j <= nT; j++) {
    l[j] = u[lay.il(j)];
  }
  final qR = u[lay.iq];
  final y = List<double>.filled(n, 0);
  y[nT + 1] = _yStar(c, t[nT + 1], x[nT + 1]);
  for (var j = nT; j >= 1; j--) {
    y[j] = y[j + 1] + c.e * (_yStar(c, t[j], x[j]) - y[j + 1]);
  }
  final hF = c.h.hL(tF, c.z);
  final r = List<double>.filled(lay.size, 0);
  var k = 0;
  final es = c.f * 30000;
  r[k++] = (v[1] * y[1] - (c.l0 + c.d) * x[0]) / c.f;
  r[k++] = _sumKx(c, t[0], x[0]) - 1;
  for (var j = 1; j <= nT; j++) {
    final fz = j == c.feedTray ? c.f * c.z : 0.0;
    final ff = j == c.feedTray ? c.f : 0.0;
    r[k++] = (l[j - 1] * x[j - 1] + v[j + 1] * y[j + 1] + fz - l[j] * x[j] -
            v[j] * y[j]) /
        c.f;
    r[k++] = _sumKx(c, t[j], x[j]) - 1;
    r[k++] = (l[j - 1] + v[j + 1] + ff - l[j] - v[j]) / c.f;
    r[k++] = (l[j - 1] * c.h.hL(t[j - 1], x[j - 1]) +
            v[j + 1] * c.h.hV(t[j + 1], y[j + 1]) +
            ff * hF -
            l[j] * c.h.hL(t[j], x[j]) -
            v[j] * c.h.hV(t[j], y[j])) /
        es;
  }
  final s = nT + 1;
  r[k++] = (l[nT] * x[nT] - v[s] * y[s] - c.b * x[s]) / c.f;
  r[k++] = _sumKx(c, t[s], x[s]) - 1;
  r[k++] = (l[nT] * c.h.hL(t[nT], x[nT]) +
          qR -
          v[s] * c.h.hV(t[s], y[s]) -
          c.b * c.h.hL(t[s], x[s])) /
      es;
  return r;
}

double _maxAbs(List<double> v) => v.fold(0.0, (m, a) => math.max(m, a.abs()));

/// Newton on the MESH set. [xGuess]/[tGuess] per stage seed it (a previous
/// solution for continuation); [tLo]/[tHi] bracket the bubble points.
Tier3Result solveTier3(Tier3Column c,
    {List<double>? xGuess,
    List<double>? tGuess,
    double tLo = 150,
    double tHi = 700,
    double tol = 1e-10,
    int maxIter = 80}) {
  final n = c.nStages, nT = c.nTrays;
  final lay = _Lay(n);
  final tF = bubbleTK(c.k, c.p, c.z, lo: tLo, hi: tHi);
  var u = List<double>.filled(lay.size, 0);
  for (var j = 0; j < n; j++) {
    final xg = xGuess?[j] ?? (0.95 - 0.9 * j / (n - 1)).clamp(0.01, 0.99);
    u[lay.ix(j)] = xg;
    u[lay.it(j)] = tGuess?[j] ?? bubbleTK(c.k, c.p, xg, lo: tLo, hi: tHi);
  }
  for (var j = 2; j <= nT + 1; j++) {
    u[lay.iv(j)] = c.l0 + c.d;
  }
  for (var j = 1; j <= nT; j++) {
    u[lay.il(j)] = c.l0 + (j >= c.feedTray ? c.f : 0);
  }
  u[lay.iq] = (c.l0 + c.d) * 32000;
  var res = _res(c, lay, u, tF);
  var it = 0;
  while (_maxAbs(res) > tol && it < maxIter) {
    it++;
    final m = lay.size;
    final jac = List.generate(m, (_) => List<double>.filled(m, 0));
    for (var kk = 0; kk < m; kk++) {
      final hh = 1e-7 * math.max(1.0, u[kk].abs());
      final up = List<double>.from(u)..[kk] += hh;
      final um = List<double>.from(u)..[kk] -= hh;
      final rp = _res(c, lay, up, tF), rm = _res(c, lay, um, tF);
      for (var i = 0; i < m; i++) {
        jac[i][kk] = (rp[i] - rm[i]) / (2 * hh);
      }
    }
    final du = solveDense(jac, [for (final v in res) -v]);
    final n0 = _maxAbs(res);
    var lam = 1.0;
    var uNew = u, rNew = res;
    for (var ls = 0; ls < 30; ls++) {
      uNew = [for (var i = 0; i < m; i++) u[i] + lam * du[i]];
      for (var j = 0; j < n; j++) {
        uNew[lay.ix(j)] = uNew[lay.ix(j)].clamp(1e-14, 1 - 1e-14);
      }
      rNew = _res(c, lay, uNew, tF);
      if (_maxAbs(rNew) < n0 || lam < 1e-5) break;
      lam *= 0.5;
    }
    u = uNew;
    res = rNew;
  }
  final x = [for (var j = 0; j < n; j++) u[lay.ix(j)]];
  final t = [for (var j = 0; j < n; j++) u[lay.it(j)]];
  final v = List<double>.filled(n, 0), l = List<double>.filled(n, 0);
  v[1] = c.l0 + c.d;
  for (var j = 2; j <= nT + 1; j++) {
    v[j] = u[lay.iv(j)];
  }
  l[0] = c.l0;
  for (var j = 1; j <= nT; j++) {
    l[j] = u[lay.il(j)];
  }
  final y1 = () {
    final y = List<double>.filled(n, 0);
    y[nT + 1] = _yStar(c, t[nT + 1], x[nT + 1]);
    for (var j = nT; j >= 1; j--) {
      y[j] = y[j + 1] + c.e * (_yStar(c, t[j], x[j]) - y[j + 1]);
    }
    return y[1];
  }();
  final qC = v[1] * (c.h.hV(t[1], y1) - c.h.hL(t[0], x[0]));
  return Tier3Result(x, t, v, l, u[lay.iq], qC, _maxAbs(res));
}

/// Continuation in D from a CMO-like start: solves at [d0] and steps to [d].
Tier3Result solveTier3Continued(Tier3Column c, double d0,
    {int steps = 4, double tLo = 150, double tHi = 700}) {
  Tier3Column at(double d) => Tier3Column(
      k: c.k,
      h: c.h,
      nTrays: c.nTrays,
      feedTray: c.feedTray,
      f: c.f,
      z: c.z,
      l0: c.l0,
      d: d,
      p: c.p,
      e: c.e);
  var r = solveTier3(at(d0), tLo: tLo, tHi: tHi);
  for (var s = 1; s <= steps; s++) {
    r = solveTier3(at(d0 + (c.d - d0) * s / steps),
        xGuess: r.x, tGuess: r.t, tLo: tLo, tHi: tHi);
  }
  return r;
}
