// VC-20 determinism: two runs with the same config, lever script and seed
// give bit-identical saveState() JSON after 10 000 steps.
library;

import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

String _run() {
  final sim = newSim(btConfig(), options: const SimOptions(seed: 7));
  for (var k = 0; k < 10000; k++) {
    if (k == 2000) sim.setLever('refluxFlow', 110 * kmolh);
    if (k == 5000) sim.setLever('feedZ.benzene', 0.55);
    if (k == 7000) sim.setLever('boilup', 160 * kmolh);
    sim.step();
  }
  return jsonEncode(sim.saveState());
}

void main() {
  test('VC-20 two runs of 10 000 steps give bit-identical saveState JSON', () {
    final a = _run();
    final b = _run();
    expect(a, equals(b));
    expect(a.length, greaterThan(100));
  });

  test('VC-20 restore then step equals continuing the original', () {
    final sim = newSim(btConfig());
    for (var k = 0; k < 1000; k++) {
      sim.step();
    }
    final saved = sim.saveState();
    final copy = Simulator.restore(
        jsonDecode(jsonEncode(saved)) as Map<String, Object?>);
    for (var k = 0; k < 500; k++) {
      sim.step();
      copy.step();
    }
    expect(jsonEncode(copy.saveState()), equals(jsonEncode(sim.saveState())));
  });
}
