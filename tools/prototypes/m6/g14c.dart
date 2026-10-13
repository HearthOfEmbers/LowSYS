import 'dart:math';
import 'ts.dart';
void main() {
  // start: 15 % level, inlet 8 %, run 1200 s; then open inlet to 100 %
  final lp = Loop(Geo(), Props());
  for (var i = 0; i < 12000; i++) lp.step(0.1, 1300e3, 15, 8);
  print('start: W ${lp.w.toStringAsFixed(2)} xe ${lp.xe.toStringAsFixed(3)} Q ${(lp.q/1e3).toStringAsFixed(0)} Is ${lp.iS.toStringAsFixed(3)} amp ${sqrt(lp.u*lp.u+lp.v*lp.v)}');
  final marks = {0.002: -1.0, 0.02: -1.0, 0.05: -1.0, 0.10: -1.0, 0.13: -1.0};
  double tIs1 = -1;
  for (var i = 0; i < 12000; i++) {
    lp.step(0.1, 1300e3, 15, 100);
    final a = sqrt(lp.u*lp.u+lp.v*lp.v), t = (i + 1) * 0.1;
    if (tIs1 < 0 && lp.iS > 1) tIs1 = t;
    for (final k in marks.keys) { if (marks[k]! < 0 && a >= k) marks[k] = t; }
  }
  print('I_s > 1 at ${tIs1.toStringAsFixed(1)} s; amplitude thresholds reached at: $marks; final Is ${lp.iS.toStringAsFixed(3)} amp ${sqrt(lp.u*lp.u+lp.v*lp.v).toStringAsFixed(3)}');
  // recovery: level ramp 15 -> 40 over 1800 s then hold; track when amp < 0.02 and Is<1
  double tStable = -1, tIsBelow = -1;
  for (var i = 0; i < 36000; i++) {
    final t = (i + 1) * 0.1;
    final lv = min(40.0, 15 + 25 * t / 1800);
    lp.step(0.1, 1300e3, lv, 100);
    final a = sqrt(lp.u*lp.u+lp.v*lp.v);
    if (tIsBelow < 0 && lp.iS < 1) tIsBelow = t;
    if (tStable < 0 && a < 0.02 && lp.iS < 1) tStable = t;
  }
  print('recovery ramp 15->40 % over 30 min: I_s < 1 at ${tIsBelow.toStringAsFixed(0)} s (level ${(15 + 25 * tIsBelow / 1800).toStringAsFixed(1)} %), amp < 0.02 at ${tStable.toStringAsFixed(0)} s');
  // step response: level jump 15 -> 50
  final l2 = Loop(Geo(), Props());
  for (var i = 0; i < 12000; i++) l2.step(0.1, 1300e3, 15, 100);
  double t2 = -1;
  for (var i = 0; i < 12000; i++) { l2.step(0.1, 1300e3, 50, 100); final a = sqrt(l2.u*l2.u+l2.v*l2.v); if (t2 < 0 && a < 0.01) t2 = (i+1)*0.1; }
  print('level step 15 -> 50: amp < 0.01 after ${t2.toStringAsFixed(0)} s');
  // inlet throttle at 15 %: from oscillating to op 16
  final l3 = Loop(Geo(), Props());
  for (var i = 0; i < 12000; i++) l3.step(0.1, 1300e3, 15, 100);
  final a0 = sqrt(l3.u*l3.u+l3.v*l3.v);
  for (var i = 0; i < 3000; i++) l3.step(0.1, 1300e3, 15, 16);
  print('throttle to 16 % at 15 %: amp ${a0.toStringAsFixed(3)} -> ${sqrt(l3.u*l3.u+l3.v*l3.v).toStringAsFixed(3)} after 300 s');
}
