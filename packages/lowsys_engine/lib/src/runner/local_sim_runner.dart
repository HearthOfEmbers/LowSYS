import 'dart:async';

import '../config/column_config.dart';
import '../core/ids.dart';
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
    if (tag.startsWith('LC-')) sim.control.setMode(tag, mode);
  }

  @override
  Future<void> setLoopSp(LoopTag tag, double sp) async {
    switch (tag) {
      case 'FC-101':
        sim.setLever('feedFlow', sp);
      case 'FC-102':
        sim.setLever('refluxFlow', sp);
      case 'FC-103':
        sim.setLever('boilup', sp);
      default:
        sim.control.setSp(tag, sp);
    }
  }

  @override
  Future<void> setLoopOp(LoopTag tag, double op) async =>
      sim.control.setOp(tag, op);

  @override
  Future<SteadyStateResult> runToSteadyState(
      {double maxSimSeconds = 172800, void Function(double progress)? onProgress}) async {
    final run = sim.beginSteadyRun(maxSimSeconds: maxSimSeconds);
    while (!run.advance(const Duration(milliseconds: 50))) {
      onProgress?.call(run.progress);
      await Future<void>.delayed(Duration.zero);
    }
    onProgress?.call(1);
    return run.result!;
  }

  @override
  Future<Map<String, Object?>> save() async => sim.saveState();

  @override
  Stream<SimEvent> get events => _events.stream;

  @override
  List<LeverSpec> get levers => sim.levers;

  @override
  ThermoModel get thermo => sim.thermo;

  @override
  ColumnConfig get config => sim.config;

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sim?.dispose();
    await _events.close();
  }
}
