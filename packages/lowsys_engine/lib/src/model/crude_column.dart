// Crude column dynamics (PHYSICS.md 9.2-9.7, 12): 30 theoretical stages, three 2-stage side strippers, one
// pumparound, bottom and stripper steam, ideal overhead. Banded (tridiagonal) component solves with the explicit
// side-operation coupling of 9.4. Stage numbering in the arrays: main stage j (1..30) is index j - 1; stripper k has
// its top stage at index 30 + 2k and its bottom stage (boot) at 31 + 2k.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart';
import '../config/crude_config.dart';
import '../config/tray_geometry.dart';
import '../core/ids.dart';
import '../thermo/crude_thermo.dart';

const double _rGas = 8.314462618;
const double _g = 9.80665;

/// Actuator values the control layer hands to the column every step (SI).
class CrudeInputs {
  /// Crude rate (m3/s at 15.6 C).
  double crudeRate = 0.0368056;

  /// True furnace outlet temperature (K).
  double cot = 618.15;

  /// Pa, K: ideal top pressure and drum temperature (PHYSICS.md 9.7).
  double pTop = 160000, drumT = 318.15;

  /// Reflux, naphtha and residue valve flows (mol/s).
  double reflux = 0, naphtha = 0, residue = 0;

  /// Product valve flows of FC-311..313 (m3/s at 15.6 C, before the stripper-level cut).
  final Float64List prodVol = Float64List(3);

  /// Requested PA duty (W) and the pump factor (1 - F25 s).
  double paDuty = 5e6, paScale = 1;

  /// Delivered steam (kg/s): bottom, ss1, ss2, ss3.
  final Float64List steam = Float64List(4);
}

/// The column state and one-step integrator.
class CrudeColumn {
  static const int nm = 30, ns = 36, nc = 9;
  final ColumnConfig config;
  final CrudeUnitConfig cu;
  final CrudeThermo th;
  final SolverHealth health;
  final CrudeInputs inp = CrudeInputs();

  // ---- topology
  late final int feedSt;
  late final int paDrawSt, paRetSt;
  late final List<int> drawSt, retSt;
  late final double paCirc, tRmin;
  late final double steamT;
  final double tauW, ywMax;

  // ---- geometry per stage (main + strippers)
  final Float64List diaAt = Float64List(ns);
  late final TrayGeometry geo;
  late final double ssBoot, ssLevelSp, ssTau;

  // ---- state
  double time = 0;
  final Float64List t = Float64List(ns), p = Float64List(ns);
  final Float64List x = Float64List(ns * nc), hold = Float64List(ns), ywF = Float64List(ns);
  final Float64List l = Float64List(ns), v = Float64List(ns), steamUp = Float64List(ns);
  final Float64List sd = Float64List(3), pAct = Float64List(3), cutFac = Float64List(3);
  double drumHold = 0, sumpHold = 0;
  final Float64List xSump = Float64List(nc);
  double l0 = 0;
  double qPA = 0, paAct = 0, qPAmax = 0, qc = 0;
  bool drumLimited = false;
  double cotCtl = 618.15;

  // ---- derived (recomputed every step)
  final Float64List kk = Float64List(ns * nc), dl = Float64List(ns * nc), yy = Float64List(ns * nc);
  final Float64List hl = Float64List(ns), hv = Float64List(ns);
  final Float64List _xn = Float64List(ns * nc);
  final Float64List _mNew = Float64List(ns);
  final Float64List _lw = Float64List(ns);
  final Float64List _steamK = Float64List(4); // mol/s of the four injection points
  final Float64List _ywOld = Float64List(ns); // steam fraction the K values of this step were computed with
  final Float64List _a = Float64List(nm), _b = Float64List(nm), _c = Float64List(nm), _r = Float64List(nm);
  final Float64List _cp = Float64List(nm), _dp = Float64List(nm);
  late CrudeFlash feed;
  double _feedT = -1, _feedP = -1;
  final Float64List z;
  double fF = 0;

  // ---- hydraulics (refreshed every [hydEvery] steps)
  final Float64List dp = Float64List(nm), flood = Float64List(nm), hcl = Float64List(nm), weepFrac = Float64List(nm);
  final Float64List rhoLs = Float64List(ns), sigmas = Float64List(ns);
  int hydEvery = 20, _hydCount = 0;

  /// False: ideal hydraulics (fixed 700 Pa per tray, no flood or weep figures).
  bool hydFull = true;
  double vDrum = 1.5e-4, vSump = 2.5e-4;

