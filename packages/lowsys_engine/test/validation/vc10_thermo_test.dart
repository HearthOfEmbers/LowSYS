// VC-10 thermodynamic spot values (Tier 2 parts: 10.1, 10.2, 10.3, 10.7
// Rackett/Pitzer/Watson, 10.8 solver robustness).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m4.dart';
import 'reference/thermo_reference.dart' as ref;
import 'reference/validation_expectations_m4.dart';

void main() {
  final db = ComponentDb.load();

  test('VC-10.1 normal boiling points from the vapour-pressure models', () {
    for (final (id, tbC) in vc101) {
      final c = db[id];
      final tb =
          ref.bisect((t) => c.vaporPressure(t) - 101325, 200, 0.98 * c.tc);
      expect(tb - 273.15, closeTo(tbC, 0.005), reason: id);
    }
  });

  test('VC-10.2 water: P_sat and saturation temperatures', () {
    final w = db['water'];
    expect(
        w.vaporPressure(298.15), closeTo(vc102.psat25, 0.0005 * vc102.psat25));
    expect(w.vaporPressure(423.15),
        closeTo(vc102.psat150, 0.0005 * vc102.psat150));
    for (final (barG, tC) in vc102.tsatBarG) {
      expect(WaterProps.saturationT(barG * 1e5 + 101325) - 273.15,
          closeTo(tC, 0.01),
          reason: '$barG bar(g)');
    }
  });

  group('VC-10.3 B-T bubble points at 1 atm (Raoult)', () {
    final m = thermoOf(btT2());
    for (final (x, tC, y, al) in vc103) {
      test('x = $x', () {
        final (t, yb) = bubble(m, 101325, x);
        expect(t - 273.15, closeTo(tC, 0.002));
        expect(yb, closeTo(y, 1e-5));
        final k = Float64List(2);
        m.kValues(t, 101325, Float64List.fromList([x, 1 - x]), k);
        expect(k[0] / k[1], closeTo(al, 1e-4));
      });
    }
    test('pressure effect at x = 0.5', () {
      for (final (p, tC, al) in vc103Pressure) {
        final (t, _) = bubble(m, p, 0.5);
        expect(t - 273.15, closeTo(tC, 0.002), reason: '$p Pa');
        final k = Float64List(2);
        m.kValues(t, p, Float64List.fromList([0.5, 0.5]), k);
        expect(k[0] / k[1], closeTo(al, 1e-4), reason: '$p Pa');
      }
    });
    test(
        'engine bubble points equal the independent Raoult reference on a grid',
        () {
      for (final p in [0.5e5, 1.01325e5, 3e5]) {
        for (var x = 0.0; x <= 1.0; x += 0.125) {
          final (t, _) = bubble(m, p, x);
          expect(t, closeTo(ref.bt.bubbleT(p, x), 1e-4), reason: 'x=$x p=$p');
        }
      }
    });
  });

  group('VC-10.7 property correlations', () {
    final m = thermoOf(btT2());
    test('Rackett densities', () {
      expect(db['benzene'].liquidDensity(353.15),
          closeTo(vc107.rhoBenzene80, 0.1));
      expect(db['toluene'].liquidDensity(383.15),
          closeTo(vc107.rhoToluene110, 0.1));
      expect(
          db['water'].liquidDensity(373.15), closeTo(vc107.rhoWater100, 0.1));
    });
    test('Pitzer Z of saturated benzene vapour at 1 atm', () {
      final rho =
          m.vaporDensity(353.15, 101325, Float64List.fromList([1.0, 0.0]));
      final z = 101325 * 78.11e-3 / (rho * 8.314462618 * 353.15);
      expect(z, closeTo(vc107.zBenzeneSat, 1e-4));
    });
    test(
        'Watson ΔH_vap of benzene at 298.15 K = 33.58 kJ/mol; enthalpies follow §3.3',
        () {
      final x = Float64List.fromList([1.0, 0.0]);
      expect((m.hV(298.15, x) - m.hL(298.15, x)) / 1000,
          closeTo(vc107.watsonBenzene298, 0.01));
      expect(m.hL(298.15, x), closeTo(0, 1e-9), reason: 'reference state');
      expect((m.hV(353.24, x) - m.hL(353.24, x)) / 1000, closeTo(30.72, 1e-6));
      for (final t in [320.0, 353.15, 380.0]) {
        expect(m.hL(t, x), closeTo(ref.benzene.hL(t), 1e-6),
            reason: 'h_L at $t');
        expect(m.hV(t, x), closeTo(ref.benzene.hV(t), 1e-6),
            reason: 'h_V at $t');
      }
    });
  });

  test(
      'VC-10.8 bubble-point robustness: 1000 random (x, P) in the B-T lever range',
      () {
    final m = thermoOf(btT2());
    final rng = math.Random(42);
    var fallbacks = 0;
    for (var i = 0; i < 1000; i++) {
      final x = rng.nextDouble();
      final p = 0.2e5 + rng.nextDouble() * 4.8e5;
      final xs = Float64List.fromList([x, 1 - x]);
      final y = Float64List(2), k = Float64List(2);
      final h = SolverHealth();
      final t = m.bubbleT(p, xs, 300, y, k, h);
      fallbacks += h.bubbleFallbacks;
      expect((k[0] * x + k[1] * (1 - x) - 1).abs(), lessThan(1e-9),
          reason: 'ΣKx at x=$x p=$p');
      expect(t, closeTo(ref.bt.bubbleT(p, x), 1e-6));
    }
    expect(fallbacks, lessThanOrEqualTo(10), reason: '≥ 99 % without fallback');
  });

  test('VC-27.1 methanol–water Raoult bubble points agree with the reference',
      () {
    final m = thermoOf(mwT2());
    for (var x = 0.0; x <= 1.0; x += 0.1) {
      final (t, y) = bubble(m, 101325, x);
      expect(t, closeTo(ref.mw.bubbleT(101325, x), 1e-4), reason: 'x=$x');
      expect(y, closeTo(ref.mw.yEq(101325, x), 1e-6), reason: 'x=$x');
    }
  });
}
