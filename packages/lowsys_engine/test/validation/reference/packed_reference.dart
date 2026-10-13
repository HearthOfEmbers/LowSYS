// Independent packed-section reference (validator, M8): PHYSICS.md 6.3-6.6 and (4.3) written from the spec text, no
// engine imports. Flood flux by Brent-free regula falsi (Illinois) to 1e-13 instead of the spec's 40-step bisection;
// Kremser in closed form; a per-stage-E Tier-1 CMO shooting solver for packed / mixed columns.
library;

import 'dart:math' as math;

import 'dense_solve.dart';

const double gRef = 9.80665;
const double _paPerInH2OFt = 817.22;

/// Robbins (6.1), Pa/m. lp, gp in kg/m2/s; rho in kg/m3; mu in cP; fp in 1/ft.
double robbinsRef(double lp, double gp, double rhoL, double rhoV, double muCp, double fp) {
  final rhoVlb = rhoV / 16.01846, rhoLlb = rhoL / 16.01846, sf = math.sqrt(fp / 20);
  final gf = gp * 737.338 * math.sqrt(0.075 / rhoVlb) * sf;
  final lf = lp * 737.338 * (62.4 / rhoLlb) * sf * math.pow(muCp, 0.1);
  final t = 7.4e-8 * gf * gf * math.pow(10, 2.7e-5 * lf);
  return _paPerInH2OFt * (t + 0.4 * math.pow(lf / 20000, 0.1) * math.pow(t, 4));
}

/// Kister-Gill (6.2), Pa/m.
double floodDpRef(double fp) => _paPerInH2OFt * 0.115 * math.pow(fp, 0.7);

/// G'_fl at fixed L'/G' (Illinois regula falsi on [0.01, 30]).
double floodFluxRef(double ratioLG, double rhoL, double rhoV, double muCp, double fp) {
  final target = floodDpRef(fp);
  double f(double g) => robbinsRef(ratioLG * g, g, rhoL, rhoV, muCp, fp) - target;
  var a = 0.01, b = 30.0, fa = f(a), fb = f(b);
  var side = 0;
  for (var i = 0; i < 200; i++) {
    final c = (a * fb - b * fa) / (fb - fa), fc = f(c);
    if (fc.abs() < 1e-13 * target || (b - a).abs() < 1e-14) return c;
    if (fc * fb > 0) {
      b = c;
      fb = fc;
      if (side == -1) fa /= 2;
      side = -1;
    } else {
      a = c;
      fa = fc;
      if (side == 1) fb /= 2;
      side = 1;
    }
  }
  return (a + b) / 2;
}

/// Holdup (6.3), volume fraction. mu in Pa s, uL in m/s.
double holdupRef(double muPas, double a, double uL, double rhoL, double phi) =>
    math.pow(12 * muPas * a * a * uL / (rhoL * gRef), 1 / 3).toDouble() * (1 + 1.2 * math.pow(phi, 13));

/// Onda wetted fraction (SI: mu Pa s, sigma N/m).
double ondaRef(double lp, double a, double rhoL, double muPas, double sigma, double sigmaC) {
  final re = lp / (a * muPas), fr = lp * lp * a / (rhoL * rhoL * gRef), we = lp * lp / (rhoL * sigma * a);
  return 1 -
      math.exp(-1.45 * math.pow(sigmaC / sigma, 0.75) * math.pow(re, 0.1) * math.pow(fr, -0.05) * math.pow(we, 0.2));
}

double loadingRef(double phi) => phi <= 0.8 ? 1.0 : (phi <= 1.0 ? 1 + 8 * (phi - 0.8) * (phi - 0.8) : 1.32 + 3 * (phi - 1));

/// HETP (6.5) with the M8 max(1, .) wetting rule.
double hetpRef(double hetp0, double lp, double? lpDes, double a, double rhoL, double muPas, double sigma, double sigmaC,
    double phi) {
  final w = lpDes == null
      ? 1.0
      : math.max(1.0, ondaRef(lpDes, a, rhoL, muPas, sigma, sigmaC) / ondaRef(lp, a, rhoL, muPas, sigma, sigmaC));
  return hetp0 * w * loadingRef(phi);
}

