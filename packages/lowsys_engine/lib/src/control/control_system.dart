import 'dart:math' as math;
import 'dart:typed_data';

import '../core/ids.dart';
import '../core/quantity.dart';
import '../faults/fault_manager.dart';
import '../faults/fault_spec.dart';
import '../snapshot/sim_snapshot.dart' show AlarmPriority;
import 'alarms.dart';
import 'instrument.dart';
import 'pid.dart';
import 'trend_buffer.dart';
import 'valve.dart';

export 'instrument.dart';
export 'pid.dart';
export 'valve.dart';

/// True values the instruments measure at the end of a main step (ENGINE_API.md 10 `MeasurementBus`).
class MeasurementBus {
  double drumLevelPct = 0;
  double sumpLevelPct = 0;

  /// Pa; zero with ideal hydraulics.
  double columnDp = 0;

  /// Light-component mole fractions: feed (effective), distillate, bottoms.
  double feedLight = 0.5, xD = 0.98, xB = 0.02;

  /// Tier 2 true values (M4): top pressure (Pa), steam header gauge pressure (Pa), reflux temperature, CW inlet and
  /// outlet temperatures (K), CW volume flow (m3/s) and the stage temperatures (K).
  double pTop = 101325, steamGauge = 350000, tRefl = 350;
  double cwIn = 303.15, cwOut = 318, cwVol = 0;
  Float64List stageT = Float64List(0);

  double read(String ref) => switch (ref) {
        'drum.levelPct' => drumLevelPct,
        'sump.levelPct' => sumpLevelPct,
        'columnDp' => columnDp,
        'stream.feed.x[0]' => feedLight,
        'stream.distillate.heavy' => 1 - xD,
        'stream.bottoms.x[0]' => xB,
        'pTop' => pTop,
        'steamGauge' => steamGauge,
        'refluxT' => tRefl,
        'cwIn' => cwIn,
        'cwOut' => cwOut,
        'cwVol' => cwVol,
        _ => _stage(ref),
      };

  double _stage(String ref) {
    if (ref.startsWith('stage.T[')) {
      final j = int.parse(ref.substring(8, ref.length - 1));
      return stageT[j];
    }
    throw ArgumentError('Unknown measurement $ref');
  }
}

/// Design numbers the B-T Tier 1 control system is built from (SI, mol/s).
class ControlDesign {
  final double feedFlow, refluxFlow, boilup, distillate, bottoms;
  final double dMax, bMax;
  final double drumLevelSp, sumpLevelSp;
  final double levelKc, levelTi;

  /// Tier 2 data (M4): design top pressure (Pa), CW capacity (kg/s), initial duty (W) and the clean steam-valve
  /// scale Q_max,0 (W), tray count, instrumented trays, the TC-101 tray and the PC-101 set point (Pa).
  final double pTopDesign, cwMaxFlow, dutyDesign, qMax0, cwDesign;
  final int nTrays, tc101Tray;
  /// Partial condenser (PHYSICS.md 7.2, 10.7): PC-101 drives the vapour-product valve PV-102 (full scale [dvMax] mol/s,
  /// start OP [dvOp] %) and the CW valve sits at [cwManualOp] %.
  final bool partial;
  final double dvMax, dvOp, cwManualOp;
  final List<int> trays;
  const ControlDesign({
    this.partial = false,
    this.dvMax = 0,
    this.dvOp = 20,
    this.cwManualOp = 30,
    this.pTopDesign = 101325,
    this.cwMaxFlow = 41.54,
    this.dutyDesign = 1.3e6,
    this.qMax0 = 2.17e6,
    this.cwDesign = 50,
    this.nTrays = 20,
    this.tc101Tray = 14,
    this.trays = const [1, 4, 7, 10, 12, 14, 17, 20],
    required this.feedFlow,
    required this.refluxFlow,
    required this.boilup,
    required this.distillate,
    required this.bottoms,
    required this.dMax,
    required this.bMax,
    this.drumLevelSp = 50,
    this.sumpLevelSp = 50,
    this.levelKc = 2.0,
    this.levelTi = 1800,
  });
}

const double _kmolh = 1000 / 3600;

/// Valves, instruments, loops and alarms of the B-T Tier 1 preset (PHYSICS.md 10.1-10.8).
class ControlSystem {
  static const double deltaC = 0.1;

  final int seed;
  final List<ControlLoop> loops;
  final List<Instrument> instruments;
  final List<Valve> valves;
  final AlarmManager alarms = AlarmManager();
  TrendBuffer? trends;

  bool noise = false;

  /// 1: loops with a BAD PV drop to MAN (default), 0: they keep executing on the failure value.
  bool badPvShed = true;

  /// FC-102 ratio station.
  bool ratioMode = false;
  double ratio = 2.0;
  double _lastGoodRatioSp = 0;

  // convenience handles
  late final Valve fv101, fv102, fv103, lv101, lv102;
  late final Instrument ft101,
      ft102,
      ft103,
      ft104,
      ft105,
      lt101,
      lt102,
      pdt101,
      at100,
      at101,
      at102;
  late final ControlLoop fc101, fc102, fc103, lc101, lc102;

  // ---- Tier 2 (M4): pressure, temperatures, cooling water, steam header; PC-101 and TC-101
  /// PC-101's valve: PV-101 (cooling water) with a total condenser, PV-102 (vapour product, mol/s) with a partial one;
  /// [cwValve] is always the cooling-water valve (the same object as [pv101] when the condenser is total).
  late Valve pv101, cwValve;
  bool partial = false;
  double cwManualOp = 30, meanDv = 0;
  late Instrument pt101, pt201, ti100, ti201, ti202, ft201, tiSump;
  final List<Instrument> trayTis = [];
  final List<int> trayIds = [];
  late ControlLoop pc101, tc101;

  /// True once Tier 2 is active: the Tier-2-only instruments, loops and valves are visible and updated.
  bool tier2 = false;

  /// TC-101 enabled by the operator (lever `tc101Enable`); its mode follows FC-103 (IMAN when FC-103 is not in CAS).
  bool tc101Enabled = false;

  /// Design P_top (Pa) for alarms, the density of the CW (kg/m3) for FT-201, and the T2 flags set by the stepper.
  double pDesign = 101325;
  static const double rhoWater = 995.0;
  bool modelRelief = false, modelDutyLimited = false;

  /// PC-101 gain schedule: Kc is scaled by OP / [pcScheduleOp] below that opening (never below [pcScheduleMin]).
  static const double pcScheduleOp = 35.0, pcScheduleMin = 0.1;

  /// F09 capacity factor on the CW flow and the mean CW mass flow (kg/s) of the last fast layer.
  double cwScale = 1, meanCw = 0;

  /// Instruments of the Tier-2 set in the order of the snapshot.
  List<Instrument> get t2Instruments => [
        pt101,
        pt201,
        ti100,
        ...trayTis,
        tiSump,
        ti201,
        ti202,
        ft201,
      ];

  /// The instruments, loops and valves the learner sees in the current tier.
  Iterable<Instrument> get visibleInstruments sync* {
    for (final i in instruments) {
      if (!i.hidden) yield i;
    }
  }

