// Crude control scheme (PHYSICS.md 10.7 crude paragraph, 300-series tags): loops, valves, instruments, alarms and the
// per-step sequence loops -> valves -> column -> instruments. Extends the generic services of [ControlSystem].
import 'dart:math' as math;

import '../config/column_config.dart';
import '../core/quantity.dart';
import '../core/ids.dart';
import '../model/crude_column.dart';
import '../snapshot/sim_snapshot.dart' show AlarmPriority;
import '../faults/fault_effects.dart';
import 'alarms.dart';
import 'control_system.dart';

class CrudeControl extends ControlSystem {
  final CrudeColumn col;
  final CrudeFaultState fault = CrudeFaultState();

  late final Valve fv301, fv311, fv312, fv313, fv314, fv321, fv322, fv323, fv324, lv301, lv302;
  late final ControlLoop tc301, fc301, lc301, lc302, fc311, fc312, fc313, fc314, tc320, fc321, fc322, fc323, fc324;
  late final Instrument ft300, ft301, lt301, lt302, ti320, ti314, fi314, qt314, pdt301;
  late final List<Instrument> ftProd, ltBoot, ftSteam, tiStage, tiBoot;

  /// Stages of TI-341..TI-350 (PHYSICS.md 10.7).
  static const List<int> tiStages = [1, 4, 8, 11, 15, 18, 21, 24, 26, 30];

  /// Model flags (alarms `model.*`, PHYSICS.md 10.8 crude row).
  bool modelDrawDry = false, modelCondenserLimited = false, modelPaDutyLimited = false, modelWaterCondensing = false;

  /// COT lever range (K) shown as the TC-320 span.
  static const double cotLo = 603.15, cotHi = 663.15;

  /// Reflux span (mol/s): 0..684 kmol/h.
  static const double refluxMax = 684 / 3.6;

  CrudeControl._(this.col, int seed, List<ControlLoop> loops, List<Instrument> insts, List<Valve> valves)
      : super.generic(seed, loops, insts, valves);

