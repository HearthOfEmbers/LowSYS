// M7 coder tests: explain lines eq.fug.* and eq.hengstebeck (VC-21): values equal the engine's own numbers, ids are
// in the PHYSICS.md 15 catalogue, every line has TeX.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

void main() {
  late Simulator sim;
  setUpAll(() {
    sim = Simulator(Presets.byId('debut'), options: const SimOptions(seed: 3), warmStart: false);
    sim.runToSteadyState(maxSimSeconds: 400000);
  });

  test('FUG lines: ids, TeX, values equal FugCalculator', () {
    final r = sim.explain(const ExplainFug());
    final lines = [for (final g in r.groups) ...g.lines];
    expect(lines.map((l) => l.id), [
      'eq.fug.alpha', 'eq.fug.fenske', 'eq.fug.split', 'eq.fug.underwood', 'eq.fug.gilliland', 'eq.fug.kirkbride', 'eq.fug.rigorous'
    ]);
    final f = const FugCalculator().compute(sim.snapshot(), sim.config.effectiveKeys, thermo: sim.thermo)!;
    final byId = {for (final l in lines) l.id: l};
    expect(byId['eq.fug.fenske']!.value, f.nMin);
    expect(byId['eq.fug.underwood']!.value, f.rMin);
    expect(byId['eq.fug.gilliland']!.value, f.nGilliland);
    expect(byId['eq.fug.kirkbride']!.value, f.nR);
    expect(byId['eq.fug.alpha']!.value, f.alpha[sim.config.effectiveKeys.lk]);
    for (final l in lines) {
      expect(l.texSymbolic, isNotEmpty);
      expect(l.texSubstituted, isNotEmpty);
    }
  });

  test('targets mode and the pseudo-binary line', () {
    final t = sim.explain(const ExplainFug(FugTargets(0.98, 0.98)));
    final nMin = t.groups.first.lines.firstWhere((l) => l.id == 'eq.fug.fenske').value;
    expect(nMin, closeTo(10.889, 0.15));
    final h = sim.explain(const ExplainMcCabe(McCabeElement.equilibrium));
    expect(h.groups.first.lines.single.id, 'eq.hengstebeck');
    expect(h.groups.first.lines.single.value, closeTo(2.2157, 0.005));
  });

  test('tray trace follows the light key and uses eq.depriester in Tier 3', () {
    final r = sim.explain(const ExplainStage(10));
    final lines = [for (final g in r.groups) ...g.lines];
    final snap = sim.snapshot();
    final eq = lines.firstWhere((l) => l.id == 'eq.depriester');
    final lk = sim.config.effectiveKeys.lk;
    expect((eq.value - snap.stages.yStar[10 * snap.stages.nc + lk]).abs(), lessThan(1e-12));
  });

  test('plant view: not observable', () {
    sim.setLever('view', 1);
    expect(sim.explain(const ExplainFug()).groups, isEmpty);
    sim.setLever('view', 0);
  });
}
