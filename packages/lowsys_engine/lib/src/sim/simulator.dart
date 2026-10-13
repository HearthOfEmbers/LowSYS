import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../config/column_config.dart';
import '../config/presets.dart';
import '../config/tray_geometry.dart';
import '../control/control_system.dart';
import '../control/cross_checks.dart';
import '../control/trend_buffer.dart';
import '../core/rng.dart';
import '../core/ids.dart';
import '../core/quantity.dart';
import '../faults/fault_effects.dart';
import '../faults/fault_manager.dart';
import '../explain/explain_engine.dart';
import '../explain/explain_types.dart';
import '../model/thermosyphon.dart';
import '../model/tray_hydraulics.dart';
import '../model/column_state.dart';
import '../scenario/drill.dart';
import '../scenario/scenario_def.dart';
import '../scenario/scenario_runner.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/component.dart';
import '../thermo/thermo_model.dart';
import '../thermo/tier1_constant_alpha.dart';
import '../thermo/thermo_factory.dart';
import '../thermo/tier2_raoult.dart';
import '../thermo/tier3_depriester.dart';
import 'lever_spec.dart';
import 'stepper.dart';

/// Outcome of [Simulator.runToSteadyState].
class SteadyStateResult {
  final bool reached;

  /// Simulated seconds until the steady-state monitor of PHYSICS.md 13.3 declared steady (VC-7.4).
  final double simSeconds;

  /// Simulated seconds of the whole run, including the polish phase that continues until the
  /// residual is below the polish tolerance so the state is converged far below 1e-6.
  final double totalSimSeconds;

  /// Last steady-state residual delta (PHYSICS.md 13.3).
  final double residual;

  /// When not reached: estimated time constant (s) of the slowest mode from the residual decay,
  /// or null if the residual is not decaying. A caller can report "still converging" and extend the run.
  final double? slowModeTau;

  /// True when the run stopped at its cap while the residual was still decaying.
  bool get stillConverging => !reached && slowModeTau != null;
  const SteadyStateResult({
    this.slowModeTau,
    required this.reached,
    required this.simSeconds,
    double? totalSimSeconds,
    required this.residual,
  }) : totalSimSeconds = totalSimSeconds ?? simSeconds;
}

/// A resumable run to steady state, so a UI can march it in slices of wall time.
class SteadyRun {
  final Simulator _sim;
  final double maxSimSeconds;
  final double dt;
  final double polishTolerance;
  final double _t0;
  SteadyStateResult? _result;
  double? _declaredAt;

  final bool _noiseWas;

  SteadyRun._(this._sim, this.maxSimSeconds, this.dt, this.polishTolerance)
      : _t0 = _sim.time,
        _noiseWas = _sim._control.noise {
    if (_noiseWas) _sim._setNoise(false);
  }

  /// Result, restoring the noise lever (PHYSICS.md 13.3: noise is suspended while the run marches).
  SteadyStateResult _finalize(bool reached) {
    final r = _make(reached);
    if (_noiseWas) _sim._setNoise(true);
    return r;
  }

  bool get done => _result != null;
  SteadyStateResult? get result => _result;

  /// 0..1 estimate from the residual.
  double get progress {
    if (done) return 1;
    final r = _sim.steadyResidual;
    if (!r.isFinite) return 0;
    final tol =
        polishTolerance.isFinite ? math.min(polishTolerance, 1e-7) : 1e-7;
    final p = (-(math.log(r) / math.ln10) - 2.0) /
        (-(math.log(tol) / math.ln10) - 2.0);
    return p.clamp(0.0, 0.99);
  }

  SteadyStateResult _make(bool reached) => SteadyStateResult(
        reached: reached,
        simSeconds: _declaredAt ?? (_sim.time - _t0),
        totalSimSeconds: _sim.time - _t0,
        residual: _sim.steadyResidual,
        slowModeTau: reached ? null : _sim.slowModeTau,
      );

  /// Marches until done or [budget] of wall time is used. Returns [done].
  bool advance(Duration budget) {
    if (done) return true;
    final sw = Stopwatch()..start();
    var k = 0;
    while (true) {
      final steps = 30; // one monitor interval at dt = 2 s
      for (var i = 0; i < steps; i++) {
        _sim._stepOnce(dt);
        if (_sim._halted) {
          _result = _finalize(false);
          return true;
        }
      }
      k++;
      if (_declaredAt == null && _sim.isSteady) _declaredAt = _sim.time - _t0;
      if (_sim.isSteady && _sim.steadyResidual <= polishTolerance) {
        _result = _finalize(true);
        _sim._emit(SimEventType.steadyReached, 'Steady state reached');
        return true;
      }
      if (_sim.time - _t0 >= maxSimSeconds) {
        _result = _finalize(false);
        return true;
      }
      if (sw.elapsedMicroseconds > budget.inMicroseconds && k > 0) return false;
    }
  }
}

/// The M1 simulator: binary or multicomponent Tier 1 column (constant alpha, CMO), ideal hydraulics.
/// Single-threaded and synchronous; it never reads a wall clock (ENGINE_API.md 6).
class Simulator {
  ColumnConfig _config;
  final SimOptions options;
  ThermoTier _tier = ThermoTier.t1;
  HydraulicsMode _hydraulics = HydraulicsMode.ideal;

  late Tier1ConstantAlpha _thermo;
  late Tier2Raoult _t2;

  /// Tier-3 model (NRTL, DePriester, or Raoult again for `sameAsTier2`), PHYSICS.md 3.4.
  late Tier2Raoult _t3;

  /// The energy-balance model of the active tier (Tier 2 Raoult or the Tier-3 model).
  Tier2Raoult get _active => _tier == ThermoTier.t3 ? _t3 : _t2;
  late ColumnState _state;
  late StepInputs _inputs;
  late ControlSystem _control;
  late Stepper _stepper;
  late HydraulicSolver _hyd;
  late EffectiveParams _ep;
  late FaultManager _faults;
  late TrendBuffer _trends;
  late CrossCheckEngine _checks;
  final Map<String, Rng> _fieldRng = {};
  final Map<String, _FieldReq> _fields = {};
  double _lastEvalEnd = -1;
  double _levelViolation = 0;
  double? _pinDrum;
  late StepDebug _debug;
  late List<LeverSpec> _levers;
  final SolverHealth _health = SolverHealth();
  final StreamController<SimEvent> _events =
      StreamController<SimEvent>.broadcast();

  double _carry = 0;
  int _serial = 0;

  /// Reboiler duty lever (W) remembered while the column runs Tier 1.
  double _dutyLever = 1301477.0;

  /// Feed-tray fraction phi = feedStage / N, stored when the feed tray is set explicitly and kept across
  /// tray-count rebuilds (PHYSICS.md 13.4).
  double _feedPhi = 0.5;
  late int _seed = options.seed;
  ScenarioRunner? _scenario;
  final List<(String, double)> _failLog = [];
  final Set<String> _failSeen = {};
  bool _halted = false;

  // steady-state monitor (PHYSICS.md 13.3)
  double _nextCheck = 60;
  Float64List _prevX = Float64List(0);
  Float64List _prevM = Float64List(0);
  final Float64List _prevOp = Float64List(5);
  // noise-on monitor: 300-s means (PHYSICS.md 13.3)
  Float64List _sumX = Float64List(0),
      _sumM = Float64List(0),
      _prevMeanX = Float64List(0),
      _prevMeanM = Float64List(0);
  final Float64List _sumOp = Float64List(5), _prevMeanOp = Float64List(5);
  int _nSum = 0;
  bool _hasPrevMean = false;
  double _nextCheckNoisy = 300;
  int _noisyCount = 0;
  SimView _view = SimView.model;
  int _steadyCount = 0;
  bool _steady = false;
  double _residual = double.infinity;
  double _prevResidual = double.infinity;

  static final Map<String, Map<String, Object?>> _warmCache = {};

  Simulator(ColumnConfig config,
      {this.options = const SimOptions(), bool warmStart = true})
      : _config = config {
    _build(config, null);
    if (warmStart) _applyWarmStart();
  }

  Simulator._restoring(ColumnConfig config, this.options, int seed)
      : _config = config {
    _seed = seed;
    _build(config, null);
  }

  // ---------------------------------------------------------------- construction

  void _build(ColumnConfig config, _Carry? carry) {
    final problems = config.validate();
    if (problems.isNotEmpty) throw ConfigException(problems.join('; '));
    _config = config;
    _tier = config.tier;
    _hydraulics = config.hydraulics;
    final nc = config.nc;
    final N = config.trayCount;
    _thermo = Tier1ConstantAlpha.fromConfig(config);
    _t2 = Tier2Raoult.fromConfig(config);
    _t3 = ThermoFactory.buildTier3(config);
    final feed = config.feeds.first;
    final lev = config.initialLevers;

    final inp = StepInputs(nc);
    inp.feedFlowSp = lev['feedFlow'] ?? feed.flow;
    inp.refluxFlowSp = lev['refluxFlow'] ?? 0.0;
    inp.refluxRatio = lev['refluxRatio'] ?? 2.0;
    inp.ratioMode = (lev['refluxMode'] ?? 0) >= 0.5;
    inp.boilupSp = lev['boilup'] ?? 0.0;
    inp.feedQ = lev['feedQ'] ??
        (feed.thermal is FeedQ ? (feed.thermal as FeedQ).q : 1.0);
    inp.feedStage = feed.stage;
    if (carry == null) _feedPhi = feed.stage / N;
    inp.murphree = config.murphree;
    for (var i = 0; i < nc; i++) {
      inp.z[i] = feed.z[i];
    }
    inp.pTopInit = lev['pTop'] ?? config.condenser.pTopDesign;
    inp.steamHeaderP = config.reboiler.steamHeaderPressure;
    inp.cwInT = config.condenser.cwInletT;
    inp.cwMaxFlow = config.condenser.cwMaxFlow;
    inp.refluxSub = lev['refluxSubcooling'] ?? 0.0;
    inp.inertVent = lev['inertVent'] ?? 0.0;
    inp.feedSat = lev['feedT'] == null &&
        feed.thermal is FeedQ &&
        (feed.thermal as FeedQ).q == 1.0;
    inp.feedT = lev['feedT'] ?? _feedTemperature(config, inp);
    _dutyLever = lev['reboilerDuty'] ?? 1301477.0;
    _inputs = inp;

    // design flows for the level-loop valves (PHYSICS.md 10.4: D_max = 2 x design D)
    final f0 = inp.feedFlowSp;
    final v1 = inp.boilupSp + (1 - inp.feedQ) * f0;
    final l0 = inp.ratioMode
        ? inp.refluxRatio * v1 / (inp.refluxRatio + 1)
        : inp.refluxFlowSp;
    final d0 = math.max(0.0, v1 - l0);
    final b0 = math.max(0.0, f0 - d0);
    final dMax = config.control.distillateMax ??
        (d0 > 0 ? 2 * d0 : math.max(2 * f0, 1e-6));
    final bMax =
        config.control.bottomsMax ?? (b0 > 0 ? 2 * b0 : math.max(2 * f0, 1e-6));
    _control = ControlSystem.bt(
        ControlDesign(
          feedFlow: f0,
          refluxFlow: l0,
          boilup: inp.boilupSp,
          distillate: d0,
          bottoms: b0,
          dMax: dMax,
          bMax: bMax,
          drumLevelSp: config.control.drumLevelSp,
          sumpLevelSp: config.control.sumpLevelSp,
          levelKc: config.control.levelKc,
          levelTi: config.control.levelTi,
          pTopDesign: config.condenser.pTopDesign,
          cwMaxFlow: config.condenser.cwMaxFlow,
          dutyDesign: _dutyLever,
          nTrays: N,
          tc101Tray: config.control.tc101Tray,
          trays: config.control.trayList(N),
          partial: _isPartial(config),
          feedMax: _rangeMax(config, 'feedFlow', 250),
          refluxMax: _rangeMax(config, 'refluxFlow', 300),
          boilupMax: _rangeMax(config, 'boilup', 300),
          dutyMax: _rangeMax(config, 'reboilerDuty', 3.0e6, kmolh: false),
          dTbubDp: config.condenser.dTbubDp,
          pcKc: config.condenser.pcKc,
          thermosyphon: config.reboiler.type == ReboilerType.thermosyphon ? config.reboiler.thermosyphon : null,
          dvMax: config.condenser.dvMax,
          cwManualOp: lev['cwOP'] ?? config.condenser.cwOpPartial,
        ),
        _seed);
    _trends = TrendBuffer();
    _control.attachTrends(_trends);
    _control.setNoise(options.measurementNoise);
    _checks = CrossCheckEngine();
    _control.onMaintenanceDone = (tag) => _faults.clearTag(tag);

    _state = ColumnState(N, nc);
    _debug = StepDebug(nc);
    final sec = config.traySection;
    final stageGeom = _stageGeometries(config);
    _ep = EffectiveParams(N + 2, nc);
    _faults = carry?.faults ??
        FaultManager(
            systemFactor: sec.geometry.systemFactor,
            phiDcBase: sec.geometry.downcomerAeration);
    _faults.onChange = _noteChange;
    _faults.componentIds = config.components;
    _faults.validator = (spec) => _control.validateFault(spec);
    _hyd = HydraulicSolver(
      nTrays: N,
      nc: nc,
      thermo: _thermo,
      geom: sec.geometry,
      stageGeometry: stageGeom,
      trayType: sec.type,
      pTop: config.condenser.pTopDesign,
      entrainment: options.entrainment,
      weeping: options.weeping,
      downcomerLimit: options.downcomerLimit,
    );
    _stepper = Stepper(
      hyd: _hyd,
      ep: _ep,
      faults: _faults,
      full: config.hydraulics == HydraulicsMode.full,
      tier2: config.tier != ThermoTier.t1,
      refluxCapacity: _control.fv102.fMax,  // F_max of FV-102 (PHYSICS.md 10.2), not the design L0
      t2: _active,
      cond: config.condenser,
      reb: config.reboiler,
      thermo: _thermo,
      s: _state,
      inp: _inputs,
      control: _control,
      health: _health,
      debug: _debug,
      stageGeometry: stageGeom,
      drumVolume: config.condenser.drumVolume,
      sumpVolume: config.reboiler.sumpVolume,
      murphreePasses: options.murphreePasses,
    );
    _stepper.initializeCold();
    _initControl();
    if (_tier != ThermoTier.t1) _enterTier2Control(_dutyLever);
    _levers = _buildLevers();
    _carry = 0;
    _halted = false;
    _resetMonitor(capture: true);
    if (carry != null) _applyCarry(carry);
  }

