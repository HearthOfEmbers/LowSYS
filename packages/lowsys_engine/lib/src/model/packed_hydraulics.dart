import 'dart:math' as math;

/// Closed-form packed-section correlations of PHYSICS.md 6 (M8), exposed for the stepper, the overlay and tests.
abstract final class PackedHydraulics {
  static const double g = 9.80665;

  /// Robbins pressure drop (6.1), US-unit form with F_pd = F_p, as Pa/m. L', G' in kg/m2/s, densities in kg/m3,
  /// [muCp] the liquid viscosity in cP.
  static double robbins(double lp, double gp, double rhoL, double rhoV, double muCp, double fp) =>
      817.22 * robbinsInH2OPerFt(lp, gp, rhoL, rhoV, muCp, fp);

  static double robbinsInH2OPerFt(double lp, double gp, double rhoL, double rhoV, double muCp, double fp) {
    final rhoVlb = rhoV / 16.01846, rhoLlb = rhoL / 16.01846;
    final gf = gp * 737.338 * math.sqrt(0.075 / rhoVlb) * math.sqrt(fp / 20);
    final lf = lp * 737.338 * (62.4 / rhoLlb) * math.sqrt(fp / 20) * math.pow(muCp, 0.1);
    final t = 7.4e-8 * gf * gf * math.pow(10, 2.7e-5 * lf);
    return t + 0.4 * math.pow(lf / 20000, 0.1) * math.pow(t, 4);
  }

  /// Kister-Gill flood pressure drop (6.2), Pa/m.
  static double kisterGillFloodDp(double fp) => 817.22 * 0.115 * math.pow(fp, 0.7);

  /// Flood vapour flux G'_fl at the load ratio [ratioLG] = L'/G' (bisection on [0.01, 30], 40 iterations).
  static double floodFlux(double ratioLG, double rhoL, double rhoV, double muCp, double fp, {int iters = 40}) {
    final target = kisterGillFloodDp(fp);
    var lo = 0.01, hi = 30.0;
    for (var i = 0; i < iters; i++) {
      final mid = 0.5 * (lo + hi);
      if (robbins(mid * ratioLG, mid, rhoL, rhoV, muCp, fp) < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// Pre-loading (Nusselt) holdup h_L,S of (6.3); [mu] in Pa s, [uL] superficial liquid velocity m/s.
  static double holdupS(double mu, double a, double uL, double rhoL) =>
      math.pow(12 * mu * a * a * uL / (rhoL * g), 1 / 3).toDouble();

  /// 1 + 1.2 phi^13 of (6.3); phi is capped at 2 so the factor stays finite.
  static double holdupFactor(double phi) => 1 + 1.2 * math.pow(math.min(phi, 2.0), 13);

  /// h_L of (6.3).
  static double holdup(double mu, double a, double uL, double rhoL, double phi) =>
      holdupS(mu, a, uL, rhoL) * holdupFactor(phi);

  /// Onda wetted fraction a_w/a (6.5). [mu] in Pa s, sigma and sigmaC in N/m.
  static double ondaWetFraction(double lp, double a, double rhoL, double mu, double sigma, double sigmaC) {
    final re = lp / (a * mu), fr = lp * lp * a / (rhoL * rhoL * g), we = lp * lp / (rhoL * sigma * a);
    return 1 - math.exp(-1.45 * math.pow(sigmaC / sigma, 0.75) * math.pow(re, 0.1) * math.pow(fr, -0.05) * math.pow(we, 0.2));
  }

  /// Loading factor g(phi) of (6.5).
  static double loadingFactor(double phi) =>
      phi <= 0.8 ? 1.0 : (phi <= 1.0 ? 1 + 8 * (phi - 0.8) * (phi - 0.8) : 1.32 + 3 * (phi - 1.0));

  /// Wetting factor max(1, a_w,ref/a_w); 1 without a design flux.
  static double wettingFactor(double lp, double? lpDes, double a, double rhoL, double mu, double sigma, double sigmaC) {
    if (lpDes == null || lpDes <= 0 || !(lp > 0)) return 1.0;
    final w = ondaWetFraction(lp, a, rhoL, mu, sigma, sigmaC);
    final wr = ondaWetFraction(lpDes, a, rhoL, mu, sigma, sigmaC);
    return math.max(1.0, wr / w);
  }

  /// HETP of (6.5).
  static double hetp(double hetpRef, double wetting, double phi) => hetpRef * wetting * loadingFactor(phi);

  /// Lewis relation (4.3).
  static double lewisEO(double emv, double lam) =>
      (lam - 1).abs() < 1e-9 ? emv : math.log(1 + emv * (lam - 1)) / math.log(lam);
  static double lewisEMV(double eo, double lam) =>
      (lam - 1).abs() < 1e-9 ? eo : (math.pow(lam, eo) - 1) / (lam - 1);

  /// Outflow of a segment from its holdup, (6.4): mol/s for holdup [m] mol. [factor] = 1 + 1.2 phi^13.
  static double outflow(double m, double vL, double aT, double h, double factor, double rhoL, double mu, double a) {
    final hl = m * vL / (aT * h * factor);
    return hl * hl * hl * rhoL * g * aT / (12 * mu * a * a * vL);
  }

  /// Equilibrium slope m_k of (6.4) from alpha' and x'.
  static double slope(double alphaP, double xp) => alphaP / math.pow(1 + (alphaP - 1) * xp, 2);
}

/// Parallel-column maldistribution model (6.6).
abstract final class Maldistribution {
  /// Kremser fraction stripped; n may be fractional.
  static double kremser(double s, double n) {
    if (math.log(s).abs() < 1e-9) return n / (n + 1);
    final sn = math.pow(s, n + 1).toDouble();
    if (sn.isInfinite) return 1.0;
    return (sn - s) / (sn - 1);
  }

  static double nEff(double s, double phi) {
    if (math.log(s).abs() < 1e-9) return phi / (1 - phi);
    return math.log((s - phi) / (1 - phi)) / math.log(s) - 1;
  }

  /// Mixed-outlet Kremser fraction Phi_mal for split [f].
  static double phiMal(double s, double n, double f) =>
      ((1 + f) * kremser(s / (1 + f), n) + (1 - f) * kremser(s / (1 - f), n)) / 2;

  /// E_mal = n_eff / n (6.6); 1 for f <= 0.
  static double eMal(double s, double n, double f) {
    if (f <= 1e-12 || n <= 0) return 1.0;
    final pm = phiMal(s, n, f);
    final ne = nEff(s, pm);
    final e = ne / n;
    return e.isFinite ? e.clamp(0.0, 1.0) : 1.0;
  }
}
