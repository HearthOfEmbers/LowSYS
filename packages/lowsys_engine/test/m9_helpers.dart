// Shared helpers of the M9 coder tests (crude unit).
import 'package:lowsys_engine/lowsys_engine.dart';

const double crudeRate0 = 0.0368056; // m3/s, 132.5 m3/h

Simulator crudeSim({bool noise = false, int seed = 1, Map<String, double> levers = const {}}) {
  final s = Simulator(Presets.byId('crude'), options: SimOptions(seed: seed, measurementNoise: noise));
  for (final e in levers.entries) {
    s.setLever(e.key, e.value);
  }
  return s;
}

Simulator steadyC(Simulator s, {double max = 172800}) {
  final r = s.runToSteadyState(maxSimSeconds: max);
  if (!r.reached) {
    // dry draws wander very slowly; accept a state that moves less than 1e-3 per minute
    if (r.residual > 5e-3) throw StateError('no steady state, residual ${r.residual}');
  }
  return s;
}

CrudeProductKpis kpiOf(Simulator s) => s.snapshot().kpis.crude!;

double instr(Simulator s, String tag) => s.snapshot().instruments.firstWhere((i) => i.tag == tag).value;

FaultId injectF24(Simulator s, String point, double sev, {double ramp = 60}) => s.faults
    .inject(FaultSpec(type: FaultType.strippingSteamLoss, location: FaultLocation.steam(point), severity: sev, onset: s.time, ramp: ramp));

FaultId injectF25(Simulator s, double sev) => s.faults.inject(
    FaultSpec(type: FaultType.pumparoundTrip, location: const FaultLocation.equipment('pumparound'), severity: sev, onset: s.time));

FaultId injectF26(Simulator s, double sev, {double ramp = 300}) => s.faults.inject(FaultSpec(
    type: FaultType.cotUpset,
    location: const FaultLocation.equipment('furnace'),
    severity: sev,
    onset: s.time,
    ramp: ramp,
    params: const {'dT': -15}));

double c(double k) => k - 273.15;
