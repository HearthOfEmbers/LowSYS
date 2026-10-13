// Independent crude reference (validator, M9): PHYSICS.md 9.1, 9.2 (feed flash), 9.6 written from the spec text
// (docs/milestones/M9.md), no engine imports and no prototype code. Temperatures in K unless named C.
library;

import 'dart:math' as math;

const double rGas = 8.314462618;
const List<double> assayVol = [0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100];
const List<double> assayTbpC = [20, 70, 100, 165, 230, 290, 350, 405, 465, 535, 620, 680, 760];
const List<double> cutsC = [20, 90, 150, 200, 250, 300, 350, 425, 525, 760];
const double kwRef = 11.9;

double _interp(List<double> xs, List<double> ys, double x) {
  if (x <= xs.first) return ys.first;
  for (var k = 0; k < xs.length - 1; k++) {
    if (x <= xs[k + 1]) return ys[k] + (ys[k + 1] - ys[k]) * (x - xs[k]) / (xs[k + 1] - xs[k]);
  }
  return ys.last;
}

double assayTbpAtC(double vol) => _interp(assayVol, assayTbpC, vol);
double assayVolAtC(double tC) => _interp(assayTbpC, assayVol, tC);

/// Lee-Kesler ln(Psat/Pc) terms.
double lkF0(double tr) => 5.92714 - 6.09648 / tr - 1.28862 * math.log(tr) + 0.169347 * math.pow(tr, 6);
double lkF1(double tr) => 15.2518 - 15.6875 / tr - 13.4721 * math.log(tr) + 0.43577 * math.pow(tr, 6);

class PcRef {
  final double tLoC, tHiC, vol, tb, sg, mw, tc, pcBar, omega, dHvap, rho, cp0, dcp, aV, bV;
  PcRef(this.tLoC, this.tHiC, this.vol, this.tb, this.sg, this.mw, this.tc, this.pcBar, this.omega, this.dHvap, this.rho,
      this.cp0, this.dcp, this.aV, this.bV);

  /// m3 at 15.6 C per mol.
  double get vStd => mw / (1000 * rho);
  double psat(double t) => 1e5 * pcBar * math.exp(lkF0(t / tc) + omega * lkF1(t / tc));
  double hL(double t) {
    double f(double tt) => cp0 * (tt - 298.15) + 0.5 * dcp * (tt - 298.15) * (tt - 298.15);
    return f(t) - f(tb);
  }

  double hV(double t) => dHvap + aV * (t - tb) + 0.5 * bV * (t * t - tb * tb);
}

List<PcRef> pseudoRef({double kw = kwRef}) {
  final out = <PcRef>[];
  for (var i = 0; i < cutsC.length - 1; i++) {
    final vLo = assayVolAtC(cutsC[i]), vHi = assayVolAtC(cutsC[i + 1]);
    final tb = assayTbpAtC(0.5 * (vLo + vHi)) + 273.15;
    final sg = math.pow(1.8 * tb, 1 / 3) / kw;
    final mw = 1.6607e-4 * math.pow(tb, 2.1962) * math.pow(sg, -1.0164);
    final tc = 19.06232 * math.pow(tb, 0.58848) * math.pow(sg, 0.3596);
    final pc = 5.53027e7 * math.pow(tb, -2.3125) * math.pow(sg, 2.3201);
    final tbr = tb / tc;
    final om = (math.log(1.01325 / pc) - lkF0(tbr)) / lkF1(tbr);
    final d0 = 6.09648 / (tbr * tbr) - 1.28862 / tbr + 1.016082 * math.pow(tbr, 5);
    final d1 = 15.6875 / (tbr * tbr) - 13.4721 / tbr + 2.61462 * math.pow(tbr, 5);
    final dz = math.sqrt(1 - (1.01325 / pc) / (tbr * tbr * tbr));
    final dh = rGas * tc * tbr * tbr * (d0 + om * d1) * dz;
    final k = 4.1868 * (0.055 * kw + 0.35);
    final cp0 = k * ((0.6811 - 0.308 * sg) + (0.000815 - 0.000306 * sg) * (1.8 * 298.15 - 459.67)) * mw;
    final dcp = k * (0.000815 - 0.000306 * sg) * 1.8 * mw;
    final fw = mw * 4.1868 * (4 - sg) / 6450;
    out.add(PcRef(cutsC[i], cutsC[i + 1], (vHi - vLo) / 100, tb, sg, mw, tc, pc, om, dh, 999.0 * sg, cp0, dcp,
        fw * 210.33, fw * 1.8));
  }
  return out;
}

/// Steam (9.2): a_V 30.2, b_V 0.0104, T_b 373.15 K; the latent heat cancels in differences.
double hVsteamDiff(double t1, double t2) => 30.2 * (t2 - t1) + 0.5 * 0.0104 * (t2 * t2 - t1 * t1);

