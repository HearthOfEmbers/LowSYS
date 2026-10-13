import 'dart:math';
import 'ts.dart';
List<double> runOne({double qSp = 1300e3, double level = 50, double op = 100, double kout = 3, double kin = 4, double dur = 2400}) {
  final geo = Geo()..kout = kout..kin = kin;
  final lp = Loop(geo, Props());
  final n = (dur / 0.1).round(), nA = 3000;
  final w = Stat(), x = Stat(), q = Stat(), iS = Stat(), a = Stat(), t = Stat(), qm = Stat();
  for (var i = 0; i < n; i++) {
    lp.step(0.1, qSp, level, op);
    if (i >= n - nA) { w.add(lp.w); x.add(lp.xe); q.add(lp.qDel); iS.add(lp.iS); a.add(sqrt(lp.u*lp.u+lp.v*lp.v)); t.add(lp.tOsc); qm.add(lp.q);}
  }
  return [w.mean, x.mean, q.mean/1e3, iS.mean, a.mean, t.mean, qm.mean/1e3, lp.xeBar, lp.routBar, lp.rinBar];
}
String f(double v, [int d = 3]) => v.toStringAsFixed(d);
void pr(String l, List<double> r) => print('$l W ${f(r[0],2)} xe ${f(r[1])} Qdel ${f(r[2],0)} Q ${f(r[6],0)} Is ${f(r[3])} amp ${f(r[4],3)} T ${f(r[5],1)} | xeBar/0.3 ${f(r[7]/0.3)} rout ${f(r[8])} rin ${f(r[9])}');
void mainSweep() {
  print('-- level sweep, 1300 kW');
  for (final lv in [90, 75, 60, 50, 40, 35, 30, 27, 25, 22, 20, 15, 10]) pr('L$lv', runOne(level: lv.toDouble()));
  print('-- F17 Kin = 4 + 300 s, level 50');
  for (final s in [0.0, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0]) pr('s$s', runOne(kin: 4 + 300 * s));
  print('-- F18 Kout = 3 + 40 s, level 50');
  for (final s in [0.0, 0.1, 0.2, 0.25, 0.3, 0.4, 0.5, 0.7, 1.0]) pr('s$s', runOne(kout: 3 + 40 * s));
  print('-- F17 at 75 %');
  for (final s in [0.5, 1.0]) pr('s$s', runOne(kin: 4 + 300 * s, level: 75));
  print('-- F18 at 75 %');
  for (final s in [0.3, 0.5, 1.0]) pr('s$s', runOne(kout: 3 + 40 * s, level: 75));
}
