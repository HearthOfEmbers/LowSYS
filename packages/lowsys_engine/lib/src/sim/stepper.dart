// ignore_for_file: non_constant_identifier_names  // physics symbols (L0, VB, F, N) follow PHYSICS.md
import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart';
import '../config/tray_geometry.dart';
import '../control/control_system.dart';
import '../core/ids.dart';
import '../faults/fault_effects.dart';
import '../faults/fault_manager.dart';
import '../math/banded_solver.dart';
import '../model/column_state.dart';
import '../model/thermosyphon.dart';
import '../model/tray_hydraulics.dart';
import '../thermo/component.dart' show WaterProps;
import '../thermo/tier1_constant_alpha.dart';
import '../thermo/tier2_raoult.dart';

/// One fixed step of the Tier 1 column, PHYSICS.md 12.4 in order, no allocation.
///
/// Tier 1 skips steps 5 (reboiler duty), 10 (pressure) and 11 (thermo update beyond the
/// composition-dependent quantities). Ideal hydraulics: only the Bennett weir relation
/// (alpha_e and C); no pressure drop, entrainment, weeping or downcomer limit (PHYSICS.md 4.6).
/// Full hydraulics: PHYSICS.md 5 through [HydraulicSolver] (step 4), with entrainment, bypass and the
/// downcomer cap in the implicit holdup solve (12.2) and in the banded component solve (12.3).
class Stepper {
  final int nTrays;
  final int n;
  final int nc;
  final Tier1ConstantAlpha thermo;

  /// Tier-2 Raoult model (PHYSICS.md 3), used while [tier2] is true.
  Tier2Raoult t2;
  final CondenserConfig cond;
  final ReboilerConfig reb;
  final ColumnState s;
  final StepInputs inp;
  final ControlSystem control;
  final SolverHealth health;
  final StepDebug debug;
  final HydraulicSolver hyd;
  final EffectiveParams ep;
  final FaultManager faults;
  final MeasurementBus bus = MeasurementBus();
  final List<double> _dl = [0.0];

  /// Highest flood fraction (jet, downcomer, froth fill) and weeping fraction of the last step (live metrics).
  double liveMaxFlood = 0, liveMaxWeep = 0;

  /// True for full hydraulics (PHYSICS.md 5); false for ideal (M1) hydraulics.
  bool full;

  /// True while the column runs Tier 2 (energy balances and pressure dynamics, PHYSICS.md 4.5, 7, 8).
  bool tier2;

  // Geometry (PHYSICS.md 5.1)
  final double aActive;
  final double weirLength;
  final double weirHeight;
  final double bennettC;
  final double drumVolume;
  final double sumpVolume;
  final double aTotal;

  /// Design reflux flow (mol/s): the capacity of the reflux pump for fault F12 (PHYSICS.md 11).
  double refluxCapacity;

  /// Time constants of the entrainment fraction and filtered liquid load (PHYSICS.md 5.5, 5.6).
  static const double tauPsi = 5.0, tauLbar = 10.0;

  final int murphreePasses;

  // Scratch (preallocated; reused every step).
  final Float64List _kt;
  final Float64List _yhat;
  final Float64List _mnew;
  final Float64List _mhat;
  final Float64List _g, _a, _b, _c, _d, _sol, _cp, _dp;
  final Float64List _xn;
  final Float64List _yy;

  // Backup for the failure path (PHYSICS.md 12.7).
  final ColumnState _backup;

  Stepper({
    required this.thermo,
    required this.t2,
    required this.cond,
    required this.reb,
    required this.s,
    required this.inp,
    required this.control,
    required this.health,
    required this.debug,
    required this.hyd,
    required this.ep,
    required this.faults,
    required this.full,
    this.tier2 = false,
    required this.refluxCapacity,
    required TrayGeometry geometry,
    required this.drumVolume,
    required this.sumpVolume,
    this.murphreePasses = 2,
  })  : nTrays = s.nTrays,
        n = s.n,
        nc = s.nc,
        aActive = geometry.areaActive,
        aTotal = geometry.areaTotal,
        weirLength = geometry.weirLength,
        weirHeight = geometry.weirHeight,
        bennettC = geometry.bennettC,
        _kt = Float64List(s.n * s.nc),
        _yhat = Float64List(s.n * s.nc),
        _mnew = Float64List(s.n * s.nc),
        _mhat = Float64List(s.n),
        _g = Float64List(s.n),
        _a = Float64List(s.n),
        _b = Float64List(s.n),
        _c = Float64List(s.n),
        _d = Float64List(s.n),
        _sol = Float64List(s.n),
        _cp = Float64List(s.n),
        _dp = Float64List(s.n),
        _xn = Float64List(s.nc),
        _yy = Float64List(s.nc),
        _backup = ColumnState(s.nTrays, s.nc);

  double get rhoL => thermo.rhoL;
  double get rhoV => thermo.rhoV;

  // ---------------------------------------------------------------- derived state

  /// Liquid molar volume of stage [j] from its composition (m3/mol).
  double _vLiq(int j) {
    if (tier2) {
      var tj = j == 0 ? s.tRefl : s.t[j];
      if (!(tj > 200)) tj = 350;
      return t2.liquidMolarVolumeAt(tj, s.x, j * nc);
    }
    var mm = 0.0;
    for (var i = 0; i < nc; i++) {
      mm += s.x[j * nc + i] * thermo.mw[i];
    }
    return mm / (1000 * rhoL);
  }

  /// Recompute x, M, vLiq from the component holdups m.
  void refreshFromHoldups() {
    for (var j = 0; j < n; j++) {
      var tot = 0.0;
      for (var i = 0; i < nc; i++) {
        tot += s.m[j * nc + i];
      }
      s.holdup[j] = tot;
      if (tot > 0) {
        for (var i = 0; i < nc; i++) {
          s.x[j * nc + i] = s.m[j * nc + i] / tot;
        }
      }
      s.vLiq[j] = _vLiq(j);
    }
  }

  /// Vapour leaving every stage bottom-up with the Murphree relation (PHYSICS.md 4.2), from the
  /// liquid compositions in [x] (row-major, normalised on the fly), into [yOut]; y* into [ysOut].
  void _computeVapour(Float64List x, Float64List yOut, Float64List? ysOut) {
    final N = nTrays;
    for (var j = N + 1; j >= 0; j--) {
      final off = j * nc;
      var sx = 0.0;
      for (var i = 0; i < nc; i++) {
        sx += x[off + i];
      }
      if (sx > 0) {
        for (var i = 0; i < nc; i++) {
          _xn[i] = x[off + i] / sx;
        }
      } else {
        for (var i = 0; i < nc; i++) {
          _xn[i] = 1.0 / nc;
        }
      }
      if (tier2) {
        var ss = 0.0;
        for (var i = 0; i < nc; i++) {
          _yy[i] = s.kt[off + i] * _xn[i];
          ss += _yy[i];
        }
        if (ss > 0) {
          for (var i = 0; i < nc; i++) {
            _yy[i] /= ss;
          }
        }
      } else {
        thermo.equilibrium(_xn, 0, _yy, 0);
      }
      if (ysOut != null) {
        for (var i = 0; i < nc; i++) {
          ysOut[off + i] = _yy[i];
        }
      }
      if (j == 0) {
        // drum: the condensate has the composition of the vapour leaving tray 1; with a partial condenser the
        // drum vapour is in equilibrium with the drum liquid (PHYSICS.md 7.1)
        for (var i = 0; i < nc; i++) {
          yOut[i] = partial ? _yy[i] : yOut[nc + i];
        }
      } else if (j == N + 1) {
        for (var i = 0; i < nc; i++) {
          yOut[off + i] = _yy[i];
        }
      } else {
        final e = s.eff[j];
        final below = (j + 1) * nc;
        for (var i = 0; i < nc; i++) {
          yOut[off + i] = yOut[below + i] + e * (_yy[i] - yOut[below + i]);
        }
      }
    }
  }

