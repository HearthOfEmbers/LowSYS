// M9: VC-15.4 default steady state, closure, flags, direction checks, settling time and the step budget (VC-19).
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm9_helpers.dart';

void main() {
  late Simulator sim;
  setUpAll(() {
    sim = crudeSim();
  });

  test('VC-15.4 reference table at the default steady state', () {
    final s = sim.snapshot();
    final k = s.kpis.crude!;
    expect(sim.isSteady, isTrue);
    expect(k.yieldVolPct[0], closeTo(19.75, 0.3));
    expect(k.yieldVolPct[1], closeTo(11.70, 0.02));
    expect(k.yieldVolPct[2], closeTo(16.70, 0.02));
    expect(k.yieldVolPct[3], closeTo(5.30, 0.02));
    expect(k.yieldVolPct[4], closeTo(46.55, 0.3));
    expect(k.yieldVolPct.fold(0.0, (a, b) => a + b), closeTo(100, 1e-3));
    expect(k.overflashVolPct, closeTo(4.60, 0.6));
    expect(c(sim.liveMetric('stage[1].t') as double), closeTo(125.0, 0.05));
    expect(c(sim.liveMetric('stage[8].t') as double), closeTo(182.26, 1.5));
    expect(c(sim.liveMetric('stage[15].t') as double), closeTo(250.12, 1.5));
    expect(c(sim.liveMetric('stage[21].t') as double), closeTo(322.55, 1.5));
    expect(c(k.flashZoneT), closeTo(343.25, 1.5));
    expect(c(k.bottomT), closeTo(331.09, 1.5));
    expect(c(s.strippers[0].t[1]), closeTo(164.66, 2));
    expect(c(s.strippers[1].t[1]), closeTo(238.54, 2));
    expect(c(s.strippers[2].t[1]), closeTo(302.56, 2));
    expect(c(k.paReturnT), closeTo(202.5, 3));
    expect(s.streams[StreamId.reflux]!.flow * 3.6, closeTo(316.1, 316.1 * 0.03));
    expect(k.qc / 1e6, closeTo(8.945, 8.945 * 0.03));
    for (var i = 0; i < 3; i++) {
      expect(s.strippers[i].draw * 3.6, closeTo([96.12, 102.05, 28.37][i], [96.12, 102.05, 28.37][i] * 0.03));
      expect(s.strippers[i].vaporReturn * 3.6, closeTo([17.37, 14.88, 6.37][i], [17.37, 14.88, 6.37][i] * 0.10));
    }
    const d5 = [58.9, 160.5, 229.3, 318.2], d50 = [100.2, 200.3, 281.9, 369.3], d95 = [159.7, 238.2, 327.9, 398.2];
    for (var i = 0; i < 4; i++) {
      expect(c(k.d86p5[i]), closeTo(d5[i], 3));
      expect(c(k.d86p50[i]), closeTo(d50[i], 3));
      expect(c(k.d86p95[i]), closeTo(d95[i], 3));
    }
    expect(k.gapKeroNaphtha, closeTo(0.9, 4));
    expect(k.gapDieselKero, closeTo(-9.0, 4));
    expect(k.gapAgoDiesel, closeTo(-9.7, 4));
    expect(c(k.residueTbp5), closeTo(358.8, 2));
    expect(s.stages.p[26] / 1e5, closeTo(1.699, 0.02));
    expect(s.stages.p[30] / 1e5, closeTo(1.723, 0.02));
    expect(s.kpis.columnDp / 1000, closeTo(12.89, 12.89 * 0.15));
    var fmin = 1e9, fmax = 0.0;
    for (var j = 1; j <= 30; j++) {
      fmin = fmin < s.stages.jetFlood[j] ? fmin : s.stages.jetFlood[j];
      fmax = fmax > s.stages.jetFlood[j] ? fmax : s.stages.jetFlood[j];
    }
    expect(100 * fmin, closeTo(36.0, 4));
    expect(100 * fmax, closeTo(59.3, 4));
    expect(k.waterDewMargin, closeTo(50.1, 2));
  });

  test('closure, bounds and flags', () {
    final s = sim.snapshot();
    final k = s.kpis.crude!;
    expect(s.kpis.balanceResidual.abs(), lessThan(1e-4));
    expect(s.kpis.energyResidual.abs(), lessThan(1e-3));
    // lumped upper bounds of the gaps (VC-15.3)
    expect(k.gapKeroNaphtha, lessThan(17.4));
    expect(k.gapDieselKero, lessThan(15.1));
    expect(k.gapAgoDiesel, lessThan(0.3));
    expect(k.drawDry, [false, false, false]);
    expect(k.condenserLimited, isFalse);
    expect(k.paDutyLimited, isFalse);
    expect(sim.liveMetric('alarm.count'), 0);
    expect(s.solverHealth.negativeLatent, 0);
    expect(s.solverHealth.bubbleFallbacks, 0);
    for (var j = 1; j <= 30; j++) {
      expect(s.stages.weepFrac[j], lessThan(0.3), reason: 'weep stage $j');
    }
    // water out = steam in (160.98 kmol/h)
    var steam = 0.0;
    for (final st in s.strippers) {
      steam += st.steam;
    }
    steam += sim.lever('steam.bottom') / 0.018015;
    expect(steam * 3.6, closeTo(160.98, 0.05));
  });

  test('direction checks from the default steady state', () {
    Simulator run(Map<String, double> lev) => steadyC(crudeSim(levers: lev));
    var k = kpiOf(run({'drawRate.kero': 0.137 * crudeRate0}));
    expect(c(k.d86p95[1]), closeTo(256.1, 3));
    expect(c(k.d86p5[2]), closeTo(238.5, 3));
    expect(k.gapDieselKero, lessThan(-14));
    expect(k.gapKeroNaphtha, closeTo(0.9, 5));
    expect(k.yieldVolPct[4], closeTo(46.55 - 1.97, 0.3));
    expect(k.overflashVolPct, closeTo(1.74, 0.6));
    k = kpiOf(run({'drawRate.kero': 0.097 * crudeRate0}));
    expect(c(k.d86p95[1]), closeTo(230.2, 3));
    expect(k.yieldVolPct[4], closeTo(46.55 + 1.98, 0.3));
    expect(k.overflashVolPct, closeTo(7.58, 0.8));
    k = kpiOf(run({'cot': 623.15}));
    expect(k.overflashVolPct, closeTo(6.56, 0.6));
    expect(k.gapDieselKero, closeTo(0.1, 4));
    expect(k.qc / 1e6, closeTo(9.27, 0.3));
    final s3 = run({'paDuty': 3e6});
    k = kpiOf(s3);
    expect(k.gapDieselKero, closeTo(6.5, 3));
    expect(k.qc / 1e6, closeTo(10.81, 0.35));
    expect(s3.snapshot().kpis.maxFloodPct, closeTo(65.7, 4));
    k = kpiOf(run({'steam.bottom': 1000 / 3600}));
    expect(k.yieldVolPct[4], closeTo(47.07, 0.3));
    expect(c(k.bottomT), closeTo(336.9, 1.5));
  });

  test('COT scan: overflash', () {
    final ref = {335.0: 1.17, 340.0: 2.76, 345.0: 4.60, 350.0: 6.56};
    for (final e in ref.entries) {
      final k = kpiOf(steadyC(crudeSim(levers: {'cot': e.key + 273.15})));
      expect(k.overflashVolPct, closeTo(e.value, 0.6), reason: 'COT ${e.key}');
    }
  });

  test('settling time from the cold start and the step budget (VC-19 crude)', () {
    final s = crudeSimCold();
    final r = s.runToSteadyState(maxSimSeconds: 8 * 3600);
    expect(r.reached, isTrue);
    // ignore: avoid_print
    print('cold start: steady declared after ${(r.simSeconds / 3600).toStringAsFixed(2)} h of process time');
    expect(r.simSeconds, lessThanOrEqualTo(8 * 3600));
    final sw = Stopwatch()..start();
    const n = 20000;
    for (var i = 0; i < n; i++) {
      s.step();
    }
    final us = sw.elapsedMicroseconds / n;
    // ignore: avoid_print
    print('crude step(): ${us.toStringAsFixed(0)} us (JIT); the VC-19 target of 150 us is for release/AOT builds');
    expect(us, lessThan(450));
  });
}

/// The crude preset without the warm start.
Simulator crudeSimCold() => Simulator(Presets.byId('crude'), warmStart: false);
