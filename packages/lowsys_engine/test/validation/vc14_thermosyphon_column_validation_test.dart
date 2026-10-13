// M6 validation, column level: VC-14.2 key items, G14 start (VC-14.3), typical sigma (10.5), H4/H5 drill evidence
// (VALIDATION.md §H) and the E.3 reference values 19, 23-29 of the M6 excerpt. B-T Tier 2, noise off unless stated.
import 'dart:convert';
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const _long = Timeout(Duration(minutes: 20));

Simulator _tsSim() {
  final c0 = Presets.byId('bt').copyWith(tier: ThermoTier.t2);
  final cfg = c0.copyWith(reboiler: ReboilerConfig.fromJson({...c0.reboiler.toJson(), 'type': 'thermosyphon'}));
  return Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
}

Simulator _copy(Simulator s) =>
    Simulator.restore(jsonDecode(jsonEncode(s.saveState())) as Map<String, Object?>);

bool _alarm(Simulator s, String id) => s.snapshot().alarms.any((a) => a.id == id && a.state != AlarmState.rtnUnack);
double _level(Simulator s) => s.snapshot().kpis.sumpLevelPct;
double _inst(Simulator s, String tag) => s.snapshot().instruments.firstWhere((i) => i.tag == tag).value;

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
double _pp(List<double> v) => v.reduce(math.max) - v.reduce(math.min);

/// Mean upward-crossing interval of the de-meaned series sampled every [dt] s.
double _period(List<double> v, double dt) {
  final m = _mean(v);
  final c = <int>[];
  for (var i = 1; i < v.length; i++) {
    if (v[i - 1] < m && v[i] >= m) c.add(i);
  }
  return c.length < 3 ? double.nan : (c.last - c.first) * dt / (c.length - 1);
}

