import 'dart:math';
import 'ts.dart';
void row(String label, {double qSp = 1300e3, double level = 75, double op = 100, double kout = 3, double kin = 4, double rf = 0, double dur = 3600}) {
  final lp = Loop(Geo()..kout = kout..kin = kin, Props())..rf = rf;
  final n = (dur / 0.1).round(), nA = 3000;
  final w = Stat(), x = Stat(), q = Stat(), iS = Stat(), a = Stat(), t = Stat(), qs = Stat();
  double? last; final per = <double>[]; var pu = lp.u;
  for (var i = 0; i < n; i++) {
    lp.step(0.1, qSp, level, op);
    if (i >= n - nA) {
      w.add(lp.w); x.add(lp.xe); q.add(lp.qDel); iS.add(lp.iS); a.add(sqrt(lp.u*lp.u+lp.v*lp.v)); t.add(lp.tOsc); qs.add(lp.q);
      if (pu < 0 && lp.u >= 0) { final tc = i * 0.1; if (last != null) per.add(tc - last); last = tc; }
    }
    pu = lp.u;
  }
  final pz = per.isEmpty ? t.mean : per.reduce((p, c) => p + c) / per.length;
  String f(double v, [int d = 3]) => v.toStringAsFixed(d);
  String pm(Stat s, int d, [double k = 1]) => s.half * k < pow(10, -d) / 2 ? f(s.mean * k, d) : '${f(s.mean * k, d)} ± ${f(s.half * k, d)}';
  print('| $label | ${pm(w, 2)} | ${pm(x, 3)} | ${pm(q, 0, 1e-3)} | ${f(qs.mean / 1e3, 0)} | ${f(iS.mean, 2)} | ${a.mean < 5e-4 ? '< 1e-6' : f(a.mean, 3)} | ${f(pz, 1)} (T_osc ${f(t.mean, 1)}) |');
}
void main() {
  row('1300 kW, 90 %, 100 %', level: 90);
  row('1300 kW, 75 %, 100 %', level: 75);
  row('1300 kW, 75 %, 16 %', level: 75, op: 16);
  row('1300 kW, 50 %, 100 %', level: 50);
  row('1300 kW, 30 %, 100 %', level: 30);
  row('1300 kW, 15 %, 100 %', level: 15);
  row('1300 kW, 15 %, 16 %', level: 15, op: 16);
  row('1300 kW, 15 %, 8 %', level: 15, op: 8);
  row('1600 kW, 75 %, 100 %', qSp: 1600e3, level: 75);
  row('1600 kW, 30 %, 100 %', qSp: 1600e3, level: 30);
  row('1300 kW, 75 %, K_out 20', kout: 20);
  row('1300 kW, 75 %, R_f 4e-4 m2K/W', rf: 4e-4);
  row('1300 kW, 50 %, F17 s 0.5 (K_in 154)', level: 50, kin: 154);
  row('1300 kW, 50 %, F18 s 0.4 (K_out 19)', level: 50, kout: 19);
  row('1300 kW, 30 %, 1200 s run', level: 30, dur: 1200);
  row('1300 kW, 15 %, 16 %, 1200 s run', level: 15, op: 16, dur: 1200);
}
