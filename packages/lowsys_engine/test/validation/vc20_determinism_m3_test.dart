// VC-20.3–20.6: PRNG vectors, save/restore with noise and faults, noise-on
// reproducibility and stream independence, noise-on steady indicator.
library;

import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';
import 'reference/prng_reference.dart' as ref;
import 'reference/validation_expectations_m3.dart';

void main() {
  group('VC-20.3 PRNG vectors (xoshiro128**)', () {
    test('FNV-1a-32', () {
      expect(fnv1a32(''), vc203.fnvEmpty);
      expect(fnv1a32('a'), vc203.fnvA);
      expect(fnv1a32('FT-102'), vc203.fnvFt102);
    });
    test('stream (1, "FT-102") next32 after warm-up', () {
      final g = Rng.stream(1, 'FT-102');
      for (final v in vc203.next32) {
        expect(g.next32(), v);
      }
    });
    test('uniform and normal', () {
      final g = Rng.stream(1, 'FT-102');
      expect(g.uniform(), closeTo(vc203.uniform, 1e-15));
      expect(g.normal(), closeTo(vc203.normal1, 1e-15));
      expect(g.normal(), closeTo(vc203.normal2, 1e-15));
      final d = Rng.stream(42, 'drill');
      expect(d.uniform(), closeTo(vc203.drillUniform1, 1e-15));
      expect(d.uniform(), closeTo(vc203.drillUniform2, 1e-15));
    });
    test('engine stream equals the independent reference for 10 000 outputs',
        () {
      final a = Rng.stream(123, 'inst:LT-101:s');
      final b = ref.Xoshiro128ss.stream(123, 'inst:LT-101:s');
      for (var i = 0; i < 10000; i++) {
        expect(a.next32(), b.next32(), reason: 'output $i');
      }
    });
    test('1e6 normals from (7, "stats"): mean ±0.003, variance 1 ± 0.005', () {
      final g = Rng.stream(7, 'stats');
      var s = 0.0, s2 = 0.0;
      for (var i = 0; i < 1000000; i++) {
        final v = g.normal();
        s += v;
        s2 += v * v;
      }
      final m = s / 1e6;
      expect(m, closeTo(0, 0.003));
      expect(s2 / 1e6 - m * m, closeTo(1, 0.005));
    });
  });

  test(
      'VC-20.4 save/restore with noise, a ramping plugged FT-102 and an unacknowledged alarm',
      () {
    final sim = steadyT1(noise: true, seed: 5);
    injectInstrumentFault(sim, 'FT-102', 'plugged',
        severity: 1.0, ramp: 300, onset: sim.time + 900);
    sim.setLever('drumLevelSp', 86); // drive an LT-101.HI alarm
    sim.advance(1800);
    expect(
        sim.snapshot().alarms.any((a) => a.state == AlarmState.unack), isTrue);
    final saved = jsonEncode(sim.saveState());
    final copy = Simulator.restore(jsonDecode(saved) as Map<String, Object?>);
    sim.advance(1800);
    copy.advance(1800);
    expect(jsonEncode(copy.saveState()), equals(jsonEncode(sim.saveState())));
  });

  group('VC-20.5 noise-on reproducibility and stream independence', () {
    List<double> ft102Series(int seed, {void Function(Simulator)? extra}) {
      final sim = steadyT1(noise: true, seed: seed);
      extra?.call(sim);
      return sampleReadings(sim, 'FT-102', 600);
    }

    test('same seed bit-identical; seeds 1 and 2 differ', () {
      final a = ft102Series(1), b = ft102Series(1), c = ft102Series(2);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
    test('a fault on FT-101 or spiking on TI-107 leaves FT-102 bit-identical',
        () {
      final base = ft102Series(1);
      final withFt101 = ft102Series(1,
          extra: (s) =>
              injectInstrumentFault(s, 'FT-101', 'bias', severity: 0.5));
      expect(withFt101, equals(base));
      // TI-107 exists only in Tier 2; use PDT-101 spiking in Tier 1 as the independent stream
      final withSpike = ft102Series(1,
          extra: (s) =>
              injectInstrumentFault(s, 'PDT-101', 'spiking', severity: 0.5));
      expect(withSpike, equals(base));
    });
  });

  group('VC-20.6 steady indicator with noise on', () {
    test(
        'turns green within 60 min, stays ≥ 95 % over 2 h, false within 10 min of a +10 % reflux step',
        () {
      final sim = steadyT1(noise: true, seed: 3);
      final tGreen = firstTime(sim, 3600, (s) => s.steady.isSteady, sample: 60);
      expect(tGreen, isNotNull, reason: 'never steady within 60 min');
      final frac = fractionOf(sim, 7200, (s) => s.steady.isSteady, sample: 60);
      expect(frac, greaterThanOrEqualTo(0.95));
      sim.setLever('refluxFlow', 110 * kmolh);
      final tFalse = firstTime(sim, 600, (s) => !s.steady.isSteady, sample: 60);
      expect(tFalse, isNotNull);
    });
    test(
        'run-to-steady with noise on returns the noise-off state and leaves noise on',
        () {
      final sim = steadyT1(noise: true, seed: 3);
      sim.advance(600);
      sim.setLever('refluxFlow', 110 * kmolh);
      final r = sim.runToSteadyState();
      expect(r.reached, isTrue);
      expect(prof(sim).xD, closeTo(0.993373, 1e-5));
      expect(sim.lever('noise'), 1);
    });
  });
}
