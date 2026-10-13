// M6 drills H1 to H5: each starts, draws a candidate, injects it at the onset and runs for an hour with noise on,
// without a solver failure; the snapshot carries no fault data and the plant views mask the truth.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final id in ['H1_creeping_dp', 'H2_pressure', 'H3_lost_separation', 'H4_reboiler', 'H5_bottoms_swings']) {
    test('$id runs with four seeds', () {
      final def = Scenarios.byId(id);
      final drawn = <String>{};
      for (final seed in [1, 3, 6, 7]) {
        final sim = Simulator(Presets.byId('bt'), options: SimOptions(seed: seed), warmStart: false);
        sim.startScenario(def, seed: seed);
        drawn.add(DrillDraw.draw(def, seed).candidateId);
        sim.advance(3000);
        expect(sim.halted, isFalse, reason: '$id seed $seed');
        final s = sim.snapshot();
        expect(s.visibleFaults, isEmpty);
        expect(s.kpis.pTop.isFinite, isTrue);
        expect(s.scenario, isNotNull);
        if (def.view != 'model') {
          expect(s.stages.x[3].isNaN, isTrue);
          expect(s.view.isPlant, isTrue);
        }
        if (id == 'H5_bottoms_swings') expect(s.reboiler.type, ReboilerType.thermosyphon);
      }
      // ignore: avoid_print
      print('$id candidates drawn for seeds 1, 3, 6, 7: $drawn');
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
