// The crude unit inside the Simulator (M9): construction, stepping, levers, live metrics, snapshot, persistence.
// A part of simulator.dart so that it can reach the private state; the generic methods branch to these.
part of 'simulator.dart';

/// One lab sample of the products (PHYSICS.md 9.6; ENGINE_API.md 11.12): the plant views show the last published one.
class _CrudeLab {
  final double time;
  final Float64List d86p5, d86p50, d86p95;
  final double residueTbp5;
  _CrudeLab(this.time, this.d86p5, this.d86p50, this.d86p95, this.residueTbp5);

  Map<String, Object?> toJson() => {
        'time': time,
        'p5': d86p5.toList(),
        'p50': d86p50.toList(),
        'p95': d86p95.toList(),
        'res': residueTbp5,
      };

  factory _CrudeLab.fromJson(Map<String, Object?> j) {
    Float64List f(String k) => Float64List.fromList([for (final v in j[k]! as List<Object?>) (v! as num).toDouble()]);
    return _CrudeLab((j['time']! as num).toDouble(), f('p5'), f('p50'), f('p95'), (j['res']! as num).toDouble());
  }
}

/// Run-time state of the crude unit.
class _CrudeRt {
  final CrudeColumn col;
  final CrudeControl cc;
  final CrudeProducts prod;
  double nextCheck = 60;
  final Float64List prevX = Float64List(CrudeColumn.ns * CrudeColumn.nc);
  final Float64List prevHold = Float64List(CrudeColumn.ns);
  final Float64List prevOp = Float64List(5);
  // noise-on monitor: successive 300-s means
  final Float64List sumT = Float64List(CrudeColumn.ns), prevMeanT = Float64List(CrudeColumn.ns);
  final Float64List sumH = Float64List(CrudeColumn.ns), prevMeanH = Float64List(CrudeColumn.ns);
  int nSum = 0, noisyCount = 0;
  bool hasPrev = false;
  double nextNoisy = 300;
  // lab results
  double nextSample = 1800;
  _CrudeLab? pending, published;
  double publishAt = double.infinity;
  // KPI cache (per sim time)
  double kpiTime = -1;
  CrudeProductKpis? kpiCache;
  _CrudeRt(this.col, this.cc, this.prod);
}

extension _SimCrude on Simulator {
  CrudeColumn get _col => _cr!.col;
  CrudeControl get _cc => _cr!.cc;

  // ---------------------------------------------------------------- construction
  void _buildCrude(ColumnConfig config, _Carry? carry) {
    final problems = config.validate();
    if (problems.isNotEmpty) throw ConfigException(problems.join('; '));
    _config = config;
    _tier = ThermoTier.t2;
    _hydraulics = config.hydraulics;
    final nc = config.nc;
    _state = ColumnState(config.trayCount, nc);
    _inputs = StepInputs(nc);
    _debug = StepDebug(nc);
    _trends = TrendBuffer();
    _checks = CrossCheckEngine();
    _faults = carry?.faults ?? FaultManager();
    _faults.onChange = _noteChange;
    _faults.componentIds = config.components;
    _faults.validator = (spec) {
      if (spec.type == FaultType.strippingSteamLoss) {
        final p = spec.location.steamPoint;
        if (p == null || !const ['bottom', 'ss1', 'ss2', 'ss3'].contains(p)) {
          throw ConfigException('F24 needs a steam point: bottom, ss1, ss2 or ss3');
        }
        return;
      }
      if (spec.type == FaultType.pumparoundTrip || spec.type == FaultType.cotUpset) return;
      _control.validateFault(spec);
    };
    final col = CrudeColumn(config, _health);
    col.hydFull = config.hydraulics == HydraulicsMode.full;
    final cc = CrudeControl.build(config, col, _seed);
    cc.primeInputs(config);
    col.initCold();
    cc.initialiseCrude(0);
    cc.attachTrends(_trends);
    cc.setNoise(options.measurementNoise);
    cc.onMaintenanceDone = (tag) => _faults.clearTag(tag);
    _control = cc;
    _cr = _CrudeRt(col, cc, CrudeProducts(col.th, trimPct: 100 * config.crude!.tbpTrim));
    _levers = _crudeLevers();
    _carry = 0;
    _halted = false;
    _crudeResetMonitor(capture: true);
    _crudeInitLab();
  }

  void _crudeInitLab() {
    final r = _cr!;
    final lab = _crudeSampleLab(_state.time - 1800);
    r.published = lab;
    r.pending = null;
    r.publishAt = double.infinity;
    r.nextSample = 1800 * ((_state.time) / 1800).floor() + 1800;
  }

  void _crudeInitControl() {
    _cc.initialiseCrude(_state.time);
    _trends.reset();
    _control.alarms.reset();
    _control.alarms.journal.clear();
    _lastEvalEnd = -1;
    _fields.clear();
    _checks.results = const [];
    _cr!.kpiTime = -1;
  }

  void _crudeWarmStart() {
    final key = jsonEncode([_config.toJson(), 'crude']);
    final cached = Simulator._warmCache[key];
    if (cached != null) {
      _crudeLoadDynamic(cached);
    } else {
      runToSteadyState(maxSimSeconds: 172800);
      Simulator._warmCache[key] = _crudeDumpDynamic(includeTrends: false);
    }
    _crudeAfterSteady(0);
  }

  void _crudeAfterSteady(double time) {
    _state.time = time;
    _col.time = time;
    _carry = 0;
    _control.reseed(_seed);
    _crudeInitControl();
    _levelViolation = 0;
    _crudeResetMonitor(capture: true);
    _steady = true;
    _steadyCount = 5;
    _crudeInitLab();
    if (_control.noise) _crudeResetNoisy();
  }

  // ---------------------------------------------------------------- stepping
  void _crudeStepOnce(double dt) {
    if (_halted) return;
    final cc = _cc, col = _col;
    final t = _state.time;
    _faults.applyCrude(t, cc.fault);
    cc.time = t;
    _control.applyFaults(_faults.controlSpecs);
    final ok = cc.stepAll(dt, t);
    _state.time = t + dt;
    if (!ok) {
      _halted = true;
      _health.fatal = true;
      _health.fatalMessage = 'The model could not continue from this state';
      _emit(SimEventType.solverFallback, _health.fatalMessage!);
      return;
    }
    _crudeMonitor();
    final d = col.drumLevelPct, sp = col.sumpLevelPct;
    if (d < 5 || d > 95 || sp < 5 || sp > 95) _levelViolation += dt;
    _cr!.kpiTime = -1;
    _crudeLabStep();
    _scenario?.update();
  }

