// M9 crude prototype library (physics lead, readiness pass 2026-10-13). Pure Dart, no packages.
// PHYSICS.md §9: assay -> pseudo-components, Lee–Kesler K with steam partial pressure, §9.1 enthalpies
// (liquid: Watson–Nelson Cp; vapour: anchored at T_b with the Fallon–Watson vapour Cp), product TBP/D86 (Daubert),
// and an independent steady-state solver for the crude column (main column, three 2-stage strippers, one
// pumparound, bottom and stripper steam). Reference for re-derivation, not engine code.
import 'dart:math' as m;

const double rGas = 8.314462618, t0 = 298.15;

// ---------------------------------------------------------------- assay (§9.1)
const tbpV = <double>[0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100];
const tbpC = <double>[20, 70, 100, 165, 230, 290, 350, 405, 465, 535, 620, 680, 760];
const cutsC = <double>[20, 90, 150, 200, 250, 300, 350, 425, 525, 760];
const double kW = 11.9;

double lerp(List<double> xs, List<double> ys, double x) {
  if (x <= xs.first) return ys.first;
  if (x >= xs.last) return ys.last;
  var k = 0;
  while (xs[k + 1] < x) k++;
  return ys[k] + (ys[k + 1] - ys[k]) * (x - xs[k]) / (xs[k + 1] - xs[k]);
}

double tbpAt(double v) => lerp(tbpV, tbpC, v); // °C at crude vol %
double volAt(double t) => lerp(tbpC, tbpV, t); // crude vol % at °C

double f0(double tr) => 5.92714 - 6.09648 / tr - 1.28862 * m.log(tr) + 0.169347 * m.pow(tr, 6);
double f1(double tr) => 15.2518 - 15.6875 / tr - 13.4721 * m.log(tr) + 0.43577 * m.pow(tr, 6);
double f0p(double tr) => 6.09648 / (tr * tr) - 1.28862 / tr + 1.016082 * m.pow(tr, 5);
double f1p(double tr) => 15.6875 / (tr * tr) - 13.4721 / tr + 2.61462 * m.pow(tr, 5);

class Comp {
  final String id;
  final double tlo, thi, vf, tb, sg, mw, tc, pc, om, dhb, rho, cp0, dcp;
  final double cpvA, cpvB; // vapour Cp = cpvA + cpvB T (J/mol/K)
  final bool water;
  Comp(this.id, this.tlo, this.thi, this.vf, this.tb, this.sg, this.mw, this.tc, this.pc, this.om, this.dhb, this.rho,
      this.cp0, this.dcp, this.cpvA, this.cpvB, {this.water = false});
  double lnPsat(double t) {
    if (water) return 73.649 - 7258.2 / t - 7.3037 * m.log(t) + 4.1653e-6 * t * t;
    final tr = t / tc;
    return m.log(pc * 1e5) + f0(tr) + om * f1(tr);
  }

  double dlnPsat(double t) {
    if (water) return 7258.2 / (t * t) - 7.3037 / t + 2 * 4.1653e-6 * t;
    final tr = t / tc;
    return (f0p(tr) + om * f1p(tr)) / tc;
  }

  double psat(double t) => m.exp(lnPsat(t));
  /// (3.3) liquid enthalpy with the §3.3 reference (pure liquid at 298.15 K).
  double hL0(double t) {
    final d = t - t0;
    return cp0 * d + 0.5 * dcp * d * d;
  }

  /// M9 rule: crude components are referenced to their own saturated liquid at T_b (h_L(T_b) = 0).
  double hL(double t) => hL0(t) - hL0(tb);

  /// Vapour enthalpy, M9 rule: ΔH_vap(T_b) + ∫_{T_b}^{T} Cp_V dT (same T_b reference).
  double hV(double t) => dhb + cpvA * (t - tb) + 0.5 * cpvB * (t * t - tb * tb);

  /// v1.0 (§3.3) vapour enthalpy, 298.15 K reference: h_L(T) + Watson ΔH_vap(T) (0 above T_c). Comparison only.
  double hVwatson(double t) => hL0(t) + (t < tc ? dhb * m.pow((tc - t) / (tc - tb), 0.38) : 0.0);
  double get vStd => mw / (1000 * rho); // m³/mol at 15.6 °C
  double rhoL(double t) {
    // Rackett ratio §3.5.1, T_ref 288.71 K (pseudo); water 0.4945, 298.15 K
    final zra = water ? 0.4945 : 0.29056 - 0.08775 * om;
    final tref = water ? 298.15 : 288.71;
    final tt = m.min(t, 0.999 * tc);
    return rho * m.pow(zra, m.pow(1 - tref / tc, 2 / 7) - m.pow(1 - tt / tc, 2 / 7));
  }

