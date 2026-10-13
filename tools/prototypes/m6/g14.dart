import 'sweep.dart' as sw;
void main() {
  for (final lv in [15.0, 20.0, 25.0]) for (final op in [100.0, 30.0, 16.0, 10.0, 5.0]) for (final q in [1300e3, 1170e3, 1000e3]) {
    final r = sw.runOne(level: lv, op: op, qSp: q, dur: 3600);
    sw.pr('L${lv.toInt()} op${op.toInt()} Q${(q/1e3).toInt()}', r);
  }
  for (final lv in [30.0, 32.0, 35.0, 40.0]) { sw.pr('L${lv.toInt()} op100 Q1300', sw.runOne(level: lv, dur: 3600)); sw.pr('L${lv.toInt()} op16 Q1300', sw.runOne(level: lv, op: 16, dur: 3600)); }
}