  void _crudeLabStep() {
    final r = _cr!;
    final t = _state.time;
    if (t + 1e-9 >= r.publishAt && r.pending != null) {
      r.published = r.pending;
      r.pending = null;
      r.publishAt = double.infinity;
    }
    if (t + 1e-9 >= r.nextSample) {
      r.pending = _crudeSampleLab(r.nextSample);
      r.publishAt = r.nextSample + 900;
      r.nextSample += 1800;
    }
  }

  _CrudeLab _crudeSampleLab(double time) {
    final r = _cr!;
    final col = r.col;
    final p5 = Float64List(4), p50 = Float64List(4), p95 = Float64List(4);
    for (var k = 0; k < 4; k++) {
      final (a, b, c) = r.prod.d86Key(k == 0 ? col.yy : col.x, _productOffset(k));
      p5[k] = a;
      p50[k] = b;
      p95[k] = c;
    }
    return _CrudeLab(time, p5, p50, p95, r.prod.tbpTrimmed(col.xSump, 0, 5));
  }

  /// Offset (in the composition arrays of the column) of product k: 0 naphtha (vapour of stage 1), 1..3 the boots.
  int _productOffset(int k) => k == 0 ? 0 : _col.s2(k - 1) * CrudeColumn.nc;

  // ---------------------------------------------------------------- steady monitor
  void _crudeResetMonitor({bool capture = false}) {
    final r = _cr!;
    r.nextCheck = _state.time + 60;
    _steadyCount = 0;
    _steady = false;
    _residual = double.infinity;
    if (capture) _crudeCapture();
  }

  void _crudeCapture() {
    final r = _cr!;
    r.prevX.setAll(0, r.col.x);
    r.prevHold.setAll(0, r.col.hold);
    for (var l = 0; l < 5; l++) {
      r.prevOp[l] = _control.loops[l].op;
    }
  }

  void _crudeResetNoisy() {
    final r = _cr!;
    r.sumT.fillRange(0, r.sumT.length, 0);
    r.sumH.fillRange(0, r.sumH.length, 0);
    r.nSum = 0;
    r.hasPrev = false;
    r.nextNoisy = _state.time + 300;
    r.noisyCount = _steady ? 3 : 0;
  }

  void _crudeMonitor() {
    final r = _cr!;
    final col = r.col;
    if (_control.noise) {
      for (var a = 0; a < CrudeColumn.ns; a++) {
        r.sumT[a] += col.t[a];
        r.sumH[a] += col.hold[a];
      }
      r.nSum++;
      if (_state.time + 1e-9 < r.nextNoisy) return;
      r.nextNoisy += 300;
      final inv = 1.0 / r.nSum;
      var delta = 0.0;
      if (r.hasPrev) {
        for (var a = 0; a < CrudeColumn.ns; a++) {
          delta = math.max(delta, (r.sumT[a] * inv - r.prevMeanT[a]).abs() / 0.5);
          final m = r.sumH[a] * inv;
          delta = math.max(delta, (m - r.prevMeanH[a]).abs() / (0.02 * math.max(m, 1e-9)));
        }
        _prevResidual = _residual;
        _residual = delta;
        r.noisyCount = delta < 1 ? r.noisyCount + 1 : 0;
        final was = _steady;
        _steady = r.noisyCount >= 3;
        if (_steady && !was) _emit(SimEventType.steadyReached, 'Steady state');
      }
      for (var a = 0; a < CrudeColumn.ns; a++) {
        r.prevMeanT[a] = r.sumT[a] * inv;
        r.prevMeanH[a] = r.sumH[a] * inv;
        r.sumT[a] = 0;
        r.sumH[a] = 0;
      }
      r.hasPrev = true;
      r.nSum = 0;
      return;
    }
    if (_state.time + 1e-9 < r.nextCheck) return;
    r.nextCheck += 60;
    var delta = 0.0;
    for (var k = 0; k < col.x.length; k++) {
      delta = math.max(delta, (col.x[k] - r.prevX[k]).abs());
    }
    for (var j = 0; j < col.hold.length; j++) {
      delta = math.max(delta, (col.hold[j] - r.prevHold[j]).abs() / math.max(col.hold[j], 1e-12));
    }
    for (var l = 0; l < 5; l++) {
      delta = math.max(delta, (_control.loops[l].op - r.prevOp[l]).abs() / 100);
    }
    _crudeCapture();
    _prevResidual = _residual;
    _residual = delta;
    _steadyCount = delta < 1e-7 ? _steadyCount + 1 : 0;
    final was = _steady;
    _steady = _steadyCount >= 5;
    if (_steady && !was) _emit(SimEventType.steadyReached, 'Steady state');
  }

