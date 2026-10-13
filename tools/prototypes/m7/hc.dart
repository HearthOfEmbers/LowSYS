// M7 light-hydrocarbon prototype: PHYSICS.md §2.1, §2.2 (Lee–Kesler), §3.3, §3.4.2 (DePriester),
// §3.6 bubble/dew, and an independent steady-state column solver (bubble-point method with
// Murphree vapour efficiency, dense linear solve per component). Pure Dart, no packages.
import 'dart:math';

const t0 = 298.15;

class Comp {
  final String id;
  final double mw, tb, tc, pc, w, dh, cp, dcp; // pc bar, dh kJ/mol, cp J/mol/K, dcp J/mol/K²
  final double aT1, aT2, aT6, ap1, ap2, ap3; // McWilliams (3.9)
  const Comp(this.id, this.mw, this.tb, this.tc, this.pc, this.w, this.dh, this.cp, this.dcp,
      this.aT1, this.aT2, this.aT6, this.ap1, this.ap2, this.ap3);
}

const propane = Comp('propane', 44.10, 231.10, 369.83, 42.48, 0.152, 19.04, 117.8, 0.60, -970688.5625, 0, 7.15059, -0.76984, 0, 6.90224);
const isobutane = Comp('isobutane', 58.12, 261.40, 407.80, 36.40, 0.184, 21.30, 140.0, 0.35, -1166846, 0, 7.72668, -0.92213, 0, 0);
const nbutane = Comp('nbutane', 58.12, 272.70, 425.12, 37.96, 0.200, 22.44, 140.9, 0.35, -1280557, 0, 7.94986, -0.96455, 0, 0);
const isopentane = Comp('isopentane', 72.15, 301.00, 460.40, 33.80, 0.227, 24.69, 164.8, 0.30, -1481583, 0, 7.58071, -0.93159, 0, 0);
const npentane = Comp('npentane', 72.15, 309.20, 469.70, 33.70, 0.252, 25.79, 167.2, 0.30, -1524891, 0, 7.33129, -0.89143, 0, 0);
const nhexane = Comp('nhexane', 86.18, 341.90, 507.60, 30.25, 0.301, 28.85, 195.6, 0.30, -1778901, 0, 6.96783, -0.84634, 0, 0);
const nheptane = Comp('nheptane', 100.20, 371.60, 540.20, 27.40, 0.350, 31.77, 224.7, 0.30, -2013803, 0, 6.52914, -0.79543, 0, 0);
const six = [propane, isobutane, nbutane, isopentane, npentane, nhexane];

double lnPsatLK(Comp c, double t) {
  final tr = t / c.tc;
  final f0 = 5.92714 - 6.09648 / tr - 1.28862 * log(tr) + 0.169347 * pow(tr, 6);
  final f1 = 15.2518 - 15.6875 / tr - 13.4721 * log(tr) + 0.43577 * pow(tr, 6);
  return log(c.pc * 1e5) + f0 + c.w * f1;
}

double dlnPsatLK(Comp c, double t) {
  final tr = t / c.tc;
  return (6.09648 / (tr * tr) - 1.28862 / tr + 1.016082 * pow(tr, 5) +
          c.w * (15.6875 / (tr * tr) - 13.4721 / tr + 2.61462 * pow(tr, 5))) / c.tc;
}

bool dpOutOfRange = false;
double dpTmaxR = 851.67; // 200 °C (Seader/Henley statement of the McWilliams fit); PHYSICS.md v1 said 700 °R
double lnKdp(Comp c, double t, double pPa) {
  var tR = 1.8 * t, p = pPa / 6894.757;
  if (tR < 365 || tR > dpTmaxR || p < 14.7 || p > 870) dpOutOfRange = true;
  tR = tR.clamp(365.0, dpTmaxR); p = p.clamp(14.7, 870.0);
  return c.aT1 / (tR * tR) + c.aT2 / tR + c.aT6 + c.ap1 * log(p) + c.ap2 / (p * p) + c.ap3 / p;
}

double dlnKdp(Comp c, double t) {
  final tR = (1.8 * t).clamp(365.0, dpTmaxR);
  return 1.8 * (-2 * c.aT1 / (tR * tR * tR) - c.aT2 / (tR * tR));
}

/// model: 0 constant alpha (Tier 1), 1 Raoult + Lee–Kesler (Tier 2), 2 DePriester (Tier 3)
class Thermo {
  final List<Comp> c;
  final int model;
  final List<double>? alpha;
  Thermo(this.c, this.model, [this.alpha]);
  int get n => c.length;
  double lnK(int i, double t, double p) => model == 2 ? lnKdp(c[i], t, p) : lnPsatLK(c[i], t) - log(p);
  double k(int i, double t, double p) => exp(lnK(i, t, p));
  double dlnK(int i, double t) => model == 2 ? dlnKdp(c[i], t) : dlnPsatLK(c[i], t);