  Iterable<ControlLoop> get visibleLoops sync* {
    for (final l in loops) {
      if (!l.hidden) yield l;
    }
  }

  Iterable<Valve> get visibleValves sync* {
    for (final v in valves) {
      if (!v.hidden) yield v;
    }
  }

  final Map<String, Instrument> _inst = {};
  final Map<String, ControlLoop> _loops = {};
  final Map<String, Valve> _valves = {};

  // trend series indices
  final Map<String, int> _tix = {};
  // trend series indices cached per object (the string keys would be rebuilt on every push)
  final Map<Instrument, int> _pvIx = {};
  List<int> _opIx = const [], _spIx = const [], _posIx = const [];

  // true values the alarms and models need (set by the simulator)
  /// True with full hydraulics; PDT-101 reads zero (bottom of its span) otherwise, so it raises no OOR.
  bool modelFull = false;
  bool modelFlood = false, modelWeep = false, modelDc = false;

  /// Last mean flows of the fast layer (mol/s): feed, reflux, boilup, distillate, bottoms.
  final Float64List meanFlows = Float64List(5);

  /// Moles per 1 % of drum and sump level at the design state (PHYSICS.md 14.6: C1, C3, C5).
  double n01 = 307, ns1 = 236;

  /// Sim time (s) of the last control action, used for journal entries.
  double time = 0;

  /// Called when a maintenance period ends, with the tag (the simulator clears the faults on it).
  void Function(String tag)? onMaintenanceDone;

  /// Fast-layer trace for tests: when non-null every sub-step appends one [FastPoint].
  FastTrace? fastTrace;

  ControlSystem._(this.seed, this.loops, this.instruments, this.valves);