  /// Range of a flow or duty lever (PHYSICS.md 2.3 "Lever ranges"): the B-T value [bt] (kmol/h, or W when [kmolh] is
  /// false) for `bt`, else 2 x the preset's default.
  static double _rangeMax(ColumnConfig c, String lever, double bt, {bool kmolh = true}) {
    if (c.presetId == 'bt' || c.presetId == 'bt_custom_alpha' || !Presets.ids.contains(c.presetId)) return bt;
    final d = Presets.byId(c.presetId).initialLevers[lever];
    if (d == null || d <= 0) return bt;
    return kmolh ? 2 * d / _kmolh : 2 * d;
  }

  /// A partial condenser exists only in Tiers 2 and 3 (PHYSICS.md 7.2).
  static bool _isPartial(ColumnConfig c) =>
      c.condenser.type == CondenserType.partial && c.tier != ThermoTier.t1;

  /// Tray geometry of every stage 0..N+1 (stages outside tray sections get the first section's).
  static List<TrayGeometry> _stageGeometries(ColumnConfig c) {
    final first = c.traySection.geometry;
    final out = List<TrayGeometry>.filled(c.trayCount + 2, first);
    var stage = 1;
    for (final s in c.sections) {
      for (var k = 0; k < s.stageCount; k++) {
        if (s is TraySection) out[stage + k] = s.geometry;
      }
      stage += s.stageCount;
    }
    return out;
  }

  void _initFromCarry() {
    _stepper.bus
      ..drumLevelPct = _stepper.drumLevelPct
      ..sumpLevelPct = _stepper.sumpLevelPct;
  }

  /// Instruments, loop histories, trends and alarms start at the current true values (PHYSICS.md 13.1 step 6).
  void _initControl() {
    _stepper.bus
      ..drumLevelPct = _stepper.drumLevelPct
      ..sumpLevelPct = _stepper.sumpLevelPct
      ..columnDp = 0
      ..lk = _config.effectiveKeys.lk
      ..hk = _config.effectiveKeys.hk
      ..setCuts(_inputs.z, _state.x, 0, (_state.nTrays + 1) * _state.nc, _state.nc);
    _stepper.fillBusT2();
    _control.initialise(_stepper.bus, _state.time);
    _trends.reset();
    _control.alarms.reset();
    _control.alarms.journal.clear();
    _computeLevelConstants();
    _lastEvalEnd = -1;
    _fields.clear();
    _checks.results = const [];
  }

  void _computeLevelConstants() {
    final s = _state;
    _control.n01 = 0.01 * _config.condenser.drumVolume / s.vLiq[0];
    _control.ns1 = 0.01 * _config.reboiler.sumpVolume / s.vLiq[s.nTrays + 1];
  }

  void _resetMonitor({bool capture = false}) {
    _nextCheck = _state.time + 60;
    _steadyCount = 0;
    _steady = false;
    _residual = double.infinity;
    if (capture) _captureMonitor();
  }

  void _captureMonitor() {
    if (_prevX.length != _state.x.length) {
      _prevX = Float64List(_state.x.length);
      _prevM = Float64List(_state.holdup.length);
    }
    _prevX.setAll(0, _state.x);
    _prevM.setAll(0, _state.holdup);
    for (var l = 0; l < 5; l++) {
      _prevOp[l] = _control.loops[l].op;
    }
  }

  void _applyWarmStart() {
    final key = jsonEncode([_config.toJson(), options.murphreePasses]);
    final cached = _warmCache[key];
    if (cached != null) {
      _loadDynamic(cached);
    } else {
      runToSteadyState(maxSimSeconds: 172800);
      _warmCache[key] = _dumpDynamic(includeTrends: false);
    }
    _state.time = 0;
    _carry = 0;
    _nextCheck = 60;
    _steady = true;
    _steadyCount = 5;
    _captureMonitor();
    // the cache was made with another seed: re-key the streams, then restart instruments, trends and alarms
    _control.reseed(_seed);
    _initControl();
    _levelViolation = 0;
    if (_control.noise) _resetNoisyMonitor();
  }

  // ---------------------------------------------------------------- time

  /// Simulation time (s).
  double get time => _state.time;

  /// True when the solver gave up (PHYSICS.md 12.7); [solverHealth] says why.
  bool get halted => _halted;

  /// One step of `options.dt`.
  void step() => _stepOnce(options.dt);

  /// Whole steps of `options.dt`; the remainder is carried to the next call.
  void advance(double simSeconds) {
    _carry += simSeconds;
    final dt = options.dt;
    final steps = (_carry / dt + 1e-9).floor();
    for (var i = 0; i < steps; i++) {
      _stepOnce(dt);
      if (_halted) break;
    }
    _carry -= steps * dt;
    if (_carry < 0) _carry = 0;
  }

  /// Advances using the fast-forward step `options.dtFastForward` for about [simSeconds].
  void advanceFast(double simSeconds) {
    final dt = options.dtFastForward;
    final steps = (simSeconds / dt).round();
    for (var i = 0; i < steps; i++) {
      _stepOnce(dt);
      if (_halted) break;
    }
  }

  void _stepOnce(double dt) {
    if (_halted) return;
    var remaining = dt;
    var h = dt;
    var halvings = 0;
    while (remaining > 1e-12) {
      final hh = math.min(h, remaining);
      if (_pinDrum != null) _applyPin();
      _stepper.strictClamp = halvings < 3;
      if (_stepper.step(hh)) {
        remaining -= hh;
        _monitor();
        _afterStep(hh);
      } else {
        halvings++;
        _health.stepRetries++;
        h = hh / 2;
        if (halvings > 3) {
          _halted = true;
          _health.fatal = true;
          _health.fatalMessage = 'The model could not continue from this state';
          _emit(SimEventType.solverFallback, _health.fatalMessage!);
          return;
        }
      }
    }
  }

  void _emit(SimEventType t, String msg) {
    if (!_events.isClosed) _events.add(SimEvent(t, _state.time, msg));
  }

  /// Marches to steady state (PHYSICS.md 13.1) with the fast-forward step until the monitor of 13.3
  /// declares steady, then keeps going until the residual is below [polishTolerance] (docs/DEVIATIONS.md).
  SteadyStateResult runToSteadyState({
    double maxSimSeconds = 345600,
    bool fastForward = true,
    double polishTolerance = 1e-11,
  }) {
    final run = beginSteadyRun(
        maxSimSeconds: maxSimSeconds,
        fastForward: fastForward,
        polishTolerance: polishTolerance);
    while (!run.advance(const Duration(seconds: 3600))) {}
    return run.result!;
  }

  /// Starts a resumable run to steady state; call [SteadyRun.advance] repeatedly.
  SteadyRun beginSteadyRun(
      {double maxSimSeconds = 345600,
      bool fastForward = true,
      double polishTolerance = 1e-11}) {
    _carry = 0;
    // align to a whole number of fast steps from the next monitor check
    return SteadyRun._(this, maxSimSeconds,
        fastForward ? options.dtFastForward : options.dt, polishTolerance);
  }

  // ---------------------------------------------------------------- steady monitor

  bool get isSteady => _steady;

  /// Slowest-mode time constant (s) estimated from the last two residuals; null if not decaying.
  double? get slowModeTau {
    if (!_prevResidual.isFinite || !_residual.isFinite || _residual <= 0)
      return null;
    if (_residual >= _prevResidual) return null;
    return 60 / math.log(_prevResidual / _residual);
  }

  /// Last residual delta of PHYSICS.md 13.3 (infinity until the first check).
  double get steadyResidual => _residual;

  void _monitor() {
    if (_control.noise) {
      _monitorNoisy();
      return;
    }
    if (_state.time + 1e-9 < _nextCheck) return;
    _nextCheck += 60;
    var delta = 0.0;
    final s = _state;
    for (var k = 0; k < s.x.length; k++) {
      delta = math.max(delta, (s.x[k] - _prevX[k]).abs());
    }
    for (var j = 0; j < s.holdup.length; j++) {
      delta = math.max(delta,
          (s.holdup[j] - _prevM[j]).abs() / math.max(s.holdup[j], 1e-12));
    }
    for (var l = 0; l < 5; l++) {
      delta = math.max(delta, (_control.loops[l].op - _prevOp[l]).abs() / 100);
    }
    _captureMonitor();
    _prevResidual = _residual;
    _residual = delta;
    if (delta < 1e-7) {
      _steadyCount++;
    } else {
      _steadyCount = 0;
    }
    final was = _steady;
    _steady = _steadyCount >= 5;
    if (_steady && !was) _emit(SimEventType.steadyReached, 'Steady state');
  }

  // Noise-on monitor tolerances (PHYSICS.md 13.3, [impl-tunable]; DEVIATIONS.md E30): the 300-s means move by
  // up to 1.1e-2 (x), 5.3e-3 (relative holdup) and 1.1 % (OP) from noise alone.
  static const double _tolX = 1.8e-2, _tolM = 8e-3, _tolOp = 2.0;

  /// Noise-on monitor: successive 300-s means (thresholds [impl-tunable], DEVIATIONS.md E30).
  void _monitorNoisy() {
    final s = _state;
    if (_sumX.length != s.x.length) {
      _sumX = Float64List(s.x.length);
      _sumM = Float64List(s.holdup.length);
      _prevMeanX = Float64List(s.x.length);
      _prevMeanM = Float64List(s.holdup.length);
      _hasPrevMean = false;
      _nSum = 0;
    }
    for (var k = 0; k < s.x.length; k++) {
      _sumX[k] += s.x[k];
    }
    for (var j = 0; j < s.holdup.length; j++) {
      _sumM[j] += s.holdup[j];
    }
    for (var l = 0; l < 5; l++) {
      _sumOp[l] += _control.loops[l].op;
    }
    _nSum++;
    if (s.time + 1e-9 < _nextCheckNoisy) return;
    _nextCheckNoisy += 300;
    final inv = 1.0 / _nSum;
    var delta = 0.0;
    if (_hasPrevMean) {
      for (var k = 0; k < s.x.length; k++) {
        delta = math.max(delta, (_sumX[k] * inv - _prevMeanX[k]).abs() / _tolX);
      }
      for (var j = 0; j < s.holdup.length; j++) {
        final m = _sumM[j] * inv;
        delta = math.max(
            delta, (m - _prevMeanM[j]).abs() / (_tolM * math.max(m, 1e-12)));
      }
      for (var l = 0; l < 5; l++) {
        delta =
            math.max(delta, (_sumOp[l] * inv - _prevMeanOp[l]).abs() / _tolOp);
      }
      _prevResidual = _residual;
      _residual = delta;
      if (delta < 1) {
        _noisyCount++;
      } else {
        _noisyCount = 0;
      }
      final was = _steady;
      _steady = _noisyCount >= 3;
      if (_steady && !was) _emit(SimEventType.steadyReached, 'Steady state');
    }
    for (var k = 0; k < s.x.length; k++) {
      _prevMeanX[k] = _sumX[k] * inv;
      _sumX[k] = 0;
    }
    for (var j = 0; j < s.holdup.length; j++) {
      _prevMeanM[j] = _sumM[j] * inv;
      _sumM[j] = 0;
    }
    for (var l = 0; l < 5; l++) {
      _prevMeanOp[l] = _sumOp[l] * inv;
      _sumOp[l] = 0;
    }
    _hasPrevMean = true;
    _nSum = 0;
  }

  /// Switches the measurement noise (lever `noise`) and re-arms the steady monitor for the new mode.
  void _setNoise(bool on) {
    if (on == _control.noise) return;
    _control.setNoise(on);
    _resetNoisyMonitor();
    if (!on) {
      _nextCheck = _state.time + 60;
      _steadyCount = _steady ? 5 : 0;
      _captureMonitor();
    }
  }

  void _resetNoisyMonitor() {
    _sumX.fillRange(0, _sumX.length, 0);
    _sumM.fillRange(0, _sumM.length, 0);
    _sumOp.fillRange(0, 5, 0);
    _nSum = 0;
    _hasPrevMean = false;
    _nextCheckNoisy = _state.time + 300;
    _noisyCount = _steady ? 3 : 0;
  }

  void _noteChange() {
    _steady = false;
    _steadyCount = 0;
  }

  // ---------------------------------------------------------------- levers

  ThermoTier get tier => _tier;
  HydraulicsMode get hydraulicsMode => _hydraulics;
  ColumnConfig get config => _config;
  ControlSystem get control => _control;
  SolverHealth get solverHealth => _health;

  /// Per-step flows for exact conservation accounting (VALIDATION.md 0 (d)).
  @visibleForTesting
  StepDebug get debug => _debug;

  /// Events (steady reached, rebuild done, solver fallback).
  Stream<SimEvent> get events => _events.stream;

  List<LeverSpec> get levers => _levers;

  static const double _kmolh = 1000 / 3600;

