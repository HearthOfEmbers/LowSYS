// Checks of VC-9.5 dew/bubble points without the 700 °R clamp, and with rounded compositions.
import 'hc.dart';
import 'vc9.dart' show zDebut, zDeprop, aDebut, aDeprop;

void main() {
  const psia = 6894.757;
  final th = Thermo(six, 2);
  final gd = Fug(aDebut, zDebut, 2, 3, 0.98, 0.98);
  final gp = Fug(aDeprop, zDeprop, 0, 1, 0.99, 0.95);
  for (final c in [
    ['debut', gd, 100.0], ['deprop', gp, 250.0]
  ]) {
    final g = c[1] as Fug, p = (c[2] as double) * psia;
    final xdR = [for (final v in g.xd) double.parse(v.toStringAsFixed(5))];
    final xbR = [for (final v in g.xb) double.parse(v.toStringAsFixed(5))];
    dpOutOfRange = false;
    final td = th.dewT(g.xd, p), tb = th.bubbleT(g.xb, p, 380);
    final oor = dpOutOfRange;
    print('${c[0]}: D dew ${f4(td - 273.15, 3)} (rounded x ${f4(th.dewT(xdR, p) - 273.15, 3)}), '
        'B bubble ${f4(tb - 273.15, 3)} (rounded ${f4(th.bubbleT(xbR, p, 380) - 273.15, 3)}) T_R(B) ${f4(1.8 * tb, 1)} outOfRange=$oor');
  }
}