  /// Builds the B-T Tier 1 control system at its design flows. The loops and valves start in AUTO at the OPs
  /// that give the design flows, instruments start at the true values (PHYSICS.md 10.4 initialisation).
  factory ControlSystem.bt(ControlDesign d, int seed) {
    Valve valve(String id, double fMax, double flow) =>
        Valve(id, fMax, seed, op: fMax > 0 ? 100 * flow / fMax : 0);
    final fv101 = valve('FV-101', 250 * _kmolh, d.feedFlow);
    final fv102 = valve('FV-102', 300 * _kmolh, d.refluxFlow);
    final fv103 = valve('FV-103', 300 * _kmolh, d.boilup);
    final lv101 = valve('LV-101', d.dMax, d.distillate);
    final lv102 = valve('LV-102', d.bMax, d.bottoms);

    Instrument ft(String tag, double hiKmolh) => Instrument(
        InstrumentSpec(
          tag: tag,
          type: InstrumentType.ftLiquid,
          measures: 'valve.flow',
          quantity: Quantity.molarFlow,
          lo: 0,
          hi: hiKmolh * _kmolh,
          tauM: 0.5,
          sigmaS: 0.50,
          tauS: 1,
          sigmaE: 0.02,
          resolution: 0.1 * _kmolh,
        ),
        seed: seed);
    Instrument lt(String tag, InstrumentType ty, double sigmaS, double tauS) =>
        Instrument(
            InstrumentSpec(
              tag: tag,
              type: ty,
              measures: ty == InstrumentType.ltDrum
                  ? 'drum.levelPct'
                  : 'sump.levelPct',
              quantity: Quantity.percent,
              lo: 0,
              hi: 100,
              tauM: 2,
              sigmaS: sigmaS,
              tauS: tauS,
              sigmaE: 0.02,
              resolution: 0.1,
            ),
            seed: seed);
    Instrument at(String tag, String measures, double hi, double phase) =>
        Instrument(
            InstrumentSpec(
              tag: tag,
              type: InstrumentType.at,
              measures: measures,
              quantity: Quantity.fraction,
              lo: 0,
              hi: hi,
              tauM: 0,
              sigmaS: 0,
              tauS: 1,
              sigmaE: 0.5,
              analyserPhase: phase,
              resolution: 1e-4,
            ),
            seed: seed);
    final ft101 = ft('FT-101', 250),
        ft102 = ft('FT-102', 300),
        ft103 = ft('FT-103', 300),
        ft104 = ft('FT-104', 100),
        ft105 = ft('FT-105', 100);
    final lt101 = lt('LT-101', InstrumentType.ltDrum, 0.5, 5);
    final lt102 = lt('LT-102', InstrumentType.ltSump, 1.0, 3);
    final pdt101 = Instrument(
        InstrumentSpec(
          tag: 'PDT-101',
          type: InstrumentType.pdt,
          measures: 'columnDp',
          quantity: Quantity.pressureDelta,
          lo: 0,
          hi: 40000,
          tauM: 2,
          sigmaS: 1.0,
          tauS: 5,
          sigmaE: 0.02,
          resolution: 10,
        ),
        seed: seed);
    final at100 = at('AT-100', 'stream.feed.x[0]', 1.0, 0);
    final at101 = at('AT-101', 'stream.distillate.heavy', 0.10, 100);
    final at102 = at('AT-102', 'stream.bottoms.x[0]', 0.10, 200);
    final insts = [
      ft101,
      ft102,
      ft103,
      ft104,
      ft105,
      lt101,
      lt102,
      pdt101,
      at100,
      at101,
      at102
    ];

    ControlLoop fc(
            String tag, Instrument pv, Valve v, double sp, double spHi) =>
        ControlLoop(
          tag: tag,
          pvTag: pv.spec.tag,
          mvRef: v.id,
          params: const PidParams(
              kc: 0.6, ti: 2.0, action: Action.reverse, spKick: true),
          fastLayer: true,
          lo: pv.spec.lo,
          hi: pv.spec.hi,
          spLo: 0,
          spHi: spHi,
          sp: sp,
          op: v.position,
        );
    ControlLoop lc(String tag, Instrument pv, Valve v, double sp) =>
        ControlLoop(
          tag: tag,
          pvTag: pv.spec.tag,
          mvRef: v.id,
          params: PidParams(
              kc: d.levelKc,
              ti: d.levelTi,
              action: Action.direct,
              spKick: false),
          fastLayer: false,
          lo: 0,
          hi: 100,
          spLo: 10,
          spHi: 90,
          sp: sp,
          op: v.position,
        );
    final fc101 = fc('FC-101', ft101, fv101, d.feedFlow, 250 * _kmolh);
    final fc102 = fc('FC-102', ft102, fv102, d.refluxFlow, 300 * _kmolh);
    final fc103 = fc('FC-103', ft103, fv103, d.boilup, 300 * _kmolh);
    final lc101 = lc('LC-101', lt101, lv101, d.drumLevelSp);
    final lc102 = lc('LC-102', lt102, lv102, d.sumpLevelSp);
    // FT-104 and FT-105 are moved by the level loops acting on the level noise: sigma_typ = sqrt(sigma_disp^2 + (Kc sigma_LT F_max/span)^2)
    for (final (ft, lt, v) in [(ft104, lt101, lv101), (ft105, lt102, lv102)]) {
      final g = d.levelKc * lt.spec.sigmaDisp * v.fMax / (ft.spec.hi - ft.spec.lo);
      ft.typicalPct = math.sqrt(ft.spec.sigmaDisp * ft.spec.sigmaDisp + g * g);
    }
    // ---- Tier 2 additions (M4): PT/TI/FT-201 instruments, PV-101, PC-101 and TC-101 (PHYSICS.md 10.1, 10.5, 10.7)
    final pDes = d.pTopDesign;
    Instrument pt(String tag, String measures, double hi, Quantity q,
            double res) =>
        Instrument(
            InstrumentSpec(
              tag: tag,
              type: InstrumentType.pt,
              measures: measures,
              quantity: q,
              lo: 0,
              hi: hi,
              tauM: 1,
              sigmaS: 0.05,
              tauS: 2,
              sigmaE: 0.02,
              resolution: res,
            ),
            seed: seed);
    Instrument ti(String tag, String measures, InstrumentType ty, double sigS,
            double sigE) =>
        Instrument(
            InstrumentSpec(
              tag: tag,
              type: ty,
              measures: measures,
              quantity: Quantity.temperature,
              lo: 273.15,
              hi: 473.15,
              tauM: 10,
              sigmaS: sigS,
              tauS: 20,
              sigmaE: sigE,
              resolution: 0.1,
            ),
            seed: seed);
    final pt101 = pt('PT-101', 'pTop', 2 * pDes, Quantity.pressure, 10);
    final pt201 =
        pt('PT-201', 'steamGauge', 1e6, Quantity.pressureDelta, 100);
    final ti100 = ti('TI-100', 'refluxT', InstrumentType.tiLine, 0.025, 0.01);
    final ti201 = ti('TI-201', 'cwIn', InstrumentType.tiLine, 0.025, 0.01);
    final ti202 = ti('TI-202', 'cwOut', InstrumentType.tiLine, 0.025, 0.01);
    final trayTis = [
      for (final j in d.trays)
        ti('TI-${100 + j}', 'stage.T[$j]', InstrumentType.tiTray, 0.075, 0.01)
    ];
    final tiSump = ti('TI-${100 + d.nTrays + 1}', 'stage.T[${d.nTrays + 1}]',
        InstrumentType.tiTray, 0.075, 0.01);
    final ft201 = Instrument(
        InstrumentSpec(
          tag: 'FT-201',
          type: InstrumentType.ftWater,
          measures: 'cwVol',
          quantity: Quantity.volumeFlowLiquid,
          lo: 0,
          hi: 150 / 3600,
          tauM: 0.5,
          sigmaS: 0.30,
          tauS: 1,
          sigmaE: 0.02,
          resolution: 0.1 / 3600,
        ),
        seed: seed);
    final t2insts = [pt101, pt201, ti100, ...trayTis, tiSump, ti201, ti202, ft201];
    final cwValve = Valve('PV-101', d.cwMaxFlow, seed,
        op: d.partial ? d.cwManualOp : d.cwDesign);
    final pv101 = d.partial
        ? Valve('PV-102', d.dvMax, seed, op: d.dvOp)
        : cwValve;
    final pc101 = ControlLoop(
      tag: 'PC-101',
      pvTag: 'PT-101',
      mvRef: pv101.id,
      params: d.partial
          ? const PidParams(kc: 2.0, ti: 30, action: Action.direct, spKick: false)
          : const PidParams(
              kc: 10, ti: 120, action: Action.direct, spKick: false),
      fastLayer: false,
      lo: 0,
      hi: 2 * pDes,
      spLo: 20000,
      spHi: 500000,
      sp: pDes,
      op: d.partial ? d.dvOp : d.cwDesign,
    );
    final tcTray = d.trays.contains(d.tc101Tray) ? d.tc101Tray : d.trays.first;
    final tc101 = ControlLoop(
      tag: 'TC-101',
      pvTag: 'TI-${100 + tcTray}',
      mvRef: 'FC-103.sp',
      params: const PidParams(
          kc: 4.0,
          ti: 900,
          action: Action.reverse,
          spKick: false,
          opLo: 20,
          opHi: 65),
      fastLayer: false,
      lo: 273.15,
      hi: 473.15,
      spLo: 273.15,
      spHi: 473.15,
      sp: 365,
      op: 40,
      mode: LoopMode.man,
    );
    for (final i in t2insts) {
      i.hidden = true;
    }
    pv101.hidden = true;
    pc101.hidden = true;
    tc101.hidden = true;
    insts.addAll(t2insts);
    final cs = ControlSystem._(
        seed,
        [fc101, fc102, fc103, lc101, lc102, pc101, tc101],
        insts,
        [fv101, fv102, fv103, lv101, lv102, pv101]);
    cs
      ..pv101 = pv101
      ..cwValve = cwValve
      ..partial = d.partial
      ..cwManualOp = d.cwManualOp
      ..pt101 = pt101
      ..pt201 = pt201
      ..ti100 = ti100
      ..ti201 = ti201
      ..ti202 = ti202
      ..ft201 = ft201
      ..tiSump = tiSump
      ..pc101 = pc101
      ..tc101 = tc101
      ..pDesign = pDes;
    cs.trayTis.addAll(trayTis);
    cs.trayIds.addAll(d.trays);
    cs.trayCount = d.nTrays;
    cs
      ..fv101 = fv101
      ..fv102 = fv102
      ..fv103 = fv103
      ..lv101 = lv101
      ..lv102 = lv102
      ..ft101 = ft101
      ..ft102 = ft102
      ..ft103 = ft103
      ..ft104 = ft104
      ..ft105 = ft105
      ..lt101 = lt101
      ..lt102 = lt102
      ..pdt101 = pdt101
      ..at100 = at100
      ..at101 = at101
      ..at102 = at102
      ..fc101 = fc101
      ..fc102 = fc102
      ..fc103 = fc103
      ..lc101 = lc101
      ..lc102 = lc102;
    for (final i in insts) {
      cs._inst[i.spec.tag] = i;
    }
    for (final l in cs.loops) {
      cs._loops[l.tag] = l;
      cs._inst[l.pvTag]!.loopTag = l.tag;
    }
    for (final v in cs.valves) {
      cs._valves[v.id] = v;
    }
    cs._buildAlarms();
    return cs;
  }

  Instrument instrument(String tag) =>
      _inst[tag] ?? (throw ArgumentError('No instrument $tag'));
  bool hasInstrument(String tag) => _inst.containsKey(tag);
  Valve valve(String id) =>
      _valves[id] ?? (throw ArgumentError('No valve $id'));
  bool hasValve(String id) => _valves.containsKey(id);
  ControlLoop loop(LoopTag tag) =>
      _loops[tag] ?? (throw ArgumentError('No loop $tag'));

  /// The valve a loop drives.
  Valve valveOf(ControlLoop l) => _valves[l.mvRef]!;

