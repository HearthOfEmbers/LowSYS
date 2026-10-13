import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../core/rng.dart';
import '../faults/fault_spec.dart';
import '../sim/simulator.dart';
import '../snapshot/sim_snapshot.dart';
import 'drill.dart';
import 'predicate.dart';
import 'scenario_def.dart';
import 'scoring.dart';

/// What a scenario needs from the simulation (ENGINE_API.md 11.3).
abstract class ScenarioHost {
  double get time;
  double get dt;
  int get seed;
  double lever(LeverId id);
  void setLever(LeverId id, double value);
  void setLoopMode(LoopTag tag, LoopMode mode);
  void setSp(LoopTag tag, double sp);

  /// CAS-slave `delta` rule (ENGINE_API.md 11.1): bumps the master's OP by the equivalent % of the slave span.
  /// Returns false when [tag] is not a CAS slave.
  bool bumpCasSlave(LoopTag tag, double delta);

  /// Loads another preset (and tier) at its steady state, keeping the scenario running (G7).
  void loadPreset(String presetId, {String? tier, Map<String, Object?> overrides});
  double loopSp(LoopTag tag);
  LoopMode loopMode(LoopTag tag);
  FaultId injectFault(FaultSpec spec);
  void clearFault(FaultId id);
  LiveMetricContext get context;
  double get levelViolationSeconds;
  bool get reliefLifted;

  /// First cross-check that went `fail` after [since], as (id, time), or null.
  (String, double)? firstFailedCheck(double since);

  /// Text for \`fault.magnitude\` of an instrument fault.
  String faultMagnitude(CandidateDef c, double severity, double sign);
}

class SimulatorHost implements ScenarioHost {
  final Simulator sim;
  SimulatorHost(this.sim);
  @override
  double get time => sim.time;
  @override
  double get dt => sim.options.dt;
  @override
  int get seed => sim.seed;
  @override
  double lever(LeverId id) => sim.lever(id);
  @override
  void setLever(LeverId id, double value) {
    final spec = sim.levers.firstWhere((l) => l.id == id,
        orElse: () => throw ArgumentError('Unknown lever "$id"'));
    sim.setLever(id, value.clamp(spec.min, spec.max).toDouble());
  }

  @override
  void setLoopMode(LoopTag tag, LoopMode mode) =>
      sim.control.setMode(tag, mode);
  @override
  void setSp(LoopTag tag, double sp) => sim.control.setSp(tag, sp);
  @override
  bool bumpCasSlave(LoopTag tag, double delta) =>
      sim.control.bumpCasSlave(tag, delta);
  @override
  void loadPreset(String presetId,
          {String? tier, Map<String, Object?> overrides = const {}}) =>
      sim.loadPreset(presetId, tier: tier, overrides: overrides);
  @override
  double loopSp(LoopTag tag) => sim.control.loop(tag).sp;
  @override
  LoopMode loopMode(LoopTag tag) => sim.control.loop(tag).mode;
  @override
  FaultId injectFault(FaultSpec spec) => sim.faults.inject(spec);
  @override
  void clearFault(FaultId id) => sim.faults.clear(id);
  @override
  late final LiveMetricContext context = LiveMetricContext(sim);
  @override
  double get levelViolationSeconds => sim.safetyLevelViolationSeconds;
  @override
  bool get reliefLifted => false;
  @override
  (String, double)? firstFailedCheck(double since) =>
      sim.firstFailedCheckSince(since);
  @override
  String faultMagnitude(CandidateDef c, double severity, double sign) {
    final tag = c.location.tagName;
    final inst = tag != null && sim.control.hasInstrument(tag)
        ? sim.control.instrument(tag)
        : null;
    final sg = sign < 0 ? '−' : '+';
    if (c.faultType == FaultType.coolingLoss && c.params['mode'] == 'temperature') {
      return (15 * severity).toStringAsFixed(1); // K of CW inlet temperature rise (PHYSICS.md 11)
    }
    if (inst == null) return severity.toStringAsFixed(2);
    final pct = 10 * severity;
    return '$sg${pct.toStringAsFixed(1)} % of span';
  }
}