  CrudeColumn(this.config, this.health)
      : cu = config.crude!,
        th = CrudeThermo(config.crude!.assay),
        z = Float64List(nc),
        tauW = config.crude!.steamFilterTau,
        ywMax = config.crude!.steamFracMax {
    final f = config.feeds.first;
    feedSt = f.stage;
    drawSt = [for (final d in config.sideDraws) d.drawStage];
    retSt = [for (final d in config.sideDraws) d.returnStage];
    final pa = config.pumparounds.first;
    paDrawSt = pa.drawStage;
    paRetSt = pa.returnStage;
    paCirc = pa.circulation;
    tRmin = pa.tReturnMin;
    steamT = config.steam.first.temperature;
    final secs = config.sections.whereType<TraySection>().toList();
    geo = secs.first.geometry;
    var stage = 0;
    for (final s in secs) {
      for (var k = 0; k < s.trays; k++) {
        diaAt[stage++] = s.geometry.diameter;
      }
    }
    for (var k = 0; k < 3; k++) {
      diaAt[30 + 2 * k] = config.strippers[k].diameter;
      diaAt[31 + 2 * k] = config.strippers[k].diameter;
    }
    ssBoot = config.strippers.first.bootVolume;
    ssLevelSp = config.strippers.first.levelSp;
    ssTau = config.strippers.first.levelTau;
    for (var i = 0; i < nc; i++) {
      z[i] = f.z[i];
    }
    feed = th.flash(z, inp.cot, 1.7e5);
  }

  int s1(int k) => 30 + 2 * k;
  int s2(int k) => 31 + 2 * k;
  static const double kgs2mol = 1 / 0.018015;

  // ---------------------------------------------------------------- tray geometry helpers
  double aT(int a) => math.pi * diaAt[a] * diaAt[a] / 4;
  double aA(int a) => aT(a) * (1 - 2 * geo.downcomerFraction);
  double aN(int a) => aT(a) * (1 - geo.downcomerFraction);
  double lwOf(int a) => geo.weirLength * diaAt[a] / geo.diameter;
  double vL(int a) => 1.15 * th.vStdMix(x, a * nc);
  double m0(int a) => aA(a) * geo.weirHeight * 0.5 / vL(a);

  double _weir(int a) {
    const al = 0.5;
    final cc = geo.bennettC;
    final h = hold[a] * vL(a) / (aA(a) * al) - geo.weirHeight;
    if (h <= 0) return 0;
    return lwOf(a) * al * math.pow(h / cc, 1.5) / vL(a);
  }

  // ---------------------------------------------------------------- initialisation (PHYSICS.md 13.1)
  void initCold() {
    fF = inp.crudeRate / th.vStdMix(z, 0);
    for (var j = 0; j < nm; j++) {
      t[j] = 273.15 + 120 + (340 - 120) * j / (nm - 1);
      for (var i = 0; i < nc; i++) {
        x[j * nc + i] = z[i];
      }
    }
    for (var k = 0; k < 3; k++) {
      t[s1(k)] = t[drawSt[k] - 1] - 5;
      t[s2(k)] = t[drawSt[k] - 1] - 10;
      for (var i = 0; i < nc; i++) {
        x[s1(k) * nc + i] = z[i];
        x[s2(k) * nc + i] = z[i];
      }
    }
    for (var i = 0; i < nc; i++) {
      xSump[i] = z[i];
    }
    time = 0;
    cotCtl = inp.cot;
    for (var a = 0; a < ns; a++) {
      p[a] = inp.pTop;
      hold[a] = 3 * m0(a);
    }
    for (var k = 0; k < 3; k++) {
      hold[s2(k)] = ssLevelSp * ssBoot / vL(s2(k));
    }
    _setPressures();
    for (var a = 0; a < nm; a++) {
      v[a] = 0.3 * fF;
    }
    final pk0 = [for (var k = 0; k < 3; k++) _prodSpecMol(k)];
    for (var k = 0; k < 3; k++) {
      v[s1(k)] = 0.2 * pk0[k];
      v[s2(k)] = 0.1 * pk0[k];
      pAct[k] = pk0[k];
      cutFac[k] = 1;
    }
    l0 = 0.5 * fF;
    _setSteam();
    for (var a = 0; a < ns; a++) {
      ywF[a] = _ywRaw(a);
    }
    _feedT = -1;
    _updateFeed();
    _hydCount = 0;
    _refreshProps();
    hydraulics();
    _setPressures();
    drumHold = 0.5 * cu.drumVolume / vDrum;
    sumpHold = 0.5 * cu.sumpVolume / vSump;
  }

  double _prodSpecMol(int k) => inp.prodVol[k] / th.vStdMix(x, s2(k) * nc);

  // ---------------------------------------------------------------- derived-state helpers
  void _setPressures() {
    p[0] = inp.pTop;
    for (var j = 1; j < nm; j++) {
      p[j] = p[j - 1] + dp[j - 1];
    }
    for (var k = 0; k < 3; k++) {
      p[s1(k)] = p[drawSt[k] - 1];
      p[s2(k)] = p[drawSt[k] - 1];
    }
  }