  /// Starts every instrument at the true values and the loop histories at the PV (PHYSICS.md 13.1 step 6).
  void initialise(MeasurementBus bus, double t) {
    meanFlows[0] = fv101.flow;
    ft101.reset(fv101.fMax * fv101.g(fv101.position), t);
    ft102.reset(fv102.fMax * fv102.g(fv102.position), t);
    ft103.reset(fv103.fMax * fv103.g(fv103.position), t);
    ft104.reset(lv101.fMax * lv101.g(lv101.position), t);
    ft105.reset(lv102.fMax * lv102.g(lv102.position), t);
    lt101.reset(bus.drumLevelPct, t);
    lt102.reset(bus.sumpLevelPct, t);
    pdt101.reset(bus.columnDp, t);
    at100.reset(bus.feedLight, t);
    at101.reset(1 - bus.xD, t);
    at102.reset(bus.xB, t);
    if (tier2) _resetT2Instruments(bus, t);
    for (final l in loops) {
      l.initHistory(_inst[l.pvTag]!.value);
    }
    _lastGoodRatioSp = fc102.sp;
  }

  // ---------------------------------------------------------------- trends

  void attachTrends(TrendBuffer tb) {
    trends = tb;
    for (final i in instruments) {
      _tix['PV:${i.spec.tag}'] = tb.register('PV:${i.spec.tag}');
      _pvIx[i] = _tix['PV:${i.spec.tag}']!;
    }
    for (final l in loops) {
      _tix['OP:${l.tag}'] = tb.register('OP:${l.tag}');
      _tix['SP:${l.tag}'] = tb.register('SP:${l.tag}');
    }
    for (final v in valves) {
      _tix['POS:${v.id}'] = tb.register('POS:${v.id}');
    }
    for (final m in [
      'model.xD',
      'model.xB',
      'model.dp',
      'model.flood',
      'model.drum',
      'model.sump'
    ]) {
      _tix[m] = tb.register(m);
    }
  }

  void pushModel(
      double xD, double xB, double dp, double flood, double drum, double sump) {
    final tb = trends;
    if (tb == null) return;
    tb.push(_tix['model.xD']!, xD);
    tb.push(_tix['model.xB']!, xB);
    tb.push(_tix['model.dp']!, dp);
    tb.push(_tix['model.flood']!, flood);
    tb.push(_tix['model.drum']!, drum);
    tb.push(_tix['model.sump']!, sump);
  }

  void _pushInstrument(Instrument i) {
    final tb = trends;
    if (tb == null) return;
    tb.push(_pvIx[i]!, i.value, i.quality.index);
  }

  void _pushLoops() {
    final tb = trends;
    if (tb == null) return;
    if (_opIx.isEmpty) {
      _opIx = [for (final l in loops) _tix['OP:${l.tag}']!];
      _spIx = [for (final l in loops) _tix['SP:${l.tag}']!];
      _posIx = [for (final v in valves) _tix['POS:${v.id}']!];
    }
    for (var k = 0; k < loops.length; k++) {
      tb.push(_opIx[k], loops[k].op);
      tb.push(_spIx[k], loops[k].sp);
    }
    for (var k = 0; k < valves.length; k++) {
      tb.push(_posIx[k], valves[k].position);
    }
  }

  // ---------------------------------------------------------------- operator actions

  /// Mode change, bumpless per PHYSICS.md 10.2. Throws StateError for AUTO/CAS on a BAD PV and for IMAN.
  void setMode(LoopTag tag, LoopMode mode) {
    final l = loop(tag);
    if (mode == LoopMode.iman) throw StateError('IMAN is engine-internal');
    final inst = _inst[l.pvTag]!;
    if (mode == LoopMode.cas && !(tag == 'FC-103' && tc101Enabled)) {
      throw StateError('$tag has no master loop in this configuration');
    }
    if (mode == LoopMode.auto &&
        (inst.quality == Quality.bad || inst.quality == Quality.oos)) {
      throw StateError('Cannot select AUTO on a BAD PV (${l.pvTag})');
    }
    if (mode == l.mode) return;
    if (mode == LoopMode.auto) {
      l.trackPv(inst.value);
      l.shed = false;
    }
    l.mode = mode;
    l.requestedMode = mode;
    alarms.log(time, 'MODE $tag ${mode.name.toUpperCase()}');
  }

  void setSp(LoopTag tag, double sp) {
    final l = loop(tag);
    l.setSp(sp);
    if (tag == 'PC-101' && tier2) setPtSpan();
  }

  void setOp(LoopTag tag, double op) {
    final l = loop(tag);
    if (l.mode != LoopMode.man)
      throw StateError('OP can only be set in MAN ($tag is ${l.mode.name})');
    l.setOp(op);
  }

  void setNoise(bool on) {
    if (on != noise) {
      for (final i in instruments) {
        i.resetNoise();
        i.noise = on;
      }
      for (final v in valves) {
        v.resetNoise();
      }
      if (partial) cwValve.resetNoise();
    }
    noise = on;
  }

  /// Re-keys every random stream from [seed] (after a warm start loaded from a cache made with another seed).
  void reseed(int seed) {
    for (final i in instruments) {
      i.reseed(seed);
    }
    for (final v in valves) {
      v.reseed(seed);
    }
    if (partial) cwValve.reseed(seed);
  }

  /// Applies the active F19/F28/F20 faults to the instruments and valves (called at the start of a step).
  void applyFaults(Iterable<FaultSpec> specs) {
    for (final i in instruments) {
      i.fault = null;
    }
    for (final v in valves) {
      v.fault = ValveFault.none;
    }
    for (final s in specs) {
      final tag = s.location.tagName;
      if (tag == null) continue;
      if (s.type == FaultType.instrument || s.type == FaultType.transmitter) {
        final inst = _inst[tag];
        if (inst == null) continue;
        final kind = InstrumentFaultKind.values
            .firstWhere((e) => e.name == (s.params['kind'] ?? 'bias'));
        final sg = s.params['sign'];
        final sign = sg is num && sg < 0 ? -1.0 : 1.0;
        inst.fault = InstrumentFault(kind, sign, s.severity, s.onset, s.ramp);
      } else if (s.type == FaultType.valve) {
        final v = _valves[tag];
        if (v == null || FaultManager.severityAt(s, time) <= 0) continue;
        v.fault = switch (s.params['kind'] as String? ?? 'stuck') {
          'failOpen' => ValveFault.failOpen,
          'failClosed' => ValveFault.failClosed,
          _ => ValveFault.stuck,
        };
      }
    }
  }

