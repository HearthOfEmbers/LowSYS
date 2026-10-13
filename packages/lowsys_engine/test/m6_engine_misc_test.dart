// M6 engine checks (coder): views (plant, plantCalc, drill masking), explain lines eq.ts.*, the reboiler type and
// tier switches, C4 of FV-103 on a thermosyphon, the process-driven typical sigma.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

ColumnConfig _tsCfg({HydraulicsMode h = HydraulicsMode.ideal}) {
  final cfg0 = Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: h);
  return cfg0.copyWith(reboiler: ReboilerConfig.fromJson({...cfg0.reboiler.toJson(), 'type': 'thermosyphon'}));
}

Simulator _tsSim({HydraulicsMode h = HydraulicsMode.ideal}) =>
    Simulator(_tsCfg(h: h), options: const SimOptions(seed: 3), warmStart: false);

void main() {
  late Simulator steady;
  setUpAll(() {
    steady = _tsSim(h: HydraulicsMode.full);
    expect(steady.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
  });

  test('model view carries the loop; plant view NaNs it; plantCalc keeps the calculated fields', () {
    final m = steady.snapshot().reboiler;
    expect(m.type, ReboilerType.thermosyphon);
    for (final v in [m.circulation, m.exitQuality, m.riserQuality, m.instabilityIndex, m.oscAmplitude, m.oscPeriod,
      m.inletLineDp, m.outletLineDp, m.drivingHead, m.sensibleFraction]) {
      expect(v.isFinite, isTrue);
    }
    expect(m.steamSideDuty, closeTo(m.qDelivered, 0.02 * m.qDelivered));
    steady.setLever('view', 1);
    var p = steady.snapshot();
    for (final v in [p.reboiler.circulation, p.reboiler.exitQuality, p.reboiler.instabilityIndex, p.reboiler.oscAmplitude,
      p.reboiler.inletLineDp, p.reboiler.outletLineDp, p.reboiler.drivingHead, p.reboiler.sensibleFraction]) {
      expect(v.isNaN, isTrue);
    }
    expect(p.reboiler.inletValve, 100);
    expect(p.kpis.maxFloodPct.isNaN, isTrue);
    steady.setLever('view', 2);
    expect(steady.lever('view'), 2);
    p = steady.snapshot();
    expect(p.view, SimView.plantCalc);
    // kept: circulation, exit quality, riser quality, I_s, amplitude, period, line dPs; not kept: driving head, f_sc
    for (final v in [p.reboiler.circulation, p.reboiler.exitQuality, p.reboiler.riserQuality, p.reboiler.instabilityIndex,
      p.reboiler.oscAmplitude, p.reboiler.oscPeriod, p.reboiler.inletLineDp, p.reboiler.outletLineDp]) {
      expect(v.isFinite, isTrue);
    }
    expect(p.reboiler.drivingHead.isNaN, isTrue);
    expect(p.reboiler.sensibleFraction.isNaN, isTrue);
    expect(p.kpis.maxFloodPct.isFinite, isTrue);
    expect(p.kpis.maxWeepFraction.isFinite, isTrue);
    expect(p.stages.dp[5].isFinite, isTrue);
    expect(p.stages.jetFlood[5].isFinite, isTrue);
    expect(p.stages.x[5].isNaN, isTrue);
    expect(p.stages.vaporUp[5].isNaN, isTrue);
    expect(p.stages.efficiency[5].isNaN, isTrue);
    steady.setLever('view', 0);
  });

  test('explain: the thermosyphon lines of PHYSICS.md 15 agree with the snapshot', () {
    final snap = steady.snapshot();
    final r = steady.explain(const ExplainReboiler());
    final lines = {for (final g in r.groups) for (final l in g.lines) l.id: l};
    for (final id in ['eq.ts.subcooling', 'eq.ts.exitQuality', 'eq.ts.drivingHead', 'eq.ts.friction', 'eq.ts.instabilityIndex', 'eq.boilup']) {
      expect(lines.containsKey(id), isTrue, reason: id);
    }
    expect(lines.containsKey('eq.kettleDuty'), isFalse);
    expect(lines['eq.ts.exitQuality']!.value, closeTo(snap.reboiler.exitQuality, 1e-9));
    expect(lines['eq.ts.drivingHead']!.value, closeTo(snap.reboiler.drivingHead, 1e-6 * snap.reboiler.drivingHead.abs() + 1e-6));
    expect(lines['eq.ts.instabilityIndex']!.value, closeTo(snap.reboiler.instabilityIndex, 1e-9));
    // circulation settles where the loss equals the driving head (implicit step, tiny residual)
    expect(lines['eq.ts.friction']!.value, closeTo(snap.reboiler.drivingHead, 0.01 * snap.reboiler.drivingHead.abs() + 1));
  });

  test('plant view only offers the instrument, loop and check explain targets', () {
    steady.setLever('view', 1);
    final r = steady.explain(const ExplainReboiler());
    expect(r.groups, isEmpty);
    steady.setLever('view', 0);
  });

  test('C4 of FV-103 on a thermosyphon is ok at the steady state; F18 shows on the loop, not on FT-103', () {
    final s = _tsSim();
    s.runToSteadyState(maxSimSeconds: 400000);
    s.setCheckWindow(600);
    s.advance(1500);
    final c = {for (final r in s.snapshot().crossChecks) r.id: r};
    expect(c['C4:FV-103']!.status, CheckStatus.ok, reason: '${c['C4:FV-103']!.residual} ${c['C4:FV-103']!.band}');
    expect(c['C3b']!.status, CheckStatus.ok);
    s.faults.inject(const FaultSpec(
        type: FaultType.tsOutletRestriction,
        location: FaultLocation.equipment('reboiler'),
        severity: 0.4,
        onset: 0,
        ramp: 1));
    s.advance(1800);
    final ts = s.control.ts!;
    expect(ts.iS, greaterThan(1.3));
    expect(ts.amplitude, greaterThan(0.1));
    expect(s.snapshot().reboiler.outletLineDp, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('F17 (inlet restriction) lowers the circulation and does not surge', () {
    final s = _tsSim();
    s.runToSteadyState(maxSimSeconds: 400000);
    final w0 = s.control.ts!.w;
    s.faults.inject(const FaultSpec(
        type: FaultType.tsInletRestriction,
        location: FaultLocation.equipment('reboiler'),
        severity: 0.5,
        onset: 0,
        ramp: 1));
    s.advance(2400);
    final ts = s.control.ts!;
    expect(ts.w, lessThan(0.75 * w0));
    expect(ts.iS, lessThan(1.0));
    expect(ts.amplitude, lessThan(0.005));
  });

  test('reboilerType lever: kettle -> thermosyphon keeps the duty, runs to a steady state', () {
    final cfg = Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.ideal);
    final s = Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
    s.runToSteadyState(maxSimSeconds: 400000);
    final q0 = s.snapshot().kpis.qr;
    expect(s.control.ts, isNull);
    s.setLever('reboilerType', 1);
    expect(s.control.ts, isNotNull);
    expect(s.snapshot().reboiler.type, ReboilerType.thermosyphon);
    s.advance(600);
    final k = s.snapshot().kpis;
    expect(k.qr, closeTo(q0, 0.02 * q0));
    expect(s.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
    s.setLever('reboilerType', 0);
    expect(s.control.ts, isNull);
    s.advance(300);
    expect(s.snapshot().kpis.qr, closeTo(q0, 0.03 * q0));
  });

  test('Tier 1 and back: the loop is re-initialised (PHYSICS.md 13.1 step 7), the duty comes back', () {
    final s = _tsSim();
    s.runToSteadyState(maxSimSeconds: 400000);
    final q0 = s.snapshot().kpis.qr;
    s.setTier(ThermoTier.t1);
    s.advance(120);
    s.setTier(ThermoTier.t2);
    s.advance(900);
    final k = s.snapshot().kpis;
    expect(k.qr.isFinite, isTrue);
    expect(k.qr, closeTo(q0, 0.03 * q0));
    expect(s.control.ts!.iS, inInclusiveRange(0.6, 0.9));
    expect(s.snapshot().reboiler.type, ReboilerType.thermosyphon);
  });

  test('drill masking: fault parameters are NaN while a drill runs (model view)', () {
    final s = Simulator(Presets.byId('bt'), options: const SimOptions(seed: 3), warmStart: false);
    s.startScenario(Scenarios.byId('H4_reboiler'));
    final r = s.snapshot();
    expect(r.reboiler.uaEff.isNaN, isTrue);
    expect(r.reboiler.qMax.isNaN, isTrue);
    expect(r.condenser!.uaEff.isNaN, isTrue);
    expect(r.condenser!.inertFraction.isNaN, isTrue);
    expect(r.visibleFaults, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('typical sigma of the process-driven tags (Tier 2): PT-101, TI-100, FT-201, TI-202', () {
    final s = Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2), options: const SimOptions(seed: 3), warmStart: false);
    s.runToSteadyState(maxSimSeconds: 400000);
    s.setLever('noise', 1);
    s.advance(1200);
    final r = {for (final i in s.snapshot().instruments) i.tag: i};
    final pt = r['PT-101']!;
    // sqrt(sigma_disp^2 + (0.0015 SP)^2): about 0.15 kPa plus the transmitter's own noise
    expect(pt.typicalSigma, inInclusiveRange(0.0015 * 101325, 0.0015 * 101325 + 150));
    expect(r['TI-100']!.typicalSigma, closeTo(0.05, 0.02));
    expect(r['FT-201']!.typicalSigma, greaterThan(0));
    final ratio = r['TI-202']!.sigma5min / r['TI-202']!.typicalSigma;
    expect(ratio, inInclusiveRange(0.2, 4));
  });
}
