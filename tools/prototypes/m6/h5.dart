import 'dart:math';
import 'ts.dart';
void main() {
  final lp = Loop(Geo(), Props());
  for (var i = 0; i < 6000; i++) lp.step(0.1, 1300e3, 50, 100);
  double tIs = -1, t05 = -1, t02 = -1;
  for (var i = 0; i < 4 * 36000; i++) {
    final t = (i + 1) * 0.1;
    final lv = 50 - 10 * t / 3600;
    lp.step(0.1, 1300e3, lv, 100);
    final a = sqrt(lp.u * lp.u + lp.v * lp.v);
    if (tIs < 0 && lp.iS > 1) tIs = t;
    if (t02 < 0 && a >= 0.02) t02 = t;
    if (t05 < 0 && a >= 0.05) t05 = t;
  }
  String h(double t) => '${(t / 3600).toStringAsFixed(2)} h (level ${(50 - 10 * t / 3600).toStringAsFixed(1)} %)';
  print('I_s>1 at ${h(tIs)}; amp>=0.02 at ${h(t02)}; amp>=0.05 at ${h(t05)}');
  // F17/F18 ramps at 50 %: s_f mid, ramp 1800 s
  for (final c in [['F17', 0.55], ['F17', 0.3], ['F18', 0.4], ['F18', 0.2]]) {
    final l = Loop(Geo(), Props());
    for (var i = 0; i < 6000; i++) l.step(0.1, 1300e3, 50, 100);
    final w0 = l.w; double tIs1 = -1, tA = -1, minW = 1e9, maxIs = 0;
    for (var i = 0; i < 36000; i++) {
      final t = (i + 1) * 0.1; final s = (c[1] as double) * min(1.0, t / 1800);
      if (c[0] == 'F17') l.geo.kin = 4 + 300 * s; else l.geo.kout = 3 + 40 * s;
      l.step(0.1, 1300e3, 50, 100);
      final a = sqrt(l.u * l.u + l.v * l.v);
      if (tIs1 < 0 && l.iS > 1) tIs1 = t; if (tA < 0 && a >= 0.05) tA = t; minW = min(minW, l.w); maxIs = max(maxIs, l.iS);
    }
    print('${c[0]} s ${c[1]}: W0 ${w0.toStringAsFixed(2)} -> end ${l.w.toStringAsFixed(2)} (${((l.w / w0 - 1) * 100).toStringAsFixed(0)} %), xe ${l.xe.toStringAsFixed(3)}, max Is ${maxIs.toStringAsFixed(2)}, Is>1 at ${tIs1.toStringAsFixed(0)} s, amp>=0.05 at ${tA.toStringAsFixed(0)} s, Q ${(l.q / 1e3).toStringAsFixed(0)}');
  }
}