  List<LeverSpec> _buildLevers() {
    final N = _config.trayCount;
    final c0 = _config.components.first;
    final inp = _inputs;
    final isCustom = _config.presetId == 'bt_custom_alpha';
    return [
      LeverSpec(
          id: 'feedFlow',
          label: 'Feed rate F',
          quantity: Quantity.molarFlow,
          min: 0,
          max: _rangeMax(_config, 'feedFlow', 250) * _kmolh,
          defaultValue: inp.feedFlowSp,
          boundLoop: 'FC-101',
          group: 'feed'),
      LeverSpec(
          id: 'feedZ.$c0',
          label: 'Feed composition z',
          quantity: Quantity.fraction,
          min: 0.01,
          max: 0.99,
          defaultValue: inp.z[0],
          group: 'feed'),
      LeverSpec(
          id: 'feedQ',
          label: 'Feed condition q',
          quantity: Quantity.dimensionless,
          min: -0.5,
          max: 1.5,
          defaultValue: inp.feedQ,
          tiers: const {ThermoTier.t1},
          group: 'feed'),
      LeverSpec(
          id: 'feedStage',
          label: 'Feed tray',
          quantity: Quantity.dimensionless,
          min: 1,
          max: N.toDouble(),
          defaultValue: inp.feedStage.toDouble(),
          group: 'feed',
          integer: true),
      LeverSpec(
          id: 'refluxFlow',
          label: 'Reflux flow L0',
          quantity: Quantity.molarFlow,
          min: 0,
          max: _rangeMax(_config, 'refluxFlow', 300) * _kmolh,
          defaultValue: inp.refluxFlowSp,
          boundLoop: 'FC-102',
          group: 'top'),
      LeverSpec(
          id: 'refluxRatio',
          label: 'Reflux ratio R',
          quantity: Quantity.dimensionless,
          min: 0.1,
          max: 20,
          defaultValue: inp.refluxRatio,
          group: 'top'),
      LeverSpec(
          id: 'refluxMode',
          label: 'Reflux mode (0 flow, 1 ratio)',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: inp.ratioMode ? 1 : 0,
          group: 'top',
          integer: true),
      LeverSpec(
          id: 'drumLevelSp',
          label: 'Drum level SP',
          quantity: Quantity.percent,
          min: 10,
          max: 90,
          defaultValue: _config.control.drumLevelSp,
          boundLoop: 'LC-101',
          group: 'top'),
      LeverSpec(
          id: 'boilup',
          label: 'Boilup V_B',
          quantity: Quantity.molarFlow,
          min: 0,
          max: _rangeMax(_config, 'boilup', 300) * _kmolh,
          defaultValue: inp.boilupSp,
          tiers: const {ThermoTier.t1},
          boundLoop: 'FC-103',
          group: 'bottom'),
      LeverSpec(
          id: 'sumpLevelSp',
          label: 'Sump level SP',
          quantity: Quantity.percent,
          min: 10,
          max: 90,
          defaultValue: _config.control.sumpLevelSp,
          boundLoop: 'LC-102',
          group: 'bottom'),
      LeverSpec(
          id: 'reboilerDuty',
          label: 'Reboiler duty Q_R',
          quantity: Quantity.energyRate,
          min: 0,
          max: _rangeMax(_config, 'reboilerDuty', 3.0e6, kmolh: false),
          defaultValue: _dutyLever,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          boundLoop: 'FC-103',
          group: 'bottom'),
      LeverSpec(
          id: 'pTop',
          label: 'Top pressure',
          quantity: Quantity.pressure,
          min: (_config.tier3Model == Tier3Model.dePriester || _config.condenser.pTopDesign > 5e5) ? 300000 : 20000,
          max: (_config.tier3Model == Tier3Model.dePriester || _config.condenser.pTopDesign > 5e5) ? 2.5e6 : 500000,
          defaultValue: inp.pTopInit,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          boundLoop: 'PC-101',
          group: 'top'),
      LeverSpec(
          id: 'refluxSubcooling',
          label: 'Reflux subcooling',
          quantity: Quantity.temperatureDelta,
          min: 0,
          max: 30,
          defaultValue: 0,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          group: 'top'),
      LeverSpec(
          id: 'feedT',
          label: 'Feed temperature',
          quantity: Quantity.temperature,
          min: 293.15,
          max: 480,
          defaultValue: inp.feedT,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          group: 'feed'),
      LeverSpec(
          id: 'cwInletT',
          label: 'Cooling water inlet T',
          quantity: Quantity.temperature,
          min: 278.15,
          max: 318.15,
          defaultValue: _config.condenser.cwInletT,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          group: 'advanced'),
      LeverSpec(
          id: 'cwMaxFlow',
          label: 'Cooling water capacity',
          quantity: Quantity.volumeFlowLiquid,
          min: 50 / 3600,
          max: 500 / 3600,
          defaultValue: _config.condenser.cwMaxFlow / ControlSystem.rhoWater,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          group: 'advanced'),
      LeverSpec(
          id: 'steamHeaderP',
          label: 'Steam header pressure (abs)',
          quantity: Quantity.pressure,
          min: 201325,
          max: 2101325,
          defaultValue: _config.reboiler.steamHeaderPressure,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          group: 'advanced'),
      const LeverSpec(
          id: 'inertVent',
          label: 'Overhead inert vent',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 0,
          tiers: {ThermoTier.t2, ThermoTier.t3},
          group: 'advanced'),
      const LeverSpec(
          id: 'tc101Enable',
          label: 'TC-101 tray temperature control',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 0,
          tiers: {ThermoTier.t2, ThermoTier.t3},
          group: 'advanced',
          integer: true),
      LeverSpec(
          id: 'tc101Tray',
          label: 'TC-101 tray',
          quantity: Quantity.dimensionless,
          min: 1,
          max: N.toDouble(),
          defaultValue: _config.control.tc101Tray.toDouble(),
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          group: 'advanced',
          integer: true),
      LeverSpec(
          id: 'tc101Sp',
          label: 'TC-101 set point',
          quantity: Quantity.temperature,
          min: 273.15,
          max: 473.15,
          defaultValue: 365,
          tiers: const {ThermoTier.t2, ThermoTier.t3},
          boundLoop: 'TC-101',
          group: 'advanced'),
      const LeverSpec(
          id: 'cwOP',
          label: 'Cooling water valve OP',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 50,
          tiers: {ThermoTier.t2, ThermoTier.t3},
          boundLoop: 'PC-101',
          group: 'advanced'),
      const LeverSpec(
          id: 'condenserType',
          label: 'Condenser (0 total, 1 partial)',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 0,
          tiers: {ThermoTier.t2, ThermoTier.t3},
          requiresPause: true,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'reboilerType',
          label: 'Reboiler (0 kettle, 1 thermosyphon)',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 0,
          tiers: {ThermoTier.t2, ThermoTier.t3},
          requiresPause: true,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'tsInletValve',
          label: 'Thermosyphon inlet valve',
          quantity: Quantity.percent,
          min: 5,
          max: 100,
          defaultValue: 100,
          tiers: {ThermoTier.t2, ThermoTier.t3},
          group: 'bottom'),
      LeverSpec(
          id: 'nTrays',
          label: 'Number of trays N',
          quantity: Quantity.dimensionless,
          min: 3,
          max: 60,
          defaultValue: N.toDouble(),
          requiresPause: true,
          group: 'column',
          integer: true),
      LeverSpec(
          id: 'murphree',
          label: 'Murphree efficiency E',
          quantity: Quantity.fraction,
          min: 0.05,
          max: 1.0,
          defaultValue: inp.murphree,
          group: 'column'),
      if (isCustom)
        LeverSpec(
            id: 'alpha',
            label: 'Relative volatility α',
            quantity: Quantity.dimensionless,
            min: 1.05,
            max: 10,
            defaultValue: _thermo.alpha[0] / _thermo.alpha[1],
            tiers: const {ThermoTier.t1},
            group: 'column'),
      const LeverSpec(
          id: 'hydraulics',
          label: 'Hydraulics (0 ideal, 1 full)',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 0,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'trayType.0',
          label: 'Tray type (0 sieve, 1 valve)',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 0,
          requiresPause: true,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'antifoam',
          label: 'Antifoam injection',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 0,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'distillateValve',
          label: 'Distillate valve OP',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 50,
          boundLoop: 'LC-101',
          group: 'advanced'),
      const LeverSpec(
          id: 'bottomsValve',
          label: 'Bottoms valve OP',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 50,
          boundLoop: 'LC-102',
          group: 'advanced'),
      const LeverSpec(
          id: 'feedFlowOp',
          label: 'Feed valve OP',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 40,
          boundLoop: 'FC-101',
          group: 'advanced'),
      const LeverSpec(
          id: 'refluxOp',
          label: 'Reflux valve OP',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 33,
          boundLoop: 'FC-102',
          group: 'advanced'),
      const LeverSpec(
          id: 'boilupOp',
          label: 'Boilup valve OP',
          quantity: Quantity.percent,
          min: 0,
          max: 100,
          defaultValue: 50,
          boundLoop: 'FC-103',
          group: 'advanced'),
      LeverSpec(
          id: 'noise',
          label: 'Measurement noise',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: options.measurementNoise ? 1 : 0,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'view',
          label: 'View (0 model, 1 plant, 2 plant with calculations)',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 2,
          defaultValue: 0,
          group: 'advanced',
          integer: true),
      const LeverSpec(
          id: 'badPvShed',
          label: 'Shed loops on bad PV',
          quantity: Quantity.dimensionless,
          min: 0,
          max: 1,
          defaultValue: 1,
          group: 'advanced',
          integer: true),
      for (final v in _control.valves)
        LeverSpec(
            id: 'bypass.${v.id}',
            label: 'Bypass ${v.id}',
            quantity: Quantity.percent,
            min: -1,
            max: 100,
            defaultValue: -1,
            group: 'advanced'),
    ];
  }

  LeverSpec _spec(LeverId id) => _levers.firstWhere((l) => l.id == id,
      orElse: () => throw ArgumentError('Unknown lever "$id"'));

  /// Current value of a lever (SI).
  double lever(LeverId id) {
    final inp = _inputs;
    if (id.startsWith('feedZ.')) {
      final k = _config.components.indexOf(id.substring(6));
      if (k < 0) throw ArgumentError('Unknown lever "$id"');
      return inp.z[k];
    }
    if (id.startsWith('bypass.'))
      return _control.valve(id.substring(7)).bypassTarget;
    switch (id) {
      case 'feedFlow':
        return _control.fc101.sp;
      case 'feedQ':
        return inp.feedQ;
      case 'feedStage':
        return inp.feedStage.toDouble();
      case 'refluxFlow':
        return _control.fc102.sp;
      case 'refluxRatio':
        return inp.refluxRatio;
      case 'refluxMode':
        return inp.ratioMode ? 1 : 0;
      case 'boilup':
        return _tier == ThermoTier.t1 ? _control.fc103.sp : inp.boilupSp;
      case 'reboilerDuty':
        return _tier == ThermoTier.t1 ? _dutyLever : _control.fc103.sp;
      case 'pTop':
        return _tier == ThermoTier.t1 ? inp.pTopInit : _control.pc101.sp;
      case 'refluxSubcooling':
        return inp.refluxSub;
      case 'feedT':
        return inp.feedT;
      case 'cwInletT':
        return inp.cwInT;
      case 'cwMaxFlow':
        return inp.cwMaxFlow / ControlSystem.rhoWater;
      case 'steamHeaderP':
        return inp.steamHeaderP;
      case 'inertVent':
        return inp.inertVent;
      case 'tc101Enable':
        return _control.tc101Enabled ? 1 : 0;
      case 'tc101Tray':
        return _control.tc101Tray.toDouble();
      case 'tc101Sp':
        return _control.tc101.sp;
      case 'cwOP':
        return _control.partial ? _control.cwManualOp : _control.pc101.op;
      case 'condenserType':
        return _control.partial ? 1.0 : 0.0;
      case 'reboilerType':
        return _control.ts != null ? 1.0 : 0.0;
      case 'tsInletValve':
        return _control.tsInletOp;
      case 'drumLevelSp':
        return _control.lc101.sp;
      case 'sumpLevelSp':
        return _control.lc102.sp;
      case 'nTrays':
        return _config.trayCount.toDouble();
      case 'murphree':
        return inp.murphree;
      case 'alpha':
        return _thermo.alpha[0] / _thermo.alpha[1];
      case 'hydraulics':
        return _stepper.full ? 1 : 0;
      case 'trayType.0':
        return _hyd.trayType == TrayType.valve ? 1 : 0;
      case 'antifoam':
        return _faults.antifoam ? 1 : 0;
      case 'distillateValve':
        return _control.lc101.op;
      case 'bottomsValve':
        return _control.lc102.op;
      case 'feedFlowOp':
        return _control.fc101.op;
      case 'refluxOp':
        return _control.fc102.op;
      case 'boilupOp':
        return _control.fc103.op;
      case 'noise':
        return _control.noise ? 1 : 0;
      case 'view':
        return _view.index.toDouble();
      case 'badPvShed':
        return _control.badPvShed ? 1 : 0;
    }
    throw ArgumentError('Unknown lever "$id"');
  }

