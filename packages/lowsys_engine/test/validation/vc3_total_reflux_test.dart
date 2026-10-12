// VC-3.2 dynamic total reflux: 5 trays + reboiler, E = 1, F = 0, D = B = 0,
// L0 = VB = 150 kmol/h. After 6 h the Fenske stage count from (xD, xB)
// must be exactly 6.0000 (± 0.001).
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('VC-3.2 dynamic total reflux gives N_s = 6.0000 after 6 h', () {
    final cfg = btConfig(overrides: {
      'sections[0].trays': 5,
      'feeds[0].stage': 3,
      'murphree': 1.0,
    });
    final sim = newSim(cfg);
    sim.setLever('feedFlow', 0);
    sim.setLever('refluxFlow', 150 * kmolh);
    sim.setLever('boilup', 150 * kmolh);
    // D and B valves closed: LC-101/102 in MAN at 0 %.
    sim.control.setMode('LC-101', LoopMode.man);
    sim.control.setOp('LC-101', 0);
    sim.control.setMode('LC-102', LoopMode.man);
    sim.control.setOp('LC-102', 0);

    // The product valves and the flow levers close through their actuator
    // lags (a few seconds), so take the inventory baseline once they are
    // shut; after that the column is sealed.
    sim.advance(120);
    final inv0 = prof(sim).lightInventory();
    final tot0 = prof(sim).totalInventory();
    sim.advance(6 * 3600 - 120);
    final p = prof(sim);
    expectPhysical(p.s, where: 'total reflux 6 h');
    expect(p.totalInventory(), closeTo(tot0, 1e-8 * tot0),
        reason: 'total inventory sealed');

    final ns =
        math.log((p.xD / (1 - p.xD)) / (p.xB / (1 - p.xB))) / math.log(2.5);
    expect(ns, closeTo(6.0, 1e-3),
        reason:
            'Fenske N_s from xD=${p.xD} xB=${p.xB} (prototype 0.916057 / 0.042786)');
    // With no products and no feed, the light-component inventory is constant.
    expect(p.lightInventory(), closeTo(inv0, 1e-8 * inv0));
    expect(p.dKmolh, closeTo(0, 1e-9));
    expect(p.bKmolh, closeTo(0, 1e-9));
    // Every tray at E = 1 sits on the equilibrium curve and passing streams
    // are equal (y_{j+1} = x_j) at total reflux.
    for (var j = 1; j <= p.nTrays; j++) {
      expect(p.y(j + 1), closeTo(p.x(j), 1e-6),
          reason: 'passing streams tray $j');
    }
  });
}
