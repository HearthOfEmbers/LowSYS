// Solver self-checks (VC-4.1 B-T, component closure) and a few extra reference values.
import 'hc.dart';
import 'refs.dart' show debut, deprop, solve, imp;
import 'vc9.dart' show zDebut, aDebut;

void main() {
  // VC-4.1: B-T Tier 1, 20 trays, feed 10, z 0.5, L0 100, VB 150, E 0.7, alpha 2.5 -> xD 0.981183
  final bt = [six[0], six[1]]; // components only carry data; alpha drives Tier 1
  final c = Column(Thermo(bt, 0, [2.5, 1.0]), 20, 10, molps(100), [0.5, 0.5], 101325, 0.7);
  c.solveLV(molps(100), molps(150));
  print('VC-4.1 check: xD ${c.xD[0].toStringAsFixed(6)} xB ${c.xB[0].toStringAsFixed(6)} (doc 0.981183 / 0.018817)');
  // closure on the debutanizer default
  final d = solve(debut, 2);
  var worst = 0.0;
  for (var i = 0; i < 6; i++) {
    final r = (d.f * d.z[i] - d.d * d.xD[i] - d.b * d.xB[i]).abs() / (d.f * d.z[i]);
    if (r > worst) worst = r;
  }
  print('debut T3 component closure (max rel) ${worst.toStringAsExponential(2)}');
  // VC-9.3 Hengstebeck values (Tier 1, E 1, 22/12)
  final t1 = Column(Thermo(six, 0, aDebut), 22, 12, molps(100), zDebut, 100 * 6894.757, 1.0);
  t1.solveLV(molps(76.39), molps(121.33));
  double xp(List<double> x) => x[2] / (x[2] + x[3]);
  print("VC-9.3 Hengstebeck: xD' ${f4(xp(t1.xD), 5)} xB' ${f4(xp(t1.xB), 5)} x' tray 12 ${f4(xp(t1.x[12]), 5)} y' tray 12 ${f4(t1.y[12][2] / (t1.y[12][2] + t1.y[12][3]), 5)}");
  // F12 at the top of the drill range
  final q0 = d.qr;
  for (final s in [0.55, 0.58, 0.62]) {
    final cap = (1 - s) * 2 * debut.l0;
    final c12 = solve(debut, 2, l0: cap, qr: q0);
    print('F12 s $s cap ${f4(cap, 2)}: D ${f4(kmolh(c12.d), 2)} ${imp(c12, debut)} T1 ${f4(c12.t[1] - 273.15, 2)} rHK ${f4(c12.recB(3))}');
  }
  // deprop default impurity and the deprop 22-tray E = 1 FUG-design column in Tier 3
  final dp = solve(deprop, 2);
  print('deprop default ${imp(dp, deprop)}');
  final dpe = solve(deprop, 2, e: 1.0, nT: 20, nf: 8);
  print('deprop T3 E1 20/8: rLK ${f4(dpe.recD(0))} rHK ${f4(dpe.recB(1))}');
}