  /// Sets a lever (SI value). Out-of-range values throw [RangeError].
  void setLever(LeverId id, double value) {
    final spec = _spec(id);
    const eps = 1e-9;
    if (value.isNaN ||
        value < spec.min - eps * (1 + spec.min.abs()) ||
        value > spec.max + eps * (1 + spec.max.abs())) {
      throw RangeError('Lever $id = $value outside [${spec.min}, ${spec.max}]');
    }
    final v = value.clamp(spec.min, spec.max).toDouble();
    final inp = _inputs;
    if (id.startsWith('bypass.')) {
      final valve = _control.valve(id.substring(7));
      valve.bypassTarget = v < 0 ? -1 : v;
      if (v >= 0) {
        for (final l in _control.loops) {
          if (l.mvRef == valve.id && l.mode != LoopMode.man)
            _control.setMode(l.tag, LoopMode.man);
        }
      }
      return;
    }
    if (id.startsWith('feedZ.')) {
      final k = _config.components.indexOf(id.substring(6));
      final nc = _config.nc;
      var restOld = 0.0;
      for (var i = 0; i < nc; i++) {
        if (i != k) restOld += inp.z[i];
      }
      for (var i = 0; i < nc; i++) {
        if (i == k) continue;
        inp.z[i] =
            restOld > 0 ? inp.z[i] * (1 - v) / restOld : (1 - v) / (nc - 1);
      }
      inp.z[k] = v;
      _noteChange();
      return;
    }
    switch (id) {
      case 'feedFlow':
        inp.feedFlowSp = v;
        _control.setSp('FC-101', v);
      case 'feedQ':
        inp.feedQ = v;
      case 'feedStage':
        inp.feedStage = v.round();
        _feedPhi = inp.feedStage / _config.trayCount;
      case 'refluxFlow':
        inp.refluxFlowSp = v;
        _control.setSp('FC-102', v);
      case 'refluxRatio':
        inp.refluxRatio = v;
      case 'refluxMode':
        inp.ratioMode = v >= 0.5;
      case 'boilup':
        inp.boilupSp = v;
        if (_tier == ThermoTier.t1) _control.setSp('FC-103', v);
      case 'reboilerDuty':
        _dutyLever = v;
        if (_tier != ThermoTier.t1) _control.setSp('FC-103', v);
      case 'pTop':
        inp.pTopInit = v;
        if (_tier != ThermoTier.t1) {
          _control.setSp('PC-101', v);
          _control.setPtSpan();
        }
      case 'refluxSubcooling':
        inp.refluxSub = v;
      case 'feedT':
        inp.feedT = v;
        inp.feedSat = false;
      case 'cwInletT':
        inp.cwInT = v;
      case 'cwMaxFlow':
        inp.cwMaxFlow = v * ControlSystem.rhoWater;
      case 'steamHeaderP':
        inp.steamHeaderP = v;
      case 'inertVent':
        inp.inertVent = v;
      case 'tc101Enable':
        _control.setTc101Enable(v >= 0.5);
      case 'tc101Tray':
        _control.setTc101Tray(v.round());
      case 'tc101Sp':
        _control.setSp('TC-101', v);
      case 'cwOP':
        if (_control.partial) {
          _control.cwManualOp = v;
        } else {
          _opLever('PC-101', v);
        }
      case 'condenserType':
        _setCondenserType(v >= 0.5 ? CondenserType.partial : CondenserType.total);
        return;
      case 'drumLevelSp':
        _control.setSp('LC-101', v);
      case 'sumpLevelSp':
        _control.setSp('LC-102', v);
      case 'murphree':
        inp.murphree = v;
      case 'alpha':
        _thermo.alpha[0] = v;
        _thermo.alpha[1] = 1.0;
        _config = _config.copyWith(tier1Alpha: Float64List.fromList([v, 1.0]));
      case 'hydraulics':
        setHydraulicsMode(
            v >= 0.5 ? HydraulicsMode.full : HydraulicsMode.ideal);
      case 'trayType.0':
        _hyd.trayType = v >= 0.5 ? TrayType.valve : TrayType.sieve;
        _config = _config.copyWith(
            sections: [for (final s in _config.sections) s is TraySection ? s.copyWith(type: _hyd.trayType) : s]);
      case 'antifoam':
        _faults.setAntifoam(v >= 0.5, _state.time);
      case 'reboilerType':
        _setReboilerType(v >= 0.5 ? ReboilerType.thermosyphon : ReboilerType.kettle);
      case 'tsInletValve':
        _control.tsInletOp = v;
      case 'distillateValve':
        _opLever('LC-101', v);
      case 'bottomsValve':
        _opLever('LC-102', v);
      case 'feedFlowOp':
        _opLever('FC-101', v);
      case 'refluxOp':
        _opLever('FC-102', v);
      case 'boilupOp':
        _opLever('FC-103', v);
      case 'noise':
        _setNoise(v >= 0.5);
        return;
      case 'view':
        _view = SimView.values[v.round().clamp(0, 2)];
        return;
      case 'badPvShed':
        _control.badPvShed = v >= 0.5;
        return;
      case 'nTrays':
        _rebuildTrays(v.round());
        return;
    }
    _noteChange();
  }

  /// OP levers act only while the loop is in MAN (ENGINE_API.md 6.3).
  void _opLever(LoopTag tag, double v) {
    final l = _control.loop(tag);
    if (l.mode == LoopMode.man) l.setOp(v);
  }

  /// Opens the failed steam trap bypass (F14, PHYSICS.md 11): the condensate backup falls to zero over 300 s.
  void openTrapBypass() => _faults.setTrapBypass(true, _state.time);

  // ---------------------------------------------------------------- operator actions (M3)

  void acknowledgeAlarm(String alarmId) =>
      _control.alarms.acknowledge(alarmId, _state.time);
  void acknowledgeAllAlarms() => _control.alarms.acknowledgeAll(_state.time);

  /// Field gauge reading (LG-101 drum sight glass, LG-102 sump): the result arrives 180 s later. One
  /// request per gauge can be pending (PHYSICS.md 10.5).
  void requestFieldCheck(String gaugeTag) {
    if (gaugeTag != 'LG-101' && gaugeTag != 'LG-102') {
      throw ArgumentError('Unknown gauge "$gaugeTag"');
    }
    final cur = _fields[gaugeTag];
    if (cur != null && cur.value == null) return;
    _fields[gaugeTag] = _FieldReq(gaugeTag, _state.time, _state.time + 180);
    _control.alarms.log(_state.time, 'FIELD CHECK requested $gaugeTag');
  }

  void _processFields(double t) {
    for (final f in _fields.values) {
      if (f.value != null || t + 1e-9 < f.readyAt) continue;
      final rng = _fieldRng.putIfAbsent(
          f.tag, () => Rng.stream(_seed, 'field:${f.tag}'));
      final truth =
          f.tag == 'LG-101' ? _stepper.drumLevelPct : _stepper.sumpLevelPct;
      final raw = truth + 1.0 * rng.normal();
      f.value = ((raw / 2).roundToDouble() * 2).clamp(0.0, 100.0);
      _control.alarms
          .log(t, 'FIELD CHECK ${f.tag} = ${f.value!.toStringAsFixed(0)} %');
    }
  }

  /// Takes an instrument out of service for 1800 s (sandbox only; PHYSICS.md 10.5).
  void requestMaintenance(String tag) {
    if (_scenarioIsDrill)
      throw StateError('Maintenance is not available in a drill');
    final inst = _control.instrument(tag);
    inst.startMaintenance(_state.time);
    _control.alarms.log(_state.time, 'MAINTENANCE started $tag');
  }

  /// Window of the cross-checks: 300, 600, 1800 or 3600 s.
  void setCheckWindow(double seconds) {
    _checks.setWindow(seconds);
    _evalChecks();
  }

  /// C6 reference (Tiers 2/3): the newest 300 s of the TI readings become the "no change" profile.
  void setTemperatureReference() {
    final ctx = _t2Context();
    if (ctx == null) return;
    if (_checks.setReference(_trends, ctx)) {
      _evalChecks();
      return;
    }
    _checks.tiReference = {
      for (final tag in CrossCheckEngine.tiTags(ctx))
        tag: _control.instrument(tag).value
    };
    _evalChecks();
  }

  T2CheckContext? _t2Context() => _tier == ThermoTier.t1
      ? null
      : T2CheckContext(
          thermo: _active,
          feedT: _inputs.feedT,
          refluxSubLever: _inputs.refluxSub,
          uaRebClean: _config.reboiler.uaClean,
          cwMax: _inputs.cwMaxFlow,
          trayIds: _control.trayIds,
          nTrays: _state.nTrays,
          thermosyphon: _control.ts == null ? null : _config.reboiler.thermosyphon,
          sumpHeight: _config.reboiler.sumpHeight);

  int _tier2StartBin = 0;

  bool get _scenarioIsDrill => _scenario?.def.isDrill ?? false;

  /// Seconds the true drum or sump level was below 5 % or above 95 % (safety score, VC-25.4).
  double get safetyLevelViolationSeconds => _levelViolation;

  /// The trend buffer (5-s bins, PHYSICS.md 14.6).
  TrendBuffer get trends => _trends;

  /// Fast-layer recorder for tests (VALIDATION.md VC-16.4).
  @visibleForTesting
  FastTrace get fastLayerTrace => _control.fastTrace ??= FastTrace();

  /// Pins the true drum level for tests (VC-25.1): the holdup is reset to this level before every step.
  @visibleForTesting
  void holdDrumLevelForTest(double? level) {
    _pinDrum = level;
    if (level != null) _applyPin();
  }

  void _applyPin() {
    final s = _state;
    final nc = s.nc;
    final m0 = _pinDrum! / 100 * _config.condenser.drumVolume / s.vLiq[0];
    for (var i = 0; i < nc; i++) {
      s.m[i] = s.x[i] * m0;
    }
    s.holdup[0] = m0;
  }

  void _evalChecks() {
    _checks.evaluate(_trends, _control, _inputs.feedQ, _steady,
        t2: _t2Context(), tier2StartBin: _tier2StartBin);
  }

  /// Everything that follows a successful main step (PHYSICS.md 12.4 step 13).
  void _afterStep(double h) {
    final d = _stepper.drumLevelPct, sp = _stepper.sumpLevelPct;
    if (d < 5 || d > 95 || sp < 5 || sp > 95) _levelViolation += h;
    _processFields(_state.time);
    _scenario?.update();
    if (_trends.newestEnd > _lastEvalEnd + 1e-9) {
      _lastEvalEnd = _trends.newestEnd;
      _evalChecks();
      for (final c in _checks.results) {
        if (c.status == CheckStatus.fail && _failSeen.add(c.id)) _failLog.add((c.id, _state.time));
      }
    }
  }

  // ---------------------------------------------------------------- scenarios (M3)

  /// The seed of the noise and drill streams for this run.
  int get seed => _seed;

  /// The running scenario, if any (updated after every main step).
  ScenarioRunner? get scenario => _scenario;

  static final Map<String, Map<String, Object?>> _scenarioCache = {};

  /// Starts [def] (ENGINE_API.md 6.1, 11.1): builds the configuration, applies the levers, reaches the
  /// steady start with noise off, applies loops, noise, view and shed, sets t = 0, then runs the events of
  /// t = 0 and (drills) the draw. Replaces any running scenario. [seed] defaults to the option seed.
  void startScenario(ScenarioDef def, {int? seed}) {
    _scenario = null;
    _seed = seed ?? options.seed;
    _failLog.clear();
    _failSeen.clear();
    _view = SimView.model;
    _pinDrum = null;
    _build(def.buildConfig(), null);
    _control.setNoise(false);
    _resetNoisyMonitor();
    for (final e in def.leverSet.entries) {
      setLever(e.key, e.value);
    }
    if (def.start == 'steady') {
      final key = jsonEncode([_configWithCurrentLevers().toJson(), def.leverSet, options.murphreePasses]);
      final cached = _scenarioCache[key];
      if (cached != null) {
        _loadDynamic(cached);
      } else {
        runToSteadyState(maxSimSeconds: 172800);
        _scenarioCache[key] = _dumpDynamic(includeTrends: false);
      }
      _state.time = 0;
      _carry = 0;
      _nextCheck = 60;
      _steady = true;
      _steadyCount = 5;
      _captureMonitor();
    }
    _control.setNoise(false);
    _control.reseed(_seed);
    _initControl();
    _levelViolation = 0;
    final tags = def.loops.keys.toList()..sort();
    for (final tag in tags) {
      final cfg = def.loops[tag]!;
      final mode = cfg['mode'] as String?;
      if (mode != null) {
        _control.setMode(tag, LoopMode.values.firstWhere((m) => m.name == mode));
      }
      if (cfg['sp'] != null) _control.setSp(tag, (cfg['sp']! as num).toDouble());
      if (cfg['op'] != null) _control.setOp(tag, (cfg['op']! as num).toDouble());
    }
    _control.badPvShed = def.badPvShed;
    _view = switch (def.view) {
      'plant' => SimView.plant,
      'plantCalc' => SimView.plantCalc,
      _ => SimView.model,
    };
    _setNoise(def.noise);
    _resetMonitor(capture: true);
    if (_control.noise) _resetNoisyMonitor();
    _scenario = ScenarioRunner(def, SimulatorHost(this));
    _scenario!.update();
  }

  /// Replaces the column by another preset, at its steady state, and keeps the clock, the scenario and the
  /// noise and view settings (G7 "Next", the `loadPreset` event; ENGINE_API.md 11.8).
  void loadPreset(String presetId,
      {String? tier, Map<String, Object?> overrides = const {}}) {
    var cfg = Presets.byId(presetId);
    if (overrides.isNotEmpty) cfg = cfg.applyOverrides(overrides);
    if (tier != null) {
      cfg = cfg.copyWith(tier: ThermoTier.values.firstWhere((e) => e.name == tier));
    }
    final keepTime = _state.time;
    final noise = _control.noise;
    final view = _view;
    final scenario = _scenario;
    _scenario = null;
    _pinDrum = null;
    _build(cfg, null);
    _control.setNoise(false);
    _resetNoisyMonitor();
    final key = jsonEncode(
        [_configWithCurrentLevers().toJson(), 'preset', options.murphreePasses]);
    final cached = _scenarioCache[key];
    if (cached != null) {
      _loadDynamic(cached);
    } else {
      runToSteadyState(maxSimSeconds: 172800);
      _scenarioCache[key] = _dumpDynamic(includeTrends: false);
    }
    _state.time = keepTime;
    _carry = 0;
    _nextCheck = keepTime + 60;
    _steady = true;
    _steadyCount = 5;
    _captureMonitor();
    _control.setNoise(false);
    _control.reseed(_seed);
    _initControl();
    if (_tier != ThermoTier.t1) _tier2StartBin = (_trends.newestEnd / TrendBuffer.binSeconds).round();
    _view = view;
    _setNoise(noise);
    _resetMonitor(capture: true);
    if (_control.noise) _resetNoisyMonitor();
    _scenario = scenario;
    if (_tier != ThermoTier.t1) setTemperatureReference();
    _emit(SimEventType.rebuildDone, 'Loaded preset $presetId');
  }

  void takeHint(int index) => _requireScenario().takeHint(index);
  AnswerResult submitAnswer(String objectiveId, Object answer) =>
      _requireScenario().submitAnswer(objectiveId, answer);
  DrillResult submitDiagnosis(Diagnosis d) => _requireScenario().submitDiagnosis(d);
  ScoreCard finishScenario() => _requireScenario().finish();

  ScenarioRunner _requireScenario() =>
      _scenario ?? (throw StateError('No scenario is running'));

  /// First cross-check that went `fail` at or after sim time [since], as (id, time).
  (String, double)? firstFailedCheckSince(double since) {
    for (final f in _failLog) {
      if (f.$2 >= since) return f;
    }
    return null;
  }

  static final RegExp _mStage = RegExp(r'^stage\[(\d+)\]\.(\w+)$');
  static final RegExp _mLoop = RegExp(r'^loop\[([\w-]+)\]\.(\w+)$');
  static final RegExp _mInst = RegExp(r'^instrument\[([\w-]+)\]\.(\w+)$');
  static final RegExp _mValve = RegExp(r'^valve\[([\w-]+)\]\.(\w+)$');
  static final RegExp _mCheck = RegExp(r'^check\[([\w:.-]+)\]\.(\w+)$');
  static final RegExp _mAlarm = RegExp(r'^alarm\[([\w.:-]+)\]\.active$');

  double _tsLive(double Function(ThermosyphonLoop) f) {
    final l = _control.ts;
    return l == null || _tier == ThermoTier.t1 ? double.nan : f(l);
  }

