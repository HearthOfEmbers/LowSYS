// M8 packed-section prototype (physics lead, readiness pass 2026-10-13).
// PHYSICS.md §6 (packing data, Robbins, Kister–Gill, holdup, Onda wetting, HETP, Lewis, maldistribution)
// and an independent steady-state B-T column solver (Tier 1 CMO or Tier 2 Raoult/Antoine with the §3.3
// enthalpies and §3.5 properties) whose stages are sieve trays (fixed Murphree E) or packed segments
// (E from the HETP, coupled by an outer fixed-point loop). Pure Dart, no packages. Not engine code.
import 'dart:math';

const g0 = 9.80665;
const rGas = 8.314462618;

// ------------------------------------------------------------------------------------------------
// §6.2 packing table. sigmaC in N/m; rhoBed = solid mass per m³ of bed (ρ_solid (1 − ε)), M8 addition.
class Packing {
  final String id;
  final double a, eps, fp, sigmaC, hetpRef, rhoBed;
  const Packing(this.id, this.a, this.eps, this.fp, this.sigmaC, this.hetpRef, this.rhoBed);
}

const pall25m = Packing('pall25m', 205, 0.94, 56, 0.075, 0.46, 7900 * 0.06);
const pall50m = Packing('pall50m', 105, 0.96, 27, 0.075, 0.91, 7900 * 0.04);
const raschig50c = Packing('raschig50c', 92, 0.74, 65, 0.061, 0.91, 2300 * 0.26);
const struct250 = Packing('struct250', 250, 0.98, 20, 0.075, 0.50, 7900 * 0.02);
const struct500 = Packing('struct500', 500, 0.975, 34, 0.075, 0.30, 7900 * 0.025);
const packings = [pall25m, pall50m, raschig50c, struct250, struct500];

/// Kister's rules of thumb quoted in §6.2: random HETP[ft] = 1.5 × size[in]; structured HETP[in] = 1200/a[ft²/ft³] + 4.
double hetpRuleStructured(double aM2M3) => (1200 / (aM2M3 / 3.28084) + 4) * 0.0254;

// ------------------------------------------------------------------------------------------------
// (6.1) Robbins, US-unit form, F_pd = F_p. Inputs SI: L', G' kg/m²/s, ρ kg/m³, μ in cP.
double robbinsInH2OPerFt(double lp, double gp, double rhoL, double rhoV, double muCp, double fpd) {
  final rhoVlb = rhoV / 16.01846, rhoLlb = rhoL / 16.01846;
  final gf = gp * 737.338 * sqrt(0.075 / rhoVlb) * sqrt(fpd / 20);
  final lf = lp * 737.338 * (62.4 / rhoLlb) * sqrt(fpd / 20) * pow(muCp, 0.1);
  final t = 7.4e-8 * gf * gf * pow(10, 2.7e-5 * lf);
  return t + 0.4 * pow(lf / 20000, 0.1) * pow(t, 4);
}

double robbinsPaPerM(double lp, double gp, double rhoL, double rhoV, double muCp, double fpd) =>
    817.22 * robbinsInH2OPerFt(lp, gp, rhoL, rhoV, muCp, fpd);

/// (6.2) Kister–Gill flood ΔP, Pa/m.
double kgFloodPaPerM(double fp) => 817.22 * 0.115 * pow(fp, 0.7);

