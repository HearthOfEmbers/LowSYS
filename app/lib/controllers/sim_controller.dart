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

  /// Broken trays from the visible faults (stage to open fraction); the static vessel layer redraws on change.
  final ValueNotifier<Map<int, double>> brokenStages = ValueNotifier(const {});

  /// Lever values (SI); notifies only when a value changed.
  final ValueNotifier<Map<String, double>> leverValues = ValueNotifier(const {});

  /// Diagram tab (0 McCabe-Thiele, 1 Profiles) and the profile quantity (index into ProfileKind).
  final ValueNotifier<int> diagramTab = ValueNotifier<int>(0);
  final ValueNotifier<int> profileKind = ValueNotifier<int>(0);

  /// Control tab (0 Levers, 1 Faults).
  final ValueNotifier<int> controlTab = ValueNotifier<int>(0);

  /// Display unit system (SCOPE.md 4: SI / US field, switchable at runtime).
  final ValueNotifier<UnitSystem> units = ValueNotifier<UnitSystem>(UnitSystem.si);

  /// Math overlay: the target being explained and the live result (re-evaluated about 4 times a second).
  final ValueNotifier<ExplainTarget?> mathTarget = ValueNotifier<ExplainTarget?>(null);
  final ValueNotifier<ExplainResult?> mathResult = ValueNotifier<ExplainResult?>(null);

  /// Active scenario, if any; [scenarioTick] changes when objectives or hints change.
  ScenarioDef? scenarioDef;
  ScenarioRunner? scenario;
  final ValueNotifier<int> scenarioTick = ValueNotifier<int>(0);
  ScoreCard? scoreCard;
  String? debriefText;

  /// Levers the scenario locks.
  Set<String> get lockedLevers => {...?scenarioDef?.leverLock};

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

  /// Sandbox default is full hydraulics (SCOPE.md 4.2); the preset itself stays ideal (docs/DEVIATIONS.md E19).
  Future<void> load(PresetId id, {ColumnConfig? config, bool keepScenario = false}) async {
    _loaded = false;
    presetId = id;
    _debt = 0;
    selectedStage.value = null;
    closeMath();
    if (!keepScenario) {
      scenario = null;
      scenarioDef = null;
      scoreCard = null;
    }
    await runner.load(config ?? Presets.byId(id).copyWith(hydraulics: HydraulicsMode.full));
    _loaded = true;
    await _refresh();
    notifyListeners();
  }

  void toggleUnits() {
    units.value = units.value == UnitSystem.si ? UnitSystem.usField : UnitSystem.si;
  }

  // ---------------------------------------------------------------- math overlay

  Future<void> openMath(ExplainTarget target) async {
    mathTarget.value = target;
    mathResult.value = await runner.explain(target);
  }

  void closeMath() {
    mathTarget.value = null;
    mathResult.value = null;
  }

  int _mathFrame = 0;
  Future<void> _refreshMath() async {
    final t = mathTarget.value;
    if (t == null || ++_mathFrame % 15 != 0) return;
    mathResult.value = await runner.explain(t);
  }

  // ---------------------------------------------------------------- faults

  Future<FaultId> injectFault(FaultSpec spec) async {
    final id = await runner.injectFault(spec);
    await _refresh();
    return id;
  }

  Future<void> clearFault(FaultId id) async {
    await runner.clearFault(id);
    await _refresh();
  }

  // ---------------------------------------------------------------- scenarios

  Future<void> startScenario(ScenarioDef def) async {
    await load(def.preset, config: def.buildConfig(), keepScenario: true);
    scenarioDef = def;
    scoreCard = null;
    debriefText = null;
    for (final e in def.leverSet.entries) {
      await runner.setLever(e.key, e.value);
    }
    scenario = ScenarioRunner(def, _ControllerHost(this));
    scenarioTick.value++;
    await _refresh();
    scenario!.update(snapshot.value);
    notifyListeners();
  }

  /// Ends the scenario: score card and debrief text.
  void finishScenario() {
    final r = scenario;
    if (r == null) return;
    scoreCard = r.finish();
    debriefText = r.debriefText(snapshot.value!);
    scenarioTick.value++;
    notifyListeners();
  }

  void leaveScenario() {
    scenario = null;
    scenarioDef = null;
    scoreCard = null;
    scenarioTick.value++;
    notifyListeners();
  }

  void _updateScenario(SimSnapshot s) {
    final r = scenario;
    if (r == null || scoreCard != null) return;
    final before = '${r.objectives.where((o) => o.achieved).length}/${r.unlockedHints.length}';
    r.update(s);
    final after = '${r.objectives.where((o) => o.achieved).length}/${r.unlockedHints.length}';
    if (before != after || s.time.floor() % 5 == 0) scenarioTick.value++;
  }

  Future<void> _refresh() async {
    final s = await runner.snapshot();
    snapshot.value = s;
    mccabe.value = _builder.build(s, runner.thermo, showRmin: showRmin);
    final st = (trays: s.layout.nTrays, feed: s.layout.feedStages.first);
    if (st != structure.value) structure.value = st;
    if (!mapEquals(s.levers, leverValues.value)) leverValues.value = s.levers;
    final br = <int, double>{};
    for (final fa in s.visibleFaults) {
      if (fa.type == FaultType.trayDamage && fa.location.stageFrom != null) {
        for (var j = fa.location.stageFrom!; j <= fa.location.stageTo!; j++) {
          br[j] = fa.severity;
        }
      }
    }
    if (!mapEquals(br, brokenStages.value)) brokenStages.value = br;
    _updateScenario(s);
    _refreshMath();
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
      final limited = dtWall * _speed > cap || (requested - adv > 1.0);
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
    brokenStages.dispose();
    leverValues.dispose();
    mccabe.dispose();
    units.dispose();
    diagramTab.dispose();
    profileKind.dispose();
    controlTab.dispose();
    mathTarget.dispose();
    mathResult.dispose();
    scenarioTick.dispose();
    selectedStage.dispose();
    steadyProgress.dispose();
    achievedSpeed.dispose();
    notice.dispose();
    runner.dispose();
    super.dispose();
  }
}

/// Lets a [ScenarioRunner] drive the controller's runner (calls complete synchronously on the local runner).
class _ControllerHost implements ScenarioHost {
  final SimController c;
  _ControllerHost(this.c);
  @override
  SimSnapshot snapshot() => c.snapshot.value!;
  @override
  void setLever(LeverId id, double value) {
    c.setLever(id, value);
  }

  @override
  void setLoopMode(LoopTag tag, LoopMode mode) {
    c.runner.setLoopMode(tag, mode);
  }

  @override
  FaultId injectFault(FaultSpec spec) {
    c.runner.injectFault(spec);
    return '';
  }

  @override
  void clearFault(FaultId id) {
    c.runner.clearFault(id);
  }
}