/// Run-time state of one objective.
class ObjectiveRuntime {
  final ObjectiveDef def;
  bool achieved = false;
  double? achievedAt;
  double holdSince = -1;
  int attemptsLeft;
  bool exhausted = false;
  ObjectiveRuntime(this.def) : attemptsLeft = def.answer?.attempts ?? 0;
  String get id => def.id;
  String get text => def.text;
}

@immutable
class ScoreCard {
  /// The terms of the score (guided: O, T, S, Q; drill: C and L in [objectives] and [quality]).
  final double objectives, time, safety, quality;

  /// 0..100 as a number; the rounded value is [score].
  final double total;
  final int score;
  final bool completed;
  final double elapsed;
  final double hintCost, bonus, penalty;

  /// Drill facts: onset, off-spec time, protect time, diagnosis time (null = never).
  final double? t0, offSpecAt, protectAt, diagnosisAt;
  final String? firstFlaggedCheck;
  final String debriefText;
  const ScoreCard({
    required this.objectives,
    required this.time,
    required this.safety,
    required this.quality,
    required this.total,
    required this.score,
    required this.completed,
    required this.elapsed,
    this.hintCost = 0,
    this.bonus = 0,
    this.penalty = 0,
    this.t0,
    this.offSpecAt,
    this.protectAt,
    this.diagnosisAt,
    this.firstFlaggedCheck,
    this.debriefText = '',
  });
}

/// Evaluates objectives, hints, events and scoring for one run (ENGINE_API.md 11.3). The simulator calls
/// [update] after every main step, so the result does not depend on the frame rate.
class ScenarioRunner {
  final ScenarioDef def;
  final ScenarioHost host;
  final List<ObjectiveRuntime> objectives;
  final List<bool> _hintAvailable, _hintTaken;
  final Map<String, Object?> _answers = {};
  final List<ScenarioMessage> messages = [];
  final Set<int> _fired = {};
  final Map<int, double> _randomAt = {};
  final Map<String, FaultId> _eventFaults = {};
  final Map<String, Object?> _start = {};
  late double t0;
  double _lastTime = 0;
  double _elapsed = 0;
  double _qualityHeld = 0;
  bool finished = false;

  // drill
  DrillDraw? draw;
  FaultId? _drillFault;
  double? _offSpecAt, _protectAt, _diagnosisAt, _offSpecHoldSince;
  final List<DrillAttempt> _attempts = [];
  int diagnosisAttemptsLeft = 0;
  bool _fullyCorrect = false;
  (String, double)? _firstFlagged;
  ScoreCard? _card;

  ScenarioRunner(this.def, this.host, {bool restoring = false})
      : objectives = [for (final o in def.objectives) ObjectiveRuntime(o)],
        _hintAvailable = List.filled(def.hints.length, false),
        _hintTaken = List.filled(def.hints.length, false) {
    t0 = host.time;
    _lastTime = t0;
    diagnosisAttemptsLeft = def.diagnosis?.attempts ?? 0;
    if (!restoring) {
      _begin();
    } else if (def.isDrill) {
      draw = DrillDraw.draw(def, host.seed, dt: host.dt);
    }
  }

  factory ScenarioRunner.forSimulator(ScenarioDef def, Simulator sim) =>
      ScenarioRunner(def, SimulatorHost(sim));

