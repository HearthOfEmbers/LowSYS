// Thermosyphon loop prototype, PHYSICS.md §8.3 as written (M6 readiness pass).
import 'dart:math';

const g = 9.80665;
bool exact = true, floorUnstableOnly = true;

class Geo {
  double nt = 200, di = 0.0212, lt = 3.0, area = 47.6, u = 1000;
  double z0 = 1.2, hs = 2.4, zret = 4.5, din = 0.20, lin = 6.0, dr = 0.30;
  double kin = 4, kout = 3, xc = 0.30;
}

class Props {
  double rhoL = 780, rhoV = 2.93, lam = 361e3, cp = 1950, mu = 0.27e-3;
  double dTdP = 3.63e-4, tSump = 383.54, tSt = 421.25;
}

class Loop {
  final Geo geo;
  final Props p;
  double w, xr = 0, u, v = 0, xe = 0;
  double xeBar = 0, routBar = 0, rinBar = 0, iS = 0;
  bool filtInit = false;
  // diagnostics of the last sub-step
  double q = 0, qDel = 0, qMax = 0, fsc = 0, tOsc = 0, rhoB = 0, dpDrive = 0;
  double rf = 0, fFlood = 0;
  Loop(this.geo, this.p, {this.w = 12, this.u = 1e-3});

  double alpha(double x) {
    if (x <= 0) return 0;
    final s = pow(p.rhoL / p.rhoV, 1 / 3);
    return 1 / (1 + ((1 - x) / x) * (p.rhoV / p.rhoL) * s);
  }

  double rhoTp(double x) {
    final a = alpha(x);
    return a * p.rhoV + (1 - a) * p.rhoL;
  }

  double vh(double x) => x / p.rhoV + (1 - x) / p.rhoL;

  void step(double dlt, double qSp, double level, double op) {
    final at = geo.nt * pi * geo.di * geo.di / 4;
    final ain = pi * geo.din * geo.din / 4;
    final ar = pi * geo.dr * geo.dr / 4;
    final lr = geo.zret - geo.lt;
    final z = geo.z0 + level / 100 * geo.hs;
    final dTsub = p.dTdP * p.rhoL * g * z;
    final tbm = p.tSump + dTsub / 2;
    final wh = max(w * (1 + u), 0.3);
    if (exact) {
      final q0 = (1 - fFlood) / (1 / geo.u + rf) * geo.area * (p.tSt - tbm);
      final h = wh * p.lam, sens = wh * p.cp * dTsub;
      const k = 0.65 / 0.35;
      var x = (min(qSp, q0) - sens) / h;
      if (x > geo.xc) {
        final dSp = 1 - k * (((qSp - sens) / h) - geo.xc);
        if (qSp <= q0 * max(0.35, dSp)) {
          x = (qSp - sens) / h;
        } else {
          x = (q0 * (1 + k * geo.xc) - sens) / (h + q0 * k);
          if (x > geo.xc + 0.35) x = (0.35 * q0 - sens) / h; // D floor (needs q0*0.35 < qSp, true here)
        }
      }
      xe = max(0.0, x);
      final qDry = wh * (p.cp * dTsub + p.lam);
      final d = xe <= geo.xc ? 1.0 : max(0.35, 1 - k * (xe - geo.xc));
      qMax = d * q0;
      q = min(qSp, qMax);
      if (xe > 1) { xe = 1; q = min(q, qDry); }
    } else
    for (var it = 0; it < 3; it++) {
      final d = xe <= geo.xc ? 1.0 : max(0.35, 1 - 0.65 * (xe - geo.xc) / 0.35);
      final ueff = d * (1 - fFlood) / (1 / geo.u + rf);
      qMax = ueff * geo.area * (p.tSt - tbm);
      q = min(qSp, qMax);
      xe = max(0.0, (q - wh * p.cp * dTsub) / (wh * p.lam));
    }
    fsc = q > 0 ? min(1.0, max(0.0, w) * p.cp * dTsub / q) : 1.0;
    var sum = 0.0;
    for (var k = 0; k < 8; k++) {
      sum += rhoTp(xe * (k + 0.5) / 8);
    }
    rhoB = sum / 8;
    final mr = ar * lr * rhoTp(xr);
    xr = (mr * xr + dlt * wh * xe) / (mr + dlt * wh);
    final rhoR = rhoTp(xr);
    dpDrive = g * (p.rhoL * z - p.rhoL * geo.lt * fsc - rhoB * geo.lt * (1 - fsc) - rhoR * lr);
    final phi2 = 1 + 0.5 * xe * (p.rhoL / p.rhoV - 1);
    final re = max(2000.0, w.abs() * geo.di / (at * p.mu));
    final fd = 0.316 * pow(re, -0.25);
    final kv = 1 / pow(op / 100, 2);
    final cin = (geo.kin + kv) / (2 * p.rhoL * ain * ain);
    final ctube = fd * geo.lt * (fsc + (1 - fsc) * phi2) / (geo.di * 2 * p.rhoL * at * at);
    final cacc = (vh(xe) - 1 / p.rhoL) / (at * at);
    final cout = geo.kout * vh(xr) / (2 * ar * ar);
    final inert = geo.lin / ain + geo.lt / at + lr / ar;
    w = (w + dlt / inert * dpDrive) / (1 + dlt / inert * (cin + ctube + cacc + cout) * w.abs());
    if (w < 0) w = 0;
    // filters
    final a = filtInit ? dlt / (30 + dlt) : 1.0;
    filtInit = true;
    xeBar += a * (xe - xeBar);
    routBar += a * (cout * w * w / (0.5 * p.rhoL * g * z) - routBar);
    rinBar += a * (cin * w * w / (p.rhoL * g * z) - rinBar);
    iS = max(xeBar / 0.30, routBar) / (1 + 3 * rinBar);
    // oscillator
    final mh = at * geo.lt * (p.rhoL * fsc + rhoB * (1 - fsc));
    tOsc = 2 * (mh + mr) / max(w, 0.3);
    final om = 2 * pi / tOsc;
    const tauS = 20.0, aSat = 0.30;
    final sig = (iS - 1) / tauS;
    final kap = (max(sig, 0) + 1 / tauS) / (aSat * aSat);
    qDel = q * (1 + u);
    final c = cos(om * dlt), s = sin(om * dlt);
    var un = u * c - v * s, vn = u * s + v * c;
    final f = exp((sig - kap * (u * u + v * v)) * dlt);
    un *= f;
    vn *= f;
    final r = sqrt(un * un + vn * vn);
    if (floorUnstableOnly && sig <= 0) {
      if (r < 1e-12) { un = 0; vn = 0; }
    } else if (r < 1e-3) {
      if (r == 0) {
        un = 1e-3;
        vn = 0;
      } else {
        un *= 1e-3 / r;
        vn *= 1e-3 / r;
      }
    }
    u = un;
    v = vn;
  }
}

