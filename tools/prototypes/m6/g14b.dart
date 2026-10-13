import 'sweep.dart' as sw;
void main() {
  for (final op in [12.0, 10.0, 8.0]) sw.pr('L15 op${op.toInt()} Q1300', sw.runOne(level: 15, op: op, dur: 3600));
}