  /// Builds the control system at the design operating point (valves and loops in AUTO at the OPs that give the
  /// default flows).
  factory CrudeControl.build(ColumnConfig cfg, CrudeColumn col, int seed) {
    final lev = cfg.initialLevers;
    double l(String k, double d) => lev[k] ?? d;
    final cu = cfg.crude!;
    Valve valve(String id, double fMax, double flow) => Valve(id, fMax, seed, op: fMax > 0 ? 100 * flow / fMax : 0);
    // design flows used for valve sizing and initial OPs
    final refl0 = 316.1 / 3.6, naph0 = 192.96 / 3.6, res0 = 40.0;
    final prodMax = [0.25, 0.30, 0.15].map((f) => f * 0.073611).toList();
    final prodSp = [l('drawRate.kero', 0.00430625), l('drawRate.diesel', 0.00614653), l('drawRate.ago', 0.00195069)];
    final steamMax = [1.3889, 0.27778, 0.27778, 0.27778];
    final steamSp = [l('steam.bottom', 0.555556), l('steam.ss1', 0.0833333), l('steam.ss2', 0.0833333), l('steam.ss3', 0.0833333)];
    final paSp = l('paDuty', 5e6);
    final fv301 = valve('FV-301', refluxMax, refl0);
    final fvp = [for (var k = 0; k < 3; k++) valve('FV-${311 + k}', prodMax[k], prodSp[k])];
    final fv314 = valve('FV-314', 15e6, paSp);
    final fvs = [for (var q = 0; q < 4; q++) valve('FV-${321 + q}', steamMax[q], steamSp[q])];
    final lv301 = valve('LV-301', 2 * naph0, naph0);
    final lv302 = valve('LV-302', 2 * res0, res0);

    Instrument inst(String tag, String measures, InstrumentType ty, Quantity q, double lo, double hi,
            {double tauM = 0.5, double sigS = 0.5, double tauS = 1, double sigE = 0.02, double res = 0.1}) =>
        Instrument(
            InstrumentSpec(
                tag: tag,
                type: ty,
                measures: measures,
                quantity: q,
                lo: lo,
                hi: hi,
                tauM: tauM,
                sigmaS: sigS,
                tauS: tauS,
                sigmaE: sigE,
                resolution: res),
            seed: seed);
    Instrument ti(String tag, String m, [double lo = 273.15, double hi = 673.15]) =>
        inst(tag, m, InstrumentType.tiTray, Quantity.temperature, lo, hi, tauM: 10, sigS: 0.075, tauS: 20, res: 0.1);
    final ft300 = inst('FT-300', 'crudeRate', InstrumentType.ftLiquid, Quantity.volumeFlowCrude, 0, 0.073611 * 1.0,
        sigS: 0.3, res: 1e-5);
    final ft301 = inst('FT-301', 'valve.flow', InstrumentType.ftLiquid, Quantity.molarFlow, 0, refluxMax, res: 0.1 / 3.6);
    final lt301 = inst('LT-301', 'drum.levelPct', InstrumentType.ltDrum, Quantity.percent, 0, 100,
        tauM: 2, sigS: 0.5, tauS: 5);
    final lt302 = inst('LT-302', 'sump.levelPct', InstrumentType.ltSump, Quantity.percent, 0, 100,
        tauM: 2, sigS: 1.0, tauS: 3);
    final ftProd = [
      for (var k = 0; k < 3; k++)
        inst('FT-${311 + k}', 'valve.flow', InstrumentType.ftLiquid, Quantity.volumeFlowCrude, 0, prodMax[k], res: 1e-6)
    ];
    final ltBoot = [
      for (var k = 0; k < 3; k++)
        inst('LT-${311 + k}', 'stripper.levelPct', InstrumentType.ltSump, Quantity.percent, 0, 100,
            tauM: 2, sigS: 1.0, tauS: 3)
    ];
    final fi314 = inst('FI-314', 'paCirculation', InstrumentType.ftLiquid, Quantity.volumeFlowCrude, 0, 0.0666667, res: 1e-5);
    final qt314 = inst('QT-314', 'paDuty', InstrumentType.ftSteam, Quantity.energyRate, 0, 15e6, res: 1e3);
    final ti314 = ti('TI-314', 'paReturnT');
    final ti320 = ti('TI-320', 'cot', cotLo, cotHi + 30);
    final ftSteam = [
      for (var q = 0; q < 4; q++)
        inst('FT-${321 + q}', 'valve.flow', InstrumentType.ftSteam, Quantity.massFlow, 0, steamMax[q], res: 1e-4)
    ];
    final pdt301 = inst('PDT-301', 'columnDp', InstrumentType.pdt, Quantity.pressureDelta, 0, 40000,
        tauM: 2, sigS: 1.0, tauS: 5, res: 10);
    final tiStage = [for (final j in tiStages) ti('TI-${340 + tiStages.indexOf(j) + 1}', 'stage.T[$j]')];
    final tiBoot = [for (var k = 0; k < 3; k++) ti('TI-${351 + k}', 'stripper.T[$k]')];
    // flows moved by the level loops: typical sigma as in the B-T scheme
    final insts = <Instrument>[
      ft300, ft301, ...ftProd, fi314, qt314, ti314, ti320, ...ftSteam, lt301, lt302, ...ltBoot, pdt301, ...tiStage, ...tiBoot
    ];

    ControlLoop fc(String tag, Instrument pv, Valve v, double sp, double spHi, {double kc = 0.5, double ti = 3.0}) =>
        ControlLoop(
            tag: tag,
            pvTag: pv.spec.tag,
            mvRef: v.id,
            params: PidParams(kc: kc, ti: ti, action: Action.reverse, spKick: true),
            fastLayer: true,
            lo: pv.spec.lo,
            hi: pv.spec.hi,
            spLo: 0,
            spHi: spHi,
            sp: sp,
            op: v.position);
    ControlLoop lc(String tag, Instrument pv, Valve v) => ControlLoop(
        tag: tag,
        pvTag: pv.spec.tag,
        mvRef: v.id,
        params: const PidParams(kc: 2.0, ti: 1800, action: Action.direct, spKick: false),
        fastLayer: false,
        lo: 0,
        hi: 100,
        spLo: 10,
        spHi: 90,
        sp: 50,
        op: v.position);
    final fc301 = fc('FC-301', ft301, fv301, refl0, refluxMax, kc: 0.5, ti: 3.0);
    final tc301 = ControlLoop(
        tag: 'TC-301',
        pvTag: 'TI-341',
        mvRef: 'FC-301.sp',
        masterTag: null,
        params: const PidParams(kc: 1.0, ti: 300, action: Action.direct, spKick: false),
        fastLayer: false,
        lo: 373.15,
        hi: 423.15,
        spLo: 363.15,
        spHi: 433.15,
        sp: l('topTSp', 398.15),
        op: 100 * refl0 / refluxMax);
    final lc301 = lc('LC-301', lt301, lv301), lc302 = lc('LC-302', lt302, lv302);
    final fcp = [for (var k = 0; k < 3; k++) fc('FC-${311 + k}', ftProd[k], fvp[k], prodSp[k], prodMax[k])];
    final fc314 = fc('FC-314', qt314, fv314, paSp, 15e6, kc: 0.4, ti: 4.0);
    final tc320 = ControlLoop(
        tag: 'TC-320',
        pvTag: 'TI-320',
        mvRef: 'furnace',
        params: const PidParams(kc: 1.0, ti: double.infinity, action: Action.reverse, spKick: false),
        fastLayer: false,
        lo: cotLo,
        hi: cotHi,
        spLo: cotLo,
        spHi: cotHi,
        sp: l('cot', 618.15),
        op: 100 * (l('cot', 618.15) - cotLo) / (cotHi - cotLo));
    final fcs = [for (var q = 0; q < 4; q++) fc('FC-${321 + q}', ftSteam[q], fvs[q], steamSp[q], steamMax[q])];
    fc301
      ..mode = LoopMode.cas
      ..requestedMode = LoopMode.cas;
    final loops = [tc301, fc301, lc301, lc302, ...fcp, fc314, tc320, ...fcs];
    final valves = <Valve>[fv301, ...fvp, fv314, ...fvs, lv301, lv302];
    final cc = CrudeControl._(col, seed, loops, insts, valves);
    cc
      ..fv301 = fv301
      ..fv311 = fvp[0]
      ..fv312 = fvp[1]
      ..fv313 = fvp[2]
      ..fv314 = fv314
      ..fv321 = fvs[0]
      ..fv322 = fvs[1]
      ..fv323 = fvs[2]
      ..fv324 = fvs[3]
      ..lv301 = lv301
      ..lv302 = lv302
      ..tc301 = tc301
      ..fc301 = fc301
      ..lc301 = lc301
      ..lc302 = lc302
      ..fc311 = fcp[0]
      ..fc312 = fcp[1]
      ..fc313 = fcp[2]
      ..fc314 = fc314
      ..tc320 = tc320
      ..fc321 = fcs[0]
      ..fc322 = fcs[1]
      ..fc323 = fcs[2]
      ..fc324 = fcs[3]
      ..ft300 = ft300
      ..ft301 = ft301
      ..lt301 = lt301
      ..lt302 = lt302
      ..ti320 = ti320
      ..ti314 = ti314
      ..fi314 = fi314
      ..qt314 = qt314
      ..pdt301 = pdt301
      ..ftProd = ftProd
      ..ltBoot = ltBoot
      ..ftSteam = ftSteam
      ..tiStage = tiStage
      ..tiBoot = tiBoot;
    cc.indexAll();
    cc.pDesign = cfg.condenser.pTopDesign;
    cc._buildAlarmsCrude(cu.qcMax);
    return cc;
  }