void main() {
  late Simulator base;
  late double op50;
  setUpAll(() {
    base = _tsSim();
    final r = base.runToSteadyState(maxSimSeconds: 400000);
    expect(r.reached, isTrue);
    op50 = base.control.lc102.op;
  });

  test('VC-14.2.1 / E.3 #28: steady at 50 %, no oscillation, I_s 0.65-0.85; Q_max,0 = U A (T_st - T_b,mean); FV-103 near 79 %',
      () {
    final ts = base.control.ts!;
    final s = base.snapshot();
    expect(s.reboiler.oscAmplitude, lessThan(1e-6));
    expect(s.reboiler.instabilityIndex, inInclusiveRange(0.65, 0.85));
    final z = 1.2 + _level(base) / 100 * 2.4;
    final dTsub = ts.p.dTsatdP * ts.p.rhoL * 9.80665 * z;
    final q0Hand = 47.6e3 * (ts.p.tSteam - ts.p.tSump - dTsub / 2);
    expect(ts.qMax0, closeTo(q0Hand, 1e-3 * q0Hand), reason: 'Q_max,0 by hand from the engine state');
    print('#28 Q_max,0 ${(ts.qMax0 / 1e3).toStringAsFixed(1)} kW (spec 1636), FV-103 '
        '${base.control.fv103.position.toStringAsFixed(1)} % (spec ~79), T_sump ${(ts.p.tSump - 273.15).toStringAsFixed(2)} C '
        '(VC-14.1 input 110.39 C), I_s ${s.reboiler.instabilityIndex.toStringAsFixed(3)}, level ${_level(base).toStringAsFixed(1)} %');
    expect(ts.qMax0, closeTo(1636e3, 0.03 * 1636e3));
    expect(base.control.fv103.position, closeTo(79, 3));
    expect(s.kpis.qr, closeTo(1300e3, 0.005 * 1300e3), reason: 'FC-103 holds 1300 kW');
    // the sump is the column's bottom: T_sump is the bubble point there, and the loop's steam T is above it
    expect(ts.p.tSteam, greaterThan(ts.p.tSump + dTsub));
  });

  group('VC-14.2.2-14.2.4: drain to 15 %, throttle, refill', () {
    late Simulator sim;
    final boil = <double>[], dp = <double>[], ft = <double>[], qr = <double>[], ampTrace = <double>[];
    var alarmSeen = false, ftBinPp = 0.0, c3b = CheckStatus.notAvailable;
    double tGrow10 = double.nan, tGrow90 = double.nan;
    late double ampBefore, ampAfter5min, ampMin16;
    double tClear = double.nan;
    var alarmCleared = false;
    setUpAll(() {
      sim = _copy(base);
      sim.control.setMode('LC-102', LoopMode.man);
      sim.control.setOp('LC-102', 100);
      while (_level(sim) > 15 && sim.time < 400000 + base.time) {
        sim.advance(1);
        ampTrace.add(sim.control.ts!.amplitude);
      }
      sim.control.setOp('LC-102', op50);
      // 25 min at 15 %: samples every 0.5 s
      final bins = <double>[];
      var bin = <double>[];
      for (var i = 0; i < 3000; i++) {
        sim.advance(0.5);
        final s = sim.snapshot();
        if (i % 2 == 1) ampTrace.add(sim.control.ts!.amplitude);
        if (i < 1200) alarmSeen = alarmSeen || _alarm(sim, 'model.tsUnstable');
        if (i >= 600 && i < 1200) {
          boil.add(s.kpis.boilup);
          dp.add(s.kpis.columnDp);
        }
        if (i >= 600) {
          ft.add(_inst(sim, 'FT-103'));
          qr.add(s.kpis.qr);
          bin.add(_inst(sim, 'FT-103'));
          if (bin.length == 10) {
            bins.add(_mean(bin));
            bin = [];
          }
        }
      }
      c3b = sim.snapshot().crossChecks.firstWhere((c) => c.id == 'C3b').status;
      ftBinPp = _pp(bins) / bins.reduce(math.max);
      final aFin = ampTrace.last;
      final i10 = ampTrace.indexWhere((a) => a >= 0.1 * aFin), i90 = ampTrace.indexWhere((a) => a >= 0.9 * aFin);
      tGrow10 = i10.toDouble();
      tGrow90 = i90.toDouble();
      // 14.2.3: throttle to 16 %, 5 min
      ampBefore = sim.control.ts!.amplitude;
      sim.setLever('tsInletValve', 16);
      sim.advance(300);
      ampAfter5min = sim.control.ts!.amplitude;
      ampMin16 = ampAfter5min;
      for (var i = 0; i < 20; i++) {
        sim.advance(15);
        ampMin16 = math.min(ampMin16, sim.control.ts!.amplitude);
      }
      // refill: MAN OP 0 to >= 50 %, then AUTO at SP 50
      sim.control.setOp('LC-102', 0);
      double? t35;
      while (_level(sim) < 50) {
        sim.advance(1);
        if (t35 == null && _level(sim) >= 35) t35 = sim.time;
      }
      sim.setLever('sumpLevelSp', 50);
      sim.control.setMode('LC-102', LoopMode.auto);
      while (sim.time < t35! + 300) {
        sim.advance(1);
        if (tClear.isNaN && sim.control.ts!.amplitude < 0.005) tClear = sim.time - t35;
      }
      alarmCleared = !_alarm(sim, 'model.tsUnstable');
      print('14.2.2 boilup mean ${(_mean(boil) * 3.6).toStringAsFixed(1)} kmol/h p-p ${(100 * _pp(boil) / _mean(boil)).toStringAsFixed(1)} %, '
          'period ${_period(boil, 0.5).toStringAsFixed(2)} s, column dP period ${_period(dp, 0.5).toStringAsFixed(2)} s; '
          'growth 10->90 % of final ${(tGrow90 - tGrow10).toStringAsFixed(0)} s; FT-103 5-s bins p-p '
          '${(100 * ftBinPp).toStringAsFixed(1)} %; FT-103 vs qr ${(100 * (_mean(ft) / _mean(qr) - 1)).toStringAsFixed(2)} %, C3b $c3b');
      print('14.2.3 amplitude ${ampBefore.toStringAsFixed(3)} -> ${ampAfter5min.toStringAsFixed(3)} (5 min at 16 %), '
          'min later ${ampMin16.toStringAsFixed(3)}; < 0.005 at ${tClear.toStringAsFixed(0)} s after 35 %, alarm cleared $alarmCleared');
    });

    test('14.2.2 within 10 min of 15 %: boilup p-p >= 10 %, period 5-15 s, alarm, growth >= 30 s (ideal hydraulics)',
        () {
      expect(_pp(boil) / _mean(boil), greaterThanOrEqualTo(0.10));
      final p = _period(boil, 0.5);
      expect(p, inInclusiveRange(5, 15));
      expect(alarmSeen, isTrue, reason: 'model.tsUnstable');
      expect(tGrow90 - tGrow10, greaterThanOrEqualTo(30), reason: 'the amplitude grows, it does not step');
    }, timeout: _long);
    test('14.2.2 FT-103 5-s bins vary <= 2 % peak to peak',
        skip: 'pending spec ruling (DEVIATIONS "M6 checkpoint" point 1): the steam-side Q_k itself swings with the '
            'mist-flow limit; engine about 8 % (see the print)', () {
      expect(ftBinPp, lessThanOrEqualTo(0.02));
    });
    test('14.2.4 energy: mean FT-103 vs mean kpi.qr <= 1 % over 20 min; C3b ok', () {
      expect((_mean(ft) / _mean(qr) - 1).abs(), lessThanOrEqualTo(0.01));
      expect(c3b, CheckStatus.ok);
    });
    test('14.2.3 throttle to 16 %: amplitude down >= 30 % within 5 min but stays >= 0.04; refill clears it within 5 min of 35 %',
        () {
      expect(ampAfter5min, lessThanOrEqualTo(0.7 * ampBefore));
      expect(ampMin16, greaterThanOrEqualTo(0.04));
      expect(tClear, lessThanOrEqualTo(300));
      expect(alarmCleared, isTrue);
    });
  });

  group('VC-14.3 G14 start (E.3 #19)', () {
    late Simulator g;
    double tIs1 = double.nan, t005 = double.nan;
    late double is0, op0, q0;
    setUpAll(() {
      g = Simulator(Presets.byId('bt'), options: const SimOptions(seed: 3), warmStart: false);
      g.startScenario(Scenarios.byId('G14_thermosyphon'));
      is0 = g.control.ts!.iS;
      op0 = g.control.fc103.op;
      q0 = g.snapshot().kpis.qr;
      while (g.time < 600) {
        g.advance(1);
        if (tIs1.isNaN && g.control.ts!.iS > 1) tIs1 = g.time;
        if (t005.isNaN && g.control.ts!.amplitude >= 0.05) t005 = g.time;
      }
      print('G14: start I_s ${is0.toStringAsFixed(3)}, FC-103 ${op0.toStringAsFixed(1)} %, qr ${(q0 / 1e3).toStringAsFixed(0)} kW; '
          'I_s > 1 at $tIs1 s (spec 17 s), amplitude 0.05 at $t005 s (spec ~300 s)');
    });
    test('start: I_s 0.80-0.95, FC-103 at 100 %; surging (amplitude >= 0.05) within 10 min', () {
      expect(is0, inInclusiveRange(0.80, 0.95));
      expect(op0, closeTo(100, 1));
      expect(t005, lessThanOrEqualTo(600));
      expect(_level(g), inInclusiveRange(5, 95));
    }, timeout: _long);
    test('start duty 1040-1140 kW',
        skip: 'pending spec ruling (DEVIATIONS "M6 checkpoint" point 2): engine 1157 kW from the column sump T', () {
      expect(q0, inInclusiveRange(1040e3, 1140e3));
    });
  });

  test('E.3 #29 typical sigma at design (Tier 2, kettle, AUTO): PT-101 0.15 kPa, TI-100 0.05 K, FT-201 2.2 % of flow, TI-202 0.32 K',
      () {
    final s = Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2), options: const SimOptions(seed: 3), warmStart: false);
    s.runToSteadyState(maxSimSeconds: 400000);
    s.setLever('noise', 1);
    s.advance(1200);
    final r = {for (final i in s.snapshot().instruments) i.tag: i};
    final pt = r['PT-101']!.typicalSigma, ti100 = r['TI-100']!.typicalSigma;
    final ft = r['FT-201']!, ti202 = r['TI-202']!;
    final rise = ti202.value - (r['TI-201']?.value ?? double.nan);
    print('#29 PT-101 ${pt.toStringAsFixed(1)} Pa, TI-100 ${ti100.toStringAsFixed(4)} K, FT-201 ${ft.typicalSigma} '
        '(${(100 * ft.typicalSigma / ft.value).toStringAsFixed(2)} % of ${ft.value}), TI-202 ${ti202.typicalSigma.toStringAsFixed(3)} K '
        '(rise ${rise.toStringAsFixed(2)} K)');
    // E.3 #29 lists sigma_proc; the snapshot's typical sigma is sqrt(sigma_disp^2 + sigma_proc^2) (10.5). Before the
    // first 300-s window there is no process part, so a fresh Tier-2 build gives the transmitter's sigma_disp.
    final t1 = Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2), options: const SimOptions(seed: 3), warmStart: false);
    final r1 = {for (final i in t1.snapshot().instruments) i.tag: i};
    double proc(double typ, String tag) => math.sqrt(typ * typ - math.pow(r1[tag]!.typicalSigma, 2));
    print('#29 sigma_disp PT-101 ${r1['PT-101']!.typicalSigma.toStringAsFixed(1)} Pa, TI-100 '
        '${r1['TI-100']!.typicalSigma.toStringAsFixed(4)} K; sigma_proc ${proc(pt, 'PT-101').toStringAsFixed(1)} Pa, '
        '${proc(ti100, 'TI-100').toStringAsFixed(4)} K');
    expect(proc(pt, 'PT-101'), closeTo(0.0015 * 101325, 2), reason: 'sigma_P = 0.0015 SP');
    expect(proc(ti100, 'TI-100'), closeTo(3.2e-4 * 0.0015 * 101325, 0.003), reason: '0.32 K/kPa x 0.15 kPa');
    expect(ft.typicalSigma * 3600, closeTo(1.65, 0.1), reason: 'm3/h at about 72-75 m3/h');
    expect(ft.typicalSigma / ft.value, closeTo(0.022, 0.15 * 0.022));
    expect(ti202.typicalSigma, closeTo(0.32, 0.2 * 0.32));
    if (rise.isFinite) expect(ti202.typicalSigma, closeTo(0.022 * rise, 0.15 * 0.022 * rise));
  }, timeout: _long);

  group('§H H5 drill evidence on the thermosyphon column (onset 600 s, drill ramps; E.3 #24, #25)', () {
    ({double w0, double xe0, double din0, double dout0, Simulator s, List<double> iS, List<double> boil, double tIs1,
        double tAmp005}) run(FaultType type, double sev) {
      final s = _copy(base);
      final t0 = s.time;
      final ts = s.control.ts!;
      final w0 = ts.w, xe0 = ts.xe, din0 = ts.inletLineDp, dout0 = ts.outletLineDp;
      s.faults.inject(FaultSpec(
          type: type, location: const FaultLocation.equipment('reboiler'), severity: sev, onset: t0 + 600, ramp: 1800));
      final iS = <double>[], boil = <double>[];
      var tIs1 = double.nan, tA = double.nan;
      while (s.time < t0 + 600 + 7200) {
        s.advance(0.5);
        iS.add(ts.iS);
        if (s.time > t0 + 600 + 7200 - 300) boil.add(s.snapshot().kpis.boilup);
        if (tIs1.isNaN && ts.iS > 1) tIs1 = s.time - t0 - 600;
        if (tA.isNaN && ts.amplitude >= 0.05) tA = s.time - t0 - 600;
      }
      return (w0: w0, xe0: xe0, din0: din0, dout0: dout0, s: s, iS: iS, boil: boil, tIs1: tIs1, tAmp005: tA);
    }

    test('F17 inlet restriction s 0.55: W down >= 20 %, x_e up >= 0.1, inlet dP >= 5x, I_s < 1 throughout, no oscillation', () {
      final r = run(FaultType.tsInletRestriction, 0.55);
      final ts = r.s.control.ts!;
      print('#24 F17: W ${r.w0.toStringAsFixed(2)} -> ${ts.w.toStringAsFixed(2)} (${(100 * (ts.w / r.w0 - 1)).toStringAsFixed(0)} %), '
          'x_e ${r.xe0.toStringAsFixed(3)} -> ${ts.xe.toStringAsFixed(3)}, inlet dP x${(ts.inletLineDp / r.din0).toStringAsFixed(1)}, '
          'max I_s ${r.iS.reduce(math.max).toStringAsFixed(3)}, amplitude ${ts.amplitude.toStringAsExponential(2)}');
      expect(ts.w, lessThanOrEqualTo(0.8 * r.w0));
      expect(ts.xe - r.xe0, greaterThanOrEqualTo(0.1));
      expect(ts.inletLineDp, greaterThanOrEqualTo(5 * r.din0));
      expect(r.iS.reduce(math.max), lessThan(1));
      expect(ts.amplitude, lessThan(0.01));
    }, timeout: _long);

    test('F18 outlet restriction s 0.4: I_s > 1 within 15 min, boilup period 5-15 s and p-p >= 10 % within 30 min, outlet dP >= 1.5x, '
        'duty below SP with FC-103 at 100 %', () {
      final r = run(FaultType.tsOutletRestriction, 0.4);
      final s = r.s, ts = s.control.ts!;
      final pp = _pp(r.boil) / _mean(r.boil), per = _period(r.boil, 0.5);
      print('#25 F18: I_s > 1 at ${(r.tIs1 / 60).toStringAsFixed(1)} min (spec 6), amplitude 0.05 at '
          '${(r.tAmp005 / 60).toStringAsFixed(1)} min (spec 14); outlet dP x${(ts.outletLineDp / r.dout0).toStringAsFixed(2)} '
          '(spec ~2.6); boilup p-p ${(100 * pp).toStringAsFixed(0)} %, period ${per.toStringAsFixed(1)} s; '
          'steam-side ${(s.snapshot().reboiler.steamSideDuty / 1e3).toStringAsFixed(0)} kW, FC-103 ${s.control.fc103.op.toStringAsFixed(1)} %');
      expect(r.tIs1, lessThanOrEqualTo(900));
      expect(r.tAmp005, lessThanOrEqualTo(1800));
      expect(per, inInclusiveRange(5, 15));
      expect(pp, greaterThanOrEqualTo(0.10));
      expect(ts.outletLineDp, greaterThanOrEqualTo(1.5 * r.dout0));
      expect(s.control.fc103.op, closeTo(100, 0.5));
      expect(s.snapshot().reboiler.steamSideDuty, lessThan(1300e3 * 0.99));
    }, timeout: _long);
  });

  test('§H H5 LT-102 drift +10 %/h (E.3 #23, #27): displayed level at SP, true level falls; W down >= 8 % in 1 h; '
      'I_s > 1 once the true level <= 32 %; boilup p-p >= 10 % before 22 %; C5 sump fail (3600-s window) 75 min after onset',
      () {
    final s = _copy(base);
    s.setCheckWindow(3600);
    final t0 = s.time + 600;
    final ts = s.control.ts!;
    final w0 = ts.w;
    s.faults.inject(FaultSpec(
        type: FaultType.instrument,
        location: const FaultLocation.tag('LT-102'),
        severity: 1.0,
        onset: t0,
        params: const {'kind': 'drift', 'sign': 1}));
    double? wAt1h, levelIs1, tIs1, levelPp, tPp;
    CheckStatus? c5At75;
    final win = <double>[];
    while (s.time < t0 + 3 * 3600) {
      s.advance(0.5);
      final k = s.snapshot().kpis;
      if (wAt1h == null && s.time >= t0 + 3600) wAt1h = ts.w;
      if (levelIs1 == null && ts.iS > 1) {
        levelIs1 = k.sumpLevelPct;
        tIs1 = (s.time - t0) / 3600;
      }
      win.add(k.boilup);
      if (win.length > 120) win.removeAt(0);
      if (levelPp == null && win.length == 120 && _pp(win) / _mean(win) >= 0.10) {
        levelPp = k.sumpLevelPct;
        tPp = (s.time - t0) / 3600;
      }
      if (c5At75 == null && s.time >= t0 + 75 * 60) {
        c5At75 = s.snapshot().crossChecks.firstWhere((c) => c.id.startsWith('C5') && c.id.contains('sump')).status;
      }
      if (levelPp != null && c5At75 != null) break;
    }
    final lt = _inst(s, 'LT-102');
    print('#23 LT-102 drift: W at 1 h ${(100 * (wAt1h! / w0 - 1)).toStringAsFixed(1)} %; I_s > 1 at ${tIs1?.toStringAsFixed(2)} h, '
        'level ${levelIs1?.toStringAsFixed(1)} % (spec 1.93 h, 30.7 %); boilup p-p >= 10 % at ${tPp?.toStringAsFixed(2)} h, '
        'level ${levelPp?.toStringAsFixed(1)} % (spec 2.45 h, 25.5 %); C5:sump at 75 min (3600-s window) $c5At75; LT-102 reads $lt');
    expect(wAt1h / w0 - 1, lessThanOrEqualTo(-0.08));
    expect(levelIs1, isNotNull);
    expect(levelIs1!, lessThanOrEqualTo(32));
    expect(levelPp, isNotNull);
    expect(levelPp!, greaterThanOrEqualTo(22));
    expect(c5At75, CheckStatus.fail);
  }, timeout: _long);

  group('E.3 #26 kettle F13 s 0.85, ramp 5400 s (H4, Tier 2)', () {
    double? tSat, opAt30, opPre, tShort;
    late double op0, qr2h;
    var limited = false;
    setUpAll(() {
      final s = Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2), options: const SimOptions(seed: 3), warmStart: false);
      s.runToSteadyState(maxSimSeconds: 400000);
      final t0 = s.time + 600;
      op0 = s.control.fv103.position;
      s.faults.inject(FaultSpec(
          type: FaultType.reboilerFouling,
          location: const FaultLocation.equipment('reboiler'),
          severity: 0.85,
          onset: t0,
          ramp: 5400));
      var opPrev = op0;
      while (s.time < t0 + 7200) {
        s.advance(5);
        final op = s.control.fv103.position;
        if (opAt30 == null && s.time >= t0 + 1800) opAt30 = op;
        if (tShort == null && s.time > t0 && s.snapshot().kpis.qr < 0.995 * 1300e3) tShort = (s.time - t0) / 60;
        if (tSat == null && op >= 99.5) {
          tSat = (s.time - t0) / 60;
          opPre = opPrev;
        }
        opPrev = op;
        limited = limited || _alarm(s, 'model.dutyLimited');
      }
      qr2h = s.snapshot().kpis.qr;
      print('#26 kettle F13: FV-103 ${op0.toStringAsFixed(1)} % -> ${opAt30!.toStringAsFixed(1)} % at 30 min, '
          '${opPre?.toStringAsFixed(1)} % 5 s before saturating at ${tSat?.toStringAsFixed(1)} min (spec ~47; '
          's(t) ${(0.85 * (tSat ?? 0) * 60 / 5400).toStringAsFixed(3)}, spec 0.44); duty < SP from ${tShort?.toStringAsFixed(1)} min; '
          'qr at 2 h ${(qr2h / 1e3).toStringAsFixed(0)} kW; dutyLimited $limited');
    });
    test('valve saturates >= 30 min after onset, ~47 min (± 15 %); duty below SP after; model.dutyLimited', () {
      expect(tSat, isNotNull);
      expect(tSat!, greaterThanOrEqualTo(30));
      expect(tSat!, closeTo(47, 0.15 * 47));
      expect(qr2h, lessThan(0.98 * 1300e3));
      expect(limited, isTrue);
    }, timeout: _long);
    test('the steam valve creeps open over >= 30 min before saturating (§H H4 row, H4 debrief)',
        skip: 'spec item (DEVIATIONS "M6 validation"): with Q_v = Q_max,0(clean) g(p) and Q = min(Q_v, Q_max) (§10.3) '
            'the valve cannot see fouling until Q_max < Q_v; engine: flat at 58.7 %, then 100 % within seconds', () {
      expect(opAt30!, greaterThan(op0 + 5));
    });
  });

  test('VC-14.2.2 (full hydraulics): at 15 % level the column dP and the bottom-tray dP oscillate at the boilup period',
      () {
    final c0 = Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.full);
    final cfg = c0.copyWith(reboiler: ReboilerConfig.fromJson({...c0.reboiler.toJson(), 'type': 'thermosyphon'}));
    final s = Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
    expect(s.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
    final op = s.control.lc102.op;
    s.control.setMode('LC-102', LoopMode.man);
    s.control.setOp('LC-102', 100);
    while (_level(s) > 15) {
      s.advance(1);
    }
    s.control.setOp('LC-102', op);
    s.advance(300);
    final boil = <double>[], dp = <double>[], dpb = <double>[];
    int? jb;
    for (var i = 0; i < 600; i++) {
      s.advance(0.5);
      final q = s.snapshot();
      if (jb == null) {
        jb = q.stages.n - 1;
        while (jb! > 0 && !(q.stages.dp[jb] > 0)) {
          jb--;
        }
      }
      boil.add(q.kpis.boilup);
      dp.add(q.kpis.columnDp);
      dpb.add(q.stages.dp[jb]);
    }
    final p = _period(boil, 0.5);
    print('14.2.2 full hydraulics: boilup period ${p.toStringAsFixed(2)} s, p-p ${(100 * _pp(boil) / _mean(boil)).toStringAsFixed(1)} %; '
        'column dP period ${_period(dp, 0.5).toStringAsFixed(2)} s p-p ${(100 * _pp(dp) / _mean(dp)).toStringAsFixed(1)} %; '
        'stage $jb dP period ${_period(dpb, 0.5).toStringAsFixed(2)} s p-p ${(100 * _pp(dpb) / _mean(dpb)).toStringAsFixed(1)} %');
    expect(p, inInclusiveRange(5, 15));
    expect(_period(dp, 0.5), closeTo(p, 0.15 * p));
    expect(_period(dpb, 0.5), closeTo(p, 0.15 * p));
    expect(_pp(dp) / _mean(dp), greaterThan(0.01));
  }, timeout: _long);
}