  void _setSteam() {
    for (var q = 0; q < 4; q++) {
      _steamK[q] = inp.steam[q] * kgs2mol;
    }
    for (var j = 1; j <= nm; j++) {
      var s = _steamK[0];
      for (var k = 0; k < 3; k++) {
        if (j <= retSt[k]) s += _steamK[1 + k];
      }
      steamUp[j - 1] = s;
    }
    for (var k = 0; k < 3; k++) {
      steamUp[s1(k)] = _steamK[1 + k];
      steamUp[s2(k)] = _steamK[1 + k];
    }
  }

  double _ywRaw(int a) => math.min(ywMax, steamUp[a] / (steamUp[a] + math.max(v[a], 1e-9)));

  void _updateFeed() {
    final tf = inp.cot, pf = p[feedSt - 1];
    if ((tf - _feedT).abs() > 0.02 || (pf - _feedP).abs() > 30) {
      feed = th.flash(z, tf, pf);
      _feedT = tf;
      _feedP = pf;
    }
  }

  /// K, y, h_L, h_V of every stage at the current T, x and filtered steam fraction.
  void _refreshProps() {
    for (var a = 0; a < ns; a++) {
      final pHc = p[a] * (1 - ywF[a]);
      final off = a * nc;
      th.kValues(kk, off, t[a], pHc, dl);
      var s = 0.0;
      for (var i = 0; i < nc; i++) {
        final y = kk[off + i] * x[off + i];
        yy[off + i] = y;
        s += y;
      }
      if (s > 0) {
        final inv = 1 / s;
        for (var i = 0; i < nc; i++) {
          yy[off + i] *= inv;
        }
      }
      hl[a] = th.hLmix(x, off, t[a]);
      hv[a] = th.hVmix(yy, off, t[a]);
    }
  }

  /// Steam enthalpy flow into stage index [a] minus out (W), from the current temperatures.
  double _qSteam(int a) {
    if (a < nm) {
      final j = a + 1;
      var qin = j < nm ? steamUp[a + 1] * th.hVwater(t[a + 1]) : _steamK[0] * th.hVwater(steamT);
      for (var k = 0; k < 3; k++) {
        if (retSt[k] == j) qin += _steamK[1 + k] * th.hVwater(t[s1(k)]);
      }
      return qin - steamUp[a] * th.hVwater(t[a]);
    }
    final k = (a - 30) ~/ 2;
    final top = a == s1(k);
    final tin = top ? t[s2(k)] : steamT;
    return _steamK[1 + k] * (th.hVwater(tin) - th.hVwater(t[a]));
  }

