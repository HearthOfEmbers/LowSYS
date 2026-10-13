import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart';
import '../faults/fault_effects.dart';
import 'column_state.dart';
import 'packed_hydraulics.dart';

/// Per-segment and per-bed state of the packed sections (PHYSICS.md 6; M8). A pure function of (state, effective
/// parameters): the stepper, the snapshot and the explain API all read these arrays, as for the tray hydraulics.
class PackedModel {
  final List<BedLayout> beds;
  final int n, nc;

  /// Tier-1 relative volatilities (for alpha' of (6.4) in Tier 1), light and heavy key and the liquid viscosity (Pa s).
  final List<double> alpha1;
  final List<double> mw;
  final int lk, hk;
  final double mu;

  /// Stage -> bed (0-based) or -1.
  final Int32List bedOf;

  // per segment (index = stage)
  late final Float64List lp, gp, phi, gfl, dpPerM, dp, hL, hLs, holdupFac, wetFrac, wetting, hetp, lam, eo, emv, carry,
      metal, coef, hSeg, nthSeg, facState;

  /// Time constant (s) of the lag on the holdup factor (6.3): the explicit coupling holdup -> L_k -> phi_p -> factor is
  /// a 13th-power loop and oscillates (a 1-s limit cycle at phi_p > 0.9, M8 coder) unless the factor follows its
  /// value with a short lag. Steady states are unchanged. DEVIATIONS.md "M8 checkpoint".
  static const double tauFactor = 10.0;
  bool _facReady = false;

  // per bed (index = bed - 1)
  late final Float64List bedDp, bedMaxPhi, bedNth, bedS, bedEMal, bedF, bedCrush;

  /// True after an [update] in ideal-hydraulics mode (no phi, no dP, no modifiers).
  bool ideal = false;

  PackedModel({
    required this.beds,
    required this.n,
    required this.nc,
    required this.alpha1,
    required this.mw,
    required this.lk,
    required this.hk,
    required this.mu,
  }) : bedOf = Int32List(n)..fillRange(0, n, -1) {
    Float64List f() => Float64List(n);
    lp = f();
    gp = f();
    phi = f();
    gfl = f();
    dpPerM = f();
    dp = f();
    hL = f();
    hLs = f();
    holdupFac = f()..fillRange(0, n, 1.0);
    facState = f()..fillRange(0, n, 1.0);
    wetFrac = f()..fillRange(0, n, 1.0);
    wetting = f()..fillRange(0, n, 1.0);
    hetp = f();
    lam = f()..fillRange(0, n, 1.0);
    eo = f()..fillRange(0, n, 1.0);
    emv = f()..fillRange(0, n, 1.0);
    carry = f();
    metal = f();
    coef = f();
    hSeg = f();
    nthSeg = f();
    final nb = beds.length;
    bedDp = Float64List(nb);
    bedMaxPhi = Float64List(nb);
    bedNth = Float64List(nb);
    bedS = Float64List(nb)..fillRange(0, nb, 1.0);
    bedEMal = Float64List(nb)..fillRange(0, nb, 1.0);
    bedF = Float64List(nb);
    bedCrush = Float64List(nb);
    for (var b = 0; b < nb; b++) {
      for (var j = beds[b].first; j <= beds[b].last; j++) {
        bedOf[j] = b;
        hSeg[j] = beds[b].section.bedHeight / beds[b].segments;
        metal[j] = beds[b].section.packing.rhoBed * beds[b].section.area * hSeg[j] * 500.0;
      }
    }
  }

  bool isPacked(int j) => j >= 0 && j < n && bedOf[j] >= 0;

  /// Packing factor with the F23 increase.
  double fpEff(int b) => beds[b].section.packing.fp * (1 + 1.5 * bedCrush[b]);

  /// Segment height H_k including the F23 shortening (m).
  double segHeight(int b) => beds[b].section.bedHeight * (1 - 0.15 * bedCrush[b]) / beds[b].segments;

  /// Cold-start holdup of segment [j] at the flows in [s] (mol): (6.3) with phi = 0.
  double initialHoldup(ColumnState s, int j, Float64List rhoLs) {
    final b = bedOf[j];
    final sec = beds[b].section, pk = sec.packing;
    final vl = s.vLiq[j];
    final uL = s.liquid[j] * vl / sec.area;
    final h = PackedHydraulics.holdupS(mu, pk.a, math.max(uL, 1e-12), rhoLs[j]);
    return h * sec.area * segHeight(b) / vl;
  }

  /// Forget the lag state (after a restore or rebuild); the next [update] starts it at the raw factor.
  void resetFilters() => _facReady = false;

  /// Moves the lagged holdup factor towards its raw value by [dt] (once per step, after [update]).
  void advanceFilters(double dt) {
    for (var j = 0; j < n; j++) {
      if (bedOf[j] >= 0) facState[j] += (holdupFac[j] - facState[j]) * dt / (tauFactor + dt);
    }
  }