  void _begin() {
    // values at t = 0 for "from: start" comparisons
    final paths = <String>[];
    for (final o in def.objectives) {
      o.when?.collectStartMetrics(paths);
    }
    def.offSpec?.collectStartMetrics(paths);
    for (final h in def.hints) {
      h.when?.collectStartMetrics(paths);
    }
    for (final p in paths) {
      _start[p] = host.context.read(p);
    }
    host.context.start = _start;
    // random event times, drawn at t = 0 in event order
    final rng = Rng.stream(host.seed, 'scenario:events');
    for (var i = 0; i < def.events.length; i++) {
      final r = def.events[i].atRandom;
      if (r != null) _randomAt[i] = r[0] + rng.uniform() * (r[1] - r[0]);
    }
    if (def.isDrill) {
      final d = DrillDraw.draw(def, host.seed, dt: host.dt);
      draw = d;
      final c = d.candidate;
      final params = Map<String, Object?>.from(c.params);
      if (params['sign'] == 'random') params['sign'] = d.sign;
      _drillFault = host.injectFault(FaultSpec(
        type: c.faultType,
        location: c.location,
        severity: d.severity,
        onset: t0 + d.onset,
        ramp: c.ramp,
        params: params,
        hidden: true,
      ));
    }
  }

  List<ObjectiveRuntime> get objectiveStates => objectives;
  double get elapsed => _elapsed;
  bool get allAchieved => objectives.every((o) => o.achieved);

  /// True when objective [id] has been met (metric `objective[id].met`).
  bool objectiveMet(String id) =>
      objectives.any((o) => o.id == id && o.achieved);
  bool get fullyDiagnosed => _fullyCorrect;
  List<String> get unlockedHints => [
        for (var i = 0; i < def.hints.length; i++)
          if (_hintTaken[i]) def.hints[i].text
      ];

  /// Unlocks and charges hint [index] (ENGINE_API.md 11.4).
  void takeHint(int index) {
    if (index < 0 || index >= def.hints.length)
      throw RangeError.index(index, def.hints);
    if (!_hintAvailable[index])
      throw StateError('Hint $index is not available yet');
    _hintTaken[index] = true;
  }

  double get hintCost {
    var c = 0.0;
    for (var i = 0; i < def.hints.length; i++) {
      if (_hintTaken[i]) c += def.hints[i].cost;
    }
    return c;
  }

  AnswerResult submitAnswer(String objectiveId, Object answer) {
    final o = objectives.firstWhere((x) => x.id == objectiveId,
        orElse: () => throw ArgumentError('No objective $objectiveId'));
    final spec = o.def.answer;
    if (spec == null)
      throw StateError('Objective $objectiveId takes no answer');
    _answers[objectiveId] = answer;
    if (o.achieved || o.exhausted)
      return AnswerResult(objectiveId, o.achieved, o.attemptsLeft);
    if (spec.isCorrect(answer)) {
      o.achieved = true;
      o.achievedAt = host.time - t0;
    } else {
      o.attemptsLeft--;
      if (o.attemptsLeft <= 0) o.exhausted = true;
    }
    return AnswerResult(objectiveId, o.achieved, o.attemptsLeft);
  }

  DrillResult submitDiagnosis(Diagnosis d) {
    final dr = draw;
    if (dr == null) throw StateError('Not a drill');
    if (diagnosisAttemptsLeft <= 0 || finished) {
      return DrillResult(
          fullyCorrect: _fullyCorrect,
          categoryOk: false,
          locationOk: false,
          modeOk: false,
          attemptsLeft: 0);
    }
    final c = dr.candidate;
    final catOk = d.category == c.answerCategory;
    final locOk = d.location == c.answerLocation;
    final modeOk = d.mode != null && d.mode == c.answerMode;
    final t = host.time - t0;
    _attempts.add(DrillAttempt(
        time: t, categoryOk: catOk, locationOk: locOk, modeOk: modeOk));
    diagnosisAttemptsLeft--;
    host.context; // no-op
    if (catOk && locOk) {
      _fullyCorrect = true;
      _diagnosisAt = t;
      finished = true;
    } else if (diagnosisAttemptsLeft <= 0) {
      _diagnosisAt = t;
      finished = true;
    }
    return DrillResult(
        fullyCorrect: catOk && locOk,
        categoryOk: catOk,
        locationOk: locOk,
        modeOk: modeOk,
        attemptsLeft: diagnosisAttemptsLeft);
  }