  // ---------------------------------------------------------------- one step
  /// Advances by [dt] seconds. Returns false when the state went non-finite (the caller restores a backup).
  bool step(double dt) {
    fF = inp.crudeRate / th.vStdMix(z, 0);
    _setSteam();
    if (_hydCount++ % hydEvery == 0) {
      hydraulics();
    }
    _setPressures();
    _updateFeed();
    _refreshProps();
    // stripper draws (LC-31x on the stripper levels with feed-forward) and product cut
    for (var a = 0; a < ns; a++) {
      _lw[a] = _weir(a);
    }
    final pSpec = [0.0, 0.0, 0.0];
    for (var k = 0; k < 3; k++) {
      final ab = s2(k);
      final mRef = ssLevelSp * ssBoot / vL(ab);
      // product cut by the boot level, in fractions of the level SP (the prototype's law, PHYSICS.md 9.4)
      cutFac[k] = ((hold[ab] / mRef - 0.2) / 0.3).clamp(0.0, 1.0);
      pSpec[k] = _prodSpecMol(k);
      pAct[k] = pSpec[k] * cutFac[k];
      final req = math.max(0.0, pAct[k] + v[s1(k)] + (mRef - hold[ab]) / ssTau);
      final ad = drawSt[k] - 1;
      final avail = math.max(0.0, 0.5 * (hold[ad] - 0.3 * m0(ad)) / dt);
      sd[k] = math.min(req, avail);
    }
    final ap = paDrawSt - 1;
    final pPA = paCirc * inp.paScale / th.vStdMix(x, ap * nc);
    paAct = math.min(pPA, math.max(0.0, 0.5 * (hold[ap] - 0.3 * m0(ap)) / dt));
    qPAmax = paAct <= 1e-9 ? 0.0 : paAct * (hl[ap] - th.hLmix(x, ap * nc, tRmin));
    qPA = paAct <= 1e-9 ? 0.0 : math.min(inp.paDuty, qPAmax);
    for (var j = 0; j < nm; j++) {
      l[j] = _lw[j];
    }
    for (var k = 0; k < 3; k++) {
      l[s1(k)] = _lw[s1(k)];
      l[s2(k)] = pAct[k];
    }
    // vapour from the energy balances, strippers first, then the main column bottom-up (4.6)
    for (var k = 0; k < 3; k++) {
      final at = s1(k), ab = s2(k), ad = drawSt[k] - 1;
      var den = hv[ab] - hl[ab];
      if (den <= 0) {
        health.negativeLatent++;
        den = 1;
      }
      v[ab] = math.max(0.0, (l[at] * (hl[at] - hl[ab]) + _qSteam(ab)) / den);
      den = hv[at] - hl[at];
      if (den <= 0) {
        health.negativeLatent++;
        den = 1;
      }
      v[at] = math.max(
          0.0, (sd[k] * (hl[ad] - hl[at]) + v[ab] * (hv[ab] - hl[at]) + _qSteam(at)) / den);
    }
    final hr = th.hLmix(yy, 0, inp.drumT);
    final paH = paAct > 1e-9 ? hl[ap] - qPA / paAct : hl[ap];
    for (var j = nm; j >= 1; j--) {
      final a = j - 1;
      var num = _qSteam(a);
      if (j == 1) {
        num += l0 * (hr - hl[0]);
      } else {
        num += l[a - 1] * (hl[a - 1] - hl[a]);
      }
      if (j < nm) num += v[a + 1] * (hv[a + 1] - hl[a]);
      if (j == feedSt) num += fF * (feed.h - hl[a]);
      if (j == paRetSt && paAct > 0) num += paAct * (paH - hl[a]);
      for (var k = 0; k < 3; k++) {
        if (retSt[k] == j) num += v[s1(k)] * (hv[s1(k)] - hl[a]);
      }
      var den = hv[a] - hl[a];
      if (den <= 0) {
        health.negativeLatent++;
        den = 1;
      }
      final vRaw = num / den;
      if (vRaw <= 0) {
        // vapour-free stage (spec rulings M9 item 5): V = 0 and T follows the stage energy balance, not the bubble point,
        // until the stage is supplied with enough energy to boil again
        v[a] = 0.0;
        final cp = th.hLmix(x, a * nc, t[a] + 1) - hl[a];
        // implicit in the outflow enthalpy (d num / dT = -L cp), stable on the thin film of a dry tray
        vfDT[a] = cp > 1 && hold[a] > 0 ? (dt * num / (cp * (hold[a] + dt * l[a]))).clamp(-5.0, 5.0) : 0.0;
        vf[a] = true;
      } else {
        v[a] = vRaw;
        vf[a] = false;
      }
    }
    // overhead: reflux from FC-301, limited by what the drum can supply
    final reflux = inp.reflux;
    final lMax = math.max(0.0, v[0] + (drumHold - 0.02 * cu.drumVolume / vDrum) / 30);
    l0 = math.min(reflux, lMax);
    drumLimited = reflux > lMax;
    // steam fraction filter (9.3)
    final w = math.min(1.0, dt / tauW);
    for (var a = 0; a < ns; a++) {
      _ywOld[a] = ywF[a];
      ywF[a] += w * (_ywRaw(a) - ywF[a]);
    }
    // holdups, semi-implicit in the weir outflow (L_out(M_new) = L_out + dL/dM dM): the explicit weir relation is
    // unstable for dt above about 1 s on the small stripping trays
    for (var j = 1; j <= nm; j++) {
      final a = j - 1;
      var d = (j == 1 ? l0 : l[a - 1]) + (j < nm ? v[a + 1] : 0.0) - v[a];
      if (j == feedSt) d += fF;
      if (j == paRetSt) d += paAct;
      if (j == paDrawSt) d -= paAct;
      for (var k = 0; k < 3; k++) {
        if (retSt[k] == j) d += v[s1(k)];
        if (drawSt[k] == j) d -= sd[k];
      }
      _implicitHold(a, d, dt);
    }
    for (var k = 0; k < 3; k++) {
      final at = s1(k), ab = s2(k);
      _implicitHold(at, sd[k] + v[ab] - v[at], dt);
      _mNew[ab] = math.max(1e-3, hold[ab] + dt * (l[at] - pAct[k] - v[ab]));
    }
    _components(dt);
    // drum and sump (ideal overhead composition: reflux and naphtha leave at y1)
    final dMax = math.max(0.0, v[0] - l0 + (drumHold - 0.02 * cu.drumVolume / vDrum) / 30);
    final dNaph = math.min(inp.naphtha, dMax);
    drumHold = math.max(0.0, drumHold + dt * (v[0] - l0 - dNaph));
    final bMax = math.max(0.0, l[nm - 1] + (sumpHold - 0.02 * cu.sumpVolume / vSump) / 30);
    final bRes = math.min(inp.residue, bMax);
    final lin = l[nm - 1];
    final sNew = math.max(1e-3, sumpHold + dt * (lin - bRes));
    if (lin > 0) {
      final wmix = math.min(1.0, lin * dt / sNew);
      var sum = 0.0;
      for (var i = 0; i < nc; i++) {
        xSump[i] += wmix * (x[(nm - 1) * nc + i] - xSump[i]);
        sum += xSump[i];
      }
      for (var i = 0; i < nc; i++) {
        xSump[i] /= sum;
      }
    }
    sumpHold = sNew;
    naphthaOut = dNaph;
    residueOut = bRes;
    qc = _condenserDuty();
    time += dt;
    return t[0].isFinite && t[nm - 1].isFinite && v[0].isFinite;
  }

