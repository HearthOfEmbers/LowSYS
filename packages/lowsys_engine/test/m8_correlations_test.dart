// M8 coder tests: the packed-section correlations of PHYSICS.md 6 against the VC-13 reference values
// (VC-13.1 Robbins, 13.2 Kister-Gill / G'_fl / holdup / Onda, 13.3 maldistribution and Lewis, 13.7 HETP modifiers).
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:lowsys_engine/src/data/packings_json.dart';
import 'package:lowsys_engine/src/model/packed_hydraulics.dart';
import 'package:test/test.dart';

void main() {
  test('VC-13.1 Robbins reference example: 309.83 Pa/m', () {
    final dp = PackedHydraulics.robbins(12.2, 2.03, 1000, 1.1853, 1.0, 24);
    expect(dp, closeTo(309.8307, 0.01));
    expect(dp * 2, closeTo(619.661, 0.02));
  });

  test('VC-13.2 Kister-Gill flood dP for F_p 20 / 27 / 34 / 56 / 65', () {
    final ref = {20.0: 765.17, 27.0: 944.04, 34.0: 1109.36, 56.0: 1573.14, 65.0: 1746.13};
    ref.forEach((fp, v) => expect(PackedHydraulics.kisterGillFloodDp(fp), closeTo(v, 0.1)));
  });

  group('B-T loads in a 1.2 m column (L\' 2.088, G\' 3.132, rho 800 / 2.9, sigma 0.020, mu 0.27 cP)', () {
    final rows = {
      'struct250': (148.66, 6.2390, 0.5020, 0.04070, 0.8858),
      'pall50m': (204.75, 5.7125, 0.5483, 0.02283, 0.9471),
      'pall25m': (469.71, 4.4823, 0.6987, 0.03605, 0.9023),
      'raschig50c': (570.62, 4.2493, 0.7371, 0.02137, 0.9284),
      'struct500': (263.13, 5.3117, 0.5896, 0.06467, 0.8178),
    };
    rows.forEach((id, r) {
      test(id, () {
        final p = PackingData.byId(id);
        const lp = 2.088, gp = 3.132, mu = 0.27e-3;
        final dp = PackedHydraulics.robbins(lp, gp, 800, 2.9, 0.27, p.fp);
        expect(dp, closeTo(r.$1, 0.005 * r.$1));
        final gfl = PackedHydraulics.floodFlux(lp / gp, 800, 2.9, 0.27, p.fp);
        expect(gfl, closeTo(r.$2, 0.001 * r.$2));
        expect(gp / gfl, closeTo(r.$3, 0.005));
        expect(PackedHydraulics.holdup(mu, p.a, lp / 800, 800, gp / gfl), closeTo(r.$4, 1e-4));
        expect(PackedHydraulics.ondaWetFraction(lp, p.a, 800, mu, 0.020, p.sigmaC), closeTo(r.$5, 1e-4));
      });
    });
  });

  test('struct250 along the flood line (L\'/G\' = 0.6667): dP/H, h_L and g(phi)', () {
    final p = PackingData.byId('struct250');
    final gfl = PackedHydraulics.floodFlux(0.6667, 800, 2.9, 0.27, p.fp);
    final dp = {0.5: 147.41, 0.7: 305.55, 0.8: 416.57, 0.9: 562.10, 0.95: 654.32, 1.0: 765.17, 1.05: 900.97};
    final hl = {0.5: 0.04064, 0.7: 0.04599, 0.8: 0.05066, 0.9: 0.06451, 0.95: 0.08133, 1.0: 0.11263, 1.05: 0.16979};
    final g = {0.5: 1.0, 0.7: 1.0, 0.8: 1.0, 0.9: 1.08, 0.95: 1.18, 1.0: 1.32, 1.05: 1.47};
    for (final phi in dp.keys) {
      final gp = phi * gfl;
      expect(PackedHydraulics.robbins(0.6667 * gp, gp, 800, 2.9, 0.27, p.fp), closeTo(dp[phi]!, 1e-3 * dp[phi]!), reason: 'dP at $phi');
      final uL = 0.6667 * gp / 800;
      expect(PackedHydraulics.holdup(0.27e-3, p.a, uL, 800, phi), closeTo(hl[phi]!, 1e-3 * hl[phi]!), reason: 'h_L at $phi');
      expect(PackedHydraulics.loadingFactor(phi), closeTo(g[phi]!, 1e-3));
    }
    // between phi 0.8 and 1.0 the dP rises 1.84x for 1.25x the vapour flux (G^2 alone gives 1.56x)
    expect(765.17 / 416.57, closeTo(1.84, 0.01));
  });

  test('VC-13.3 maldistribution table', () {
    // S, n, f, Phi_K uniform, Phi_mal, n_eff, E_O
    const rows = [
      (1.0, 10.0, 0.2, 0.90909, 0.87505, 7.003, 0.7003),
      (1.0, 10.0, 0.4, 0.90909, 0.79421, 3.859, 0.3859),
      (1.0, 20.0, 0.2, 0.95238, 0.89685, 8.694, 0.4347),
      (1.0, 20.0, 0.4, 0.95238, 0.79982, 3.996, 0.1998),
      (1.5, 10.0, 0.4, 0.99415, 0.95597, 5.200, 0.5200),
      (0.7, 10.0, 0.4, 0.69395, 0.63859, 3.969, 0.3969),
      (1.0, 5.0, 0.4, 0.83333, 0.75958, 3.159, 0.6319),
      (1.2, 20.0, 0.3, 0.99556, 0.93856, 6.943, 0.3471),
      (1.0, 9.0, 0.3, 0.90000, 0.83391, 5.021, 0.5579),
      (1.0, 9.0, 0.6, 0.90000, 0.69722, 2.303, 0.2559),
      (1.0, 8.5, 0.4, 0.89474, 0.78990, 3.760, 0.4423),
    ];
    for (final r in rows) {
      expect(Maldistribution.kremser(r.$1, r.$2), closeTo(r.$4, 1e-4));
      final pm = Maldistribution.phiMal(r.$1, r.$2, r.$3);
      expect(pm, closeTo(r.$5, 1e-4));
      expect(Maldistribution.nEff(r.$1, pm), closeTo(r.$6, 1e-3));
      expect(Maldistribution.eMal(r.$1, r.$2, r.$3), closeTo(r.$7, 1e-4));
    }
    // shape: E_mal falls with n and with f, lowest near S = 1
    expect(Maldistribution.eMal(1, 20, 0.2), lessThan(Maldistribution.eMal(1, 10, 0.2)));
    expect(Maldistribution.eMal(1, 10, 0.4), lessThan(Maldistribution.eMal(1, 10, 0.2)));
    expect(Maldistribution.eMal(1, 10, 0.4), lessThan(Maldistribution.eMal(1.5, 10, 0.4)));
    expect(Maldistribution.eMal(1, 10, 0.0), 1.0);
    // f -> 1: the B half carries no liquid, Phi_K = 1
    expect(Maldistribution.eMal(1.0, 9.0, 0.95).isFinite, isTrue);
  });

  test('Lewis relation (4.3) and its inverse', () {
    expect(PackedHydraulics.lewisEO(0.5, 0.5), closeTo(0.41504, 1e-5));
    expect(PackedHydraulics.lewisEO(0.7, 1.5), closeTo(0.74015, 1e-5));
    expect(PackedHydraulics.lewisEO(0.5, 2.0), closeTo(0.58496, 1e-5));
    for (final lam in [0.3, 0.9, 1.0, 1.7, 4.0]) {
      final emv = PackedHydraulics.lewisEMV(0.62, lam);
      expect(PackedHydraulics.lewisEO(emv, lam), closeTo(0.62, 1e-9));
    }
  });

  test('VC-13.7 wetting factor max(1, a_w,ref/a_w) and the structured HETP rule', () {
    final p = PackingData.byId('struct250');
    const mu = 0.27e-3;
    final wet = {0.25: 0.60480, 0.5: 0.70623, 1.0: 0.80138, 2.088: 0.88581, 4.0: 0.94005};
    wet.forEach((lp, v) => expect(PackedHydraulics.ondaWetFraction(lp, p.a, 800, mu, 0.020, p.sigmaC), closeTo(v, 1e-5)));
    final fac = {0.25: 1.46463, 0.5: 1.25427, 1.0: 1.10535, 2.088: 1.0, 4.0: 1.0};
    fac.forEach((lp, v) => expect(PackedHydraulics.wettingFactor(lp, 2.088, p.a, 800, mu, 0.020, p.sigmaC), closeTo(v, 1e-5)));
    expect(PackedHydraulics.wettingFactor(1.0, null, p.a, 800, mu, 0.020, p.sigmaC), 1.0);
    // Kister's structured rule: HETP[in] = 1200/a[ft2/ft3] + 4
    double rule(double a) => (1200 / (a / 3.28084) + 4) * 0.0254;
    expect(rule(250), closeTo(0.5016, 1e-4));
    expect(rule(500), closeTo(0.3016, 1e-4));
  });

  test('packing table and segmentation', () {
    expect(PackingData.all.map((p) => p.id), ['pall25m', 'pall50m', 'raschig50c', 'struct250', 'struct500']);
    expect(PackingData.byId('struct250').hetpRef, 0.50);
    expect(PackingData.byId('struct250').rhoBed, closeTo(7900 * 0.02, 1e-9));
    expect(const PackedSection(bedHeight: 4.5, packingId: 'struct250').stageCount, 9);
    expect(const PackedSection(bedHeight: 4.05, packingId: 'struct250').stageCount, 8);
    expect(const PackedSection(bedHeight: 4.5, packingId: 'pall50m').stageCount, 5);
    expect(const PackedSection(bedHeight: 0.5, packingId: 'pall50m').stageCount, 1);
    // JSON round trip
    final s = SectionConfig.fromJson({'kind': 'packed', 'bedHeight': 4.5, 'packingId': 'struct250', 'diameter': 1.0, 'designLiquidFlux': 1.9});
    expect(s, isA<PackedSection>());
    expect((s as PackedSection).toJson()['designLiquidFlux'], 1.9);
    expect(math.pi * 1.0 * 1.0 / 4, closeTo(s.area, 1e-12));
  });
}
