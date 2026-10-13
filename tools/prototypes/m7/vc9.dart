// VC-9.1/9.2 FUG, VC-9.4 DePriester spot values, VC-9.5 bubble/dew points, preset α (§2.3).
import 'dart:math';
import 'hc.dart';

const zDebut = [0.05, 0.15, 0.25, 0.20, 0.20, 0.15];
const zDeprop = [0.30, 0.20, 0.25, 0.10, 0.10, 0.05];
const aDebut = [5.180, 2.628, 2.041, 1.000, 0.843, 0.385];
const aDeprop = [2.172, 1.000, 0.747, 0.378, 0.330, 0.157];

void fugCase(String label, List<double> a, List<double> z, int lk, int hk, double rl, double rh) {
  final g = Fug(a, z, lk, hk, rl, rh);
  print('$label: Nmin ${f4(g.nMin)} theta ${f4(g.theta, 5)} Rmin ${f4(g.rMin)} R ${f4(g.r)} X ${f4(g.xX, 5)} Y ${f4(g.yY, 5)} N ${f4(g.n, 3)} NR/NS ${f4(g.nrNs)} D ${f4(g.dTot)}');
  for (var i = 0; i < z.length; i++) {
    print('   ${six[i].id.padRight(10)} d ${f4(g.d[i])} b ${f4(g.b[i])} xD ${f4(g.xd[i], 5)} xB ${f4(g.xb[i], 5)}');
  }
}

double fToK(double f) => (f - 32) / 1.8 + 273.15;

void main() {
  fugCase('VC-9.1 debut', aDebut, zDebut, 2, 3, 0.98, 0.98);
  fugCase('VC-9.2 deprop', aDeprop, zDeprop, 0, 1, 0.99, 0.95);

  // VC-9.4 spot values
  final psia = 6894.757;
  final spots = [
    [nbutane, 150.0, 100.0, 1.0648], [isopentane, 200.0, 100.0, 0.8922], [npentane, 200.0, 100.0, 0.7572],
    [propane, 100.0, 200.0, 1.0073], [isobutane, 100.0, 100.0, 0.7826], [nhexane, 250.0, 100.0, 0.6301],
  ];
  for (final s in spots) {
    final c = s[0] as Comp;
    final t = fToK(s[1] as double), p = (s[2] as double) * psia;
    final kd = exp(lnKdp(c, t, p)), kr = exp(lnPsatLK(c, t) - log(p));
    print('VC-9.4 ${c.id} ${s[1]}F ${s[2]}psia: DP ${f4(kd)} (doc ${s[3]})  LK-Raoult ${f4(kr, 3)}');
  }

  // VC-9.5 bubble/dew, preset alpha
  for (final cas in [
    ['debut', zDebut, aDebut, 2, 3, 0.98, 0.98, 100.0],
    ['deprop', zDeprop, aDeprop, 0, 1, 0.99, 0.95, 250.0],
  ]) {
    final z = cas[1] as List<double>, a = cas[2] as List<double>;
    final g = Fug(a, z, cas[3] as int, cas[4] as int, cas[5] as double, cas[6] as double);
    final p = (cas[7] as double) * psia;
    for (final model in [2, 1]) {
      final th = Thermo(six, model);
      final tf = th.bubbleT(z, p), td = th.dewT(g.xd, p), tbb = th.bubbleT(g.xb, p);
      final tdb = th.bubbleT(g.xd, p);
      final hk = cas[4] as int;
      final at = [for (var i = 0; i < 6; i++) th.k(i, td, p) / th.k(hk, td, p)];
      final ab = [for (var i = 0; i < 6; i++) th.k(i, tbb, p) / th.k(hk, tbb, p)];
      final am = [for (var i = 0; i < 6; i++) sqrt(at[i] * ab[i])];
      print('VC-9.5 ${cas[0]} model $model: feed bubble ${f4(tf - 273.15, 2)} C, D dew ${f4(td - 273.15, 2)} C (D bubble ${f4(tdb - 273.15, 2)}), B bubble ${f4(tbb - 273.15, 2)} C');
      print('   alpha top ${at.map((v) => f4(v, 3)).join(', ')}');
      print('   alpha bot ${ab.map((v) => f4(v, 3)).join(', ')}');
      print('   alpha geo ${am.map((v) => f4(v, 3)).join(', ')}');
      // FUG with the recomputed alpha
      final g2 = Fug(am, z, cas[3] as int, hk, cas[5] as double, cas[6] as double);
      print('   FUG with these alpha: Nmin ${f4(g2.nMin)} Rmin ${f4(g2.rMin)} N ${f4(g2.n, 3)} D ${f4(g2.dTot)}');
    }
  }
}
