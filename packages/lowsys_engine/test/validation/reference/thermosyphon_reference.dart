// Independent reference for the thermosyphon loop (PHYSICS.md 8.3.1-8.3.3, M6 excerpt), written by the validator from
// the spec text only (not from lib/src/model/thermosyphon.dart). Pure Dart, no engine imports.
import 'dart:math' as math;

class TsRefInputs {
  final double rhoL, rhoV, lambda, cpL, muL, dTdP, tSump, tSt;
  const TsRefInputs({
    this.rhoL = 780,
    this.rhoV = 2.93,
    this.lambda = 361e3,
    this.cpL = 1950,
    this.muL = 0.27e-3,
    this.dTdP = 3.63e-4,
    this.tSump = 383.54,
    this.tSt = 421.25,
  });
}

class TsRefGeometry {
  final double nT, di, lt, area, u, z0, hSump, zRet, dr, dIn, lIn, kIn, kOut, xc;
  const TsRefGeometry({
    this.nT = 200,
    this.di = 0.0212,
    this.lt = 3.0,
    this.area = 47.6,
    this.u = 1000,
    this.z0 = 1.2,
    this.hSump = 2.4,
    this.zRet = 4.5,
    this.dr = 0.30,
    this.dIn = 0.20,
    this.lIn = 6.0,
    this.kIn = 4,
    this.kOut = 3,
    this.xc = 0.30,
  });
}

class TsRefLoop {
  static const g = 9.80665, tauF = 30.0, tauS = 20.0, aSat = 0.30, k = 0.65 / 0.35;
  final TsRefInputs p;
  final TsRefGeometry geo;
  double w, xr = 0, xe = 0, xeBar = 0, rOut = 0, rIn = 0, u = 1e-3, v = 0;
  bool first = true;
  // diagnostics of the last sub-step
  double q = 0, qDel = 0, iS = 0, tOsc = 0, fsc = 0, dTsub = 0, q0 = 0, qMax = 0, dpIn = 0, dpOut = 0, uUsed = 0;

  TsRefLoop({this.p = const TsRefInputs(), this.geo = const TsRefGeometry(), this.w = 12});

  double get aT => geo.nT * math.pi * geo.di * geo.di / 4;
  double get aIn => math.pi * geo.dIn * geo.dIn / 4;
  double get aR => math.pi * geo.dr * geo.dr / 4;
  double get lR => geo.zRet - geo.lt;
  double get amp => math.sqrt(u * u + v * v);

  double rhoTp(double x) {
    if (x <= 0) return p.rhoL;
    final sz = math.pow(p.rhoL / p.rhoV, 1 / 3).toDouble();
    final a = 1 / (1 + ((1 - x) / x) * (p.rhoV / p.rhoL) * sz);
    return a * p.rhoV + (1 - a) * p.rhoL;
  }

  double vh(double x) => x / p.rhoV + (1 - x) / p.rhoL;
  double dFun(double x) => x <= geo.xc ? 1.0 : math.max(0.35, 1 - k * (x - geo.xc));

