import 'dart:math' as math;

import '../config/column_config.dart';

/// Sump-liquid properties and steam temperature that the loop sees; frozen over a main step (PHYSICS.md 8.3.2).
class ThermosyphonProps {
  /// kg/m3
  double rhoL, rhoV;

  /// Mass latent heat (J/kg) and liquid heat capacity (J/kg/K).
  double lambdaMass, cpL;

  /// Liquid viscosity (Pa s), dT_sat/dP (K/Pa).
  double muL, dTsatdP;

  /// Sump temperature and steam temperature (K).
  double tSump, tSteam;
  ThermosyphonProps({
    this.rhoL = 780,
    this.rhoV = 2.93,
    this.lambdaMass = 361e3,
    this.cpL = 1950,
    this.muL = 0.27e-3,
    this.dTsatdP = 3.63e-4,
    this.tSump = 383.54,
    this.tSteam = 421.25,
  });

  void copyFrom(ThermosyphonProps o) {
    rhoL = o.rhoL;
    rhoV = o.rhoV;
    lambdaMass = o.lambdaMass;
    cpL = o.cpL;
    muL = o.muL;
    dTsatdP = o.dTsatdP;
    tSump = o.tSump;
    tSteam = o.tSteam;
  }
}

/// The thermosyphon reboiler loop (PHYSICS.md 8.3): circulation W, riser quality, the exact exit-quality solve with
/// mist-flow degradation, an implicit momentum balance, the instability index I_s (8.4) and the Stuart-Landau
/// oscillator (8.5). Pure: no column. One [substep] per control fast-layer sub-step (0.1 s).
class ThermosyphonLoop {
  static const double g = 9.80665;
  static const double _k = 0.65 / 0.35;
  static const double tauF = 30.0, tauS = 20.0, aSat = 0.30;

  ThermosyphonGeometry geo;
  final ThermosyphonProps p;

  // ---- states
  /// Circulation (kg/s), riser quality, exit quality of the last sub-step, the filters and the oscillator.
  double w = 12, xr = 0, xe = 0, xeBar = 0, routBar = 0, rinBar = 0, u = 1e-3, v = 0;
  bool filtInit = false;

  // ---- diagnostics of the last sub-step
  double iS = 0,
      q = 0,
      qDelivered = 0,
      qMax = 0,
      qMax0 = 0,
      fsc = 0,
      tOsc = 10,
      rhoB = 0,
      drivingHead = 0,
      inletLineDp = 0,
      outletLineDp = 0,
      dTsub = 0,
      tbMean = 0,
      wHeater = 0,
      mHeater = 0,
      mRiser = 0,
      frictionDp = 0,
      accDp = 0,
      cIn = 0,
      cOut = 0,
      cTube = 0,
      cAcc = 0;

  ThermosyphonLoop(this.geo, {ThermosyphonProps? props}) : p = props ?? ThermosyphonProps();

  double get at => geo.nTubes * math.pi * geo.tubeId * geo.tubeId / 4;
  double get ain => math.pi * geo.inletD * geo.inletD / 4;
  double get ar => math.pi * geo.riserD * geo.riserD / 4;
  double get lRiser => geo.zReturn - geo.tubeLength;
  double get amplitude => math.sqrt(u * u + v * v);

  /// Static liquid height above the bottom tubesheet (m) at [levelPct] of the sump.
  double liquidHeight(double levelPct, double hSump) => geo.z0 + levelPct.clamp(0.0, 100.0) / 100 * hSump;

  /// Subcooling of the sump liquid at the tube inlet (K).
  double subcooling(double z) => p.dTsatdP * p.rhoL * g * z;

  /// Q_max,0 = U A (T_st - T_b,mean) (W): the clean maximum used by the steam valve (PHYSICS.md 8.3.4).
  double qMax0For(double z) => math.max(0.0, geo.u * geo.area * (p.tSteam - (p.tSump + subcooling(z) / 2)));

  double _alpha(double x) {
    if (x <= 0) return 0;
    final s = math.pow(p.rhoL / p.rhoV, 1 / 3);
    return 1 / (1 + ((1 - x) / x) * (p.rhoV / p.rhoL) * s);
  }

