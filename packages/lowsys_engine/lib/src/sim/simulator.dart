import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../config/column_config.dart';
import '../control/control_system.dart';
import '../core/ids.dart';
import '../core/quantity.dart';
import '../model/column_state.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/component.dart';
import '../thermo/thermo_model.dart';
import '../thermo/tier1_constant_alpha.dart';
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

  SteadyRun._(this._sim, this.maxSimSeconds, this.dt, this.polishTolerance)
      : _t0 = _sim.time;

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
          _result = _make(false);
          return true;
        }
      }
      k++;
      if (_declaredAt == null && _sim.isSteady) _declaredAt = _sim.time - _t0;
      if (_sim.isSteady && _sim.steadyResidual <= polishTolerance) {
        _result = _make(true);
        _sim._emit(SimEventType.steadyReached, 'Steady state reached');
        return true;
      }
      if (_sim.time - _t0 >= maxSimSeconds) {
        _result = _make(false);
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
  late ColumnState _state;
  late StepInputs _inputs;
  late ControlSystem _control;
  late Stepper _stepper;
  late StepDebug _debug;
  late List<LeverSpec> _levers;
  final SolverHealth _health = SolverHealth();
  final StreamController<SimEvent> _events =
      StreamController<SimEvent>.broadcast();

  double _carry = 0;
  int _serial = 0;
  bool _halted = false;

  // steady-state monitor (PHYSICS.md 13.3)
  double _nextCheck = 60;
  Float64List _prevX = Float64List(0);
  Float64List _prevM = Float64List(0);
  final Float64List _prevOp = Float64List(2);
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

  Simulator._restoring(ColumnConfig config, this.options) : _config = config {
    _build(config, null);
  }

  // ---------------------------------------------------------------- construction

  void _build(ColumnConfig config, _Carry? carry) {
    final problems = config.validate();
    if (problems.isNotEmpty) throw ConfigException(problems.join('; '));
    if (config.tier != ThermoTier.t1) {
      throw ConfigException(
          'Only Tier 1 is available in this build (got ${config.tier.name})');
    }
    _config = config;
    _tier = config.tier;
    _hydraulics = config.hydraulics;
    final nc = config.nc;
    final N = config.trayCount;
    _thermo = Tier1ConstantAlpha.fromConfig(config);
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
    inp.murphree = config.murphree;
    for (var i = 0; i < nc; i++) {
      inp.z[i] = feed.z[i];
    }
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
    _control = ControlSystem.levels(
      kc: config.control.levelKc,
      ti: config.control.levelTi,
      drumSp: config.control.drumLevelSp,
      sumpSp: config.control.sumpLevelSp,
      dMax: dMax,
      bMax: bMax,
      dInit: d0,
      bInit: b0,
    );

    _state = ColumnState(N, nc);
    _debug = StepDebug(nc);
    final sec = config.traySection;
    _stepper = Stepper(
      thermo: _thermo,
      s: _state,
      inp: _inputs,
      control: _control,
      health: _health,
      debug: _debug,
      geometry: sec.geometry,
      drumVolume: config.condenser.drumVolume,
      sumpVolume: config.reboiler.sumpVolume,
      murphreePasses: options.murphreePasses,
    );
    _stepper.initializeCold();
    _levers = _buildLevers();
    _carry = 0;
    _halted = false;
    _resetMonitor(capture: true);
    if (carry != null) _applyCarry(carry);
    // after carry the loop PV filters must follow the state
    _stepper.bus.drumLevelPct = _stepper.drumLevelPct;
    _stepper.bus.sumpLevelPct = _stepper.sumpLevelPct;
    _control.loops[0].pv = _stepper.drumLevelPct;
    _control.loops[1].pv = _stepper.sumpLevelPct;
    _control.loops[0].toJson();
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
    _prevOp[0] = _control.loops[0].op;
    _prevOp[1] = _control.loops[1].op;
  }

  void _applyWarmStart() {
    final key = jsonEncode([_config.toJson(), options.murphreePasses]);
    final cached = _warmCache[key];
    if (cached != null) {
      _loadDynamic(cached);
    } else {
      runToSteadyState();
      _warmCache[key] = _dumpDynamic();
    }
    _state.time = 0;
    _carry = 0;
    _nextCheck = 60;
    _steady = true;
    _steadyCount = 5;
    _captureMonitor();
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
      if (_stepper.step(hh)) {
        remaining -= hh;
        _monitor();
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
    double maxSimSeconds = 172800,
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
      {double maxSimSeconds = 172800,
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
    if (!_prevResidual.isFinite || !_residual.isFinite || _residual <= 0) return null;
    if (_residual >= _prevResidual) return null;
    return 60 / math.log(_prevResidual / _residual);
  }

  /// Last residual delta of PHYSICS.md 13.3 (infinity until the first check).
  double get steadyResidual => _residual;

  void _monitor() {
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
    for (var l = 0; l < 2; l++) {
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
          max: 250 * _kmolh,
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
          label: 'Reflux flow L₀',
          quantity: Quantity.molarFlow,
          min: 0,
          max: 300 * _kmolh,
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
          max: 300 * _kmolh,
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
    switch (id) {
      case 'feedFlow':
        return inp.feedFlowSp;
      case 'feedQ':
        return inp.feedQ;
      case 'feedStage':
        return inp.feedStage.toDouble();
      case 'refluxFlow':
        return inp.refluxFlowSp;
      case 'refluxRatio':
        return inp.refluxRatio;
      case 'refluxMode':
        return inp.ratioMode ? 1 : 0;
      case 'boilup':
        return inp.boilupSp;
      case 'drumLevelSp':
        return _control.loops[0].sp;
      case 'sumpLevelSp':
        return _control.loops[1].sp;
      case 'nTrays':
        return _config.trayCount.toDouble();
      case 'murphree':
        return inp.murphree;
      case 'alpha':
        return _thermo.alpha[0] / _thermo.alpha[1];
      case 'distillateValve':
        return _control.loops[0].op;
      case 'bottomsValve':
        return _control.loops[1].op;
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
      case 'feedQ':
        inp.feedQ = v;
      case 'feedStage':
        inp.feedStage = v.round();
      case 'refluxFlow':
        inp.refluxFlowSp = v;
      case 'refluxRatio':
        inp.refluxRatio = v;
      case 'refluxMode':
        inp.ratioMode = v >= 0.5;
      case 'boilup':
        inp.boilupSp = v;
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
      case 'distillateValve':
        _control.setOp('LC-101', v);
      case 'bottomsValve':
        _control.setOp('LC-102', v);
      case 'nTrays':
        _rebuildTrays(v.round());
        return;
    }
    _noteChange();
  }

  // ---------------------------------------------------------------- structure

  /// Tier 1 only in this milestone.
  void setTier(ThermoTier tier) {
    if (tier != ThermoTier.t1) {
      throw UnsupportedError('Tier ${tier.name} arrives with M4/M5');
    }
  }

  void setHydraulicsMode(HydraulicsMode mode) {
    if (mode != HydraulicsMode.ideal) {
      throw UnsupportedError('Full tray hydraulics arrive with M2');
    }
  }

  /// A configuration with the current lever values baked in (feed, flows, efficiency, SPs).
  ColumnConfig _configWithCurrentLevers() {
    final inp = _inputs;
    final feed = _config.feeds.first.copyWith(
      stage: inp.feedStage,
      flow: inp.feedFlowSp,
      z: Float64List.fromList(inp.z),
      thermal: FeedQ(inp.feedQ),
    );
    return _config.copyWith(
      feeds: [feed, ..._config.feeds.skip(1)],
      murphree: inp.murphree,
      initialLevers: {
        'feedFlow': inp.feedFlowSp,
        'refluxFlow': inp.refluxFlowSp,
        'refluxRatio': inp.refluxRatio,
        'refluxMode': inp.ratioMode ? 1.0 : 0.0,
        'boilup': inp.boilupSp,
        'feedQ': inp.feedQ,
      },
      control: ControlConfig(
        levelKc: _config.control.levelKc,
        levelTi: _config.control.levelTi,
        drumLevelSp: _control.loops[0].sp,
        sumpLevelSp: _control.loops[1].sp,
        distillateMax: _control.distillateValve.maxFlow,
        bottomsMax: _control.bottomsValve.maxFlow,
      ),
    );
  }

  void _rebuildTrays(int trays) {
    final cur = _configWithCurrentLevers();
    final oldN = cur.trayCount;
    if (trays == oldN) return;
    final fs = (cur.feeds.first.stage * trays / oldN).round().clamp(1, trays);
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
      loops: [for (final l in _control.loops) l.toJson()],
      dFlow: _control.distillateValve.flow,
      bFlow: _control.bottomsValve.flow,
      feedAct: old.feedAct,
      refluxAct: old.refluxAct,
      boilupAct: old.boilupAct,
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
    for (var l = 0; l < 2; l++) {
      _control.loops[l].loadJson(c.loops[l]);
    }
    _control.distillateValve.flow = c.dFlow;
    _control.bottomsValve.flow = c.bFlow;
    _resetMonitor(capture: true);
  }

  // ---------------------------------------------------------------- outputs

  /// Immutable copy of the current state (allocates; call once per frame).
  SimSnapshot snapshot() {
    final s = _state;
    final N = s.nTrays;
    final n = s.n;
    final nc = s.nc;
    final sec = _config.traySection.geometry;
    final aA = sec.areaActive;
    final nan = double.nan;
    final hcl = Float64List(n);
    final froth = Float64List(n);
    for (var j = 1; j <= N; j++) {
      hcl[j] = s.holdup[j] * s.vLiq[j] / aA;
      froth[j] = s.alphaE[j] > 0 ? hcl[j] / s.alphaE[j] : hcl[j];
    }
    final stages = StageArrays(
      n: n,
      nc: nc,
      x: Float64List.fromList(s.x),
      y: Float64List.fromList(s.y),
      yStar: Float64List.fromList(s.yStar),
      t: Float64List(n)..fillRange(0, n, nan),
      p: Float64List(n)..fillRange(0, n, _config.condenser.pTopDesign),
      liquidDown: Float64List.fromList(s.liquid),
      vaporUp: Float64List.fromList(s.vapor),
      entrain: Float64List(n),
      weep: Float64List(n),
      holdup: Float64List.fromList(s.holdup),
      hcl: hcl,
      froth: froth,
      dp: Float64List(n),
      jetFlood: Float64List(n),
      dcFlood: Float64List(n),
      frothFill: Float64List(n),
      stability: Float64List(n),
      weepFrac: Float64List(n),
      efficiency: Float64List.fromList(s.eff),
      hetp: Float64List(n)..fillRange(0, n, nan),
      packFlood: Float64List(n)..fillRange(0, n, nan),
      flags: Uint8List(n),
    );
    // Report the flows the solver used in the last completed step, so that integrating the
    // snapshot flows closes the component balance exactly (the valves already hold next step's flow).
    final used = _debug.dt > 0;
    final f = used ? _debug.feedFlow : s.feedAct;
    final dFlow = used ? _debug.distillateFlow : _control.distillateValve.flow;
    final bFlow = used ? _debug.bottomsFlow : _control.bottomsValve.flow;
    final l0 = used ? _debug.refluxFlow : s.liquid[0];
    final vUp = used ? _debug.boilupFlow : s.vapor[N + 1];
    final xDrum = Float64List.fromList(s.x.sublist(0, nc));
    final xSump = Float64List.fromList(s.x.sublist((N + 1) * nc, (N + 2) * nc));
    final ySump = Float64List.fromList(s.y.sublist((N + 1) * nc, (N + 2) * nc));
    final streams = <StreamId, StreamSnapshot>{
      StreamId.feed: StreamSnapshot(
          StreamId.feed, f, Float64List.fromList(_inputs.z), nan),
      StreamId.reflux: StreamSnapshot(StreamId.reflux, l0, xDrum, nan),
      StreamId.distillate:
          StreamSnapshot(StreamId.distillate, dFlow, xDrum, nan),
      StreamId.bottoms: StreamSnapshot(StreamId.bottoms, bFlow, xSump, nan),
      StreamId.boilup: StreamSnapshot(StreamId.boilup, vUp, ySump, nan),
    };
    final xD = s.x[0];
    final xB = s.x[(N + 1) * nc];
    final fz = f * _inputs.z[0];
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
      qc: nan,
      qr: nan,
      columnDp: 0,
      maxFloodPct: 0,
      drumLevelPct: drumPct,
      sumpLevelPct: sumpPct,
      pTop: _config.condenser.pTopDesign,
      balanceResidual: fz > 0 ? (fz - dFlow * xD - bFlow * xB).abs() / fz : 0.0,
      energyResidual: nan,
    );
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
    return SimSnapshot(
      serial: ++_serial,
      time: s.time,
      tier: _tier,
      hydraulics: _hydraulics,
      layout: layout,
      components: List.unmodifiable(_config.components),
      stages: stages,
      streams: Map.unmodifiable(streams),
      condenser: CondenserSnapshot(s.holdup[0], drumPct),
      reboiler: ReboilerSnapshot(s.holdup[N + 1], sumpPct,
          mMin > 0 ? (s.holdup[N + 1] / mMin).clamp(0.0, 1.0) : 1.0),
      loops: [
        for (final l in _control.loops)
          LoopSnapshot(l.tag, l.mode, l.pv, l.sp, l.op),
      ],
      alarms: const [],
      kpis: kpis,
      steady: SteadyInfo(_steady, _residual),
      solverHealth: _health.copy(),
      visibleFaults: const [],
      levers: {for (final l in _levers) l.id: lever(l.id)},
      feedQ: _inputs.feedQ,
      murphree: _inputs.murphree,
    );
  }

  /// The Tier 1 thermo model for diagram builders.
  ConstantAlphaThermo get thermo => _thermo;

  /// Component data for the configured components.
  List<Component> get componentData {
    final db = ComponentDb.load();
    return [for (final id in _config.components) db[id]];
  }

  // ---------------------------------------------------------------- persistence

  Map<String, Object?> _dumpDynamic() => {
        'state': _state.toJson(),
        'control': _control.toJson(),
      };

  void _loadDynamic(Map<String, Object?> d) {
    _state.loadJson(d['state']! as Map<String, Object?>);
    _control.loadJson(d['control']! as Map<String, Object?>);
    _stepper.refreshFromHoldups();
    _stepper.refreshVapour();
    _stepper.bus.drumLevelPct = _stepper.drumLevelPct;
    _stepper.bus.sumpLevelPct = _stepper.sumpLevelPct;
    _debug.dt = 0;
  }

  /// Config, levers, full state and controller states (JSON-encodable).
  Map<String, Object?> saveState() => {
        'version': 1,
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
        },
        'alpha': _thermo.alpha.toList(),
        'dynamic': _dumpDynamic(),
        'carry': _carry,
        'serial': _serial,
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
    final sim = Simulator._restoring(cfg, opt);
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
    final a = saved['alpha']! as List<Object?>;
    for (var i = 0; i < a.length; i++) {
      sim._thermo.alpha[i] = (a[i]! as num).toDouble();
    }
    sim._loadDynamic(saved['dynamic']! as Map<String, Object?>);
    sim._carry = (saved['carry']! as num).toDouble();
    sim._serial = (saved['serial']! as num).toInt();
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
    sim._prevOp[0] = (po[0]! as num).toDouble();
    sim._prevOp[1] = (po[1]! as num).toDouble();
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
  final List<Map<String, Object?>> loops;
  final double dFlow, bFlow, feedAct, refluxAct, boilupAct;
  _Carry({
    required this.oldN,
    required this.oldNc,
    required this.x,
    required this.holdup,
    required this.time,
    required this.loops,
    required this.dFlow,
    required this.bFlow,
    required this.feedAct,
    required this.refluxAct,
    required this.boilupAct,
  });
}
