// M7 coder tests: debut / deprop presets (VALIDATION.md VC-9.6), key cuts, analysers, tier switches.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const _kmolh = 1000 / 3600;

Simulator _sim(String id) => Simulator(Presets.byId(id), options: const SimOptions(seed: 3), warmStart: false);

SimSnapshot _steady(Simulator s) {
  expect(s.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
  return s.snapshot();
}

void main() {
  group('debut', () {
    late Simulator sim;
    late SimSnapshot s;
    setUpAll(() {
      sim = _sim('debut');
      s = _steady(sim);
    });

    test('preset: Tier 3, DePriester, keys, E 0.7, 32 trays / feed 16', () {
      final c = sim.config;
      expect(c.tier, ThermoTier.t3);
      expect(c.tier3Model, Tier3Model.dePriester);
      expect(c.components[c.keys!.lk], 'nbutane');
      expect(c.components[c.keys!.hk], 'isopentane');
      expect(c.trayCount, 32);
      expect(c.feeds.first.stage, 16);
      expect(c.murphree, 0.7);
      expect(c.availableTiers, {ThermoTier.t1, ThermoTier.t2, ThermoTier.t3});
      final back = ColumnConfig.fromJson(c.toJson());
      expect(back.keys, c.keys);
    });

    test('9.6 steady state: D, recoveries, key-cut KPIs, temperatures, duties', () {
      expect(s.kpis.d / _kmolh, closeTo(44.94, 0.02));
      expect(s.kpis.recoveryLK!, closeTo(0.9781, 0.002));
      expect(s.kpis.recoveryHK!, closeTo(0.9783, 0.002));
      expect(s.kpis.xD, closeTo(0.54406, 5e-4));
      expect(s.kpis.xDHeavy, closeTo(0.01124, 5e-4));
      expect(s.kpis.xBLight, closeTo(0.01020, 5e-4));
      final n = s.layout.nTrays;
      expect(s.stages.t[0] - 273.15, closeTo(49.573, 0.05));
      expect(s.stages.t[1] - 273.15, closeTo(54.423, 0.05));
      expect(s.stages.t[n + 1] - 273.15, closeTo(112.719, 0.05));
      expect(s.kpis.qr / 1000, closeTo(679.68, 0.1));
      expect(s.kpis.qc / 1000, closeTo(616.34, 616.34 * 0.003));
      expect(s.stages.vaporUp[1] / _kmolh, closeTo(121.34, 121.34 * 0.002));
      expect(s.stages.vaporUp[n + 1] / _kmolh, closeTo(115.36, 115.36 * 0.002));
      expect(s.kpis.balanceResidual, lessThan(1e-3));
      expect(s.kpis.energyResidual, lessThan(1e-6));
    });

    test('analysers read the key cuts (AT-100 0.450, AT-101 0.0112, AT-102 0.0102) with the GC composition', () {
      Map<String, InstrumentReading> at() => {for (final i in sim.snapshot().instruments) if (i.tag.startsWith('AT-')) i.tag: i};
      sim.advance(1200);
      final a = at();
      expect(a['AT-100']!.value, closeTo(0.45, 1e-3));
      expect(a['AT-101']!.value, closeTo(0.0112, 5e-4));
      expect(a['AT-102']!.value, closeTo(0.0102, 5e-4));
      final c = a['AT-101']!.components!;
      expect(c.length, 6);
      expect(c.fold<double>(0, (p, e) => p + e), closeTo(1.0, 1e-3));
      expect(c[2], closeTo(0.5441, 2e-3));
      expect(a['AT-100']!.components![3], closeTo(0.20, 1e-3));
      // C2 closes on the light cut at steady state
      sim.setCheckWindow(1800);
      sim.advance(3600);
      final c2 = sim.snapshot().crossChecks.firstWhere((c) => c.id == 'C2');
      expect(c2.status.name, 'ok');
    });

    test('plant view: streams carry the GC composition, kpis the analyser cuts', () {
      sim.setLever('view', 1);
      final p = sim.snapshot();
      expect(p.streams[StreamId.distillate]!.composition[2], closeTo(0.544, 5e-3));
      expect(p.kpis.xDHeavy, closeTo(0.0112, 1e-3));
      sim.setLever('view', 0);
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('9.6 tier switches at steady state keep V1 and D (debut T3 to T2 and T1)', () {
    final sim = _sim('debut');
    _steady(sim);
    sim.setTier(ThermoTier.t2);
    // T2 <-> T3 keeps the duty SP, so D drifts (PHYSICS.md 13.5); VC-9.6 quotes T2 at the same L0 and D: Q_R 681.4 kW
    sim.setLever('reboilerDuty', 681400);
    var s = _steady(sim);
    expect(s.kpis.recoveryLK!, closeTo(0.9933, 0.003));
    expect(s.kpis.recoveryHK!, closeTo(0.9948, 0.003));
    expect(s.kpis.qr / 1000, closeTo(681.4, 3));
    sim.setTier(ThermoTier.t1);
    s = _steady(sim);
    expect(s.kpis.recoveryLK!, closeTo(0.9835, 0.003));
    expect(s.kpis.recoveryHK!, closeTo(0.9846, 0.003));
    expect(s.kpis.d / _kmolh, closeTo(44.94, 0.3));
  }, timeout: const Timeout(Duration(minutes: 10)));

  group('deprop', () {
    late Simulator sim;
    late SimSnapshot s;
    setUpAll(() {
      sim = _sim('deprop');
      s = _steady(sim);
    });

    test('9.6 steady state', () {
      expect(s.kpis.d / _kmolh, closeTo(30.78, 0.05));
      expect(s.kpis.recoveryLK!, closeTo(0.9906, 0.002));
      expect(s.kpis.recoveryHK!, closeTo(0.9535, 0.002));
      expect(s.kpis.xDHeavy, closeTo(0.03443, 5e-4));
      expect(s.kpis.xBLight, closeTo(0.00408, 5e-4));
      final n = s.layout.nTrays;
      expect(s.stages.t[n + 1] - 273.15, closeTo(123.851, 0.05));
      expect(s.kpis.qc / 1000, closeTo(349.84, 349.84 * 0.003));
      expect(s.kpis.pTop, closeTo(1724000, 1000));
    });

    test('pressure set point range reaches 25 bar', () {
      final lever = sim.levers.firstWhere((l) => l.id == 'pTop');
      expect(lever.max, greaterThanOrEqualTo(2.5e6));
      expect(lever.min, greaterThanOrEqualTo(3e5 - 1));
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
