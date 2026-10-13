// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import '../config/tray_geometry.dart';
import '../core/ids.dart';
import '../faults/fault_effects.dart';
import '../thermo/tier1_constant_alpha.dart';
import 'column_state.dart';

/// Derived tray geometry (PHYSICS.md 5.1).
class TrayGeometryDerived {
  final double aT, aD, aN, aA, lW;
  const TrayGeometryDerived._(this.aT, this.aD, this.aN, this.aA, this.lW);
  factory TrayGeometryDerived.from(TrayGeometry g) {
    final aT = g.areaTotal, aD = g.downcomerFraction * aT;
    return TrayGeometryDerived._(aT, aD, aT - aD, aT - 2 * aD, g.weirLength);
  }
}

/// Closed-form tray correlations of PHYSICS.md 5, exposed for the overlay and tests.
abstract final class TrayCorrelations {
  /// PHYSICS.md 5.3 Bennett froth density: alpha_e = exp(-12.55 K_s^0.91).
  static double bennettAlphaE(double ks) =>
      ks <= 0 ? 1.0 : math.exp(-12.55 * math.pow(ks, 0.91));

  /// PHYSICS.md 5.3: C = 0.501 + 0.438 exp(-137.8 h_w).
  static double bennettC(double hw) => 0.501 + 0.438 * math.exp(-137.8 * hw);

  /// PHYSICS.md 5.5 Lygeros-Magoulas fit of Fair's flooding chart (tray spacing in m, result m/s).
  static double csbLygerosMagoulas(double tsMetres, double fLV) =>
      0.0105 +
      8.127e-4 *
          math.pow(tsMetres * 1000, 0.755) *
          math.exp(-1.463 * math.pow(fLV, 0.842));

  /// PHYSICS.md (5.7) entrainment fraction fit, capped at 0.6.
  static double psiEq(double fLV, double phi) =>
      math.min(0.60, 4.0e-5 * math.pow(fLV / 0.1, -0.83) * math.exp(7.5 * phi));

  /// PHYSICS.md (5.13) weeping fraction from the stability factor.
  static double weepFraction(double stability) =>
      ((0.75 - stability) / 0.55).clamp(0.0, 1.0);

  /// PHYSICS.md (5.15) orifice drainage constant kappa (mol^0.5/s): L_dump = kappa max(0, sqrt(M) - sqrt(Mc)).
  static double dumpKappa(double aDrain, double aAct, double vL) =>
      0.6 * aDrain * math.sqrt(2 * 9.80665 * vL / aAct) / vL;
}

/// Evaluates the tray hydraulics of PHYSICS.md 5 for every tray from the current state. Pure function of
/// (state, effective parameters): the stepper, the snapshot and the explain API all read these arrays, so
/// they cannot disagree (VALIDATION.md VC-21). No allocation.
class HydraulicSolver {
  final int nTrays, n, nc;
  final Tier1ConstantAlpha thermo;
  final TrayGeometry geom;
  final TrayGeometryDerived d;
  TrayType trayType;
  /// Top pressure (Pa); the Tier-2 stepper updates it every step.
  double pTop;
  final bool entrainment, weeping, downcomerLimit;

  // Outputs (index = stage; trays 1..N used)
  late final Float64List aAct,
      qIn,
      qOut,
      ks,
      alphaE,
      ahEff,
      uh,
      dpDry,
      hcl,
      froth,
      dp,
      pressure,
      fLV,
      csb,
      unf,
      phi,
      psiEq,
      entrain,
      eOv,
      mMax,
      fill,
      stab,
      weepW,
      bypass,
      weepFlow,
      kd,
      mcSqrt,
      hNorm,
      dcHead,
      lMax,
      hDc,
      dcFrac,
      mwL,
      rhoLs,
      rhoVs,
      sigmas,
      mwVin,
      mwVout,
      lWeir;
  late final Uint8List flags;
  double pressureDropTotal = 0;

  HydraulicSolver({
    required this.nTrays,
    required this.nc,
    required this.thermo,
    required this.geom,
    required this.trayType,
    required this.pTop,
    this.entrainment = true,
    this.weeping = true,
    this.downcomerLimit = true,
  })  : n = nTrays + 2,
        d = TrayGeometryDerived.from(geom) {
    Float64List f() => Float64List(n);
    aAct = f();
    qIn = f();
    qOut = f();
    ks = f();
    alphaE = f();
    ahEff = f();
    uh = f();
    dpDry = f();
    hcl = f();
    froth = f();
    dp = f();
    pressure = f();
    fLV = f();
    csb = f();
    unf = f();
    phi = f();
    psiEq = f();
    entrain = f();
    eOv = f();
    mMax = f();
    fill = f();
    stab = f();
    weepW = f();
    bypass = f();
    weepFlow = f();
    kd = f();
    mcSqrt = f();
    hNorm = f();
    dcHead = f();
    lMax = f();
    hDc = f();
    dcFrac = f();
    mwL = f();
    rhoLs = f()..fillRange(0, n, thermo.rhoL);
    rhoVs = f()..fillRange(0, n, thermo.rhoV);
    sigmas = f()..fillRange(0, n, thermo.sigma);
    mwVin = f();
    mwVout = f();
    lWeir = f();
    flags = Uint8List(n);
  }

