import 'dart:math' as math;
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('VC-7.1 reflux step 100 -> 110 kmol/h from the default steady state',
      () {
    final sim = btSim();
    sim.setLever('refluxFlow', kmolh(110));
    final times = [60.0, 300.0, 600.0, 1800.0, 3600.0, 7200.0];
    final refXd = [0.9815, 0.9843, 0.9875, 0.9925, 0.9933, 0.99337];
    final refXb = [0.0195, 0.0385, 0.0718, 0.1447, 0.1680, 0.17105];
    final refD = [48.96, 45.45, 42.42, 38.47, 39.20, 39.99];
    final got = <List<double>>[];
    var xdPrev = 0.0;
    var monotone = true;
    var minD = 1e9;
    var maxDrumDev = 0.0;
    var t = 0.0;
    for (final target in times) {
      while (t < target - 1e-9) {
        sim.advance(1);
        t += 1;
        final k = sim.snapshot().kpis;
        if (t >= 60) {
          if (k.xD < xdPrev - 1e-12) monotone = false;
          xdPrev = k.xD;
        }
        minD = k.d * 3.6 < minD ? k.d * 3.6 : minD;
        final dev = (k.drumLevelPct - 50).abs();
        if (dev > maxDrumDev) maxDrumDev = dev;
      }
      final k = sim.snapshot().kpis;
      got.add([k.xD, k.xB, k.d * 3.6]);
    }
    test('values at the tabulated times', () {
      for (var i = 0; i < times.length; i++) {
        expect(got[i][0], closeTo(refXd[i], 0.002),
            reason: 'xD at ${times[i]}');
        expect(got[i][1], closeTo(refXb[i], 0.01), reason: 'xB at ${times[i]}');
        expect(got[i][2], closeTo(refD[i], 1.0), reason: 'D at ${times[i]}');
      }
    });
    test('direction checks', () {
      expect(monotone, isTrue);
      expect(minD, lessThan(40));
      expect(got.last[2], closeTo(40, 0.3));
    });
    test('drum level excursion 2..6 points and recovery', () {
      expect(maxDrumDev, inInclusiveRange(2.0, 6.0));
      sim.advance(6 * 3600);
      final k = sim.snapshot().kpis;
      expect(k.drumLevelPct, closeTo(50, 0.01));
      expect(k.xD, closeTo(0.993373, 1e-4));
    });
  });

  test('VC-7.3 sump level after +10 % feed: deviation 2..6 points, final 50 %',
      () {
    final sim = btSim();
    sim.setLever('feedFlow', kmolh(110));
    var maxDev = 0.0;
    for (var t = 0; t < 4 * 3600; t++) {
      sim.advance(1);
      if (t % 5 == 0) {
        final dev = (sim.snapshot().kpis.sumpLevelPct - 50).abs();
        if (dev > maxDev) maxDev = dev;
      }
    }
    expect(maxDev, inInclusiveRange(2.0, 6.0));
    sim.advance(8 * 3600);
    expect(sim.snapshot().kpis.sumpLevelPct, closeTo(50, 0.01));
  });

  test(
      'VC-7.2 hydraulic lag: tray 1 reaches 63 % within 1-4 s, tray 20 within 20-45 s',
      () {
    final sim = btSim();
    final l0 = sim.snapshot().stages.liquidDown;
    final base1 = l0[1], base20 = l0[20];
    sim.setLever('refluxFlow', kmolh(110));
    // the FC lag (3 s) is part of the response; measure from the lever change
    double? t1, t20;
    for (var i = 1; i <= 200; i++) {
      sim.step();
      final st = sim.snapshot().stages.liquidDown;
      final step = kmolh(10);
      if (t1 == null && st[1] - base1 >= 0.632 * step) t1 = i * 0.5;
      if (t20 == null && st[20] - base20 >= 0.632 * step) t20 = i * 0.5;
    }
    expect(t1, isNotNull);
    expect(t20, isNotNull);
    expect(t1!, inInclusiveRange(1, 4));
    expect(t20!, inInclusiveRange(20, 45));
  });

  test(
      'VC-3.2 dynamic total reflux gives N_stages = 6 (5 trays + reboiler, E = 1)',
      () {
    final cfg =
        Presets.byId('bt').copyWith(murphree: 1.0).withTrays(5, feedStage: 3);
    final sim = Simulator(cfg, warmStart: false);
    sim.setLever('feedFlow', 0);
    sim.setLever('refluxFlow', kmolh(150));
    sim.setLever('boilup', kmolh(150));
    sim.control.setMode('LC-101', LoopMode.man);
    sim.control.setMode('LC-102', LoopMode.man);
    sim.control.setOp('LC-101', 0);
    sim.control.setOp('LC-102', 0);
    sim.advance(6 * 3600);
    final k = sim.snapshot().kpis;
    final s = (k.xD / (1 - k.xD)) / (k.xB / (1 - k.xB));
    expect(_ln(s) / _ln(2.5), closeTo(6.0, 0.001));
    expect(k.xD, closeTo(0.916057, 2e-3));
  });

  test('levers: validation and effects', () {
    final sim = btSim();
    expect(() => sim.setLever('nope', 1), throwsArgumentError);
    expect(() => sim.setLever('feedFlow', -1), throwsRangeError);
    expect(() => sim.setLever('feedQ', 2), throwsRangeError);
    sim.setLever('feedZ.benzene', 0.3);
    expect(sim.lever('feedZ.benzene'), 0.3);
    expect(sim.isSteady, isFalse,
        reason: 'a lever change clears the steady flag');
    sim.setLever('refluxMode', 1);
    sim.setLever('refluxRatio', 2.0);
    sim.advance(3600);
    final k = sim.snapshot().kpis;
    expect(k.refluxRatio, closeTo(2.0, 0.01));
  });

  test('rebuild to a different number of trays keeps the column running', () {
    final sim = btSim();
    sim.setLever('nTrays', 30);
    expect(sim.config.trayCount, 30);
    expect(sim.snapshot().stages.n, 32);
    expect(sim.lever('feedStage'), 15);
    sim.runToSteadyState();
    final k = sim.snapshot().kpis;
    expect(k.xD, greaterThan(0.981));
    expect(k.xD.isFinite, isTrue);
    expect(sim.solverHealth.negativeClamps, 0);
  });

  test('custom alpha lever', () {
    final sim = Simulator(Presets.byId('bt_custom_alpha'), warmStart: false);
    sim.setLever('alpha', 1.5);
    sim.runToSteadyState();
    final lo = sim.snapshot().kpis.xD;
    final sim2 = Simulator(Presets.byId('bt_custom_alpha'), warmStart: false);
    sim2.setLever('alpha', 4.0);
    sim2.runToSteadyState();
    expect(sim2.snapshot().kpis.xD, greaterThan(lo));
  });
}

double _ln(double v) => math.log(v);
