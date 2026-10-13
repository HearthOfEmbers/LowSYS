// Shared helpers of the M8 coder tests (packed sections).
import 'package:lowsys_engine/lowsys_engine.dart';

/// The H7 beds: both narrowed to D_bed = 1.0 m through `overrides.sections` (ENGINE_API.md 11.11).
final List<Map<String, Object?>> h7Sections = [
  {'kind': 'packed', 'bedHeight': 4.5, 'packingId': 'struct250', 'diameter': 1.0, 'designLiquidFlux': 1.9},
  {'kind': 'packed', 'bedHeight': 4.5, 'packingId': 'struct250', 'diameter': 1.0, 'designLiquidFlux': 4.0},
];

/// `bt_packed` at the given tier and hydraulics (cold start, no warm start).
Simulator packedSim({String tier = 't1', String hydraulics = 'full', int seed = 1, bool noise = false}) => Simulator(
    Presets.byId('bt_packed').applyOverrides({'tier': tier, 'hydraulics': hydraulics}),
    options: SimOptions(seed: seed, measurementNoise: noise),
    warmStart: false);

/// The H7 column: `bt_packed`, Tier 2, full hydraulics, D_bed 1.0 m, CW at 15 C.
Simulator h7Sim({int seed = 1, bool noise = false}) {
  final sim = Simulator(
      Presets.byId('bt_packed').applyOverrides({'tier': 't2', 'hydraulics': 'full', 'sections': h7Sections}),
      options: SimOptions(seed: seed, measurementNoise: noise),
      warmStart: false);
  sim.setLever('cwInletT', 288.15);
  return sim;
}

Simulator steady(Simulator s) {
  final r = s.runToSteadyState(maxSimSeconds: 172800);
  if (!r.reached) throw StateError('no steady state');
  return s;
}

const double kmolh = 1000 / 3600;