  // ---------------------------------------------------------------- levers
  List<LeverSpec> _crudeLevers() {
    final lev = _config.initialLevers;
    double d(String k, double def) => lev[k] ?? def;
    LeverSpec l(String id, String label, Quantity q, double min, double max, double def,
            {String? loop, String group = 'crude', bool integer = false}) =>
        LeverSpec(
            id: id,
            label: label,
            quantity: q,
            min: min,
            max: max,
            defaultValue: def,
            tiers: const {ThermoTier.t2},
            boundLoop: loop,
            group: group,
            integer: integer);
    final out = <LeverSpec>[
      l('crudeRate', 'Crude rate', Quantity.volumeFlowCrude, 0.009167, 0.073611, d('crudeRate', 0.0368056)),
      l('cot', 'Furnace outlet temperature (COT)', Quantity.temperature, 603.15, 663.15, d('cot', 618.15), loop: 'TC-320'),
      l('pTop', 'Top pressure', Quantity.pressure, 100000, 250000, d('pTop', 160000)),
      l('topTSp', 'Top temperature SP', Quantity.temperature, 363.15, 433.15, d('topTSp', 398.15), loop: 'TC-301'),
      for (var k = 0; k < 3; k++)
        l('drawRate.${_drawName(k)}', '${_drawLabel(k)} draw', Quantity.volumeFlowCrude, 0,
            _drawShare(k) * 0.073611, d('drawRate.${_drawName(k)}', 0.0), loop: 'FC-${311 + k}'),
      l('paDuty', 'Pumparound duty', Quantity.energyRate, 0, 10e6, d('paDuty', 5e6), loop: 'FC-314'),
      l('steam.bottom', 'Bottom stripping steam', Quantity.massFlow, 0, 1.3889, d('steam.bottom', 0.555556), loop: 'FC-321'),
      for (var k = 0; k < 3; k++)
        l('steam.ss${k + 1}', 'Stripper steam ${_drawLabel(k)}', Quantity.massFlow, 0, 0.27778,
            d('steam.ss${k + 1}', 0.0833333), loop: 'FC-${322 + k}'),
      l('drumTSp', 'Overhead drum temperature', Quantity.temperature, 303.15, 333.15, d('drumTSp', 318.15)),
      l('refluxOp', 'Reflux valve OP', Quantity.percent, 0, 100, 46, loop: 'FC-301', group: 'advanced'),
      for (var k = 0; k < 3; k++)
        l('drawOp.${_drawName(k)}', '${_drawLabel(k)} product valve OP', Quantity.percent, 0, 100, 25,
            loop: 'FC-${311 + k}', group: 'advanced'),
      l('paOp', 'PA cooler bypass OP', Quantity.percent, 0, 100, 33, loop: 'FC-314', group: 'advanced'),
      l('steamOp.bottom', 'Bottom steam valve OP', Quantity.percent, 0, 100, 40, loop: 'FC-321', group: 'advanced'),
      for (var k = 0; k < 3; k++)
        l('steamOp.ss${k + 1}', 'Stripper steam ${k + 1} valve OP', Quantity.percent, 0, 100, 30,
            loop: 'FC-${322 + k}', group: 'advanced'),
      l('noise', 'Measurement noise', Quantity.dimensionless, 0, 1, options.measurementNoise ? 1 : 0,
          group: 'advanced', integer: true),
      l('view', 'View (0 model, 1 plant, 2 plant with calculations)', Quantity.dimensionless, 0, 2, 0,
          group: 'advanced', integer: true),
      l('badPvShed', 'Shed loops on bad PV', Quantity.dimensionless, 0, 1, 1, group: 'advanced', integer: true),
      l('hydraulics', 'Hydraulics (0 ideal, 1 full)', Quantity.dimensionless, 0, 1,
          _config.hydraulics == HydraulicsMode.full ? 1 : 0,
          group: 'advanced', integer: true),
      for (final v in _control.valves)
        l('bypass.${v.id}', 'Bypass ${v.id}', Quantity.percent, -1, 100, -1, group: 'advanced'),
    ];
    _syncDrawSpecsIn(out);
    return out;
  }

  static const List<String> _drawNames = ['kero', 'diesel', 'ago'];
  static const List<String> _drawLabels = ['Kerosene', 'Diesel', 'AGO'];
  static const List<double> _drawShares = [0.25, 0.30, 0.15];
  String _drawName(int k) => _drawNames[k];
  String _drawLabel(int k) => _drawLabels[k];
  double _drawShare(int k) => _drawShares[k];

  /// The draw levers' range is a share of the current crude rate (SCOPE.md 4.4); a value above it is kept.
  void _syncDrawSpecsIn(List<LeverSpec> specs) {
    final rate = _col.inp.crudeRate;
    for (var k = 0; k < 3; k++) {
      final id = 'drawRate.${_drawNames[k]}';
      final i = specs.indexWhere((s) => s.id == id);
      if (i < 0) continue;
      final cur = specs[i];
      final loop = [_cc.fc311, _cc.fc312, _cc.fc313][k];
      final def = (_config.initialLevers[id] ?? loop.sp);
      specs[i] = LeverSpec(
          id: id,
          label: cur.label,
          quantity: cur.quantity,
          min: 0,
          max: math.max(_drawShares[k] * rate, loop.sp),
          defaultValue: def,
          tiers: cur.tiers,
          boundLoop: cur.boundLoop,
          group: cur.group);
    }
  }

  double _crudeLever(LeverId id) {
    final cc = _cc, col = _col;
    if (id.startsWith('bypass.')) return _control.valve(id.substring(7)).bypassTarget;
    switch (id) {
      case 'crudeRate':
        return col.inp.crudeRate;
      case 'cot':
        return cc.tc320.sp;
      case 'pTop':
        return col.inp.pTop;
      case 'topTSp':
        return cc.tc301.sp;
      case 'drawRate.kero':
        return cc.fc311.sp;
      case 'drawRate.diesel':
        return cc.fc312.sp;
      case 'drawRate.ago':
        return cc.fc313.sp;
      case 'paDuty':
        return cc.fc314.sp;
      case 'steam.bottom':
        return cc.fc321.sp;
      case 'steam.ss1':
        return cc.fc322.sp;
      case 'steam.ss2':
        return cc.fc323.sp;
      case 'steam.ss3':
        return cc.fc324.sp;
      case 'drumTSp':
        return col.inp.drumT;
      case 'refluxOp':
        return cc.fc301.op;
      case 'drawOp.kero':
        return cc.fc311.op;
      case 'drawOp.diesel':
        return cc.fc312.op;
      case 'drawOp.ago':
        return cc.fc313.op;
      case 'paOp':
        return cc.fc314.op;
      case 'steamOp.bottom':
        return cc.fc321.op;
      case 'steamOp.ss1':
        return cc.fc322.op;
      case 'steamOp.ss2':
        return cc.fc323.op;
      case 'steamOp.ss3':
        return cc.fc324.op;
      case 'noise':
        return _control.noise ? 1 : 0;
      case 'view':
        return _view.index.toDouble();
      case 'badPvShed':
        return _control.badPvShed ? 1 : 0;
      case 'hydraulics':
        return col.hydFull ? 1 : 0;
    }
    throw ArgumentError('Unknown lever "$id"');
  }

