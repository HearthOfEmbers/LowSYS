import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../faults/fault_spec.dart';
import '../sim/simulator.dart';
import '../snapshot/sim_snapshot.dart';
import 'predicate.dart';
import 'scenario_def.dart';

/// What a scenario needs from the simulation: snapshots in, lever/loop/fault actions out.
abstract class ScenarioHost {
  SimSnapshot snapshot();
  void setLever(LeverId id, double value);
  void setLoopMode(LoopTag tag, LoopMode mode);
  FaultId injectFault(FaultSpec spec);
  void clearFault(FaultId id);
}

class SimulatorHost implements ScenarioHost {
  final Simulator sim;
  SimulatorHost(this.sim);
  @override
  SimSnapshot snapshot() => sim.snapshot();
  @override
  void setLever(LeverId id, double value) => sim.setLever(id, value);
  @override
  void setLoopMode(LoopTag tag, LoopMode mode) =>
      sim.control.setMode(tag, mode);
  @override
  FaultId injectFault(FaultSpec spec) => sim.faults.inject(spec);
  @override
  void clearFault(FaultId id) => sim.faults.clear(id);
}

class ObjectiveState {
  final ObjectiveDef def;
  bool achieved = false;
  double? achievedAt;
  double _holdSince = -1;
  ObjectiveState(this.def);
  String get id => def.id;
  String get text => def.text;
}

@immutable
class ScoreCard {
  /// 0..1 each; total 0..100.
  final double objectives, time, safety, quality, total;
  final bool completed;
  final double elapsed;
  const ScoreCard({
    required this.objectives,
    required this.time,
    required this.safety,
    required this.quality,
    required this.total,
    required this.completed,
    required this.elapsed,
  });
}

/// Evaluates objectives, hints, timed events and scoring for one scenario run (ENGINE_API.md 11.3).
class ScenarioRunner {
  final ScenarioDef def;
  final ScenarioHost host;
  final List<ObjectiveState> objectives;
  final List<String> _hints = [];
  final Map<String, Object?> _answers = {};
  final List<String> messages = [];
  final Set<int> _firedEvents = {};
  double? _t0;
  double _lastTime = 0;
  double _levelViolation = 0;
  double _qualityHeld = 0;
  double _elapsed = 0;

  ScenarioRunner(this.def, this.host)
      : objectives = [for (final o in def.objectives) ObjectiveState(o)];

  factory ScenarioRunner.forSimulator(ScenarioDef def, Simulator sim) =>
      ScenarioRunner(def, SimulatorHost(sim));

  List<String> get unlockedHints => List.unmodifiable(_hints);
  double get elapsed => _elapsed;
  bool get allAchieved => objectives.every((o) => o.achieved);

  void submitAnswer(String id, Object answer) => _answers[id] = answer;

  /// Evaluate against the latest state; call about once per frame.
  void update([SimSnapshot? snap]) {
    final s = snap ?? host.snapshot();
    _t0 ??= s.time;
    final t = s.time - _t0!;
    final dt = (s.time - _lastTime).clamp(0.0, 600.0);
    _lastTime = s.time;
    _elapsed = t;
    // timed events
    for (var i = 0; i < def.events.length; i++) {
      final e = def.events[i];
      if (_firedEvents.contains(i) || t < e.at) continue;
      _firedEvents.add(i);
      switch (e.action) {
        case 'setLever':
          host.setLever(
              e.data['lever']! as String, (e.data['value']! as num).toDouble());
        case 'setLoopMode':
          host.setLoopMode(e.data['tag']! as String,
              LoopMode.values.firstWhere((m) => m.name == e.data['mode']));
        case 'injectFault':
          host.injectFault(ScenarioDef.faultOf(e.data, s.time));
        case 'message':
          messages.add(e.data['text']! as String);
      }
    }
    // safety bookkeeping
    final k = s.kpis;
    final bad = k.drumLevelPct < 5 ||
        k.drumLevelPct > 95 ||
        k.sumpLevelPct < 5 ||
        k.sumpLevelPct > 95;
    if (bad) _levelViolation += dt;
    final ctx = MetricContext(s, t, _answers, _levelViolation);
    for (final o in objectives) {
      if (o.achieved && o.def.latch) continue;
      final dep = o.def.after;
      final depOk =
          dep == null || objectives.firstWhere((x) => x.id == dep).achieved;
      final holds = depOk && (o.def.when?.eval(ctx) ?? false);
      if (holds) {
        if (o._holdSince < 0) o._holdSince = t;
        if (t - o._holdSince >= o.def.holdFor) {
          if (!o.achieved) o.achievedAt = t;
          o.achieved = true;
        }
      } else {
        o._holdSince = -1;
        if (!o.def.latch) o.achieved = false;
      }
    }
    // hints
    for (final h in def.hints) {
      if (_hints.contains(h.text)) continue;
      final byTime = h.after != null && t >= h.after!;
      final byCond = h.when != null && h.when!.eval(ctx);
      if (byTime || byCond) _hints.add(h.text);
    }
    // quality: time the product spec is held
    final qs = def.scoring['qualitySpec'];
    if (qs is Map<String, Object?>) {
      if (Predicate.fromJson(qs).eval(ctx)) _qualityHeld += dt;
    }
  }

  ScoreCard finish() {
    final nAch = objectives.where((o) => o.achieved).length;
    final objFrac = objectives.isEmpty ? 1.0 : nAch / objectives.length;
    final done = nAch == objectives.length;
    final timeFrac =
        done ? (1 - _elapsed / def.timeLimit).clamp(0.0, 1.0) : 0.0;
    final safety = _levelViolation > 60 ? 0.0 : 1.0;
    final quality =
        _elapsed > 0 ? (_qualityHeld / _elapsed).clamp(0.0, 1.0) : 0.0;
    final w = def.scoring;
    double wt(String k, double d) => (w[k] as num?)?.toDouble() ?? d;
    final total = 100 *
        (wt('objectives', 0.6) * objFrac +
            wt('time', 0.2) * timeFrac +
            wt('safety', 0.1) * safety +
            wt('quality', 0.1) * quality);
    return ScoreCard(
        objectives: objFrac,
        time: timeFrac,
        safety: safety,
        quality: quality,
        total: total,
        completed: done,
        elapsed: _elapsed);
  }

  /// Debrief text with `{metric:format}` placeholders replaced by live values.
  String debriefText(SimSnapshot s) {
    final ctx = MetricContext(s, _elapsed, _answers, _levelViolation);
    return def.debrief
        .replaceAllMapped(RegExp(r'\{([\w\[\].\-]+)(?::([0-9.]+))?\}'), (m) {
      final v = ctx.read(m.group(1)!);
      if (v is num) {
        final dec = m.group(2) == null
            ? 2
            : (m.group(2)!.split('.').length > 1
                ? m.group(2)!.split('.')[1].length
                : 0);
        return v.toStringAsFixed(dec);
      }
      return v?.toString() ?? m.group(0)!;
    });
  }
}
