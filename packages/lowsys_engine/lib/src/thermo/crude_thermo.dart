// Crude fractionation thermodynamics (PHYSICS.md 9.1, 9.3): the assay, the pseudo-components and the M9 enthalpy rule.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'component.dart';

const double _r = 8.314462618, _t0 = 298.15;

double _f0(double tr) => 5.92714 - 6.09648 / tr - 1.28862 * math.log(tr) + 0.169347 * math.pow(tr, 6);
double _f1(double tr) => 15.2518 - 15.6875 / tr - 13.4721 * math.log(tr) + 0.43577 * math.pow(tr, 6);
double _f0p(double tr) => 6.09648 / (tr * tr) - 1.28862 / tr + 1.016082 * math.pow(tr, 5);
double _f1p(double tr) => 15.6875 / (tr * tr) - 13.4721 / tr + 2.61462 * math.pow(tr, 5);

double _lerp(List<double> xs, List<double> ys, double x) {
  if (x <= xs.first) return ys.first;
  if (x >= xs.last) return ys.last;
  var k = 0;
  while (xs[k + 1] < x) {
    k++;
  }
  return ys[k] + (ys[k + 1] - ys[k]) * (x - xs[k]) / (xs[k + 1] - xs[k]);
}

/// Extra data of a pseudo-component beyond [Component] (ENGINE_API.md 3.1): the cut range and the Fallon-Watson
/// vapour heat capacity Cp_V = cpVA + cpVB T (J/mol/K).
@immutable
class PseudoInfo {
  /// K, the cut range (TBP spread of PHYSICS.md 9.6 step 2).
  final double tLo, tHi;
  final double sg, kw;

  /// Share of the crude (vol, 15.6 C).
  final double volFrac;
  final double cpVA, cpVB;
  const PseudoInfo(
      {required this.tLo,
      required this.tHi,
      required this.sg,
      required this.kw,
      required this.volFrac,
      required this.cpVA,
      required this.cpVB});
}

/// A pseudo-component: the common [Component] data plus the crude-specific [PseudoInfo].
@immutable
class PseudoComponent {
  final Component comp;
  final PseudoInfo info;
  const PseudoComponent(this.comp, this.info);
}

/// The shipped synthetic light crude (about 32 API): TBP table and cut boundaries, PHYSICS.md 9.1.
@immutable
class Assay {
  /// vol % distilled and the TBP temperature (C).
  final List<double> tbpVol, tbpC;

  /// Cut boundaries (C): n + 1 values give n pseudo-components.
  final List<double> cutsC;

  /// Watson factor.
  final double kw;
  const Assay({required this.tbpVol, required this.tbpC, required this.cutsC, this.kw = 11.9});

  static const Assay light = Assay(
    tbpVol: [0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100],
    tbpC: [20, 70, 100, 165, 230, 290, 350, 405, 465, 535, 620, 680, 760],
    cutsC: [20, 90, 150, 200, 250, 300, 350, 425, 525, 760],
  );

  /// TBP temperature (C) at crude vol %.
  double tbpAt(double v) => _lerp(tbpVol, tbpC, v);

  /// Crude vol % distilled at TBP temperature (C).
  double volAt(double t) => _lerp(tbpC, tbpVol, t);

  int get count => cutsC.length - 1;