  void _crudeSetLever(LeverId id, double value) {
    final spec = _spec(id);
    const eps = 1e-9;
    if (value.isNaN || value < spec.min - eps * (1 + spec.min.abs()) || value > spec.max + eps * (1 + spec.max.abs())) {
      throw RangeError('Lever $id = $value outside [${spec.min}, ${spec.max}]');
    }
    final v = value.clamp(spec.min, spec.max).toDouble();
    final cc = _cc, col = _col;
    if (id.startsWith('bypass.')) {
      final valve = _control.valve(id.substring(7));
      valve.bypassTarget = v < 0 ? -1 : v;
      if (v >= 0) {
        for (final l in _control.loops) {
          if (l.mvRef == valve.id && l.mode != LoopMode.man) _control.setMode(l.tag, LoopMode.man);
        }
      }
      return;
    }
    switch (id) {
      case 'crudeRate':
        col.inp.crudeRate = v;
        _syncDrawSpecsIn(_levers);
      case 'cot':
        _control.setSp('TC-320', v);
      case 'pTop':
        col.inp.pTop = v;
      case 'topTSp':
        _control.setSp('TC-301', v);
      case 'drawRate.kero':
        _control.setSp('FC-311', v);
      case 'drawRate.diesel':
        _control.setSp('FC-312', v);
      case 'drawRate.ago':
        _control.setSp('FC-313', v);
      case 'paDuty':
        _control.setSp('FC-314', v);
      case 'steam.bottom':
        _control.setSp('FC-321', v);
      case 'steam.ss1':
        _control.setSp('FC-322', v);
      case 'steam.ss2':
        _control.setSp('FC-323', v);
      case 'steam.ss3':
        _control.setSp('FC-324', v);
      case 'drumTSp':
        col.inp.drumT = v;
      case 'refluxOp':
        _opLever('FC-301', v);
      case 'drawOp.kero':
        _opLever('FC-311', v);
      case 'drawOp.diesel':
        _opLever('FC-312', v);
      case 'drawOp.ago':
        _opLever('FC-313', v);
      case 'paOp':
        _opLever('FC-314', v);
      case 'steamOp.bottom':
        _opLever('FC-321', v);
      case 'steamOp.ss1':
        _opLever('FC-322', v);
      case 'steamOp.ss2':
        _opLever('FC-323', v);
      case 'steamOp.ss3':
        _opLever('FC-324', v);
      case 'noise':
        _crudeSetNoise(v >= 0.5);
        return;
      case 'view':
        _view = SimView.values[v.round().clamp(0, 2)];
        return;
      case 'badPvShed':
        _control.badPvShed = v >= 0.5;
        return;
      case 'hydraulics':
        _hydraulics = v >= 0.5 ? HydraulicsMode.full : HydraulicsMode.ideal;
        col.hydFull = v >= 0.5;
        col.hydraulics();
        _config = _config.copyWith(hydraulics: _hydraulics);
    }
    cc.time = _state.time;
    _noteChange();
  }

  void _crudeSetNoise(bool on) {
    if (on == _control.noise) return;
    _control.setNoise(on);
    _crudeResetNoisy();
    if (!on) {
      _cr!.nextCheck = _state.time + 60;
      _steadyCount = _steady ? 5 : 0;
      _crudeCapture();
    }
  }

  // ---------------------------------------------------------------- live metrics
  CrudeProductKpis _crudeKpis({bool lab = false}) {
    final r = _cr!;
    if (!lab && r.kpiCache != null && r.kpiTime == _state.time) return r.kpiCache!;
    final col = r.col;
    final cc = r.cc;
    final plant = _view.isPlant;
    final yield5 = Float64List(5), flow5 = Float64List(5);
    final rate = col.inp.crudeRate;
    flow5[0] = col.naphthaOut * col.th.vStdMix(col.yy, 0);
    for (var k = 0; k < 3; k++) {
      flow5[1 + k] = col.pAct[k] * col.th.vStdMix(col.x, col.s2(k) * CrudeColumn.nc);
    }
    flow5[4] = col.residueOut * col.th.vStdMix(col.xSump, 0);
    for (var k = 0; k < 5; k++) {
      yield5[k] = 100 * flow5[k] / rate;
    }
    final p5 = Float64List(4), p50 = Float64List(4), p95 = Float64List(4);
    double resTbp5;
    var labTime = double.nan;
    if (plant) {
      final l = r.published!;
      p5.setAll(0, l.d86p5);
      p50.setAll(0, l.d86p50);
      p95.setAll(0, l.d86p95);
      resTbp5 = l.residueTbp5;
      labTime = l.time;
      // yields from the product flow meters (plant views)
      final ftCrude = math.max(cc.ft300.value, 1e-9);
      yield5[1] = 100 * cc.instrument('FT-311').value / ftCrude;
      yield5[2] = 100 * cc.instrument('FT-312').value / ftCrude;
      yield5[3] = 100 * cc.instrument('FT-313').value / ftCrude;
    } else {
      for (var k = 0; k < 4; k++) {
        final (a, b, c) = r.prod.d86Key(k == 0 ? col.yy : col.x, _productOffset(k));
        p5[k] = a;
        p50[k] = b;
        p95[k] = c;
      }
      resTbp5 = r.prod.tbpTrimmed(col.xSump, 0, 5);
    }
    final calc = _view == SimView.plantCalc;
    final nan = double.nan;
    final kp = CrudeProductKpis(
      yieldVolPct: yield5,
      productFlow: flow5,
      d86p5: p5,
      d86p50: p50,
      d86p95: p95,
      gapKeroNaphtha: p5[1] - p95[0],
      gapDieselKero: p5[2] - p95[1],
      gapAgoDiesel: p5[3] - p95[2],
      residueTbp5: resTbp5,
      overflashVolPct: col.overflash,
      topT: plant ? cc.instrument('TI-341').value : col.t[0],
      flashZoneT: plant ? cc.instrument('TI-349').value : col.t[col.feedSt - 1],
      bottomT: plant ? cc.instrument('TI-350').value : col.t[CrudeColumn.nm - 1],
      cot: plant ? (calc ? nan : cc.ti320.value) : col.inp.cot,
      qc: plant && !calc ? nan : col.qc,
      qcMax: col.cu.qcMax,
      qPa: plant ? cc.qt314.value : col.qPA,
      qPaMax: plant && !calc ? nan : col.qPAmax,
      paReturnT: plant ? cc.ti314.value : col.paReturnT,
      paCirculation: plant ? cc.fi314.value : col.paAct * col.th.vStdMix(col.x, (col.paDrawSt - 1) * CrudeColumn.nc),
      waterDewMargin: plant && !calc ? nan : col.waterDewMargin,
      drawDry: [for (var k = 0; k < 3; k++) col.cutFac[k] < 0.999],
      condenserLimited: cc.modelCondenserLimited,
      paDutyLimited: cc.modelPaDutyLimited,
      labSampleTime: labTime,
    );
    if (!lab) {
      r.kpiCache = kp;
      r.kpiTime = _state.time;
    }
    return kp;
  }