  /// Gives up a drill (no more attempts).
  void giveUp() {
    finished = true;
    _diagnosisAt ??= host.time - t0;
  }

  /// Evaluate against the live state; called by the simulator after every main step.
  void update() {
    if (finished && _card != null) return;
    final now = host.time;
    final t = now - t0;
    final dt = (now - _lastTime).clamp(0.0, 600.0);
    _lastTime = now;
    _elapsed = t;
    final ctx = host.context
      ..answers = _answers
      ..scenarioTime = t;
    // events
    for (var i = 0; i < def.events.length; i++) {
      if (_fired.contains(i)) continue;
      final e = def.events[i];
      final due = e.at != null
          ? t >= e.at!
          : e.atRandom != null
              ? t >= _randomAt[i]!
              : (e.when?.evaluate(ctx) ?? false);
      if (!due) continue;
      _fired.add(i);
      _fireEvent(e, now, t);
    }
    // objectives
    for (final o in objectives) {
      if (o.def.answer != null) continue;
      if (o.achieved && o.def.latch) continue;
      final dep = o.def.after;
      final depOk =
          dep == null || objectives.firstWhere((x) => x.id == dep).achieved;
      final holds = depOk && (o.def.when?.evaluate(ctx) ?? false);
      if (holds) {
        if (o.holdSince < 0) o.holdSince = t;
        if (t - o.holdSince >= o.def.holdFor) {
          if (!o.achieved) o.achievedAt = t;
          o.achieved = true;
        }
      } else {
        o.holdSince = -1;
        if (!o.def.latch) o.achieved = false;
      }
    }
    // hints
    for (var i = 0; i < def.hints.length; i++) {
      final h = def.hints[i];
      if (!_hintAvailable[i]) {
        final byTime = h.after != null && t >= h.after!;
        final byCond = h.when != null && h.when!.evaluate(ctx);
        if (byTime || byCond) _hintAvailable[i] = true;
      }
      if (_hintAvailable[i] && !_hintTaken[i] && h.cost <= 0 && !def.isDrill)
        _hintTaken[i] = true;
    }
    // quality
    final qs = def.scoring['qualitySpec'];
    if (qs is Map<String, Object?>) {
      _qualitySpec ??= Predicate.fromJson(qs);
      if (_qualitySpec!.evaluate(ctx)) _qualityHeld += dt;
    }
    // drill clocks
    final dr = draw;
    if (dr != null && !finished) {
      if (_offSpecAt == null && t >= dr.onset && def.offSpec != null) {
        if (def.offSpec!.evaluate(ctx)) {
          _offSpecHoldSince ??= t;
          if (t - _offSpecHoldSince! >= def.offSpecHold) _offSpecAt = t;
        } else {
          _offSpecHoldSince = null;
        }
      }
      if (_protectAt == null &&
          dr.candidate.protect.isNotEmpty &&
          t >= dr.onset &&
          _offSpecAt == null) {
        for (final p in dr.candidate.protect) {
          if (p.modes.contains(host.loopMode(p.tag).name)) {
            _protectAt = t;
            break;
          }
        }
      }
      if (_firstFlagged == null && t >= dr.onset) {
        _firstFlagged = host.firstFailedCheck(t0 + dr.onset);
      }
    }
    if (t >= def.timeLimit) {
      finished = true;
      _diagnosisAt ??= null;
    }
  }

  Predicate? _qualitySpec;