  /// PHYSICS.md 9.1: Riazi-Daubert properties, Lee-Kesler omega and latent heat, Watson-Nelson Cp, Fallon-Watson Cp_V.
  List<PseudoComponent> pseudoComponents() {
    final out = <PseudoComponent>[];
    for (var i = 0; i < count; i++) {
      final vlo = volAt(cutsC[i]), vhi = volAt(cutsC[i + 1]);
      final vf = (vhi - vlo) / 100;
      final tb = tbpAt((vlo + vhi) / 2) + 273.15;
      final sg = math.pow(1.8 * tb, 1 / 3) / kw;
      final mw = 1.6607e-4 * math.pow(tb, 2.1962) * math.pow(sg, -1.0164);
      final tc = 19.06232 * math.pow(tb, 0.58848) * math.pow(sg, 0.3596);
      final pcBar = 5.53027e7 * math.pow(tb, -2.3125) * math.pow(sg, 2.3201);
      final tbr = tb / tc;
      final om = (math.log(1.01325 / pcBar) - _f0(tbr)) / _f1(tbr);
      final psi = tbr * tbr * (_f0p(tbr) + om * _f1p(tbr));
      final dz = math.sqrt(1 - (1.01325 / pcBar) / (tbr * tbr * tbr));
      final dhb = _r * tc * psi * dz;
      final rho = 999.0 * sg;
      final a = 4.1868 * (0.055 * kw + 0.35);
      final cpkg = a * ((0.6811 - 0.308 * sg) + (0.000815 - 0.000306 * sg) * (1.8 * _t0 - 459.67));
      final dcpkg = a * (0.000815 - 0.000306 * sg) * 1.8;
      final cv = mw * 4.1868 * (4 - sg) / 6450;
      final comp = Component(
        id: 'PC${i + 1}',
        name: 'Pseudo-component ${i + 1}',
        mw: mw,
        tb: tb,
        tc: tc,
        pc: pcBar * 1e5,
        omega: om,
        dHvapTb: dhb,
        cp0: cpkg * mw,
        dCp: dcpkg * mw,
        rhoRef: rho,
        tRef: 288.71,
        sigmaRef: 0,
        vpKind: VaporPressureKind.leeKesler,
        vpCoeffs: const [],
      );
      out.add(PseudoComponent(
          comp,
          PseudoInfo(
              tLo: cutsC[i] + 273.15,
              tHi: cutsC[i + 1] + 273.15,
              sg: sg,
              kw: kw,
              volFrac: vf,
              cpVA: cv * 210.33,
              cpVB: cv * 1.8)));
    }
    return out;
  }
}

/// Crude thermodynamics at array level (no allocation in the hot paths). Components 0..nHc-1 are the pseudo-components;
/// index [nHc] is water, which exists as vapour only (PHYSICS.md 9.3).
class CrudeThermo {
  final Assay assay;
  final int nHc;
  final List<PseudoComponent> pcs;
  final Float64List tb, tc, lnPc, om, mw, dhb, cp0, dcp, cvA, cvB, vStd, rho, tLo, tHi, volFrac;

  /// Water, PHYSICS.md 2.1 and (9.2): a_V 30.2, b_V 0.0104.
  static const double waterA = 30.2, waterB = 0.0104, waterMw = 18.015, waterTb = 373.15, waterDhb = 40660.0;

  CrudeThermo._(this.assay, this.pcs)
      : nHc = pcs.length,
        tb = Float64List.fromList([for (final p in pcs) p.comp.tb]),
        tc = Float64List.fromList([for (final p in pcs) p.comp.tc]),
        lnPc = Float64List.fromList([for (final p in pcs) math.log(p.comp.pc)]),
        om = Float64List.fromList([for (final p in pcs) p.comp.omega]),
        mw = Float64List.fromList([for (final p in pcs) p.comp.mw]),
        dhb = Float64List.fromList([for (final p in pcs) p.comp.dHvapTb]),
        cp0 = Float64List.fromList([for (final p in pcs) p.comp.cp0]),
        dcp = Float64List.fromList([for (final p in pcs) p.comp.dCp]),
        cvA = Float64List.fromList([for (final p in pcs) p.info.cpVA]),
        cvB = Float64List.fromList([for (final p in pcs) p.info.cpVB]),
        vStd = Float64List.fromList([for (final p in pcs) p.comp.mw / (1000 * p.comp.rhoRef)]),
        rho = Float64List.fromList([for (final p in pcs) p.comp.rhoRef]),
        tLo = Float64List.fromList([for (final p in pcs) p.info.tLo]),
        tHi = Float64List.fromList([for (final p in pcs) p.info.tHi]),
        volFrac = Float64List.fromList([for (final p in pcs) p.info.volFrac]);

