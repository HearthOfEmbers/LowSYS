// M2 fixtures: full tray hydraulics, faults and units. Every engine
// touch-point for M2 lives here (ENGINE_API.md §4, §7.1, §9, §12 names).
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

export 'fixtures.dart';

/// B-T preset in full hydraulics (PHYSICS.md §5 defaults).
ColumnConfig btFull({Map<String, Object?> overrides = const {}}) {
  var cfg = Presets.byId(Presets.bt);
  if (overrides.isNotEmpty) cfg = cfg.applyOverrides(overrides);
  return cfg.copyWith(hydraulics: HydraulicsMode.full);
}

/// VC-12.4 "Load +x %": F stays at 100 kmol/h; L0 and V_B both gain the
/// same absolute amount, x % of the design V_B (150): +20 % = +30 kmol/h on
/// each, so D stays at 50 and only the internal traffic rises.
void addLoad(Simulator sim, double fraction) {
  sim.setLever('refluxFlow', (100 + 150 * fraction) * kmolh);
  sim.setLever('boilup', (150 + 150 * fraction) * kmolh);
}

/// VC-12.4 "Turndown to x %": F, L0 and V_B all scaled by the factor.
void scaleLoad(Simulator sim, double factor) {
  sim.setLever('feedFlow', 100 * kmolh * factor);
  sim.setLever('refluxFlow', 100 * kmolh * factor);
  sim.setLever('boilup', 150 * kmolh * factor);
}

/// Per-tray hydraulic indicators of a snapshot (trays 1..N).
class Hyd {
  final SimSnapshot s;
  Hyd(this.s);
  int get nTrays => s.stages.n - 2;
  double dp(int j) => s.stages.dp[j];
  double jetFlood(int j) => s.stages.jetFlood[j];
  double dcFlood(int j) => s.stages.dcFlood[j];
  double frothFill(int j) => s.stages.frothFill[j];
  double stability(int j) => s.stages.stability[j];
  double weepFrac(int j) => s.stages.weepFrac[j];
  double entrain(int j) => s.stages.entrain[j];
  double weep(int j) => s.stages.weep[j];
  double hcl(int j) => s.stages.hcl[j];
  double froth(int j) => s.stages.froth[j];
  double efficiency(int j) => s.stages.efficiency[j];
  double holdup(int j) => s.stages.holdup[j];
  bool dcLimited(int j) => (s.stages.flags[j] & 1) != 0;
  bool dumping(int j) => (s.stages.flags[j] & 2) != 0;
  bool overflowing(int j) => (s.stages.flags[j] & 4) != 0;
  bool flooding(int j) => (s.stages.flags[j] & 16) != 0;

  /// Column ΔP (Pa) from the KPI.
  double get columnDp => s.kpis.columnDp;
  double get maxFloodPct => s.kpis.maxFloodPct;

  double maxOverTrays(double Function(int j) f) {
    var m = -double.infinity;
    for (var j = 1; j <= nTrays; j++) {
      m = math.max(m, f(j));
    }
    return m;
  }

  double sumDp(int from, int to) {
    var sum = 0.0;
    for (var j = from; j <= to; j++) {
      sum += dp(j);
    }
    return sum;
  }

  int countTrays(bool Function(int j) pred) {
    var c = 0;
    for (var j = 1; j <= nTrays; j++) {
      if (pred(j)) c++;
    }
    return c;
  }
}

Hyd hyd(Simulator sim) => Hyd(sim.snapshot());

/// Injects a tray fault on trays [from]..[to] (ENGINE_API.md §9).
FaultId injectTrayFault(Simulator sim, FaultType type,
    {required int from,
    int? to,
    double severity = 1.0,
    double ramp = 0,
    double? onset,
    Map<String, Object?> params = const {}}) {
  return sim.faults.inject(FaultSpec(
    type: type,
    location: FaultLocation.stages(from, to ?? from),
    severity: severity,
    onset: onset ?? sim.time,
    ramp: ramp,
    params: params,
  ));
}

/// Injects a feed fault (F07).
FaultId injectFeedFault(Simulator sim,
        {double severity = 1.0,
        double ramp = 0,
        Map<String, Object?> params = const {
          'dz': [0.15, -0.15]
        }}) =>
    sim.faults.inject(FaultSpec(
      type: FaultType.feedComposition,
      location: FaultLocation.feed(0),
      severity: severity,
      onset: sim.time,
      ramp: ramp,
      params: params,
    ));

/// Hydraulic robustness assertions (VC-12.4): no NaN, no negative holdup,
/// solver not fatal, plus the generic physical bounds.
void expectHydraulicallySane(SimSnapshot s, {String where = ''}) {
  expectPhysical(s, where: where);
  final st = s.stages;
  for (var j = 1; j < st.n - 1; j++) {
    for (final (name, v) in [
      ('dp', st.dp[j]),
      ('jetFlood', st.jetFlood[j]),
      ('dcFlood', st.dcFlood[j]),
      ('frothFill', st.frothFill[j]),
      ('weepFrac', st.weepFrac[j]),
      ('entrain', st.entrain[j]),
      ('weep', st.weep[j]),
      ('hcl', st.hcl[j]),
    ]) {
      expect(v.isFinite, isTrue, reason: '$name[$j] not finite $where');
      expect(v, greaterThanOrEqualTo(-1e-12),
          reason: '$name[$j] negative $where');
    }
    expect(st.weepFrac[j], lessThanOrEqualTo(1 + 1e-12),
        reason: 'weepFrac[$j] > 1 $where');
    expect(st.efficiency[j], inInclusiveRange(-1e-12, 1 + 1e-12),
        reason: 'efficiency[$j] $where');
  }
  expect(s.kpis.columnDp.isFinite && s.kpis.columnDp >= 0, isTrue,
      reason: 'column ΔP $where');
  expect(s.solverHealth.fatal, isFalse, reason: 'fatal $where');
}

/// Exact component closure over [steps] steps using StepDebug (VC-5.1 form).
List<double> exactClosureSteps(Simulator sim, int steps,
    {void Function(int k)? onStep}) {
  final nc = sim.config.nc;
  double inv(int i) {
    final p = prof(sim);
    var sum = 0.0;
    for (var j = 0; j < p.n; j++) {
      sum += p.s.stages.holdup[j] * p.s.stages.x[j * nc + i];
    }
    return sum;
  }

  final inv0 = [for (var i = 0; i < nc; i++) inv(i)];
  final fin = List<double>.filled(nc, 0), fout = List<double>.filled(nc, 0);
  for (var k = 0; k < steps; k++) {
    sim.step();
    onStep?.call(k);
    final d = sim.debug;
    for (var i = 0; i < nc; i++) {
      fin[i] += d.feedRate[i] * d.dt;
      fout[i] += (d.distillateRate[i] + d.bottomsRate[i]) * d.dt;
    }
  }
  return [
    for (var i = 0; i < nc; i++)
      ((inv(i) - inv0[i]) - fin[i] + fout[i]).abs() / math.max(fin[i], 1e-300)
  ];
}
