import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../painters/profile_painter.dart' show TierGhost;
import 'save_store.dart';

/// Speeds offered in the TimeBar; 0 is pause.
const List<double> kSpeeds = [0, 1, 2, 5, 10, 30, 100, 300, 1000];

/// Owns the [SimRunner], the frame loop (ENGINE_API.md 13.3) and coarse UI state.
/// The per-frame path never rebuilds widgets: painters listen to [snapshot] and [mccabe].
class SimController extends ChangeNotifier {
  final SimRunner runner;
  final McCabeThieleBuilder _builder = McCabeThieleBuilder();

  SimController({SimRunner? runner}) : runner = runner ?? LocalSimRunner();

  /// Latest snapshot (null until loaded).
  final ValueNotifier<SimSnapshot?> snapshot = ValueNotifier<SimSnapshot?>(
    null,
  );

  /// McCabe-Thiele data for the latest snapshot.
  final ValueNotifier<McCabeThieleData?> mccabe =
      ValueNotifier<McCabeThieleData?>(null);

  /// Column structure (trays, feed tray); changes rarely, so the static vessel layer rebuilds rarely.
  final ValueNotifier<({int trays, int feed})> structure = ValueNotifier((
    trays: 20,
    feed: 10,
  ));

  /// Broken trays from the visible faults (stage to open fraction); the static vessel layer redraws on change.
  final ValueNotifier<Map<int, double>> brokenStages = ValueNotifier(const {});

  /// Lever values (SI); notifies only when a value changed.
  final ValueNotifier<Map<String, double>> leverValues = ValueNotifier(
    const {},
  );

  /// Diagram tab (0 McCabe-Thiele, 1 Profiles) and the profile quantity (index into ProfileKind).
  final ValueNotifier<int> diagramTab = ValueNotifier<int>(0);
  final ValueNotifier<int> profileKind = ValueNotifier<int>(0);

  /// Control tab (0 Levers, 1 Loops, 2 Balance, 3 Trends, 4 Faults, 5 Energy).
  final ValueNotifier<int> controlTab = ValueNotifier<int>(0);

  /// Active theme id (Blueprint or Control Room, SCOPE.md 7.2) and the Control Room's composition shading option.
  final ValueNotifier<String> themeId = ValueNotifier<String>('blueprint');
  final ValueNotifier<bool> compositionShading = ValueNotifier<bool>(false);

  /// Display unit system (SCOPE.md 4: SI / US field, switchable at runtime).
  final ValueNotifier<UnitSystem> units = ValueNotifier<UnitSystem>(
    UnitSystem.si,
  );

  /// Math overlay: the target being explained and the live result (re-evaluated about 4 times a second).
  final ValueNotifier<ExplainTarget?> mathTarget =
      ValueNotifier<ExplainTarget?>(null);
  final ValueNotifier<ExplainResult?> mathResult =
      ValueNotifier<ExplainResult?>(null);

  /// Active scenario, if any; [scenarioTick] changes when objectives or hints change.
  ScenarioDef? scenarioDef;
  final ValueNotifier<int> scenarioTick = ValueNotifier<int>(0);
  bool _finishing = false;

  /// Scenario state of the latest snapshot (objectives, hints, messages, timer).
  ScenarioSnapshot? get scenario => snapshot.value?.scenario;

  /// Persistence for settings and sandbox slots; autosave runs every 60 s of wall time.
  SaveStore? saveStore;
  double _autosaveWall = 0;
  final ValueNotifier<String?> saveMessage = ValueNotifier<String?>(null);

  /// Loop or instrument tag whose faceplate is open, and the trend tags shown.
  final ValueNotifier<String?> selectedLoop = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> trendTags = ValueNotifier<List<String>>(
    const ['PV:FT-102', 'PV:LT-101'],
  );
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

  static bool perfRecording = false;
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
  Future<void> load(
    PresetId id, {
    ColumnConfig? config,
    bool keepScenario = false,
  }) async {
    _loaded = false;
    presetId = id;
    _debt = 0;
    selectedStage.value = null;
    closeMath();
    if (!keepScenario) {
      scenarioDef = null;
      scoreCard = null;
    }
    await runner.load(
      config ?? Presets.byId(id).copyWith(hydraulics: HydraulicsMode.full),
    );
    if (!keepScenario)
      await runner.setLever('noise', 1); // sandbox default (SCOPE.md 3, M3)
    _loaded = true;
    await _refresh();
    notifyListeners();
  }

