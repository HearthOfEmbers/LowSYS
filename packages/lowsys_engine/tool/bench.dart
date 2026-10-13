import 'package:lowsys_engine/lowsys_engine.dart';
void main() {
  final cfg = Presets.byId('bt').copyWith(hydraulics: HydraulicsMode.full);
  final sim = Simulator(cfg);
  sim.setLever('noise', const bool.fromEnvironment('NOISE', defaultValue: true) ? 1 : 0);
  sim.advance(600);
  var sw = Stopwatch()..start();
  for (var i = 0; i < 2000; i++) sim.step();
  print('step us ${sw.elapsedMicroseconds / 2000}');
  sw = Stopwatch()..start();
  for (var i = 0; i < 300; i++) sim.snapshot();
  print('snapshot us ${sw.elapsedMicroseconds / 300}');
  final b = McCabeThieleBuilder();
  final s = sim.snapshot();
  sw = Stopwatch()..start();
  for (var i = 0; i < 300; i++) b.build(s, sim.thermo);
  print('mccabe us ${sw.elapsedMicroseconds / 300}');
}