  factory CrudeThermo([Assay assay = Assay.light]) => CrudeThermo._(assay, assay.pseudoComponents());

  /// ln P_sat (Pa) of component [i] at [t] (K), Lee-Kesler for pseudo-components, DIPPR-101 for water.
  double lnPsat(int i, double t) {
    if (i == nHc) return 73.649 - 7258.2 / t - 7.3037 * math.log(t) + 4.1653e-6 * t * t;
    final tr = t / tc[i];
    final t2 = tr * tr, t3 = t2 * tr, t6 = t3 * t3;
    final lt = math.log(tr);
    final f0 = 5.92714 - 6.09648 / tr - 1.28862 * lt + 0.169347 * t6;
    final f1 = 15.2518 - 15.6875 / tr - 13.4721 * lt + 0.43577 * t6;
    return lnPc[i] + f0 + om[i] * f1;
  }

  /// d ln P_sat / dT (1/K).
  double dlnPsat(int i, double t) {
    if (i == nHc) return 7258.2 / (t * t) - 7.3037 / t + 2 * 4.1653e-6 * t;
    final tr = t / tc[i];
    final t2 = tr * tr, t5 = t2 * t2 * tr;
    return ((6.09648 / t2 - 1.28862 / tr + 1.016082 * t5) + om[i] * (15.6875 / t2 - 13.4721 / tr + 2.61462 * t5)) /
        tc[i];
  }

  double psat(int i, double t) => math.exp(lnPsat(i, t));

  /// K_i = P_sat,i(T) / P_HC for every pseudo-component into [k] at [off]; the log-slopes d ln P_sat / dT into [dl].
  void kValues(Float64List k, int off, double t, double pHc, Float64List dl) {
    final lp = math.log(pHc);
    for (var i = 0; i < nHc; i++) {
      final tr = t / tc[i];
      final t2 = tr * tr, t3 = t2 * tr, t5 = t3 * t2, t6 = t3 * t3;
      final lt = math.log(tr);
      final f0 = 5.92714 - 6.09648 / tr - 1.28862 * lt + 0.169347 * t6;
      final f1 = 15.2518 - 15.6875 / tr - 13.4721 * lt + 0.43577 * t6;
      k[off + i] = math.exp(lnPc[i] + f0 + om[i] * f1 - lp);
      dl[off + i] =
          ((6.09648 / t2 - 1.28862 / tr + 1.016082 * t5) + om[i] * (15.6875 / t2 - 13.4721 / tr + 2.61462 * t5)) /
              tc[i];
    }
  }

  /// Bubble point (K) of liquid [x] (nHc entries at [off]) at the hydrocarbon partial pressure [pHc]; Newton from [tg].
  double bubbleT(Float64List x, int off, double pHc, double tg) {
    var t = tg;
    for (var it = 0; it < 40; it++) {
      var s = 0.0, ds = 0.0;
      for (var i = 0; i < nHc; i++) {
        final kx = x[off + i] * math.exp(lnPsat(i, t)) / pHc;
        s += kx;
        ds += kx * dlnPsat(i, t);
      }
      if (!(s > 0) || !(ds > 0)) return t;
      var dt = -math.log(s) / (ds / s);
      if (dt > 30) dt = 30;
      if (dt < -30) dt = -30;
      t += dt;
      if (dt.abs() < 1e-9) break;
    }
    return t;
  }

  /// Liquid enthalpy (J/mol) of component [i], T_b reference (9.1); water by the same rule with the Section 2.1 Cp.
  double hLi(int i, double t) {
    if (i == nHc) {
      const cp = 75.3, d = 0.01;
      double f(double tt) => cp * (tt - _t0) + 0.5 * d * (tt - _t0) * (tt - _t0);
      return f(t) - f(waterTb);
    }
    final d = t - _t0, db = tb[i] - _t0;
    return cp0[i] * (d - db) + 0.5 * dcp[i] * (d * d - db * db);
  }