  /// Open fraction of the deck of tray [j] (broken tray); zero in ideal hydraulics.
  double _sB(int j) => full ? ep.brokenS[j] : 0.0;

  /// Murphree efficiency of tray [j]: E (1 - b_V) min(1, h_cl / 5 mm), PHYSICS.md (4.2).
  double _effOf(int j) {
    final sB = _sB(j);
    final hcl = s.holdup[j] * s.vLiq[j] / (aActive * math.max(1 - sB, 0.02));
    final f = hcl >= 0.005 ? 1.0 : (hcl <= 0 ? 0.0 : hcl / 0.005);
    return inp.murphree * (1 - sB) * f;
  }

  /// Refresh efficiencies and the vapour/equilibrium arrays from the current liquid state.
  void refreshVapour() {
    if (tier2) {
      t2Thermo(s.pTop);
      return;
    }
    for (var j = 1; j <= nTrays; j++) {
      s.eff[j] = _effOf(j);
    }
    s.eff[nTrays + 1] = 1.0;
    s.eff[0] = 1.0;
    _computeVapour(s.x, s.y, s.yStar);
  }

  /// Fault effects and, in full hydraulics, the hydraulic arrays for the current state (used by the
  /// snapshot and the explain API; the step does the same before it advances).
  void refreshHydraulics(double dt) {
    faults.apply(s.time, ep, inp.z);
    hyd.pTop = s.pTop;
    if (full) hyd.update(s, ep, dt);
  }

  /// Initialises psi and the filtered liquid load from the current state (switching to full hydraulics).
  void initHydraulicState() {
    faults.apply(s.time, ep, inp.z);
    hyd.update(s, ep, 0.5);
    for (var j = 1; j <= nTrays; j++) {
      s.psi[j] = hyd.entrainmentFilterInit(j);
      s.lbar[j] = s.liquid[j];
    }
    hyd.update(s, ep, 0.5);
  }

  // ---------------------------------------------------------------- initialisation

