// Partial condenser (E50, PHYSICS.md 7.2 to 7.5): PV-102 vapour product, PC-101 Kc 2 / Ti 30 s.
import 'dart:convert';
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

ColumnConfig _partialCfg(double cwOp) {
  final cfg = Presets.byId('bt')
      .copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.ideal);
  return cfg.copyWith(
    condenser: CondenserConfig.fromJson(
        {...cfg.condenser.toJson(), 'type': 'partial'}),
    initialLevers: {...cfg.initialLevers, 'cwOP': cwOp},
  );
}

Simulator _steady(double cwOp) {
  final sim = Simulator(_partialCfg(cwOp),
      options: const SimOptions(seed: 3), warmStart: false);
  sim.runToSteadyState();
  return sim;
}

void main() {
  test('steady state: P holds, mass and energy close, vapour product flows', () {
    final sim = _steady(30);
    final s = sim.snapshot();
    final c = s.condenser!;
    expect(c.partial, isTrue);
    expect(s.kpis.pTop, closeTo(101325, 500));
    final dv = c.vaporProduct * 3.6;
    expect(dv, inInclusiveRange(5, 25));
    final f = s.streams[StreamId.feed]!.flow;
    expect(s.kpis.d + c.vaporProduct + s.kpis.b, closeTo(f, 1e-4 * f));
    expect(s.kpis.energyResidual, lessThan(1e-6));
    // the vapour product is richer in the light key than the liquid distillate (y_0 = K x_0)
    final vp = s.streams[StreamId.vaporProduct]!;
    expect(vp.composition[0], greaterThan(s.stages.x[0]));
    expect(vp.flow, c.vaporProduct);
  });

  test('over-sized CW (70 %, spec default): PV-102 closes and P floats below SP',
      () {
    final sim = _steady(70);
    final s = sim.snapshot();
    expect(s.condenser!.vaporProduct, lessThan(1e-6));
    expect(s.kpis.pTop, lessThan(101325 - 3000));
  });

  test('VC-16.6b: +-10 kPa SP steps settle within 1 kPa in 10 min, overshoot <= 30 %',
      () {
    for (final step in [10000.0, -10000.0]) {
      final sim = _steady(30);
      final p0 = sim.snapshot().kpis.pTop;
      sim.setLever('pTop', p0 + step);
      var over = 0.0, lastOut = 0.0;
      for (var t = 0; t < 1800; t += 5) {
        sim.advance(5);
        final e = sim.snapshot().kpis.pTop - (p0 + step);
        if (e.abs() > 1000) lastOut = t + 5.0;
        over = math.max(over, e * step.sign);
      }
      expect(lastOut, lessThanOrEqualTo(600), reason: 'step $step');
      expect(over, lessThanOrEqualTo(0.3 * step.abs()), reason: 'step $step');
    }
  });

  test('save and restore continue bit-identically', () {
    final sim = _steady(30);
    sim.setLever('noise', 1);
    sim.setLever('pTop', 104000);
    sim.advance(600);
    final copy = Simulator.restore(
        jsonDecode(jsonEncode(sim.saveState())) as Map<String, Object?>);
    expect(jsonEncode(copy.saveState()), jsonEncode(sim.saveState()));
    sim.advance(120);
    copy.advance(120);
    expect(jsonEncode(copy.saveState()), jsonEncode(sim.saveState()));
  });

  test('condenserType lever rebuilds; Tier 1 refuses a partial condenser', () {
    final sim = Simulator(
        Presets.byId('bt')
            .copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.ideal),
        options: const SimOptions(seed: 3),
        warmStart: false);
    sim.setLever('cwOP', 30);
    sim.setLever('condenserType', 1);
    sim.advance(60);
    expect(sim.snapshot().condenser!.partial, isTrue);
    expect(() => sim.setTier(ThermoTier.t1), throwsUnsupportedError);
    sim.setLever('condenserType', 0);
    sim.advance(60);
    expect(sim.snapshot().condenser!.partial, isFalse);
  });
}