  /// True model values (never the plant view) for scenario predicates.
  CrudeProductKpis _crudeTrueKpis() {
    final was = _view;
    _view = SimView.model;
    final k = _crudeKpis(lab: true);
    _view = was;
    return k;
  }

  dynamic _crudeLiveMetric(String path) {
    final col = _col, cc = _cc;
    switch (path) {
      case 'steady':
        return _steady;
      case 'tier':
        return 2;
      case 'preset':
        return _config.presetId;
      case 'alarm.count':
        return _control.alarms.activeCount;
      case 'safety.reliefLifted':
        return false;
      case 'safety.levelViolationSeconds':
        return _levelViolation;
      case 'condenser.drumLevelPct':
        return col.drumLevelPct;
      case 'condenser.qc':
        return col.qc;
      case 'kpi.drumLevelPct':
        return col.drumLevelPct;
      case 'kpi.sumpLevelPct':
        return col.sumpLevelPct;
      case 'kpi.qc':
        return col.qc;
      case 'kpi.pTop':
        return col.inp.pTop;
      case 'kpi.columnDp':
        return col.columnDp;
      case 'kpi.maxFloodPct':
        return 100 * cc.maxFlood;
      case 'kpi.maxWeepFraction':
        return cc.maxWeep;
    }
    if (path.startsWith('crude.')) {
      final k = _crudeTrueKpis();
      final parts = path.substring(6).split('.');
      const prods = ['naphtha', 'kero', 'diesel', 'ago', 'residue'];
      switch (parts[0]) {
        case 'yield':
          final i = prods.indexOf(parts[1]);
          return i < 0 ? null : k.yieldVolPct[i];
        case 'd86p5':
        case 'd86p50':
        case 'd86p95':
          final i = prods.indexOf(parts[1]);
          if (i < 0 || i > 3) return null;
          return (parts[0] == 'd86p5' ? k.d86p5 : (parts[0] == 'd86p50' ? k.d86p50 : k.d86p95))[i];
        case 'gap':
          return switch (parts[1]) {
            'keroNaphtha' => k.gapKeroNaphtha,
            'dieselKero' => k.gapDieselKero,
            'agoDiesel' => k.gapAgoDiesel,
            _ => null
          };
        case 'residueTbp5':
          return k.residueTbp5;
        case 'overflash':
          return k.overflashVolPct;
        case 'topT':
          return k.topT;
        case 'flashZoneT':
          return k.flashZoneT;
        case 'bottomT':
          return k.bottomT;
        case 'cot':
          return k.cot;
        case 'qc':
          return k.qc;
        case 'qPa':
          return k.qPa;
        case 'drawDry':
          final i = const ['kero', 'diesel', 'ago'].indexOf(parts[1]);
          return i < 0 ? null : (k.drawDry[i] ? 1 : 0);
      }
      return null;
    }
    final om = RegExp(r'^objective\[(\w+)\]\.met$').firstMatch(path);
    if (om != null) return _scenario?.objectiveMet(om.group(1)!) ?? false;
    if (path.startsWith('lever.')) {
      try {
        return _crudeLever(path.substring(6));
      } on ArgumentError {
        return null;
      }
    }
    var m = Simulator._mStage.firstMatch(path);
    if (m != null) {
      final j = int.parse(m.group(1)!);
      if (j < 1 || j > CrudeColumn.nm) return null;
      switch (m.group(2)) {
        case 't':
          return col.t[j - 1];
        case 'p':
          return col.p[j - 1];
        case 'holdup':
          return col.hold[j - 1];
        case 'jetFlood':
          return col.flood[j - 1];
        case 'weepFrac':
          return col.weepFrac[j - 1];
        case 'x':
          return col.x[(j - 1) * CrudeColumn.nc];
      }
      return null;
    }
    m = Simulator._mLoop.firstMatch(path);
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
    m = Simulator._mInst.firstMatch(path);
    if (m != null) {
      final i = _control.instrument(m.group(1)!);
      return m.group(2) == 'value' ? i.value : i.quality.name;
    }
    m = Simulator._mValve.firstMatch(path);
    if (m != null) {
      final v = _control.valve(m.group(1)!);
      final loop = _control.loops.firstWhere((l) => l.mvRef == v.id);
      return m.group(2) == 'op' ? loop.op : v.position;
    }
    m = Simulator._mAlarm.firstMatch(path);
    if (m != null) return _control.alarms.isActive(m.group(1)!);
    return null;
  }