  /// Highest flood fraction and weeping fraction over the 30 stages (last hydraulics refresh).
  double get maxFlood {
    var m = 0.0;
    for (var j = 0; j < CrudeColumn.nm; j++) {
      m = math.max(m, col.flood[j]);
    }
    return m;
  }

  double get maxWeep {
    var m = 0.0;
    for (var j = 0; j < CrudeColumn.nm; j++) {
      m = math.max(m, col.weepFrac[j]);
    }
    return m;
  }

  /// Sets the column inputs to the design flows before a cold start.
  void primeInputs(ColumnConfig cfg) {
    final inp = col.inp;
    inp.crudeRate = cfg.initialLevers['crudeRate'] ?? 0.0368056;
    inp.cot = tc320.sp;
    inp.pTop = cfg.initialLevers['pTop'] ?? 160000;
    inp.drumT = cfg.initialLevers['drumTSp'] ?? 318.15;
    inp.reflux = fc301.sp;
    final fcp = [fc311, fc312, fc313];
    for (var k = 0; k < 3; k++) {
      inp.prodVol[k] = fcp[k].sp;
    }
    inp.paDuty = fc314.sp;
    final fcs = [fc321, fc322, fc323, fc324];
    for (var q = 0; q < 4; q++) {
      inp.steam[q] = fcs[q].sp;
    }
    inp.naphtha = lv301.fMax * 0.5;
    inp.residue = lv302.fMax * 0.5;
    col.cotCtl = tc320.sp;
  }

