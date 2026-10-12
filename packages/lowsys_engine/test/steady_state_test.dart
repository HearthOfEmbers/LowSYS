import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final bt = Presets.byId('bt');

  group('M1 steady states match the independent Newton solutions (VC-4)', () {
    void check(
        String name, Simulator sim, double xd, double xb, double dKmolh) {
      test(name, () {
        final r = sim.runToSteadyState();
        expect(r.reached, isTrue, reason: 'steady state not reached');
        final k = sim.snapshot().kpis;
        expect(k.xD, closeTo(xd, 1e-5));
        expect(k.xB, closeTo(xb, 1e-5));
        expect(k.d * 3.6, closeTo(dKmolh, 1e-4));
      });
    }

    Simulator cold(ColumnConfig c, [Map<String, double> lev = const {}]) {
      final s = Simulator(c, warmStart: false);
      lev.forEach(s.setLever);
      return s;
    }

    check('4.1 default', cold(bt), 0.981183, 0.018817, 50);
    check(
        '4.2 E = 1', cold(bt.copyWith(murphree: 1.0)), 0.995951, 0.004049, 50);
    check('4.3 E = 0.5', cold(bt.copyWith(murphree: 0.5)), 0.953307, 0.046693,
        50);
    check(
        '4.4 feed tray 5', cold(bt, {'feedStage': 5}), 0.948400, 0.051600, 50);
    check('4.5 feed tray 15', cold(bt, {'feedStage': 15}), 0.967099, 0.032901,
        50);
    check(
        '4.6 L0 110, V 160',
        cold(bt, {'refluxFlow': kmolh(110), 'boilup': kmolh(160)}),
        0.984504,
        0.015496,
        50);
    check(
        '4.7 L0 150, V 200',
        cold(bt, {'refluxFlow': kmolh(150), 'boilup': kmolh(200)}),
        0.991024,
        0.008976,
        50);
    check('4.8 q 0.5, V 100', cold(bt, {'feedQ': 0.5, 'boilup': kmolh(100)}),
        0.966910, 0.033090, 50);
    check(
        '4.9 V 155', cold(bt, {'boilup': kmolh(155)}), 0.907066, 0.002475, 55);
    check(
        '4.10 z 0.6', cold(bt, {'feedZ.benzene': 0.6}), 0.992453, 0.207547, 50);
    check('4.11 L0 110', cold(bt, {'refluxFlow': kmolh(110)}), 0.993373,
        0.171085, 40);
    check(
        '4.12 E 1, N 15, feed 8',
        cold(bt.copyWith(murphree: 1.0).withTrays(15, feedStage: 8)),
        0.986620,
        0.013380,
        50);
    check(
      '4.13 E 1, N 11, feed 6, 82.5/132.5',
      cold(bt.copyWith(murphree: 1.0).withTrays(11, feedStage: 6),
          {'refluxFlow': kmolh(82.5), 'boilup': kmolh(132.5)}),
      0.953272,
      0.046728,
      50,
    );
  });

  test('4.14 feed-tray scan, optimum on tray 11', () {
    const ref = [
      0.93211,
      0.94840,
      0.96031,
      0.96893,
      0.97495,
      0.97891,
      0.98118,
      0.98203,
      0.98147,
      0.97927,
      0.97479,
      0.96710,
      0.95520
    ];
    var best = 0, bestX = 0.0;
    for (var f = 4; f <= 16; f++) {
      final sim = btSteady({'feedStage': f.toDouble()});
      final x = sim.snapshot().kpis.xD;
      expect(x, closeTo(ref[f - 4], 1e-5), reason: 'feed tray $f');
      if (x > bestX) {
        bestX = x;
        best = f;
      }
    }
    expect(best, 11);
  });

  test(
      'warm start of the default preset is already steady and equals the cold result',
      () {
    final sim = btSim();
    final k = sim.snapshot().kpis;
    expect(sim.isSteady, isTrue);
    expect(sim.time, 0);
    expect(k.xD, closeTo(0.981183, 1e-5));
    expect(k.xB, closeTo(0.018817, 1e-5));
    expect(k.drumLevelPct, closeTo(50, 1e-4));
    expect(k.sumpLevelPct, closeTo(50, 1e-4));
  });

  test(
      'VC-7.4 steady-state monitor declares steady between 2.5 and 6 h from cold',
      () {
    final sim = Simulator(bt, warmStart: false);
    var t = 0.0;
    while (!sim.isSteady && t < 12 * 3600) {
      sim.advance(60);
      t += 60;
    }
    expect(sim.time / 3600, inInclusiveRange(2.5, 6.0));
  });

  test(
      'VC-6 time-step robustness: same steady state for dt 0.25, 0.5, 2, 5, 30 and one Murphree pass',
      () {
    for (final dt in [0.25, 0.5, 2.0, 5.0, 30.0]) {
      final sim = Simulator(bt,
          warmStart: false, options: SimOptions(dtFastForward: dt));
      sim.runToSteadyState();
      final k = sim.snapshot().kpis;
      expect(k.xD, closeTo(0.981183, 1e-6), reason: 'dt $dt');
      expect(k.xB, closeTo(0.018817, 1e-6), reason: 'dt $dt');
      expect(sim.solverHealth.negativeClamps, 0);
      expect(k.xD.isNaN, isFalse);
    }
    final one = Simulator(bt,
        warmStart: false, options: const SimOptions(murphreePasses: 1));
    one.runToSteadyState();
    expect(one.snapshot().kpis.xD, closeTo(0.981183, 1e-6));
  });
}