  /// Validates an F19/F28/F20 fault before it is accepted (ConfigException on a mismatch).
  void validateFault(FaultSpec s) {
    final tag = s.location.tagName;
    if (tag == null) throw ConfigException('Fault needs a tag location');
    if (s.type == FaultType.valve) {
      if (!_valves.containsKey(tag)) throw ConfigException('No valve $tag');
      final k = s.params['kind'];
      if (k != 'stuck' && k != 'failOpen' && k != 'failClosed')
        throw ConfigException('Unknown valve fault kind $k');
      return;
    }
    final inst = _inst[tag];
    if (inst == null) throw ConfigException('No instrument $tag');
    final kindName = (s.params['kind'] as String?) ?? '';
    final kind = InstrumentFaultKind.values.where((e) => e.name == kindName);
    if (kind.isEmpty)
      throw ConfigException('Unknown instrument fault kind "$kindName"');
    final k = kind.first;
    final f19 = k == InstrumentFaultKind.bias ||
        k == InstrumentFaultKind.drift ||
        k == InstrumentFaultKind.stuck;
    if ((s.type == FaultType.instrument) != f19)
      throw ConfigException(
          'Fault kind $kindName does not match type ${s.type.name}');
    final at = inst.spec.isAnalyser;
    final ft = inst.spec.type == InstrumentType.ftLiquid ||
        inst.spec.type == InstrumentType.ftSteam ||
        inst.spec.type == InstrumentType.ftWater;
    final lt = inst.spec.type == InstrumentType.ltDrum ||
        inst.spec.type == InstrumentType.ltSump;
    final ok = switch (k) {
      InstrumentFaultKind.bias ||
      InstrumentFaultKind.drift ||
      InstrumentFaultKind.stuck =>
        true,
      InstrumentFaultKind.signalLossLow ||
      InstrumentFaultKind.signalLossHigh =>
        !at,
      InstrumentFaultKind.signalLoss => at,
      InstrumentFaultKind.plugged => ft ||
          lt ||
          at ||
          inst.spec.type == InstrumentType.pdt ||
          inst.spec.type == InstrumentType.pt,
      InstrumentFaultKind.spiking => !at,
      InstrumentFaultKind.coated => inst.spec.type == InstrumentType.tiTray ||
          inst.spec.type == InstrumentType.tiLine,
    };
    if (!ok)
      throw ConfigException('Fault kind $kindName does not apply to $tag');
    if ((k == InstrumentFaultKind.bias || k == InstrumentFaultKind.drift) &&
        s.params['sign'] == null) {
      throw ConfigException('bias and drift need params.sign');
    }
  }

  // ---------------------------------------------------------------- fast layer

  /// PHYSICS.md 10.1 fast layer: n_c sub-steps of 0.1 s from time [t]. The mean valve flows over the sub-steps
  /// go to [meanFlows] (feed, reflux, boilup, distillate, bottoms).
  void runFastLayer(double dt, double t) {
    time = t;
    final nc = math.max(1, (dt / deltaC).round());
    var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, sCw = 0.0, sDv = 0.0;
    for (var k = 0; k < nc; k++) {
      final tk = t + k * deltaC;
      // 1. valves in the fixed order, then the transmitter on each line
      final f0 = fv101.step(deltaC, fc101.op, noise);
      ft101.update(deltaC, f0, tk);
      final f1 = fv102.step(deltaC, fc102.op, noise);
      ft102.update(deltaC, f1, tk);
      final f2 = fv103.step(deltaC, fc103.op, noise);
      ft103.update(deltaC, f2, tk);
      final f3 = lv101.step(deltaC, lc101.op, noise);
      ft104.update(deltaC, f3, tk);
      final f4 = lv102.step(deltaC, lc102.op, noise);
      ft105.update(deltaC, f4, tk);
      s0 += f0;
      s1 += f1;
      s2 += f2;
      s3 += f3;
      s4 += f4;
      if (tier2) {
        final fcw = partial
            ? cwValve.step(deltaC, cwManualOp, noise) * cwScale
            : pv101.step(deltaC, pc101.op, noise) * cwScale;
        if (partial) sDv += pv101.step(deltaC, pc101.op, noise);
        ft201.update(deltaC, fcw / rhoWater, tk);
        sCw += fcw;
      }
      // 2. flow loops in tag order: ratio station, then PID
      if (ratioMode && fc102.mode != LoopMode.man) {
        if (ft104.quality == Quality.good ||
            ft104.quality == Quality.uncertain) {
          _lastGoodRatioSp = ratio * ft104.value;
        }
        fc102.setSpCascade(_lastGoodRatioSp);
      }
      _executeLoop(fc101, deltaC, tk + deltaC);
      _executeLoop(fc102, deltaC, tk + deltaC);
      _executeLoop(fc103, deltaC, tk + deltaC);
      _pushInstrument(ft101);
      _pushInstrument(ft102);
      _pushInstrument(ft103);
      _pushInstrument(ft104);
      _pushInstrument(ft105);
      if (tier2) _pushInstrument(ft201);
      final tr = fastTrace;
      if (tr != null) {
        tr.points.add(FastPoint(
            tk + deltaC,
            [f0, f1, f2, f3, f4],
            [ft101.value, ft102.value, ft103.value, ft104.value, ft105.value],
            [fc101.op, fc102.op, fc103.op, lc101.op, lc102.op]));
      }
    }
    meanFlows[0] = s0 / nc;
    meanFlows[1] = s1 / nc;
    meanFlows[2] = s2 / nc;
    meanFlows[3] = s3 / nc;
    meanFlows[4] = s4 / nc;
    meanCw = sCw / nc;
    meanDv = sDv / nc;
  }

  void _executeLoop(ControlLoop l, double h, double t) {
    final inst = _inst[l.pvTag]!;
    final bad = inst.quality == Quality.bad || inst.quality == Quality.oos;
    final inMaint = inst.quality == Quality.oos;
    if ((l.mode == LoopMode.auto || l.mode == LoopMode.cas) &&
        bad &&
        (badPvShed || inMaint)) {
      l.mode = LoopMode.man;
      l.requestedMode = LoopMode.man;
      l.shed = true;
      alarms.journal.add(
          JournalEntry(t, 'SHED ${l.tag} to MAN (bad PV ${inst.spec.tag})'));
    }
    l.execute(inst.value, h);
  }

  // ---------------------------------------------------------------- main layer

  /// PHYSICS.md 10.1 main layer at step 12: instruments, level loops, alarms. [t] is the time at the END of the step.
  void runMainLayer(double dt, MeasurementBus bus, double t) {
    final tStart = t - dt;
    lt101.update(dt, bus.drumLevelPct, tStart);
    lt102.update(dt, bus.sumpLevelPct, tStart);
    pdt101.update(dt, bus.columnDp, tStart);
    at100.updateAnalyser(dt, bus.feedLight, t);
    at101.updateAnalyser(dt, 1 - bus.xD, t);
    at102.updateAnalyser(dt, bus.xB, t);
    for (final i in [lt101, lt102, pdt101, at100, at101, at102]) {
      _pushInstrument(i);
    }
    if (tier2) {
      pt101.update(dt, bus.pTop, tStart);
      pt201.update(dt, bus.steamGauge, tStart);
      ti100.update(dt, bus.tRefl, tStart);
      for (var k = 0; k < trayTis.length; k++) {
        trayTis[k].update(dt, bus.stageT[trayIds[k]], tStart);
      }
      tiSump.update(dt, bus.stageT[trayCount + 1], tStart);
      ti201.update(dt, bus.cwIn, tStart);
      ti202.update(dt, bus.cwOut, tStart);
      for (final i in t2Instruments) {
        if (i != ft201) _pushInstrument(i);
      }
    }
    // maintenance finished?
    for (final i in instruments) {
      if (i.oosUntil > 0 && t >= i.oosUntil) {
        i.finishMaintenance(trueValue(i, bus), t);
        alarms.log(t, 'MAINTENANCE done ${i.spec.tag}');
        onMaintenanceDone?.call(i.spec.tag);
      }
    }
    _executeLoop(lc101, dt, t);
    _executeLoop(lc102, dt, t);
    if (tier2) {
      pc101.kcScale =
          partial ? 1.0 : (pc101.op / pcScheduleOp).clamp(pcScheduleMin, 1.0);
      _executeLoop(pc101, dt, t);
      _runTc101(dt, t);
    }
    _pushLoops();
    alarms.update(dt, t);
    trends?.advance(t);
    time = t;
  }

