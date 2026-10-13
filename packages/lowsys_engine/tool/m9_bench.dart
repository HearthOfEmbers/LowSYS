import 'package:lowsys_engine/lowsys_engine.dart';

void main() {
  final s = Simulator(Presets.byId('crude'));
  for (var i = 0; i < 2000; i++) {
    s.step();
  }
  final sw = Stopwatch()..start();
  const n = 100000;
  for (var i = 0; i < n; i++) {
    s.step();
  }
  print('crude step: ${(sw.elapsedMicroseconds / n).toStringAsFixed(1)} us/step');
}