  Future<void> setTheme(String id) async {
    themeId.value = id;
    try {
      await saveStore?.write('settings.theme', id);
    } on Object {
      // settings are a convenience
    }
  }

  Future<void> restoreSettings() async {
    final store = saveStore;
    if (store == null) return;
    try {
      final id = await store.read('settings.theme');
      if (id != null && id.isNotEmpty) themeId.value = id;
    } on Object {
      // ignore
    }
  }

  void toggleUnits() {
    units.value = units.value == UnitSystem.si
        ? UnitSystem.usField
        : UnitSystem.si;
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
    _loaded = false;
    closeMath();
    selectedStage.value = null;
    _debt = 0;
    scoreCard = null;
    debriefText = null;
    _finishing = false;
    presetId = def.preset;
    await runner.startScenario(
      def,
      seed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
    );
    scenarioDef = def;
    _loaded = true;
    scenarioTick.value++;
    await _refresh();
    notifyListeners();
  }

  /// Ends the scenario: score card and debrief text from the engine.
  Future<void> finishScenario() async {
    if (scenarioDef == null || scoreCard != null) return;
    scoreCard = await runner.finishScenario();
    debriefText = scoreCard!.debriefText;
    scenarioTick.value++;
    notifyListeners();
  }

  void leaveScenario() {
    scenarioDef = null;
    scoreCard = null;
    scenarioTick.value++;
    load(presetId);
  }

  Future<void> takeHint(int index) async {
    await runner.takeHint(index);
    await _refresh();
    scenarioTick.value++;
  }

  Future<AnswerResult> submitAnswer(String objectiveId, Object answer) async {
    final r = await runner.submitAnswer(objectiveId, answer);
    await _refresh();
    scenarioTick.value++;
    return r;
  }

  Future<DrillResult> submitDiagnosis(Diagnosis d) async {
    final r = await runner.submitDiagnosis(d);
    await _refresh();
    scenarioTick.value++;
    return r;
  }

  String _scenarioSig = '';
  void _updateScenario(SimSnapshot s) {
    final sc = s.scenario;
    if (sc == null) return;
    final sig =
        '${sc.objectives.where((o) => o.met).length}/${sc.hints.where((h) => h.unlocked).length}/${sc.messages.length}/${sc.finished}/${(sc.elapsed / 5).floor()}';
    if (sig != _scenarioSig) {
      _scenarioSig = sig;
      scenarioTick.value++;
    }
    if (sc.finished && scoreCard == null && !_finishing) {
      _finishing = true;
      finishScenario();
    }
  }

  // ---------------------------------------------------------------- M3 operator actions

  /// V and L of the tier just left (ghost ticks on the V and L profiles, PHYSICS.md 14.5).
  final ValueNotifier<TierGhost?> tierGhost = ValueNotifier<TierGhost?>(null);

  /// Thermodynamic tier switch (PHYSICS.md 13.5): T1 textbook (CMO) or T2 ideal + energy balances.
  Future<void> setTier(ThermoTier t) async {
    if (!_loaded) return;
    final before = snapshot.value;
    if (before != null && before.tier == t) return;
    // Tier 1 has a total condenser only (PHYSICS.md 7.2): a partial condenser stays in Tier 2
    if (t == ThermoTier.t1 && (before?.condenser?.partial ?? false)) return;
    await runner.setTier(t);
    if (before != null) {
      tierGhost.value = TierGhost(
        before.tier == ThermoTier.t1 ? 'Tier 1' : 'Tier 2',
        List<double>.from(before.stages.vaporUp),
        List<double>.from(before.stages.liquidDown),
      );
    }
    await _refresh();
    notifyListeners();
  }

  /// Loads another preset at its steady state, keeping a running scenario (G7).
  Future<void> loadPreset(String id, {ThermoTier? tier}) async {
    if (!_loaded) return;
    await runner.loadPreset(id, tier: tier?.name);
    presetId = id;
    await _refresh();
    notifyListeners();
  }

  /// "Set reference" of the C6 temperature profile.
  Future<void> setTemperatureReference() async {
    await runner.setTemperatureReference();
    await _refresh();
  }

  /// F14: open the trap bypass.
  Future<void> openTrapBypass() async {
    await runner.openTrapBypass();
    await _refresh();
  }

  Future<void> setLoopMode(LoopTag tag, LoopMode mode) async {
    try {
      await runner.setLoopMode(tag, mode);
    } on StateError catch (e) {
      notice.value = e.message;
    }
    await _refresh();
  }

  Future<void> setLoopSp(LoopTag tag, double sp) async {
    await runner.setLoopSp(tag, sp);
    await _refresh();
  }

