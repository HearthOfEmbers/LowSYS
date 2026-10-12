// Independent sieve/valve tray hydraulics (PHYSICS.md §5 correlations,
// re-derived from the cited sources: Bennett et al. 1983, Fair 1961 with the
// Lygeros–Magoulas 1986 fit, Summers et al. 2010, Bolles 1976, Coulson &
// Richardson vol. 6). Pure Dart, no engine imports. Used to recompute the
// VALIDATION.md VC-12 numbers and to judge the design-point plausibility.
library;

import 'dart:math' as math;

const double g = 9.80665;

/// Tray geometry derived quantities (PHYSICS.md 5.1).
class TrayGeom {
  final double dC, ts, fd, hW, hAp, fh, dh, c0;
  final double fv, rMin, dpLift, cv; // valve trays
  final double phiDc;
  const TrayGeom({
    this.dC = 1.2,
    this.ts = 0.9, // v1.1 default; v1.0 was 0.6
    this.fd = 0.12,
    this.hW = 0.05,
    this.hAp = 0.038,
    this.fh = 0.10,
    this.dh = 0.0127,
    this.c0 = 0.73,
    this.fv = 0.14,
    this.rMin = 0.25,
    this.dpLift = 190,
    this.cv = 0.65,
    this.phiDc = 0.5,
  });

  double get aT => math.pi * dC * dC / 4;
  double get aD => fd * aT;
  double get aN => aT - aD;
  double get aA => aT - 2 * aD;
  double get aH => fh * aA;

  /// Weir length from (θ − sin θ)/2π = f_d (Newton from θ = 2).
  double get lW {
    var th = 2.0;
    for (var i = 0; i < 60; i++) {
      final f = (th - math.sin(th)) / (2 * math.pi) - fd;
      th -= f / ((1 - math.cos(th)) / (2 * math.pi));
    }
    return dC * math.sin(th / 2);
  }
}

/// Tier-1 fluid constants for B-T.
class Fluid {
  final double rhoL, rhoV, sigma, mwL, mwV;
  const Fluid(
      {this.rhoL = 800,
      this.rhoV = 2.9,
      this.sigma = 0.020,
      required this.mwL,
      required this.mwV});
  double get vL => mwL / 1000 / rhoL; // m3/mol
}

// ---------------------------------------------------------------- Bennett
double bennettAlphaE(double ks) => math.exp(-12.55 * math.pow(ks, 0.91));
double bennettC(double hW) => 0.501 + 0.438 * math.exp(-137.8 * hW);

/// Clear-liquid height for a given weir volumetric load q (m³/s).
double bennettHcl(double q, double alphaE, double lW, double hW) {
  final c = bennettC(hW);
  final hOw = c * math.pow(q / (lW * alphaE), 2 / 3);
  return alphaE * (hW + hOw);
}

/// Weir flow (m³/s) from the clear-liquid height — inverse of the above.
double bennettQw(double hCl, double alphaE, double lW, double hW) {
  final c = bennettC(hW);
  final x = hCl / alphaE - hW;
  return x <= 0 ? 0 : lW * alphaE * math.pow(x / c, 1.5);
}

// ------------------------------------------------------- Fair / Lygeros
double lygerosMagoulasCsb(double tsMm, double fLv) =>
    0.0105 +
    8.127e-4 * math.pow(tsMm, 0.755) * math.exp(-1.463 * math.pow(fLv, 0.842));

double fairHoleCorrection(double ahOverAa) =>
    ahOverAa >= 0.10 ? 1.0 : math.max(0.5, 5 * ahOverAa + 0.5);

double unf(double csb, double sigma, double rhoL, double rhoV,
        {double sf = 1, double fHole = 1}) =>
    csb *
    math.pow(sigma / 0.020, 0.2) *
    math.sqrt((rhoL - rhoV) / rhoV) *
    sf *
    fHole;

// ------------------------------------------------------------ entrainment
double psiEq(double fLv, double phi, {double psiMax = 0.6}) =>
    math.min(psiMax, 4.0e-5 * math.pow(fLv / 0.1, -0.83) * math.exp(7.5 * phi));

// ---------------------------------------------------------------- weeping
double weepFraction(double stability) =>
    ((0.75 - stability) / 0.55).clamp(0.0, 1.0);

// ----------------------------------------------------------------- valves
/// Bolles three-regime dry drop. Returns (ΔP_dry, regime 0 closed / 1 balancing / 2 open).
(double, int) valveDryDrop(double qIn, TrayGeom gm, double rhoV) {
  final aMax = gm.fv * gm.aA;
  final aMin = gm.rMin * aMax;
  final dpC = rhoV / 2 * math.pow(qIn / (gm.cv * aMin), 2);
  if (dpC < gm.dpLift) return (dpC, 0);
  final aBal = qIn / (gm.cv * math.sqrt(2 * gm.dpLift / rhoV));
  if (aBal <= aMax) return (gm.dpLift, 1);
  return (rhoV / 2 * math.pow(qIn / (gm.cv * aMax), 2), 2);
}