/// Bulk crude: (SG, API, mean MW, mol per m3 at 15.6 C, kg per m3).
(double, double, double, double, double) bulkRef(List<PcRef> pcs) {
  var sg = 0.0, mass = 0.0, mol = 0.0;
  for (final p in pcs) {
    sg += p.vol * p.sg;
    mass += p.vol * p.rho;
    mol += p.vol * p.rho / p.mw * 1000;
  }
  return (sg, 141.5 / sg - 131.5, 1000 * mass / mol, mol, mass);
}

/// Molar feed composition of the crude.
List<double> feedZRef(List<PcRef> pcs) {
  final n = [for (final p in pcs) p.vol * p.rho / p.mw];
  final s = n.fold(0.0, (a, b) => a + b);
  return [for (final v in n) v / s];
}

/// Isothermal flash (Raoult, LK Psat; no steam): (beta molar, vapour vol % of the feed at 15.6 C, h per mol of feed).
(double, double, double) feedFlashRef(List<PcRef> pcs, double t, double p) {
  final z = feedZRef(pcs);
  final k = [for (final c in pcs) c.psat(t) / p];
  double rr(double b) {
    var s = 0.0;
    for (var i = 0; i < z.length; i++) {
      s += z[i] * (k[i] - 1) / (1 + b * (k[i] - 1));
    }
    return s;
  }

  var lo = 0.0, hi = 1.0;
  for (var it = 0; it < 200; it++) {
    final m = 0.5 * (lo + hi);
    if (rr(m) > 0) {
      lo = m;
    } else {
      hi = m;
    }
  }
  final b = 0.5 * (lo + hi);
  var vV = 0.0, vF = 0.0, h = 0.0;
  for (var i = 0; i < z.length; i++) {
    final x = z[i] / (1 + b * (k[i] - 1)), y = k[i] * x;
    vV += b * y * pcs[i].vStd;
    vF += z[i] * pcs[i].vStd;
    h += (1 - b) * x * pcs[i].hL(t) + b * y * pcs[i].hV(t);
  }
  return (b, 100 * vV / vF, h);
}

/// Daubert (1994) TBP -> D86, PHYSICS.md 9.6 constants, in F. [tbp7C]: TBP (C) at 0,10,30,50,70,90,100 %.
/// Returns D86 (C) at 0,5,10,30,50,70,90,95,100 %.
List<double> daubertRef(List<double> tbp7C) {
  final f = [for (final c in tbp7C) 1.8 * c + 32];
  double back(double d, double a, double b) => math.pow(math.max(0.0, d) / a, 1 / b).toDouble();
  final d50 = math.pow(f[3] / 0.8718, 1 / 1.0258).toDouble();
  final d30 = d50 - back(f[3] - f[2], 3.0305, 0.8008);
  final d10 = d30 - back(f[2] - f[1], 4.9004, 0.7164);
  final d0 = d10 - back(f[1] - f[0], 7.4012, 0.6024);
  final d70 = d50 + back(f[4] - f[3], 2.5282, 0.8200);
  final d90 = d70 + back(f[5] - f[4], 3.0419, 0.7550);
  final d100 = d90 + back(f[6] - f[5], 0.1180, 1.6606);
  return [for (final v in [d0, (d0 + d10) / 2, d10, d30, d50, d70, d90, (d90 + d100) / 2, d100]) (v - 32) / 1.8];
}

const List<double> tbpPts = [0, 10, 30, 50, 70, 90, 100];

/// Ideal (assay, untrimmed) cut between TBP cut points (C): (yield vol %, D86 C at 0..100 as daubertRef).
(double, List<double>) idealCutRef(double loC, double hiC) {
  final vlo = assayVolAtC(loC), vhi = assayVolAtC(hiC);
  return (vhi - vlo, daubertRef([for (final p in tbpPts) assayTbpAtC(vlo + p / 100 * (vhi - vlo))]));
}

/// Product TBP (C) at product vol % [p] from pseudo-component VOLUME shares [v] (any scale), each spread linearly
/// over its cut range, with the 9.6 trim (0 % read at [trim] %, 100 % at 100 - [trim] %).
double productTbpRef(List<PcRef> pcs, List<double> v, double p, {double trim = 1.0}) {
  final pp = p < trim ? trim : (p > 100 - trim ? 100 - trim : p);
  final s = v.fold(0.0, (a, b) => a + b);
  var cum = 0.0;
  for (var i = 0; i < pcs.length; i++) {
    final sh = 100 * v[i] / s;
    if (sh <= 0) continue;
    if (cum + sh >= pp) return pcs[i].tLoC + (pp - cum) / sh * (pcs[i].tHiC - pcs[i].tLoC);
    cum += sh;
  }
  return pcs.last.tHiC;
}

/// Lumped ideal cut: each pseudo-component's assay volume inside [loC, hiC], through the product path (1 % trim).
List<double> lumpedCutRef(List<PcRef> pcs, double loC, double hiC) {
  final v = [
    for (final c in pcs)
      math.max(0.0, assayVolAtC(math.min(hiC, c.tHiC)) - assayVolAtC(math.max(loC, c.tLoC)))
  ];
  return daubertRef([for (final p in tbpPts) productTbpRef(pcs, v, p)]);
}
