// Shared fixtures for the VALIDATION.md suite. Every touch-point with the
// engine API lives here (ENGINE_API.md names), so an API rename is a
// one-file change. The reference calculators in `reference/` never import
// the engine; this file is the only bridge between the two.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/cmo_steady_reference.dart';

/// 1 kmol/h in mol/s (VALIDATION.md §0).
const double kmolh = 1000 / 3600;

double toKmolh(double molPerS) => molPerS / kmolh;

/// B-T default preset (`bt`) with optional scenario-style overrides
/// (ENGINE_API.md §11.1 dotted paths), always in ideal hydraulics.
ColumnConfig btConfig({Map<String, Object?> overrides = const {}}) {
  var cfg = Presets.byId(Presets.bt);
  if (overrides.isNotEmpty) cfg = cfg.applyOverrides(overrides);
  return cfg.copyWith(hydraulics: HydraulicsMode.ideal);
}

/// Builds the reference column that matches [cfg] and the current lever
/// values of [sim] (flows in kmol/h, as the reference uses).
CmoColumn referenceColumnFor(Simulator sim) {
  final cfg = sim.config;
  return CmoColumn(
    alpha: cfg.tier1Alpha![0] / cfg.tier1Alpha![1],
    nTrays: cfg.trayCount,
    feedTray: sim.lever('feedStage').round(),
    f: toKmolh(sim.lever('feedFlow')),
    z: sim.lever('feedZ.benzene'),
    q: sim.lever('feedQ'),
    l0: toKmolh(sim.lever('refluxFlow')),
    vB: toKmolh(sim.lever('boilup')),
    e: sim.lever('murphree'),
  );
}

/// A new simulator. Cold start by default so tests do not depend on the
/// shipped steady cache (VC-4.15 tests the cache separately).
Simulator newSim(ColumnConfig cfg,
        {SimOptions options = const SimOptions(), bool warmStart = false}) =>
    Simulator(cfg, options: options, warmStart: warmStart);

/// Convenience view over a snapshot: binary light-component profiles.
class Profile {
  final SimSnapshot s;
  Profile(this.s);
  int get n => s.stages.n; // stages 0..N+1
  int get nTrays => n - 2;
  double x(int j) => s.stages.x[j * s.stages.nc];
  double y(int j) => s.stages.y[j * s.stages.nc];
  double yStar(int j) => s.stages.yStar[j * s.stages.nc];
  double holdup(int j) => s.stages.holdup[j];
  double liquidDown(int j) => s.stages.liquidDown[j];
  double vaporUp(int j) => s.stages.vaporUp[j];
  double get xD => s.kpis.xD;
  double get xB => s.kpis.xB;
  double get dKmolh => toKmolh(s.kpis.d);
  double get bKmolh => toKmolh(s.kpis.b);
  double get boilupKmolh => toKmolh(s.kpis.boilup);
  double get drumLevel => s.kpis.drumLevelPct;
  double get sumpLevel => s.kpis.sumpLevelPct;

  /// Total light-component inventory over every stage (mol).
  double lightInventory() {
    var sum = 0.0;
    for (var j = 0; j < n; j++) {
      sum += s.stages.holdup[j] * x(j);
    }
    return sum;
  }

  double totalInventory() {
    var sum = 0.0;
    for (var j = 0; j < n; j++) {
      sum += s.stages.holdup[j];
    }
    return sum;
  }
}

Profile prof(Simulator sim) => Profile(sim.snapshot());

/// Runs to steady state and fails the test if the monitor never passed.
Profile runSteady(Simulator sim, {bool fastForward = true}) {
  final r = sim.runToSteadyState(fastForward: fastForward);
  expect(r.reached, isTrue,
      reason: 'steady state not reached in ${r.simSeconds} s '
          '(residual ${r.residual})');
  return prof(sim);
}

/// Asserts the physical sanity invariants of one snapshot: finite numbers,
/// compositions in [0, 1], holdups >= 0, levels in [0, 100], no fatal flag.
void expectPhysical(SimSnapshot s, {String where = ''}) {
  final st = s.stages;
  for (var i = 0; i < st.x.length; i++) {
    expect(st.x[i].isFinite, isTrue, reason: 'x[$i] not finite $where');
    expect(st.x[i], inInclusiveRange(-1e-12, 1 + 1e-12),
        reason: 'x[$i] outside [0,1] $where');
    expect(st.y[i].isFinite, isTrue, reason: 'y[$i] not finite $where');
    expect(st.y[i], inInclusiveRange(-1e-12, 1 + 1e-12),
        reason: 'y[$i] outside [0,1] $where');
  }
  for (var j = 0; j < st.n; j++) {
    expect(st.holdup[j].isFinite, isTrue,
        reason: 'holdup[$j] not finite $where');
    expect(st.holdup[j], greaterThanOrEqualTo(-1e-12),
        reason: 'negative holdup on stage $j $where');
    expect(st.liquidDown[j].isFinite && st.liquidDown[j] >= -1e-12, isTrue,
        reason: 'L[$j] negative or not finite $where');
    expect(st.vaporUp[j].isFinite && st.vaporUp[j] >= -1e-12, isTrue,
        reason: 'V[$j] negative or not finite $where');
  }
  for (final v in [s.kpis.xD, s.kpis.xB, s.kpis.d, s.kpis.b, s.kpis.boilup]) {
    expect(v.isFinite, isTrue, reason: 'KPI not finite $where');
  }
  expect(s.kpis.xD, inInclusiveRange(-1e-12, 1 + 1e-12), reason: 'xD $where');
  expect(s.kpis.xB, inInclusiveRange(-1e-12, 1 + 1e-12), reason: 'xB $where');
  expect(s.kpis.d, greaterThanOrEqualTo(-1e-12), reason: 'D < 0 $where');
  expect(s.kpis.b, greaterThanOrEqualTo(-1e-12), reason: 'B < 0 $where');
  expect(s.kpis.drumLevelPct.isFinite && s.kpis.drumLevelPct >= -1e-9, isTrue,
      reason: 'drum level $where');
  expect(s.kpis.sumpLevelPct.isFinite && s.kpis.sumpLevelPct >= -1e-9, isTrue,
      reason: 'sump level $where');
  expect(s.solverHealth.fatal, isFalse, reason: 'solver fatal $where');
}

/// Advances [sim] by [seconds] in slices of [sample] seconds and runs
/// [onSample] after each slice (the snapshot is taken for you).
void advanceSampling(Simulator sim, double seconds, double sample,
    void Function(double t, SimSnapshot s) onSample) {
  final t0 = sim.time;
  while (sim.time - t0 < seconds - 1e-9) {
    sim.advance(math.min(sample, seconds - (sim.time - t0)));
    onSample(sim.time - t0, sim.snapshot());
  }
}

/// Max |a − b| over two profiles of equal length.
double maxAbsDiff(Float64List a, Float64List b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

/// Mass-balance residual of the light component at a steady state, relative
/// to the feed: |F z − D xD − B xB| / (F z).
double balanceResidual(Simulator sim) {
  final p = prof(sim);
  final f = sim.lever('feedFlow');
  final z = sim.lever('feedZ.benzene');
  return ((f * z - p.s.kpis.d * p.xD - p.s.kpis.b * p.xB) / (f * z)).abs();
}
