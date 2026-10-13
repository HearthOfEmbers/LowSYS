import 'ts.dart';
void main() {
  final lp = Loop(Geo(), Props());
  for (var i = 0; i < 12000; i++) {
    lp.step(0.1, 1300e3, 15, 100);
    if (i >= 11900 && i < 11940) print('${i} W ${lp.w.toStringAsFixed(3)} u ${lp.u.toStringAsFixed(4)} xe ${lp.xe.toStringAsFixed(4)} q ${(lp.q/1e3).toStringAsFixed(0)} qmax ${(lp.qMax/1e3).toStringAsFixed(0)}');
  }
}
