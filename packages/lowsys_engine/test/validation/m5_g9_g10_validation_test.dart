// M5 validation (validator, engine 9348b7c, re-run at fb33c07; spec 4ee46dd): VC-28.8, G9 and
// G10 are completable by their hints. An automated player applies each
// hint's values as soon as the hint unlocks, runs at fast-forward and
// answers with the correct values; real utilities, PC-101 in AUTO, E = 1,
// noise off. Sim times are printed for the scenario JSON comments.
library;

import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const _kmolh = 1000 / 3600;
double _k(double v) => v / _kmolh;

/// Safety bookkeeping of VC-28.8: no relief lift, no level outside 5–95 %,
/// no thermoOutOfRange, at any sample.
class _Safety {
  double maxRelief = 0, minLevel = 100, maxLevel = 0;
  bool outOfRange = false;
  void sample(SimSnapshot s) {
    final c = s.condenser!;
    if (c.nRelief > maxRelief) maxRelief = c.nRelief;
    for (final l in [s.kpis.drumLevelPct, s.kpis.sumpLevelPct]) {
      if (l < minLevel) minLevel = l;
      if (l > maxLevel) maxLevel = l;
    }
    if (s.solverHealth.thermoOutOfRange) outOfRange = true;
  }

  void expectSafe(Simulator sim) {
    expect(maxRelief, 0, reason: 'relief lifted');
    expect(minLevel, greaterThanOrEqualTo(5));
    expect(maxLevel, lessThanOrEqualTo(95));
    expect(outOfRange, isFalse, reason: 'thermoOutOfRange');
    expect(sim.safetyLevelViolationSeconds, 0);
  }
}

/// Advances in [chunk]-s pieces until [done] or the scenario's time limit;
/// [each] sees every chunk's snapshot. Returns the scenario time.
double _runUntil(Simulator sim, bool Function() done,
    {double chunk = 10, void Function(SimSnapshot)? each}) {
  final run = sim.scenario!;
  while (!done() && run.elapsed < run.def.timeLimit) {
    sim.advanceFast(chunk);
    each?.call(sim.snapshot());
  }
  return run.elapsed;
}