  double tsatGuess(List<double> x, double p) {
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      // Lee–Kesler T_sat(P) by Newton from T_b
      var t = c[i].tb;
      for (var it = 0; it < 50; it++) {
        final g = lnPsatLK(c[i], t) - log(p);
        final dt = -g / dlnPsatLK(c[i], t);
        t += dt.clamp(-30.0, 30.0);
        if (dt.abs() < 1e-8) break;
      }
      s += x[i] * t;
    }
    return s;
  }

  int lastIters = 0;
  double bubbleT(List<double> x, double p, [double? tg]) {
    var t = tg ?? tsatGuess(x, p);
    for (var it = 0; it < 50; it++) {
      var s = 0.0, ds = 0.0;
      for (var i = 0; i < n; i++) {
        final kx = k(i, t, p) * x[i];
        s += kx; ds += kx * dlnK(i, t);
      }
      final g = log(s);
      var dt = -g / (ds / s);
      dt = dt.clamp(-30.0, 30.0);
      t += dt;
      lastIters = it + 1;
      if (dt.abs() < 1e-10 || g.abs() < 1e-13) break;
    }
    return t;
  }

  double dewT(List<double> y, double p, [double? tg]) {
    var t = tg ?? tsatGuess(y, p) + 10;
    for (var it = 0; it < 60; it++) {
      var s = 0.0, ds = 0.0;
      for (var i = 0; i < n; i++) {
        final yk = y[i] / k(i, t, p);
        s += yk; ds -= yk * dlnK(i, t);
      }
      final g = log(s);
      var dt = -g / (ds / s);
      dt = dt.clamp(-30.0, 30.0);
      t += dt;
      if (dt.abs() < 1e-10) break;
    }
    return t;
  }

  double hL1(int i, double t) => c[i].cp * (t - t0) + 0.5 * c[i].dcp * (t - t0) * (t - t0);
  double dHv(int i, double t) => t < c[i].tc ? c[i].dh * 1000 * pow((c[i].tc - t) / (c[i].tc - c[i].tb), 0.38) : 0.0;
  double hL(List<double> x, double t) { var s = 0.0; for (var i = 0; i < n; i++) s += x[i] * hL1(i, t); return s; }
  double hV(List<double> y, double t) { var s = 0.0; for (var i = 0; i < n; i++) s += y[i] * (hL1(i, t) + dHv(i, t)); return s; }
}

// ---------------------------------------------------------------------------------------------
// Steady-state column: stage 0 drum (total condenser, x0 = y1), 1..N trays (Murphree E on vapour),
// N+1 partial reboiler (equilibrium). Isobaric at P (ideal hydraulics: no ΔP). Feed on tray nf.
class Column {
  final Thermo th;
  final int nT, nf;
  final double f, p, e; // mol/s, Pa
  final List<double> z;
  final double q; // Tier 1 only; Tiers 2/3: saturated liquid feed at P
  Column(this.th, this.nT, this.nf, this.f, this.z, this.p, this.e, {this.q = 1.0});

  late List<List<double>> x, y; // [stage][comp], stages 0..N+1 (y[0] unused)
  late List<double> t, v, l; // t[0..N+1], v[1..N+1], l[0..N]
  double d = 0, b = 0, qr = 0, qc = 0, l0 = 0, tF = 0;
  int iters = 0;
  double energyResidual = 0;

  int get ns => nT + 2;

  void _init(double l0_, double d_) {
    final n = th.n;
    x = List.generate(ns, (_) => List<double>.from(z));
    y = List.generate(ns, (_) => List<double>.from(z));
    t = List.filled(ns, 0.0);
    v = List.filled(ns, 0.0);
    l = List.filled(ns, 0.0);
    if (th.model != 0) {
      final tb = th.bubbleT(z, p);
      for (var j = 0; j < ns; j++) t[j] = tb;
    }
    l0 = l0_;
    d = d_;
    final vtop = l0 + d;
    for (var j = 1; j <= nT + 1; j++) v[j] = (j <= nf) ? vtop : vtop - (1 - q) * f;
    for (var j = 0; j <= nT; j++) l[j] = (j < nf) ? l0 : l0 + q * f;
    b = f - d;
    if (n < 0) {}
  }

