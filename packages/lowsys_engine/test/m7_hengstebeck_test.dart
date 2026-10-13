// M7 coder tests: Hengstebeck pseudo-binary McCabe-Thiele data (PHYSICS.md 14.2, VALIDATION.md VC-9.3, VC-9.6).
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

const _kmolh = 1000 / 3600;

void main() {
  test('Tier 1, VC-9.3 column (22 trays, feed 12, E 1): stage points lie on the alpha-prime curve', () {
    var cfg = Presets.byId('debut').copyWith(tier: ThermoTier.t1, murphree: 1.0);
    cfg = cfg.withTrays(22, feedStage: 12);
    cfg = cfg.copyWith(initialLevers: {...cfg.initialLevers, 'refluxFlow': 76.39 * _kmolh, 'boilup': 121.33 * _kmolh});
    final sim = Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
    expect(sim.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
    final s = sim.snapshot();
    expect(s.kpis.recoveryLK!, closeTo(0.9843, 0.003));
    expect(s.kpis.recoveryHK!, closeTo(0.9849, 0.003));
    final d = McCabeThieleBuilder().build(s, sim.thermo, showRmin: true, keys: cfg.keys);
    expect(d.pseudoBinary, isTrue);
    expect(d.available, isTrue);
    expect(d.lightLabel, 'n-Butane');
    expect(d.heavyLabel, 'Isopentane');
    expect(d.xD, closeTo(0.98784, 2e-3));
    expect(d.xB, closeTo(0.01955, 2e-3));
    expect(d.corners[11].x, closeTo(0.56314, 3e-3)); // tray 12 is corners[11]
    expect(d.cmoRectifying, isEmpty);
    expect(d.cmoStripping, isEmpty);
    expect(d.rmin, isNull);
    expect(d.equilibriumBottom, isNull);
    expect(d.equilibriumTop.length, 101);
    const a = 2.041 / 1.0;
    for (final p in d.localEquilibrium) {
      expect(p.y, closeTo(a * p.x / (1 + (a - 1) * p.x), 1e-6));
    }
    expect(d.alphaPrimeTop, closeTo(a, 1e-9));
  });

  test('Tier 3 debut default: x-prime values and alpha-prime at top and bottom (VC-9.6)', () {
    final sim = Simulator(Presets.byId('debut'), options: const SimOptions(seed: 3), warmStart: false);
    expect(sim.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
    final s = sim.snapshot();
    final d = McCabeThieleBuilder().build(s, sim.thermo, showRmin: true, keys: sim.config.keys);
    expect(d.pseudoBinary, isTrue);
    expect(d.xF, closeTo(0.55556, 5e-4));
    expect(d.xD, closeTo(0.98253, 5e-4));
    expect(d.xB, closeTo(0.02723, 5e-4));
    expect(d.alphaPrimeTop, closeTo(2.2157, 0.002));
    expect(d.alphaPrimeBottom, closeTo(1.8853, 0.002));
    expect(d.rmin, isNull);
    expect(d.equilibriumBottom, isNull);
    expect(d.localEquilibrium.length, 33);
    for (var i = 1; i < d.equilibriumTop.length; i++) {
      expect(d.equilibriumTop[i].x, greaterThanOrEqualTo(d.equilibriumTop[i - 1].x));
    }
    expect(d.qLine, isNotNull);
    expect(d.qLine!.a.x, closeTo(d.xF, 1e-9));
    expect(d.qLine!.b.y, closeTo(1.0, 1e-9)); // q = 1: vertical, clipped to the frame
    expect(d.staircase.first.x, closeTo(d.xD, 1e-12));
    expect(d.staircase.last.x, closeTo(d.xB, 1e-12));
    // plant view: unavailable
    sim.setLever('view', 1);
    final p = McCabeThieleBuilder().build(sim.snapshot(), sim.thermo, keys: sim.config.keys);
    expect(p.available, isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