  /// True model values for scenario predicates, read from the live state without building a snapshot
  /// (ENGINE_API.md 11.3). Unknown paths give null.
  dynamic liveMetric(String path) {
    switch (path) {
      case 'steady':
        return _steady;
      case 'tier':
        return _tier == ThermoTier.t1 ? 1 : (_tier == ThermoTier.t2 ? 2 : 3);
      case 'preset':
        return _config.presetId;
      case 'alarm.count':
        return _control.alarms.activeCount;
      case 'safety.reliefLifted':
        return _stepper.reliefLifted;
      case 'safety.levelViolationSeconds':
        return _levelViolation;
      case 'condenser.drumLevelPct':
        return _stepper.drumLevelPct;
      case 'condenser.qc':
        return _tier == ThermoTier.t1 ? double.nan : _state.qC;
      case 'reboiler.qr':
        return _tier == ThermoTier.t1 ? double.nan : _stepper.qDelivered;
      case 'reboiler.steamValveOp':
        return _tier == ThermoTier.t1 ? double.nan : _control.fv103.position;
      case 'reboiler.circulation':
        return _tsLive((l) => l.w);
      case 'reboiler.exitQuality':
        return _tsLive((l) => l.xe);
      case 'reboiler.instabilityIndex':
        return _tsLive((l) => l.iS);
      case 'reboiler.oscAmplitude':
        return _tsLive((l) => l.amplitude);
      case 'reboiler.oscPeriod':
        return _tsLive((l) => l.tOsc);
      case 'reboiler.inletValve':
        return _control.tsInletOp;
    }
    final om = RegExp(r'^objective\[(\w+)\]\.met$').firstMatch(path);
    if (om != null) return _scenario?.objectiveMet(om.group(1)!) ?? false;
    if (path.startsWith('kpi.')) return _liveKpi(path.substring(4));
    if (path.startsWith('lever.')) {
      try {
        return lever(path.substring(6));
      } on ArgumentError {
        return null;
      }
    }
    var m = _mStage.firstMatch(path);
    if (m != null) {
      final j = int.parse(m.group(1)!);
      final st = _state;
      if (j < 0 || j >= st.n) return null;
      switch (m.group(2)) {
        case 'x':
          return st.x[j * st.nc];
        case 't':
          return _tier == ThermoTier.t1 ? double.nan : st.t[j];
        case 'p':
          return _tier == ThermoTier.t1
              ? _config.condenser.pTopDesign
              : (j == 0 ? st.pTop : st.pStage[j]);
        case 'holdup':
          return st.holdup[j];
        case 'weepFrac':
          return _stepper.full && j >= 1 && j <= st.nTrays ? _hyd.weepW[j] : 0.0;
        case 'jetFlood':
          return _stepper.full && j >= 1 && j <= st.nTrays ? _hyd.phi[j] : 0.0;
      }
      return null;
    }
    m = _mLoop.firstMatch(path);
    if (m != null) {
      final l = _control.loop(m.group(1)!);
      switch (m.group(2)) {
        case 'pv':
          return _control.instrument(l.pvTag).value;
        case 'sp':
          return l.sp;
        case 'op':
          return l.op;
        case 'mode':
          return l.mode.name;
      }
      return null;
    }
    m = _mInst.firstMatch(path);
    if (m != null) {
      final i = _control.instrument(m.group(1)!);
      return m.group(2) == 'value' ? i.value : i.quality.name;
    }
    m = _mValve.firstMatch(path);
    if (m != null) {
      final v = _control.valve(m.group(1)!);
      final loop = _control.loops.firstWhere((l) => l.mvRef == v.id);
      return m.group(2) == 'op' ? loop.op : v.position;
    }
    m = _mCheck.firstMatch(path);
    if (m != null) {
      for (final c in _checks.results) {
        if (c.id == m.group(1)) {
          return m.group(2) == 'residual' ? c.residual : c.status.name;
        }
      }
      return null;
    }
    m = _mAlarm.firstMatch(path);
    if (m != null) return _control.alarms.isActive(m.group(1)!);
    return null;
  }

  double _liveKpi(String f) {
    final s = _state;
    final nc = s.nc;
    final N = s.nTrays;
    final used = _debug.dt > 0;
    final d = used ? _debug.distillateFlow : _control.lv101.flow;
    final b = used ? _debug.bottomsFlow : _control.lv102.flow;
    switch (f) {
      case 'xD':
        return s.x[_config.effectiveKeys.lk];
      case 'xB':
        return s.x[(N + 1) * nc + _config.effectiveKeys.lk];
      case 'xDHeavy':
        {
          if (nc == 2) return 1 - s.x[0];
          var h = 0.0;
          for (var i = _config.effectiveKeys.hk; i < nc; i++) {
            h += s.x[i];
          }
          return h;
        }
      case 'xBLight':
        {
          if (nc == 2) return s.x[(N + 1) * nc];
          var l = 0.0;
          for (var i = 0; i <= _config.effectiveKeys.lk; i++) {
            l += s.x[(N + 1) * nc + i];
          }
          return l;
        }
      case 'recoveryLK':
        {
          final kk = _config.effectiveKeys;
          final fl = used ? _debug.feedFlow : s.feedAct;
          final fzk = fl * _ep.zEff[kk.lk];
          return fzk > 0 ? d * s.x[kk.lk] / fzk : double.nan;
        }
      case 'recoveryHK':
        {
          final kk = _config.effectiveKeys;
          final fl = used ? _debug.feedFlow : s.feedAct;
          final fzk = fl * _ep.zEff[kk.hk];
          return fzk > 0 ? b * s.x[(N + 1) * nc + kk.hk] / fzk : double.nan;
        }
      case 'd':
        return d;
      case 'b':
        return b;
      case 'refluxRatio':
        return d > 1e-9 ? (used ? _debug.refluxFlow : s.liquid[0]) / d : double.nan;
      case 'boilup':
        return used ? _debug.boilupFlow : s.vapor[N + 1];
      case 'columnDp':
        return _stepper.bus.columnDp;
      case 'maxFloodPct':
        return 100 * _stepper.liveMaxFlood;
      case 'maxWeepFraction':
        return _stepper.liveMaxWeep;
      case 'drumLevelPct':
        return _stepper.drumLevelPct;
      case 'sumpLevelPct':
        return _stepper.sumpLevelPct;
      case 'pTop':
        return _tier == ThermoTier.t1 ? _config.condenser.pTopDesign : s.pTop;
      case 'qc':
        return _tier == ThermoTier.t1 ? double.nan : s.qC;
      case 'qr':
        return _tier == ThermoTier.t1 ? double.nan : _stepper.qDelivered;
      case 'balanceResidual':
        final fl = used ? _debug.feedFlow : s.feedAct;
        var zc = 0.0, dc = 0.0, bc = 0.0;
        for (var i = 0; i <= _config.effectiveKeys.lk; i++) {
          zc += _ep.zEff[i];
          dc += s.x[i];
          bc += s.x[(N + 1) * nc + i];
        }
        final fz = fl * zc;
        return fz > 0 ? (fz - d * dc - b * bc).abs() / fz : 0.0;
    }
    return double.nan;
  }

  // ---------------------------------------------------------------- structure

  // ---------------------------------------------------------------- Tier 2 helpers (M4)