  /// The true value an instrument measures.
  double trueValue(Instrument i, MeasurementBus bus) {
    switch (i.spec.tag) {
      case 'FT-101':
        return fv101.flow;
      case 'FT-102':
        return fv102.flow;
      case 'FT-103':
        return fv103.flow;
      case 'FT-104':
        return lv101.flow;
      case 'FT-105':
        return lv102.flow;
    }
    return bus.read(i.spec.measures);
  }

  // ---------------------------------------------------------------- Tier 2 (M4)

  /// Number of trays N (for the sump TI and the stage-temperature table).
  int trayCount = 20;

  static InstrumentSpec ft103Spec(bool t2) => InstrumentSpec(
        tag: 'FT-103',
        type: t2 ? InstrumentType.ftSteam : InstrumentType.ftLiquid,
        measures: 'valve.flow',
        quantity: t2 ? Quantity.energyRate : Quantity.molarFlow,
        lo: 0,
        hi: t2 ? 3.0e6 : 300 * _kmolh,
        tauM: 0.5,
        sigmaS: 0.50,
        tauS: 1,
        sigmaE: 0.02,
        resolution: t2 ? 100 : 0.1 * _kmolh,
      );

  void _setHidden(bool hide) {
    for (final i in t2Instruments) {
      i.hidden = hide;
    }
    pv101.hidden = hide;
    pc101.hidden = hide;
    tc101.hidden = hide;
  }

  /// Applies the tier-dependent spans and visibility without touching any state (restore from a saved state).
  void applyTier(bool t2) {
    tier2 = t2;
    _setHidden(!t2);
    ft103.applySpec(ft103Spec(t2));
    fc103.lo = 0;
    fc103.hi = ft103.spec.hi;
    fc103.spLo = 0;
    fc103.spHi = ft103.spec.hi;
    fv103.fMax = t2 ? math.max(fv103.fMax, 1.0) : 300 * _kmolh;
  }

  /// T2 <-> T3 switch with a total condenser (PHYSICS.md 13.5): puts the CW valve and PC-101's OP, bumplessly,
  /// at the position that delivers the CW flow [mcw] (kg/s, after the fault scale).
  void setCwFlowBumpless(double mcw) {
    if (partial || cwValve.fMax <= 0) return;
    final gt = (mcw / (cwValve.fMax * cwScale)).clamp(0.0, 1.0);
    final op = cwValve.characteristic == ValveCharacteristic.linear
        ? 100 * gt
        : 100 * math.log(gt * 49 + 1) / math.log(50);
    cwValve
      ..position = op
      ..command = op;
    pc101.op = op;
  }

  /// Tier 1 -> Tier 2 (PHYSICS.md 13.5): the Tier-2 objects appear at their true values; FT-103 changes quantity and
  /// FV-103's position is re-initialised so that the delivered duty [duty] (W) is continuous.
  void enterTier2(MeasurementBus bus, double t,
      {required double duty, required double qMax0}) {
    tier2 = true;
    _setHidden(false);
    ft103.retarget(ft103Spec(true), duty, t);
    fc103.lo = 0;
    fc103.hi = ft103.spec.hi;
    fc103.spLo = 0;
    fc103.spHi = ft103.spec.hi;
    fv103.fMax = math.max(qMax0, 1.0);
    fv103.init(100 * duty / fv103.fMax);
    fc103.op = fv103.position;
    fc103.sp = duty;
    fc103.initHistory(ft103.value);
    _resetT2Instruments(bus, t);
    pc101.sp = bus.pTop;
    if (!partial) {
      // PC-101 starts at the 50 % design OP (PHYSICS.md 13.5), whatever the hidden valve last held
      pv101.init(50);
    }
    pc101.op = pv101.position;
    pc101.mode = LoopMode.auto;
    pc101.requestedMode = LoopMode.auto;
    pc101.initHistory(pt101.value);
    tc101Enabled = false;
    tc101.mode = LoopMode.iman;
    tc101.requestedMode = LoopMode.auto;
    tc101.op = 100 * duty / fc103.hi;
    tc101.sp = instrument(tc101.pvTag).value;
    tc101.initHistory(instrument(tc101.pvTag).value);
    if (fc103.mode == LoopMode.cas) fc103.mode = LoopMode.auto;
  }

  void _resetT2Instruments(MeasurementBus bus, double t) {
    pt101.reset(bus.pTop, t);
    pt201.reset(bus.steamGauge, t);
    ti100.reset(bus.tRefl, t);
    for (var k = 0; k < trayTis.length; k++) {
      trayTis[k].reset(bus.stageT[trayIds[k]], t);
    }
    tiSump.reset(bus.stageT[trayCount + 1], t);
    ti201.reset(bus.cwIn, t);
    ti202.reset(bus.cwOut, t);
    ft201.reset(bus.cwVol, t);
  }

  /// Tier 2 -> Tier 1 (PHYSICS.md 13.5): FT-103 reads the boilup [boilup] (mol/s) again, FV-103 delivers it.
  void enterTier1(double t, {required double boilup}) {
    tier2 = false;
    tc101Enabled = false;
    _setHidden(true);
    ft103.retarget(ft103Spec(false), boilup, t);
    fc103.lo = 0;
    fc103.hi = ft103.spec.hi;
    fc103.spLo = 0;
    fc103.spHi = ft103.spec.hi;
    fv103.fMax = 300 * _kmolh;
    fv103.init(100 * boilup / fv103.fMax);
    fc103.op = fv103.position;
    fc103.sp = boilup;
    fc103.initHistory(ft103.value);
    if (fc103.mode == LoopMode.cas) fc103.mode = LoopMode.auto;
    tc101.mode = LoopMode.iman;
  }

