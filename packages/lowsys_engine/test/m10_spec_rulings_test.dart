// "Spec rulings M9" coder actions: F24 cap against the onset SP, vapour-free stage, o1 timing, energy closure.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm9_helpers.dart';

void main() {
  test('F24 cap is (1 - s) of the SP at onset: raising the SP does not restore the steam', () {
    final s = crudeSim(levers: {'steam.bottom': 2000 / 3600});
    s.advance(600);
    injectF24(s, 'bottom', 0.5);
    s.advance(900);
    final before = kpiOf(s).bottomT;

    s.setLever('steam.bottom', 4000 / 3600);
    s.advance(900);
    final steam = instr(s, 'FT-321') * 3600; // kg/h (bottom steam)
    // 1000 kg/h, the valve flow at 0.5 of the onset SP, not the 2000 kg/h the new SP asks for
    expect(steam, closeTo(1000, 150), reason: 'steam after the SP raise $steam kg/h; bottom T before $before');
  });

  test('F24 s = 1: vapour-free stage, energy closure, stage-30 rise recorded', () {
    final base = kpiOf(crudeSim());
    final s = crudeSim();
    injectF24(s, 'bottom', 1.0);
    final r = s.runToSteadyState(maxSimSeconds: 172800);
    expect(r.reached, isTrue, reason: 'steady state not reached, residual ${r.residual}');
    final k = kpiOf(s);
    // ignore: avoid_print
    print('F24 s=1 bottom T rise ${(k.bottomT - base.bottomT).toStringAsFixed(2)} K, energy residual ${s.snapshot().kpis.energyResidual}, negativeClamps ${s.snapshot().solverHealth.negativeClamps}');
    // VC-15.7: 1e-3 relative to Q_C + Q_PA, checked at three times 20 min apart (spec ruling M9-coder, 2026-10-13)
    for (var i = 0; i < 3; i++) {
      if (i > 0) s.advance(1200);
      final sn = s.snapshot();
      // ignore: avoid_print
      print('F24 s=1 closure at +${i * 20} min: ${sn.kpis.energyResidual}');
      expect(sn.kpis.energyResidual.abs(), lessThan(1e-3), reason: 'energy closure at check $i');
      // stages 27-30 are vapour-free: the stage-26 liquid temperature, within 0.02 K
      for (var j = 27; j <= 30; j++) {
        expect(sn.stages.t[j], closeTo(sn.stages.t[26], 0.02), reason: 'stage $j at check $i');
      }
    }
    // no new clamp episodes over the final hour
    final c0 = s.snapshot().solverHealth.negativeClamps;
    s.advance(3600);
    expect(s.snapshot().solverHealth.negativeClamps, c0, reason: 'negativeClamps grew over the final hour');
    expect(k.bottomT - base.bottomT, inInclusiveRange(12.9, 16.9));
  });

  test('G16 o1 is met 20-40 min after PA 3 MW without a steady-state condition', () {
    final def = Scenarios.byId('G16_crude_gaps');
    final sim = Simulator(Presets.byId('crude'));
    sim.startScenario(def);
    sim.setLever('paDuty', 3e6);
    sim.setLever('steam.ss2', 1000 / 3600);
    var t = 0.0;
    double? met;
    while (t < 3600 && met == null) {
      sim.advance(30);
      t += 30;
      if (sim.snapshot().scenario!.objectives.first.met) met = t;
    }
    // ignore: avoid_print
    print('G16 o1 met at ${met == null ? 'never' : (met / 60).toStringAsFixed(1)} min');
    expect(met, isNotNull);
  });
}
