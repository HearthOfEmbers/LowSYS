// ignore_for_file: non_constant_identifier_names  // physics symbols (L0, VB, F, N) follow PHYSICS.md
import 'dart:math' as math;
import 'dart:typed_data';

import '../config/tray_geometry.dart';
import '../control/control_system.dart';
import '../core/ids.dart';
import '../faults/fault_effects.dart';
import '../faults/fault_manager.dart';
import '../math/banded_solver.dart';
import '../model/column_state.dart';
import '../model/tray_hydraulics.dart';
import '../thermo/tier1_constant_alpha.dart';

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
  final ColumnState s;
  final StepInputs inp;
  final ControlSystem control;
  final SolverHealth health;
  final StepDebug debug;
  final HydraulicSolver hyd;
  final EffectiveParams ep;
  final FaultManager faults;
  final MeasurementBus bus = MeasurementBus();

  /// True for full hydraulics (PHYSICS.md 5); false for ideal (M1) hydraulics.
  bool full;

  // Geometry (PHYSICS.md 5.1)
  final double aActive;
  final double weirLength;
  final double weirHeight;
  final double bennettC;
  final double drumVolume;
  final double sumpVolume;

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
    required this.s,
    required this.inp,
    required this.control,
    required this.health,
    required this.debug,
    required this.hyd,
    required this.ep,
    required this.faults,
    required this.full,
    required TrayGeometry geometry,
    required this.drumVolume,
    required this.sumpVolume,
    this.murphreePasses = 2,
  })  : nTrays = s.nTrays,
        n = s.n,
        nc = s.nc,
        aActive = geometry.areaActive,
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
      thermo.equilibrium(_xn, 0, _yy, 0);
      if (ysOut != null) {
        for (var i = 0; i < nc; i++) {
          ysOut[off + i] = _yy[i];
        }
      }
      if (j == 0) {
        // drum: the condensate has the composition of the vapour leaving tray 1
        for (var i = 0; i < nc; i++) {
          yOut[i] = yOut[nc + i];
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
    for (var j = 0; j < n; j++) {
      s.entrain[j] = 0;
      s.bypass[j] = 0;
      s.psi[j] = 0;
      s.lbar[j] = s.liquid[j];
    }
    if (full) initHydraulicState();
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
    final qin = s.vapor[j + 1] * mwv / (1000 * rhoV);
    final us = qin / aActive;
    final ks = us * math.sqrt(rhoV / (rhoL - rhoV));
    return ks <= 0 ? 1.0 : math.exp(-12.55 * math.pow(ks, 0.91));
  }

  // ---------------------------------------------------------------- the step

  /// Advances the state by [dt]. Returns false (state restored) when the step produced NaN, Inf or a
  /// negative holdup beyond tolerance.
  bool step(double dt) {
    _backup.copyFrom(s);
    _advance(dt);
    if (!_healthy()) {
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
    s.boilupAct = VB;

    // --- 6. vapour profile, Tier 1 CMO (PHYSICS.md 4.4) with sump starvation (8.1)
    final mMin = 0.05 * sumpVolume / s.vLiq[N + 1];
    final sSump = mMin > 0 ? (s.holdup[N + 1] / mMin).clamp(0.0, 1.0) : 1.0;
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

    // reflux and distillate pumps cannot take more than the drum holds (7.3)
    final v1 = s.vapor[1];
    final e1 = full ? s.entrain[1] : 0.0;
    final availD = s.holdup[0] / dt + v1 + e1;
    final totD = L0 + D;
    if (totD > availD) {
      final f = totD > 0 ? availD / totD : 0.0;
      L0 *= f;
      D *= f;
      control.fv102.cap = L0;
      control.lv101.cap = D;
    } else {
      control.fv102.cap = double.infinity;
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
      if (kd > 0) {
        // dumping tray (PHYSICS.md 5.15, 12.2): implicit solve for u = sqrt(M); the residual is convex in u
        var u = math.sqrt(math.max(mn, 0.0));
        for (var it = 0; it < 60; it++) {
          final m2 = u * u;
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
          final g = m2 - mn - dt * (inflow - lw - kd * u);
          final gp = 2 * u + dt * (2 * u * dl + kd);
          final un = math.max(0.0, u - g / gp);
          final du = (un - u).abs();
          u = un;
          if (du < 1e-12 * math.max(1.0, u)) break;
        }
        mm = u * u;
        final hcl = mm * vl / aa;
        final arg = (hcl / ae - weirHeight) / bennettC;
        var lw = arg > 0 ? weirLength * ae * arg * math.sqrt(arg) / vl : 0.0;
        if (lw > cap) lw = cap;
        lj = lw + kd * u;
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
    }

    // --- 11. new state
    for (var k = 0; k < _mnew.length; k++) {
      var v = _mnew[k];
      if (v < 0) {
        if (v < -1e-12) health.negativeClamps++;
        v = 0;
      }
      s.m[k] = v;
    }
    refreshFromHoldups();
    for (var j = 1; j <= N; j++) {
      s.eff[j] = full
          ? inp.murphree *
              (1 - ep.brokenS[j]) *
              math.min(
                  1.0,
                  s.holdup[j] *
                      s.vLiq[j] /
                      (aActive * math.max(1 - ep.brokenS[j], 0.02)) /
                      0.005)
          : _effOf(j);
    }
    _computeVapour(s.x, s.y, s.yStar);
  }

  void _componentPass(double dt, double F, int fs, double D, double B,
      double L0, Float64List z) {
    final N = nTrays;
    final v1 = s.vapor[1];
    for (var i = 0; i < nc; i++) {
      // drum row (total condenser, PHYSICS.md 12.3)
      _g[0] = 0;
      _a[0] = 0;
      _b[0] = 1 + dt * (L0 + D) / _mhat[0];
      _c[0] = -dt * (v1 * s.eff[1] * _kt[nc + i] + s.entrain[1]) / _mhat[1];
      _d[0] = s.m[i] + dt * v1 * (1 - s.eff[1]) * _yhat[2 * nc + i];
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

  // ---------------------------------------------------------------- controllers

  /// Control main layer (PHYSICS.md 10.1, step 12) from the end-of-step state.
  void _controllers(double dt) {
    final N = nTrays;
    bus.drumLevelPct = 100 * s.holdup[0] * s.vLiq[0] / drumVolume;
    bus.sumpLevelPct = 100 * s.holdup[N + 1] * s.vLiq[N + 1] / sumpVolume;
    bus.columnDp = full ? hyd.pressureDropTotal : 0.0;
    bus.feedLight = ep.zEff[0];
    bus.xD = s.x[0];
    bus.xB = s.x[(N + 1) * nc];
    control.modelFull = full;
    if (full) {
      var maxFlood = 0.0, maxWeep = 0.0;
      var dcLim = false;
      for (var j = 1; j <= N; j++) {
        maxFlood = math.max(maxFlood,
            math.max(hyd.phi[j], math.max(hyd.dcFrac[j], hyd.fill[j])));
        maxWeep = math.max(maxWeep, hyd.weepW[j]);
        if ((hyd.flags[j] & 1) != 0) dcLim = true;
      }
      control.modelFlood = maxFlood > 0.9;
      control.modelWeep = maxWeep > 0.3;
      control.modelDc = dcLim;
    } else {
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