  List<double> _solveComp(int i, List<List<double>> kk) {
    final m = 2 * (nT + 1);
    final a = List.generate(m, (_) => List<double>.filled(m + 1, 0.0));
    int xi(int j) => 2 * (j - 1);
    int yi(int j) => 2 * (j - 1) + 1;
    for (var j = 1; j <= nT + 1; j++) {
      final r = xi(j), r2 = yi(j);
      if (j <= nT) {
        // balance
        if (j == 1) {
          a[r][yi(1)] += l[0];
        } else {
          a[r][xi(j - 1)] += l[j - 1];
        }
        a[r][xi(j)] -= l[j];
        a[r][yi(j)] -= v[j];
        a[r][yi(j + 1)] += v[j + 1];
        if (j == nf) a[r][m] -= f * z[i];
        // efficiency
        a[r2][yi(j)] = 1;
        a[r2][yi(j + 1)] = -(1 - e);
        a[r2][xi(j)] = -e * kk[j][i];
      } else {
        a[r][xi(j - 1)] += l[j - 1];
        a[r][xi(j)] -= b;
        a[r][yi(j)] -= v[j];
        a[r2][yi(j)] = 1;
        a[r2][xi(j)] = -kk[j][i];
      }
    }
    // Gaussian elimination, partial pivoting
    for (var c = 0; c < m; c++) {
      var piv = c;
      for (var r = c + 1; r < m; r++) if (a[r][c].abs() > a[piv][c].abs()) piv = r;
      final tmp = a[c]; a[c] = a[piv]; a[piv] = tmp;
      final pv = a[c][c];
      for (var r = c + 1; r < m; r++) {
        final fct = a[r][c] / pv;
        if (fct == 0) continue;
        for (var k = c; k <= m; k++) a[r][k] -= fct * a[c][k];
      }
    }
    final sol = List<double>.filled(m, 0.0);
    for (var r = m - 1; r >= 0; r--) {
      var s = a[r][m];
      for (var k = r + 1; k < m; k++) s -= a[r][k] * sol[k];
      sol[r] = s / a[r][r];
    }
    return sol;
  }

  /// Solve with reflux l0 and distillate d (mol/s). Tier 1 uses CMO with V from l0 + d.
  void solveLD(double l0_, double d_, {int maxIt = 3000, double tol = 1e-12, bool quiet = true}) {
    _init(l0_, d_);
    final n = th.n;
    if (th.model != 0) tF = th.bubbleT(z, p);
    final hF = th.model != 0 ? th.hL(z, tF) : 0.0;
    for (iters = 0; iters < maxIt; iters++) {
      // K at the current state
      final kk = List.generate(ns, (_) => List<double>.filled(n, 0.0));
      for (var j = 1; j <= nT + 1; j++) {
        if (th.model == 0) {
          var s = 0.0;
          for (var i = 0; i < n; i++) s += th.alpha![i] * x[j][i];
          for (var i = 0; i < n; i++) kk[j][i] = th.alpha![i] / s;
        } else {
          for (var i = 0; i < n; i++) kk[j][i] = th.k(i, t[j], p);
        }
      }
      final xn = List.generate(ns, (_) => List<double>.filled(n, 0.0));
      final yn = List.generate(ns, (_) => List<double>.filled(n, 0.0));
      for (var i = 0; i < n; i++) {
        final s = _solveComp(i, kk);
        for (var j = 1; j <= nT + 1; j++) {
          xn[j][i] = max(0.0, s[2 * (j - 1)]);
          yn[j][i] = max(0.0, s[2 * (j - 1) + 1]);
        }
      }
      var dx = 0.0;
      for (var j = 1; j <= nT + 1; j++) {
        var sx = 0.0, sy = 0.0;
        for (var i = 0; i < n; i++) { sx += xn[j][i]; sy += yn[j][i]; }
        for (var i = 0; i < n; i++) {
          xn[j][i] /= sx; yn[j][i] /= sy;
          dx = max(dx, (xn[j][i] - x[j][i]).abs());
        }
        x[j] = xn[j]; y[j] = yn[j];
      }
      x[0] = List<double>.from(y[1]);
      var dv = 0.0;
      if (th.model != 0) {
        for (var j = 0; j <= nT + 1; j++) t[j] = th.bubbleT(x[j], p, t[j]);
        // top-down energy sweep with V1 = L0 + D
        final h = List<double>.generate(ns, (j) => th.hL(x[j], t[j]));
        final hv = List<double>.generate(ns, (j) => j == 0 ? 0.0 : th.hV(y[j], t[j]));
        final vn = List<double>.filled(ns, 0.0), ln = List<double>.filled(ns, 0.0);
        ln[0] = l0;
        vn[1] = l0 + d;
        for (var j = 1; j <= nT; j++) {
          final fj = j == nf ? f : 0.0;
          vn[j + 1] = (vn[j] * (hv[j] - h[j]) - ln[j - 1] * (h[j - 1] - h[j]) - fj * (hF - h[j])) / (hv[j + 1] - h[j]);
          ln[j] = ln[j - 1] + vn[j + 1] + fj - vn[j];
        }
        for (var j = 1; j <= nT + 1; j++) dv = max(dv, (vn[j] - v[j]).abs() / vn[j]);
        for (var j = 1; j <= nT + 1; j++) v[j] = vn[j];
        for (var j = 0; j <= nT; j++) l[j] = ln[j];
        b = l[nT] - v[nT + 1];
        qr = v[nT + 1] * hv[nT + 1] + b * h[nT + 1] - l[nT] * h[nT];
        qc = v[1] * hv[1] - (l0 + d) * h[0];
        energyResidual = f * hF + qr - qc - d * h[0] - b * h[nT + 1];
      }
      if (dx < tol && dv < 1e-12) break;
    }
  }