  static const double _g = 9.80665;

  double get rhoL => thermo.rhoL;
  double get rhoV => thermo.rhoV;

  /// Bennett inverse: clear-liquid height of a tray carrying liquid [q] (m3/s) at froth density [ae].
  double normalHcl(double q, double ae) =>
      ae *
      (geom.weirHeight +
          TrayCorrelations.bennettC(geom.weirHeight) *
              math.pow(q / (d.lW * ae), 2.0 / 3.0));

  /// Fills the arrays from the state. [dt] only enters the cap on entrainment and the overflow time constant.
  void update(ColumnState s, EffectiveParams ep, double dt) {
    final N = nTrays;
    final aA = d.aA;
    final c = TrayCorrelations.bennettC(geom.weirHeight);
    final valve = trayType == TrayType.valve;
    final dh = valve ? 0.040 : geom.holeDiameter;
    pressure[1] = pTop;
    pressureDropTotal = 0;
    for (var j = 1; j <= N; j++) {
      final sB = ep.brokenS[j];
      final vl = s.vLiq[j];
      final rhoL = rhoLs[j], rhoV = rhoVs[j], sigma = sigmas[j];
      final sq = math.sqrt(rhoV / (rhoL - rhoV));
      var mwl = 0.0, mwvIn = 0.0, mwvOut = 0.0;
      for (var i = 0; i < nc; i++) {
        mwl += s.x[j * nc + i] * thermo.mw[i];
        mwvIn += s.y[(j + 1) * nc + i] * thermo.mw[i];
        mwvOut += s.y[j * nc + i] * thermo.mw[i];
      }
      mwL[j] = mwl;
      mwVin[j] = mwvIn;
      mwVout[j] = mwvOut;
      qIn[j] = s.vapor[j + 1] * mwvIn / (1000 * rhoV);
      qOut[j] = s.vapor[j] * mwvOut / (1000 * rhoV);
      final aa = aA * math.max(1 - sB, 0.02);
      aAct[j] = aa;
      // PHYSICS.md 5.1-5.3 froth density from the vapour loading on the nominal active area
      final k = qIn[j] / aA * sq;
      ks[j] = k;
      final ae = TrayCorrelations.bennettAlphaE(k) * ep.sfFroth[j];
      alphaE[j] = ae;
      // dry pressure drop (5.3 sieve, 5.4 valve), broken deck opens a large hole (PHYSICS.md 11, F04)
      final scale = ep.holeScale[j];
      double dd;
      double ah;
      double drainA;
      if (!valve) {
        ah = geom.holeFraction * aA * scale * (1 - sB) + sB * aA;
        ahEff[j] = ah;
        drainA = ah;
        final u = qIn[j] / ah;
        uh[j] = u;
        dd = rhoV / 2 * (u / geom.orificeCoeff) * (u / geom.orificeCoeff);
      } else {
        final aMin =
            (geom.valveClosedRatio * geom.valveOpenFraction * aA * scale) *
                    (1 - sB) +
                sB * aA;
        final aMax = (geom.valveOpenFraction * aA * scale) * (1 - sB) + sB * aA;
        ah = aMax;
        ahEff[j] = ah;
        drainA = aMin;
        final cv = geom.valveCoeff;
        final q = qIn[j];
        final dpc = rhoV / 2 * math.pow(q / (cv * aMin), 2).toDouble();
        if (dpc < geom.valveLiftDp) {
          dd = dpc;
          uh[j] = q / aMin;
        } else {
          final aBal = q / (cv * math.sqrt(2 * geom.valveLiftDp / rhoV));
          if (aBal <= aMax) {
            dd = geom.valveLiftDp;
            uh[j] = q / aBal;
          } else {
            dd = rhoV / 2 * math.pow(q / (cv * aMax), 2).toDouble();
            uh[j] = q / aMax;
          }
        }
      }
      dpDry[j] = dd;
      final h = s.holdup[j] * vl / aa;
      hcl[j] = h;
      froth[j] = ae > 0 ? h / ae : h;
      final arg = ae > 0 ? (h / ae - geom.weirHeight) / c : 0.0;
      lWeir[j] = arg > 0 ? d.lW * ae * arg * math.sqrt(arg) / vl : 0.0;
      // a broken deck cannot hold a liquid head: the opening drains it (deviation E20)
      dp[j] = dd + rhoL * _g * h * (1 - sB) + 4 * sigma / dh;
      pressure[j + 1] = pressure[j] + dp[j];
      pressureDropTotal += dp[j];
      // jet flooding (5.5)
      final vj = s.vapor[j];
      double f;
      if (vj > 1e-12 && mwvOut > 0) {
        f = (s.lbar[j] * mwl) / (vj * mwvOut) * math.sqrt(rhoV / rhoL);
      } else {
        f = 2.0;
      }
      f = f.clamp(0.01, 2.0);
      fLV[j] = f;
      final cs = TrayCorrelations.csbLygerosMagoulas(geom.traySpacing, f);
      csb[j] = cs;
      final ratio = ah / aA;
      final fHole = ratio >= 0.10 ? 1.0 : math.max(0.5, 5 * ratio + 0.5);
      final un = cs *
          math.pow(sigma / 0.020, 0.2) *
          math.sqrt((rhoL - rhoV) / rhoV) *
          ep.sfFlood[j] *
          fHole;
      unf[j] = un;
      final ph = (qOut[j] / d.aN) / un;
      phi[j] = ph;
      psiEq[j] = TrayCorrelations.psiEq(f, ph);
      // weeping and dumping (5.12-5.15)
      final hdry = dd / (rhoL * _g);
      final st = h > 1e-9 ? math.sqrt(hdry / h) : 1e6;
      stab[j] = st;
      final w = weeping ? TrayCorrelations.weepFraction(st) : 0.0;
      weepW[j] = w;
      bypass[j] = math.min(1.0, w + sB);
      kd[j] = weeping ? TrayCorrelations.dumpKappa(drainA, aa, vl) : 0.0;
      // holdup at which Phi = 0.2: h_cl = 25 h_dry (PHYSICS.md 5.15)
      mcSqrt[j] = weeping ? math.sqrt(25 * hdry * aa / vl) : double.infinity;
      // full-tray overflow (5.9)
      final mm = geom.traySpacing * ae * aa / vl;
      mMax[j] = mm;
      fill[j] = s.holdup[j] / mm;
      eOv[j] = (entrainment && st >= 0.2 && s.holdup[j] > mm)
          ? (s.holdup[j] - mm) / math.max(5.0, 4 * dt)
          : 0.0;
    }
    // second pass: downcomer backup (5.10, 5.11) needs the receiving tray's normal clear-liquid height
    for (var j = 1; j <= N; j++) {
      final vlj = s.vLiq[j];
      double hn;
      if (j + 1 <= N) {
        final q = s.liquid[j] * s.vLiq[j + 1];
        hn = alphaE[j + 1] > 0 ? normalHcl(q, alphaE[j + 1]) : 0.0;
      } else {
        hn = 0.0;
      }
      hNorm[j] = hn;
      final dpHead = dp[j] / (rhoL * _g);
      final phiDc = ep.phiDc[j];
      final lim = phiDc * (geom.traySpacing + geom.weirHeight);
      final head = lim - dpHead - hn;
      final hap = geom.apronClearance * ep.apronScale[j];
      dcHead[j] = head;
      lMax[j] = downcomerLimit
          ? d.lW * hap * math.sqrt(math.max(head, 0.0) / 0.166) / vlj
          : double.infinity;
      final uap = s.liquid[j] * vlj / (d.lW * hap);
      final hdc = dpHead + hn + 0.166 * uap * uap;
      hDc[j] = hdc;
      dcFrac[j] = hdc / lim;
    }
    finishEntrainment(s, dt);
  }