  // ---------------------------------------------------------------- snapshot
  SimSnapshot _crudeSnapshot() {
    final r = _cr!;
    final col = r.col, cc = r.cc;
    const nc = CrudeColumn.nc, nm = CrudeColumn.nm;
    const n = nm + 2, ncAll = nc + 1; // stages 0..31, components PC1..PC9 and water
    final plant = _view.isPlant, calc = _view == SimView.plantCalc;
    final nan = double.nan;
    final x = Float64List(n * ncAll), y = Float64List(n * ncAll), yStar = Float64List(n * ncAll);
    final t = Float64List(n), p = Float64List(n), liquid = Float64List(n), vapor = Float64List(n);
    final holdup = Float64List(n), hcl = Float64List(n), froth = Float64List(n), dp = Float64List(n);
    final jet = Float64List(n), weep = Float64List(n), eff = Float64List(n);
    for (var i = 0; i < nc; i++) {
      x[i] = col.yy[i];
      y[i] = col.yy[i];
      x[(nm + 1) * ncAll + i] = col.xSump[i];
    }
    t[0] = col.inp.drumT;
    p[0] = col.p[0] - col.cu.drumDp;
    holdup[0] = col.drumHold;
    for (var j = 1; j <= nm; j++) {
      final a = j - 1;
      for (var i = 0; i < nc; i++) {
        x[j * ncAll + i] = col.x[a * nc + i];
        y[j * ncAll + i] = col.yy[a * nc + i] * (1 - col.ywF[a]);
        yStar[j * ncAll + i] = col.yy[a * nc + i];
      }
      y[j * ncAll + nc] = col.ywF[a];
      t[j] = col.t[a];
      p[j] = col.p[a];
      liquid[j] = col.l[a];
      vapor[j] = col.v[a] + col.steamUp[a];
      holdup[j] = col.hold[a];
      hcl[j] = col.hcl[a];
      froth[j] = col.hcl[a] / 0.5;
      dp[j] = col.dp[a];
      jet[j] = col.flood[a];
      weep[j] = col.weepFrac[a];
      eff[j] = 1.0;
    }
    liquid[0] = col.l0;
    liquid[nm + 1] = col.residueOut;
    t[nm + 1] = col.t[nm - 1];
    p[nm + 1] = col.p[nm - 1] + col.dp[nm - 1];
    holdup[nm + 1] = col.sumpHold;
    vapor[0] = col.v[0];
    var stages = StageArrays(
      n: n,
      nc: ncAll,
      x: x,
      y: y,
      yStar: yStar,
      t: t,
      p: p,
      liquidDown: liquid,
      vaporUp: vapor,
      entrain: Float64List(n),
      weep: Float64List(n),
      holdup: holdup,
      hcl: hcl,
      froth: froth,
      dp: dp,
      dpDry: Float64List(n),
      jetFlood: jet,
      dcFlood: Float64List(n),
      frothFill: Float64List(n),
      stability: Float64List(n),
      weepFrac: weep,
      efficiency: eff,
      hetp: Float64List(n)..fillRange(0, n, nan),
      packFlood: Float64List(n)..fillRange(0, n, nan),
      packHoldup: Float64List(n)..fillRange(0, n, nan),
      wetFrac: Float64List(n)..fillRange(0, n, nan),
      flags: Uint8List(n),
    );
    final kp = _crudeKpis();
    final instr = [for (final i in _control.visibleInstruments) i.readingAt(_state.time)];
    InstrumentReading rd(String tag) => instr.firstWhere((q) => q.tag == tag);
    if (plant) {
      Float64List nanArr(int len) => Float64List(len)..fillRange(0, len, nan);
      final tPlant = nanArr(n);
      for (var k = 0; k < CrudeControl.tiStages.length; k++) {
        tPlant[CrudeControl.tiStages[k]] = rd('TI-${341 + k}').value;
      }
      stages = StageArrays(
        n: n,
        nc: ncAll,
        x: nanArr(n * ncAll),
        y: nanArr(n * ncAll),
        yStar: nanArr(n * ncAll),
        t: tPlant,
        p: stages.p,
        liquidDown: nanArr(n),
        vaporUp: nanArr(n),
        entrain: nanArr(n),
        weep: nanArr(n),
        holdup: nanArr(n),
        hcl: stages.hcl,
        froth: stages.froth,
        dp: calc ? stages.dp : nanArr(n),
        dpDry: nanArr(n),
        jetFlood: calc ? stages.jetFlood : nanArr(n),
        dcFlood: nanArr(n),
        frothFill: nanArr(n),
        stability: nanArr(n),
        weepFrac: calc ? stages.weepFrac : nanArr(n),
        efficiency: nanArr(n),
        hetp: stages.hetp,
        packFlood: stages.packFlood,
        packHoldup: stages.packHoldup,
        wetFrac: stages.wetFrac,
        flags: stages.flags,
      );
    }
    // streams
    final zf = Float64List(ncAll);
    for (var i = 0; i < nc; i++) {
      zf[i] = col.z[i];
    }
    final xr = Float64List(ncAll), xn = Float64List(ncAll);
    for (var i = 0; i < nc; i++) {
      xr[i] = col.xSump[i];
      xn[i] = col.yy[i];
    }
    Float64List nanVec() => Float64List(ncAll)..fillRange(0, ncAll, nan);
    final streams = <StreamId, StreamSnapshot>{
      StreamId.feed: StreamSnapshot(StreamId.feed, plant ? cc.ft300.value / col.th.vStdMix(col.z, 0) : col.fF, zf,
          plant ? cc.ti320.value : col.inp.cot),
      StreamId.reflux: StreamSnapshot(StreamId.reflux, plant ? cc.instrument('FT-301').value : col.l0, plant ? nanVec() : xn, col.inp.drumT),
      StreamId.distillate: StreamSnapshot(StreamId.distillate, col.naphthaOut, plant ? nanVec() : xn, col.inp.drumT),
      StreamId.bottoms: StreamSnapshot(StreamId.bottoms, col.residueOut, plant ? nanVec() : xr, col.t[nm - 1]),
    };
    var maxFlood = 0.0, maxWeep = 0.0;
    for (var j = 0; j < nm; j++) {
      maxFlood = math.max(maxFlood, col.flood[j]);
      maxWeep = math.max(maxWeep, col.weepFrac[j]);
    }
    final kpis = Kpis(
      crude: kp,
      xD: nan,
      xB: nan,
      d: col.naphthaOut,
      b: col.residueOut,
      refluxRatio: col.naphthaOut > 1e-9 ? col.l0 / col.naphthaOut : nan,
      boilup: nan,
      qc: plant && !calc ? nan : col.qc,
      qr: nan,
      columnDp: plant ? cc.pdt301.value : col.columnDp,
      maxFloodPct: plant && !calc ? nan : 100 * maxFlood,
      maxWeepFraction: plant && !calc ? nan : maxWeep,
      drumLevelPct: plant ? cc.lt301.value : col.drumLevelPct,
      sumpLevelPct: plant ? cc.lt302.value : col.sumpLevelPct,
      pTop: col.inp.pTop,
      balanceResidual: plant ? nan : col.massResidual(),
      energyResidual: plant ? nan : col.energyResidual(),
    );
    // strippers
    final strip = <StripperSnapshot>[
      for (var k = 0; k < 3; k++)
        StripperSnapshot(
          t: Float64List.fromList([col.t[col.s1(k)], col.t[col.s2(k)]]),
          l: Float64List.fromList([col.l[col.s1(k)], col.l[col.s2(k)]]),
          v: Float64List.fromList([col.v[col.s1(k)], col.v[col.s2(k)]]),
          levelPct: plant ? rd('LT-${311 + k}').value : col.bootLevelPct(k),
          draw: col.sd[k],
          product: col.pAct[k],
          vaporReturn: col.v[col.s1(k)],
          steam: col.inp.steam[1 + k] * CrudeColumn.kgs2mol,
        ),
    ];
    // loops, valves
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
      valveSnaps.add(ValveSnapshot(v.id, loop.op, plant ? nan : v.position, v.fMax, v.expectedFlow(loop.op),
          v.bypassActive ? v.bypassPos : -1));
    }
    const calcAlarms = {'model.flood', 'model.weep', 'model.paDutyLimited', 'model.drawDry', 'model.condenserLimited'};
    final alarms = [
      for (final a in _control.alarms.active())
        if (!plant || !a.id.startsWith('model.') || (calc && calcAlarms.contains(a.id))) a,
    ];
    final layout = ColumnLayoutInfo(
      nTrays: nm,
      feedStages: [col.feedSt],
      kinds: [StageKind.drum, for (var j = 1; j <= nm; j++) StageKind.tray, StageKind.sump],
      names: ['Drum', for (var j = 1; j <= nm; j++) 'Stage $j', 'Sump'],
      sectionEnds: const [26, 30],
    );
    final condenser = CondenserSnapshot(col.drumHold, kpis.drumLevelPct,
        qC: kpis.qc,
        tCond: plant ? nan : col.t[0],
        tReflux: col.inp.drumT,
        partial: false,
        vaporInventory: Float64List(0));
    final reboiler = ReboilerSnapshot(col.sumpHold, kpis.sumpLevelPct, 1.0, tSump: plant ? rd('TI-350').value : col.t[nm - 1]);
    final prodData = _crudeProductData(kp);
    return SimSnapshot(
      serial: ++_serial,
      time: _state.time,
      tier: ThermoTier.t2,
      hydraulics: _hydraulics,
      layout: layout,
      components: List.unmodifiable(_config.components),
      stages: stages,
      streams: Map.unmodifiable(streams),
      condenser: condenser,
      reboiler: reboiler,
      loops: loopSnaps,
      alarms: alarms,
      kpis: kpis,
      steady: SteadyInfo(_steady, _residual),
      solverHealth: _health.copy(),
      visibleFaults: plant ? const [] : _faults.activeAt(_state.time),
      levers: {for (final l in _levers) l.id: _crudeLever(l.id)},
      feedQ: 1.0,
      murphree: 1.0,
      view: _view,
      instruments: instr,
      valves: valveSnaps,
      crossChecks: const [],
      fieldChecks: const [],
      scenario: _scenario?.snapshot(),
      strippers: strip,
      crudeProducts: prodData,
    );
  }

  /// Products-tab data (ENGINE_API.md 7.3).
  CrudeProductData _crudeProductData(CrudeProductKpis kp) {
    final r = _cr!;
    final col = r.col;
    final th = col.th;
    final plant = _view.isPlant;
    final tbp = <List<({double vol, double t})>>[
      [for (var pc = 0; pc <= 100; pc += 2) (vol: pc.toDouble(), t: th.assay.tbpAt(pc.toDouble()) + 273.15)],
    ];
    final d86 = <List<({double vol, double t})>>[];
    final lab = r.published!;
    if (plant) {
      // lab results give 5/50/95 %: the curves through them are not available, so the plant views draw those three points
      for (var k = 0; k < 4; k++) {
        d86.add([
          (vol: 5.0, t: lab.d86p5[k]),
          (vol: 50.0, t: lab.d86p50[k]),
          (vol: 95.0, t: lab.d86p95[k]),
        ]);
      }
    }
    for (var k = 0; k < 5; k++) {
      final x = k == 0 ? col.yy : (k == 4 ? col.xSump : col.x);
      final off = k == 0 ? 0 : (k == 4 ? 0 : col.s2(k - 1) * CrudeColumn.nc);
      tbp.add(plant ? const [] : r.prod.tbpCurve(x, off));
      if (!plant && k < 4) {
        final c = r.prod.productD86(x, off);
        d86.add([for (var i = 0; i < d86Points.length; i++) (vol: d86Points[i], t: c[i])]);
      }
    }
    final gaps = [
      GapBar(CrudeProduct.naphtha, CrudeProduct.kero, kp.d86p95[0], kp.d86p5[1]),
      GapBar(CrudeProduct.kero, CrudeProduct.diesel, kp.d86p95[1], kp.d86p5[2]),
      GapBar(CrudeProduct.diesel, CrudeProduct.ago, kp.d86p95[2], kp.d86p5[3]),
    ];
    // ideal yields at the current draw levers: naphtha cut at TBP 165 C, then the three product levers (PHYSICS.md 9.8)
    final rate = col.inp.crudeRate;
    final a = th.assay;
    final yN = a.volAt(165);
    final lev = [for (final l in [_cc.fc311, _cc.fc312, _cc.fc313]) 100 * l.sp / rate];
    final ideal = Float64List.fromList([yN, ...lev, 100 - yN - lev.fold(0.0, (s, v) => s + v)]);
    final cut = Float64List.fromList([
      165 + 273.15,
      a.tbpAt(yN + lev[0]) + 273.15,
      a.tbpAt(yN + lev[0] + lev[1]) + 273.15,
      a.tbpAt(yN + lev[0] + lev[1] + lev[2]) + 273.15,
    ]);
    return CrudeProductData(tbp, d86, gaps, ideal, cut, labSampleTime: plant ? lab.time : double.nan);
  }

  // ---------------------------------------------------------------- persistence
  Map<String, Object?> _crudeDumpDynamic({bool includeTrends = true}) => {
        'crude': _col.toJson(),
        'control': _control.toJson(includeTrends: includeTrends),
        'time': _state.time,
      };

  void _crudeLoadDynamic(Map<String, Object?> d) {
    _col.loadJson(d['crude']! as Map<String, Object?>);
    _control.loadJson(d['control']! as Map<String, Object?>);
    _state.time = (d['time'] as num?)?.toDouble() ?? _col.time;
    _cr!.kpiTime = -1;
  }

  Map<String, Object?> _crudeSaveState() => {
        'version': 2,
        'config': _config.toJson(),
        'options': {
          'dt': options.dt,
          'dtFastForward': options.dtFastForward,
          'murphreePasses': options.murphreePasses,
          'seed': options.seed,
          'measurementNoise': options.measurementNoise,
        },
        'levers': {for (final l in _levers) l.id: _crudeLever(l.id)},
        'dynamic': _crudeDumpDynamic(),
        'faults': _faults.toJson(),
        'carry': _carry,
        'seed': _seed,
        'scenario': _scenario == null ? null : {'def': _scenario!.def.source, 'state': _scenario!.toJson()},
        'failLog': [for (final f in _failLog) [f.$1, f.$2]],
        'view': _view.index,
        'levelViolation': _levelViolation,
        'serial': _serial,
        'lab': {
          'published': _cr!.published?.toJson(),
          'pending': _cr!.pending?.toJson(),
          'publishAt': _cr!.publishAt.isFinite ? _cr!.publishAt : null,
          'nextSample': _cr!.nextSample,
        },
        'monitor': {
          'nextCheck': _cr!.nextCheck,
          'steadyCount': _steadyCount,
          'steady': _steady,
          'residual': _residual.isFinite ? _residual : null,
        },
      };

  void _crudeRestore(Map<String, Object?> saved) {
    final lv = (saved['levers']! as Map<String, Object?>);
    final col = _col;
    col.inp.crudeRate = (lv['crudeRate']! as num).toDouble();
    col.inp.pTop = (lv['pTop']! as num).toDouble();
    col.inp.drumT = (lv['drumTSp']! as num).toDouble();
    if (saved['faults'] != null) _faults.loadJson(saved['faults']! as Map<String, Object?>);
    _crudeLoadDynamic(saved['dynamic']! as Map<String, Object?>);
    _carry = (saved['carry']! as num).toDouble();
    _view = SimView.values[(saved['view']! as num).toInt()];
    _levelViolation = (saved['levelViolation']! as num).toDouble();
    _serial = (saved['serial']! as num).toInt();
    final lab = saved['lab'] as Map<String, Object?>?;
    if (lab != null) {
      final r = _cr!;
      r.published = lab['published'] == null ? r.published : _CrudeLab.fromJson(lab['published']! as Map<String, Object?>);
      r.pending = lab['pending'] == null ? null : _CrudeLab.fromJson(lab['pending']! as Map<String, Object?>);
      r.publishAt = (lab['publishAt'] as num?)?.toDouble() ?? double.infinity;
      r.nextSample = (lab['nextSample']! as num).toDouble();
    }
    final m = saved['monitor']! as Map<String, Object?>;
    _cr!.nextCheck = (m['nextCheck']! as num).toDouble();
    _steadyCount = (m['steadyCount']! as num).toInt();
    _steady = m['steady']! as bool;
    _residual = (m['residual'] as num?)?.toDouble() ?? double.infinity;
    _crudeCapture();
    _syncDrawSpecsIn(_levers);
    for (final f in (saved['failLog'] as List<Object?>?) ?? const []) {
      final l = f! as List<Object?>;
      _failLog.add((l[0]! as String, (l[1]! as num).toDouble()));
      _failSeen.add(l[0]! as String);
    }
    final sc = saved['scenario'] as Map<String, Object?>?;
    if (sc != null) {
      final def = ScenarioDef.fromJson(Map<String, Object?>.from(sc['def']! as Map<Object?, Object?>));
      _scenario = ScenarioRunner(def, SimulatorHost(this), restoring: true)..loadJson(sc['state']! as Map<String, Object?>);
    }
  }

  // ---------------------------------------------------------------- presets and explain
  void _crudeLoadPreset(ColumnConfig cfg) {
    final keepTime = _state.time;
    final noise = _control.noise;
    final view = _view;
    final scenario = _scenario;
    _scenario = null;
    _pinDrum = null;
    _build(cfg, null);
    if (_cr != null) {
      _control.setNoise(false);
      _crudeResetNoisy();
      _crudeWarmStart();
      _crudeAfterSteady(keepTime);
      _view = view;
      _crudeSetNoise(noise);
      _scenario = scenario;
    } else {
      _applyWarmStart();
      _state.time = keepTime;
      _scenario = scenario;
    }
    _emit(SimEventType.rebuildDone, 'Loaded preset ${cfg.presetId}');
  }

  ExplainResult _crudeExplain(ExplainTarget target) =>
      ExplainResult(title: 'Not available', groups: const [], notes: const ['Crude equation traces: see ExplainCrude.'], time: _state.time);

  // ---------------------------------------------------------------- scenarios
  static final Map<String, Map<String, Object?>> _crudeScenarioCache = {};

  void _crudeStartScenario(ScenarioDef def, int? seed) {
    _scenario = null;
    _seed = seed ?? options.seed;
    _failLog.clear();
    _failSeen.clear();
    _view = SimView.model;
    _pinDrum = null;
    _build(def.buildConfig(), null);
    _control.setNoise(false);
    _crudeResetNoisy();
    for (final e in def.leverSet.entries) {
      setLever(e.key, e.value);
    }
    if (def.start == 'steady') {
      final key = jsonEncode([_config.toJson(), def.leverSet, 'crudeScenario']);
      final cached = _crudeScenarioCache[key];
      if (cached != null) {
        _crudeLoadDynamic(cached);
      } else {
        runToSteadyState(maxSimSeconds: 172800);
        _crudeScenarioCache[key] = _crudeDumpDynamic(includeTrends: false);
      }
      _crudeAfterSteady(0);
    }
    _control.setNoise(false);
    _control.reseed(_seed);
    _crudeInitControl();
    _levelViolation = 0;
    final tags = def.loops.keys.toList()..sort();
    for (final tag in tags) {
      final cfg = def.loops[tag]!;
      final mode = cfg['mode'] as String?;
      if (mode != null) _control.setMode(tag, LoopMode.values.firstWhere((m) => m.name == mode));
      if (cfg['sp'] != null) _control.setSp(tag, (cfg['sp']! as num).toDouble());
      if (cfg['op'] != null) _control.setOp(tag, (cfg['op']! as num).toDouble());
    }
    _control.badPvShed = def.badPvShed;
    _view = switch (def.view) {
      'plant' => SimView.plant,
      'plantCalc' => SimView.plantCalc,
      _ => SimView.model,
    };
    _crudeSetNoise(def.noise);
    _crudeResetMonitor(capture: true);
    if (_control.noise) _crudeResetNoisy();
    _crudeInitLab();
    _scenario = ScenarioRunner(def, SimulatorHost(this));
    _scenario!.update();
  }
}