  Future<void> setLoopOp(LoopTag tag, double op) async {
    try {
      await runner.setLoopOp(tag, op);
    } on StateError {
      return;
    }
    await _refresh();
  }

  Future<void> acknowledge(String id) async {
    await runner.acknowledgeAlarm(id);
    await _refresh();
  }

  Future<void> acknowledgeAll() async {
    await runner.acknowledgeAllAlarms();
    await _refresh();
  }

  Future<void> fieldCheck(String gauge) async {
    await runner.requestFieldCheck(gauge);
    await _refresh();
  }

  Future<void> maintenance(String tag) async {
    try {
      await runner.requestMaintenance(tag);
    } on StateError catch (e) {
      notice.value = e.message;
    }
    await _refresh();
  }

  double checkWindow = 600;

  Future<void> setCheckWindow(double seconds) async {
    checkWindow = seconds;
    await runner.setCheckWindow(seconds);
    await _refresh();
  }

  TrendBuffer get trends => runner.trends;

  // ---------------------------------------------------------------- sandbox save and load

  /// Saves the sandbox state to slot [n] (0 is the autosave).
  Future<void> saveSandbox(int n) async {
    final store = saveStore;
    if (store == null || !_loaded) return;
    final saved = await runner.save();
    await store.write('sandbox.slot.$n', encodeJson(saved));
    notice.value = n == 0 ? null : 'Saved to slot $n';
  }

  Future<bool> loadSandbox(int n) async {
    final store = saveStore;
    if (store == null) return false;
    final text = await store.read('sandbox.slot.$n');
    if (text == null) return false;
    _loaded = false;
    scenarioDef = null;
    scoreCard = null;
    closeMath();
    await runner.loadSaved(decodeJson(text)! as Map<String, Object?>);
    _loaded = true;
    await _refresh();
    notifyListeners();
    notice.value = 'Loaded slot $n';
    return true;
  }

  /// Wall time (microseconds) of the last frames' engine advance, snapshot and diagram build (perf run only).
  static final List<int> perfAdvance = [], perfSnapshot = [], perfMccabe = [], perfNotify = [];

  // Loop OPs move every step with noise on; no lever tile shows them, so they must not rebuild the lever panel.
  static const Set<String> _opLevers = {'feedFlowOp', 'refluxOp', 'boilupOp', 'distillateValve', 'bottomsValve'};

  static bool _sameLevers(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (_opLevers.contains(e.key)) continue;
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<void> _refresh() async {
    final sw = Stopwatch()..start();
    final s = await runner.snapshot();
    final t1 = sw.elapsedMicroseconds;
    snapshot.value = s;
    final t2 = sw.elapsedMicroseconds;
    mccabe.value = _builder.build(s, runner.thermo, showRmin: showRmin);
    if (perfRecording) {
      perfSnapshot.add(t1);
      perfNotify.add(t2 - t1);
      perfMccabe.add(sw.elapsedMicroseconds - t2);
    }
    final st = (trays: s.layout.nTrays, feed: s.layout.feedStages.first);
    if (st != structure.value) structure.value = st;
    if (!_sameLevers(s.levers, leverValues.value)) leverValues.value = s.levers;
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
    _autosaveWall += wall.clamp(0.0, 0.5);
    if (_autosaveWall >= 60 && _loaded && scenarioDef == null) {
      _autosaveWall = 0;
      saveSandbox(0);
    }
    if (!_loaded || _busy || paused || runningToSteady) return;
    _busy = true;
    try {
      final dtWall = wall.clamp(0.0, 0.1);
      _debt += dtWall * _speed;
      final cap = math.max(
        2 * (1 / 60) * _speed,
        1.0,
      ); // always allow at least two steps of 0.5 s
      if (_debt > cap) _debt = cap;
      final requested = _debt;
      final swA = Stopwatch()..start();
      final adv = await runner.advance(_debt, const Duration(milliseconds: 6));
      if (perfRecording) perfAdvance.add(swA.elapsedMicroseconds);
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
      notice.value =
          'Still converging (slow mode, tau about $tau h). Run again to continue.';
    } else if (!r.reached) {
      notice.value =
          'No steady state found within ${(maxSimSeconds / 3600).toStringAsFixed(0)} h of simulated time.';
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
    themeId.dispose();
    tierGhost.dispose();
    compositionShading.dispose();
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
    selectedLoop.dispose();
    trendTags.dispose();
    saveMessage.dispose();
    runner.dispose();
    super.dispose();
  }
}
