import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Per-component inventory (mol) from the snapshot holdups and compositions.
Float64List inventory(Simulator sim) {
  final s = sim.snapshot().stages;
  final inv = Float64List(s.nc);
  for (var j = 0; j < s.n; j++) {
    for (var i = 0; i < s.nc; i++) {
      inv[i] += s.holdup[j] * s.x[j * s.nc + i];
    }
  }
  return inv;
}

void main() {
  test(
      'VC-5.1 component conservation to 1e-10 over 10 h incl. a reflux step and a feed step',
      () {
    final sim = Simulator(Presets.byId('bt'), warmStart: false);
    const nc = 2;
    final inv0 = inventory(sim);
    final feedIn = Float64List(nc), out = Float64List(nc);
    var fzTotal = 0.0;
    const totalSteps = 10 * 3600 * 2;
    for (var k = 0; k < totalSteps; k++) {
      if (k == 4 * 3600 * 2) sim.setLever('refluxFlow', kmolh(112));
      if (k == 7 * 3600 * 2) sim.setLever('feedFlow', kmolh(90));
      sim.step();
      final d = sim.debug;
      for (var i = 0; i < nc; i++) {
        feedIn[i] += d.feedRate[i] * d.dt;
        out[i] += (d.distillateRate[i] + d.bottomsRate[i]) * d.dt;
      }
      fzTotal += d.feedFlow * d.dt;
    }
    final inv1 = inventory(sim);
    for (var i = 0; i < nc; i++) {
      final err = ((inv1[i] - inv0[i]) - feedIn[i] + out[i]).abs() / fzTotal;
      expect(err, lessThan(1e-10), reason: 'component $i');
    }
    expect(sim.solverHealth.negativeClamps, 0);
  });

  test('no negative holdups and no NaN after violent lever moves', () {
    final sim = btSim();
    sim.setLever('boilup', 0);
    sim.setLever('refluxFlow', kmolh(300));
    sim.advance(1800);
    sim.setLever('refluxFlow', 0);
    sim.setLever('boilup', kmolh(300));
    sim.advance(1800);
    final s = sim.snapshot();
    for (final v in s.stages.holdup) {
      expect(v.isFinite && v >= 0, isTrue);
    }
    for (final v in s.stages.x) {
      expect(v.isFinite && v >= -1e-12 && v <= 1 + 1e-9, isTrue);
    }
    expect(sim.halted, isFalse);
  });
}
