import '../config/column_config.dart';
import '../core/ids.dart';
import '../sim/lever_spec.dart';
import '../sim/simulator.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/thermo_model.dart';

/// The only thing the app uses to talk to the engine (ENGINE_API.md 6.6). The M10 move to a
/// background isolate is a local change behind this interface.
abstract class SimRunner {
  Future<void> load(ColumnConfig config,
      {SimOptions options = const SimOptions(), bool warmStart = true});
  Future<void> loadSaved(Map<String, Object?> saved);

  /// Advance by up to [simSeconds] but stop when [wallBudget] is used. Returns the sim time actually advanced.
  Future<double> advance(double simSeconds, Duration wallBudget);
  Future<SimSnapshot> snapshot();
  Future<void> setLever(LeverId id, double value);
  Future<void> setTier(ThermoTier t);
  Future<void> setLoopMode(LoopTag tag, LoopMode mode);
  Future<void> setLoopSp(LoopTag tag, double sp);
  Future<void> setLoopOp(LoopTag tag, double op);
  Future<SteadyStateResult> runToSteadyState(
      {double maxSimSeconds = 172800, void Function(double progress)? onProgress});
  Future<Map<String, Object?>> save();
  Stream<SimEvent> get events;
  Future<void> dispose();

  // --- additions for the M1 app (see docs/DEVIATIONS.md)

  /// Levers this configuration offers.
  List<LeverSpec> get levers;

  /// Thermo model for diagram builders.
  ThermoModel get thermo;
  ColumnConfig get config;
  Future<void> rebuild(ColumnConfig config);
}