  double _rhoTp(double x) {
    final a = _alpha(x);
    return a * p.rhoV + (1 - a) * p.rhoL;
  }

  double _vh(double x) => x / p.rhoV + (1 - x) / p.rhoL;

  /// Starts the loop (PHYSICS.md 13.1 step 7): W0 = Q / (0.25 lambda), x_r = x_e = 0, u = 1e-3, v = 0, filters from the
  /// first sub-step.
  void init(double qRequest) {
    w = math.max(qRequest, 1.0) / (0.25 * p.lambdaMass);
    xr = 0;
    xe = 0;
    u = 1e-3;
    v = 0;
    xeBar = 0;
    routBar = 0;
    rinBar = 0;
    filtInit = false;
  }

  /// One sub-step of [dt] seconds. [qRequest] is the steam valve's duty request (W), [levelPct] the sump level (%),
  /// [hSump] the sump height (m), [inletOpPct] the inlet valve opening (%), [rfK] the reboiler fouling resistance
  /// (K/W, per exchanger), [fFlooded] the flooded tube fraction, [kInAdd] and [kOutAdd] the F17/F18 loss increments.
  void substep(double dt, double qRequest, double levelPct, double hSump, double inletOpPct,
      {double rfK = 0, double fFlooded = 0, double kInAdd = 0, double kOutAdd = 0}) {
    final z = liquidHeight(levelPct, hSump);
    final lr = lRiser;
    final aT = at, aIn = ain, aR = ar;
    dTsub = subcooling(z);
    tbMean = p.tSump + dTsub / 2;
    final wh = math.max(w * (1 + u), 0.3);
    wHeater = wh;
    final lam = p.lambdaMass;
    final xc = geo.xCrit;
    final q0 = (1 - fFlooded) / (1 / geo.u + geo.area * rfK) * geo.area * (p.tSteam - tbMean);
    qMax0 = math.max(0.0, geo.u * geo.area * (p.tSteam - tbMean));
    final h = wh * lam;
    final sens = wh * p.cpL * dTsub;
    double dOf(double x) => x <= xc ? 1.0 : math.max(0.35, 1 - _k * (x - xc));
    var x = (math.min(qRequest, q0) - sens) / h;
    if (x > xc) {
      final xSp = (qRequest - sens) / h;
      if (qRequest <= dOf(xSp) * q0) {
        x = xSp;
      } else {
        x = (q0 * (1 + _k * xc) - sens) / (h + _k * q0);
        if (x > xc + 0.35) x = (0.35 * q0 - sens) / h;
      }
    }
    xe = x.clamp(0.0, 1.0).toDouble();
    qMax = dOf(xe) * math.max(q0, 0.0);
    final qDry = wh * (p.cpL * dTsub + lam);
    q = math.max(0.0, math.min(qRequest, math.min(qMax, qDry)));
    fsc = q > 0 ? (math.max(w, 0.0) * p.cpL * dTsub / q).clamp(0.0, 1.0).toDouble() : 1.0;
    var sum = 0.0;
    for (var k = 0; k < 8; k++) {
      sum += _rhoTp(xe * (k + 0.5) / 8);
    }
    rhoB = sum / 8;
    mRiser = aR * lr * _rhoTp(xr);
    xr = (mRiser * xr + dt * wh * xe) / (mRiser + dt * wh);
    final rhoR = _rhoTp(xr);
    drivingHead = g * (p.rhoL * z - p.rhoL * geo.tubeLength * fsc - rhoB * geo.tubeLength * (1 - fsc) - rhoR * lr);
    final phi2 = 1 + 0.5 * xe * (p.rhoL / p.rhoV - 1);
    final re = math.max(2000.0, w.abs() * geo.tubeId / (aT * p.muL));
    final fd = 0.316 * math.pow(re, -0.25);
    final kValve = 1 / math.pow(math.max(inletOpPct, 1e-3) / 100, 2);
    cIn = (geo.kIn + kInAdd + kValve) / (2 * p.rhoL * aIn * aIn);
    cTube = fd * geo.tubeLength * (fsc + (1 - fsc) * phi2) / (geo.tubeId * 2 * p.rhoL * aT * aT);
    cAcc = (_vh(xe) - 1 / p.rhoL) / (aT * aT);
    cOut = (geo.kOut + kOutAdd) * _vh(xr) / (2 * aR * aR);
    final inertance = geo.inletLength / aIn + geo.tubeLength / aT + lr / aR;
    final f = dt / inertance;
    w = (w + f * drivingHead) / (1 + f * (cIn + cTube + cAcc + cOut) * w.abs());
    if (w < 0) w = 0;
    inletLineDp = cIn * w * w;
    outletLineDp = cOut * w * w;
    frictionDp = (cIn + cTube + cOut) * w * w;
    accDp = cAcc * w * w;
    // filters and the instability index (8.4)
    final a = filtInit ? dt / (tauF + dt) : 1.0;
    filtInit = true;
    xeBar += a * (xe - xeBar);
    routBar += a * (cOut * w * w / (0.5 * p.rhoL * g * z) - routBar);
    rinBar += a * (cIn * w * w / (p.rhoL * g * z) - rinBar);
    iS = math.max(xeBar / 0.30, routBar) / (1 + 3 * rinBar);
    // oscillator (8.5)
    mHeater = aT * geo.tubeLength * (p.rhoL * fsc + rhoB * (1 - fsc));
    tOsc = 2 * (mHeater + mRiser) / math.max(w, 0.3);
    final om = 2 * math.pi / tOsc;
    final sig = (iS - 1) / tauS;
    final kap = (math.max(sig, 0.0) + 1 / tauS) / (aSat * aSat);
    qDelivered = q * (1 + u);
    final c = math.cos(om * dt), s = math.sin(om * dt);
    var un = u * c - v * s, vn = u * s + v * c;
    final gr = math.exp((sig - kap * (u * u + v * v)) * dt);
    un *= gr;
    vn *= gr;
    final r = math.sqrt(un * un + vn * vn);
    if (sig > 0) {
      if (r < 1e-3) {
        if (r == 0) {
          un = 1e-3;
          vn = 0;
        } else {
          un *= 1e-3 / r;
          vn *= 1e-3 / r;
        }
      }
    } else if (r < 1e-12) {
      un = 0;
      vn = 0;
    }
    u = un;
    v = vn;
  }

