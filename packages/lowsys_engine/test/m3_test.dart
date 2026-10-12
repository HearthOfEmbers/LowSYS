import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const kmolh = 1000 / 3600;

Simulator steady({int seed = 1, bool noise = false}) {
  final sim = Simulator(Presets.byId('bt'), options: SimOptions(seed: seed));
  sim.runToSteadyState();
  if (noise) sim.setLever('noise', 1);
  return sim;
}

void main() {
  test(
      'save/restore with noise, a plugged ramping fault and an alarm is bit-identical',
      () {
    final sim = steady(noise: true, seed: 5);
    sim.faults.inject(FaultSpec(
      type: FaultType.transmitter,
      location: const FaultLocation.tag('FT-102'),
      severity: 1.0,
      onset: sim.time + 900,
      ramp: 300,
      params: {'kind': 'plugged'},
    ));
    sim.setLever('drumLevelSp', 90);
    sim.advance(4000);
    expect(sim.snapshot().alarms, isNotEmpty);
    final saved = jsonEncode(sim.saveState());
    final copy = Simulator.restore(jsonDecode(saved) as Map<String, Object?>);
    sim.advance(1800);
    copy.advance(1800);
    expect(jsonEncode(copy.saveState()), equals(jsonEncode(sim.saveState())));
  });
}
