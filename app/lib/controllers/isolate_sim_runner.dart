import 'dart:async';
import 'dart:isolate';

import 'package:lowsys_engine/lowsys_engine.dart';

/// A [SimRunner] whose [LocalSimRunner] lives in a background isolate (M10 performance pass). Every call is a message;
/// the synchronous getters of [SimRunner] ([config], [levers], [trends]) are caches the worker refreshes with each reply.
/// [thermo] and [idealThermo] are not available: the derived diagram data comes from [frame].
class IsolateSimRunner implements SimRunner {
  final ReceivePort _rx = ReceivePort();
  SendPort? _tx;
  Future<void>? _starting;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = {};
  final Map<int, void Function(double)> _progress = {};
  final StreamController<SimEvent> _events = StreamController<SimEvent>.broadcast();
  Isolate? _isolate;

  ColumnConfig? _config;
  List<LeverSpec> _levers = const [];
  final TrendBuffer _trends = TrendBuffer();
  final Map<String, int> _trendSynced = {};
  int _epoch = -1;

  Future<void> _start() => _starting ??= () async {
        final ready = Completer<SendPort>();
        _rx.listen((m) {
          final msg = m as List<Object?>;
          if (msg[0] == 'ready') {
            ready.complete(msg[1]! as SendPort);
            return;
          }
          final id = msg[0]! as int;
          switch (msg[1]) {
            case 'event':
              _events.add(msg[2]! as SimEvent);
            case 'progress':
              _progress[id]?.call(msg[2]! as double);
            case 'ok':
              _applyMeta(msg[3]);
              _pending.remove(id)?.complete(msg[2]);
              _progress.remove(id);
            case 'err':
              final text = msg[3]! as String;
              final Object e = switch (msg[2]) {
                'range' => RangeError(text),
                'state' => StateError(text),
                _ => Exception(text),
              };
              _pending.remove(id)?.completeError(e);
              _progress.remove(id);
          }
        });
        _isolate = await Isolate.spawn(_worker, _rx.sendPort);
        _tx = await ready.future;
      }();

  void _applyMeta(Object? meta) {
    if (meta == null) return;
    final m = meta as RunnerMeta;
    _config = m.config;
    _levers = m.levers;
  }

  Future<T> _call<T>(String op, [List<Object?> args = const [], void Function(double)? onProgress]) async {
    await _start();
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    if (onProgress != null) _progress[id] = onProgress;
    _tx!.send([id, op, args]);
    return (await c.future) as T;
  }

  @override
  Future<void> load(ColumnConfig config, {SimOptions options = const SimOptions(), bool warmStart = true}) =>
      _call('load', [config, options, warmStart]);
  @override
  Future<void> loadSaved(Map<String, Object?> saved) => _call('loadSaved', [saved]);
  @override
  Future<void> rebuild(ColumnConfig config) => _call('rebuild', [config]);
  @override
  Future<double> advance(double simSeconds, Duration wallBudget) =>
      _call('advance', [simSeconds, wallBudget.inMicroseconds]);
  @override
  Future<SimSnapshot> snapshot() => _call('snapshot');

  @override
  Future<FrameResult> frame(FrameRequest req,
      {double advanceSeconds = 0, Duration budget = const Duration(milliseconds: 6)}) async {
    final names = {for (final t in req.trendTags) t};
    for (final n in names) {
      _trendSynced.putIfAbsent(n, () => 0);
    }
    _trendSynced.removeWhere((k, _) => !names.contains(k));
    final reply = await _call<List<Object?>>(
        'frame', [req, advanceSeconds, budget.inMicroseconds, Map<String, int>.of(_trendSynced)]);
    final epoch = reply[2]! as int;
    final payload = reply[1] as Map<Object?, Object?>?;
    final rewound = payload != null && _trendSynced.values.any((v) => v > (payload['nextBin']! as int));
    if (epoch != _epoch || rewound) {
      // a new simulator in the worker: forget the mirrored bins and resync from the start next frame
      _epoch = epoch;
      _trends.reset();
      for (final k in _trendSynced.keys.toList()) {
        _trendSynced[k] = 0;
      }
    } else if (payload != null) {
      final next = _trends.ingest(Map<String, Object?>.from(payload));
      for (final n in (payload['series']! as Map).keys) {
        _trendSynced[n as String] = next;
      }
    }
    return reply[0]! as FrameResult;
  }

