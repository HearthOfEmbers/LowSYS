// M7 coder benchmark: VC-19, 40 trays x 7 components in Tier 3 (JIT numbers; the release target is 100 us).
import 'dart:typed_data';
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

void main() {
  test('40 trays x 7 components Tier 3: step time and finite state', () {
    var cfg = Presets.byId('debut');
    cfg = cfg.copyWith(
      components: ['propane', 'isobutane', 'nbutane', 'isopentane', 'npentane', 'nhexane', 'nheptane'],
      keys: const KeyComponents(2, 3),
      feeds: [
        cfg.feeds.first.copyWith(stage: 20, z: Float64List.fromList([0.05, 0.15, 0.25, 0.20, 0.15, 0.12, 0.08]))
      ],
    ).withTrays(40, feedStage: 20);
    final sim = Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
    sim.advance(60);
    final sw = Stopwatch()..start();
    const n = 2000;
    sim.advance(n * 0.5);
    sw.stop();
    final us = sw.elapsedMicroseconds / n;
    // ignore: avoid_print
    print('VC-19 40x7 Tier 3: ${us.toStringAsFixed(1)} us/step (JIT, includes the control layers)');
    expect(sim.snapshot().kpis.pTop.isFinite, isTrue);
    expect(us, lessThan(1000));
  });
}