  /// Vapour enthalpy (J/mol) of component [i], anchored at T_b (9.2).
  double hVi(int i, double t) {
    if (i == nHc) return waterDhb + waterA * (t - waterTb) + 0.5 * waterB * (t * t - waterTb * waterTb);
    return dhb[i] + cvA[i] * (t - tb[i]) + 0.5 * cvB[i] * (t * t - tb[i] * tb[i]);
  }

  double hLmix(Float64List x, int off, double t) {
    var h = 0.0;
    for (var i = 0; i < nHc; i++) {
      h += x[off + i] * hLi(i, t);
    }
    return h;
  }

  double hVmix(Float64List y, int off, double t) {
    var h = 0.0;
    for (var i = 0; i < nHc; i++) {
      h += y[off + i] * hVi(i, t);
    }
    return h;
  }

  double hVwater(double t) => hVi(nHc, t);
  double hLwater(double t) => hLi(nHc, t);

  /// Rackett liquid density (kg/m3) of pseudo-component [i].
  double rhoL(int i, double t) {
    final zra = 0.29056 - 0.08775 * om[i];
    final tt = math.min(t, 0.999 * tc[i]);
    return rho[i] * math.pow(zra, math.pow(1 - 288.71 / tc[i], 2 / 7) - math.pow(1 - tt / tc[i], 2 / 7));
  }

  /// Surface tension (N/m), Riazi form, zero above T_c (PHYSICS.md 3.5.3, M9).
  double sigma(int i, double t) => 1e-3 * (673.7 / assay.kw) * math.pow(math.max(0.0, (tc[i] - t) / tc[i]), 1.232);

  /// Feed mole fractions from the assay volume fractions.
  Float64List feedZ() {
    final n = [for (var i = 0; i < nHc; i++) volFrac[i] / vStd[i]];
    final s = n.fold(0.0, (a, b) => a + b);
    return Float64List.fromList([for (final v in n) v / s]);
  }

  /// Volume (m3, 15.6 C) of one mole of liquid [x].
  double vStdMix(Float64List x, int off) {
    var v = 0.0;
    for (var i = 0; i < nHc; i++) {
      v += x[off + i] * vStd[i];
    }
    return v;
  }

  double mwMix(Float64List x, int off) {
    var m = 0.0;
    for (var i = 0; i < nHc; i++) {
      m += x[off + i] * mw[i];
    }
    return m;
  }

  /// Isothermal flash of [z] at [t] and [p] (PHYSICS.md 3.6.3), no steam.
  CrudeFlash flash(Float64List z, double t, double p) {
    final k = Float64List(nHc);
    for (var i = 0; i < nHc; i++) {
      k[i] = psat(i, t) / p;
    }
    double f(double b) {
      var s = 0.0;
      for (var i = 0; i < nHc; i++) {
        s += z[i] * (k[i] - 1) / (1 + b * (k[i] - 1));
      }
      return s;
    }

    double b;
    if (f(0) <= 0) {
      b = 0;
    } else if (f(1) >= 0) {
      b = 1;
    } else {
      var lo = 0.0, hi = 1.0;
      for (var it = 0; it < 100; it++) {
        final mid = 0.5 * (lo + hi);
        if (f(mid) > 0) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      b = 0.5 * (lo + hi);
    }
    final x = Float64List(nHc), y = Float64List(nHc);
    for (var i = 0; i < nHc; i++) {
      x[i] = z[i] / (1 + b * (k[i] - 1));
      y[i] = k[i] * x[i];
    }
    final h = (1 - b) * hLmix(x, 0, t) + b * hVmix(y, 0, t);
    return CrudeFlash(b, x, y, h);
  }
}

class CrudeFlash {
  final double beta;
  final Float64List x, y;
  final double h;
  const CrudeFlash(this.beta, this.x, this.y, this.h);
}