  /// Holdup update of a weir stage with the inflow-minus-vapour balance [dNon] (everything except the weir outflow).
  void _implicitHold(int a, double dNon, double dt) {
    final lo = l[a];
    final hFroth = hold[a] * vL(a) / (aA(a) * 0.5) - geo.weirHeight;
    final k = hFroth > 1e-9 ? 1.5 * lo * vL(a) / (aA(a) * 0.5 * hFroth) : 0.0;
    var dM = dt * (dNon - lo) / (1 + dt * k);
    var mNew = hold[a] + dM;
    final floor = 0.05 * m0(a); // a minimal wetted film keeps a dry tray's composition and temperature defined
    if (mNew < floor) {
      mNew = floor;
      dM = mNew - hold[a];
      // spec rulings M9 C2: with the film floor binding the outflow follows from the clamped dM, L = In - Out - dM/dt
      final lNew = dNon - dM / dt;
      if (lNew < 0) health.negativeClamps++; // L = 0 with M below the film: counted
      _mNew[a] = mNew;
      l[a] = math.max(0.0, lNew);
      return;
    }
    _mNew[a] = mNew;
    l[a] = math.max(0.0, lo + k * dM);
  }

  double naphthaOut = 0, residueOut = 0;

  /// Vapour-free main-column stages (V_HC = 0, T from the energy balance) and the temperature step they take.
  late final List<bool> vf = List<bool>.filled(ns, false);
  late final List<double> vfDT = List<double>.filled(ns, 0.0);

  double _condenserDuty() {
    return v[0] * (hv[0] - th.hLmix(yy, 0, inp.drumT)) + steamUp[0] * (th.hVwater(t[0]) - th.hLwater(inp.drumT));
  }