  void step(double d, double qSp, double level, double op, {double rf = 0, double fFl = 0}) {
    final z = geo.z0 + level / 100 * geo.hSump;
    dTsub = p.dTdP * p.rhoL * g * z;
    final tb = p.tSump + dTsub / 2;
    final wh = math.max(w * (1 + u), 0.3);
    q0 = (1 - fFl) / (1 / geo.u + geo.area * rf) * geo.area * (p.tSt - tb);
    final h = wh * p.lambda, s = wh * p.cpL * dTsub;
    var x = (math.min(qSp, q0) - s) / h;
    if (x > geo.xc) {
      final xsp = (qSp - s) / h;
      if (qSp <= dFun(xsp) * q0) {
        x = xsp;
      } else {
        x = (q0 * (1 + k * geo.xc) - s) / (h + k * q0);
        if (x > geo.xc + 0.35) x = (0.35 * q0 - s) / h;
      }
    }
    xe = x.clamp(0.0, 1.0);
    qMax = dFun(xe) * q0;
    q = math.min(qSp, math.min(qMax, wh * (p.cpL * dTsub + p.lambda)));
    fsc = q == 0 ? 1.0 : (w * p.cpL * dTsub / q).clamp(0.0, 1.0);
    var rhoB = 0.0;
    for (var i = 0; i < 8; i++) {
      rhoB += rhoTp(xe * (i + 0.5) / 8) / 8;
    }
    final mR = aR * lR * rhoTp(xr);
    xr = (mR * xr + d * wh * xe) / (mR + d * wh);
    final dp = g * (p.rhoL * z - p.rhoL * geo.lt * fsc - rhoB * geo.lt * (1 - fsc) - rhoTp(xr) * lR);
    final re = math.max(2000.0, w.abs() * geo.di / (aT * p.muL));
    final fD = 0.316 * math.pow(re, -0.25);
    final phi2 = 1 + 0.5 * xe * (p.rhoL / p.rhoV - 1);
    final kV = 1 / math.pow(op / 100, 2);
    final cIn = (geo.kIn + kV) / (2 * p.rhoL * aIn * aIn);
    final cTube = fD * geo.lt * (fsc + (1 - fsc) * phi2) / (geo.di * 2 * p.rhoL * aT * aT);
    final cAcc = (vh(xe) - 1 / p.rhoL) / (aT * aT);
    final cOut = geo.kOut * vh(xr) / (2 * aR * aR);
    final inert = geo.lIn / aIn + geo.lt / aT + lR / aR;
    w = (w + d / inert * dp) / (1 + d / inert * (cIn + cTube + cAcc + cOut) * w.abs());
    if (w < 0) w = 0;
    dpIn = cIn * w * w;
    dpOut = cOut * w * w;
    final a = first ? 1.0 : d / (tauF + d);
    first = false;
    xeBar += a * (xe - xeBar);
    rOut += a * (cOut * w * w / (0.5 * p.rhoL * g * z) - rOut);
    rIn += a * (cIn * w * w / (p.rhoL * g * z) - rIn);
    iS = math.max(xeBar / 0.30, rOut) / (1 + 3 * rIn);
    uUsed = u;
    qDel = q * (1 + u);
    final mH = aT * geo.lt * (p.rhoL * fsc + rhoB * (1 - fsc));
    tOsc = 2 * (mH + mR) / math.max(w, 0.3);
    final om = 2 * math.pi / tOsc, sig = (iS - 1) / tauS;
    final kap = (math.max(sig, 0.0) + 1 / tauS) / (aSat * aSat);
    final gr = math.exp((sig - kap * (u * u + v * v)) * d);
    final c = math.cos(om * d), sn = math.sin(om * d);
    var un = (u * c - v * sn) * gr, vn = (u * sn + v * c) * gr;
    final r = math.sqrt(un * un + vn * vn);
    if (sig > 0 && r < 1e-3) {
      if (r == 0) {
        un = 1e-3;
        vn = 0;
      } else {
        un *= 1e-3 / r;
        vn *= 1e-3 / r;
      }
    } else if (sig <= 0 && r < 1e-12) {
      un = 0;
      vn = 0;
    }
    u = un;
    v = vn;
  }
}

/// Statistics of the last [window] s of a fixed-input run (VALIDATION.md VC-14.1 reporting rules).
class TsStats {
  final double wMean, wHalf, xeMean, xeHalf, qMean, qHalf, qSteam, iS, amp, period, uMean;
  TsStats(this.wMean, this.wHalf, this.xeMean, this.xeHalf, this.qMean, this.qHalf, this.qSteam, this.iS, this.amp,
      this.period, this.uMean);
  @override
  String toString() => 'W ${wMean.toStringAsFixed(3)}±${wHalf.toStringAsFixed(3)} x_e ${xeMean.toStringAsFixed(4)}'
      '±${xeHalf.toStringAsFixed(4)} Q ${(qMean / 1e3).toStringAsFixed(1)}±${(qHalf / 1e3).toStringAsFixed(1)} '
      '(${(qSteam / 1e3).toStringAsFixed(1)}) I_s ${iS.toStringAsFixed(3)} amp ${amp.toStringAsExponential(3)} '
      'period ${period.toStringAsFixed(2)} u_mean ${uMean.toStringAsExponential(2)}';
}

/// Accumulates per-sub-step samples (time, W, x_e, delivered Q, steam Q, I_s, amplitude, u used, T_osc).
class TsAcc {
  final List<double> t = [], w = [], xe = [], qd = [], qs = [], iS = [], amp = [], u = [], tOsc = [];
  void add(double time, double wv, double xev, double qdv, double qsv, double isv, double ampv, double uv, double to) {
    t.add(time);
    w.add(wv);
    xe.add(xev);
    qd.add(qdv);
    qs.add(qsv);
    iS.add(isv);
    amp.add(ampv);
    u.add(uv);
    tOsc.add(to);
  }

  static double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  static double _half(List<double> v) => (v.reduce(math.max) - v.reduce(math.min)) / 2;

  TsStats stats({required bool oscillating}) {
    double period;
    if (oscillating) {
      final c = <double>[];
      for (var i = 1; i < u.length; i++) {
        if (u[i - 1] < 0 && u[i] >= 0) c.add(t[i]);
      }
      period = c.length < 2 ? double.nan : (c.last - c.first) / (c.length - 1);
    } else {
      period = _mean(tOsc);
    }
    return TsStats(_mean(w), _half(w), _mean(xe), _half(xe), _mean(qd), _half(qd), _mean(qs), _mean(iS), _mean(amp),
        period, _mean(u));
  }
}
