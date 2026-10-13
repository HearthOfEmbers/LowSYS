// Rigorous steady states for the M7 presets: VC-9.3 (Tier 1), Tier 2 (Lee–Kesler Raoult) and Tier 3
// (DePriester) operating points, utility sizing per PHYSICS.md §7.2 / §8.2, live FUG from the column.
import 'dart:math';
import 'hc.dart';
import 'vc9.dart' show zDebut, zDeprop, aDebut, aDeprop;

const psia = 6894.757;
const tSt = 148.10 + 273.15; // 3.5 bar(g) steam
const tCw = 30.0 + 273.15, mCwMax = 41.54, cpW = 4180.0;

void rep(String label, Column c, int lk, int hk, {bool util = false}) {
  final xd = c.xD, xb = c.xB;
  var s = '$label: D ${f4(kmolh(c.d), 3)} B ${f4(kmolh(c.b), 3)} rLK ${f4(c.recD(lk))} rHK ${f4(c.recB(hk))}'
      ' xD,LK ${f4(xd[lk], 5)} xD,HK ${f4(xd[hk], 5)} xB,LK ${f4(xb[lk], 5)} xB,HK ${f4(xb[hk], 5)} it ${c.iters}';
  if (c.th.model != 0) {
    final t0s = c.t[0];
    s += '\n   T0 ${f4(t0s - 273.15, 3)} T1 ${f4(c.t[1] - 273.15, 3)} TB ${f4(c.t[c.nT + 1] - 273.15, 3)} QR ${f4(c.qr / 1e3, 1)} kW QC ${f4(c.qc / 1e3, 1)} kW'
        ' V1 ${f4(kmolh(c.v[1]), 2)} VB ${f4(kmolh(c.v[c.nT + 1]), 2)} Lbot ${f4(kmolh(c.l[c.nT]), 2)} Eres ${c.energyResidual.toStringAsExponential(1)} W';
    if (util) {
      final m = 0.5 * mCwMax;
      final ua = c.qc / ((t0s - tCw) - c.qc / (2 * m * cpW));
      final uaR = c.qr / (0.6 * (tSt - c.t[c.nT + 1]));
      s += '\n   UA_clean ${f4(ua / 1e3, 2)} kW/K (CW out ${f4(c.qc / (m * cpW) + 30, 1)} C)  UA_R,clean ${f4(uaR / 1e3, 2)} kW/K  Qmax ${f4(uaR * (tSt - c.t[c.nT + 1]) / 1e3, 1)} kW';
    }
  }
  print(s);
}

void profile(Column c, List<int> stages) {
  for (final j in stages) {
    print('   stage $j T ${c.th.model == 0 ? '-' : f4(c.t[j] - 273.15, 2)} x ${c.x[j].map((v) => v.toStringAsExponential(3)).join(' ')}'
        '${j > 0 ? ' V ${f4(kmolh(c.v[j]), 2)}' : ''} L ${j <= c.nT ? f4(kmolh(c.l[j]), 2) : '-'}');
  }
}

/// Live FUG as the panel computes it: α = sqrt(α_top α_bottom) from K at stage 1 and N+1,
/// recoveries from the column, R = L0/D, q = 1.
Fug liveFug(Column c, int lk, int hk, {List<double>? alphaT1}) {
  List<double> a;
  if (alphaT1 != null) {
    a = alphaT1;
  } else {
    final n = c.th.n, j1 = 1, jb = c.nT + 1;
    a = [for (var i = 0; i < n; i++) sqrt(c.th.k(i, c.t[j1], c.p) / c.th.k(hk, c.t[j1], c.p) * c.th.k(i, c.t[jb], c.p) / c.th.k(hk, c.t[jb], c.p))];
  }
  return Fug(a, c.z, lk, hk, c.recD(lk), c.recB(hk), rAbs: c.l0 / c.d);
}

void fugLine(String label, Fug g, Column c) {
  final nAct = c.nT * c.e + 1;
  print('   FUG[$label]: Nmin ${f4(g.nMin, 3)} theta ${f4(g.theta, 4)} Rmin ${f4(g.rMin, 4)} R ${f4(g.r, 4)} N ${f4(g.n, 2)}'
      ' NR/NS ${f4(g.nrNs, 3)} feed stage(Kirkbride) ${f4(g.n * g.nrNs / (1 + g.nrNs), 2)}; actual N·E+1 = ${f4(nAct, 2)}');
}

void main() {
  final f = molps(100);
  // ---- VC-9.3 debutanizer Tier 1
  final t1 = Thermo(six, 0, aDebut);
  for (final cfg in [[22, 12], [30, 16], [22, 8], [22, 16], [30, 12]]) {
    final c = Column(t1, cfg[0], cfg[1], f, zDebut, 100 * psia, 1.0);
    c.solveLV(molps(76.39), molps(121.33));
    rep('VC-9.3 debut T1 E1 N${cfg[0]} nf${cfg[1]}', c, 2, 3);
    if (cfg[0] == 22 && cfg[1] == 12) { fugLine('T1', liveFug(c, 2, 3, alphaT1: aDebut), c); profile(c, [0, 1, 12, 23]); }
  }
  {
    final c = Column(t1, 22, 12, f, zDebut, 100 * psia, 0.7);
    c.solveLV(molps(76.4), molps(121.3));
    rep('debut T1 E0.7 N22 nf12 (sandbox default)', c, 2, 3);
  }
  // ---- depropanizer Tier 1
  final t1p = Thermo(six, 0, aDeprop);
  for (final e in [1.0, 0.7]) {
    final c = Column(t1p, 20, 8, f, zDeprop, 250 * psia, e);
    c.solveLV(molps(66.1), molps(96.9));
    rep('deprop T1 E$e N20 nf8', c, 0, 1);
    if (e == 1.0) fugLine('T1', liveFug(c, 0, 1, alphaT1: aDeprop), c);
  }
  // ---- Tier 2 / Tier 3 operating points
  for (final pre in [
    ['debut', zDebut, 100.0, 22, 12, 76.4, 44.9437, 2, 3],
    ['deprop', zDeprop, 250.0, 20, 8, 66.1, 30.7771, 0, 1],
  ]) {
    final z = pre[1] as List<double>, p = (pre[2] as double) * psia;
    final nT = pre[3] as int, nf = pre[4] as int, l0 = molps(pre[5] as double), d = molps(pre[6] as double);
    final lk = pre[7] as int, hk = pre[8] as int;
    for (final e in [0.7, 1.0]) {
      final c2 = Column(Thermo(six, 1), nT, nf, f, z, p, e);
      c2.solveLD(l0, d);
      rep('${pre[0]} T2 E$e L0 ${pre[5]} D ${pre[6]}', c2, lk, hk, util: true);
      fugLine('T2', liveFug(c2, lk, hk), c2);
      final c3 = Column(Thermo(six, 2), nT, nf, f, z, p, e);
      c3.solveLD(l0, d);
      rep('${pre[0]} T3 E$e same L0, D', c3, lk, hk, util: true);
      fugLine('T3', liveFug(c3, lk, hk), c3);
      final c3q = Column(Thermo(six, 2), nT, nf, f, z, p, e);
      c3q.solveLQ(l0, c2.qr, d);
      rep('${pre[0]} T3 E$e same L0, T2 duty ${f4(c2.qr / 1e3, 1)} kW', c3q, lk, hk);
      if (e == 0.7) profile(c3q, [0, 1, nf, nT, nT + 1]);
    }
  }
}
