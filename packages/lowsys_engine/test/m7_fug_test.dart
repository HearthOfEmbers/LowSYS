// M7 coder tests: FUG module (PHYSICS.md 14.3, VALIDATION.md VC-9.1, 9.2, 9.7).
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

Float64List _f(List<double> v) => Float64List.fromList(v);

void main() {
  test('VC-9.1 debutanizer design: N_min, theta, R_min, N, Kirkbride, D', () {
    final r = FugCalculator.core(
        alpha: _f([5.180, 2.628, 2.041, 1.0, 0.843, 0.385]),
        z: _f([0.05, 0.15, 0.25, 0.20, 0.20, 0.15]),
        lk: 2,
        hk: 3,
        rLK: 0.98,
        rHK: 0.98,
        q: 1,
        f: 100,
        rOverRmin: 1.3);
    expect(r.valid, isTrue);
    expect(r.nMin, closeTo(10.9100, 1e-3));
    expect(r.theta, closeTo(1.31112, 1e-4));
    expect(r.rMin, closeTo(1.3073, 1e-3));
    expect(r.r, closeTo(1.6996, 1e-3));
    expect(r.x, closeTo(0.14528, 1e-4));
    expect(r.y, closeTo(0.50951, 1e-4));
    expect(r.nGilliland, closeTo(23.282, 5e-3));
    expect(r.nrOverNs, closeTo(1.0042, 1e-3));
    expect(r.d.fold<double>(0, (a, b) => a + b), closeTo(44.9437, 1e-3));
    expect(r.d[0], closeTo(5.0, 1e-3));
    expect(r.d[1], closeTo(14.9806, 1e-3));
    expect(r.b[5], closeTo(15.0, 1e-3));
    expect(r.xD[2], closeTo(0.54513, 1e-4));
  });

  test('VC-9.2 depropanizer design', () {
    final r = FugCalculator.core(
        alpha: _f([2.172, 1.0, 0.747, 0.378, 0.330, 0.157]),
        z: _f([0.30, 0.20, 0.25, 0.10, 0.10, 0.05]),
        lk: 0,
        hk: 1,
        rLK: 0.99,
        rHK: 0.95,
        q: 1,
        f: 100,
        rOverRmin: 1.3);
    expect(r.nMin, closeTo(9.7203, 1e-3));
    expect(r.theta, closeTo(1.40567, 1e-4));
    expect(r.rMin, closeTo(1.6522, 1e-3));
    expect(r.nGilliland, closeTo(20.364, 5e-3));
    expect(r.nrOverNs, closeTo(0.4740, 1e-3));
    expect(r.d.fold<double>(0, (a, b) => a + b), closeTo(30.7771, 1e-3));
  });

  test('guards: non-adjacent keys, no split, R = R_min', () {
    final a = _f([5.180, 2.628, 2.041, 1.0, 0.843, 0.385]);
    final z = _f([0.05, 0.15, 0.25, 0.20, 0.20, 0.15]);
    final bad = FugCalculator.core(alpha: a, z: z, lk: 1, hk: 3, rLK: 0.98, rHK: 0.98, q: 1, f: 100, rOverRmin: 1.3);
    expect(bad.valid, isFalse);
    expect(bad.reason, FugInvalidReason.notAdjacent);
    final half = FugCalculator.core(alpha: a, z: z, lk: 2, hk: 3, rLK: 0.5, rHK: 0.98, q: 1, f: 100, rOverRmin: 1.3);
    expect(half.valid, isFalse);
    expect(half.reason, FugInvalidReason.noSplit);
    final zero = FugCalculator.core(alpha: a, z: z, lk: 2, hk: 3, rLK: 0.98, rHK: 0.98, q: 1, f: 0, rOverRmin: 1.3);
    expect(zero.valid, isFalse);
    final atMin = FugCalculator.core(alpha: a, z: z, lk: 2, hk: 3, rLK: 0.98, rHK: 0.98, q: 1, f: 100, rOverRmin: 1.0);
    expect(atMin.valid, isTrue);
    expect(atMin.belowRmin, isTrue);
    expect(atMin.nGilliland, double.infinity);
  });

  group('live panel on the debut default (VC-9.7)', () {
    late Simulator sim;
    late SimSnapshot snap;
    setUpAll(() {
      sim = Simulator(Presets.byId('debut'), options: const SimOptions(seed: 3), warmStart: false);
      expect(sim.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
      snap = sim.snapshot();
    });

    test('live mode', () {
      final r = const FugCalculator().compute(snap, sim.config.effectiveKeys, thermo: sim.thermo)!;
      expect(r.valid, isTrue);
      expect(r.alpha[0], closeTo(5.1968, 0.01));
      expect(r.alpha[1], closeTo(2.6337, 0.01));
      expect(r.alpha[2], closeTo(2.0438, 0.01));
      expect(r.nMin, closeTo(10.639, 0.15));
      expect(r.theta, closeTo(1.3115, 1e-3));
      expect(r.rMin, closeTo(1.2974, 5e-3));
      expect(r.r, closeTo(1.6999, 5e-3));
      expect(r.nGilliland, closeTo(22.56, 0.3));
      expect(r.nrOverNs, closeTo(1.007, 0.01));
      expect(r.nR, closeTo(11.32, 0.3));
      expect(r.nActual, closeTo(23.40, 1e-6));
      expect(r.nRActual, closeTo(10.50, 1e-6));
    });

    test('targets 98 / 98 with the live R', () {
      final r = const FugCalculator()
          .compute(snap, sim.config.effectiveKeys, targets: const FugTargets(0.98, 0.98), thermo: sim.thermo)!;
      expect(r.nMin, closeTo(10.889, 0.15));
      expect(r.rMin, closeTo(1.3030, 5e-3));
      expect(r.nGilliland, closeTo(23.16, 0.3));
    });

    test('wrong keys (isobutane / isopentane): keys must be adjacent', () {
      final r = const FugCalculator().compute(snap, const KeyComponents(1, 3), thermo: sim.thermo)!;
      expect(r.valid, isFalse);
      expect(r.reason, FugInvalidReason.notAdjacent);
    });

    test('plant view: no result', () {
      sim.setLever('view', 1);
      final p = sim.snapshot();
      expect(const FugCalculator().compute(p, sim.config.effectiveKeys, thermo: sim.thermo), isNull);
      sim.setLever('view', 0);
    });
  });

  test('deprop default, live (VC-9.7)', () {
    final sim = Simulator(Presets.byId('deprop'), options: const SimOptions(seed: 3), warmStart: false);
    expect(sim.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
    final r = const FugCalculator().compute(sim.snapshot(), sim.config.effectiveKeys, thermo: sim.thermo)!;
    expect(r.nMin, closeTo(9.886, 0.15));
    expect(r.rMin, closeTo(1.6628, 5e-3));
    expect(r.nGilliland, closeTo(20.83, 0.3));
    expect(r.nActual, closeTo(20.60, 1e-6));
    expect(r.nRActual, closeTo(7.00, 1e-6));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