  /// Feed temperature (K) for a feed given as q, vapour fraction or temperature (PHYSICS.md 3.6.3, 3.15).
  double _feedTemperature(ColumnConfig config, StepInputs inp) {
    final th = config.feeds.first.thermal;
    if (th is FeedTemperature) return th.t;
    final nc = config.nc;
    final z = Float64List.fromList(inp.z);
    final p = inp.pTopInit;
    final health = SolverHealth();
    final y = Float64List(nc), k = Float64List(nc), x = Float64List(nc);
    final tb = _active.bubbleT(p, z, 0, y, k, health);
    final q = th is FeedQ ? th.q : 1 - (th as FeedVaporFraction).beta;
    if (q == 1) return tb;
    if (q > 1) {
      final lam = _active.hV(tb, y) - _active.hL(tb, z);
      return tb - (q - 1) * lam / _active.cpL(tb, z);
    }
    final td = _active.dewT(p, z, tb + 5, x, health);
    if (q <= 0) {
      final lam = _active.hV(td, z) - _active.hL(td, x);
      return td - q * lam / _active.cpL(td, z) * 0.5;
    }
    var lo = tb, hi = td;
    for (var i = 0; i < 60; i++) {
      final mid = 0.5 * (lo + hi);
      if (_active.flashBeta(mid, p, z) < 1 - q) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// Makes the control system a Tier-2 one: Tier-2 instruments visible, FT-103 in kW, FC-103 on the duty [duty] (W).
  void _enterTier2Control(double duty) {
    _stepper.prepareTier2();
    _stepper.initThermosyphon(duty);
    _stepper.fillBusT2();
    _tier2StartBin = (_trends.newestEnd / TrendBuffer.binSeconds).round();
    _checks.tiReference = null;
    _control.enterTier2(_stepper.bus, _state.time,
        duty: duty, qMax0: _stepper.qMax0);
    final tr = _config.control.tc101Tray;
    if (_control.trayIds.contains(tr)) _control.setTc101Tray(tr);
  }

  /// Runtime tier switch (PHYSICS.md 13.5): the state X is kept, only the model of the derived quantities changes.
  void setTier(ThermoTier tier) {
    if (!_config.availableTiers.contains(tier)) {
      throw UnsupportedError('Tier ${tier.name} is not available for ${_config.presetId}');
    }
    if (tier == _tier) return;
    if (tier == ThermoTier.t1 && _control.partial) {
      throw UnsupportedError('Tier 1 has a total condenser only');
    }
    final s = _state;
    final N = s.nTrays;
    final nc = s.nc;
    final inp = _inputs;
    if (tier != ThermoTier.t1 && _tier != ThermoTier.t1) {
      // T2 <-> T3 (PHYSICS.md 13.5): only the K model changes, the duty SP is kept
      final qOld = s.qC;
      _tier = tier;
      _config = _config.copyWith(tier: tier);
      _stepper.t2 = _active;
      _stepper.t2Thermo(s.pTop);
      _stepper.t2RescaleInventory();
      if (!_control.partial && qOld > 0) {
        // the new K model gives another condensing T: set the CW valve for a continuous Q_C (7.3 inverted)
        final ua = _stepper.uaCondEff;
        final dtNew = s.tSat0 - _stepper.cwInT;
        if (ua > 0 && dtNew > 0) {
          final r = ua * dtNew / qOld;
          final mcw = r <= 1 ? double.infinity : ua / (2 * 4180.0 * (r - 1));
          _control.setCwFlowBumpless(mcw.isFinite ? mcw : 1e9);
        }
      }
      _levers = _buildLevers();
    } else if (tier != ThermoTier.t1) {
      // top vapour V1 and D continuous: Q_R from the steady energy balance with Tier-2/3 enthalpies
      final v1 = s.vapor[1];
      final dFlow = _debug.dt > 0 ? _debug.distillateFlow : _control.lv101.flow;
      final bFlow = _debug.dt > 0 ? _debug.bottomsFlow : _control.lv102.flow;
      final fFlow = _debug.dt > 0 ? _debug.feedFlow : s.feedAct;
      _tier = tier;
      _config = _config.copyWith(tier: tier);
      _stepper.t2 = _active;
      _stepper.tier2 = true;
      s.pTop = inp.pTopInit;
      s.nI = 0;
      s.nVi.fillRange(0, nc, 0);
      s.tSat0 = 0;
      for (var j = 0; j < s.n; j++) {
        s.t[j] = 0;
      }
      _stepper.hyd.pTop = s.pTop;
      _stepper.t2Thermo(s.pTop);
      _stepper.t2InitInventory();
      inp.feedSat = _config.feeds.first.thermal is FeedQ &&
          (_config.feeds.first.thermal as FeedQ).q == 1.0 &&
          inp.feedQ == 1.0;
      inp.feedT = _feedTemperature(_config, inp);
      final hF = _stepper.feedEnthalpyFor(_ep.zEff);
      final duty = v1 * (s.hVap[1] - s.hLiq[0]) +
          dFlow * s.hLiq[0] +
          bFlow * s.hLiq[N + 1] -
          fFlow * hF;
      _dutyLever = math.max(0.0, duty);
      _stepper.refreshFromHoldups();
      _stepper.t2Thermo(s.pTop);
      _enterTier2Control(_dutyLever);
      _levers = _buildLevers();
    } else {
      // Tier 2 -> Tier 1: V_B := V1 - (1 - q) F
      final v1 = s.vapor[1];
      final f = _debug.dt > 0 ? _debug.feedFlow : s.feedAct;
      var q = 1.0;
      try {
        q = _active.qOfFeed(_stepper.feedTemp > 0 ? _stepper.feedTemp : inp.feedT,
            s.pStage[inp.feedStage], _ep.zEff);
      } catch (_) {}
      q = q.clamp(-0.5, 1.5).toDouble();
      // a saturated-liquid feed (q = 1 preset) must come back as exactly q = 1, so that a later return to Tier 2/3
      // restores `feedSat` and the feed keeps following the local bubble point (G9 at 0.5 bar)
      if (inp.feedSat) q = 1.0;
      inp.feedQ = q;
      final vb = math.max(0.0, v1 - (1 - q) * f);
      inp.boilupSp = vb;
      _tier = ThermoTier.t1;
      _config = _config.copyWith(tier: ThermoTier.t1);
      _stepper.tier2 = false;
      _stepper.restoreTier1Props();
      _control.enterTier1(_state.time, boilup: vb);
      _stepper.refreshFromHoldups();
      _stepper.refreshVapour();
      _levers = _buildLevers();
    }
    _stepper.bus
      ..drumLevelPct = _stepper.drumLevelPct
      ..sumpLevelPct = _stepper.sumpLevelPct;
    _stepper.fillBusT2();
    _resetMonitor(capture: true);
    if (_control.noise) _resetNoisyMonitor();
    _noteChange();
  }

  /// Switches between ideal (M1) and full tray hydraulics. The composition state is kept; the entrainment
  /// filters are initialised from the current state when going to full.
  void setHydraulicsMode(HydraulicsMode mode) {
    if (mode == _hydraulics) return;
    _hydraulics = mode;
    _config = _config.copyWith(hydraulics: mode);
    _stepper.full = mode == HydraulicsMode.full;
    if (_stepper.full) {
      _stepper.initHydraulicState();
    } else {
      for (var j = 0; j < _state.n; j++) {
        _state.entrain[j] = 0;
        _state.bypass[j] = 0;
      }
    }
    _stepper.refreshVapour();
    _noteChange();
  }

  /// The fault manager (ENGINE_API.md 9).
  FaultManager get faults => _faults;

  /// Equation trace for the math overlay (ENGINE_API.md 8). Recomputes the hydraulics for the current state
  /// with the same code the stepper and the snapshot use.
  ExplainResult explain(ExplainTarget target) {
    if (_view.isPlant &&
        target is! ExplainInstrument &&
        target is! ExplainValve &&
        target is! ExplainLoop &&
        target is! ExplainCheck) {
      return ExplainResult(
          title: 'Not observable',
          groups: const [],
          notes: const ['Not observable on a real plant.'],
          time: _state.time);
    }
    _stepper.refreshHydraulics(options.dt);
    final snap = snapshot();
    return ExplainEngine(
      config: _config,
      snapshot: snap,
      hyd: _hyd,
      ep: _ep,
      thermo: _thermo,
      t2: _tier == ThermoTier.t1 ? null : _active,
      control: _control,
      full: _stepper.full,
    ).explain(target);
  }

  /// A configuration with the current lever values baked in (feed, flows, efficiency, SPs).
  ColumnConfig _configWithCurrentLevers() {
    final inp = _inputs;
    final feed = _config.feeds.first.copyWith(
      stage: inp.feedStage,
      flow: _control.fc101.sp,
      z: Float64List.fromList(inp.z),
      thermal: _tier == ThermoTier.t1
          ? FeedQ(inp.feedQ)
          : (inp.feedSat ? const FeedQ(1.0) : FeedTemperature(inp.feedT)),
    );
    final t1 = _tier == ThermoTier.t1;
    return _config.copyWith(
      tier: _tier,
      feeds: [feed, ..._config.feeds.skip(1)],
      murphree: inp.murphree,
      condenser: CondenserConfig.fromJson({
        ..._config.condenser.toJson(),
        'cwInletT': inp.cwInT,
        'cwMaxFlow': inp.cwMaxFlow,
      }),
      reboiler: ReboilerConfig.fromJson({
        ..._config.reboiler.toJson(),
        'steamHeaderPressure': inp.steamHeaderP,
      }),
      initialLevers: {
        'feedFlow': _control.fc101.sp,
        'refluxFlow': _control.fc102.sp,
        'refluxRatio': inp.refluxRatio,
        'refluxMode': inp.ratioMode ? 1.0 : 0.0,
        'boilup': t1 ? _control.fc103.sp : inp.boilupSp,
        'feedQ': inp.feedQ,
        'reboilerDuty': t1 ? _dutyLever : _control.fc103.sp,
        'pTop': t1 ? inp.pTopInit : _control.pc101.sp,
        'refluxSubcooling': inp.refluxSub,
        'inertVent': inp.inertVent,
        if (!t1 && !inp.feedSat) 'feedT': inp.feedT,
        if (_control.partial) 'cwOP': _control.cwManualOp,
      },
      control: ControlConfig(
        levelKc: _config.control.levelKc,
        levelTi: _config.control.levelTi,
        drumLevelSp: _control.lc101.sp,
        sumpLevelSp: _control.lc102.sp,
        distillateMax: _control.lv101.fMax,
        bottomsMax: _control.lv102.fMax,
        temperatureTrays: _config.control.temperatureTrays,
        tc101Tray: _control.tc101Tray,
      ),
    );
  }

  /// Condenser type switch (pause required, PHYSICS.md 7.2): rebuilds the column at its present state.
  void _setCondenserType(CondenserType type) {
    if (type == _config.condenser.type) return;
    if (_tier == ThermoTier.t1) {
      throw UnsupportedError('A partial condenser needs Tier 2 or 3');
    }
    final cur = _configWithCurrentLevers();
    final lev = {...cur.initialLevers};
    if (type == CondenserType.total) {
      lev.remove('cwOP');
    } else {
      lev['cwOP'] = cur.condenser.cwOpPartial;
    }
    rebuild(cur.copyWith(
        condenser: CondenserConfig.fromJson(
            {...cur.condenser.toJson(), 'type': type.name}),
        initialLevers: lev));
  }

  /// Reboiler type switch (pause required, PHYSICS.md 8.3, 13.1 step 7): rebuilds the column at its present state; the
  /// thermosyphon loop is initialised from it.
  void _setReboilerType(ReboilerType type) {
    if (type == _config.reboiler.type) return;
    if (_tier == ThermoTier.t1) {
      throw UnsupportedError('The thermosyphon needs Tier 2 or 3');
    }
    final cur = _configWithCurrentLevers();
    rebuild(cur.copyWith(
        reboiler: ReboilerConfig.fromJson({...cur.reboiler.toJson(), 'type': type.name})));
  }

  /// `thermoOutOfRange` (PHYSICS.md 2.2, 3.4.2): an Antoine component outside 0.1 to 5 bar, or a DePriester stage outside
  /// 365 to 852 degR and 14.7 to 870 psia. Evaluated on the present state, not sticky.
  bool _thermoOutOfRange() {
    if (_tier == ThermoTier.t1) return false;
    final s = _state;
    var pMin = double.infinity, pMax = 0.0, tMin = double.infinity, tMax = 0.0;
    for (var j = 1; j < s.n; j++) {
      pMin = math.min(pMin, s.pStage[j]);
      pMax = math.max(pMax, s.pStage[j]);
      tMin = math.min(tMin, s.t[j]);
      tMax = math.max(tMax, s.t[j]);
    }
    if (_active is Tier3DePriester) {
      return 1.8 * tMin < 365 || 1.8 * tMax > 852 || pMin < 14.7 * 6894.757 || pMax > 870 * 6894.757;
    }
    for (final c in _active.comps) {
      if (c.vpKind == VaporPressureKind.antoineLog10MmHgC && (pMin < 1e4 || pMax > 5e5)) return true;
    }
    return false;
  }

  final SolverHealth _displayHealth = SolverHealth();
  Float64List _tStar = Float64List(0);

  /// Display-only T* of Tier 1 (PHYSICS.md 1.3): the Tier-2 (Raoult) bubble point of every stage liquid at the
  /// stage pressure [p]; the engine never uses it. NaN when the solve fails.
  Float64List _displayBubbleT(Float64List p) {
    final s = _state;
    final n = s.n, nc = s.nc;
    if (_tStar.length != n) _tStar = Float64List(n)..fillRange(0, n, 350.0);
    final out = Float64List(n);
    final y = Float64List(nc), k = Float64List(nc);
    for (var j = 0; j < n; j++) {
      try {
        final t = _t2.bubbleAt(p[j] > 0 ? p[j] : _config.condenser.pTopDesign, s.x, j * nc,
            _tStar[j], y, 0, k, 0, _displayHealth);
        out[j] = t.isFinite ? t : double.nan;
        if (t.isFinite) _tStar[j] = t;
      } catch (_) {
        out[j] = double.nan;
      }
    }
    return out;
  }

  void _rebuildTrays(int trays) {
    final cur = _configWithCurrentLevers();
    final oldN = cur.trayCount;
    if (trays == oldN) return;
    final fs = (_feedPhi * trays + 1e-9).floor().clamp(1, trays);
    rebuild(cur.withTrays(trays, feedStage: fs));
  }

  /// Applies a new configuration, remapping the liquid profile when the tray count changes
  /// (PHYSICS.md 13.4). Drum, sump and controllers keep their state.
  void rebuild(ColumnConfig newConfig) {
    final old = _state;
    final carry = _Carry(
      oldN: old.nTrays,
      oldNc: old.nc,
      x: Float64List.fromList(old.x),
      holdup: Float64List.fromList(old.holdup),
      time: old.time,
      control: _control.toJson(),
      feedAct: old.feedAct,
      refluxAct: old.refluxAct,
      boilupAct: old.boilupAct,
      faults: _faults,
    );
    _build(newConfig, carry);
    _emit(SimEventType.rebuildDone,
        'Column rebuilt with ${newConfig.trayCount} trays');
  }

  void _applyCarry(_Carry c) {
    final s = _state;
    final nc = s.nc;
    final N = s.nTrays;
    s.time = c.time;
    if (c.oldNc == nc) {
      // remap trays by fractional height
      for (var jn = 1; jn <= N; jn++) {
        final u = ((jn - 0.5) / N * c.oldN + 0.5).clamp(1.0, c.oldN.toDouble());
        final i0 = u.floor().clamp(1, c.oldN);
        final i1 = math.min(i0 + 1, c.oldN);
        final w = u - i0;
        var mTot = c.holdup[i0] * (1 - w) + c.holdup[i1] * w;
        var sx = 0.0;
        for (var i = 0; i < nc; i++) {
          final xi = c.x[i0 * nc + i] * (1 - w) + c.x[i1 * nc + i] * w;
          s.x[jn * nc + i] = xi;
          sx += xi;
        }
        for (var i = 0; i < nc; i++) {
          s.x[jn * nc + i] /= sx;
          s.m[jn * nc + i] = s.x[jn * nc + i] * mTot;
        }
        s.holdup[jn] = mTot;
      }
      for (final (jOld, jNew) in [(0, 0), (c.oldN + 1, N + 1)]) {
        for (var i = 0; i < nc; i++) {
          s.x[jNew * nc + i] = c.x[jOld * nc + i];
          s.m[jNew * nc + i] = c.x[jOld * nc + i] * c.holdup[jOld];
        }
        s.holdup[jNew] = c.holdup[jOld];
      }
      _stepper.refreshFromHoldups();
      _stepper.refreshVapour();
    }
    s.feedAct = c.feedAct;
    s.refluxAct = c.refluxAct;
    s.boilupAct = c.boilupAct;
    _control.loadJson(c.control);
    if (_control.ts != null && _tier != ThermoTier.t1 && c.control['ts'] == null) {
      // kettle -> thermosyphon: start the loop from the carried column (PHYSICS.md 13.1 step 7)
      final duty = _control.fc103.sp;
      _stepper.t2Thermo(_state.pTop);
      _stepper.initThermosyphon(duty);
      _control.fv103.init(100 * duty / _control.fv103.fMax);
      _control.fc103.op = _control.fv103.position;
      _control.ft103.reset(duty, _state.time);
    }
    _initFromCarry();
    _resetMonitor(capture: true);
  }

  // ---------------------------------------------------------------- outputs

  /// Immutable copy of the current state (allocates; call once per frame).
  SimSnapshot snapshot() {
    final s = _state;
    final N = s.nTrays;
    final n = s.n;
    final nc = s.nc;
    final nan = double.nan;
    final full = _stepper.full;
    _stepper.refreshHydraulics(options.dt);
    final h = _hyd;
    Float64List copyOrZero(Float64List a) =>
        full ? Float64List.fromList(a) : Float64List(n);
    final hcl = Float64List(n);
    final froth = Float64List(n);
    final flags = Uint8List(n);
    for (var j = 1; j <= N; j++) {
      if (full) {
        hcl[j] = h.hcl[j];
        froth[j] = h.froth[j];
        flags[j] = h.flags[j];
      } else {
        hcl[j] = s.holdup[j] * s.vLiq[j] / _stepper.aActiveAt[j];
        froth[j] = s.alphaE[j] > 0 ? hcl[j] / s.alphaE[j] : hcl[j];
      }
    }
    final p = Float64List(n)..fillRange(0, n, _config.condenser.pTopDesign);
    final t2 = _tier != ThermoTier.t1;
    if (t2) {
      p.setAll(0, s.pStage);
      p[0] = s.pTop;
    }
    var maxFlood = 0.0, maxWeep = 0.0, columnDp = 0.0;
    final dcFlood = Float64List(n),
        fill = Float64List(n),
        jet = Float64List(n),
        weepFrac = Float64List(n);
    final weepFlow = Float64List(n);
    if (full) {
      for (var j = 1; j <= n - 1; j++) {
        p[j] = h.pressure[j];
      }
      columnDp = h.pressureDropTotal;
      for (var j = 1; j <= N; j++) {
        jet[j] = h.phi[j];
        dcFlood[j] = h.dcFrac[j];
        fill[j] = h.fill[j];
        weepFrac[j] = h.weepW[j];
        weepFlow[j] = h.weepFlow[j];
        maxFlood =
            math.max(maxFlood, math.max(jet[j], math.max(dcFlood[j], fill[j])));
        maxWeep = math.max(maxWeep, weepFrac[j]);
      }
    }
    final stages = StageArrays(
      n: n,
      nc: nc,
      x: Float64List.fromList(s.x),
      y: Float64List.fromList(s.y),
      yStar: Float64List.fromList(s.yStar),
      t: t2 ? Float64List.fromList(s.t) : _displayBubbleT(p),
      idealT: !t2,
      p: p,
      liquidDown: Float64List.fromList(s.liquid),
      vaporUp: Float64List.fromList(s.vapor),
      entrain: copyOrZero(h.entrain),
      weep: weepFlow,
      holdup: Float64List.fromList(s.holdup),
      hcl: hcl,
      froth: froth,
      dp: copyOrZero(h.dp),
      dpDry: copyOrZero(h.dpDry),
      jetFlood: jet,
      dcFlood: dcFlood,
      frothFill: fill,
      stability: copyOrZero(h.stab),
      weepFrac: weepFrac,
      efficiency: Float64List.fromList(s.eff),
      hetp: Float64List(n)..fillRange(0, n, nan),
      packFlood: Float64List(n)..fillRange(0, n, nan),
      flags: flags,
    );
    // Report the flows the solver used in the last completed step, so that integrating the
    // snapshot flows closes the component balance exactly (the valves already hold next step's flow).
    final used = _debug.dt > 0;
    final f = used ? _debug.feedFlow : s.feedAct;
    final dFlow = used ? _debug.distillateFlow : _control.lv101.flow;
    final bFlow = used ? _debug.bottomsFlow : _control.lv102.flow;
    final l0 = used ? _debug.refluxFlow : s.liquid[0];
    final vUp = used ? _debug.boilupFlow : s.vapor[N + 1];
    final xDrum = Float64List.fromList(s.x.sublist(0, nc));
    final xSump = Float64List.fromList(s.x.sublist((N + 1) * nc, (N + 2) * nc));
    final ySump = Float64List.fromList(s.y.sublist((N + 1) * nc, (N + 2) * nc));
    final zEff = Float64List.fromList(_ep.zEff);
    var feedQLive = nan;
    if (t2) {
      try {
        feedQLive = _active.qOfFeed(_stepper.feedTemp > 0 ? _stepper.feedTemp : _inputs.feedT,
            s.pStage[_inputs.feedStage], zEff);
      } catch (_) {}
    }
    final streams = <StreamId, StreamSnapshot>{
      StreamId.feed: StreamSnapshot(
          StreamId.feed, f, zEff, t2 ? _stepper.feedTemp : nan, feedQLive),
      StreamId.reflux:
          StreamSnapshot(StreamId.reflux, l0, xDrum, t2 ? s.tRefl : nan),
      StreamId.distillate:
          StreamSnapshot(StreamId.distillate, dFlow, xDrum, t2 ? s.tRefl : nan),
      StreamId.bottoms: StreamSnapshot(
          StreamId.bottoms, bFlow, xSump, t2 ? s.t[N + 1] : nan),
      StreamId.boilup: StreamSnapshot(
          StreamId.boilup, vUp, ySump, t2 ? s.t[N + 1] : nan),
      if (t2 && _stepper.partial)
        StreamId.vaporProduct: StreamSnapshot(StreamId.vaporProduct, s.dV,
            Float64List.fromList(s.y.sublist(0, nc)), s.tSat0),
    };
    final keys = _config.effectiveKeys;
    final xD = s.x[keys.lk];
    final xB = s.x[(N + 1) * nc + keys.lk];
    // key cuts (PHYSICS.md 10.5): light cut of F and B, heavy cut of D; for a binary they reduce to the light component
    var zCut = 0.0, bCut = 0.0, dCut = 0.0, dHeavy = 0.0;
    for (var i = 0; i < nc; i++) {
      if (i <= keys.lk) {
        zCut += zEff[i];
        bCut += s.x[(N + 1) * nc + i];
        dCut += s.x[i];
      }
      if (i >= keys.hk) dHeavy += s.x[i];
    }
    if (nc == 2) dHeavy = 1 - s.x[0];
    final fz = f * zCut;
    // vapour product light flow D_V y_V (y_V: overhead-inventory composition, 2026-10-13 ruling)
    var dvLight = 0.0;
    if (t2 && _stepper.partial && s.dV > 0) {
      var nvSum = 0.0;
      for (var i = 0; i < nc; i++) {
        nvSum += s.nVi[i];
      }
      dvLight = s.dV * (nvSum > 0 ? s.nVi[0] / nvSum : s.y[0]);
    }
    final drumPct = _stepper.drumLevelPct;
    final sumpPct = _stepper.sumpLevelPct;
    final mMin = 0.05 * _config.reboiler.sumpVolume / s.vLiq[N + 1];
    final kpis = Kpis(
      xD: xD,
      xB: xB,
      d: dFlow,
      b: bFlow,
      refluxRatio: dFlow > 1e-9 ? l0 / dFlow : nan,
      boilup: vUp,
      qc: t2 ? s.qC : nan,
      qr: t2 ? _stepper.qDelivered : nan,
      columnDp: columnDp,
      maxFloodPct: 100 * maxFlood,
      maxWeepFraction: maxWeep,
      drumLevelPct: drumPct,
      sumpLevelPct: sumpPct,
      pTop: t2 ? s.pTop : _config.condenser.pTopDesign,
      xDHeavy: dHeavy,
      xBLight: bCut,
      recoveryLK: _config.keys == null || f * zEff[keys.lk] <= 0 ? null : dFlow * xD / (f * zEff[keys.lk]),
      recoveryHK: _config.keys == null || f * zEff[keys.hk] <= 0
          ? null
          : bFlow * s.x[(N + 1) * nc + keys.hk] / (f * zEff[keys.hk]),
      balanceResidual: fz > 0 ? (fz - dFlow * dCut - dvLight - bFlow * bCut).abs() / fz : 0.0,
      energyResidual: t2 ? _stepper.energyResidual : nan,
    );
    final plant = _view.isPlant;
    final calc = _view == SimView.plantCalc;
    // fault parameters stay hidden in drills (PHYSICS.md 10.9)
    final drill = _scenarioIsDrill;
    double hide(double v) => drill ? nan : v;
    const calcAlarms = {'model.flood', 'model.weep', 'model.dcLimited', 'model.tsUnstable'};
    final alarms = [
      for (final a in _control.alarms.active())
        if (!plant || !a.id.startsWith('model.') || a.id == 'model.relief' || (calc && calcAlarms.contains(a.id))) a,
    ];
    final tsLoop = t2 ? _control.ts : null;
    // thermosyphon fields: model view all (static head and sensible fraction included), plantCalc the calculated ones
    double tsv(double v, {bool calcKeeps = true}) =>
        tsLoop == null ? nan : (plant ? (calc && calcKeeps ? v : nan) : v);
    final fl = <int>[_inputs.feedStage];
    final layout = ColumnLayoutInfo(
      nTrays: N,
      feedStages: fl,
      kinds: [
        StageKind.drum,
        for (var j = 1; j <= N; j++) StageKind.tray,
        StageKind.sump
      ],
      names: ['Drum', for (var j = 1; j <= N; j++) 'Tray $j', 'Sump'],
      sectionEnds: [N],
    );
    final instr = [for (final i in _control.visibleInstruments) i.readingAt(s.time)];
    InstrumentReading rd(String tag) => instr.firstWhere((r) => r.tag == tag);
    var stagesOut = stages;
    var streamsOut = streams;
    var kpisOut = kpis;
    var condOut = CondenserSnapshot(s.holdup[0], drumPct,
        vaporInventory: Float64List(0));
    var rebOut = ReboilerSnapshot(s.holdup[N + 1], sumpPct,
        mMin > 0 ? (s.holdup[N + 1] / mMin).clamp(0.0, 1.0) : 1.0);
    if (t2) {
      condOut = CondenserSnapshot(s.holdup[0], drumPct,
          qC: s.qC,
          uaClean: _config.condenser.uaClean,
          uaEff: hide(_stepper.uaCondEff),
          tCwIn: _stepper.cwInT,
          tCwOut: _stepper.cwOutT,
          cwFlow: _stepper.cwFlow,
          cwOp: _control.partial ? _control.cwManualOp : _control.pc101.op,
          partial: _stepper.partial,
          vaporProduct: s.dV,
          tCond: s.tSat0,
          tReflux: s.tRefl,
          subcooling: s.tSat0 - s.tRefl,
          inertFraction: hide(_stepper.yIner),
          vaporMoles: _stepper.overheadMoles,
          nCond: s.nCond,
          nVent: s.nVent,
          nRelief: s.nRelief,
          vaporInventory: Float64List.fromList(s.nVi));
      rebOut = ReboilerSnapshot(s.holdup[N + 1], sumpPct, rebOut.starvation,
          type: _config.reboiler.type,
          steamSideDuty: _control.meanSteamQ,
          circulation: tsv(tsLoop?.w ?? nan),
          exitQuality: tsv(tsLoop?.xe ?? nan),
          riserQuality: tsv(tsLoop?.xr ?? nan),
          instabilityIndex: tsv(tsLoop?.iS ?? nan),
          oscAmplitude: tsv(tsLoop?.amplitude ?? nan),
          oscPeriod: tsv(tsLoop?.tOsc ?? nan),
          inletLineDp: tsv(tsLoop?.inletLineDp ?? nan),
          outletLineDp: tsv(tsLoop?.outletLineDp ?? nan),
          drivingHead: tsv(tsLoop?.drivingHead ?? nan, calcKeeps: false),
          sensibleFraction: tsv(tsLoop?.fsc ?? nan, calcKeeps: false),
          inletValve: _control.tsInletOp,
          qDelivered: _stepper.qDelivered,
          qMax: hide(_stepper.qMax),
          uaClean: tsLoop?.geo.uaClean ?? _config.reboiler.uaClean,
          uaEff: hide(_stepper.uaRebEff),
          steamP: _stepper.steamHeaderAbs,
          steamT: _stepper.steamT,
          steamValveOp: _control.fv103.position,
          tSump: s.t[N + 1],
          dutyLimited: _control.modelDutyLimited);
    }
    if (plant) {
      Float64List nanArr(int len) => Float64List(len)..fillRange(0, len, nan);
      final lt1 = rd('LT-101').value, lt2 = rd('LT-102').value;
      // Tiers 2/3: stages.t is NaN except on the instrumented trays, which carry the TI reading (PHYSICS.md 10.9)
      final tPlant = nanArr(n);
      if (t2) {
        for (final j in _control.trayIds) {
          tPlant[j] = rd('TI-${100 + j}').value;
        }
        tPlant[N + 1] = rd('TI-${100 + N + 1}').value;
      }
      final hold = Float64List.fromList(stages.holdup);
      hold[0] = lt1 * _control.n01;
      hold[N + 1] = lt2 * _control.ns1;
      stagesOut = StageArrays(
        n: n,
        nc: nc,
        x: nanArr(n * nc),
        y: nanArr(n * nc),
        yStar: nanArr(n * nc),
        t: tPlant,
        p: stages.p,
        liquidDown: nanArr(n),
        vaporUp: nanArr(n),
        entrain: nanArr(n),
        weep: nanArr(n),
        holdup: hold,
        hcl: stages.hcl,
        froth: stages.froth,
        dp: calc ? stages.dp : nanArr(n),
        dpDry: nanArr(n),
        jetFlood: calc ? stages.jetFlood : nanArr(n),
        dcFlood: calc ? stages.dcFlood : nanArr(n),
        frothFill: calc ? stages.frothFill : nanArr(n),
        stability: calc ? stages.stability : nanArr(n),
        weepFrac: calc ? stages.weepFrac : nanArr(n),
        efficiency: nanArr(n),
        hetp: nanArr(n),
        packFlood: nanArr(n),
        flags: stages.flags,
      );
      final at0 = rd('AT-100').value,
          at1 = rd('AT-101').value,
          at2 = rd('AT-102').value;
      Float64List comp(double light, [Float64List? gc]) {
        final c = Float64List(nc)..fillRange(0, nc, nan);
        if (gc != null && gc.length == nc && nc > 2) {
          c.setAll(0, gc);
        } else if (nc == 2) {
          c[0] = light;
          c[1] = 1 - light;
        }
        return c;
      }

      final ftF = rd('FT-101').value,
          ftL = rd('FT-102').value,
          ftV = rd('FT-103').value,
          ftD = rd('FT-104').value,
          ftB = rd('FT-105').value;
      final qcPlant = t2
          ? ControlSystem.rhoWater *
              rd('FT-201').value *
              4180.0 *
              (rd('TI-202').value - rd('TI-201').value)
          : nan;
      streamsOut = {
        StreamId.feed: StreamSnapshot(StreamId.feed, ftF, comp(at0, rd('AT-100').components), nan),
        StreamId.reflux: StreamSnapshot(StreamId.reflux, ftL, comp(1 - at1, rd('AT-101').components),
            t2 ? rd('TI-100').value : nan),
        StreamId.distillate:
            StreamSnapshot(StreamId.distillate, ftD, comp(1 - at1, rd('AT-101').components), nan),
        StreamId.bottoms: StreamSnapshot(StreamId.bottoms, ftB, comp(at2, rd('AT-102').components), nan),
        StreamId.boilup: StreamSnapshot(
            StreamId.boilup, t2 ? nan : ftV, comp(double.nan), nan),
      };
      kpisOut = Kpis(
        xD: nc > 2 ? nan : 1 - at1,
        xB: nc > 2 ? nan : at2,
        xDHeavy: at1,
        xBLight: at2,
        d: ftD,
        b: ftB,
        refluxRatio: ftD > 1e-9 ? ftL / ftD : nan,
        boilup: t2 ? nan : ftV,
        qc: qcPlant,
        qr: t2 ? ftV : nan,
        columnDp: rd('PDT-101').value,
        maxFloodPct: calc ? kpis.maxFloodPct : nan,
        maxWeepFraction: calc ? kpis.maxWeepFraction : nan,
        drumLevelPct: lt1,
        sumpLevelPct: lt2,
        pTop: t2 ? rd('PT-101').value : _config.condenser.pTopDesign,
        balanceResidual: nan,
        energyResidual: nan,
      );
      condOut = t2
          ? CondenserSnapshot(hold[0], lt1,
              qC: qcPlant,
              uaClean: _config.condenser.uaClean,
              tCwIn: rd('TI-201').value,
              tCwOut: rd('TI-202').value,
              cwFlow: rd('FT-201').value * ControlSystem.rhoWater,
              cwOp: _control.pc101.op,
              tReflux: rd('TI-100').value,
              vaporInventory: Float64List(0))
          : CondenserSnapshot(hold[0], lt1, vaporInventory: Float64List(0));
      rebOut = t2
          ? ReboilerSnapshot(hold[N + 1], lt2, rebOut.starvation,
              type: _config.reboiler.type,
              steamSideDuty: ftV,
              circulation: tsv(tsLoop?.w ?? nan),
              exitQuality: tsv(tsLoop?.xe ?? nan),
              riserQuality: tsv(tsLoop?.xr ?? nan),
              instabilityIndex: tsv(tsLoop?.iS ?? nan),
              oscAmplitude: tsv(tsLoop?.amplitude ?? nan),
              oscPeriod: tsv(tsLoop?.tOsc ?? nan),
              inletLineDp: tsv(tsLoop?.inletLineDp ?? nan),
              outletLineDp: tsv(tsLoop?.outletLineDp ?? nan),
              drivingHead: tsv(tsLoop?.drivingHead ?? nan, calcKeeps: false),
              sensibleFraction: tsv(tsLoop?.fsc ?? nan, calcKeeps: false),
              inletValve: _control.tsInletOp,
              qDelivered: ftV,
              uaClean: tsLoop?.geo.uaClean ?? _config.reboiler.uaClean,
              steamP: rd('PT-201').value + 101325.0,
              steamT: WaterProps.saturationT(
                  math.max(rd('PT-201').value + 101325.0, 20000.0)),
              steamValveOp: _control.fc103.op,
              tSump: rd('TI-${100 + N + 1}').value,
              dutyLimited: _control.modelDutyLimited)
          : ReboilerSnapshot(hold[N + 1], lt2, rebOut.starvation);
    }
    final loopSnaps = <LoopSnapshot>[];
    for (final l in _control.visibleLoops) {
      final inst = _control.instrument(l.pvTag);
      loopSnaps.add(LoopSnapshot(l.tag, l.mode, inst.value, l.sp, l.op,
          shed: l.shed,
          pvQuality: inst.quality,
          spLo: l.spLo,
          spHi: l.spHi,
          opLo: l.params.opLo,
          opHi: l.params.opHi,
          kc: l.params.kc,
          ti: l.params.ti,
          td: l.params.td,
          action: l.params.action,
          spTracked: l.spTracked,
          lastError: l.lastError,
          lastDeltaOp: l.lastDeltaOp));
    }
    final valveSnaps = <ValveSnapshot>[];
    for (final v in _control.visibleValves) {
      final loop = _control.loops.firstWhere((l) => l.mvRef == v.id);
      // PV-101 passes kg/s but its meter FT-201 reads m3/s: the valve curve is drawn in meter units
      final k = v.id == 'PV-101' ? 1 / ControlSystem.rhoWater : 1.0;
      valveSnaps.add(ValveSnapshot(v.id, loop.op, plant ? nan : v.position,
          v.fMax * k, v.expectedFlow(loop.op) * k, v.bypassActive ? v.bypassPos : -1));
    }
    return SimSnapshot(
      serial: ++_serial,
      time: s.time,
      tier: _tier,
      hydraulics: _hydraulics,
      layout: layout,
      components: List.unmodifiable(_config.components),
      stages: stagesOut,
      streams: Map.unmodifiable(streamsOut),
      condenser: condOut,
      reboiler: rebOut,
      loops: loopSnaps,
      alarms: alarms,
      kpis: kpisOut,
      steady: SteadyInfo(_steady, _residual),
      solverHealth: _health.copy()..thermoOutOfRange = _thermoOutOfRange(),
      visibleFaults: plant ? const [] : _faults.activeAt(s.time),
      levers: {for (final l in _levers) l.id: lever(l.id)},
      feedQ: _inputs.feedQ,
      murphree: _inputs.murphree,
      view: _view,
      instruments: instr,
      valves: valveSnaps,
      crossChecks: _checks.results,
      fieldChecks: [
        for (final f in _fields.values)
          FieldCheck(f.tag, f.requestedAt, f.readyAt, f.value)
      ],
      scenario: _scenario?.snapshot(),
      energy: !t2
          ? null
          : (plant
              ? EnergySnapshot(nan, rd('FT-103').value, kpisOut.qc, nan, nan, nan)
              : EnergySnapshot(
                  f * _stepper.feedH,
                  _stepper.qDelivered,
                  s.qC,
                  dFlow * s.hLiq[0],
                  bFlow * s.hLiq[N + 1],
                  f * _stepper.feedH +
                      _stepper.qDelivered -
                      s.qC -
                      dFlow * s.hLiq[0] -
                      bFlow * s.hLiq[N + 1] -
                      s.dV * s.hVap[0],
                  vaporProduct: s.dV * s.hVap[0])),
    );
  }

  /// The thermo model of the active tier for diagram builders.
  ThermoModel get thermo => _tier == ThermoTier.t1 ? _thermo : _active;

  /// The Tier 1 model (relative volatilities).
  ConstantAlphaThermo get tier1Thermo => _thermo;

  /// The Tier 2 Raoult model (the display-only T* of Tier 1 and the ideal curves of the T-x-y tab come from it).
  Tier2Raoult get tier2Thermo => _t2;

  /// The Tier 3 model of the system (Raoult itself for `sameAsTier2`).
  Tier2Raoult get tier3Thermo => _t3;

  /// Component data for the configured components.
  List<Component> get componentData {
    final db = ComponentDb.load();
    return [for (final id in _config.components) db[id]];
  }

  // ---------------------------------------------------------------- persistence

  Map<String, Object?> _dumpDynamic({bool includeTrends = true}) => {
        'state': _state.toJson(),
        'control': _control.toJson(includeTrends: includeTrends),
      };

  void _loadDynamic(Map<String, Object?> d) {
    _state.loadJson(d['state']! as Map<String, Object?>);
    _faults.apply(_state.time, _ep, _inputs.z);
    _control.loadJson(d['control']! as Map<String, Object?>);
    _stepper.refreshFromHoldups();
    if (_stepper.tier2 && _state.thermoLoaded) {
      _stepper.t2RestoreDerived();
    } else {
      _stepper.refreshVapour();
    }
    _stepper.bus.drumLevelPct = _stepper.drumLevelPct;
    _stepper.bus.sumpLevelPct = _stepper.sumpLevelPct;
    _debug.dt = 0;
  }

  /// Config, levers, full state and controller states (JSON-encodable).
  Map<String, Object?> saveState() => {
        'version': 2,
        'config': _configWithCurrentLevers().toJson(),
        'options': {
          'dt': options.dt,
          'dtFastForward': options.dtFastForward,
          'murphreePasses': options.murphreePasses,
          'seed': options.seed,
          'measurementNoise': options.measurementNoise,
        },
        'inputs': {
          'feedFlow': _inputs.feedFlowSp,
          'refluxFlow': _inputs.refluxFlowSp,
          'refluxRatio': _inputs.refluxRatio,
          'ratioMode': _inputs.ratioMode,
          'boilup': _inputs.boilupSp,
          'feedQ': _inputs.feedQ,
          'feedStage': _inputs.feedStage,
          'murphree': _inputs.murphree,
          'z': _inputs.z.toList(),
          'feedT': _inputs.feedT,
          'feedSat': _inputs.feedSat,
          'refluxSub': _inputs.refluxSub,
          'inertVent': _inputs.inertVent,
          'steamHeaderP': _inputs.steamHeaderP,
          'cwInT': _inputs.cwInT,
          'cwMaxFlow': _inputs.cwMaxFlow,
          'pTopInit': _inputs.pTopInit,
          'dutyLever': _dutyLever,
          'tier': _tier.name,
        },
        'alpha': _thermo.alpha.toList(),
        'dynamic': _dumpDynamic(),
        'faults': _faults.toJson(),
        'carry': _carry,
        'seed': _seed,
        'scenario': _scenario == null
            ? null
            : {'def': _scenario!.def.source, 'state': _scenario!.toJson()},
        'failLog': [for (final f in _failLog) [f.$1, f.$2]],
        'view': _view.index,
        'levelViolation': _levelViolation,
        'checkWindow': _checks.window,
        'lastEvalEnd': _lastEvalEnd,
        'fields': [
          for (final f in _fields.values)
            [f.tag, f.requestedAt, f.readyAt, f.value]
        ],
        'fieldRng': {
          for (final e in _fieldRng.entries) e.key: e.value.toJson()
        },
        'noisy': {
          'sumX': _sumX.toList(),
          'sumM': _sumM.toList(),
          'prevX': _prevMeanX.toList(),
          'prevM': _prevMeanM.toList(),
          'sumOp': _sumOp.toList(),
          'prevOp': _prevMeanOp.toList(),
          'n': _nSum,
          'has': _hasPrevMean,
          'next': _nextCheckNoisy,
          'count': _noisyCount,
        },
        'serial': _serial,
        'feedPhi': _feedPhi,
        'monitor': {
          'nextCheck': _nextCheck,
          'steadyCount': _steadyCount,
          'steady': _steady,
          'residual': _residual.isFinite ? _residual : null,
          'prevX': _prevX.toList(),
          'prevM': _prevM.toList(),
          'prevOp': _prevOp.toList(),
        },
      };

  factory Simulator.restore(Map<String, Object?> saved, {SimOptions? options}) {
    final o = saved['options']! as Map<String, Object?>;
    final opt = options ??
        SimOptions(
          dt: (o['dt']! as num).toDouble(),
          dtFastForward: (o['dtFastForward']! as num).toDouble(),
          murphreePasses: (o['murphreePasses']! as num).toInt(),
          seed: (o['seed']! as num).toInt(),
          measurementNoise: o['measurementNoise']! as bool,
        );
    final cfg = ColumnConfig.fromJson(saved['config']! as Map<String, Object?>);
    final sim = Simulator._restoring(cfg, opt, (saved['seed'] as num?)?.toInt() ?? opt.seed);
    final inp = saved['inputs']! as Map<String, Object?>;
    sim._inputs
      ..feedFlowSp = (inp['feedFlow']! as num).toDouble()
      ..refluxFlowSp = (inp['refluxFlow']! as num).toDouble()
      ..refluxRatio = (inp['refluxRatio']! as num).toDouble()
      ..ratioMode = inp['ratioMode']! as bool
      ..boilupSp = (inp['boilup']! as num).toDouble()
      ..feedQ = (inp['feedQ']! as num).toDouble()
      ..feedStage = (inp['feedStage']! as num).toInt()
      ..murphree = (inp['murphree']! as num).toDouble();
    final z = inp['z']! as List<Object?>;
    for (var i = 0; i < z.length; i++) {
      sim._inputs.z[i] = (z[i]! as num).toDouble();
    }
    double? dd(String k) => (inp[k] as num?)?.toDouble();
    sim._inputs
      ..feedT = dd('feedT') ?? sim._inputs.feedT
      ..feedSat = (inp['feedSat'] as bool?) ?? sim._inputs.feedSat
      ..refluxSub = dd('refluxSub') ?? 0
      ..inertVent = dd('inertVent') ?? 0
      ..steamHeaderP = dd('steamHeaderP') ?? sim._inputs.steamHeaderP
      ..cwInT = dd('cwInT') ?? sim._inputs.cwInT
      ..cwMaxFlow = dd('cwMaxFlow') ?? sim._inputs.cwMaxFlow
      ..pTopInit = dd('pTopInit') ?? sim._inputs.pTopInit;
    sim._dutyLever = dd('dutyLever') ?? sim._dutyLever;
    final a = saved['alpha']! as List<Object?>;
    for (var i = 0; i < a.length; i++) {
      sim._thermo.alpha[i] = (a[i]! as num).toDouble();
    }
    if (saved['faults'] != null)
      sim._faults.loadJson(saved['faults']! as Map<String, Object?>);
    sim._loadDynamic(saved['dynamic']! as Map<String, Object?>);
    sim._carry = (saved['carry']! as num).toDouble();
    sim._view = SimView.values[(saved['view']! as num).toInt()];
    sim._levelViolation = (saved['levelViolation']! as num).toDouble();
    sim._checks.window = (saved['checkWindow']! as num).toDouble();
    sim._lastEvalEnd = (saved['lastEvalEnd']! as num).toDouble();
    for (final e in saved['fields']! as List<Object?>) {
      final l = e! as List<Object?>;
      sim._fields[l[0]! as String] = _FieldReq(
          l[0]! as String, (l[1]! as num).toDouble(), (l[2]! as num).toDouble())
        ..value = (l[3] as num?)?.toDouble();
    }
    (saved['fieldRng']! as Map<String, Object?>).forEach((k, v) {
      sim._fieldRng[k] = Rng.stream(sim._seed, 'field:$k')
        ..loadJson(v! as Map<String, Object?>);
    });
    final nz = saved['noisy']! as Map<String, Object?>;
    List<double> dl(String k) =>
        [for (final v in nz[k]! as List<Object?>) (v! as num).toDouble()];
    sim._sumX = Float64List.fromList(dl('sumX'));
    sim._sumM = Float64List.fromList(dl('sumM'));
    sim._prevMeanX = Float64List.fromList(dl('prevX'));
    sim._prevMeanM = Float64List.fromList(dl('prevM'));
    sim._sumOp.setAll(0, dl('sumOp'));
    sim._prevMeanOp.setAll(0, dl('prevOp'));
    sim._nSum = (nz['n']! as num).toInt();
    sim._hasPrevMean = nz['has']! as bool;
    sim._nextCheckNoisy = (nz['next']! as num).toDouble();
    sim._noisyCount = (nz['count']! as num).toInt();
    sim._serial = (saved['serial']! as num).toInt();
    sim._feedPhi = (saved['feedPhi'] as num?)?.toDouble() ?? sim._feedPhi;
    final m = saved['monitor']! as Map<String, Object?>;
    sim._nextCheck = (m['nextCheck']! as num).toDouble();
    sim._steadyCount = (m['steadyCount']! as num).toInt();
    sim._steady = m['steady']! as bool;
    sim._residual = (m['residual'] as num?)?.toDouble() ?? double.infinity;
    final px = m['prevX']! as List<Object?>;
    for (var i = 0; i < px.length; i++) {
      sim._prevX[i] = (px[i]! as num).toDouble();
    }
    final pm = m['prevM']! as List<Object?>;
    for (var i = 0; i < pm.length; i++) {
      sim._prevM[i] = (pm[i]! as num).toDouble();
    }
    final po = m['prevOp']! as List<Object?>;
    for (var i = 0; i < po.length; i++) {
      sim._prevOp[i] = (po[i]! as num).toDouble();
    }
    for (final f in (saved['failLog'] as List<Object?>?) ?? const []) {
      final l = f! as List<Object?>;
      sim._failLog.add((l[0]! as String, (l[1]! as num).toDouble()));
      sim._failSeen.add(l[0]! as String);
    }
    final sc = saved['scenario'] as Map<String, Object?>?;
    if (sc != null) {
      final def = ScenarioDef.fromJson(Map<String, Object?>.from(sc['def']! as Map<Object?, Object?>));
      sim._scenario = ScenarioRunner(def, SimulatorHost(sim), restoring: true)
        ..loadJson(sc['state']! as Map<String, Object?>);
    }
    return sim;
  }

  /// Rewinding needs the M3 history ring; not available in M1.
  bool rewind(double simSeconds) => false;

  void dispose() {
    _events.close();
  }
}

class _Carry {
  final int oldN, oldNc;
  final Float64List x, holdup;
  final double time;
  final Map<String, Object?> control;
  final double feedAct, refluxAct, boilupAct;
  final FaultManager faults;
  _Carry({
    required this.faults,
    required this.oldN,
    required this.oldNc,
    required this.x,
    required this.holdup,
    required this.time,
    required this.control,
    required this.feedAct,
    required this.refluxAct,
    required this.boilupAct,
  });
}

class _FieldReq {
  final String tag;
  final double requestedAt, readyAt;
  double? value;
  _FieldReq(this.tag, this.requestedAt, this.readyAt);
}
