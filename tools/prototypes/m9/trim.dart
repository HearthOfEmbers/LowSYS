// Sensitivity of the product D86 5/95 to the TBP tail trim (0 / 0.5 / 1 vol %) at the default steady state.
import 'column.dart';
import 'crude.dart';

void main() {
  final c = Crude()..solve();
  final xs = [c.naphthaX, c.prodX(0), c.prodX(1), c.prodX(2)];
  for (final tr in [0.0, 0.1, 0.5, 1.0]) {
    final d = [for (final x in xs) productD86(x, trim: tr)];
    print('trim $tr: ${d.map((e) => '${f(e[0], 1)}/${f(e[1], 1)}/${f(e[7], 1)}/${f(e[8], 1)}').join("  ")}  gaps ${f(d[1][1] - d[0][7], 1)} ${f(d[2][1] - d[1][7], 1)} ${f(d[3][1] - d[2][7], 1)}');
  }
  for (var k = 0; k < 4; k++) print('vol shares ${["N", "K", "D", "A"][k]}: ${volShares(xs[k]).map((v) => f(100 * v, 3)).join(" ")}');
  print('residue: ${volShares(c.residueX).map((v) => f(100 * v, 3)).join(" ")}');
}

List<double> volShares(List<double> x) {
  final v = [for (var i = 0; i < 9; i++) x[i] * pcs[i].vStd];
  final s = v.reduce((a, b) => a + b);
  return [for (final e in v) e / s];
}
