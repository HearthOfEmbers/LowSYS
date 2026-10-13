// M7 reference values: preset operating points (T3, E 0.7), utility sizing, tier switches, G13 and H6
// steady states, Hengstebeck pseudo-binary values. Run: dart run refs.dart
import 'dart:math';
import 'hc.dart';
import 'col.dart' show psia, tSt, tCw, mCwMax, cpW, rep, liveFug, fugLine;
import 'vc9.dart' show zDebut, zDeprop, aDebut, aDeprop;

class Pre {
  final String id; final List<double> z, a; final double pPsia, l0, d; final int nT, nf, lk, hk;
  const Pre(this.id, this.z, this.a, this.pPsia, this.nT, this.nf, this.l0, this.d, this.lk, this.hk);
  double get p => pPsia * psia;
}

const debut = Pre('debut', zDebut, aDebut, 100, 32, 16, 76.4, 44.9437, 2, 3);
const deprop = Pre('deprop', zDeprop, aDeprop, 250, 28, 11, 66.1, 30.7771, 0, 1);
final f = molps(100);

double heavyD(Column c, int hk) { var s = 0.0; for (var i = hk; i < c.th.n; i++) s += c.xD[i]; return s; }
double lightB(Column c, int lk) { var s = 0.0; for (var i = 0; i <= lk; i++) s += c.xB[i]; return s; }
String imp(Column c, Pre p) => 'xDHeavy ${f4(heavyD(c, p.hk), 5)} xBLight ${f4(lightB(c, p.lk), 5)}';

Column solve(Pre p, int model, {double e = 0.7, double? l0, double? d, double? qr, List<double>? z, double? fF, int? nT, int? nf}) {
  final th = Thermo(six, model, model == 0 ? p.a : null);
  final c = Column(th, nT ?? p.nT, nf ?? p.nf, fF ?? f, z ?? p.z, p.p, e);
  if (qr != null) {
    c.solveLQ(molps(l0 ?? p.l0), qr, molps(d ?? p.d));
  } else {
    c.solveLD(molps(l0 ?? p.l0), molps(d ?? p.d));
  }
  return c;
}