  /// Implicit component step: strippers first, then the main column tridiagonal per component (9.4).
  void _components(double dt) {
    final ap = paDrawSt - 1;
    for (var i = 0; i < nc; i++) {
      // strippers (2 x 2), liquid feed S_d x_d^n (explicit)
      for (var k = 0; k < 3; k++) {
        final at = s1(k), ab = s2(k), ad = drawSt[k] - 1;
        final a11 = _mNew[at] / dt + l[at] + v[at] * kk[at * nc + i];
        final a12 = -v[ab] * kk[ab * nc + i];
        final a21 = -l[at];
        final a22 = _mNew[ab] / dt + pAct[k] + v[ab] * kk[ab * nc + i];
        final b1 = hold[at] * x[at * nc + i] / dt + sd[k] * x[ad * nc + i];
        final b2 = hold[ab] * x[ab * nc + i] / dt;
        final det = a11 * a22 - a12 * a21;
        _xn[at * nc + i] = (b1 * a22 - a12 * b2) / det;
        _xn[ab * nc + i] = (a11 * b2 - a21 * b1) / det;
      }
      // main column
      for (var j = 1; j <= nm; j++) {
        final r = j - 1;
        var diag = _mNew[r] / dt + l[r] + v[r] * kk[r * nc + i];
        var lower = 0.0, upper = 0.0;
        var rhs = hold[r] * x[r * nc + i] / dt;
        if (j == 1) {
          diag -= l0 * kk[i];
        } else {
          lower = -l[r - 1];
        }
        if (j < nm) upper = -v[r + 1] * kk[(r + 1) * nc + i];
        if (j == feedSt) rhs += fF * z[i];
        if (j == paDrawSt) rhs -= paAct * x[ap * nc + i];
        if (j == paRetSt) rhs += paAct * x[ap * nc + i];
        for (var k = 0; k < 3; k++) {
          if (drawSt[k] == j) rhs -= sd[k] * x[r * nc + i];
          if (retSt[k] == j) rhs += v[s1(k)] * kk[s1(k) * nc + i] * _xn[s1(k) * nc + i];
        }
        _a[r] = lower;
        _b[r] = diag;
        _c[r] = upper;
        _r[r] = rhs;
      }
      // Thomas algorithm
      _cp[0] = _c[0] / _b[0];
      _dp[0] = _r[0] / _b[0];
      for (var r = 1; r < nm; r++) {
        final m = _b[r] - _a[r] * _cp[r - 1];
        _cp[r] = _c[r] / m;
        _dp[r] = (_r[r] - _a[r] * _dp[r - 1]) / m;
      }
      _xn[(nm - 1) * nc + i] = _dp[nm - 1];
      for (var r = nm - 2; r >= 0; r--) {
        _xn[r * nc + i] = _dp[r] - _cp[r] * _xn[(r + 1) * nc + i];
      }
    }
    // normalise, store holdups and bubble points
    for (var a = 0; a < ns; a++) {
      final off = a * nc;
      var sum = 0.0;
      for (var i = 0; i < nc; i++) {
        final xi = _xn[off + i] < 0 ? 0.0 : _xn[off + i];
        _xn[off + i] = xi;
        sum += xi;
      }
      if (sum <= 0) {
        health.negativeClamps++;
        for (var i = 0; i < nc; i++) {
          _xn[off + i] = z[i];
        }
        sum = 1;
      }
      final inv = 1 / sum;
      var s = 0.0, ds = 0.0;
      for (var i = 0; i < nc; i++) {
        final xi = _xn[off + i] * inv;
        x[off + i] = xi;
        final kx = xi * kk[off + i];
        s += kx;
        ds += kx * dl[off + i];
      }
      hold[a] = _mNew[a];
      // Newton on ln sum(x K) = 0 with K re-scaled to the updated steam fraction (two passes)
      final scale = (1 - _ywOld[a]) / (1 - ywF[a]);
      s *= scale;
      ds *= scale;
      if (vf[a]) {
        t[a] += vfDT[a];
      } else if (s > 0 && ds > 0) {
        var dT = -math.log(s) / (ds / s);
        dT = dT.clamp(-10.0, 10.0);
        // second-order correction with exp(dl * dT)
        var s2 = 0.0, ds2 = 0.0;
        for (var i = 0; i < nc; i++) {
          final kx = x[off + i] * kk[off + i] * scale * math.exp(dl[off + i] * dT);
          s2 += kx;
          ds2 += kx * dl[off + i];
        }
        if (s2 > 0 && ds2 > 0) dT += (-math.log(s2) / (ds2 / s2)).clamp(-5.0, 5.0);
        t[a] += dT.clamp(-15.0, 15.0);
      } else {
        health.bubbleFallbacks++;
      }
    }
  }


  // ---------------------------------------------------------------- hydraulics (PHYSICS.md 5, valve trays)
  double _rhoLmix(int a) {
    var vl = 0.0, mw = 0.0;
    for (var i = 0; i < nc; i++) {
      vl += x[a * nc + i] * th.mw[i] / (1000 * th.rhoL(i, t[a]));
      mw += x[a * nc + i] * th.mw[i];
    }
    return mw / 1000 / vl;
  }

  double _sigmaMix(int a) {
    var s = 0.0;
    for (var i = 0; i < nc; i++) {
      s += x[a * nc + i] * math.pow(th.sigma(i, t[a]), 0.25);
    }
    return math.pow(s, 4).toDouble();
  }

  // vapour leaving stage a (HC + steam): total mol/s, MW, mass density
  double _vTot = 0, _vMw = 0, _vRho = 0;
  void _vapour(int a) {
    final vh = v[a], sw = steamUp[a], tot = vh + sw;
    if (tot < 1e-6) {
      _vTot = 0;
      _vMw = 100;
      _vRho = p[a] * 0.1 / (_rGas * t[a]);
      return;
    }
    var mw = 0.0, tc = 0.0, pc = 0.0, om = 0.0;
    final off = a * nc;
    for (var i = 0; i < nc; i++) {
      final yi = yy[off + i] * vh / tot;
      mw += yi * th.mw[i];
      tc += yi * th.tc[i];
      pc += yi * math.exp(th.lnPc[i]);
      om += yi * th.om[i];
    }
    final yw = sw / tot;
    mw += yw * CrudeThermo.waterMw;
    tc += yw * 647.10;
    pc += yw * 220.64e5;
    om += yw * 0.345;
    final tr = t[a] / tc, pr = p[a] / pc;
    final b0 = 0.083 - 0.422 / math.pow(tr, 1.6), b1 = 0.139 - 0.172 / math.pow(tr, 4.2);
    final zz = (1 + (b0 + om * b1) * pr / tr).clamp(0.30, 1.05);
    _vTot = tot;
    _vMw = mw;
    _vRho = p[a] * mw / (1000 * zz * _rGas * t[a]);
  }

