import 'package:lowsys_engine/lowsys_engine.dart';

/// kmol/h to mol/s.
double kmolh(double v) => v / 3.6;

/// Fresh simulator on the default B-T preset at its steady state (warm start).
Simulator btSim(
        {ColumnConfig? config,
        SimOptions options = const SimOptions(),
        bool warm = true}) =>
    Simulator(config ?? Presets.byId('bt'), options: options, warmStart: warm);

/// Cold simulator run to steady state with the given lever settings.
Simulator btSteady(Map<String, double> levers,
    {ColumnConfig? config, SimOptions options = const SimOptions()}) {
  final sim = Simulator(config ?? Presets.byId('bt'),
      options: options, warmStart: false);
  levers.forEach(sim.setLever);
  sim.runToSteadyState();
  return sim;
}