  /// Lever `tc101Enable` (PHYSICS.md 10.7, VC-16.3): TC-101 becomes the master of FC-103, bumpless in both directions.
  void setTc101Enable(bool on) {
    if (!tier2 || on == tc101Enabled) return;
    tc101Enabled = on;
    final ti = instrument(tc101.pvTag);
    if (on) {
      tc101.op = 100 * (fc103.sp - fc103.lo) / (fc103.hi - fc103.lo);
      tc101.trackPv(ti.value);
      tc101.initHistory(ti.value);
      tc101.mode = tc101.requestedMode == LoopMode.man
          ? LoopMode.man
          : LoopMode.auto;
      tc101.requestedMode = tc101.mode;
      if (fc103.mode == LoopMode.auto) {
        fc103.mode = LoopMode.cas;
        fc103.requestedMode = LoopMode.cas;
      }
    } else {
      if (tc101.mode != LoopMode.iman) tc101.requestedMode = tc101.mode;
      tc101.mode = LoopMode.iman;
      if (fc103.mode == LoopMode.cas) {
        fc103.mode = LoopMode.auto;
        fc103.requestedMode = LoopMode.auto;
        fc103.spTracked = false;
      }
    }
  }

  /// Lever `tc101Tray`: only instrumented trays are offered.
  void setTc101Tray(int j) {
    if (!trayIds.contains(j)) {
      throw ArgumentError('TC-101 can only use an instrumented tray $trayIds');
    }
    _inst[tc101.pvTag]?.loopTag = null;
    tc101.pvTag = 'TI-${100 + j}';
    final ti = instrument(tc101.pvTag);
    ti.loopTag = 'TC-101';
    tc101.trackPv(ti.value);
    tc101.initHistory(ti.value);
    tc101.spTracked = false;
  }

  int get tc101Tray => int.parse(tc101.pvTag.substring(3)) - 100;

  /// PT-101 is ranged 0 to 2 x the larger of the design pressure and the set point (docs/DEVIATIONS.md E45), so
  /// that the 3 bar of G8 stays on scale; the PC-101 history is rescaled with it.
  void setPtSpan() {
    final double hiNew = 2 * math.max(pDesign, pc101.sp);
    final cur = pt101.spec;
    if ((hiNew - cur.hi).abs() < 1.0) return;
    pt101.applySpec(InstrumentSpec(
      tag: cur.tag,
      type: cur.type,
      measures: cur.measures,
      quantity: cur.quantity,
      lo: cur.lo,
      hi: hiNew,
      tauM: cur.tauM,
      sigmaS: cur.sigmaS,
      tauS: cur.tauS,
      sigmaE: cur.sigmaE,
      resolution: cur.resolution,
    ));
    pc101.rescaleSpan(pc101.lo, hiNew);
  }

  /// TC-101 in the main layer: the master runs in AUTO and cascades to FC-103; otherwise it follows (IMAN).
  void _runTc101(double dt, double t) {
    final ti = instrument(tc101.pvTag);
    final span = fc103.hi - fc103.lo;
    if (tc101Enabled && fc103.mode == LoopMode.cas) {
      if (tc101.mode == LoopMode.iman) {
        tc101.mode = tc101.requestedMode == LoopMode.man
            ? LoopMode.man
            : LoopMode.auto;
        tc101.op = 100 * (fc103.sp - fc103.lo) / span;
        tc101.trackPv(ti.value);
        tc101.initHistory(ti.value);
      }
      _executeLoop(tc101, dt, t);
      fc103.setSpCascade(fc103.lo + tc101.op / 100 * span);
    } else {
      if (tc101.mode != LoopMode.iman) {
        tc101.requestedMode = tc101.mode;
        tc101.mode = LoopMode.iman;
      }
      tc101.op = (100 * (fc103.sp - fc103.lo) / span)
          .clamp(tc101.params.opLo, tc101.params.opHi)
          .toDouble();
      tc101.trackPv(ti.value);
      tc101.lastError = 0;
    }
  }

  /// CAS-slave `delta` rule (ENGINE_API.md 11.1): a set-point step on a slave bumps the master's OP by the
  /// equivalent percentage of the slave span; the master trims from there.
  bool bumpCasSlave(LoopTag tag, double delta) {
    final l = loop(tag);
    if (tag != 'FC-103' || l.mode != LoopMode.cas || !tier2) return false;
    final span = l.hi - l.lo;
    tc101.setOp(tc101.op + 100 * delta / span);
    l.setSpCascade(l.lo + tc101.op / 100 * span);
    return true;
  }

  // ---------------------------------------------------------------- alarms

  void _buildAlarms() {
    void add(String id, AlarmPriority p, double on, double off, String msg,
            bool Function(bool) c,
            {bool ack = false}) =>
        alarms.add(AlarmDef(id, p, on, off, msg, c, needsAckToClear: ack));

    bool above(Instrument i, double limit, double db, bool active) {
      if (i.quality == Quality.bad || i.quality == Quality.oos) return false;
      return active ? i.value > limit - db : i.value > limit;
    }

    bool below(Instrument i, double limit, double db, bool active) {
      if (i.quality == Quality.bad || i.quality == Quality.oos) return false;
      return active ? i.value < limit + db : i.value < limit;
    }

    for (final lt in [lt101, lt102]) {
      final t = lt.spec.tag;
      add('$t.HIHI', AlarmPriority.high, 5, 10, '$t level very high',
          (a) => above(lt, 95, 1, a));
      add('$t.LOLO', AlarmPriority.high, 5, 10, '$t level very low',
          (a) => below(lt, 5, 1, a));
      add('$t.HI', AlarmPriority.medium, 5, 10, '$t level high',
          (a) => above(lt, 85, 1, a));
      add('$t.LO', AlarmPriority.medium, 5, 10, '$t level low',
          (a) => below(lt, 15, 1, a));
    }
    for (final ft in [ft101, ft102, ft103, ft104, ft105]) {
      final t = ft.spec.tag;
      add(
          '$t.HI',
          AlarmPriority.medium,
          5,
          10,
          '$t flow high',
          (a) => above(ft, ft.spec.lo + 0.90 * (ft.spec.hi - ft.spec.lo),
              0.01 * (ft.spec.hi - ft.spec.lo), a));
    }
    add('PT-101.HI', AlarmPriority.medium, 5, 10, 'PT-101 pressure high',
        (a) =>
            !pt101.hidden &&
            above(pt101, 1.15 * math.max(pc101.sp, 1.0),
                0.01 * pt101.span, a));
    add('PT-101.LO', AlarmPriority.medium, 5, 10, 'PT-101 pressure low',
        (a) =>
            !pt101.hidden &&
            below(pt101, 0.85 * math.max(pc101.sp, 1.0),
                0.01 * pt101.span, a));
    add('model.relief', AlarmPriority.high, 0, 30, 'Relief valve lifting',
        (a) => tier2 && modelRelief);
    add('model.dutyLimited', AlarmPriority.medium, 60, 30,
        'Reboiler duty limited by heat transfer', (a) => tier2 && modelDutyLimited);
    for (final at in [at101, at102]) {
      final t = at.spec.tag;
      add('$t.HI', AlarmPriority.medium, 5, 10, '$t impurity high',
          (a) => above(at, 0.05, 0.001, a));
    }
    for (final l in loops) {
      final limitPct = l.tag == 'PC-101'
          ? 3.0
          : l.tag == 'TC-101'
              ? 1.0
              : (l.fastLayer ? 5.0 : 10.0);
      add('${l.tag}.DEV', AlarmPriority.medium, 30, 10, '${l.tag} deviation',
          (a) {
        if (l.hidden) return false;
        if (l.mode != LoopMode.auto && l.mode != LoopMode.cas) return false;
        final dev = (l.pct(_inst[l.pvTag]!.value) - l.pct(l.sp)).abs();
        return a ? dev > 0.8 * limitPct : dev > limitPct;
      });
      add('${l.tag}.OPSAT', AlarmPriority.medium, 60, 10,
          '${l.tag} output saturated', (a) {
        if (l.hidden) return false;
        if (l.mode != LoopMode.auto && l.mode != LoopMode.cas) return false;
        final atLimit =
            l.op <= l.params.opLo + 1e-9 || l.op >= l.params.opHi - 1e-9;
        return atLimit && l.lastError.abs() > 2.0;
      });
      add(
          '${l.tag}.SHED',
          AlarmPriority.medium,
          0,
          0,
          '${l.tag} shed to MAN (bad PV)',
          (a) =>
              !l.hidden &&
              (l.shed || (a && _inst[l.pvTag]!.quality == Quality.bad)),
          ack: true);
    }
    for (final i in instruments) {
      final isLoopPv = i.loopTag != null;
      add(
          '${i.spec.tag}.BAD',
          isLoopPv ? AlarmPriority.high : AlarmPriority.medium,
          0,
          10,
          '${i.spec.tag} signal bad',
          (a) => !i.hidden && i.quality == Quality.bad);
      add(
          '${i.spec.tag}.OOR',
          AlarmPriority.low,
          5,
          10,
          '${i.spec.tag} out of range',
          (a) =>
              !i.hidden &&
              i.quality == Quality.uncertain &&
              i.qualityText != 'STALE' &&
              !(i.spec.type == InstrumentType.pdt && !modelFull));
    }
    for (final i in [at100, at101, at102]) {
      add('${i.spec.tag}.STALE', AlarmPriority.low, 0, 0,
          '${i.spec.tag} result stale', (a) => i.qualityText == 'STALE');
    }
    add('model.flood', AlarmPriority.medium, 30, 30,
        'Flooding: max flood above 90 %', (a) => modelFlood);
    add('model.weep', AlarmPriority.medium, 30, 30, 'Weeping above 30 %',
        (a) => modelWeep);
    add('model.dcLimited', AlarmPriority.low, 30, 30,
        'Downcomer backup limiting the liquid flow', (a) => modelDc);
  }