class Stat {
  double sum = 0, mn = double.infinity, mx = -double.infinity;
  int n = 0;
  void add(double x) {
    sum += x;
    n++;
    mn = min(mn, x);
    mx = max(mx, x);
  }

  double get mean => sum / n;
  double get half => (mx - mn) / 2;
  double get mid => (mx + mn) / 2;
}

String f(double x, [int d = 3]) => x.toStringAsFixed(d);

void run(String label, {double qSp = 1300e3, double level = 75, double op = 100, double kout = 3, double kin = 4, double rf = 0, double fFlood = 0, double dlt = 0.1}) {
  final geo = Geo()
    ..kout = kout
    ..kin = kin;
  final lp = Loop(geo, Props())
    ..rf = rf
    ..fFlood = fFlood;
  final n = (1200 / dlt).round();
  final nAvg = (300 / dlt).round();
  final sw = Stat(), sx = Stat(), sq = Stat(), si = Stat(), sa = Stat(), st = Stat(), sqm = Stat();
  for (var i = 0; i < n; i++) {
    lp.step(dlt, qSp, level, op);
    if (i >= n - nAvg) {
      sw.add(lp.w);
      sx.add(lp.xe);
      sq.add(lp.qDel);
      si.add(lp.iS);
      sa.add(sqrt(lp.u * lp.u + lp.v * lp.v));
      st.add(lp.tOsc);
      sqm.add(lp.qMax);
    }
  }
  print('$label | mid W ${f(sw.mid,2)} xe ${f(sx.mid)} Q ${f(sq.mid/1e3,0)} || W ${f(sw.mean, 2)} ± ${f(sw.half, 2)} | xe ${f(sx.mean)} ± ${f(sx.half)} | Q ${f(sq.mean / 1e3, 0)} ± ${f(sq.half / 1e3, 0)} (Qmax ${f(sqm.mean / 1e3, 0)}) | Is ${f(si.mean, 2)} | amp ${f(sa.mean)} | T ${f(st.mean, 1)}');
}

void main(List<String> args) {
  run('1300 90 100', level: 90);
  run('1300 75 100', level: 75);
  run('1300 75 16 ', level: 75, op: 16);
  run('1300 50 100', level: 50);
  run('1300 30 100', level: 30);
  run('1300 15 100', level: 15);
  run('1300 15 16 ', level: 15, op: 16);
  run('1600 75 100', qSp: 1600e3, level: 75);
  run('1600 30 100', qSp: 1600e3, level: 30);
  run('1300 75 Kout20', kout: 20);
  run('1300 75 Rf4e-4', rf: 4e-4);
}