  // ---------------------------------------------------------------- initialisation
  /// Instruments and loop histories start at the true values (PHYSICS.md 13.1 step 6).
  void initialiseCrude(double t) {
    col.inp.cot = tc320.sp;
    _updateInstruments(0.5, t, init: true);
    for (final l in loops) {
      l.initHistory(instrument(l.pvTag).value);
    }
  }

  // ---------------------------------------------------------------- one step
  /// Loops -> valves -> column -> instruments for one step of [dt] from time [t]. Returns false if the column failed.
  bool stepAll(double dt, double t) {
    time = t;
    final inp = col.inp;
    // 1 loops (PVs are the readings of the previous step)
    runLoop(lc301, dt, t);
    runLoop(lc302, dt, t);
    if (fc301.mode == LoopMode.cas) {
      if (tc301.mode == LoopMode.iman) tc301.mode = LoopMode.auto;
      runLoop(tc301, dt, t);
      fc301.setSpCascade(tc301.op / 100 * refluxMax);
    } else {
      // FC-301 on a local SP: the master tracks it (IMAN), so that going back to CAS is bumpless
      if (tc301.mode != LoopMode.iman) tc301.mode = LoopMode.iman;
      tc301.op = (100 * fc301.sp / refluxMax).clamp(0.0, 100.0);
      tc301.trackPv(instrument(tc301.pvTag).value);
    }
    for (final l in [fc301, fc311, fc312, fc313, fc314, fc321, fc322, fc323, fc324]) {
      runLoop(l, dt, t);
    }
    // TC-320: ideal furnace, first order with tau (PHYSICS.md 10.7); MAN holds the OP as a COT
    final cotTarget = tc320.mode == LoopMode.man ? cotLo + tc320.op / 100 * (cotHi - cotLo) : tc320.sp;
    col.cotCtl += (cotTarget - col.cotCtl) * dt / (col.cu.furnaceTau + dt);
    if (tc320.mode != LoopMode.man) tc320.op = 100 * (col.cotCtl - cotLo) / (cotHi - cotLo);
    inp.cot = col.cotCtl + fault.cotOffset;
    // 2 valves
    inp.reflux = fv301.step(dt, fc301.op, noise);
    final fvp = [fv311, fv312, fv313];
    for (var k = 0; k < 3; k++) {
      inp.prodVol[k] = fvp[k].step(dt, [fc311, fc312, fc313][k].op, noise);
    }
    inp.paDuty = fv314.step(dt, fc314.op, noise);
    inp.paScale = fault.paFactor;
    final fvs = [fv321, fv322, fv323, fv324];
    for (var q = 0; q < 4; q++) {
      final loop = [fc321, fc322, fc323, fc324][q];
      final passed = fvs[q].step(dt, loop.op, noise);
      // F24: a supply restriction delivers (1 - s) of the demanded steam; the loop winds up on the low flow reading
      final demand = loop.mode == LoopMode.man ? passed : loop.sp;
      inp.steam[q] = fault.steamFactor[q] < 1 ? math.min(passed, fault.steamFactor[q] * demand) : passed;
    }
    inp.naphtha = lv301.step(dt, lc301.op, noise);
    inp.residue = lv302.step(dt, lc302.op, noise);
    // 3 column
    final ok = col.step(dt);
    // 4 instruments, flags, alarms, trends
    _updateInstruments(dt, t);
    _flags();
    pushTrends();
    alarms.update(dt, t + dt);
    trends?.advance(t + dt);
    time = t + dt;
    return ok;
  }