  void _fireEvent(EventDef e, double now, double t) {
    switch (e.action) {
      case 'setLever':
        final id = e.data['lever']! as String;
        final v = e.data['value'] != null
            ? (e.data['value']! as num).toDouble()
            : host.lever(id) + (e.data['delta']! as num).toDouble();
        host.setLever(id, v);
      case 'setLoopMode':
        host.setLoopMode(e.data['tag']! as String,
            LoopMode.values.firstWhere((m) => m.name == e.data['mode']));
      case 'setSp':
        final tag = e.data['tag']! as String;
        if (e.data['value'] == null &&
            host.loopMode(tag) == LoopMode.cas &&
            host.bumpCasSlave(tag, (e.data['delta']! as num).toDouble())) {
          break;
        }
        final v = e.data['value'] != null
            ? (e.data['value']! as num).toDouble()
            : host.loopSp(tag) + (e.data['delta']! as num).toDouble();
        host.setSp(tag, v);
      case 'loadPreset':
        host.loadPreset(e.data['preset']! as String,
            tier: e.data['tier'] as String?,
            overrides: Map<String, Object?>.from(
                (e.data['overrides'] as Map?) ?? const {}));
      case 'injectFault':
        final id = host.injectFault(ScenarioDef.faultOf(e.data, now));
        if (e.id != null) _eventFaults[e.id!] = id;
      case 'clearFault':
        final ref = _eventFaults[e.data['faultRef']];
        if (ref != null) host.clearFault(ref);
      case 'message':
        break;
    }
    if (e.text != null) messages.add(ScenarioMessage(t, e.text!));
  }

  ScoreCard? get card => _card;

  Map<String, Object?> toJson() => {
        't0': t0,
        'lastTime': _lastTime,
        'elapsed': _elapsed,
        'qualityHeld': _qualityHeld,
        'finished': finished,
        'fired': _fired.toList(),
        'randomAt': {for (final e in _randomAt.entries) '${e.key}': e.value},
        'eventFaults': _eventFaults,
        'start': _start,
        'answers': _answers,
        'messages': [
          for (final m in messages) [m.time, m.text]
        ],
        'objectives': [
          for (final o in objectives)
            [o.achieved, o.achievedAt, o.holdSince, o.attemptsLeft, o.exhausted]
        ],
        'hintAvail': _hintAvailable,
        'hintTaken': _hintTaken,
        'drillFault': _drillFault,
        'offSpecAt': _offSpecAt,
        'protectAt': _protectAt,
        'diagnosisAt': _diagnosisAt,
        'offSpecHold': _offSpecHoldSince,
        'attempts': [
          for (final a in _attempts)
            [a.time, a.categoryOk, a.locationOk, a.modeOk]
        ],
        'diagLeft': diagnosisAttemptsLeft,
        'fullyCorrect': _fullyCorrect,
        'flagged': _firstFlagged == null
            ? null
            : [_firstFlagged!.$1, _firstFlagged!.$2],
      };