/// Lewis (4.3): overall efficiency from Murphree and stripping factor.
double lewisEoRef(double emv, double lam) => (lam - 1).abs() < 1e-12 ? emv : math.log(1 + emv * (lam - 1)) / math.log(lam);
double lewisEmvRef(double eo, double lam) => (lam - 1).abs() < 1e-12 ? eo : (math.pow(lam, eo) - 1) / (lam - 1);

/// Kremser fraction stripped.
double kremserRef(double s, double n) {
  if (s.isInfinite) return 1.0;
  if ((s - 1).abs() < 1e-12) return n / (n + 1);
  final sn1 = math.pow(s, n + 1);
  return (sn1 - s) / (sn1 - 1);
}

/// Parallel-column maldistribution (6.6): (phiMal, nEff, eMal).
({double phiMal, double nEff, double eMal}) maldistRef(double s, double n, double f) {
  final sb = f >= 1 ? double.infinity : s / (1 - f);
  final pm = ((1 + f) * kremserRef(s / (1 + f), n) + (1 - f) * kremserRef(sb, n)) / 2;
  final ne = (s - 1).abs() < 1e-12 ? pm / (1 - pm) : math.log((s - pm) / (1 - pm)) / math.log(s) - 1;
  return (phiMal: pm, nEff: ne, eMal: ne / n);
}

/// Tier-1 CMO binary column, total condenser, per-stage Murphree E (stages 1..n), equilibrium reboiler (stage n + 1),
/// saturated-liquid feed on stage `feed`. Newton on x_0..x_{n+1}, y_1..y_{n+1}. Returns (xD, xB, x[0..n+1]).
({double xD, double xB, List<double> x}) cmoColumnRef(
    {required double alpha, required List<double> e, required int feed, required double f, required double z,
    required double l0, required double vB}) {
  final n = e.length, b = f - (vB - l0), nx = n + 2, nu = 2 * n + 3;
  double yEq(double x) => alpha * x / (1 + (alpha - 1) * x);
  double dyEq(double x) => alpha / math.pow(1 + (alpha - 1) * x, 2);
  double lOut(int j) => j == 0 ? l0 : (j < feed ? l0 : l0 + f); // liquid leaving stage j (0: reflux)
  final u = [for (var j = 0; j < nx; j++) 0.5, for (var j = 1; j <= n + 1; j++) 0.5];
  int iy(int j) => nx + j - 1; // y_j, j = 1..n+1
  for (var it = 0; it < 100; it++) {
    final r = List<double>.filled(nu, 0), jac = [for (var i = 0; i < nu; i++) List<double>.filled(nu, 0)];
    var row = 0;
    // drum: x_0 - y_1
    r[row] = u[0] - u[iy(1)];
    jac[row][0] = 1;
    jac[row++][iy(1)] = -1;
    for (var j = 1; j <= n; j++) {
      // stage balance
      r[row] = lOut(j - 1) * u[j - 1] + vB * u[iy(j + 1)] + (j == feed ? f * z : 0) - lOut(j) * u[j] - vB * u[iy(j)];
      jac[row][j - 1] = lOut(j - 1);
      jac[row][iy(j + 1)] = vB;
      jac[row][j] = -lOut(j);
      jac[row++][iy(j)] = -vB;
      // Murphree
      r[row] = u[iy(j)] - u[iy(j + 1)] - e[j - 1] * (yEq(u[j]) - u[iy(j + 1)]);
      jac[row][iy(j)] = 1;
      jac[row][iy(j + 1)] = -1 + e[j - 1];
      jac[row++][j] = -e[j - 1] * dyEq(u[j]);
    }
    // reboiler balance and equilibrium
    r[row] = lOut(n) * u[n] - vB * u[iy(n + 1)] - b * u[n + 1];
    jac[row][n] = lOut(n);
    jac[row][iy(n + 1)] = -vB;
    jac[row++][n + 1] = -b;
    r[row] = u[iy(n + 1)] - yEq(u[n + 1]);
    jac[row][iy(n + 1)] = 1;
    jac[row][n + 1] = -dyEq(u[n + 1]);
    final dx = solveDense(jac, [for (final v in r) -v]);
    var mx = 0.0;
    for (var i = 0; i < nu; i++) {
      u[i] = (u[i] + dx[i]).clamp(0.0, 1.0);
      mx = math.max(mx, dx[i].abs());
    }
    if (mx < 1e-14) break;
  }
  return (xD: u[0], xB: u[n + 1], x: u.sublist(0, nx));
}