  double _vStdAt(int a) => col.th.vStdMix(col.x, a * CrudeColumn.nc);

  double _true(String tag) => switch (tag) {
        'FT-300' => col.inp.crudeRate,
        'FT-301' => col.l0,
        'FT-311' => col.pAct[0] * _vStdAt(col.s2(0)),
        'FT-312' => col.pAct[1] * _vStdAt(col.s2(1)),
        'FT-313' => col.pAct[2] * _vStdAt(col.s2(2)),
        'FI-314' => col.paAct * _vStdAt(col.paDrawSt - 1),
        'QT-314' => col.qPA,
        'TI-314' => col.paReturnT,
        'TI-320' => col.cotCtl,
        'FT-321' => col.inp.steam[0],
        'FT-322' => col.inp.steam[1],
        'FT-323' => col.inp.steam[2],
        'FT-324' => col.inp.steam[3],
        'LT-301' => col.drumLevelPct,
        'LT-302' => col.sumpLevelPct,
        'LT-311' => col.bootLevelPct(0),
        'LT-312' => col.bootLevelPct(1),
        'LT-313' => col.bootLevelPct(2),
        'PDT-301' => col.columnDp,
        'TI-351' => col.t[col.s2(0)],
        'TI-352' => col.t[col.s2(1)],
        'TI-353' => col.t[col.s2(2)],
        _ => double.nan,
      };

  void _updateInstruments(double dt, double t, {bool init = false}) {
    final tStart = t;
    for (final i in instruments) {
      final tag = i.spec.tag;
      double v;
      final k = tag.startsWith('TI-34') || tag == 'TI-350' ? int.tryParse(tag.substring(3)) : null;
      if (k != null && k >= 341 && k <= 350) {
        v = col.t[tiStages[k - 341] - 1];
      } else {
        v = _true(tag);
      }
      if (init) {
        i.reset(v, t);
      } else {
        i.update(dt, v, tStart);
      }
    }
  }

  void _flags() {
    var mf = 0.0, mw = 0.0;
    for (var j = 0; j < CrudeColumn.nm; j++) {
      mf = math.max(mf, col.flood[j]);
      mw = math.max(mw, col.weepFrac[j]);
    }
    modelFlood = mf > 0.9;
    modelWeep = mw > 0.3;
    modelDc = false;
    var dry = false;
    for (var k = 0; k < 3; k++) {
      if (col.cutFac[k] < 0.999) dry = true;
    }
    modelDrawDry = dry;
    modelCondenserLimited = col.qc > col.cu.qcMax;
    modelPaDutyLimited = col.qPAmax > 0 && col.inp.paDuty > col.qPAmax * 1.0001;
    modelWaterCondensing = col.p[0] * col.steamUp[0] / (col.steamUp[0] + col.v[0]) > col.th.psat(CrudeColumn.nc, col.t[0]);
  }