void main() {
  test('G10 hint path: D 48.0, x_D 0.8567, x_B 0.3630; x_B never below 0.3335; o3 = findAzeotropes rounded; no safety events',
      () {
    final sim = Simulator(Presets.byId('ac'), options: const SimOptions(seed: 3), warmStart: false);
    sim.startScenario(Scenarios.byId('G10_other_azeotrope'));
    final run = sim.scenario!;
    var s = sim.snapshot();
    expect(s.tier, ThermoTier.t3);
    expect(s.kpis.xD, closeTo(0.96153, 2e-4));
    expect(s.kpis.xB, closeTo(0.37842, 2e-4));
    final safe = _Safety()..sample(s);
    var minXb = s.kpis.xB;
    // hint 1 at 0
    sim.setLever('refluxFlow', 140 * _kmolh);
    final t1 = _runUntil(sim, () => run.objectiveMet('o1'), each: (q) {
      safe.sample(q);
      if (q.kpis.xB < minXb) minXb = q.kpis.xB;
    });
    expect(run.objectiveMet('o1'), isTrue, reason: 'o1 within the time limit');
    s = sim.snapshot();
    expect(_k(s.kpis.d), closeTo(48.0, 0.3));
    expect(s.kpis.xD, closeTo(0.8567, 0.002));
    expect(s.kpis.xB, closeTo(0.3630, 0.001));
    expect(minXb, greaterThan(0.3335), reason: 'x_B approaches the azeotrope from above');
    expect(run.submitAnswer('o2', 1).correct, isTrue);
    final az = TxyData.findAzeotropes(sim.thermo, s.kpis.pTop).single;
    final read = (az.x * 1000).round() / 1000;
    expect(read, closeTo(0.333, 0.002));
    expect(az.maximumBoiling, isTrue);
    expect(run.submitAnswer('o3', read).correct, isTrue);
    expect(run.allAchieved, isTrue);
    safe.expectSafe(sim);
    // record (VC-28.8): sim time to o1
    print('G10: o1 at ${(t1 / 3600).toStringAsFixed(2)} h of 24 h (o1 latched at '
        '${(run.objectiveStates.firstWhere((o) => o.id == 'o1').achievedAt! / 3600).toStringAsFixed(2)} h)');
    expect(t1, lessThan(0.5 * run.def.timeLimit), reason: 'OPEN_ITEMS rule: raise if over half the limit');
  });

  test('G9 shipped JSON follows the 2026-10-13 spec: o3 has no `steady`, hint 2 does not say "run to steady state"',
      () {
    final def = Scenarios.byId('G9_azeotrope_wall');
    final j = jsonDecode(Scenarios.jsonOf('G9_azeotrope_wall')) as Map<String, Object?>;
    final o3 = (j['objectives']! as List).cast<Map<String, Object?>>().firstWhere((o) => o['id'] == 'o3');
    expect(jsonEncode(o3['when']), isNot(contains('"steady"')));
    // the new text says "there is no need to wait for steady state"
    expect(def.hints[1].text.toLowerCase(), isNot(contains('run to steady state')));
  });

  /// Plays the shipped G9 (its o3 is the 2026-10-13 one from fb33c07) to o5.
  /// [lowCwHold]: the hint-3 values without P_top for that many seconds
  /// first, sampled every second into [pDev] and [cwOp]. [horizon]: run up
  /// to this many time limits.
  ({double tO1, double tSwitch, double tO3, double tO5, Simulator sim, _Safety safe}) playG9(
      {int lowCwHold = 0,
      List<double>? pDev,
      List<double>? cwOp,
      double horizon = 1}) {
    final sim = Simulator(Presets.byId('ew'), options: const SimOptions(seed: 3), warmStart: false);
    sim.startScenario(Scenarios.byId('G9_azeotrope_wall'));
    final run = sim.scenario!;
    final s0 = sim.snapshot();
    expect(s0.tier, ThermoTier.t3);
    expect(s0.kpis.xD, closeTo(0.88693, 2e-4));
    final safe = _Safety()..sample(s0);
    bool within() => run.elapsed < horizon * run.def.timeLimit;
    // hint 1 at 0
    sim.setLever('refluxFlow', 105 * _kmolh);
    while (!run.objectiveMet('o1') && within()) {
      sim.advanceFast(10);
      safe.sample(sim.snapshot());
    }
    final tO1 = run.elapsed;
    expect(run.objectiveMet('o1'), isTrue);
    final s1 = sim.snapshot();
    expect(s1.kpis.xD, closeTo(0.8902, 0.001));
    expect(s1.kpis.refluxRatio, closeTo(17.6, 0.5));
    expect(_k(s1.kpis.d), closeTo(5.97, 0.2));
    expect(run.submitAnswer('o2', 0.8956).correct, isTrue);
    // hint 2: Tier 1
    sim.setTier(ThermoTier.t1);
    final tSwitch = run.elapsed;
    while (!run.objectiveMet('o3') && within()) {
      sim.advanceFast(10);
      safe.sample(sim.snapshot());
    }
    final tO3 = run.elapsed;
    expect(run.objectiveMet('o3'), isTrue);
    expect(sim.snapshot().kpis.xD, greaterThanOrEqualTo(0.95));
    expect(run.submitAnswer('o4', 0).correct, isTrue);
    // hint 3: back to Tier 3; feed 60, reflux 60, duty 748 kW, P_top 0.5 bar(a)
    sim.setTier(ThermoTier.t3);
    sim.setLever('feedFlow', 60 * _kmolh);
    sim.setLever('refluxFlow', 60 * _kmolh);
    sim.setLever('reboilerDuty', 748e3);
    final sp = sim.lever('pTop');
    for (var t = 0; t < lowCwHold; t++) {
      sim.advance(1);
      final s = sim.snapshot();
      pDev?.add(s.kpis.pTop - sp);
      cwOp?.add(s.condenser!.cwOp);
      safe.sample(s);
    }
    sim.setLever('pTop', 50000);
    while (!run.objectiveMet('o5') && within()) {
      sim.advanceFast(10);
      safe.sample(sim.snapshot());
    }
    return (tO1: tO1, tSwitch: tSwitch, tO3: tO3, tO5: run.elapsed, sim: sim, safe: safe);
  }

  void checkHint3(Simulator sim) {
    final run = sim.scenario!;
    expect(run.objectiveMet('o5'), isTrue, reason: 'o5 (0.5 bar(a), x_D ≥ 0.897, steady)');
    final s = sim.snapshot();
    expect(s.kpis.pTop, closeTo(50000, 500));
    expect(_k(s.kpis.d), closeTo(5.97, 0.2));
    expect(s.kpis.xD, closeTo(0.9005, 0.002));
    expect(s.kpis.xD, greaterThanOrEqualTo(0.897));
    final cw = 100 * s.condenser!.cwFlow / sim.config.condenser.cwMaxFlow;
    expect(cw, inInclusiveRange(25, 45), reason: 'CW $cw % of m_cw,max');
    final az = TxyData.findAzeotropes(sim.thermo, s.kpis.pTop).single;
    expect(az.x, closeTo(0.9108, 0.002));
    expect(az.t - 273.15, closeTo(61.33, 0.1));
    expect(s.stages.t[0] - 273.15, closeTo(61.33, 0.1));
    expect(run.submitAnswer('o6', 0).correct, isTrue);
    expect(run.allAchieved, isTrue);
  }

  group('G9 hint path', () {
    late ({double tO1, double tSwitch, double tO3, double tO5, Simulator sim, _Safety safe}) r;
    setUpAll(() {
      r = playG9(horizon: 2);
      final lim = r.sim.scenario!.def.timeLimit;
      print('G9: o1 ${(r.tO1 / 3600).toStringAsFixed(2)} h; Tier-1 switch → o3 '
          '${((r.tO3 - r.tSwitch) / 3600).toStringAsFixed(2)} h; o5 ${(r.tO5 / 3600).toStringAsFixed(2)} h '
          '(${((r.tO5 - r.tO3) / 3600).toStringAsFixed(2)} h after hint 3); limit ${(lim / 3600).toStringAsFixed(0)} h');
    });
    test('checkpoints: x_D 0.8902 / R 17.6; Tier 1 x_D ≥ 0.95 held 300 s within 1 h; 0.5 bar(a): D 5.97, x_D 0.9005, CW 25–45 %, 61.33 °C; no safety events',
        () {
      checkHint3(r.sim);
      r.safe.expectSafe(r.sim);
      expect(r.tO3 - r.tSwitch, lessThan(3600), reason: 'o3 latches without steady');
    });
    test('every objective within half the time limit (ce171db: limit 432 000 s, par 216 000; hint path bound 216 000 s)',
        () {
      final lim = r.sim.scenario!.def.timeLimit;
      expect(lim, 432000);
      expect(r.sim.scenario!.def.parTime, 216000);
      expect(r.tO5, lessThan(lim / 2));
    });
  });

  group('G9 learner path at low CW (feed turned down at 1 atm, P_top 1 h later)', () {
    final dev = <double>[], ops = <double>[];
    late ({double tO1, double tSwitch, double tO3, double tO5, Simulator sim, _Safety safe}) r;
    double amp(List<double> v) =>
        v.reduce((a, b) => a > b ? a : b) - v.reduce((a, b) => a < b ? a : b);
    setUpAll(() {
      r = playG9(lowCwHold: 3600, pDev: dev, cwOp: ops, horizon: 2);
      final maxDev = dev.fold(0.0, (m, e) => e.abs() > m ? e.abs() : m);
      final iMax = dev.indexWhere((e) => e.abs() == maxDev);
      final back = dev.lastIndexWhere((e) => e.abs() > 2000) + 1;
      print('G9 low-CW hour: peak P − SP ${dev[iMax].toStringAsFixed(0)} Pa at $iMax s, back within ±2 kPa '
          'at $back s; peak-to-peak first 20 min ${amp(dev.sublist(0, 1200)).toStringAsFixed(0)} Pa, '
          'last 20 min ${amp(dev.sublist(2400)).toStringAsFixed(1)} Pa; CW OP at 1 h ${ops.last.toStringAsFixed(1)} %');
    });
    test('no sustained oscillation (last 20 min ≤ first 20 min), back within ±2 kPa in 10 min, CW near 9 %, path completes',
        () {
      expect(amp(dev.sublist(2400)), lessThanOrEqualTo(amp(dev.sublist(0, 1200))));
      expect(amp(dev.sublist(2400)), lessThan(100));
      for (final e in dev.sublist(600)) {
        expect(e.abs(), lessThanOrEqualTo(2000));
      }
      expect(ops.last, closeTo(9, 2), reason: 'VC-28.8: CW valve near 9 % open');
      checkHint3(r.sim);
    });
    test('VC-28.8 as restated (ce171db): peak |P − SP| ≤ 12 kPa; within ±2 kPa from 10 min on; CW 6–15 %; no safety events',
        () {
      for (final e in dev) {
        expect(e.abs(), lessThanOrEqualTo(12000));
      }
      for (final e in dev.sublist(600)) {
        expect(e.abs(), lessThanOrEqualTo(2000));
      }
      expect(amp(dev.sublist(2400)), lessThanOrEqualTo(amp(dev.sublist(0, 1200))));
      expect(ops.last, inInclusiveRange(6, 15));
      r.safe.expectSafe(r.sim);
    });
  });
}
