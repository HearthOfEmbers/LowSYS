/// LowSYS engine: pure-Dart dynamic distillation column model (no Flutter dependency).
library;

export 'src/config/column_config.dart';
export 'src/config/presets.dart';
export 'src/config/tray_geometry.dart';
export 'src/control/control_system.dart';
export 'src/core/ids.dart';
export 'src/core/quantity.dart';
export 'src/core/rng.dart';
export 'src/control/alarms.dart' show AlarmManager, JournalEntry;
export 'src/control/cross_checks.dart';
export 'src/control/trend_buffer.dart';
export 'src/explain/explain_engine.dart' show texNum;
export 'src/explain/explain_types.dart';
export 'src/faults/fault_manager.dart';
export 'src/faults/fault_spec.dart';
export 'src/math/banded_solver.dart';
export 'src/model/tray_hydraulics.dart'
    show TrayCorrelations, TrayGeometryDerived;
export 'src/model/column_state.dart' show StepDebug;
export 'src/runner/local_sim_runner.dart';
export 'src/runner/sim_runner.dart';
export 'src/sim/lever_spec.dart';
export 'src/sim/simulator.dart';
export 'src/snapshot/mccabe_thiele.dart';
export 'src/snapshot/sim_snapshot.dart';
export 'src/thermo/component.dart';
export 'src/thermo/thermo_factory.dart';
export 'src/thermo/thermo_model.dart';
export 'src/thermo/tier1_constant_alpha.dart';
export 'src/scenario/drill.dart';
export 'src/scenario/predicate.dart';
export 'src/scenario/scoring.dart';
export 'src/scenario/scenario_def.dart';
export 'src/scenario/scenario_library.dart';
export 'src/scenario/scenario_runner.dart';