  /// Refreshes every packed array from the state. [tier2] selects alpha' from the stored K (Tier 2/3) or the Tier-1
  /// alpha; [ideal] = ideal hydraulics (phi = 0, no dP, no wetting or loading modifier).
  void update(ColumnState s, EffectiveParams ep, Float64List rhoLs, Float64List rhoVs, Float64List sigmas,
      {required bool tier2, required bool ideal}) {
    this.ideal = ideal;
    final muCp = mu * 1000;
    for (var b = 0; b < beds.length; b++) {
      final bed = beds[b];
      final sec = bed.section, pk = sec.packing, aT = sec.area;
      bedCrush[b] = b < ep.bedCrush.length ? ep.bedCrush[b] : 0.0;
      bedF[b] = b < ep.bedMal.length ? ep.bedMal[b] : 0.0;
      final fp = fpEff(b), h = segHeight(b);
      var lnS = 0.0, nth = 0.0, dpBed = 0.0, maxPhi = 0.0;
      for (var j = bed.first; j <= bed.last; j++) {
        hSeg[j] = h;
        metal[j] = pk.rhoBed * aT * h * 500.0;
        final rhoL = rhoLs[j], rhoV = rhoVs[j], sigma = sigmas[j];
        var mwl = 0.0, mwv = 0.0;
        for (var i = 0; i < nc; i++) {
          mwl += s.x[j * nc + i] * mw[i];
          mwv += s.y[(j + 1) * nc + i] * mw[i];
        }
        final lflow = s.liquid[j], vflow = s.vapor[j + 1];
        final l1 = lp[j] = lflow * mwl / (1000 * aT);
        final g1 = gp[j] = vflow * mwv / (1000 * aT);
        final vl = s.vLiq[j];
        final uL = lflow * vl / aT;
        double ph = 0, dpm = 0, gf = 0;
        if (!ideal && l1 > 1e-9 && g1 > 1e-9) {
          dpm = PackedHydraulics.robbins(l1, g1, rhoL, rhoV, muCp, fp);
          gf = PackedHydraulics.floodFlux(l1 / g1, rhoL, rhoV, muCp, fp);
          ph = g1 / gf;
        }
        gfl[j] = gf;
        phi[j] = ph;
        dpPerM[j] = dpm;
        dp[j] = dpm * h;
        final fac = ideal ? 1.0 : PackedHydraulics.holdupFactor(ph);
        holdupFac[j] = fac;
        if (!_facReady) facState[j] = fac;
        final hls = PackedHydraulics.holdupS(mu, pk.a, math.max(uL, 0.0), rhoL);
        hLs[j] = hls;
        hL[j] = hls * fac;
        wetFrac[j] = l1 > 1e-9 ? PackedHydraulics.ondaWetFraction(l1, pk.a, rhoL, mu, sigma, pk.sigmaC) : 0.0;
        final wet = ideal
            ? 1.0
            : PackedHydraulics.wettingFactor(l1, sec.designLiquidFlux, pk.a, rhoL, mu, sigma, pk.sigmaC);
        wetting[j] = wet;
        hetp[j] = ideal ? pk.hetpRef : PackedHydraulics.hetp(pk.hetpRef, wet, ph);
        // outflow coefficient of (6.4): L = coef * M^3
        final k = vl / (aT * h * facState[j]);
        coef[j] = k * k * k * rhoL * PackedHydraulics.g * aT / (12 * mu * pk.a * pk.a * vl);
        // stripping factor lambda_k (6.4)
        double ap;
        if (tier2) {
          final kl = s.kt[j * nc + lk], kh = s.kt[j * nc + hk];
          ap = kh > 0 ? kl / kh : 1.0;
        } else {
          ap = alpha1[lk] / alpha1[hk];
        }
        final xl = s.x[j * nc + lk], xh = s.x[j * nc + hk];
        final xs = xl + xh;
        final xp = xs < 1e-9 ? 0.5 : xl / xs;
        final m = PackedHydraulics.slope(ap, xp);
        final lm = lflow > 1e-12 ? m * s.vapor[j] / lflow : 1.0;
        lam[j] = lm.isFinite ? lm.clamp(1e-3, 1e3) : 1.0;
        final nj = math.min(1.0, h / hetp[j]);
        nthSeg[j] = nj;
        nth += nj;
        lnS += math.log(lam[j]);
        dpBed += dp[j];
        maxPhi = math.max(maxPhi, ph);
        // carry-over above phi 1.05: the holdup above the h_L(phi = 1) value rises with tau_c = 5 s (6.3)
        final mRef = hls * (1 + 1.2) * aT * h / vl;
        carry[j] = (!ideal && ph > 1.05 && s.holdup[j] > mRef) ? (s.holdup[j] - mRef) / 5.0 : 0.0;
      }
      final nseg = bed.segments;
      if (b == beds.length - 1) _facReady = true;
      bedS[b] = math.exp(lnS / nseg);
      bedNth[b] = nth;
      bedDp[b] = dpBed;
      bedMaxPhi[b] = maxPhi;
      bedEMal[b] = Maldistribution.eMal(bedS[b], nth, bedF[b]);
      for (var j = bed.first; j <= bed.last; j++) {
        eo[j] = nthSeg[j] * bedEMal[b];
        final dry = math.min(1.0, hL[j] / 0.005);
        emv[j] = (PackedHydraulics.lewisEMV(eo[j], lam[j]) * dry).clamp(0.0, 1.0);
      }
    }
  }
}
