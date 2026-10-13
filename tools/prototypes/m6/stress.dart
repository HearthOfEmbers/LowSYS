import 'dart:math';
import 'ts.dart';
void main() {
  final r = Random(7);
  var bad = 0; var worst = '';
  for (var c = 0; c < 400; c++) {
    final level = r.nextDouble() * 100, op = 5 + r.nextDouble() * 95, kout = 3 + 40 * r.nextDouble(), kin = 4 + 300 * r.nextDouble();
    final q = 1e5 + r.nextDouble() * 3e6, w0 = r.nextDouble() * 30, rf = r.nextDouble() * 2e-3, ff = r.nextDouble() * 0.8;
    final lp = Loop(Geo()..kout = kout..kin = kin, Props(), w: w0)..rf = rf..fFlood = ff;
    var maxA = 0.0, minW = 1e9;
    for (var i = 0; i < 6000; i++) {
      lp.step(0.1, q, level, op);
      final a = sqrt(lp.u*lp.u+lp.v*lp.v); maxA = max(maxA, a); minW = min(minW, lp.w);
      if (!lp.w.isFinite || !lp.qDel.isFinite || !lp.iS.isFinite || lp.xe < 0 || lp.xe > 1 || lp.w < 0 || lp.fsc < 0 || lp.fsc > 1) { bad++; worst = 'L$level op$op kout$kout kin$kin q$q -> W${lp.w} xe${lp.xe}'; break; }
    }
    if (maxA > 0.32) { print('big amp $maxA at L${level.toStringAsFixed(0)} op${op.toStringAsFixed(0)} kout${kout.toStringAsFixed(0)} kin${kin.toStringAsFixed(0)} Q${(q/1e3).toStringAsFixed(0)} W${lp.w.toStringAsFixed(2)} xe${lp.xe.toStringAsFixed(2)} Is${lp.iS.toStringAsFixed(2)}'); }
  }
  print('bad $bad $worst');
}