  /// Cold initialisation (PHYSICS.md 13.1): feed composition everywhere, CMO flows,
  /// Bennett holdups, drum and sump at 50 %, controllers at the matching flows.
  void initializeCold() {
    final N = nTrays;
    final F = inp.feedFlowSp,
        L0 = inp.ratioMode ? 0.0 : inp.refluxFlowSp,
        VB = inp.boilupSp;
    final fs = inp.feedStage, q = inp.feedQ;
    s.time = 0;
    s.feedAct = F;
    s.boilupAct = VB;
    var l0 = L0;
    if (inp.ratioMode) {
      // R = L/D and V1 = L + D  ->  L = R V1 / (R + 1)
      final v1 = VB + (1 - q) * F;
      l0 = inp.refluxRatio * v1 / (inp.refluxRatio + 1);
    }
    s.refluxAct = l0;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < nc; i++) {
        s.x[j * nc + i] = inp.z[i];
      }
    }
    if (tier2) _t2ColdStart();
    for (var j = 0; j < n; j++) {
      s.vLiq[j] = _vLiq(j);
    }
    // CMO flows
    s.vapor[N + 1] = VB;
    for (var j = N; j >= 1; j--) {
      s.vapor[j] =
          math.max(0.0, s.vapor[j + 1] + (j == fs ? (1 - q) * F : 0.0));
    }
    s.liquid[0] = l0;
    for (var j = 1; j <= N; j++) {
      s.liquid[j] = l0 + (j >= fs ? q * F : 0.0);
    }
    s.liquid[N + 1] = 0;
    // holdups: placeholder to evaluate vapour compositions, then Bennett inverse
    for (var j = 0; j < n; j++) {
      s.holdup[j] = 1.0;
      s.eff[j] = j == 0 || j == N + 1 ? 1.0 : inp.murphree;
    }
    _computeVapour(s.x, s.y, s.yStar);
    for (var j = 1; j <= N; j++) {
      final ae = _alphaE(j);
      s.alphaE[j] = ae;
      final vl = s.vLiq[j];
      final qw = s.liquid[j] * vl;
      final r = qw / (weirLength * ae);
      final hcl = ae * (weirHeight + bennettC * math.pow(r, 2.0 / 3.0));
      s.holdup[j] = hcl * aActive / vl;
    }
    s.holdup[0] = 0.5 * drumVolume / s.vLiq[0];
    s.holdup[N + 1] = 0.5 * sumpVolume / s.vLiq[N + 1];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < nc; i++) {
        s.m[j * nc + i] = s.x[j * nc + i] * s.holdup[j];
      }
    }
    refreshFromHoldups();
    refreshVapour();
    if (tier2) t2Thermo(s.pTop);
    for (var j = 0; j < n; j++) {
      s.entrain[j] = 0;
      s.bypass[j] = 0;
      s.psi[j] = 0;
      s.lbar[j] = s.liquid[j];
    }
    if (full) initHydraulicState();
    if (tier2) {
      t2Thermo(s.pTop);
      t2InitInventory();
    }
    // sump / drum level measurements
    bus.drumLevelPct = 100 * s.holdup[0] * s.vLiq[0] / drumVolume;
    bus.sumpLevelPct = 100 * s.holdup[N + 1] * s.vLiq[N + 1] / sumpVolume;
  }

  /// alpha_e from the vapour loading entering tray [j] (PHYSICS.md 5.1, 5.2): the froth density
  /// exp(-12.55 K_s^0.91).
  double _alphaE(int j) {
    var mwv = 0.0;
    for (var i = 0; i < nc; i++) {
      mwv += s.y[(j + 1) * nc + i] * thermo.mw[i];
    }
    final rV = hyd.rhoVs[j], rL = hyd.rhoLs[j];
    final qin = s.vapor[j + 1] * mwv / (1000 * rV);
    final us = qin / aActive;
    final ks = us * math.sqrt(rV / (rL - rV));
    return ks <= 0 ? 1.0 : math.exp(-12.55 * math.pow(ks, 0.91));
  }

  // ---------------------------------------------------------------- the step

  /// Advances the state by [dt]. Returns false (state restored) when the step produced NaN, Inf or a
  /// negative holdup beyond tolerance.
  /// When true a significant negative clamp (an overshoot of the explicit inventory update beyond 1e-6 mol) fails the
  /// step so that the simulator halves it (PHYSICS.md 12.7); the simulator relaxes it on the last retry.
  bool strictClamp = false;
  bool _clampHit = false;

  bool step(double dt) {
    _backup.copyFrom(s);
    _clampHit = false;
    _advance(dt);
    if (!_healthy() || (strictClamp && _clampHit)) {
      s.copyFrom(_backup);
      return false;
    }
    _controllers(dt);
    s.time += dt;
    return true;
  }

  bool _healthy() {
    for (var j = 0; j < n; j++) {
      final h = s.holdup[j];
      if (h.isNaN || h.isInfinite || h < -1e-9) return false;
    }
    for (var k = 0; k < s.m.length; k++) {
      final v = s.m[k];
      if (v.isNaN || v.isInfinite) return false;
    }
    return true;
  }

  void _advance(double dt) {
    final N = nTrays;
    final fs = inp.feedStage;
    final q = inp.feedQ;
    // --- 1. faults: effective parameters (PHYSICS.md 11), then the control faults
    faults.apply(s.time, ep, inp.z);
    final z = ep.zEff;
    control.time = s.time;
    control.applyFaults(faults.controlSpecs);

    // --- 2. control fast layer (PHYSICS.md 10.1): mean valve flows over the step
    if (tier2) _t2Utilities();
    control.ratioMode = inp.ratioMode;
    control.ratio = inp.refluxRatio;
    control.runFastLayer(dt, s.time);
    final mf = control.meanFlows;
    final F = mf[0];
    final VB = mf[2];
    var D = mf[3];
    var B = mf[4];
    var L0 = mf[1];
    s.feedAct = F;
    s.refluxAct = L0;
    s.boilupAct = tier2 ? 0.0 : VB;

    // --- 6. vapour profile, Tier 1 CMO (PHYSICS.md 4.4) with sump starvation (8.1)
    final mMin = 0.05 * sumpVolume / s.vLiq[N + 1];
    final sSump = mMin > 0 ? (s.holdup[N + 1] / mMin).clamp(0.0, 1.0) : 1.0;
    if (!tier2) {
      s.vapor[N + 1] = VB * sSump;
      for (var j = N; j >= 1; j--) {
        s.vapor[j] =
            math.max(0.0, s.vapor[j + 1] + (j == fs ? (1 - q) * F : 0.0));
      }

      // --- 3./4. normalised K (4.4), efficiencies, froth density
      for (var j = 0; j < n; j++) {
        var den = 0.0;
        for (var i = 0; i < nc; i++) {
          den += thermo.alpha[i] * s.x[j * nc + i];
        }
        if (den <= 0) den = 1.0;
        for (var i = 0; i < nc; i++) {
          _kt[j * nc + i] = thermo.alpha[i] / den;
        }
      }
    } else {
      _kt.setAll(0, s.kt);
      hyd.pTop = s.pTop;
    }
    if (full) {
      // PHYSICS.md 5: hydraulic coefficients at state n, then the filter states (12.4 step 4)
      hyd.update(s, ep, dt);
      for (var j = 1; j <= N; j++) {
        s.psi[j] += (hyd.psiEq[j] - s.psi[j]) * dt / (tauPsi + dt);
        s.lbar[j] += (s.liquid[j] - s.lbar[j]) * dt / (tauLbar + dt);
      }
      hyd.finishEntrainment(s, dt);
      for (var j = 1; j <= N; j++) {
        s.alphaE[j] = hyd.alphaE[j];
        s.entrain[j] = hyd.entrain[j];
        s.bypass[j] = hyd.bypass[j];
        s.eff[j] = inp.murphree *
            (1 - ep.brokenS[j]) *
            math.min(1.0, hyd.hcl[j] / 0.005);
      }
    } else {
      for (var j = 1; j <= N; j++) {
        s.eff[j] = _effOf(j);
        s.alphaE[j] = _alphaE(j);
      }
    }
    s.eff[N + 1] = 1.0;
    s.eff[0] = 1.0;

    // --- 5./6. Tier 2: feed enthalpy, energy-balance vapour profile and the implicit pressure solve (4.5, 7.4)
    var hF = 0.0;
    if (tier2) {
      hF = _t2FeedEnthalpy(z);
      _t2PressureSolve(dt, VB, L0, F, hF, fs, sSump);
    }

    // reflux and distillate pumps cannot take more than the drum holds (7.3)
    final v1 = tier2 ? s.nCond : s.vapor[1];
    final e1 = full ? s.entrain[1] : 0.0;
    final availD = s.holdup[0] / dt + v1 + e1;
    final pumpCap = tier2 && ep.refluxCapScale < 1
        ? refluxCapacity * ep.refluxCapScale
        : double.infinity;
    final totD = L0 + D;
    if (totD > availD || L0 > pumpCap) {
      final f = totD > 0 ? math.min(1.0, availD / totD) : 0.0;
      L0 = math.min(L0 * f, pumpCap);
      D *= f;
      control.fv102.cap = L0;
      control.lv101.cap = D;
    } else {
      control.fv102.cap = pumpCap;
      control.lv101.cap = double.infinity;
    }
    s.liquid[0] = L0;

    // --- 8. hydraulic step, top-down (PHYSICS.md 12.2)
    var lPrev = L0;
    var lPrev2 = 0.0;
    for (var j = 1; j <= N; j++) {
      final fj = full ? s.bypass[j] : 0.0;
      final fPrev = j >= 2 && full ? s.bypass[j - 1] : 0.0;
      final eNext = full && j + 1 <= N ? s.entrain[j + 1] : 0.0;
      final eJ = full ? s.entrain[j] : 0.0;
      final inflow = (1 - fj) * lPrev +
          fPrev * lPrev2 +
          eNext +
          (j == fs ? F : 0.0) +
          s.vapor[j + 1] -
          s.vapor[j] -
          eJ;
      final vl = s.vLiq[j];
      final ae = s.alphaE[j];
      final aa = full ? hyd.aAct[j] : aActive;
      final cap = full ? hyd.lMax[j] : double.infinity;
      final kd = full ? hyd.kd[j] : 0.0;
      final mn = s.holdup[j];
      var mm = mn;
      double lj;
      if (full) {
        // full hydraulics (PHYSICS.md 5.15, 12.2): every tray is solved for u = sqrt(M) with a bracketed Newton
        final sqMc = hyd.mcSqrt[j];
        double lwOf(double m2, List<double> dlOut) {
          final hcl = m2 * vl / aa;
          final arg = (hcl / ae - weirHeight) / bennettC;
          var lw = 0.0, dl = 0.0;
          if (arg > 0) {
            final sq = math.sqrt(arg);
            lw = weirLength * ae * arg * sq / vl;
            dl = 1.5 * weirLength * sq / (bennettC * aa);
          }
          if (lw > cap) {
            lw = cap;
            dl = 0;
          }
          dlOut[0] = dl;
          return lw;
        }

        double gOf(double u) {
          final lw = lwOf(u * u, _dl);
          final dump = u > sqMc ? kd * (u - sqMc) : 0.0;
          return u * u - mn - dt * (inflow - lw - dump);
        }

        double u;
        if (gOf(0.0) >= 0) {
          u = 0.0;
        } else {
          var lo = 0.0, hi = math.sqrt(math.max(mn, 0.0)) + 1;
          while (gOf(hi) <= 0) {
            hi = 2 * hi + 1;
          }
          u = math.sqrt(math.max(mn, 0.0));
          if (u <= lo || u >= hi) u = 0.5 * (lo + hi);
          for (var it = 0; it < 100; it++) {
            final g = gOf(u);
            if (g > 0) {
              hi = u;
            } else {
              lo = u;
            }
            final dl = _dl[0]; // slope of the weir flow at u (set by gOf)
            final gp = 2 * u + dt * (2 * u * dl + (u > sqMc ? kd : 0.0));
            var un = u - g / gp;
            if (!(un > lo && un < hi)) un = 0.5 * (lo + hi);
            final done = (un - u).abs() < 1e-12 * math.max(1.0, u) ||
                (hi - lo) < 1e-13 * math.max(1.0, u);
            u = un;
            if (done) break;
          }
        }
        mm = u * u;
        final lw = lwOf(mm, _dl);
        lj = lw + (u > sqMc ? kd * (u - sqMc) : 0.0);
      } else {
        for (var it = 0; it < 40; it++) {
          final hcl = mm * vl / aa;
          final arg = (hcl / ae - weirHeight) / bennettC;
          var lw = 0.0, dl = 0.0;
          if (arg > 0) {
            final sq = math.sqrt(arg);
            lw = weirLength * ae * arg * sq / vl; // PHYSICS.md (5.2)
            dl = 1.5 * weirLength * sq / (bennettC * aa);
          }
          if (lw > cap) {
            lw = cap; // downcomer backup limit (5.11)
            dl = 0;
          }
          final r = mm - mn - dt * (inflow - lw);
          var mNew = mm - r / (1 + dt * dl);
          if (mNew <= 0) mNew = mm / 2;
          final dm = mNew - mm;
          mm = mNew;
          if (dm.abs() < 1e-10 * math.max(1.0, mm)) break;
        }
        final hcl = mm * vl / aa;
        final arg = (hcl / ae - weirHeight) / bennettC;
        lj = arg > 0 ? weirLength * ae * arg * math.sqrt(arg) / vl : 0.0;
        if (lj > cap) lj = cap;
      }
      _mhat[j] = mm;
      s.liquid[j] = lj;
      lPrev2 = lPrev;
      lPrev = lj;
    }
    // bottoms pump limit (8.1)
    final fN = full ? s.bypass[N] : 0.0;
    final lIntoSump = s.liquid[N] + fN * (N >= 2 ? s.liquid[N - 1] : L0);
    final availB = s.holdup[N + 1] / dt + lIntoSump - s.vapor[N + 1];
    if (B > availB) {
      B = math.max(0.0, availB);
      control.lv102.cap = B;
    } else {
      control.lv102.cap = double.infinity;
    }
    _mhat[0] = s.holdup[0] + dt * (v1 + e1 - L0 - D);
    _mhat[N + 1] = s.holdup[N + 1] + dt * (lIntoSump - s.vapor[N + 1] - B);
    for (var j = 0; j < n; j++) {
      if (!(_mhat[j] > 1e-9)) _mhat[j] = 1e-9;
    }

    // --- 9. component step (PHYSICS.md 12.3), Murphree passes
    _yhat.setAll(0, s.y);
    for (var pass = 0; pass < murphreePasses; pass++) {
      _componentPass(dt, F, fs, D, B, L0, z);
      if (pass + 1 < murphreePasses) {
        // new vapour from the pass solution for the next pass
        _computeVapour(_mnew, _yhat, null);
      }
    }

    // --- accounting for conservation tests (VC-5)
    debug
      ..dt = dt
      ..feedFlow = F
      ..refluxFlow = L0
      ..distillateFlow = D
      ..bottomsFlow = B
      ..boilupFlow = s.vapor[N + 1];
    for (var i = 0; i < nc; i++) {
      debug.feedRate[i] = F * z[i];
      debug.distillateRate[i] = D * _mnew[i] / _mhat[0];
      debug.bottomsRate[i] = B * _mnew[(N + 1) * nc + i] / _mhat[N + 1];
      debug.ventRate[i] = 0;
    }
    if (tier2) _t2InventoryUpdate(dt, F);

    // --- 11. new state
    for (var k = 0; k < _mnew.length; k++) {
      var v = _mnew[k];
      if (v < 0) {
        if (v < -1e-12) health.negativeClamps++;
        if (v < -1e-6) _clampHit = true;
        v = 0;
      }
      s.m[k] = v;
    }
    refreshFromHoldups();
    if (tier2) {
      t2Thermo(_pNew);
      _t2Diagnostics(F, D, B, hF);
      return;
    }
    for (var j = 1; j <= N; j++) {
      s.eff[j] = _effNow(j);
    }
    _computeVapour(s.x, s.y, s.yStar);
  }

  /// Murphree efficiency of tray [j] from the state (full hydraulics: with the broken-deck factor).
  double _effNow(int j) => full
      ? inp.murphree *
          (1 - ep.brokenS[j]) *
          math.min(
              1.0,
              s.holdup[j] *
                  s.vLiq[j] /
                  (aActive * math.max(1 - ep.brokenS[j], 0.02)) /
                  0.005)
      : _effOf(j);

  void _componentPass(double dt, double F, int fs, double D, double B,
      double L0, Float64List z) {
    final N = nTrays;
    final v1 = tier2 ? s.nCond : s.vapor[1];
    final part = partial;
    final vTop = s.vapor[1];
    for (var i = 0; i < nc; i++) {
      // drum row (total condenser, PHYSICS.md 12.3)
      _g[0] = 0;
      _a[0] = 0;
      if (part) {
        // partial condenser (PHYSICS.md 7.4): the drum is an equilibrium stage, the uncondensed vapour leaves at K~ x_0
        _b[0] = 1 + dt * (L0 + D + (vTop - v1) * _kt[i]) / _mhat[0];
        _c[0] =
            -dt * (vTop * s.eff[1] * _kt[nc + i] + s.entrain[1]) / _mhat[1];
        _d[0] = s.m[i] + dt * vTop * (1 - s.eff[1]) * _yhat[2 * nc + i];
      } else {
        _b[0] = 1 + dt * (L0 + D) / _mhat[0];
        _c[0] = -dt * (v1 * s.eff[1] * _kt[nc + i] + s.entrain[1]) / _mhat[1];
        _d[0] = s.m[i] + dt * v1 * (1 - s.eff[1]) * _yhat[2 * nc + i];
      }
      for (var j = 1; j <= N; j++) {
        _g[j] = j >= 2
            ? -dt * s.bypass[j - 1] * s.liquid[j - 2] / _mhat[j - 2]
            : 0.0;
        _a[j] = -dt * (1 - s.bypass[j]) * s.liquid[j - 1] / _mhat[j - 1];
        _b[j] = 1 +
            dt *
                (s.liquid[j] +
                    s.entrain[j] +
                    s.vapor[j] * s.eff[j] * _kt[j * nc + i]) /
                _mhat[j];
        final eNext = j + 1 <= N ? s.entrain[j + 1] : 0.0;
        _c[j] = -dt *
            (s.vapor[j + 1] * s.eff[j + 1] * _kt[(j + 1) * nc + i] + eNext) /
            _mhat[j + 1];
        var rhs = s.m[j * nc + i];
        var src = j == fs ? F * z[i] : 0.0;
        if (j + 2 <= N + 1) {
          src += s.vapor[j + 1] * (1 - s.eff[j + 1]) * _yhat[(j + 2) * nc + i];
        }
        src -= s.vapor[j] * (1 - s.eff[j]) * _yhat[(j + 1) * nc + i];
        rhs += dt * src;
        _d[j] = rhs;
      }
      // sump row
      _g[N + 1] = -dt * s.bypass[N] * s.liquid[N - 1] / _mhat[N - 1];
      _a[N + 1] = -dt * s.liquid[N] / _mhat[N];
      _b[N + 1] =
          1 + dt * (B + s.vapor[N + 1] * _kt[(N + 1) * nc + i]) / _mhat[N + 1];
      _c[N + 1] = 0;
      _d[N + 1] = s.m[(N + 1) * nc + i];
      BandedSolver.solve(n, _g, _a, _b, _c, _d, _sol, _cp, _dp);
      for (var j = 0; j < n; j++) {
        _mnew[j * nc + i] = _sol[j];
      }
    }
  }

  // ---------------------------------------------------------------- Tier 2 (M4)

  /// True with a partial condenser in Tiers 2/3 (PHYSICS.md 7.2 to 7.5); Tier 1 always has a total one.
  bool get partial => tier2 && cond.type == CondenserType.partial;

  /// Live outputs of the last Tier-2 step (snapshot, instruments, alarms).
  double qMax = 0,
      qMax0 = 0,
      steamT = 0,
      uaRebEff = 0,
      qDelivered = 0,
      uaCondEff = 0,
      cwFlow = 0,
      cwOutT = 0,
      cwInT = 0,
      fBlanket = 0,
      yIner = 0,
      subcool = 0,
      energyResidual = 0,
      feedTemp = 0,
      feedH = 0,
      steamHeaderAbs = 0;
  bool dutyRequestExceeds = false;
  double _pNew = 101325;
  double _tGuess = 350,
      _qcT = 0,
      _ncondT = 0,
      _nventT = 0,
      _nreliefT = 0,
      _dvT = 0;
  late final Float64List _cj = Float64List(s.n);
  late final Float64List _yb = Float64List(nc), _kb = Float64List(nc);
  double _sSumpNow = 1.0;

  double feedEnthalpyFor(Float64List z) => _t2FeedEnthalpy(z);

  /// Back to the constant Tier-1 properties for the hydraulics.
  void restoreTier1Props() {
    for (var j = 0; j < n; j++) {
      hyd.rhoLs[j] = thermo.rhoL;
      hyd.rhoVs[j] = thermo.rhoV;
      hyd.sigmas[j] = thermo.sigma;
    }
  }

  /// True once the relief valve has lifted (safety metric).
  bool reliefLifted = false;

  /// Prepares Tier-2 start values: utilities and the initial cooling-water flow.
  void prepareTier2() {
    _t2Utilities();
    cwFlow = control.cwValve.fMax * control.cwValve.g(control.cwValve.position);
    cwInT = inp.cwInT;
    cwOutT = cwInT + 14.7;
  }

  /// Copies the Tier-2 true values to the measurement bus.
  void fillBusT2() {
    if (!tier2) return;
    bus.pTop = s.pTop;
    bus.steamGauge = math.max(0.0, inp.steamHeaderP * ep.headerScale - 101325.0);
    bus.tRefl = s.tRefl;
    bus.cwIn = cwInT > 0 ? cwInT : inp.cwInT;
    bus.cwOut = cwOutT > 0 ? cwOutT : bus.cwIn + 14.7;
    bus.cwVol = cwFlow / ControlSystem.rhoWater;
    bus.stageT = s.t;
  }

  /// Start-of-step utilities (PHYSICS.md 8.2, 10.3): steam temperature, Q_max, the valve scale and caps.
  void _t2Utilities() {
    steamHeaderAbs = inp.steamHeaderP * ep.headerScale;
    steamT = WaterProps.saturationT(math.max(steamHeaderAbs, 20000.0));
    final tB = s.t[nTrays + 1];
    final ts = control.ts;
    if (ts != null) {
      // thermosyphon (PHYSICS.md 8.3.4): Q_max,0 = U A (T_st - T_b,mean) at the start-of-step state; the loop applies the
      // heat-transfer and mist-flow limits itself, so the valve is not capped
      _tsProps(ts);
      final z = ts.liquidHeight(sumpLevelPct, reb.sumpHeight);
      final ua = ts.geo.uaClean;
      final rfK = ep.rebFoulS * 1.5 / ua;
      control
        ..tsLevelPct = sumpLevelPct
        ..tsSumpHeight = reb.sumpHeight
        ..tsRfK = rfK
        ..tsFFlooded = ep.fFlooded
        ..tsKInAdd = ep.kInAdd
        ..tsKOutAdd = ep.kOutAdd;
      uaRebEff = ua / (1 + ua * rfK) * (1 - ep.fFlooded);
      qMax0 = ts.qMax0For(z);
      qMax = ts.iS > 0 || ts.qMax > 0 ? ts.qMax : qMax0;
      control.fv103.fMax = math.max(qMax0, 1.0);
      control.fv103.cap = double.infinity;
    } else {
      final rf = ep.rebFoulS * 1.5 / reb.uaClean;
      uaRebEff = reb.uaClean / (1 + reb.uaClean * rf) * (1 - ep.fFlooded);
      qMax0 = math.max(0.0, reb.uaClean * (steamT - tB));
      qMax = math.max(0.0, uaRebEff * (steamT - tB));
      control.fv103.fMax = math.max(qMax0, 1.0);
      control.fv103.cap = qMax;
    }
    control.cwValve.fMax = inp.cwMaxFlow;
    control.cwScale = ep.cwFlowScale;
    control.fv102.cap =
        ep.refluxCapScale < 1 ? refluxCapacity * ep.refluxCapScale : double.infinity;
  }

  /// The sump-liquid properties and steam temperature the thermosyphon loop sees (PHYSICS.md 8.3.1), from the
  /// start-of-step state. Clausius-Clapeyron uses the molar latent heat: dT_sat/dP = R T^2 / (lambda_molar P).
  void _tsProps(ThermosyphonLoop ts) {
    final j = nTrays + 1;
    final t = s.t[j];
    if (!(t > 200)) return;
    var mbar = 0.0;
    for (var i = 0; i < nc; i++) {
      mbar += s.x[j * nc + i] * t2.mw[i];
      _yy[i] = s.y[j * nc + i];
    }
    mbar /= 1000; // kg/mol
    final p = s.pStage[j] > 0 ? s.pStage[j] : s.pTop;
    final lamMol = s.hVap[j] - s.hLiq[j];
    final pr = ts.p;
    pr.rhoL = mbar / s.vLiq[j];
    pr.rhoV = t2.vaporDensity(t, p, _yy);
    pr.lambdaMass = lamMol / mbar;
    pr.cpL = t2.cpLAt(t, s.x, j * nc) / mbar;
    pr.muL = ts.geo.muL;
    pr.dTsatdP = gasR * t * t / (lamMol * p);
    pr.tSump = t;
    pr.tSteam = steamT;
  }

  /// PHYSICS.md 13.1 step 7: runs the loop alone for 600 s with the column frozen and Q_R,SP = [duty].
  void initThermosyphon(double duty) {
    final ts = control.ts;
    if (ts == null) return;
    _t2Utilities();
    ts.init(duty);
    final n = (600 / ControlSystem.deltaC).round();
    for (var k = 0; k < n; k++) {
      ts.substep(ControlSystem.deltaC, duty, sumpLevelPct, reb.sumpHeight, control.tsInletOp,
          rfK: control.tsRfK, fFlooded: control.tsFFlooded, kInAdd: control.tsKInAdd, kOutAdd: control.tsKOutAdd);
    }
    control.modelTsIs = ts.iS;
    control.qSt = ts.q;
  }

  double _t2FeedEnthalpy(Float64List z) {
    final fs = inp.feedStage;
    feedTemp = inp.feedT + ep.feedDt;
    final pF = s.pStage[fs] > 0 ? s.pStage[fs] : s.pTop;
    if (inp.feedSat) {
      final tb = t2.bubbleAt(pF, z, 0, inp.feedT > 200 ? inp.feedT : s.t[fs],
          _yb, 0, _kb, 0, health);
      inp.feedT = tb;
      feedTemp = tb + ep.feedDt;
    }
    feedH = t2.feedEnthalpy(feedTemp, pF, z);
    return feedH;
  }

  /// Cold-start thermo state: every stage at the bubble point of the feed at the design pressure.
  void _t2ColdStart() {
    final pt = inp.pTopInit;
    s.pTop = pt;
    s.nI = 0;
    final t =
        t2.bubbleAt(pt, s.x, 0, t2.coldGuess(s.x, 0), _yb, 0, _kb, 0, health);
    final sSum = t2.lastS, den = t2.lastDen;
    for (var j = 0; j < n; j++) {
      s.t[j] = t;
      s.pStage[j] = pt;
      s.tau[j] = j == 0 ? 0.0 : sSum / (pt * den);
      for (var i = 0; i < nc; i++) {
        s.kt[j * nc + i] = _kb[i] / sSum;
      }
    }
    s.tSat0 = t;
    s.tRefl = t - inp.refluxSub;
    s.t[0] = t;
    _tGuess = t;
    for (var j = 0; j < n; j++) {
      s.vLiq[j] = _vLiq(j);
      var mwl = 0.0;
      for (var i = 0; i < nc; i++) {
        mwl += s.x[j * nc + i] * t2.mw[i];
      }
      hyd.rhoLs[j] = mwl / 1000 / s.vLiq[j];
      hyd.sigmas[j] = thermo.sigma;
      for (var i = 0; i < nc; i++) {
        _yy[i] = _yb[i];
      }
      hyd.rhoVs[j] = t2.vaporDensity(t, pt, _yy);
    }
  }

  /// Initialises the vapour inventory from the pressure: n_V = P V / (R T_0,sat), n_V,i = n_V y_1 (PHYSICS.md 13.5).
  void t2InitInventory() {
    final nv = s.pTop * cond.overheadVolume / (gasR * s.tSat0);
    for (var i = 0; i < nc; i++) {
      s.nVi[i] = nv * s.y[nc + i];
    }
    s.nI = 0;
  }

  /// After a K-model change (T2 <-> T3) the drum temperature moves at once; rescales the condensable inventory
  /// (composition kept) so that P_top stays where it was: n_V = P (1 - y_I) V / (R T_0,sat).
  void t2RescaleInventory() {
    final nv0 = overheadMoles;
    if (!(nv0 > 0)) return;
    final nTot = nv0 + s.nI;
    final yI = s.nI / nTot;
    final nv = s.pTop * (1 - yI) * cond.overheadVolume / (gasR * s.tSat0);
    final k = nv / nv0;
    for (var i = 0; i < nc; i++) {
      s.nVi[i] *= k;
    }
  }

  /// Condensable vapour inventory (mol).
  double get overheadMoles {
    var v = 0.0;
    for (var i = 0; i < nc; i++) {
      v += s.nVi[i];
    }
    return v;
  }

  /// Thermo update at the end of a step (PHYSICS.md 12.4 step 11) and at tier switches: bubble point of every
  /// stage, K~ (4.3), tau (4.5), vapour compositions, enthalpies and the hydraulic properties (3.5).
  void t2Thermo(double pNew) {
    final N = nTrays;
    s.pTop = pNew;
    final nv = overheadMoles;
    yIner = nv + s.nI > 0 ? s.nI / (nv + s.nI) : 0.0;
    fBlanket = math.min(0.95, 3 * yIner);
    subcool = inp.refluxSub + 20 * fBlanket;
    final pc = pNew * (1 - yIner);
    // drum
    final tg = (s.tSat0 > 200) ? s.tSat0 : t2.coldGuess(s.x, 0);
    s.tSat0 = t2.bubbleAt(pc, s.x, 0, tg, _yb, 0, _kb, 0, health);
    var sSum = t2.lastS;
    for (var i = 0; i < nc; i++) {
      s.kt[i] = _kb[i] / sSum;
      s.yStar[i] = _yb[i];
    }
    s.tRefl = s.tSat0 - subcool;
    s.t[0] = s.tSat0;
    s.pStage[0] = pc;
    s.tau[0] = 0;
    final p1 = full ? hyd.pressure[1] : pNew;
    for (var j = 1; j <= N + 1; j++) {
      final pj = pNew + (full ? hyd.pressure[j] - p1 : 0.0);
      s.pStage[j] = pj;
      final tj = t2.bubbleAt(pj, s.x, j * nc, s.t[j] > 200 ? s.t[j] : s.tSat0,
          s.yStar, j * nc, _kb, 0, health);
      s.t[j] = tj;
      sSum = t2.lastS;
      s.tau[j] = sSum / (pj * t2.lastDen);
      for (var i = 0; i < nc; i++) {
        s.kt[j * nc + i] = _kb[i] / sSum;
      }
    }
    for (var j = 0; j < n; j++) {
      s.vLiq[j] = _vLiq(j);
    }
    for (var j = 1; j <= N; j++) {
      s.eff[j] = _effNow(j);
    }
    s.eff[N + 1] = 1.0;
    s.eff[0] = 1.0;
    _computeVapour(s.x, s.y, s.yStar);
    s.hLiq[0] = t2.hLAt(s.tRefl, s.x, 0);
    s.hVap[0] = t2.hVAt(s.tSat0, s.y, 0);
    for (var j = 1; j <= N + 1; j++) {
      s.hLiq[j] = t2.hLAt(s.t[j], s.x, j * nc);
      s.hVap[j] = t2.hVAt(s.t[j], s.y, j * nc);
    }
    // physical properties for the hydraulics (3.5)
    for (var j = 0; j < n; j++) {
      var mwl = 0.0;
      for (var i = 0; i < nc; i++) {
        mwl += s.x[j * nc + i] * t2.mw[i];
        _xn[i] = s.x[j * nc + i];
      }
      hyd.rhoLs[j] = mwl / 1000 / s.vLiq[j];
      hyd.sigmas[j] = t2.surfaceTension(j == 0 ? s.tRefl : s.t[j], _xn);
    }
    for (var j = 1; j <= N + 1; j++) {
      for (var i = 0; i < nc; i++) {
        _yy[i] = s.y[j * nc + i];
      }
      hyd.rhoVs[j] = t2.vaporDensity(s.t[j], s.pStage[j], _yy);
    }
    hyd.rhoVs[0] = hyd.rhoVs[1];
  }

  /// After a restore: rebuilds the quantities derived from the saved thermo arrays (efficiencies, hydraulic
  /// properties, inert fraction) without touching T, K~, y, h, H, tau or the stage pressures.
  void t2RestoreDerived() {
    final N = nTrays;
    hyd.pTop = s.pTop;
    final nv = overheadMoles;
    yIner = nv + s.nI > 0 ? s.nI / (nv + s.nI) : 0.0;
    fBlanket = math.min(0.95, 3 * yIner);
    subcool = inp.refluxSub + 20 * fBlanket;
    for (var j = 1; j <= N; j++) {
      s.eff[j] = _effNow(j);
    }
    s.eff[N + 1] = 1.0;
    s.eff[0] = 1.0;
    for (var j = 0; j < n; j++) {
      var mwl = 0.0;
      for (var i = 0; i < nc; i++) {
        mwl += s.x[j * nc + i] * t2.mw[i];
        _xn[i] = s.x[j * nc + i];
      }
      hyd.rhoLs[j] = mwl / 1000 / s.vLiq[j];
      hyd.sigmas[j] = t2.surfaceTension(j == 0 ? s.tRefl : s.t[j], _xn);
    }
    for (var j = 1; j <= N + 1; j++) {
      for (var i = 0; i < nc; i++) {
        _yy[i] = s.y[j * nc + i];
      }
      hyd.rhoVs[j] = t2.vaporDensity(s.t[j], s.pStage[j], _yy);
    }
    hyd.rhoVs[0] = hyd.rhoVs[1];
  }

  /// Heat capacity C_j (liquid plus tray metal) of every stage for the storage term (4.5).
  void _t2Capacity() {
    final metal = 75.0 * aTotal * 500.0;
    for (var j = 1; j <= nTrays + 1; j++) {
      _cj[j] = s.holdup[j] * t2.cpLAt(s.t[j], s.x, j * nc) +
          (j <= nTrays ? metal : 0.0);
    }
  }

  /// Quasi-steady energy balance vapour sweep, bottom up (PHYSICS.md 4.5): fills s.vapor for a top pressure [pNew].
  void _t2Sweep(double pNew, double dt, double qR, double l0, double f,
      double hF, int fs) {
    final N = nTrays;
    final dP = pNew - s.pTop;
    final hRefl = s.hLiq[0];
    // sump (4.7)
    {
      final hB = s.hLiq[N + 1];
      final lN = s.liquid[N];
      final fN = full ? s.bypass[N] : 0.0;
      final lN1 = N >= 2 ? s.liquid[N - 1] : l0;
      final hN = s.hLiq[N];
      final hN1 = N >= 2 ? s.hLiq[N - 1] : hRefl;
      final num = lN * (hN - hB) +
          (fN > 0 ? fN * lN1 * (hN1 - hB) : 0.0) +
          qR -
          _cj[N + 1] * s.tau[N + 1] * dP / dt;
      s.vapor[N + 1] = _sSumpNow * math.max(0.0, num / (s.hVap[N + 1] - hB));
    }
    for (var j = N; j >= 1; j--) {
      final hj = s.hLiq[j];
      final lUp = j == 1 ? l0 : s.liquid[j - 1];
      final hUp = j == 1 ? hRefl : s.hLiq[j - 1];
      final fj = full ? s.bypass[j] : 0.0;
      var num = (1 - fj) * lUp * (hUp - hj) +
          s.vapor[j + 1] * (s.hVap[j + 1] - hj);
      if (full && j >= 2) {
        final fp = s.bypass[j - 1];
        if (fp > 0) {
          final lUp2 = j == 2 ? l0 : s.liquid[j - 2];
          final hUp2 = j == 2 ? hRefl : s.hLiq[j - 2];
          num += fp * lUp2 * (hUp2 - hj);
        }
      }
      if (j == fs) num += f * (hF - hj);
      if (full && j + 1 <= N) num += s.entrain[j + 1] * (s.hLiq[j + 1] - hj);
      num -= _cj[j] * s.tau[j] * dP / dt;
      s.vapor[j] = math.max(0.0, num / (s.hVap[j] - hj));
    }
  }

  static const double _cpWater = 4180.0;

  /// The implicit overhead pressure solve (PHYSICS.md 7.4): secant on the vapour-inventory residual, with the
  /// energy-balance sweep re-run for every trial pressure. Leaves the final sweep in s.vapor.
  void _t2PressureSolve(double dt, double qR, double l0, double f, double hF,
      int fs, double sSump) {
    _sSumpNow = sSump;
    _t2Capacity();
    final nV0 = overheadMoles;
    final nI0 = s.nI;
    final yI = nV0 + nI0 > 0 ? nI0 / (nV0 + nI0) : 0.0;
    final fb = math.min(0.95, 3 * yI);
    final rfC = ep.condFoulS * 1.5 / cond.uaClean;
    final lvl = drumLevelPct;
    final flood = lvl > 100 ? math.max(0.2, 1 - (lvl - 100) / 30) : 1.0;
    final ua = cond.uaClean / (1 + cond.uaClean * rfC) * (1 - fb) * flood;
    uaCondEff = ua;
    final mcw = control.meanCw;
    cwFlow = mcw;
    final tIn = inp.cwInT + ep.cwTempAdd;
    cwInT = tIn;
    final sub = inp.refluxSub + 20 * fb;
    _tGuess = s.tSat0;
    final part = partial;
    final dvScale = part ? control.meanDv : 0.0;
    final pDown = cond.pDownEff;
    final dpDes = math.max(cond.pTopDesign - pDown, 1.0);

    double eval(double p) {
      _t2Sweep(p, dt, qR, l0, f, hF, fs);
      final v1 = s.vapor[1];
      final pc = p * (1 - yI);
      final ts = t2.bubbleAt(pc, s.x, 0, _tGuess, _yb, 0, _kb, 0, health);
      _tGuess = ts;
      final qc = mcw > 0
          ? math.max(0.0, ua * (ts - tIn) / (1 + ua / (2 * mcw * _cpWater)))
          : 0.0;
      _qcT = qc;
      // partial condenser: the uncondensed vapour leaves the drum at y_0 = K~ x_0, so desuperheating is to that vapour
      final hVs = part ? t2.hVAt(ts, _yb, 0) : t2.hVAt(ts, s.y, nc);
      final h0 = t2.hLAt(ts - sub, s.x, 0);
      // (7.4) with the entrained tray-1 liquid, which enters the drum at h_1 (2026-10-13 ruling)
      final eh = full ? s.entrain[1] * (s.hLiq[1] - h0) : 0.0;
      var nc0 = (v1 * (hVs - s.hVap[1]) + qc - eh) / (hVs - h0);
      if (!(nc0 > 0)) nc0 = 0;
      _ncondT = nc0;
      final nvent = inp.inertVent /
          100 *
          cond.ventMax *
          math.sqrt(math.max(p - cond.pVentEff, 0.0) / 50000.0);
      final nrel = cond.reliefMax *
          ((p - cond.reliefSet) / (0.1 * cond.reliefSet)).clamp(0.0, 1.0);
      _nventT = nvent;
      _nreliefT = nrel;
      // vapour product through PV-102 (7.5)
      final dv = part ? dvScale * math.sqrt(math.max(p - pDown, 0.0) / dpDes) : 0.0;
      _dvT = dv;
      final nv = pc * cond.overheadVolume / (gasR * ts);
      return nv - nV0 - dt * (v1 - nc0 - dv - (nvent + nrel) * (1 - yI));
    }

    var p0 = s.pTop;
    var r0 = eval(p0);
    var p1 = p0 * 1.001;
    var r1 = eval(p1);
    var ok = false;
    var lastDelta = double.infinity;
    for (var it = 0; it < 12; it++) {
      final den = r1 - r0;
      if (den == 0) {
        ok = true; // two identical residuals: converged to machine precision
        break;
      }
      var p2 = p1 - r1 * (p1 - p0) / den;
      if (!(p2 > 1000)) p2 = 1000;
      if (p2 > 1e7) p2 = 1e7;
      final delta = (p2 - p1).abs();
      lastDelta = delta;
      p0 = p1;
      r0 = r1;
      p1 = p2;
      r1 = eval(p1);
      // polish to 1e-4 Pa: a 0.1 Pa stop left ~5e-11 relative jitter in P that PC-101 and TC-101 kept alive (V4)
      if (delta < 1e-4) {
        ok = true;
        break;
      }
    }
    if (!ok && lastDelta < 0.1) ok = true;
    if (!ok) {
      // safeguarded fallback: bisection on a bracket (r increases with P)
      health.pressureFallbacks++;
      var lo = math.max(1000.0, 0.5 * s.pTop), hi = 2.0 * s.pTop + 1000;
      if (eval(lo) > 0 || eval(hi) < 0) {
        p1 = s.pTop;
        eval(p1);
      } else {
        for (var it = 0; it < 60; it++) {
          final mid = 0.5 * (lo + hi);
          if (eval(mid) < 0) {
            lo = mid;
          } else {
            hi = mid;
          }
          if (hi - lo < 0.05) break;
        }
        p1 = 0.5 * (lo + hi);
        eval(p1);
      }
    }
    _pNew = p1;
    s.nCond = _ncondT;
    s.qC = _qcT;
    s.qR = qR;
    s.nVent = _nventT;
    s.nRelief = _nreliefT;
    s.dV = _dvT;
    qDelivered = qR;
    if (control.ts != null) qMax = control.ts!.qMax;
    dutyRequestExceeds =
        control.fv103.fMax * control.fv103.g(control.fv103.position) >
            qMax * (1 + 1e-6) + 1.0;
  }

  /// Overhead vapour inventory per component and inert inventory (PHYSICS.md 7.1, 12.4 step 10).
  void _t2InventoryUpdate(double dt, double f) {
    final nV0 = overheadMoles;
    final yI = nV0 + s.nI > 0 ? s.nI / (nV0 + s.nI) : 0.0;
    final v1 = s.vapor[1];
    final e1 = s.eff[1];
    final ventTot = (s.nVent + s.nRelief) * (1 - yI) + s.dV;
    final part = partial;
    for (var i = 0; i < nc; i++) {
      // the vapour that does not condense: tray-1 vapour (total condenser) or the drum vapour y_0 (partial, 7.1)
      final yc = part
          ? _kt[i] * _mnew[i] / _mhat[0]
          : (1 - e1) * _yhat[2 * nc + i] +
              e1 * _kt[nc + i] * _mnew[nc + i] / _mhat[1];
      final yv = nV0 > 0 ? s.nVi[i] / nV0 : yc;
      var nn = s.nVi[i] + dt * ((v1 - s.nCond) * yc - ventTot * yv);
      if (nn < 0) {
        if (nn < -1e-12) health.negativeClamps++;
        if (nn < -1e-6) _clampHit = true;
        nn = 0;
      }
      s.nVi[i] = nn;
      debug.ventRate[i] = ventTot * yv;
    }
    var ni = s.nI + dt * (ep.epsI * f - (s.nVent + s.nRelief) * yI);
    if (ni < 0) ni = 0;
    s.nI = ni;
  }

  /// KPIs and measurement values of the finished step (PHYSICS.md VC-5.4, 10.5).
  void _t2Diagnostics(double f, double d, double b, double hF) {
    final qr = qDelivered;
    final res = f * hF +
        qr -
        s.qC -
        d * s.hLiq[0] -
        b * s.hLiq[nTrays + 1] -
        s.dV * s.hVap[0];
    energyResidual = qr > 1 ? res.abs() / qr : 0.0;
    final mcw = cwFlow;
    cwOutT = mcw > 0 ? cwInT + s.qC / (mcw * _cpWater) : cwInT;
  }

  // ---------------------------------------------------------------- controllers

  /// Control main layer (PHYSICS.md 10.1, step 12) from the end-of-step state.
  void _controllers(double dt) {
    final N = nTrays;
    bus.drumLevelPct = 100 * s.holdup[0] * s.vLiq[0] / drumVolume;
    bus.sumpLevelPct = 100 * s.holdup[N + 1] * s.vLiq[N + 1] / sumpVolume;
    bus.columnDp = full ? hyd.pressureDropTotal : 0.0;
    bus.setCuts(ep.zEff, s.x, 0, (N + 1) * nc, nc);
    control.modelFull = full;
    if (tier2) {
      fillBusT2();
      control.modelRelief = s.nRelief > 0;
      control.modelDutyLimited = dutyRequestExceeds;
      if (s.nRelief > 0) reliefLifted = true;
    }
    if (full) {
      var maxFlood = 0.0, maxWeep = 0.0;
      var dcLim = false;
      for (var j = 1; j <= N; j++) {
        maxFlood = math.max(maxFlood,
            math.max(hyd.phi[j], math.max(hyd.dcFrac[j], hyd.fill[j])));
        maxWeep = math.max(maxWeep, hyd.weepW[j]);
        if ((hyd.flags[j] & 1) != 0) dcLim = true;
      }
      liveMaxFlood = maxFlood;
      liveMaxWeep = maxWeep;
      control.modelFlood = maxFlood > 0.9;
      control.modelWeep = maxWeep > 0.3;
      control.modelDc = dcLim;
    } else {
      liveMaxFlood = 0;
      liveMaxWeep = 0;
      control.modelFlood = false;
      control.modelWeep = false;
      control.modelDc = false;
    }
    control.pushModel(
        bus.xD, bus.xB, bus.columnDp, 0, bus.drumLevelPct, bus.sumpLevelPct);
    control.runMainLayer(dt, bus, s.time + dt);
  }

  /// Level (%) of the drum / sump from the current state.
  double get drumLevelPct => 100 * s.holdup[0] * s.vLiq[0] / drumVolume;
  double get sumpLevelPct =>
      100 * s.holdup[nTrays + 1] * s.vLiq[nTrays + 1] / sumpVolume;
}