  Map<String, Object?> toJson() => {
        'w': w,
        'xr': xr,
        'xe': xe,
        'xeBar': xeBar,
        'routBar': routBar,
        'rinBar': rinBar,
        'u': u,
        'v': v,
        'filtInit': filtInit,
        'iS': iS,
        'q': q,
        'qDelivered': qDelivered,
        'qMax': qMax,
        'qMax0': qMax0,
        'fsc': fsc,
        'tOsc': tOsc,
        'rhoB': rhoB,
        'drivingHead': drivingHead,
        'inletLineDp': inletLineDp,
        'outletLineDp': outletLineDp,
        'dTsub': dTsub,
        'tbMean': tbMean,
        'wHeater': wHeater,
        'mHeater': mHeater,
        'mRiser': mRiser,
        'frictionDp': frictionDp,
        'accDp': accDp,
        'cIn': cIn,
        'cOut': cOut,
        'cTube': cTube,
        'cAcc': cAcc,
      };

  void loadJson(Map<String, Object?> j) {
    double d(String k) => (j[k]! as num).toDouble();
    w = d('w');
    xr = d('xr');
    xe = d('xe');
    xeBar = d('xeBar');
    routBar = d('routBar');
    rinBar = d('rinBar');
    u = d('u');
    v = d('v');
    filtInit = j['filtInit']! as bool;
    iS = d('iS');
    q = d('q');
    qDelivered = d('qDelivered');
    qMax = d('qMax');
    qMax0 = d('qMax0');
    fsc = d('fsc');
    tOsc = d('tOsc');
    rhoB = d('rhoB');
    drivingHead = d('drivingHead');
    inletLineDp = d('inletLineDp');
    outletLineDp = d('outletLineDp');
    dTsub = d('dTsub');
    tbMean = d('tbMean');
    wHeater = d('wHeater');
    mHeater = d('mHeater');
    mRiser = d('mRiser');
    frictionDp = d('frictionDp');
    accDp = d('accDp');
    cIn = d('cIn');
    cOut = d('cOut');
    cTube = d('cTube');
    cAcc = d('cAcc');
  }
}