  @override
  Future<void> setLever(LeverId id, double value) => _call('setLever', [id, value]);
  @override
  Future<void> setTier(ThermoTier t) => _call('setTier', [t]);
  @override
  Future<void> setLoopMode(LoopTag tag, LoopMode mode) => _call('setLoopMode', [tag, mode]);
  @override
  Future<void> setLoopSp(LoopTag tag, double sp) => _call('setLoopSp', [tag, sp]);
  @override
  Future<void> setLoopOp(LoopTag tag, double op) => _call('setLoopOp', [tag, op]);
  @override
  Future<SteadyStateResult> runToSteadyState(
          {double maxSimSeconds = 172800, void Function(double progress)? onProgress}) =>
      _call('steady', [maxSimSeconds], onProgress);
  @override
  Future<FaultId> injectFault(FaultSpec spec) => _call('injectFault', [spec]);
  @override
  Future<void> clearFault(FaultId id) => _call('clearFault', [id]);
  @override
  Future<ExplainResult> explain(ExplainTarget target) => _call('explain', [target]);
  @override
  Future<Map<String, Object?>> save() async => Map<String, Object?>.from(await _call<Map<Object?, Object?>>('save'));
  @override
  Future<void> acknowledgeAlarm(String alarmId) => _call('ack', [alarmId]);
  @override
  Future<void> acknowledgeAllAlarms() => _call('ackAll');
  @override
  Future<void> requestFieldCheck(String gaugeTag) => _call('fieldCheck', [gaugeTag]);
  @override
  Future<void> requestMaintenance(String tag) => _call('maintenance', [tag]);
  @override
  Future<void> setCheckWindow(double seconds) => _call('checkWindow', [seconds]);
  @override
  Future<void> setTemperatureReference() => _call('tempRef');
  @override
  Future<void> loadPreset(String presetId, {String? tier}) => _call('loadPreset', [presetId, tier]);
  @override
  Future<void> openTrapBypass() => _call('trap');
  @override
  Future<void> startScenario(ScenarioDef def, {int? seed}) => _call('startScenario', [def, seed]);
  @override
  Future<void> takeHint(int index) => _call('hint', [index]);
  @override
  Future<AnswerResult> submitAnswer(String objectiveId, Object answer) => _call('answer', [objectiveId, answer]);
  @override
  Future<DrillResult> submitDiagnosis(Diagnosis d) => _call('diagnosis', [d]);
  @override
  Future<ScoreCard> finishScenario() => _call('finish');
  @override
  Stream<SimEvent> get events => _events.stream;

  @override
  List<LeverSpec> get levers => _levers;
  @override
  ColumnConfig get config => _config ?? (throw StateError('IsolateSimRunner: call load() first'));
  @override
  TrendBuffer get trends => _trends;
  @override
  ThermoModel get thermo => throw UnsupportedError('thermo lives in the engine isolate; use frame()');
  @override
  ThermoModel get idealThermo => throw UnsupportedError('thermo lives in the engine isolate; use frame()');

  @override
  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _rx.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('runner disposed'));
    }
    _pending.clear();
    await _events.close();
  }
}

// ------------------------------------------------------------------ worker

