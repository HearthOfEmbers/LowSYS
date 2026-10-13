// Spec rulings of 2026-10-13 (OPEN_ITEMS.md "For coder"): partial-condenser CW default, balanceResidual with D_V,
// C1/C2/C3b n/a with a partial condenser, C4 PV-101 on the CW valve, T1 -> T2 PC-101 start at 50 %, T2 <-> T3 CW
// valve for a continuous Q_C.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const kmolh = 1000 / 3600;

void main() {
  test('partial condenser: cwOP defaults to cwOpPartial (30 %), D_V about a quarter of D, balanceResidual with D_V', () {
    final sim = Simulator(
        Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.ideal),
        options: const SimOptions(seed: 3), warmStart: false);
    sim.setLever('condenserType', 1);
    expect(sim.lever('cwOP'), 30);
    expect(sim.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
    final s = sim.snapshot();
    expect(s.condenser!.vaporProduct / kmolh, closeTo(12.6, 0.5));
    expect(s.kpis.balanceResidual, lessThan(1e-9));
    expect(s.kpis.energyResidual, lessThan(1e-6));
  });

  test('partial condenser cross-checks: C1, C2, C3b and the sump C5 n/a; C3a, drum C5 and C4 PV-101 (CW valve) ok', () {
    final sim = Simulator(
        Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.ideal),
        options: const SimOptions(seed: 3), warmStart: false);
    sim.setLever('condenserType', 1);
    sim.runToSteadyState(maxSimSeconds: 400000);
    sim.setCheckWindow(600);
    sim.advance(1500);
    final c = {for (final r in sim.snapshot().crossChecks) r.id: r};
    for (final id in ['C1', 'C2', 'C3b']) {
      expect(c[id]!.status, CheckStatus.notAvailable, reason: id);
      expect(c[id]!.reason, 'vapour product not metered');
    }
    expect(c['C5:sump']!.status, CheckStatus.notAvailable);
    for (final id in ['C3a', 'C5:drum', 'C4:PV-101']) {
      expect(c[id], isNotNull, reason: id);
      expect(c[id]!.status, CheckStatus.ok, reason: '$id ${c[id]!.residual} ${c[id]!.band}');
    }
    expect(c.containsKey('C4:PV-102'), isFalse);
  });

  test('T1 -> T2 starts PC-101 at 50 %, also after a Tier 2 visit that moved the CW valve', () {
    final sim = Simulator(Presets.byId('bt'), options: const SimOptions(seed: 3), warmStart: false);
    sim.setTier(ThermoTier.t2);
    expect(sim.control.pc101.op, closeTo(50, 1e-9));
    sim.setLever('cwOP', 80);
    sim.advance(60);
    sim.setTier(ThermoTier.t1);
    sim.advance(10);
    sim.setTier(ThermoTier.t2);
    expect(sim.control.pc101.op, closeTo(50, 1e-9));
  });

  test('c4 T2 -> T3: Q_C continuous, P within 0.5 kPa throughout, CW valve to about 59 %', () {
    final sim = Simulator(Presets.byId('c4'), options: const SimOptions(seed: 3), warmStart: false);
    sim.runToSteadyState(maxSimSeconds: 400000);
    final qOld = sim.snapshot().condenser!.qC;
    final cwOld = sim.control.cwValve.position;
    sim.setTier(ThermoTier.t3);
    final cwNew = sim.control.cwValve.position;
    sim.advance(1);
    expect(sim.snapshot().condenser!.qC, closeTo(qOld, 0.01 * qOld));
    var peak = 0.0;
    for (var i = 0; i < 1800; i++) {
      sim.advance(1);
      final dp = (sim.snapshot().kpis.pTop - 700000).abs();
      if (dp > peak) peak = dp;
    }
    // ignore: avoid_print
    print('c4 T2 -> T3: CW ${cwOld.toStringAsFixed(1)} -> ${cwNew.toStringAsFixed(1)} %, peak |dP| ${peak.toStringAsFixed(0)} Pa');
    expect(cwNew, greaterThan(cwOld));
    expect(peak, lessThan(500));
  });
}