/// Flood vapour flux at the current L'/G' (bisection on [0.01, 30], 40 iterations).
double floodGp(double ratioLG, double rhoL, double rhoV, double muCp, double fp, {int iters = 40}) {
  final target = kgFloodPaPerM(fp);
  var lo = 0.01, hi = 30.0;
  for (var i = 0; i < iters; i++) {
    final mid = 0.5 * (lo + hi);
    if (robbinsPaPerM(mid * ratioLG, mid, rhoL, rhoV, muCp, fp) < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// (6.3) holdup (volume fraction). mu in Pa·s, uL in m/s.
double holdupS(double muPas, double a, double uL, double rhoL) => pow(12 * muPas * a * a * uL / (rhoL * g0), 1 / 3).toDouble();
double holdupFactor(double phi) => 1 + 1.2 * pow(phi, 13);

/// Onda wetted fraction a_w/a. sigma, sigmaC in N/m, mu in Pa·s.
double ondaWet(double lp, double a, double rhoL, double muPas, double sigma, double sigmaC) {
  final re = lp / (a * muPas), fr = lp * lp * a / (rhoL * rhoL * g0), we = lp * lp / (rhoL * sigma * a);
  return 1 - exp(-1.45 * pow(sigmaC / sigma, 0.75) * pow(re, 0.1) * pow(fr, -0.05) * pow(we, 0.2));
}

/// (6.5) loading factor g(φ).
double gLoad(double phi) => phi <= 0.8 ? 1.0 : (phi <= 1.0 ? 1 + 8 * (phi - 0.8) * (phi - 0.8) : 1.32 + 3 * (phi - 1.0));

/// (4.3) Lewis.
double lewisEO(double emv, double lam) => (lam - 1).abs() < 1e-9 ? emv : log(1 + emv * (lam - 1)) / log(lam);
double lewisEMV(double eo, double lam) => (lam - 1).abs() < 1e-9 ? eo : (pow(lam, eo) - 1) / (lam - 1);

/// (6.6) Kremser fraction and the parallel-column maldistribution model (n may be fractional).
double kremser(double s, double n) {
  if ((log(s)).abs() < 1e-9) return n / (n + 1);
  final sn = pow(s, n + 1).toDouble();
  if (sn.isInfinite) return 1.0;
  return (sn - s) / (sn - 1);
}

double nEffFromPhi(double s, double phi) {
  if ((log(s)).abs() < 1e-9) return phi / (1 - phi);
  return log((s - phi) / (1 - phi)) / log(s) - 1;
}

class Mal {
  final double phiU, phiMal, nEff, eMal;
  Mal(this.phiU, this.phiMal, this.nEff, this.eMal);
}

Mal maldistribution(double s, double n, double f) {
  final phiU = kremser(s, n);
  if (f <= 0) return Mal(phiU, phiU, n, 1.0);
  final pm = ((1 + f) * kremser(s / (1 + f), n) + (1 - f) * kremser(s / (1 - f), n)) / 2;
  final ne = nEffFromPhi(s, pm);
  return Mal(phiU, pm, ne, ne / n);
}

// ------------------------------------------------------------------------------------------------
// B-T data, PHYSICS.md §2.1, §2.2 (Antoine A), §3.3, §3.5.
class Comp {
  final String id;
  final double mw, tb, tc, pc, w, dh, cp, dcp, rho298, sig298, aA, aB, aC;
  const Comp(this.id, this.mw, this.tb, this.tc, this.pc, this.w, this.dh, this.cp, this.dcp, this.rho298, this.sig298,
      this.aA, this.aB, this.aC);
}

const benzene = Comp('benzene', 78.11, 353.24, 562.05, 48.95, 0.210, 30.72, 135.69, 0.22, 873.6, 28.2e-3, 6.90565, 1211.033, 220.790);
const toluene = Comp('toluene', 92.14, 383.78, 591.75, 41.08, 0.264, 33.18, 157.29, 0.26, 862.3, 27.9e-3, 6.95464, 1344.800, 219.482);
const bt = [benzene, toluene];
const t0 = 298.15;

double psat(Comp c, double t) => pow(10, c.aA - c.aB / (t - 273.15 + c.aC)) * 133.322368;
double dlnPsat(Comp c, double t) => log(10) * c.aB / pow(t - 273.15 + c.aC, 2);
double hL1(Comp c, double t) => c.cp * (t - t0) + 0.5 * c.dcp * (t - t0) * (t - t0);
double dHv(Comp c, double t) => t < c.tc ? c.dh * 1000 * pow((c.tc - t) / (c.tc - c.tb), 0.38) : 0.0;

double bubbleT(List<double> x, double p, [double tg = 360]) {
  var t = tg;
  for (var it = 0; it < 60; it++) {
    var s = 0.0, ds = 0.0;
    for (var i = 0; i < 2; i++) {
      final kx = psat(bt[i], t) / p * x[i];
      s += kx;
      ds += kx * dlnPsat(bt[i], t);
    }
    final dt = (-log(s) / (ds / s)).clamp(-30.0, 30.0);
    t += dt;
    if (dt.abs() < 1e-11) break;
  }
  return t;
}

double rhoLmix(List<double> x, double t) {
  var v = 0.0, m = 0.0;
  for (var i = 0; i < 2; i++) {
    final c = bt[i];
    final zra = 0.29056 - 0.08775 * c.w;
    final rho = c.rho298 * pow(zra, pow(1 - t0 / c.tc, 2 / 7) - pow(1 - t / c.tc, 2 / 7));
    v += x[i] * c.mw / (1000 * rho);
    m += x[i] * c.mw / 1000;
  }
  return m / v;
}

double rhoVmix(List<double> y, double t, double p) {
  var tc = 0.0, pc = 0.0, w = 0.0, mw = 0.0;
  for (var i = 0; i < 2; i++) {
    tc += y[i] * bt[i].tc;
    pc += y[i] * bt[i].pc * 1e5;
    w += y[i] * bt[i].w;
    mw += y[i] * bt[i].mw;
  }
  final tr = t / tc, pr = p / pc;
  final b0 = 0.083 - 0.422 / pow(tr, 1.6), b1 = 0.139 - 0.172 / pow(tr, 4.2);
  final z = (1 + (b0 + w * b1) * pr / tr).clamp(0.30, 1.05);
  return p * mw / (1000 * z * rGas * t);
}

double sigmaMix(List<double> x, double t) {
  var s = 0.0;
  for (var i = 0; i < 2; i++) {
    final c = bt[i];
    s += x[i] * pow(c.sig298 * pow((c.tc - t) / (c.tc - t0), 1.22), 0.25);
  }
  return pow(s, 4).toDouble();
}

double mwOf(List<double> x) => x[0] * benzene.mw + x[1] * toluene.mw;

// ------------------------------------------------------------------------------------------------
// Column sections (top to bottom).
class Section {
  final bool packed;
  final int trays; // tray sections
  final double murphree; // tray sections
  final Packing? pk;
  final double bedHeight, diameter, designFlux; // packed sections (designFlux kg/m²/s: L'_des)
  double malF = 0; // F21: f = 0.6 s
  double crush = 0; // F23 severity s
  Section.trays(this.trays, this.murphree, {this.diameter = 1.2})
      : packed = false, pk = null, bedHeight = 0, designFlux = 0;
  Section.bed(Packing p, this.bedHeight, {this.diameter = 1.2, this.designFlux = 0})
      : packed = true, trays = 0, murphree = 1, pk = p;
  int get nSeg => packed ? max(1, (bedHeight / pk!.hetpRef).round()) : trays;
  double get fpEff => pk!.fp * (1 + 1.5 * crush);
  double get hEff => bedHeight * (1 - 0.15 * crush);
  double get hSeg => hEff / nSeg;
  double get area => pi * diameter * diameter / 4;
}

class SegInfo {
  double lp = 0, gp = 0, rhoL = 0, rhoV = 0, sigma = 0, dpPerM = 0, dp = 0, phi = 0, gfl = 0;
  double wet = 0, wetRef = 0, hetp = 0, lam = 1, eo = 1, emv = 1, hL = 0, hLs = 0;
}

class BedInfo {
  double s = 1, nTh = 0, eMal = 1, dp = 0, maxPhi = 0;
}

class Column {
  final List<Section> sections;
  final int tier; // 1 or 2
  final double alpha; // Tier 1
  final double f, zB, pTop; // mol/s, light mole fraction, Pa
  final int feedStage;
  final double muCp;
  final bool idealHyd;
  // Tier-1 constant properties
  double rhoL1 = 800, rhoV1 = 2.9, sigma1 = 0.020;

  late int nT;
  late List<int> secOf; // stage -> section index (1..nT)
  late List<double> e, p; // 0..nT+1
  late List<List<double>> x, y;
  late List<double> t, v, l;
  late List<SegInfo> seg;
  late List<BedInfo> bed;
  double d = 0, b = 0, qr = 0, qc = 0, l0 = 0, tF = 0;
  int outer = 0;

  Column(this.sections, {this.tier = 2, this.alpha = 2.5, this.f = 100 / 3.6, this.zB = 0.5, this.pTop = 101325,
      required this.feedStage, this.muCp = 0.27, this.idealHyd = false}) {
    secOf = [-1];
    for (var s = 0; s < sections.length; s++) {
      for (var k = 0; k < sections[s].nSeg; k++) secOf.add(s);
    }
    nT = secOf.length - 1;
    secOf.add(-1);
    e = List.filled(nT + 2, 1.0);
    for (var j = 1; j <= nT; j++) e[j] = sections[secOf[j]].packed ? 1.0 : sections[secOf[j]].murphree;
    p = List.filled(nT + 2, pTop);
    seg = List.generate(nT + 2, (_) => SegInfo());
    bed = List.generate(sections.length, (_) => BedInfo());
  }

  int get ns => nT + 2;
  List<double> get z => [zB, 1 - zB];

  // K at stage j (Tier 1: normalised α; Tier 2: Raoult at T_j, P_j)
  double kOf(int j, int i) {
    if (tier == 1) {
      final s = alpha * x[j][0] + x[j][1];
      return (i == 0 ? alpha : 1.0) / s;
    }
    return psat(bt[i], t[j]) / p[j];
  }

  List<double> _solveComp(int i, List<List<double>> kk) {
    final m = 2 * (nT + 1);
    final a = List.generate(m, (_) => List<double>.filled(m + 1, 0.0));
    int xi(int j) => 2 * (j - 1);
    int yi(int j) => 2 * (j - 1) + 1;
    for (var j = 1; j <= nT + 1; j++) {
      final r = xi(j), r2 = yi(j);
      if (j <= nT) {
        if (j == 1) {
          a[r][yi(1)] += l[0];
        } else {
          a[r][xi(j - 1)] += l[j - 1];
        }
        a[r][xi(j)] -= l[j];
        a[r][yi(j)] -= v[j];
        a[r][yi(j + 1)] += v[j + 1];
        if (j == feedStage) a[r][m] -= f * z[i];
        a[r2][yi(j)] = 1;
        a[r2][yi(j + 1)] = -(1 - e[j]);
        a[r2][xi(j)] = -e[j] * kk[j][i];
      } else {
        a[r][xi(j - 1)] += l[j - 1];
        a[r][xi(j)] -= b;
        a[r][yi(j)] -= v[j];
        a[r2][yi(j)] = 1;
        a[r2][xi(j)] = -kk[j][i];
      }
    }
    for (var c = 0; c < m; c++) {
      var piv = c;
      for (var r = c + 1; r < m; r++) if (a[r][c].abs() > a[piv][c].abs()) piv = r;
      final tmp = a[c];
      a[c] = a[piv];
      a[piv] = tmp;
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

  bool _init = false;
  void _initState(double l0_, double d_) {
    x = List.generate(ns, (_) => [zB, 1 - zB]);
    y = List.generate(ns, (_) => [zB, 1 - zB]);
    t = List.filled(ns, tier == 2 ? bubbleT(z, pTop) : 0.0);
    v = List.filled(ns, 0.0);
    l = List.filled(ns, 0.0);
    l0 = l0_;
    d = d_;
    for (var j = 1; j <= nT + 1; j++) v[j] = l0 + d;
    for (var j = 0; j <= nT; j++) l[j] = j < feedStage ? l0 : l0 + f;
    b = f - d;
    _init = true;
  }

  /// Inner solve at fixed E and P: reflux l0_ and distillate d_ (mol/s).
  void solveLD(double l0_, double d_, {int maxIt = 4000, double tol = 1e-13}) {
    if (!_init) _initState(l0_, d_);
    l0 = l0_;
    d = d_;
    if (tier == 1) {
      for (var j = 1; j <= nT + 1; j++) v[j] = l0 + d;
      for (var j = 0; j <= nT; j++) l[j] = j < feedStage ? l0 : l0 + f;
      b = f - d;
    }
    tF = tier == 2 ? bubbleT(z, p[feedStage], t[feedStage]) : 0.0;
    final hF = tier == 2 ? zB * hL1(benzene, tF) + (1 - zB) * hL1(toluene, tF) : 0.0;
    for (var it = 0; it < maxIt; it++) {
      final kk = List.generate(ns, (j) => j == 0 ? [1.0, 1.0] : [kOf(j, 0), kOf(j, 1)]);
      final xn = List.generate(ns, (_) => [0.0, 0.0]);
      final yn = List.generate(ns, (_) => [0.0, 0.0]);
      for (var i = 0; i < 2; i++) {
        final s = _solveComp(i, kk);
        for (var j = 1; j <= nT + 1; j++) {
          xn[j][i] = max(0.0, s[2 * (j - 1)]);
          yn[j][i] = max(0.0, s[2 * (j - 1) + 1]);
        }
      }
      var dx = 0.0;
      for (var j = 1; j <= nT + 1; j++) {
        final sx = xn[j][0] + xn[j][1], sy = yn[j][0] + yn[j][1];
        for (var i = 0; i < 2; i++) {
          xn[j][i] /= sx;
          yn[j][i] /= sy;
          dx = max(dx, (xn[j][i] - x[j][i]).abs());
        }
        x[j] = xn[j];
        y[j] = yn[j];
      }
      x[0] = List<double>.from(y[1]);
      var dv = 0.0;
      if (tier == 2) {
        for (var j = 0; j <= nT + 1; j++) t[j] = bubbleT(x[j], p[j], t[j]);
        double hl(int j) => x[j][0] * hL1(benzene, t[j]) + x[j][1] * hL1(toluene, t[j]);
        double hv(int j) => y[j][0] * (hL1(benzene, t[j]) + dHv(benzene, t[j])) + y[j][1] * (hL1(toluene, t[j]) + dHv(toluene, t[j]));
        final h = List<double>.generate(ns, hl);
        final hV = List<double>.generate(ns, (j) => j == 0 ? 0.0 : hv(j));
        final vn = List<double>.filled(ns, 0.0), ln = List<double>.filled(ns, 0.0);
        ln[0] = l0;
        vn[1] = l0 + d;
        for (var j = 1; j <= nT; j++) {
          final fj = j == feedStage ? f : 0.0;
          vn[j + 1] = (vn[j] * (hV[j] - h[j]) - ln[j - 1] * (h[j - 1] - h[j]) - fj * (hF - h[j])) / (hV[j + 1] - h[j]);
          ln[j] = ln[j - 1] + vn[j + 1] + fj - vn[j];
        }
        for (var j = 1; j <= nT + 1; j++) dv = max(dv, (vn[j] - v[j]).abs() / vn[j]);
        for (var j = 1; j <= nT + 1; j++) v[j] = vn[j];
        for (var j = 0; j <= nT; j++) l[j] = ln[j];
        b = l[nT] - v[nT + 1];
        qr = v[nT + 1] * hV[nT + 1] + b * h[nT + 1] - l[nT] * h[nT];
        qc = v[1] * hV[1] - (l0 + d) * h[0];
      }
      if (dx < tol && dv < 1e-12) break;
    }
  }

  /// Tier 2: reflux and reboiler duty (W); secant on D.
  void solveLQ(double l0_, double qrSpec, double dGuess) {
    var d1 = dGuess, d2 = dGuess * 1.01;
    solveLD(l0_, d1);
    var r1 = qr - qrSpec;
    for (var it = 0; it < 50; it++) {
      solveLD(l0_, d2);
      final r2 = qr - qrSpec;
      if (r2.abs() < 1e-7) break;
      final dn = d2 - r2 * (d2 - d1) / (r2 - r1);
      d1 = d2;
      r1 = r2;
      d2 = dn;
    }
  }

  /// Packed hydraulics and efficiencies at the current state (PHYSICS.md §6.3–6.6, M8 rules).
  /// Returns the max change in E.
  double updateHydraulics() {
    var de = 0.0;
    for (var s = 0; s < sections.length; s++) {
      final sec = sections[s];
      if (!sec.packed) continue;
      final pk = sec.pk!;
      final at = sec.area;
      final stages = [for (var j = 1; j <= nT; j++) if (secOf[j] == s) j];
      var lnS = 0.0, nTh = 0.0, dpBed = 0.0, maxPhi = 0.0;
      for (final j in stages) {
        final si = seg[j];
        si.rhoL = tier == 1 ? rhoL1 : rhoLmix(x[j], t[j]);
        si.rhoV = tier == 1 ? rhoV1 : rhoVmix(y[j], t[j], p[j]);
        si.sigma = tier == 1 ? sigma1 : sigmaMix(x[j], t[j]);
        si.lp = l[j] * mwOf(x[j]) / (1000 * at);
        si.gp = v[j + 1] * mwOf(y[j + 1]) / (1000 * at);
        si.dpPerM = robbinsPaPerM(si.lp, si.gp, si.rhoL, si.rhoV, muCp, sec.fpEff);
        si.gfl = floodGp(si.lp / si.gp, si.rhoL, si.rhoV, muCp, sec.fpEff);
        si.phi = si.gp / si.gfl;
        si.dp = idealHyd ? 0.0 : si.dpPerM * sec.hSeg;
        final mu = muCp * 1e-3;
        si.wet = ondaWet(si.lp, pk.a, si.rhoL, mu, si.sigma, pk.sigmaC);
        si.wetRef = ondaWet(sec.designFlux, pk.a, si.rhoL, mu, si.sigma, pk.sigmaC);
        si.hetp = idealHyd ? pk.hetpRef : pk.hetpRef * max(1.0, si.wetRef / si.wet) * gLoad(si.phi);
        si.hLs = holdupS(mu, pk.a, si.lp / si.rhoL, si.rhoL);
        si.hL = si.hLs * (idealHyd ? 1.0 : holdupFactor(si.phi));
        // λ = m V/L, m = local slope of the pseudo-binary equilibrium curve
        final al = tier == 1 ? alpha : (psat(benzene, t[j]) / psat(toluene, t[j]));
        final xx = x[j][0];
        final m = al / pow(1 + (al - 1) * xx, 2);
        si.lam = m * v[j] / l[j];
        lnS += log(si.lam);
        nTh += min(1.0, sec.hSeg / si.hetp);
        dpBed += si.dp;
        maxPhi = max(maxPhi, si.phi);
      }
      final bi = bed[s];
      bi.s = exp(lnS / stages.length);
      bi.nTh = nTh;
      bi.eMal = sec.malF > 0 ? maldistribution(bi.s, nTh, sec.malF).eMal : 1.0;
      bi.dp = dpBed;
      bi.maxPhi = maxPhi;
      for (final j in stages) {
        final si = seg[j];
        si.eo = min(1.0, sec.hSeg / si.hetp) * bi.eMal;
        si.emv = lewisEMV(si.eo, si.lam);
        de = max(de, (si.emv - e[j]).abs());
        e[j] = si.emv;
      }
    }
    // pressure profile (Tier 2 only; trays carry no ΔP in this prototype)
    if (tier == 2) {
      p[0] = pTop;
      p[1] = pTop;
      for (var j = 1; j <= nT; j++) p[j + 1] = p[j] + (sections[secOf[j]].packed ? seg[j].dp : 0.0);
    }
    return de;
  }

  /// Full steady state: Tier 1 (l0, vb) or Tier 2 (l0, qr). Flows in kmol/h, duty in kW.
  void solve({required double l0kmolh, double vbKmolh = 150, double qrKW = 1300, double dGuessKmolh = 50}) {
    final l0s = l0kmolh / 3.6;
    for (outer = 0; outer < 200; outer++) {
      if (tier == 1) {
        solveLD(l0s, vbKmolh / 3.6 - l0s);
      } else {
        solveLQ(l0s, qrKW * 1000, _init ? d : dGuessKmolh / 3.6);
      }
      final pOld = List<double>.from(p);
      final de = updateHydraulics();
      var dp = 0.0;
      for (var j = 0; j < ns; j++) dp = max(dp, (p[j] - pOld[j]).abs());
      if (de < 1e-11 && dp < 1e-7) break;
    }
  }

  double get xD => x[0][0];
  double get xB => x[nT + 1][0];
  double get dKmolh => d * 3.6;
  double get colDp => p[nT + 1] - p[1];
  double tC(int j) => t[j] - 273.15;
  double get maxPhi {
    var m = 0.0;
    for (final bi in bed) m = max(m, bi.maxPhi);
    return m;
  }
}

String f4(double v, [int dp = 4]) => v.toStringAsFixed(dp);