  double sigma(double t) => water ? 0.072 : 1e-3 * (673.7 / kW) * m.pow(m.max(0.0, (tc - t) / tc), 1.232); // N/m
}

Comp pseudo(String id, double tloC, double thiC) {
  final vlo = volAt(tloC), vhi = volAt(thiC);
  final vf = (vhi - vlo) / 100;
  final tb = tbpAt((vlo + vhi) / 2) + 273.15;
  final sg = m.pow(1.8 * tb, 1 / 3) / kW;
  final mw = 1.6607e-4 * m.pow(tb, 2.1962) * m.pow(sg, -1.0164);
  final tc = 19.06232 * m.pow(tb, 0.58848) * m.pow(sg, 0.3596);
  final pc = 5.53027e7 * m.pow(tb, -2.3125) * m.pow(sg, 2.3201); // bar
  final tbr = tb / tc;
  final om = (m.log(1.01325 / pc) - f0(tbr)) / f1(tbr);
  final psi = tbr * tbr * (f0p(tbr) + om * f1p(tbr));
  final dz = m.sqrt(1 - (1.01325 / pc) / (tbr * tbr * tbr));
  final dhb = rGas * tc * psi * dz;
  final rho = 999.0 * sg;
  final a = 4.1868 * (0.055 * kW + 0.35);
  final cpkg = a * ((0.6811 - 0.308 * sg) + (0.000815 - 0.000306 * sg) * (1.8 * t0 - 459.67));
  final dcpkg = a * (0.000815 - 0.000306 * sg) * 1.8;
  // Fallon–Watson vapour Cp: c_p [Btu/lb/°F] = (4 − SG)(t_°F + 670)/6450 -> J/mol/K = MW · 4.1868 · …
  final cv = mw * 4.1868 * (4 - sg) / 6450;
  return Comp(id, tloC, thiC, vf, tb, sg.toDouble(), mw.toDouble(), tc.toDouble(), pc.toDouble(), om, dhb, rho,
      cpkg * mw, dcpkg * mw, cv * 210.33, cv * 1.8);
}

// water: PHYSICS §2.1 row; vapour Cp = 30.2 + 0.0104 T (fit to ideal-gas steam, quoted from memory)
final water = Comp('water', 100, 100, 0, 373.15, 1.0, 18.015, 647.10, 220.64, 0.345, 40660, 997.0, 75.3, 0.01, 30.2,
    0.0104,
    water: true);

final List<Comp> pcs = [for (var i = 0; i < 9; i++) pseudo('PC${i + 1}', cutsC[i], cutsC[i + 1])];

/// Feed mole fractions from the assay volume fractions.
List<double> crudeZ() {
  final n = [for (final c in pcs) c.vf / c.vStd];
  final s = n.reduce((a, b) => a + b);
  return [for (final v in n) v / s];
}

double vStdMix(List<double> x) {
  var v = 0.0;
  for (var i = 0; i < 9; i++) v += x[i] * pcs[i].vStd;
  return v;
}

double bubbleT(List<double> x, double pHC, double tg) {
  var t = tg;
  for (var it = 0; it < 60; it++) {
    var s = 0.0, ds = 0.0;
    for (var i = 0; i < 9; i++) {
      final kx = x[i] * pcs[i].psat(t) / pHC;
      s += kx;
      ds += kx * pcs[i].dlnPsat(t);
    }
    var dt = -m.log(s) / (ds / s);
    if (dt > 30) dt = 30;
    if (dt < -30) dt = -30;
    t += dt;
    if (dt.abs() < 1e-10) break;
  }
  return t;
}

double hLmix(List<double> x, double t) {
  var h = 0.0;
  for (var i = 0; i < 9; i++) h += x[i] * pcs[i].hL(t);
  return h;
}

double hVmix(List<double> y, double t) {
  var h = 0.0;
  for (var i = 0; i < 9; i++) h += y[i] * pcs[i].hV(t);
  return h;
}

class Flash {
  double beta = 0;
  List<double> x = List.filled(9, 0), y = List.filled(9, 0);
  double h = 0;
}

