import 'dart:async';

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
import 'sim_runner.dart';

/// Wraps a [Simulator] on the calling isolate; futures complete without real asynchrony.
class LocalSimRunner implements SimRunner {
  Simulator? _sim;
  final StreamController<SimEvent> _events =
      StreamController<SimEvent>.broadcast();
  StreamSubscription<SimEvent>? _sub;

  Simulator get sim =>
      _sim ?? (throw StateError('LocalSimRunner: call load() first'));

  void _attach(Simulator s) {
    _sub?.cancel();
    _sim = s;
    _sub = s.events.listen(_events.add);
  }

  @override
  Future<void> load(ColumnConfig config,
      {SimOptions options = const SimOptions(), bool warmStart = true}) async {
    _attach(Simulator(config, options: options, warmStart: warmStart));
  }

  @override
  Future<void> loadSaved(Map<String, Object?> saved) async {
    _attach(Simulator.restore(saved));
  }

  @override
  Future<void> rebuild(ColumnConfig config) async {
    sim.rebuild(config);
  }

  @override
  Future<double> advance(double simSeconds, Duration wallBudget) async {
    final s = sim;
    final dt = s.options.dt;
    final steps = (simSeconds / dt + 1e-9).floor();
    final sw = Stopwatch()..start();
    var done = 0;
    while (done < steps && !s.halted) {
      final chunk = steps - done < 8 ? steps - done : 8;
      for (var i = 0; i < chunk; i++) {
        s.step();
      }
      done += chunk;
      if (sw.elapsed >= wallBudget) break;
    }
    return done * dt;
  }

  @override
  Future<SimSnapshot> snapshot() async => sim.snapshot();

  @override
  Future<void> setLever(LeverId id, double value) async =>
      sim.setLever(id, value);

  @override
  Future<void> setTier(ThermoTier t) async => sim.setTier(t);

  @override
  Future<void> setLoopMode(LoopTag tag, LoopMode mode) async {
    sim.control.setMode(tag, mode);
  }

  @override
  Future<void> setLoopSp(LoopTag tag, double sp) async {
    switch (tag) {
      case 'FC-101':
        sim.setLever('feedFlow', sp);
      case 'FC-102':
        sim.setLever('refluxFlow', sp);
      case 'FC-103':
        sim.setLever(sim.tier == ThermoTier.t1 ? 'boilup' : 'reboilerDuty', sp);
      case 'PC-101':
        sim.setLever('pTop', sp);
      case 'TC-101':
        sim.setLever('tc101Sp', sp);
      default:
        sim.control.setSp(tag, sp);
    }
  }

  @override
  Future<void> setLoopOp(LoopTag tag, double op) async =>
      sim.control.setOp(tag, op);

  @override
  Future<SteadyStateResult> runToSteadyState(
      {double maxSimSeconds = 172800,
      void Function(double progress)? onProgress}) async {
    final run = sim.beginSteadyRun(maxSimSeconds: maxSimSeconds);
    while (!run.advance(const Duration(milliseconds: 50))) {
      onProgress?.call(run.progress);
      await Future<void>.delayed(Duration.zero);
    }
    onProgress?.call(1);
    return run.result!;
  }

  @override
  Future<FaultId> injectFault(FaultSpec spec) async => sim.faults.inject(spec);

  @override
  Future<void> clearFault(FaultId id) async => sim.faults.clear(id);

  @override
  Future<ExplainResult> explain(ExplainTarget target) async =>
      sim.explain(target);

  @override
  Future<Map<String, Object?>> save() async => sim.saveState();

  @override
  Future<void> acknowledgeAlarm(String alarmId) async => sim.acknowledgeAlarm(alarmId);
  @override
  Future<void> acknowledgeAllAlarms() async => sim.acknowledgeAllAlarms();
  @override
  Future<void> requestFieldCheck(String gaugeTag) async => sim.requestFieldCheck(gaugeTag);
  @override
  Future<void> requestMaintenance(String tag) async => sim.requestMaintenance(tag);
  @override
  Future<void> setCheckWindow(double seconds) async => sim.setCheckWindow(seconds);
  @override
  Future<void> setTemperatureReference() async => sim.setTemperatureReference();
  @override
  Future<void> loadPreset(String presetId, {String? tier}) async =>
      sim.loadPreset(presetId, tier: tier);
  @override
  Future<void> openTrapBypass() async => sim.openTrapBypass();
  @override
  Future<void> startScenario(ScenarioDef def, {int? seed}) async => sim.startScenario(def, seed: seed);
  @override
  Future<void> takeHint(int index) async => sim.takeHint(index);
  @override
  Future<AnswerResult> submitAnswer(String objectiveId, Object answer) async => sim.submitAnswer(objectiveId, answer);
  @override
  Future<DrillResult> submitDiagnosis(Diagnosis d) async => sim.submitDiagnosis(d);
  @override
  Future<ScoreCard> finishScenario() async => sim.finishScenario();

  @override
  Stream<SimEvent> get events => _events.stream;

  @override
  List<LeverSpec> get levers => sim.levers;

  @override
  ThermoModel get thermo => sim.thermo;

  @override
  ColumnConfig get config => sim.config;

  @override
  TrendBuffer get trends => sim.trends;

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sim?.dispose();
    await _events.close();
  }
}