/// All hydraulic indicators of one sieve tray at a steady vapour load V
/// (mol/s, entering and leaving) and net liquid downflow Ln (mol/s). The
/// entrainment recycle is included at its own equilibrium: with fractional
/// entrainment ψ the tray's gross liquid is L = Ln (1 − ψ)/(1 − 2ψ) for a
/// uniform column section (inflow Ln + e_below = outflow L + e).
class TrayPoint {
  final double ks,
      alphaE,
      hCl,
      holdup,
      uH,
      dpDry,
      dpSigma,
      dp,
      fLv,
      csb,
      uNf,
      phi,
      psi,
      stability,
      weep,
      hDc,
      dcFrac,
      lGross;
  const TrayPoint(
      this.ks,
      this.alphaE,
      this.hCl,
      this.holdup,
      this.uH,
      this.dpDry,
      this.dpSigma,
      this.dp,
      this.fLv,
      this.csb,
      this.uNf,
      this.phi,
      this.psi,
      this.stability,
      this.weep,
      this.hDc,
      this.dcFrac,
      this.lGross);
}

TrayPoint sieveTray(double v, double ln, Fluid fl,
    {TrayGeom gm = const TrayGeom(),
    double sFoul = 0,
    double sf = 1,
    double phiDcOverride = double.nan,
    double hNormBelow = double.nan,
    bool recycle = true}) {
  final qV = v * fl.mwV / 1000 / fl.rhoV;
  final aHeff = gm.aH * (1 - 0.8 * sFoul);
  final ks = qV / gm.aA * math.sqrt(fl.rhoV / (fl.rhoL - fl.rhoV));
  final alphaE = bennettAlphaE(ks) * sf;
  final uH = qV / aHeff;
  final dpDry = fl.rhoV / 2 * math.pow(uH / gm.c0, 2);
  final dpSigma = 4 * fl.sigma / gm.dh;
  // entrainment / gross liquid fixed point
  var psi = 0.0, lGross = ln, fLv = 0.0, csb = 0.0, uNf = 0.0, phi = 0.0;
  // The uniform-section recycle L = Ln(1−ψ)/(1−2ψ) is singular at ψ = 0.5:
  // beyond that the tray is flooded and liquid accumulates (overflow in the
  // dynamic model). The static estimate caps ψ at 0.45 and flags it.
  for (var it = 0; it < 200; it++) {
    lGross = ln * (1 - psi) / (1 - 2 * psi);
    fLv = (lGross * fl.mwL / (v * fl.mwV) * math.sqrt(fl.rhoV / fl.rhoL))
        .clamp(0.01, 2.0);
    csb = lygerosMagoulasCsb(gm.ts * 1000, fLv);
    uNf = unf(csb, fl.sigma, fl.rhoL, fl.rhoV,
        sf: sf, fHole: fairHoleCorrection(aHeff / gm.aA));
    phi = qV / gm.aN / uNf;
    final psiNew = recycle ? math.min(0.45, psiEq(fLv, phi)) : 0.0;
    if ((psiNew - psi).abs() < 1e-12) break;
    psi = 0.5 * psi + 0.5 * psiNew;
  }
  final q = lGross * fl.vL;
  final hCl = bennettHcl(q, alphaE, gm.lW, gm.hW);
  final holdup = hCl * gm.aA / fl.vL;
  final dp = dpDry + fl.rhoL * g * hCl + dpSigma;
  final hDry = dpDry / (fl.rhoL * g);
  final stability = math.sqrt(hDry / hCl);
  final weep = weepFraction(stability);
  final uAp = q / (gm.lW * gm.hAp);
  final hNorm = hNormBelow.isNaN ? hCl : hNormBelow;
  final hDc = dp / (fl.rhoL * g) + hNorm + 0.166 * uAp * uAp;
  final phiDc = phiDcOverride.isNaN ? gm.phiDc : phiDcOverride;
  final dcFrac = hDc / (phiDc * (gm.ts + gm.hW));
  return TrayPoint(ks, alphaE, hCl, holdup, uH, dpDry, dpSigma, dp, fLv, csb,
      uNf, phi, psi, stability, weep, hDc, dcFrac, lGross);
}

/// Load fraction (L and V scaled together) at which the stability factor
/// crosses 0.75 (weep onset) — bisection on the sieve-tray model.
double weepPointLoadFraction(double vDesign, double lDesign, Fluid fl,
    {TrayGeom gm = const TrayGeom()}) {
  var lo = 0.05, hi = 1.0;
  for (var i = 0; i < 60; i++) {
    final mid = 0.5 * (lo + hi);
    final p = sieveTray(vDesign * mid, lDesign * mid, fl, gm: gm);
    if (p.stability < 0.75) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// Load fraction at which jet flood φ reaches 1 (L and V scaled together).
double jetFloodLoadFraction(double vDesign, double lDesign, Fluid fl,
    {TrayGeom gm = const TrayGeom(), double sf = 1}) {
  var lo = 1.0, hi = 3.0;
  for (var i = 0; i < 60; i++) {
    final mid = 0.5 * (lo + hi);
    final p = sieveTray(vDesign * mid, lDesign * mid, fl, gm: gm, sf: sf);
    if (p.phi < 1) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}