void main() {
  for (final p in [debut, deprop]) {
    print('================ ${p.id}: ${p.nT} trays, feed ${p.nf}, E 0.7, P ${f4(p.p / 1e5, 3)} bar');
    final c3 = solve(p, 2);
    rep('${p.id} T3 default (L0, D)', c3, p.lk, p.hk);
    print('   ${imp(c3, p)}  Tfeed ${f4(c3.tF - 273.15, 3)} C');
    final m = 0.5 * mCwMax;
    final ua = c3.qc / ((c3.t[0] - tCw) - c3.qc / (2 * m * cpW));
    final tb = c3.t[c3.nT + 1];
    final uaR = c3.qr / (0.6 * (tSt - tb));
    print('   UA_clean ${f4(ua / 1e3, 2)} kW/K, CW out at 50 %: ${f4(30 + c3.qc / (m * cpW), 2)} C; at 100 % CW Q_C max '
        '${f4(ua * (c3.t[0] - tCw) / (1 + ua / (2 * mCwMax * cpW)) / 1e3, 1)} kW; UA_R,clean ${f4(uaR / 1e3, 2)} kW/K; Q_max,0 ${f4(uaR * (tSt - tb) / 1e3, 1)} kW');
    // dT_bub/dP of the design distillate
    final th3 = Thermo(six, 2), th2 = Thermo(six, 1);
    final dp = 1000.0;
    final s3 = (th3.bubbleT(c3.xD, p.p + dp) - th3.bubbleT(c3.xD, p.p - dp)) / (2 * dp) * 1000;
    final s2 = (th2.bubbleT(c3.xD, p.p + dp) - th2.bubbleT(c3.xD, p.p - dp)) / (2 * dp) * 1000;
    print('   dT_bub/dP of x_D at P: T3 ${f4(s3, 4)} K/kPa, T2 ${f4(s2, 4)} K/kPa; relief 1.5 P = ${f4(1.5 * p.p / 1e5, 2)} bar(a)');
    print('   T profile: top ${f4(c3.t[1] - 273.15, 2)}, feed ${f4(c3.t[p.nf] - 273.15, 2)}, tray N ${f4(c3.t[p.nT] - 273.15, 2)}, reb ${f4(tb - 273.15, 2)} C; V1 ${f4(kmolh(c3.v[1]), 2)} VB ${f4(kmolh(c3.v[p.nT + 1]), 2)}');
    // Hengstebeck
    double xp(List<double> x) => x[p.lk] / (x[p.lk] + x[p.hk]);
    print('   Hengstebeck: zF\' ${f4(p.z[p.lk] / (p.z[p.lk] + p.z[p.hk]), 5)} xD\' ${f4(xp(c3.xD), 5)} xB\' ${f4(xp(c3.xB), 5)}'
        ' feed-stage x\' ${f4(xp(c3.x[p.nf]), 5)} alpha\' top ${f4(th3.k(p.lk, c3.t[1], p.p) / th3.k(p.hk, c3.t[1], p.p), 4)} bottom ${f4(th3.k(p.lk, tb, p.p) / th3.k(p.hk, tb, p.p), 4)}');
    fugLine('T3 live', liveFug(c3, p.lk, p.hk), c3);
    // tier switches at the same V1 and D (top-vapour rule): T2 with the T3 V1 -> same L0, D
    final c2 = solve(p, 1);
    rep('${p.id} T2 same L0, D', c2, p.lk, p.hk);
    final c1 = solve(p, 0);
    rep('${p.id} T1 same L0, D (V_B = ${f4(kmolh(c1.v[c1.nT + 1]), 2)})', c1, p.lk, p.hk);
    // T2 at the T3 duty
    final c2q = solve(p, 1, qr: c3.qr);
    rep('${p.id} T2 at T3 duty', c2q, p.lk, p.hk);
  }

  // ---- G13: debutanizer T3 at the sandbox configuration; reflux for 98/98 with D held
  print('================ G13');
  final g0 = solve(debut, 2);
  final fug0 = liveFug(g0, 2, 3);
  final a = [for (var i = 0; i < 6; i++) sqrt(g0.th.k(i, g0.t[1], g0.p) / g0.th.k(3, g0.t[1], g0.p) * g0.th.k(i, g0.t[33], g0.p) / g0.th.k(3, g0.t[33], g0.p))];
  final tgt = Fug(a, debut.z, 2, 3, 0.98, 0.98, rAbs: g0.l0 / g0.d);
  print('start: alpha ${a.map((v) => f4(v, 4)).join(' ')}');
  print('start FUG(targets 98/98): Nmin ${f4(tgt.nMin, 3)} theta ${f4(tgt.theta, 4)} Rmin ${f4(tgt.rMin, 4)} R ${f4(tgt.r, 4)} N ${f4(tgt.n, 2)} NR/NS ${f4(tgt.nrNs, 3)} D ${f4(tgt.dTot, 3)}');
  fugLine('start live', fug0, g0);
  double lo = 76.4, hi = 120;
  for (var it = 0; it < 40; it++) {
    final mid = 0.5 * (lo + hi);
    final c = solve(debut, 2, l0: mid);
    if (min(c.recD(2), c.recB(3)) < 0.98) { lo = mid; } else { hi = mid; }
  }
  final g1 = solve(debut, 2, l0: hi);
  rep('G13 98/98 at D held: L0 ${f4(hi, 2)} (R ${f4(hi / debut.d, 4)})', g1, 2, 3);
  fugLine('end live', liveFug(g1, 2, 3), g1);
  for (final l in [80.0, 85.0, 90.0]) {
    final c = solve(debut, 2, l0: l);
    rep('G13 hint scan L0 $l (duty follows)', c, 2, 3);
  }
  // G13 with E = 1 on 22 trays / feed 12 (VC-9.3 column) for comparison
  final ge = solve(debut, 2, e: 1.0, nT: 22, nf: 12);
  rep('T3 E1 22/12 at design L0, D', ge, 2, 3);

  // ---- H6 candidates (debut T3 default, LV control: steady state at fixed L0 and Q_R)
  print('================ H6');
  final h0 = solve(debut, 2);
  final q0 = h0.qr;
  print('base: Q_R ${f4(q0 / 1e3, 1)} kW, ${imp(h0, debut)}, rLK ${f4(h0.recD(2))} rHK ${f4(h0.recB(3))}');
  for (final s in [0.5, 0.75, 1.0]) {
    final dz = [-0.02, -0.04, 0.02, 0.04, 0.0, 0.0];
    final z = [for (var i = 0; i < 6; i++) debut.z[i] + s * dz[i]];
    final c = solve(debut, 2, z: z, qr: q0);
    print('F07 s $s z ${z.map((v) => f4(v, 3)).join(' ')} (light cut ${f4(z[0] + z[1] + z[2], 3)}): D ${f4(kmolh(c.d), 2)} ${imp(c, debut)} rLK ${f4(c.recD(2))} rHK ${f4(c.recB(3))} T1 ${f4(c.t[1] - 273.15, 2)} TB ${f4(c.t[c.nT + 1] - 273.15, 2)}');
  }
  for (final s in [0.5, 0.55, 0.6, 0.65]) {
    final cap = (1 - s) * 2 * debut.l0;
    final l = min(cap, debut.l0);
    final c = solve(debut, 2, l0: l, qr: q0);
    print('F12 s $s cap ${f4(cap, 2)} kmol/h: D ${f4(kmolh(c.d), 2)} ${imp(c, debut)} rLK ${f4(c.recD(2))} rHK ${f4(c.recB(3))} T1 ${f4(c.t[1] - 273.15, 2)} T0 ${f4(c.t[0] - 273.15, 2)}');
  }
  // planning event: feed, reflux and duty +8 %; FV-102 stuck keeps L0
  final ok = solve(debut, 2, fF: f * 1.08, l0: debut.l0 * 1.08, qr: q0 * 1.08, d: debut.d * 1.08);
  print('planning healthy: D ${f4(kmolh(ok.d), 3)} ${imp(ok, debut)}');
  final st = solve(debut, 2, fF: f * 1.08, qr: q0 * 1.08, d: debut.d * 1.08);
  print('planning + FV-102 stuck (L0 76.4): D ${f4(kmolh(st.d), 2)} ${imp(st, debut)} rLK ${f4(st.recD(2))} rHK ${f4(st.recB(3))} T1 ${f4(st.t[1] - 273.15, 2)}');
  final st2 = solve(debut, 2, fF: f * 1.05, qr: q0 * 1.05, d: debut.d * 1.05);
  print('planning +5 % + FV-102 stuck: D ${f4(kmolh(st2.d), 2)} ${imp(st2, debut)}');
}