  void loadJson(Map<String, Object?> j) {
    double d(Object? v) => (v! as num).toDouble();
    t0 = d(j['t0']);
    _lastTime = d(j['lastTime']);
    _elapsed = d(j['elapsed']);
    _qualityHeld = d(j['qualityHeld']);
    finished = j['finished']! as bool;
    _fired
      ..clear()
      ..addAll(
          [for (final v in j['fired']! as List<Object?>) (v! as num).toInt()]);
    _randomAt
      ..clear()
      ..addAll({
        for (final e in (j['randomAt']! as Map<String, Object?>).entries)
          int.parse(e.key): d(e.value)
      });
    _eventFaults
      ..clear()
      ..addAll({
        for (final e in (j['eventFaults']! as Map<String, Object?>).entries)
          e.key: e.value! as String
      });
    _start
      ..clear()
      ..addAll(j['start']! as Map<String, Object?>);
    host.context.start = _start;
    _answers
      ..clear()
      ..addAll(j['answers']! as Map<String, Object?>);
    messages
      ..clear()
      ..addAll([
        for (final e in j['messages']! as List<Object?>)
          ScenarioMessage(d((e! as List<Object?>)[0]), (e as List<Object?>)[1]! as String)
      ]);
    final os = j['objectives']! as List<Object?>;
    for (var i = 0; i < objectives.length; i++) {
      final l = os[i]! as List<Object?>;
      objectives[i]
        ..achieved = l[0]! as bool
        ..achievedAt = (l[1] as num?)?.toDouble()
        ..holdSince = d(l[2])
        ..attemptsLeft = (l[3]! as num).toInt()
        ..exhausted = l[4]! as bool;
    }
    final ha = j['hintAvail']! as List<Object?>,
        ht = j['hintTaken']! as List<Object?>;
    for (var i = 0; i < _hintAvailable.length; i++) {
      _hintAvailable[i] = ha[i]! as bool;
      _hintTaken[i] = ht[i]! as bool;
    }
    _drillFault = j['drillFault'] as String?;
    _offSpecAt = (j['offSpecAt'] as num?)?.toDouble();
    _protectAt = (j['protectAt'] as num?)?.toDouble();
    _diagnosisAt = (j['diagnosisAt'] as num?)?.toDouble();
    _offSpecHoldSince = (j['offSpecHold'] as num?)?.toDouble();
    _attempts
      ..clear()
      ..addAll([
        for (final a0 in j['attempts']! as List<Object?>)
          DrillAttempt(
              time: d((a0! as List<Object?>)[0]),
              categoryOk: (a0 as List<Object?>)[1]! as bool,
              locationOk: a0[2]! as bool,
              modeOk: a0[3]! as bool)
      ]);
    diagnosisAttemptsLeft = (j['diagLeft']! as num).toInt();
    _fullyCorrect = j['fullyCorrect']! as bool;
    final fl = j['flagged'] as List<Object?>?;
    _firstFlagged = fl == null ? null : (fl[0]! as String, d(fl[1]));
  }

  /// Ends the run and scores it (ENGINE_API.md 11.4).
  ScoreCard finish() {
    final existing = _card;
    if (existing != null) return existing;
    finished = true;
    final t = host.time - t0;
    _elapsed = t;
    final relief = host.reliefLifted;
    final viol = host.levelViolationSeconds;
    ScoreCard card;
    if (def.isDrill) {
      final dr = draw!;
      final res = Scoring.drill(
        weights: def.drillWeights,
        t0: dr.onset,
        attempts: _attempts,
        protectMetAt: _protectAt,
        offSpecAt: _offSpecAt,
        reliefLifted: relief,
        levelViolationSeconds: viol,
        hintCost: hintCost,
        hasProtect: dr.candidate.protect.isNotEmpty,
      );
      card = ScoreCard(
        objectives: res.category,
        time: res.time,
        safety: res.safety,
        quality: res.location,
        total: 100 * res.raw.clamp(0.0, 1.0),
        score: res.score,
        completed: _fullyCorrect,
        elapsed: t,
        hintCost: res.hints,
        bonus: res.bonus,
        penalty: res.penalty,
        t0: dr.onset,
        offSpecAt: _offSpecAt,
        protectAt: _protectAt,
        diagnosisAt: _diagnosisAt,
        firstFlaggedCheck: _firstFlagged == null
            ? null
            : '${_firstFlagged!.$1} at ${_fmtTime(_firstFlagged!.$2 - t0)}',
        debriefText: _debrief(dr.candidate.debrief +
            (dr.candidate.debrief.isEmpty ? '' : '\n\n') +
            def.debrief),
      );
    } else {
      final res = Scoring.guided(
        weights: def.guidedWeights,
        objectiveWeights: [for (final o in objectives) o.def.weight],
        achieved: [for (final o in objectives) o.achieved],
        tEnd: t,
        parTime: def.parTime,
        timeLimit: def.timeLimit,
        reliefLifted: relief,
        levelViolationSeconds: viol,
        qualityFraction: t > 0 ? _qualityHeld / t : 0,
        hintCost: hintCost,
      );
      final qs = def.scoring['qualitySpec'];
      final qualityTerm = qs == null ? def.guidedWeights.quality : res.quality;
      final adjusted =
          qs == null ? res.raw - res.quality + qualityTerm : res.raw;
      card = ScoreCard(
        objectives: res.objectives,
        time: res.time,
        safety: res.safety,
        quality: qualityTerm,
        total: 100 * adjusted.clamp(0.0, 1.0),
        score: (100 * adjusted.clamp(0.0, 1.0)).round(),
        completed: allAchieved,
        elapsed: t,
        hintCost: res.hints,
        debriefText: _debrief(def.debrief),
      );
    }
    _card = card;
    return card;
  }

