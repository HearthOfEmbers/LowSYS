import '../config/column_config.dart';
import '../core/ids.dart';
import '../explain/explain_types.dart';
import '../control/trend_buffer.dart';
import '../scenario/drill.dart';
import '../scenario/scenario_def.dart';
import '../scenario/scenario_runner.dart';
import '../faults/fault_spec.dart';
import '../sim/lever_spec.dart';
import '../sim/simulator.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/thermo_model.dart';
import 'frame.dart';

/// The only thing the app uses to talk to the engine (ENGINE_API.md 6.6). The M10 move to a
/// background isolate is a local change behind this interface.
abstract class SimRunner {
  Future<void> load(ColumnConfig config,
      {SimOptions options = const SimOptions(), bool warmStart = true});
  Future<void> loadSaved(Map<String, Object?> saved);

  /// Advance by up to [simSeconds] but stop when [wallBudget] is used. Returns the sim time actually advanced.
  Future<double> advance(double simSeconds, Duration wallBudget);
  Future<SimSnapshot> snapshot();

  /// Advances by up to [advanceSeconds] within [budget] (0: no advance) and returns the snapshot with the derived data
  /// of [req] (M10). A background-isolate runner does all of it off the UI isolate.
  Future<FrameResult> frame(FrameRequest req,
      {double advanceSeconds = 0, Duration budget = const Duration(milliseconds: 6)});
  Future<void> setLever(LeverId id, double value);
  Future<void> setTier(ThermoTier t);
  Future<void> setLoopMode(LoopTag tag, LoopMode mode);
  Future<void> setLoopSp(LoopTag tag, double sp);
  Future<void> setLoopOp(LoopTag tag, double op);
  Future<SteadyStateResult> runToSteadyState(
      {double maxSimSeconds = 172800,
      void Function(double progress)? onProgress});
  Future<FaultId> injectFault(FaultSpec spec);
  Future<void> clearFault(FaultId id);
  Future<ExplainResult> explain(ExplainTarget target);
  Future<Map<String, Object?>> save();

  // --- M3: operator actions and scenarios
  Future<void> acknowledgeAlarm(String alarmId);
  Future<void> acknowledgeAllAlarms();
  Future<void> requestFieldCheck(String gaugeTag);
  Future<void> requestMaintenance(String tag);
  Future<void> setCheckWindow(double seconds);
  Future<void> setTemperatureReference();

  /// Replaces the column by another preset at its steady state (G7, the Learn screen's presets).
  Future<void> loadPreset(String presetId, {String? tier});

  /// Opens the failed steam trap bypass (F14, PHYSICS.md 11).
  Future<void> openTrapBypass();

  /// Starts a scenario; [seed] defaults to the options seed.
  Future<void> startScenario(ScenarioDef def, {int? seed});
  Future<void> takeHint(int index);
  Future<AnswerResult> submitAnswer(String objectiveId, Object answer);
  Future<DrillResult> submitDiagnosis(Diagnosis d);
  Future<ScoreCard> finishScenario();
  Stream<SimEvent> get events;
  Future<void> dispose();

  // --- additions for the M1 app (see docs/DEVIATIONS.md)

  /// Levers this configuration offers.
  List<LeverSpec> get levers;

  /// Thermo model for diagram builders.
  ThermoModel get thermo;

  /// The Tier-2 (Raoult) model: the ideal curves of the T-x-y tab in Tier 1 and the display-only T*.
  ThermoModel get idealThermo;

  /// Trend bins of every reading (M3); the local runner shares the engine's buffer.
  TrendBuffer get trends;
  ColumnConfig get config;
  Future<void> rebuild(ColumnConfig config);
}