Flash flash(List<double> z, double t, double p) {
  final k = [for (final c in pcs) c.psat(t) / p];
  double f(double b) {
    var s = 0.0;
    for (var i = 0; i < 9; i++) s += z[i] * (k[i] - 1) / (1 + b * (k[i] - 1));
    return s;
  }

  final r = Flash();
  double b;
  if (f(0) <= 0) {
    b = 0;
  } else if (f(1) >= 0) {
    b = 1;
  } else {
    var lo = 0.0, hi = 1.0;
    for (var it = 0; it < 200; it++) {
      final mid = 0.5 * (lo + hi);
      if (f(mid) > 0) lo = mid; else hi = mid;
    }
    b = 0.5 * (lo + hi);
  }
  r.beta = b;
  for (var i = 0; i < 9; i++) {
    r.x[i] = z[i] / (1 + b * (k[i] - 1));
    r.y[i] = k[i] * r.x[i];
  }
  r.h = (1 - b) * hLmix(r.x, t) + b * hVmix(r.y, t);
  return r;
}

// ---------------------------------------------------------------- product TBP and D86 (§9.6)
/// Product TBP (°C) at product vol % p, with each pseudo-component spread linearly over its cut range.
double productTbp(List<double> x, double p) {
  final v = [for (var i = 0; i < 9; i++) x[i] * pcs[i].vStd];
  final s = v.reduce((a, b) => a + b);
  var cum = 0.0;
  for (var i = 0; i < 9; i++) {
    final share = 100 * v[i] / s;
    if (share <= 0) continue;
    if (cum + share >= p || i == 8) {
      final f = ((p - cum) / share).clamp(0.0, 1.0);
      return pcs[i].tlo + f * (pcs[i].thi - pcs[i].tlo);
    }
    cum += share;
  }
  return pcs[8].thi;
}

/// Daubert (1994) TBP -> D86. Input TBP (°C) at 0,10,30,50,70,90,100; output D86 (°C) at 0,5,10,30,50,70,90,95,100.
List<double> d86(List<double> t) {
  final f = [for (final c in t) 1.8 * c + 32];
  double inv(double dt, double a, double b) => m.pow(m.max(0.0, dt) / a, 1 / b).toDouble();
  final d50 = m.pow(f[3] / 0.8718, 1 / 1.0258).toDouble();
  final d30 = d50 - inv(f[3] - f[2], 3.0305, 0.8008);
  final d10 = d30 - inv(f[2] - f[1], 4.9004, 0.7164);
  final d0 = d10 - inv(f[1] - f[0], 7.4012, 0.6024);
  final d70 = d50 + inv(f[4] - f[3], 2.5282, 0.8200);
  final d90 = d70 + inv(f[5] - f[4], 3.0419, 0.7550);
  final d100 = d90 + inv(f[6] - f[5], 0.1180, 1.6606);
  final r = [d0, (d0 + d10) / 2, d10, d30, d50, d70, d90, (d90 + d100) / 2, d100];
  return [for (final v in r) (v - 32) / 1.8];
}

const d86Pts = [0.0, 10.0, 30.0, 50.0, 70.0, 90.0, 100.0];

/// D86 of a product from its pseudo-component composition. [trim] = vol % cut off each tail for the 0 % and 100 %
/// TBP points (M9 rule: 1.0).
List<double> productD86(List<double> x, {double trim = 1.0}) {
  final t = [
    for (final p in d86Pts) productTbp(x, p == 0 ? trim : (p == 100 ? 100 - trim : p))
  ];
  return d86(t);
}

/// Ideal (perfect) cut of the assay between two TBP temperatures: TBP at product vol %.
List<double> idealCutD86(double tlo, double thi) {
  final vlo = volAt(tlo), vhi = volAt(thi);
  return d86([for (final p in d86Pts) tbpAt(vlo + p / 100 * (vhi - vlo))]);
}

// ---------------------------------------------------------------- dense LU
List<double> solveDense(List<List<double>> a, List<double> b) {
  final n = b.length;
  for (var c = 0; c < n; c++) {
    var piv = c;
    var best = a[c][c].abs();
    for (var r = c + 1; r < n; r++) {
      if (a[r][c].abs() > best) {
        best = a[r][c].abs();
        piv = r;
      }
    }
    if (piv != c) {
      final t = a[c];
      a[c] = a[piv];
      a[piv] = t;
      final tb = b[c];
      b[c] = b[piv];
      b[piv] = tb;
    }
    final d = a[c][c];
    for (var r = c + 1; r < n; r++) {
      final f = a[r][c] / d;
      if (f == 0) continue;
      final ar = a[r], ac = a[c];
      for (var k = c; k < n; k++) ar[k] -= f * ac[k];
      b[r] -= f * b[c];
    }
  }
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var s = b[r];
    for (var k = r + 1; k < n; k++) s -= a[r][k] * x[k];
    x[r] = s / a[r][r];
  }
  return x;
}

String f(num v, [int d = 2]) => v.toStringAsFixed(d);