  static String _fmtTime(double s) {
    if (s.isNaN || s.isInfinite) return 'never';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = (s % 60).floor();
    return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static final RegExp _tpl =
      RegExp(r'\{([\w\[\].:\-]+?)(?::([0-9.]+|time))?\}');

  String _debrief(String text) => text.replaceAllMapped(_tpl, (m) {
        final v = m.group(1)!;
        final fmt = m.group(2);
        Object? val = _resolve(v);
        if (val == null) return m.group(0)!;
        if (fmt == 'time')
          return val is num ? _fmtTime(val.toDouble()) : '$val';
        if (val is num) {
          final dec = fmt == null
              ? 2
              : (fmt.contains('.') ? fmt.split('.')[1].length : 0);
          return val.isNaN ? 'n/a' : val.toDouble().toStringAsFixed(dec);
        }
        return '$val';
      });

  Object? _resolve(String v) {
    final dr = draw;
    switch (v) {
      case 'fault.tag':
        return dr?.candidate.location.tagName ??
            dr?.candidate.location.toString();
      case 'fault.mode':
        return dr?.candidate.answerMode ?? dr?.candidate.params['kind'];
      case 'fault.severity':
        return dr?.severity;
      case 'fault.sign':
        final s = dr == null
            ? 1.0
            : (dr.candidate.params['sign'] == 'random'
                ? dr.sign
                : (dr.candidate.params['sign'] as num?)?.toDouble() ?? 1.0);
        return s < 0 ? '−' : '+';
      case 'fault.magnitude':
        return dr == null
            ? null
            : host.faultMagnitude(
                dr.candidate,
                dr.severity,
                dr.candidate.params['sign'] == 'random'
                    ? dr.sign
                    : (dr.candidate.params['sign'] as num?)?.toDouble() ?? 1.0);
      case 'fault.onset':
        return dr?.onset;
      case 'result.offSpecTime':
        return _offSpecAt ?? double.infinity;
      case 'result.protectTime':
        return _protectAt ?? double.infinity;
      case 'result.diagnosisTime':
        return _diagnosisAt ?? double.infinity;
      case 'result.firstFlaggedCheck':
        return _firstFlagged == null
            ? 'none'
            : '${_firstFlagged!.$1} at ${_fmtTime(_firstFlagged!.$2 - t0)}';
    }
    final ctx = host.context
      ..answers = _answers
      ..scenarioTime = _elapsed;
    return ctx.read(v);
  }

  /// The immutable view for the UI. Drills carry no fault data.
  ScenarioSnapshot snapshot() => ScenarioSnapshot(
        id: def.id,
        kind: def.kind,
        elapsed: _elapsed,
        timeLimit: def.timeLimit,
        objectives: [
          for (final o in objectives)
            ObjectiveState(
                o.id,
                o.text,
                o.achieved,
                o.achievedAt,
                o.holdSince >= 0 && !o.achieved ? _elapsed - o.holdSince : 0,
                o.def.holdFor),
        ],
        hints: [
          for (var i = 0; i < def.hints.length; i++)
            HintState(i, _hintAvailable[i], _hintTaken[i], def.hints[i].cost,
                _hintTaken[i] ? def.hints[i].text : null),
        ],
        messages: List.unmodifiable(messages),
        diagnosisAttemptsLeft: diagnosisAttemptsLeft,
        finished: finished,
      );
}
