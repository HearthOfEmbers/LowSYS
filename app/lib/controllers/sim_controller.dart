import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

/// Speeds offered in the TimeBar; 0 is pause.
const List<double> kSpeeds = [0, 1, 2, 5, 10, 30, 100, 300, 1000];

/// Owns the [SimRunner], the frame loop (ENGINE_API.md 13.3) and coarse UI state.
/// The per-frame path never rebuilds widgets: painters listen to [snapshot] and [mccabe].
class SimController extends ChangeNotifier {
  final SimRunner runner;
  final McCabeThieleBuilder _builder = McCabeThieleBuilder();

  SimController({SimRunner? runner}) : runner = runner ?? LocalSimRunner();

  /// Latest snapshot (null until loaded).
  final ValueNotifier<SimSnapshot?> snapshot = ValueNotifier<SimSnapshot?>(null);

  /// McCabe-Thiele data for the latest snapshot.
  final ValueNotifier<McCabeThieleData?> mccabe = ValueNotifier<McCabeThieleData?>(null);

  /// Column structure (trays, feed tray); changes rarely, so the static vessel layer rebuilds rarely.
  final ValueNotifier<({int trays, int feed})> structure = ValueNotifier((trays: 20, feed: 10));

  /// Lever values (SI); notifies only when a value changed.
  final ValueNotifier<Map<String, double>> leverValues = ValueNotifier(const {});

  /// Selected stage (0 = drum, 1..N trays, N+1 = sump), or null.
  final ValueNotifier<int?> selectedStage = ValueNotifier<int?>(null);

  /// 0..1 while a run-to-steady-state is in progress, otherwise null.
  final ValueNotifier<double?> steadyProgress = ValueNotifier<double?>(null);

  /// Achieved speed (sim s per wall s), smoothed.
  final ValueNotifier<double> achievedSpeed = ValueNotifier<double>(0);

  /// Outcome message of the last run-to-steady-state (null if none or dismissed).
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  PresetId presetId = Presets.bt;
  double _speed = 10;
  bool _paused = false;
  bool speedLimited = false;
  bool _loaded = false;
  bool _busy = false;
  double _debt = 0;
  Duration _lastTick = Duration.zero;
  bool showRmin = false;

  double get speed => _speed;
  bool get paused => _paused || _speed == 0;
  bool get loaded => _loaded;
  bool get runningToSteady => steadyProgress.value != null;
  List<LeverSpec> get levers => runner.levers;
  ColumnConfig get config => runner.config;

  Future<void> load(PresetId id) async {
    _loaded = false;
    presetId = id;
    _debt = 0;
    selectedStage.value = null;
    await runner.load(Presets.byId(id));
    _loaded = true;
    await _refresh();
    notifyListeners();
  }

  Future<void> _refresh() async {
    final s = await runner.snapshot();
    snapshot.value = s;
    mccabe.value = _builder.build(s, runner.thermo, showRmin: showRmin);
    final st = (trays: s.layout.nTrays, feed: s.layout.feedStages.first);
    if (st != structure.value) structure.value = st;
    if (!mapEquals(s.levers, leverValues.value)) leverValues.value = s.levers;
  }

  void setSpeed(double v) {
    _speed = v;
    _paused = v == 0;
    notifyListeners();
  }

  void togglePause() {
    if (_speed == 0) _speed = 1;
    _paused = !_paused;
    notifyListeners();
  }

  void stepSpeed(int dir) {
    final i = kSpeeds.indexOf(_speed);
    final j = (i + dir).clamp(1, kSpeeds.length - 1);
    setSpeed(kSpeeds[j]);
  }

  void toggleRmin() {
    showRmin = !showRmin;
    _refresh();
    notifyListeners();
  }

  /// Frame callback from the screen's Ticker.
  Future<void> onTick(Duration elapsed) async {
    final wall = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_loaded || _busy || paused || runningToSteady) return;
    _busy = true;
    try {
      final dtWall = wall.clamp(0.0, 0.1);
      _debt += dtWall * _speed;
      final cap = math.max(2 * (1 / 60) * _speed, 1.0); // always allow at least two steps of 0.5 s
      if (_debt > cap) _debt = cap;
      final requested = _debt;
      final adv = await runner.advance(_debt, const Duration(milliseconds: 6));
      _debt -= adv;
      if (dtWall > 0) {
        final inst = adv / dtWall;
        achievedSpeed.value = achievedSpeed.value * 0.9 + inst * 0.1;
      }
      final limited = dtWall * _speed > cap || (requested >= 0.5 && adv < 0.9 * requested);
      if (limited != speedLimited) {
        speedLimited = limited;
        notifyListeners();
      }
      await _refresh();
    } finally {
      _busy = false;
    }
  }

  Future<void> setLever(LeverId id, double value) async {
    if (!_loaded) return;
    try {
      await runner.setLever(id, value);
    } on RangeError {
      return;
    }
    if (id == 'nTrays') {
      selectedStage.value = null;
      notifyListeners();
    }
    await _refresh();
  }

  /// Run to steady state in 50 ms slices; the dialog watches [steadyProgress].
  Future<void> runToSteady({double maxSimSeconds = 172800}) async {
    if (!_loaded || runningToSteady) return;
    final wasPaused = _paused;
    steadyProgress.value = 0;
    notifyListeners();
    final r = await runner.runToSteadyState(
      maxSimSeconds: maxSimSeconds,
      onProgress: (p) => steadyProgress.value = p,
    );
    steadyProgress.value = null;
    _paused = wasPaused;
    if (r.stillConverging) {
      final tau = (r.slowModeTau! / 3600).toStringAsFixed(1);
      notice.value = 'Still converging (slow mode, tau about $tau h). Run again to continue.';
    } else if (!r.reached) {
      notice.value = 'No steady state found within ${(maxSimSeconds / 3600).toStringAsFixed(0)} h of simulated time.';
    } else {
      notice.value = null;
    }
    await _refresh();
    notifyListeners();
  }

  void selectStage(int? stage) => selectedStage.value = stage;

  Future<void> reset() => load(presetId);

  @override
  void dispose() {
    snapshot.dispose();
    structure.dispose();
    leverValues.dispose();
    mccabe.dispose();
    selectedStage.dispose();
    steadyProgress.dispose();
    achievedSpeed.dispose();
    notice.dispose();
    runner.dispose();
    super.dispose();
  }
}
