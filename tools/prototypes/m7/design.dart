// Sandbox tray counts at E = 0.7 (FUG N / 0.7), feed-tray scan, and the G13 reflux needed for 98/98 in Tier 3.
import 'dart:math';
import 'hc.dart';
import 'col.dart' show psia, rep, liveFug, fugLine;
import 'vc9.dart' show zDebut, zDeprop, aDebut, aDeprop;

void main(List<String> args) {
  final f = molps(100);
  final which = args.isEmpty ? 'scan' : args[0];
  if (which == 'scan') {
    for (final pre in [
      ['debut', zDebut, aDebut, 100.0, 76.4, 44.9437, 2, 3, [32], [14, 15, 16, 17, 18]],
      ['deprop', zDeprop, aDeprop, 250.0, 66.1, 30.7771, 0, 1, [28], [8, 9, 10, 11, 12]],
    ]) {
      final z = pre[1] as List<double>, p = (pre[3] as double) * psia;
      for (final nT in pre[8] as List<int>) {
        for (final nf in pre[9] as List<int>) {
          final c = Column(Thermo(six, 2), nT, nf, f, z, p, 0.7);
          c.solveLD(molps(pre[4] as double), molps(pre[5] as double));
          rep('${pre[0]} T3 E0.7 N$nT nf$nf', c, pre[6] as int, pre[7] as int);
          final c1 = Column(Thermo(six, 0, pre[2] as List<double>), nT, nf, f, z, p, 0.7);
          c1.solveLD(molps(pre[4] as double), molps(pre[5] as double));
          rep('${pre[0]} T1 E0.7 N$nT nf$nf', c1, pre[6] as int, pre[7] as int);
        }
      }
    }
  }
}
