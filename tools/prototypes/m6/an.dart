import 'dart:math';
import 'ts.dart';
void case_(String label, {double qSp = 1300e3, double level = 75, double op = 100, double kout = 3, double kin = 4, double dur = 1200, double dlt = 0.1, bool jitter = false}) {
  final geo = Geo()..kout = kout..kin = kin;
  final lp = Loop(geo, Props());
  final n = (dur / dlt).round(), nA = (300 / dlt).round();
  final w = Stat(), x = Stat(), q = Stat(), iS = Stat(), a = Stat(), t = Stat(), uu = Stat();
  double? lastCross; final periods = <double>[]; var prevU = lp.u;
  var maxJump = 0.0; var prevX = 0.0;
  for (var i = 0; i < n; i++) {
    lp.step(dlt, qSp, level, op);
    if (i >= n - nA) {
      w.add(lp.w); x.add(lp.xe); q.add(lp.qDel); iS.add(lp.iS); a.add(sqrt(lp.u*lp.u+lp.v*lp.v)); t.add(lp.tOsc); uu.add(lp.u);
      if (prevU < 0 && lp.u >= 0) { final tc = i * dlt; if (lastCross != null) periods.add(tc - lastCross); lastCross = tc; }
      if (i > n - nA) maxJump = max(maxJump, (lp.xe - prevX).abs());
    }
    prevU = lp.u; prevX = lp.xe;
  }
  final per = periods.isEmpty ? double.nan : periods.reduce((p, c) => p + c) / periods.length;
  String f(double v, [int d = 3]) => v.toStringAsFixed(d);
  print('$label: W ${f(w.mean,2)} [${f(w.mid,2)}±${f(w.half,2)}] xe ${f(x.mean)} [${f(x.mid)}±${f(x.half)}] Q ${f(q.mean/1e3,0)} [${f(q.mid/1e3,0)}±${f(q.half/1e3,0)}] Is ${f(iS.mean)} amp ${f(a.mean,4)} Tosc ${f(t.mean,2)} Tzc ${f(per,2)} meanU ${f(uu.mean,4)} maxdxe ${f(maxJump,4)}');
}
void main(List<String> args) {
  final dlt = args.isNotEmpty ? double.parse(args[0]) : 0.1;
  final dur = args.length > 1 ? double.parse(args[1]) : 1200.0;
  case_('1300 90', level: 90, dlt: dlt, dur: dur);
  case_('1300 75', level: 75, dlt: dlt, dur: dur);
  case_('1300 75 v16', level: 75, op: 16, dlt: dlt, dur: dur);
  case_('1300 50', level: 50, dlt: dlt, dur: dur);
  case_('1300 30', level: 30, dlt: dlt, dur: dur);
  case_('1300 15', level: 15, dlt: dlt, dur: dur);
  case_('1300 15 v16', level: 15, op: 16, dlt: dlt, dur: dur);
  case_('1600 75', qSp: 1600e3, level: 75, dlt: dlt, dur: dur);
  case_('1600 30', qSp: 1600e3, level: 30, dlt: dlt, dur: dur);
  case_('1300 75 Kout20', kout: 20, dlt: dlt, dur: dur);
}