  /// Tray pressure drop, jet flood and froth per stage 1..30 (valve trays), and the pressures that follow.
  void hydraulics() {
    final lW0 = geo.weirLength;
    for (var j = 1; j <= nm; j++) {
      final a = j - 1;
      if (!hydFull) {
        dp[a] = 700;
        flood[a] = 0;
        hcl[a] = 0;
        weepFrac[a] = 0;
        continue;
      }
      final rl = _rhoLmix(a), sig = _sigmaMix(a);
      rhoLs[a] = rl;
      sigmas[a] = sig;
      _vapour(a);
      final vTot = _vTot, vMw = _vMw, rv = _vRho;
      final qOut = vTot * vMw / (1000 * rv);
      double qIn;
      if (j < nm) {
        _vapour(a + 1);
        qIn = _vTot * _vMw / (1000 * _vRho);
        for (var k = 0; k < 3; k++) {
          if (retSt[k] == j) {
            _vapour(s1(k));
            qIn += _vTot * _vMw / (1000 * _vRho);
          }
        }
      } else {
        qIn = _steamK[0] * _rGas * t[a] / p[a];
      }
      final mwl = th.mwMix(x, a * nc);
      final flv = vTot < 1e-6 ? 2.0 : ((l[a] * mwl) / (vTot * vMw) * math.sqrt(rv / rl)).clamp(0.01, 2.0);
      final csb = 0.0105 + 8.127e-4 * math.pow(geo.traySpacing * 1000, 0.755) * math.exp(-1.463 * math.pow(flv, 0.842));
      final unf = csb * math.pow(sig / 0.020, 0.2) * math.sqrt((rl - rv) / rv);
      flood[a] = (qOut / aN(a)) / unf;
      final aa = aA(a), lW = lW0 * diaAt[a] / geo.diameter;
      final amin = geo.valveClosedRatio * geo.valveOpenFraction * aa, amax = geo.valveOpenFraction * aa;
      final dpc = rv / 2 * math.pow(qIn / (geo.valveCoeff * amin), 2);
      double dry0;
      if (dpc < geo.valveLiftDp) {
        dry0 = dpc;
      } else {
        final abal = qIn / (geo.valveCoeff * math.sqrt(2 * geo.valveLiftDp / rv));
        dry0 = abal <= amax ? geo.valveLiftDp : rv / 2 * math.pow(qIn / (geo.valveCoeff * amax), 2);
      }
      final ks = (qIn / aa) * math.sqrt(rv / (rl - rv));
      final ae = math.exp(-12.55 * math.pow(ks, 0.91));
      final qw = l[a] * mwl / (1000 * rl);
      hcl[a] = ae * (geo.weirHeight + geo.bennettC * math.pow(qw / (lW * ae), 2 / 3));
      dp[a] = dry0 + rl * _g * hcl[a] + 4 * sig / 0.040;
      // weeping: the valves are open (dry drop at or above the lift) when the vapour load carries the tray
      weepFrac[a] = dpc >= geo.valveLiftDp * 0.5 ? 0.0 : (1 - dpc / (geo.valveLiftDp * 0.5)).clamp(0.0, 1.0);
    }
    // drum and sump liquid molar volumes (m3/mol)
    vDrum = _drumMolarVolume();
    vSump = 1.15 * th.vStdMix(xSump, 0);
  }

  double _drumMolarVolume() {
    var vl = 0.0;
    for (var i = 0; i < nc; i++) {
      vl += yy[i] * th.mw[i] / (1000 * th.rhoL(i, inp.drumT));
    }
    return vl;
  }

  // ---------------------------------------------------------------- persistence
  static List<double> _l(Float64List a) => a.toList();
  static void _ld(Float64List a, Object? j) {
    final l = j! as List<Object?>;
    for (var i = 0; i < a.length && i < l.length; i++) {
      a[i] = (l[i]! as num).toDouble();
    }
  }

  Map<String, Object?> toJson() => {
        'time': time,
        't': _l(t),
        'p': _l(p),
        'x': _l(x),
        'hold': _l(hold),
        'ywF': _l(ywF),
        'l': _l(l),
        'v': _l(v),
        'steamUp': _l(steamUp),
        'sd': _l(sd),
        'pAct': _l(pAct),
        'cutFac': _l(cutFac),
        'xSump': _l(xSump),
        'dp': _l(dp),
        'flood': _l(flood),
        'hcl': _l(hcl),
        'weepFrac': _l(weepFrac),
        'drumHold': drumHold,
        'sumpHold': sumpHold,
        'l0': l0,
        'qPA': qPA,
        'paAct': paAct,
        'qPAmax': qPAmax,
        'qc': qc,
        'cotCtl': cotCtl,
        'vDrum': vDrum,
        'vSump': vSump,
        'naphthaOut': naphthaOut,
        'residueOut': residueOut,
      };

