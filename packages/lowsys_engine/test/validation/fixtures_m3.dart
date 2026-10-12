// M3 fixtures: control loops, instruments, alarms, cross-checks, scenarios.
// Every M3 engine touch-point lives here (ENGINE_API.md §6–§11 names).
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';

import 'fixtures_m2.dart';

export 'fixtures_m2.dart';

/// Reading of one instrument tag from a snapshot.
InstrumentReading reading(SimSnapshot s, String tag) =>
    s.instruments.firstWhere((r) => r.tag == tag);

ValveSnapshot valveOf(SimSnapshot s, String id) =>
    s.valves.firstWhere((v) => v.id == id);

LoopSnapshot loopOf(SimSnapshot s, LoopTag tag) =>
    s.loops.firstWhere((l) => l.tag == tag);

CrossCheckResult? checkOf(SimSnapshot s, String id) {
  for (final c in s.crossChecks) {
    if (c.id == id) return c;
  }
  return null;
}

bool hasAlarm(SimSnapshot s, String id) => s.alarms.any((a) => a.id == id);

/// Instrument fault (F19 bias/drift/stuck or F28 modes) on one tag.
FaultId injectInstrumentFault(Simulator sim, String tag, String kind,
    {double severity = 1.0, int sign = 1, double ramp = 0, double? onset}) {
  const f19 = {'bias', 'drift', 'stuck'};
  return sim.faults.inject(FaultSpec(
    type: f19.contains(kind) ? FaultType.instrument : FaultType.transmitter,
    location: FaultLocation.tag(tag),
    severity: severity,
    onset: onset ?? sim.time,
    ramp: ramp,
    params: {'kind': kind, if (kind == 'bias' || kind == 'drift') 'sign': sign},
  ));
}

FaultId injectValveFault(Simulator sim, String valveId, String kind,
        {double? onset}) =>
    sim.faults.inject(FaultSpec(
      type: FaultType.valve,
      location: FaultLocation.tag(valveId),
      severity: 1.0,
      onset: onset ?? sim.time,
      ramp: 0,
      params: {'kind': kind},
    ));

/// B-T Tier 1, ideal hydraulics, steady, then noise on/off as requested.
Simulator steadyT1(
    {bool noise = false, int seed = 1, bool full = false, int view = 0}) {
  final sim =
      newSim(full ? btFull() : btConfig(), options: SimOptions(seed: seed));
  runSteady(sim);
  if (noise) sim.setLever('noise', 1);
  if (view != 0) sim.setLever('view', view.toDouble());
  return sim;
}

/// Samples [tag] every [sample] s for [seconds] and returns the readings.
List<double> sampleReadings(Simulator sim, String tag, double seconds,
    {double sample = 0.5}) {
  final out = <double>[];
  advanceSampling(
      sim, seconds, sample, (t, s) => out.add(reading(s, tag).value));
  return out;
}

double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

double stdDev(List<double> v) {
  final m = mean(v);
  return math
      .sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length);
}

/// First time (relative) at which [pred] holds, sampling every [sample] s
/// for up to [seconds]; null if never.
double? firstTime(
    Simulator sim, double seconds, bool Function(SimSnapshot s) pred,
    {double sample = 5}) {
  double? hit;
  advanceSampling(sim, seconds, sample, (t, s) {
    if (hit == null && pred(s)) hit = t;
  });
  return hit;
}

/// Fraction of evaluations over the run at which [pred] holds.
double fractionOf(
    Simulator sim, double seconds, bool Function(SimSnapshot s) pred,
    {double sample = 5}) {
  var n = 0, k = 0;
  advanceSampling(sim, seconds, sample, (t, s) {
    n++;
    if (pred(s)) k++;
  });
  return k / n;
}

bool checkFails(SimSnapshot s, String id) =>
    checkOf(s, id)?.status == CheckStatus.fail;
bool checkOk(SimSnapshot s, String id) =>
    checkOf(s, id)?.status == CheckStatus.ok;

double signalLookRatio(SimSnapshot s, String tag) {
  final r = reading(s, tag);
  return r.sigma5min / r.typicalSigma;
}

/// Reads a TRUE (unmasked) metric while the simulator may be in plant view:
/// the `view` lever is a pure masking switch (PHYSICS.md §10.9), so flipping
/// it for one snapshot reveals the model values without touching the state.
class TrueView {
  final Simulator sim;
  TrueView(this.sim);
  double read(String path) {
    final v = sim.lever('view');
    if (v != 0) sim.setLever('view', 0);
    final s = sim.snapshot();
    if (v != 0) sim.setLever('view', v);
    switch (path) {
      case 'kpi.xD':
        return s.kpis.xD;
      case 'kpi.xB':
        return s.kpis.xB;
      case 'sump.levelPct':
        return s.kpis.sumpLevelPct;
      case 'drum.levelPct':
        return s.kpis.drumLevelPct;
      default:
        throw ArgumentError('unknown true metric $path');
    }
  }
}

/// `McCabeThieleData.available` arrives with the M3 scenario layer; until
/// then an unavailable diagram is one with no staircase.
bool mccabeAvailable(Object mt) {
  try {
    return (mt as dynamic).available as bool;
  } on NoSuchMethodError {
    return (mt as McCabeThieleData).staircase.isNotEmpty;
  }
}