void _worker(SendPort main) {
  final rx = ReceivePort();
  main.send(['ready', rx.sendPort]);
  final runner = LocalSimRunner();
  var epoch = 0;
  Simulator? lastSim;
  ColumnConfig? sentConfig;
  List<LeverSpec>? sentLevers;
  StreamSubscription<SimEvent>? sub;

  RunnerMeta? meta() {
    try {
      final c = runner.config, l = runner.levers;
      if (identical(c, sentConfig) && identical(l, sentLevers)) return null;
      sentConfig = c;
      sentLevers = l;
      return RunnerMeta(c, l);
    } on StateError {
      return null; // not loaded yet
    }
  }

  int currentEpoch() {
    // a replaced simulator bumps the epoch so the main side resyncs the trend mirror
    final s = runner.sim;
    if (!identical(s, lastSim)) {
      lastSim = s;
      epoch++;
    }
    return epoch;
  }

  rx.listen((m) async {
    final msg = m as List<Object?>;
    final id = msg[0]! as int;
    final op = msg[1]! as String;
    final a = msg[2]! as List<Object?>;
    try {
      sub ??= runner.events.listen((e) => main.send([0, 'event', e]));
      final Object? r = switch (op) {
        'load' => await _v(runner.load(a[0]! as ColumnConfig, options: a[1]! as SimOptions, warmStart: a[2]! as bool)),
        'loadSaved' => await _v(runner.loadSaved((a[0]! as Map).cast<String, Object?>())),
        'rebuild' => await _v(runner.rebuild(a[0]! as ColumnConfig)),
        'advance' => await runner.advance(a[0]! as double, Duration(microseconds: a[1]! as int)),
        'snapshot' => await runner.snapshot(),
        'frame' => await _frame(runner, a, currentEpoch),
        'setLever' => await _v(runner.setLever(a[0]! as String, a[1]! as double)),
        'setTier' => await _v(runner.setTier(a[0]! as ThermoTier)),
        'setLoopMode' => await _v(runner.setLoopMode(a[0]! as String, a[1]! as LoopMode)),
        'setLoopSp' => await _v(runner.setLoopSp(a[0]! as String, a[1]! as double)),
        'setLoopOp' => await _v(runner.setLoopOp(a[0]! as String, a[1]! as double)),
        'steady' => await runner.runToSteadyState(
            maxSimSeconds: a[0]! as double, onProgress: (p) => main.send([id, 'progress', p])),
        'injectFault' => await runner.injectFault(a[0]! as FaultSpec),
        'clearFault' => await _v(runner.clearFault(a[0]! as FaultId)),
        'explain' => await runner.explain(a[0]! as ExplainTarget),
        'save' => await runner.save(),
        'ack' => await _v(runner.acknowledgeAlarm(a[0]! as String)),
        'ackAll' => await _v(runner.acknowledgeAllAlarms()),
        'fieldCheck' => await _v(runner.requestFieldCheck(a[0]! as String)),
        'maintenance' => await _v(runner.requestMaintenance(a[0]! as String)),
        'checkWindow' => await _v(runner.setCheckWindow(a[0]! as double)),
        'tempRef' => await _v(runner.setTemperatureReference()),
        'loadPreset' => await _v(runner.loadPreset(a[0]! as String, tier: a[1] as String?)),
        'trap' => await _v(runner.openTrapBypass()),
        'startScenario' => await _v(runner.startScenario(a[0]! as ScenarioDef, seed: a[1] as int?)),
        'hint' => await _v(runner.takeHint(a[0]! as int)),
        'answer' => await runner.submitAnswer(a[0]! as String, a[1]!),
        'diagnosis' => await runner.submitDiagnosis(a[0]! as Diagnosis),
        'finish' => await runner.finishScenario(),
        _ => throw StateError('unknown op $op'),
      };
      main.send([id, 'ok', r, meta()]);
    } catch (e) {
      final kind = e is RangeError ? 'range' : (e is StateError ? 'state' : 'other');
      final text = e is RangeError ? '${e.message}' : (e is StateError ? e.message : '$e');
      main.send([id, 'err', kind, text]);
    }
  });
}

Future<Object?> _frame(LocalSimRunner runner, List<Object?> a, int Function() epoch) async {
  final req = a[0]! as FrameRequest;
  final r = await runner.frame(req, advanceSeconds: a[1]! as double, budget: Duration(microseconds: a[2]! as int));
  final ep = epoch();
  final synced = (a[3]! as Map<Object?, Object?>).cast<String, int>();
  final payload = synced.isEmpty ? null : runner.trends.exportSince(synced);
  return [r, payload, ep];
}

Future<Object?> _v(Future<void> f) async {
  await f;
  return null;
}