  /// Entrained flows from the filtered fraction state psi (5.8) plus the full-tray overflow (5.9), and
  /// the per-tray flag bits. Called by [update] and by the stepper after it advanced psi.
  void finishEntrainment(ColumnState s, double dt) {
    final N = nTrays;
    for (var j = 1; j <= N; j++) {
      double e = 0;
      if (entrainment) {
        final p = math.min(s.psi[j], 0.6);
        e = p / (1 - p) * s.liquid[j] + eOv[j];
        final cap = 0.3 * s.holdup[j] / dt;
        if (e > cap) e = cap;
      }
      entrain[j] = e;
      weepFlow[j] = bypass[j] * s.liquid[j - 1];
      var fl = 0;
      if (lMax[j] < double.infinity && lWeir[j] > lMax[j]) fl |= 1;
      if (weeping && s.holdup[j] > mcSqrt[j] * mcSqrt[j]) fl |= 2;
      if (fill[j] >= 1 && eOv[j] > 0) fl |= 4;
      if (hcl[j] < 0.002) fl |= 8;
      if (fill[j] >= 1 || phi[j] >= 1) fl |= 16;
      flags[j] = fl;
    }
    entrain[0] = 0;
    entrain[N + 1] = 0;
  }

  /// Equilibrium value of the entrainment fraction used to initialise the filter state.
  double entrainmentFilterInit(int j) => entrainment ? psiEq[j] : 0.0;
}