  void _buildAlarmsCrude(double qcMax) {
    void add(String id, AlarmPriority p, double on, double off, String msg, bool Function(bool) c) =>
        alarms.add(AlarmDef(id, p, on, off, msg, c));
    bool above(Instrument i, double limit, double db, bool active) {
      if (i.quality == Quality.bad || i.quality == Quality.oos) return false;
      return active ? i.value > limit - db : i.value > limit;
    }

    bool below(Instrument i, double limit, double db, bool active) {
      if (i.quality == Quality.bad || i.quality == Quality.oos) return false;
      return active ? i.value < limit + db : i.value < limit;
    }

    for (final lt in [lt301, lt302]) {
      final t = lt.spec.tag;
      add('$t.HIHI', AlarmPriority.high, 5, 10, '$t level very high', (a) => above(lt, 95, 1, a));
      add('$t.LOLO', AlarmPriority.high, 5, 10, '$t level very low', (a) => below(lt, 5, 1, a));
      add('$t.HI', AlarmPriority.medium, 10, 10, '$t level high', (a) => above(lt, 80, 2, a));
      add('$t.LO', AlarmPriority.medium, 10, 10, '$t level low', (a) => below(lt, 20, 2, a));
    }
    for (final i in instruments) {
      final t = i.spec.tag;
      add('$t.BAD', AlarmPriority.medium, 2, 2, '$t bad signal', (a) => i.quality == Quality.bad);
    }
    add('model.flood', AlarmPriority.medium, 30, 30, 'Flooding: max flood above 90 %', (a) => modelFlood);
    add('model.weep', AlarmPriority.medium, 30, 30, 'Weeping above 30 %', (a) => modelWeep);
    add('model.drawDry', AlarmPriority.medium, 30, 30, 'A side draw is dry: the stripper level is falling', (a) => modelDrawDry);
    add('model.condenserLimited', AlarmPriority.medium, 30, 30, 'Condenser duty above its limit', (a) => modelCondenserLimited);
    add('model.paDutyLimited', AlarmPriority.low, 30, 30, 'PA duty limited by the cooler (FC-314 saturated)', (a) => modelPaDutyLimited);
    add('model.waterCondensing', AlarmPriority.high, 30, 30, 'Water condensing in the top trays', (a) => modelWaterCondensing);
  }

  /// The true value an instrument measures (cross-checks, plant views).
  double trueOf(Instrument i) {
    final tag = i.spec.tag;
    final k = int.tryParse(tag.length > 3 ? tag.substring(3) : '');
    if (tag.startsWith('TI-34') || tag == 'TI-350') {
      return col.t[tiStages[k! - 341] - 1];
    }
    return _true(tag);
  }

  // ---------------------------------------------------------------- operator actions
  @override
  void setMode(LoopTag tag, LoopMode mode) {
    if (mode == LoopMode.iman) throw StateError('IMAN is engine-internal');
    if (tag == 'FC-301') {
      if (mode == fc301.mode) return;
      if (mode == LoopMode.cas) {
        tc301.mode = LoopMode.auto;
        tc301.requestedMode = LoopMode.auto;
        tc301.op = (100 * fc301.sp / refluxMax).clamp(0.0, 100.0);
        tc301.trackPv(instrument(tc301.pvTag).value);
      } else if (mode == LoopMode.auto) {
        fc301.trackPv(instrument(fc301.pvTag).value);
        fc301.shed = false;
      }
      fc301.mode = mode;
      fc301.requestedMode = mode;
      alarms.log(time, 'MODE FC-301 ${mode.name.toUpperCase()}');
      return;
    }
    if (mode == LoopMode.cas) throw StateError('$tag has no master loop in this configuration');
    if (tag == 'TC-301' && fc301.mode != LoopMode.cas) {
      throw StateError('TC-301 follows FC-301 while FC-301 is not in CAS');
    }
    super.setMode(tag, mode);
  }

  // ---------------------------------------------------------------- persistence
  @override
  Map<String, Object?> toJson({bool includeTrends = true}) => {
        'noise': noise,
        'badPvShed': badPvShed,
        'loops': {for (final l in loops) l.tag: l.toJson()},
        'valves': {for (final v in valves) v.id: v.toJson()},
        'instruments': {for (final i in instruments) i.spec.tag: i.toJson()},
        'alarms': alarms.toJson(),
        'trends': includeTrends ? trends?.toJson() : null,
        'cotCtl': col.cotCtl,
      };

  @override
  void loadJson(Map<String, Object?> j) {
    noise = j['noise']! as bool;
    for (final i in instruments) {
      i.noise = noise;
    }
    badPvShed = j['badPvShed']! as bool;
    final ls = j['loops']! as Map<String, Object?>;
    for (final l in loops) {
      final m = ls[l.tag];
      if (m != null) l.loadJson(m as Map<String, Object?>);
    }
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
    if (tr != null && trends != null) trends!.loadJson(tr as Map<String, Object?>);
    col.cotCtl = (j['cotCtl'] as num?)?.toDouble() ?? col.cotCtl;
  }
}