  void loadJson(Map<String, Object?> j) {
    time = (j['time']! as num).toDouble();
    _ld(t, j['t']);
    _ld(p, j['p']);
    _ld(x, j['x']);
    _ld(hold, j['hold']);
    _ld(ywF, j['ywF']);
    _ld(l, j['l']);
    _ld(v, j['v']);
    _ld(steamUp, j['steamUp']);
    _ld(sd, j['sd']);
    _ld(pAct, j['pAct']);
    _ld(cutFac, j['cutFac']);
    _ld(xSump, j['xSump']);
    _ld(dp, j['dp']);
    _ld(flood, j['flood']);
    _ld(hcl, j['hcl']);
    _ld(weepFrac, j['weepFrac']);
    double d(String k) => (j[k]! as num).toDouble();
    drumHold = d('drumHold');
    sumpHold = d('sumpHold');
    l0 = d('l0');
    qPA = d('qPA');
    paAct = d('paAct');
    qPAmax = d('qPAmax');
    qc = d('qc');
    cotCtl = d('cotCtl');
    vDrum = d('vDrum');
    vSump = d('vSump');
    naphthaOut = d('naphthaOut');
    residueOut = d('residueOut');
    fF = inp.crudeRate / th.vStdMix(z, 0);
    _feedT = -1;
    _setSteam();
    _updateFeed();
    _refreshProps();
  }

  // ---------------------------------------------------------------- reporting
  double get crudeRate => inp.crudeRate;
  double volPct(double mol, Float64List xx, int off) => 100 * mol * th.vStdMix(xx, off) / inp.crudeRate;

  /// Naphtha rate leaving the drum (mol/s).
  double get dNaph => naphthaOut;
  double get yNaph => volPct(naphthaOut, yy, 0);
  double yProd(int k) => volPct(pAct[k], x, s2(k) * nc);
  double get yRes => volPct(residueOut, xSump, 0);
  double get overflash => volPct(l[feedSt - 2], x, (feedSt - 2) * nc);
  double get drumLevelPct => 100 * drumHold * vDrum / cu.drumVolume;
  double get sumpLevelPct => 100 * sumpHold * vSump / cu.sumpVolume;
  double bootLevelPct(int k) => 100 * hold[s2(k)] * vL(s2(k)) / ssBoot;

  /// Water dew-point margin on stage 1 (K).
  double get waterDewMargin {
    final pw = p[0] * steamUp[0] / (steamUp[0] + v[0]);
    if (!(pw > 0)) return double.infinity;
    var tt = 360.0;
    for (var it = 0; it < 50; it++) {
      tt -= (th.lnPsat(nc, tt) - math.log(pw)) / th.dlnPsat(nc, tt);
    }
    return t[0] - tt;
  }

  /// PA return temperature (K) from the return enthalpy.
  double get paReturnT {
    final ap = paDrawSt - 1;
    if (paAct <= 1e-9) return t[ap];
    final h = hl[ap] - qPA / paAct;
    var tt = t[ap];
    for (var it = 0; it < 30; it++) {
      var cp = 0.0;
      for (var i = 0; i < nc; i++) {
        cp += x[ap * nc + i] * (th.cp0[i] + th.dcp[i] * (tt - 298.15));
      }
      tt -= (th.hLmix(x, ap * nc, tt) - h) / cp;
    }
    return tt;
  }

  /// Relative energy closure (in - out)/feed enthalpy at the current state (steady-state check, VC-15.4).
  double energyResidual() {
    var hin = fF * feed.h + _steamK[0] * th.hVwater(steamT);
    var wTot = _steamK[0];
    for (var k = 0; k < 3; k++) {
      hin += _steamK[1 + k] * th.hVwater(steamT);
      wTot += _steamK[1 + k];
    }
    var hout = naphthaOut * th.hLmix(yy, 0, inp.drumT) + wTot * th.hLwater(inp.drumT) + qc + qPA;
    for (var k = 0; k < 3; k++) {
      hout += pAct[k] * hl[s2(k)];
    }
    hout += residueOut * hl[nm - 1];
    // spec rulings M9 C3: relative to the duty moved, Q_C + Q_PA (fF h_F is small and can pass through zero)
    final den = qc.abs() + qPA.abs();
    return (hin - hout) / (den > 1 ? den : (fF * feed.h).abs());
  }

  /// Relative mass closure (feed - products)/feed at the current state.
  double massResidual() {
    final fin = fF * th.mwMix(z, 0);
    var out = naphthaOut * th.mwMix(yy, 0) + residueOut * th.mwMix(xSump, 0);
    for (var k = 0; k < 3; k++) {
      out += pAct[k] * th.mwMix(x, s2(k) * nc);
    }
    return (fin - out) / fin;
  }

  /// Total column pressure drop (Pa).
  double get columnDp {
    var s = 0.0;
    for (var j = 0; j < nm; j++) {
      s += dp[j];
    }
    return s;
  }
}