  /// Clears a SHED condition when the learner re-selects AUTO; handled in [setMode]. Called after mode changes.
  void clearShedIfAuto() {
    for (final l in loops) {
      if (l.mode == LoopMode.auto) l.shed = false;
    }
  }

  // ---------------------------------------------------------------- persistence

  Map<String, Object?> toJson({bool includeTrends = true}) => {
        'noise': noise,
        'badPvShed': badPvShed,
        'ratioMode': ratioMode,
        'ratio': ratio,
        'lastGoodRatioSp': _lastGoodRatioSp,
        'tier2': tier2,
        'tc101Enabled': tc101Enabled,
        'tc101Pv': tc101.pvTag,
        'cwScale': cwScale,
        if (partial) 'cwManualOp': cwManualOp,
        if (partial) 'cwValve': cwValve.toJson(),
        'loops': {for (final l in loops) l.tag: l.toJson()},
        'valves': {for (final v in valves) v.id: v.toJson()},
        'instruments': {for (final i in instruments) i.spec.tag: i.toJson()},
        'alarms': alarms.toJson(),
        'trends': includeTrends ? trends?.toJson() : null,
        'meanFlows': meanFlows.toList(),
        'n01': n01,
        'ns1': ns1,
      };

  void loadJson(Map<String, Object?> j) {
    noise = j['noise']! as bool;
    for (final i in instruments) {
      i.noise = noise;
    }
    badPvShed = j['badPvShed']! as bool;
    ratioMode = j['ratioMode']! as bool;
    ratio = (j['ratio']! as num).toDouble();
    _lastGoodRatioSp = (j['lastGoodRatioSp']! as num).toDouble();
    applyTier((j['tier2'] as bool?) ?? false);
    tc101Enabled = (j['tc101Enabled'] as bool?) ?? false;
    final pv = j['tc101Pv'] as String?;
    if (pv != null && _inst.containsKey(pv)) tc101.pvTag = pv;
    cwScale = (j['cwScale'] as num?)?.toDouble() ?? 1.0;
    if (partial) {
      cwManualOp = (j['cwManualOp'] as num?)?.toDouble() ?? cwManualOp;
      final cv = j['cwValve'];
      if (cv != null) cwValve.loadJson(cv as Map<String, Object?>);
    }
    // keyed by tag: the instrumented trays change with the tray count (PHYSICS.md 10.5)
    final ls = j['loops']! as Map<String, Object?>;
    for (final l in loops) {
      final m = ls[l.tag];
      if (m != null) l.loadJson(m as Map<String, Object?>);
    }
    // re-range PT-101 before its saved state (the OU noise state) is loaded, or applySpec would reset it
    if (tier2) setPtSpan();
    final vs = j['valves']! as Map<String, Object?>;
    for (final v in valves) {
      final m = vs[v.id];
      if (m != null) v.loadJson(m as Map<String, Object?>);
    }
    final ins = j['instruments']! as Map<String, Object?>;
    for (final i in instruments) {
      final m = ins[i.spec.tag];
      if (m != null) i.loadJson(m as Map<String, Object?>);
    }
    alarms.loadJson(j['alarms']! as Map<String, Object?>);
    final tr = j['trends'];
    if (tr != null && trends != null)
      trends!.loadJson(tr as Map<String, Object?>);
    final mf = j['meanFlows']! as List<Object?>;
    for (var i = 0; i < 5; i++) {
      meanFlows[i] = (mf[i]! as num).toDouble();
    }
    n01 = (j['n01']! as num).toDouble();
    ns1 = (j['ns1']! as num).toDouble();
  }
}

/// One sub-step of the fast layer, for tests (VALIDATION.md VC-16.4): [time] is the sim time at the END of the
/// sub-step; flows are the true valve flows (mol/s), readings the transmitter values (SI), ops the loop outputs (%).
class FastPoint {
  final double time;
  final List<double> _flows, _readings, _ops;
  const FastPoint(this.time, this._flows, this._readings, this._ops);
  static const _valves = ['FV-101', 'FV-102', 'FV-103', 'LV-101', 'LV-102'];
  static const _tags = ['FT-101', 'FT-102', 'FT-103', 'FT-104', 'FT-105'];
  static const _loops = ['FC-101', 'FC-102', 'FC-103', 'LC-101', 'LC-102'];
  double flow(String valveId) => _flows[_valves.indexOf(valveId)];
  double reading(String tag) => _readings[_tags.indexOf(tag)];
  double op(String loopTag) => _ops[_loops.indexOf(loopTag)];
}

/// Recorder of fast-layer sub-steps (test only; grows without bound while attached).
class FastTrace {
  final List<FastPoint> points = [];
}