  /// Tiers 2/3: reflux l0 and reboiler duty qrSpec (W); secant on D.
  void solveLQ(double l0_, double qrSpec, double dGuess) {
    var d1 = dGuess, d2 = dGuess * 1.02;
    solveLD(l0_, d1);
    var r1 = qr - qrSpec;
    for (var it = 0; it < 40; it++) {
      solveLD(l0_, d2);
      final r2 = qr - qrSpec;
      if (r2.abs() < 1e-6) break;
      final dn = d2 - r2 * (d2 - d1) / (r2 - r1);
      d1 = d2; r1 = r2; d2 = dn;
    }
  }

  /// Tier 1: reflux l0 and boilup vb (CMO): D = vb + (1 - q) F - l0
  void solveLV(double l0_, double vb) => solveLD(l0_, vb + (1 - q) * f - l0_);

  List<double> get xD => x[0];
  List<double> get xB => x[nT + 1];
  double recD(int i) => d * xD[i] / (f * z[i]);
  double recB(int i) => b * xB[i] / (f * z[i]);
}

// ---------------------------------------------------------------------------------------------
// FUG per PHYSICS.md §14.3 / VALIDATION.md VC-9 procedure.
class Fug {
  late double nMin, theta, rMin, r, xX, yY, n, nrNs, dTot, bTot;
  late List<double> d, b, xd, xb;
  Fug(List<double> alpha, List<double> z, int lk, int hk, double rLK, double rHK,
      {double f = 100, double q = 1, double? rAbs, double rFactor = 1.3}) {
    final nc = z.length;
    final dLK = rLK * f * z[lk], bLK = f * z[lk] - dLK;
    final bHK = rHK * f * z[hk], dHK = f * z[hk] - bHK;
    final aLK = alpha[lk] / alpha[hk];
    nMin = log((dLK / bLK) * (bHK / dHK)) / log(aLK);
    d = List.filled(nc, 0.0); b = List.filled(nc, 0.0);
    for (var i = 0; i < nc; i++) {
      if (i == lk) { d[i] = dLK; b[i] = bLK; continue; }
      if (i == hk) { d[i] = dHK; b[i] = bHK; continue; }
      final ratio = pow(alpha[i] / alpha[hk], nMin) * dHK / bHK;
      d[i] = f * z[i] * ratio / (1 + ratio);
      b[i] = f * z[i] - d[i];
    }
    dTot = d.reduce((a, c) => a + c); bTot = f - dTot;
    xd = [for (final v in d) v / dTot]; xb = [for (final v in b) v / bTot];
    // Underwood
    double phi(double th) { var s = 0.0; for (var i = 0; i < nc; i++) s += alpha[i] * z[i] / (alpha[i] - th); return s - (1 - q); }
    var lo = alpha[hk] + 1e-12, hi = alpha[lk] - 1e-12;
    for (var it = 0; it < 80; it++) { final mid = 0.5 * (lo + hi); if (phi(mid) > 0) { hi = mid; } else { lo = mid; } } // phi rises with θ
    theta = 0.5 * (lo + hi);
    var s = 0.0;
    for (var i = 0; i < nc; i++) s += alpha[i] * xd[i] / (alpha[i] - theta);
    rMin = s - 1;
    r = rAbs ?? rFactor * rMin;
    xX = (r - rMin) / (r + 1);
    yY = 1 - exp((1 + 54.4 * xX) / (11 + 117.2 * xX) * (xX - 1) / sqrt(xX));
    n = (nMin + yY) / (1 - yY);
    nrNs = pow((z[hk] / z[lk]) * pow(xb[lk] / xd[hk], 2) * (bTot / dTot), 0.206).toDouble();
  }
}

String f4(double v, [int dp = 4]) => v.toStringAsFixed(dp);
double kmolh(double molps) => molps * 3.6;
double molps(double kmolh) => kmolh / 3.6;
