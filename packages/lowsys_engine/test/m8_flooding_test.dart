// M8 coder tests: VC-13.4 packing flooding develops over time (ratio-preserving +10 % steps), steady guide rows,
// the dynamics past flood (carry-over), and the robustness assertion over 4 h.
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm8_helpers.dart';

void _scale(Simulator sim, double f0, double l0, double v0, double k) {
  sim.setLever('feedFlow', f0 * k);
  sim.setLever('refluxFlow', l0 * k);
  sim.setLever('boilup', v0 * k);
}

void main() {
  test('steady guide rows n = 0, 3, 4, 5 (V_B 150 x 1.1^n, F and L0 with it)', () {
    // n: phi lower, phi upper, dP lower, dP upper, h_L(18), HETP(18), x_D, x_B
    final rows = {
      0: (0.5938, 0.4882, 818.6, 587.4, 0.05270, 0.5000, 0.99383, 0.00617),
      3: (0.7903, 0.6497, 1596.5, 1082.7, 0.06115, 0.5000, 0.99383, 0.00617),
      4: (0.8693, 0.7153, 2043.2, 1338.5, 0.07136, 0.5192, 0.99356, 0.00644),
      5: (0.9555, 0.7904, 2692.7, 1678.7, 0.10265, 0.5968, 0.99168, 0.00832),
    };
    final sim = steady(packedSim());
    final f0 = sim.lever('feedFlow'), l0 = sim.lever('refluxFlow'), v0 = sim.lever('boilup');
    for (final e in rows.entries) {
      _scale(sim, f0, l0, v0, math.pow(1.1, e.key).toDouble());
      steady(sim);
      final s = sim.snapshot(), r = e.value;
      expect(s.beds[1].maxFlood, closeTo(r.$1, 0.002), reason: 'phi lower, n=${e.key}');
      expect(s.beds[0].maxFlood, closeTo(r.$2, 0.002), reason: 'phi upper');
      expect(s.beds[1].dp, closeTo(r.$3, 0.005 * r.$3), reason: 'dP lower');
      expect(s.beds[0].dp, closeTo(r.$4, 0.005 * r.$4), reason: 'dP upper');
      expect(s.stages.packHoldup[18], closeTo(r.$5, 1e-4), reason: 'h_L');
      expect(s.stages.hetp[18], closeTo(r.$6, 0.003), reason: 'HETP');
      expect(s.kpis.xD, closeTo(r.$7, 1e-4), reason: 'x_D');
      expect(s.kpis.xB, closeTo(r.$8, 1e-4), reason: 'x_B');
    }
  });

  test('flooding develops dynamically: steps of +10 % every 30 min, past flood the dP keeps rising', () {
    final sim = steady(packedSim());
    final f0 = sim.lever('feedFlow'), l0 = sim.lever('refluxFlow'), v0 = sim.lever('boilup');
    final dp = <double>[], phi = <double>[], hl = <double>[];
    double? crossedAt, crossedDp;
    var minHold = 1e9;
    final trace = <(double, double)>[];
    for (var n = 1; n <= 6; n++) {
      _scale(sim, f0, l0, v0, math.pow(1.1, n).toDouble());
      for (var t = 0; t < 1800; t += 30) {
        sim.advance(30);
        final s = sim.snapshot();
        expect(sim.halted, isFalse);
        for (final h in s.stages.holdup) {
          expect(h.isNaN || h.isInfinite, isFalse);
          minHold = math.min(minHold, h);
        }
        if (crossedAt == null && s.beds[1].maxFlood >= 1.0) {
          crossedAt = sim.time;
          crossedDp = s.beds[1].dp;
        }
        if (crossedAt != null) trace.add((sim.time - crossedAt, s.beds[1].dp));
        if (t == 1770) {
          dp.add(s.beds[1].dp);
          phi.add(s.beds[1].maxFlood);
          hl.add(s.stages.packHoldup[18]);
        }
      }
    }
    expect(minHold, greaterThanOrEqualTo(0));
    // holdup and dP rise steeply once phi_p > 0.85: the dP increase per step grows
    expect(dp[1] - dp[0], lessThan(dp[4] - dp[3]));
    expect(hl[4] - hl[3], greaterThan(hl[1] - hl[0]));
    expect(phi[5], greaterThan(1.0));
    // at phi_p >= 1 the bed dP exceeds the Kister-Gill flood dP and keeps rising for at least 5 min
    expect(crossedAt, isNotNull);
    final floodDp = 765.17 * 4.5;
    final after = trace.where((e) => e.$1 >= 600).first.$2;
    expect(dp[5], greaterThan(floodDp));
    expect(trace.where((e) => e.$1 >= 300).first.$2, greaterThan(crossedDp!), reason: 'still rising 5 min after crossing');
    expect(after, greaterThan(crossedDp), reason: 'and 10 min after');
    expect(sim.snapshot().stages.hetp[18] / 0.5, greaterThanOrEqualTo(1.3));
    expect(dp.last, greaterThan(3688.0 * 0.95), reason: 'at least the no-carry-over bound (3688 Pa)');
    // PDT-103 stays inside its 10 kPa span
    final pdt = sim.snapshot().instruments.firstWhere((i) => i.tag == 'PDT-103').value;
    expect(pdt, lessThan(10000));
    // ignore: avoid_print
    print('VC-13.4 dynamics: phi_p crossed 1 at ${crossedAt!.toStringAsFixed(0)} s (dP ${crossedDp!.toStringAsFixed(0)} Pa); '
        'dP 5 min later ${trace.where((e) => e.$1 >= 300).first.$2.toStringAsFixed(0)}, 10 min ${after.toStringAsFixed(0)}, '
        'end of step 6 ${dp.last.toStringAsFixed(0)} Pa; phi per step ${phi.map((p) => p.toStringAsFixed(3)).toList()}; '
        'HETP18 ${sim.snapshot().stages.hetp[18].toStringAsFixed(3)} m');
  });

  test('settling time of holdup and dP after a +10 % load step near flood (n = 4 -> 5)', () {
    final sim = steady(packedSim());
    final f0 = sim.lever('feedFlow'), l0 = sim.lever('refluxFlow'), v0 = sim.lever('boilup');
    _scale(sim, f0, l0, v0, math.pow(1.1, 4).toDouble());
    steady(sim);
    final dp0 = sim.snapshot().beds[1].dp;
    final h0 = sim.snapshot().stages.packHoldup[18];
    _scale(sim, f0, l0, v0, math.pow(1.1, 5).toDouble());
    double? t90, th90;
    final t0 = sim.time;
    final target = 2692.7;
    for (var t = 0; t < 7200 && (t90 == null || th90 == null); t += 10) {
      sim.advance(10);
      final s = sim.snapshot();
      if (t90 == null && (s.beds[1].dp - dp0) >= 0.9 * (target - dp0)) t90 = sim.time - t0;
      if (th90 == null && (s.stages.packHoldup[18] - h0) >= 0.9 * (0.10265 - h0)) th90 = sim.time - t0;
    }
    expect(t90, isNotNull);
    expect(th90, isNotNull);
    // ignore: avoid_print
    print('VC-13.4: after the +10 % step the lower bed dP reaches 90 % of its new steady value in ${t90!.toStringAsFixed(0)} s, '
        'the holdup of segment 18 in ${th90!.toStringAsFixed(0)} s (the dP follows the flows, the holdup the drainage time)');
    expect(th90, greaterThan(20), reason: 'not instantaneous');
  });

  test('robustness: every VC-13.8 case with the +25 % event, 4 h, no NaN and no negative holdup', () {
    final cases = <(String, FaultType?, int, double)>[
      ('healthy', null, 0, 0),
      ('F21 upper 0.8', FaultType.packingMaldistribution, 1, 0.8),
      ('F21 lower 0.8', FaultType.packingMaldistribution, 2, 0.8),
      ('F23 upper 0.5', FaultType.packingCrush, 1, 0.5),
      ('F23 lower 0.5', FaultType.packingCrush, 2, 0.5),
    ];
    for (final c in cases) {
      final sim = h7Sim();
      if (c.$2 != null) {
        sim.faults.inject(FaultSpec(type: c.$2!, location: FaultLocation.bed(c.$3), severity: c.$4, onset: 600));
      }
      var bad = false;
      for (var t = 0; t < 14400; t += 60) {
        if (t == 2700) {
          for (final lev in ['feedFlow', 'refluxFlow', 'reboilerDuty']) {
            sim.setLever(lev, sim.lever(lev) * 1.25);
          }
        }
        sim.advance(60);
        final s = sim.snapshot();
        for (final v in [...s.stages.holdup, ...s.stages.x, s.kpis.xD, s.kpis.xB, s.kpis.columnDp]) {
          if (v.isNaN || v.isInfinite) bad = true;
        }
        if (s.stages.holdup.any((h) => h < 0)) bad = true;
        if (sim.halted) bad = true;
      }
      expect(bad, isFalse, reason: c.$1);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
