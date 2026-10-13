// M8 validation (engine 9eb2b6e, f1fbc23): key numbers of docs/milestones/M8.md E.3 against the spec values and an
// independent reference (reference/packed_reference.dart: the PHYSICS.md 6.3-6.6 correlations written from the text,
// and a Newton CMO column with per-stage E). Column checks recompute every packed segment's dP, phi_p, h_L, HETP,
// lambda and the bed's S and E_mal from the engine's own state (flows, x, y, T, P) with the reference correlations.
// Physical-sense and directional checks: dP vs load, HETP modifiers, flood scaling, maldistribution, F21 / F23,
// mixed columns, G15 o2, the holdup-factor lag (coder deviation 1).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/packed_reference.dart';

const _kmolh = 1000 / 3600;
const _long = Timeout(Duration(minutes: 20));
const _mu = 0.00027; // Pa s, B-T preset constant (all tiers)
const _a = 250.0, _sigmaC = 0.075, _hRef = 0.5; // struct250

final _h7Sections = [
  {'kind': 'packed', 'bedHeight': 4.5, 'packingId': 'struct250', 'diameter': 1.0, 'designLiquidFlux': 1.9},
  {'kind': 'packed', 'bedHeight': 4.5, 'packingId': 'struct250', 'diameter': 1.0, 'designLiquidFlux': 4.0},
];

Simulator _packed({String tier = 't1', String hyd = 'full', bool h7 = false, Map<String, Object?> ov = const {}}) {
  final sim = Simulator(
      Presets.byId('bt_packed').applyOverrides({'tier': tier, 'hydraulics': hyd, if (h7) 'sections': _h7Sections, ...ov}),
      options: const SimOptions(seed: 3),
      warmStart: false);
  if (h7) sim.setLever('cwInletT', 288.15);
  return sim;
}

SimSnapshot _steady(Simulator s) {
  expect(s.runToSteadyState(maxSimSeconds: 172800).reached, isTrue);
  return s.snapshot();
}

void _scaleLoad(Simulator sim, double k, {bool t2 = false}) {
  for (final lev in ['feedFlow', 'refluxFlow', t2 ? 'reboilerDuty' : 'boilup']) {
    sim.setLever(lev, sim.lever(lev) * k);
  }
}

double _rel(double a, double b) => ((a - b) / b).abs();

/// Reference recomputation of one bed from the engine state.
class _Bed {
  final List<double> dp = [], phi = [], hl = [], hetp = [], lam = [], lp = [], emv = [];
  double s = double.nan, nTh = double.nan, eMal = 1, dpSum = 0, phiMax = 0, tauKin = 0;
}

_Bed _recompute(Simulator sim, SimSnapshot s, int bed, {double crush = 0, double f = 0}) {
  final b = s.beds[bed - 1], nc = s.stages.nc, st = s.stages, th = sim.thermo;
  final t1 = s.tier == ThermoTier.t1;
  final aT = math.pi * b.diameter * b.diameter / 4, fp = 20 * (1 + 1.5 * crush);
  final hSeg = 0.5 * (1 - 0.15 * crush); // F23: H_bed (1 - 0.15 s), same segment count
  final lpDes = bed == 1 ? 1.9 : 4.0;
  const mw = [78.11, 92.14];
  final r = _Bed();
  var lnS = 0.0;
  for (var j = b.firstStage; j <= b.lastStage; j++) {
    final x = Float64List.fromList(st.x.sublist(j * nc, (j + 1) * nc)), y = Float64List.fromList(st.y.sublist(j * nc, (j + 1) * nc));
    var mwl = 0.0, mwv = 0.0;
    for (var i = 0; i < nc; i++) {
      mwl += x[i] * mw[i];
      mwv += st.y[(j + 1) * nc + i] * mw[i];
    }
    final rhoL = t1 ? 800.0 : mwl / 1000 / th.liquidMolarVolume(st.t[j], x);
    final rhoV = t1 ? 2.9 : th.vaporDensity(st.t[j], st.p[j], y);
    final sigma = t1 ? 0.020 : th.surfaceTension(st.t[j], x);
    final lp = st.liquidDown[j] * mwl / 1000 / aT, gp = st.vaporUp[j + 1] * mwv / 1000 / aT;
    final dpm = robbinsRef(lp, gp, rhoL, rhoV, _mu * 1000, fp);
    final phi = gp / floodFluxRef(lp / gp, rhoL, rhoV, _mu * 1000, fp);
    final hl = holdupRef(_mu, _a, lp / rhoL, rhoL, phi);
    final hetp = hetpRef(_hRef, lp, lpDes, _a, rhoL, _mu, sigma, _sigmaC, phi);
    // lambda_k = m_k V_k / L_k with the local alpha' (K ratio) and x'
    final ap = t1
        ? 2.5
        : () {
            final k = Float64List(nc);
            th.kValues(st.t[j], st.p[j], x, k);
            return k[0] / k[1];
          }();
    final m = ap / math.pow(1 + (ap - 1) * x[0], 2);
    final lam = (m * st.vaporUp[j] / st.liquidDown[j]).clamp(1e-3, 1e3);
    r.dp.add(dpm * hSeg);
    r.phi.add(phi);
    r.hl.add(hl);
    r.hetp.add(hetp);
    r.lam.add(lam);
    r.lp.add(lp);
    lnS += math.log(lam);
    r.dpSum += dpm * hSeg;
    r.phiMax = math.max(r.phiMax, phi);
    // kinematic-wave drainage time of the film, dM/dL = M / (3 L) per segment (factor term ignored)
    r.tauKin += hl * aT * hSeg * rhoL / (mwl / 1000) / (3 * st.liquidDown[j]);
  }
  final n = b.lastStage - b.firstStage + 1;
  r.s = math.exp(lnS / n);
  r.nTh = r.hetp.fold(0.0, (a, h) => a + math.min(1.0, hSeg / h));
  r.eMal = f == 0 ? 1.0 : maldistRef(r.s, r.nTh, f).eMal;
  for (var k = 0; k < n; k++) {
    r.emv.add(lewisEmvRef(math.min(1.0, hSeg / r.hetp[k]) * r.eMal, r.lam[k]));
  }
  return r;
}

/// Engine segment values = reference recomputation (dP 0.1 %, phi 1e-4, h_L 1e-3 rel, HETP 1e-4 rel, E_MV 1e-4).
void _matches(SimSnapshot s, int bed, _Bed r, {bool emv = true}) {
  final b = s.beds[bed - 1], st = s.stages;
  for (var j = b.firstStage, k = 0; j <= b.lastStage; j++, k++) {
    expect(_rel(st.dp[j], r.dp[k]), lessThan(1e-3), reason: 'dP seg $j: engine ${st.dp[j]} ref ${r.dp[k]}');
    expect(st.packFlood[j], closeTo(r.phi[k], 1e-4), reason: 'phi seg $j');
    expect(_rel(st.packHoldup[j], r.hl[k]), lessThan(1e-3), reason: 'h_L seg $j');
    expect(_rel(st.hetp[j], r.hetp[k]), lessThan(1e-4), reason: 'HETP seg $j');
    if (emv) expect(st.efficiency[j], closeTo(r.emv[k], 1e-4), reason: 'E_MV seg $j');
  }
  expect(_rel(b.dp, r.dpSum), lessThan(1e-3), reason: 'bed dP');
  expect(b.maxFlood, closeTo(r.phiMax, 1e-4), reason: 'bed phi max');
  expect(b.nTheoretical, closeTo(r.nTh, 1e-3), reason: 'n_th');
}

String _bedLine(SimSnapshot s, int bed, _Bed r) {
  final b = s.beds[bed - 1];
  return 'bed $bed dP ${b.dp.toStringAsFixed(1)} (ref ${r.dpSum.toStringAsFixed(1)}) Pa, phi ${b.maxFlood.toStringAsFixed(4)} '
      '(ref ${r.phiMax.toStringAsFixed(4)}), n_th ${b.nTheoretical.toStringAsFixed(3)}, S ${r.s.toStringAsFixed(4)}, '
      'E_mal ${b.eMal.toStringAsFixed(4)} (ref ${r.eMal.toStringAsFixed(4)}), lambda ${r.lam.first.toStringAsFixed(3)}..'
      '${r.lam.last.toStringAsFixed(3)}';
}

void main() {
  test('E.3 #1-11 correlations: engine = independent reference = spec', () {
    // #1 Robbins, #2 Kister-Gill
    expect(PackedHydraulics.robbins(12.2, 2.03, 1000, 1.1853, 1, 24), closeTo(309.8307, 1e-3));
    expect(robbinsRef(12.2, 2.03, 1000, 1.1853, 1, 24), closeTo(309.8307, 1e-3));
    for (final (fp, v) in [(20, 765.17), (27, 944.04), (34, 1109.36), (56, 1573.14), (65, 1746.13)]) {
      expect(PackedHydraulics.kisterGillFloodDp(fp.toDouble()), closeTo(v, 0.01));
      expect(floodDpRef(fp.toDouble()), closeTo(v, 0.01));
    }
    // #3, #4 B-T load (L' 2.088, G' 3.132, 800 / 2.9, 0.27 cP, sigma 0.020)
    for (final (fp, a, sc, dp, gfl, phi, hl, aw) in [
      (20.0, 250.0, 0.075, 148.66, 6.2390, 0.5020, 0.04070, 0.8858),
      (56.0, 205.0, 0.075, 469.71, 4.4823, 0.6987, 0.03605, 0.9023),
      (27.0, 105.0, 0.075, 204.75, 5.7125, 0.5483, 0.02283, 0.9471),
    ]) {
      final e = PackedHydraulics.floodFlux(2.088 / 3.132, 800, 2.9, 0.27, fp);
      final rf = floodFluxRef(2.088 / 3.132, 800, 2.9, 0.27, fp);
      expect(PackedHydraulics.robbins(2.088, 3.132, 800, 2.9, 0.27, fp), closeTo(dp, 0.005 * dp));
      expect(_rel(e, rf), lessThan(1e-9), reason: 'G\'_fl engine (40 bisections) = reference (1e-13)');
      expect(e, closeTo(gfl, 1e-3 * gfl));
      expect(3.132 / e, closeTo(phi, 0.005));
      expect(PackedHydraulics.holdup(_mu, a, 2.088 / 800, 800, 3.132 / e), closeTo(hl, 1e-4));
      expect(PackedHydraulics.ondaWetFraction(2.088, a, 800, _mu, 0.020, sc), closeTo(aw, 1e-4));
      expect(ondaRef(2.088, a, 800, _mu, 0.020, sc), closeTo(aw, 1e-4));
    }
    // #5, #6 struct250 flood line
    final g = floodFluxRef(2.088 / 3.132, 800, 2.9, 0.27, 20);
    for (final (phi, dp, hl, gg) in [(0.8, 416.57, 0.05066, 1.0), (0.95, 654.32, 0.08133, 1.18), (1.0, 765.17, 0.11263, 1.32)]) {
      final gp = phi * g, lp = gp * 2.088 / 3.132;
      expect(PackedHydraulics.robbins(lp, gp, 800, 2.9, 0.27, 20), closeTo(dp, 1e-3 * dp));
      expect(PackedHydraulics.holdup(_mu, 250, lp / 800, 800, phi), closeTo(hl, 1e-3 * hl));
      expect(PackedHydraulics.loadingFactor(phi), closeTo(gg, 1e-12));
      expect(holdupRef(_mu, 250, lp / 800, 800, phi), closeTo(hl, 1e-3 * hl));
    }
    // #7 wetting factor, #8 structured HETP rule (HETP[in] = 1200 / a[ft2/ft3] + 4)
    for (final (lp, v) in [(1.0, 1.10535), (0.5, 1.25427), (0.25, 1.46463), (4.0, 1.0)]) {
      expect(PackedHydraulics.wettingFactor(lp, 2.088, 250, 800, _mu, 0.020, 0.075), closeTo(v, 1e-5));
      expect(hetpRef(1, lp, 2.088, 250, 800, _mu, 0.020, 0.075, 0), closeTo(v, 1e-5));
    }
    for (final (a, h) in [(250.0, 0.5016), (500.0, 0.3016)]) {
      expect((1200 / (a * 0.3048) + 4) * 0.0254, closeTo(h, 1e-4));
    }
    // #9, #10 maldistribution, #11 Lewis
    for (final (s, n, f, em) in [(1.0, 9.0, 0.3, 0.5579), (1.0, 9.0, 0.6, 0.2559), (1.0, 8.5, 0.4, 0.4423), (1.5, 10.0, 0.4, 0.5200)]) {
      expect(Maldistribution.eMal(s, n, f), closeTo(em, 1e-4));
      expect(maldistRef(s, n, f).eMal, closeTo(em, 1e-4));
    }
    expect(maldistRef(1, 8.5, 0.4).nEff, closeTo(3.760, 1e-3));
    expect(PackedHydraulics.lewisEO(0.7, 1.5), closeTo(0.74015, 1e-5));
    expect(lewisEoRef(0.7, 1.5), closeTo(0.74015, 1e-5));
  });

  test('directional (reference): dP steepens toward flood; crushing lowers G\'_fl; phi_p scales with a ratio-preserving k; '
      'E_mal falls with n and f and is lowest near S = 1', () {
    final g20 = floodFluxRef(2 / 3, 800, 2.9, 0.27, 20);
    double slope(double phi) {
      double dp(double p) => robbinsRef(p * g20 * 2 / 3, p * g20, 800, 2.9, 0.27, 20);
      return (math.log(dp(phi * 1.001)) - math.log(dp(phi / 1.001))) / (2 * math.log(1.001));
    }

    // d ln dP / d ln G' at fixed L'/G': 2 + liquid term at low load, rising toward flood
    expect(slope(0.8), greaterThan(slope(0.5)));
    expect(slope(1.0), greaterThan(slope(0.8)));
    expect(slope(1.0), greaterThan(3));
    // F23: F_p,eff = 20 (1 + 1.5 s) lowers G'_fl at the same L'/G' (flood dP rises only as F_p^0.7)
    expect(floodFluxRef(2 / 3, 800, 2.9, 0.27, 20 * 1.45), lessThan(0.9 * g20));
    expect(floodFluxRef(2 / 3, 800, 2.9, 0.27, 20 * 1.75), lessThan(floodFluxRef(2 / 3, 800, 2.9, 0.27, 20 * 1.45)));
    // ratio-preserving throughput factor: phi_p(k) = k phi_p (G'_fl depends only on L'/G' and properties)
    expect(1.1 * 3.132 / floodFluxRef(2.088 / 3.132, 800, 2.9, 0.27, 20), closeTo(0.5522, 1e-4));
    // maldistribution shape (VC-13.3)
    expect(maldistRef(1, 20, 0.2).eMal, lessThan(maldistRef(1, 10, 0.2).eMal));
    expect(maldistRef(1, 10, 0.4).eMal, lessThan(maldistRef(1, 10, 0.2).eMal));
    expect(maldistRef(1, 10, 0.4).eMal, lessThan(maldistRef(1.5, 10, 0.4).eMal));
    expect(maldistRef(1, 10, 0.4).eMal, lessThan(maldistRef(0.7, 10, 0.4).eMal));
  });

  test('coder deviation 1 (holdup-factor lag): the explicit holdup -> L -> phi_p -> factor loop gain passes 1 just above '
      'phi_p ~ 0.9, so a period-2 cycle is expected without the lag; tau 10 s brings the per-step gain below 1', () {
    // gain = |d ln L / d ln factor| (= 3, from (6.4)) x |d ln phi / d ln L| (at fixed G') x d ln factor / d ln phi
    final rows = <String>[];
    double gainAt(double phi) {
      const r0 = 2.088 / 3.132;
      final gp = phi * floodFluxRef(r0, 800, 2.9, 0.27, 20), lp = r0 * gp;
      double phiOf(double l) => gp / floodFluxRef(l / gp, 800, 2.9, 0.27, 20);
      final dlnPhi = (math.log(phiOf(lp * 1.001)) - math.log(phiOf(lp / 1.001))) / (2 * math.log(1.001));
      final fac = 1 + 1.2 * math.pow(phi, 13), dlnFac = 13 * 1.2 * math.pow(phi, 13) / fac;
      final g = 3 * dlnPhi * dlnFac;
      rows.add('phi ${phi.toStringAsFixed(2)}: dln phi/dln L ${dlnPhi.toStringAsFixed(3)}, dln f/dln phi '
          '${dlnFac.toStringAsFixed(2)}, loop gain ${g.toStringAsFixed(2)} (with tau 10 s: ${(g / 10).toStringAsFixed(2)})');
      return g;
    }

    final g7 = gainAt(0.7), g9 = gainAt(0.9), g95 = gainAt(0.95), g105 = gainAt(1.05);
    print('holdup-factor loop: ${rows.join('; ')}');
    expect(g7, lessThan(1));
    expect(g9, closeTo(0.9, 0.05), reason: 'crosses 1 just above phi_p 0.9');
    expect(g95, greaterThan(1));
    expect(g105 / 10, lessThan(1), reason: 'the 10-s lag (dt 1 s) stabilises the loop up to past flood');
  });

  group('bt_packed Tier 1', () {
    late Simulator sim;
    late SimSnapshot s;
    setUpAll(() {
      sim = _packed();
      s = _steady(sim);
    });
    test('#13, #14 full: x_D 0.99383, x_B 0.00617 (= independent CMO, E_O 1 on 18 segments); bed dP 587.4 / 818.6, column '
        '1406.0 Pa; phi 0.4882 / 0.5938; S 0.7685 / 1.1714; every segment = reference', () {
      final ref = cmoColumnRef(alpha: 2.5, e: List.filled(18, 1.0), feed: 10, f: 100, z: 0.5, l0: 100, vB: 150);
      final up = _recompute(sim, s, 1), lo = _recompute(sim, s, 2);
      print('bt_packed T1 full: x_D ${s.kpis.xD.toStringAsFixed(6)} (CMO ${ref.xD.toStringAsFixed(6)}), x_B '
          '${s.kpis.xB.toStringAsFixed(6)}, column dP ${s.kpis.columnDp.toStringAsFixed(1)} Pa; ${_bedLine(s, 1, up)}; '
          '${_bedLine(s, 2, lo)}; min L\' ${up.lp.reduce(math.min).toStringAsFixed(3)} / ${lo.lp.reduce(math.min).toStringAsFixed(3)}');
      expect(s.kpis.xD, closeTo(ref.xD, 2e-5));
      expect(s.kpis.xB, closeTo(ref.xB, 2e-5));
      expect(s.kpis.xD, closeTo(0.99383, 2e-5));
      expect(s.kpis.xB, closeTo(0.00617, 2e-5));
      expect(s.kpis.d / _kmolh, closeTo(50.0, 0.01));
      _matches(s, 1, up);
      _matches(s, 2, lo);
      expect(s.beds[0].dp, closeTo(587.4, 0.005 * 587.4));
      expect(s.beds[1].dp, closeTo(818.6, 0.005 * 818.6));
      expect(s.kpis.columnDp, closeTo(1406.0, 0.005 * 1406.0));
      expect(s.beds[0].maxFlood, closeTo(0.4882, 0.002));
      expect(s.beds[1].maxFlood, closeTo(0.5938, 0.002));
      expect(up.s, closeTo(0.7685, 0.002));
      expect(lo.s, closeTo(1.1714, 0.002));
      expect(s.beds[0].nTheoretical, closeTo(9, 1e-9));
      expect(s.beds[1].nTheoretical, closeTo(9, 1e-9));
      // L'_des = smallest segment L' at the defaults rounded down (1.924 / 4.201)
      expect(up.lp.reduce(math.min), closeTo(1.924, 0.002));
      expect(lo.lp.reduce(math.min), closeTo(4.201, 0.002));
    });
    test('#18 G15: lower-bed phi_p scales with a ratio-preserving k = 1.059 to the trays\' 0.629 (gain 5.9 %, upper 28.9 %); '
        'o2 margins at steady', () {
      final k = 0.629 / s.beds[1].maxFlood;
      final s2 = Simulator(sim.config, options: const SimOptions(seed: 3), warmStart: false);
      _scaleLoad(s2, k);
      final q = _steady(s2);
      print('G15: k ${k.toStringAsFixed(4)}: lower phi ${q.beds[1].maxFlood.toStringAsFixed(4)}, upper '
          '${q.beds[0].maxFlood.toStringAsFixed(4)}; o2 margins at steady: x_D - 0.993 = ${(s.kpis.xD - 0.993).toStringAsFixed(5)}, '
          '1500 - dP = ${(1500 - s.kpis.columnDp).toStringAsFixed(1)} Pa');
      expect(k - 1, closeTo(0.059, 0.003));
      expect(0.629 / s.beds[0].maxFlood - 1, closeTo(0.289, 0.005));
      expect(q.beds[1].maxFlood, closeTo(0.629, 1e-3));
      expect(q.beds[0].maxFlood / s.beds[0].maxFlood, closeTo(k, 1e-3));
      expect(14.49 / (s.kpis.columnDp / 1000), closeTo(10.31, 0.05));
      expect(s.kpis.xD, greaterThan(0.993 + 5e-4));
      expect(s.kpis.columnDp, lessThan(1500 - 50));
    });
    test('#19 VC-13.4 n = 5 (x 1.1^5): lower phi 0.9555, dP 2692.7 Pa, HETP(18) 0.5968 m, x_B 0.00832; segments = '
        'reference; holdup settles on the film time scale', () {
      final s5 = Simulator(sim.config, options: const SimOptions(seed: 3), warmStart: false);
      _scaleLoad(s5, math.pow(1.1, 5).toDouble());
      final q = _steady(s5);
      final lo = _recompute(s5, q, 2);
      print('VC-13.4 n 5: ${_bedLine(q, 2, lo)}; HETP(18) ${q.stages.hetp[18].toStringAsFixed(4)}, h_L(18) '
          '${q.stages.packHoldup[18].toStringAsFixed(5)}, x_D ${q.kpis.xD.toStringAsFixed(5)}, x_B ${q.kpis.xB.toStringAsFixed(5)}; '
          'lower-bed kinematic drainage time ${lo.tauKin.toStringAsFixed(0)} s');
      _matches(q, 2, lo);
      expect(q.beds[1].maxFlood, closeTo(0.9555, 0.002));
      expect(q.beds[1].dp, closeTo(2692.7, 0.005 * 2692.7));
      expect(q.stages.hetp[18], closeTo(0.5968, 0.003));
      expect(q.stages.packHoldup[18], closeTo(0.10265, 0.005 * 0.10265));
      expect(q.kpis.xB, closeTo(0.00832, 1e-4));
      // loading (g > 1) costs stages: x_B worse than at the design load
      expect(q.kpis.xB, greaterThan(s.kpis.xB));
    });
    test('turndown to 50 % (ratio-preserving): L\' below L\'_des, HETP rises by the wetting factor (= reference), '
        'x_D falls below the full-load 0.99383', () {
      final s5 = Simulator(sim.config, options: const SimOptions(seed: 3), warmStart: false);
      _scaleLoad(s5, 0.5);
      final q = _steady(s5);
      final up = _recompute(s5, q, 1), lo = _recompute(s5, q, 2);
      print('turndown 50 %: HETP(1) ${q.stages.hetp[1].toStringAsFixed(4)}, HETP(18) ${q.stages.hetp[18].toStringAsFixed(4)} m, '
          'n_th ${q.beds[0].nTheoretical.toStringAsFixed(3)} / ${q.beds[1].nTheoretical.toStringAsFixed(3)}, x_D '
          '${q.kpis.xD.toStringAsFixed(5)}, x_B ${q.kpis.xB.toStringAsFixed(5)}, dP ${q.kpis.columnDp.toStringAsFixed(1)} Pa');
      _matches(q, 1, up);
      _matches(q, 2, lo);
      expect(q.stages.hetp[1], greaterThan(1.05 * _hRef));
      expect(q.beds[0].nTheoretical, lessThan(9));
      expect(q.kpis.xD, lessThan(s.kpis.xD));
      expect(q.kpis.columnDp, lessThan(0.35 * s.kpis.columnDp), reason: 'dP ~ G^2 at low load');
    });
  }, timeout: _long);

  test('#15, #16 bt_packed Tier 2 full: x_D 0.99339, x_B 0.01063, D 49.796, T_B 110.56 °C, column dP 1276.2 Pa; '
      'TI-101/109/110/118 80.44 / 91.80 / 93.37 / 110.06 °C; lambda 0.590 .. 1.638; segments = reference', () {
    final sim = _packed(tier: 't2');
    final s = _steady(sim);
    final up = _recompute(sim, s, 1), lo = _recompute(sim, s, 2);
    final ti = {for (final i in s.instruments) i.tag: i.value};
    print('bt_packed T2 full: x_D ${s.kpis.xD.toStringAsFixed(5)}, x_B ${s.kpis.xB.toStringAsFixed(5)}, D '
        '${(s.kpis.d / _kmolh).toStringAsFixed(3)}, T_B ${(s.stages.t[19] - 273.15).toStringAsFixed(2)}, dP '
        '${s.kpis.columnDp.toStringAsFixed(1)}; TI ${[for (final t in ['TI-101', 'TI-109', 'TI-110', 'TI-118']) (ti[t]! - 273.15).toStringAsFixed(2)]}; '
        '${_bedLine(s, 1, up)}; ${_bedLine(s, 2, lo)}; min L\' ${up.lp.reduce(math.min).toStringAsFixed(3)} / '
        '${lo.lp.reduce(math.min).toStringAsFixed(3)}');
    _matches(s, 1, up);
    _matches(s, 2, lo);
    expect(s.kpis.xD, closeTo(0.99339, 2e-5));
    expect(s.kpis.xB, closeTo(0.01063, 2e-5));
    expect(s.kpis.d / _kmolh, closeTo(49.796, 0.01));
    expect(s.stages.t[19] - 273.15, closeTo(110.56, 0.02));
    expect(s.kpis.columnDp, closeTo(1276.2, 0.005 * 1276.2));
    for (final (t, v) in [('TI-101', 80.44), ('TI-109', 91.80), ('TI-110', 93.37), ('TI-118', 110.06)]) {
      expect(ti[t]! - 273.15, closeTo(v, 0.02), reason: t);
    }
    expect(up.lam.first, closeTo(0.590, 0.003));
    expect(lo.lam.last, closeTo(1.638, 0.003));
    expect(lo.lp.reduce(math.min), greaterThanOrEqualTo(4.0), reason: 'L\'_des 4.0 below the T2 minimum 4.054');
    expect(up.lp.reduce(math.min), greaterThanOrEqualTo(1.9));
  }, timeout: _long);

  test('#17 mixed template (bed over 11 sieve trays, feed 10), T1 ideal: x_D 0.99133 (= CMO, E 1 / 0.7); murphree 0.5 acts '
      'on the trays only (= CMO with 1 / 0.5)', () {
    final sim = Simulator(Presets.byId('bt').withInternals(2), options: const SimOptions(seed: 3), warmStart: false);
    final s = _steady(sim);
    final ref = cmoColumnRef(
        alpha: 2.5, e: [...List.filled(9, 1.0), ...List.filled(11, 0.7)], feed: 10, f: 100, z: 0.5, l0: 100, vB: 150);
    sim.setLever('murphree', 0.5);
    final q = _steady(sim);
    final ref5 = cmoColumnRef(
        alpha: 2.5, e: [...List.filled(9, 1.0), ...List.filled(11, 0.5)], feed: 10, f: 100, z: 0.5, l0: 100, vB: 150);
    print('mixed T1 ideal: x_D ${s.kpis.xD.toStringAsFixed(6)} (CMO ${ref.xD.toStringAsFixed(6)}), x_B ${s.kpis.xB.toStringAsFixed(6)}; '
        'murphree 0.5: x_D ${q.kpis.xD.toStringAsFixed(6)} (CMO ${ref5.xD.toStringAsFixed(6)}), segment E ${q.stages.efficiency[1]}');
    expect(s.layout.nTrays, 20);
    expect(s.kpis.xD, closeTo(0.99133, 2e-5));
    expect(s.kpis.xB, closeTo(0.00867, 2e-5));
    expect(s.kpis.xD, closeTo(ref.xD, 2e-5));
    expect(q.kpis.xD, closeTo(ref5.xD, 2e-5));
    expect(q.kpis.xB, closeTo(ref5.xB, 2e-5));
    for (var j = 1; j <= 9; j++) {
      expect(q.stages.efficiency[j], closeTo(1.0, 1e-9), reason: 'segment $j keeps E from its HETP');
    }
  }, timeout: _long);

  group('H7 column (VC-13.8; T2, D_bed 1.0 m, CW 15 °C)', () {
    late SimSnapshot h;
    setUpAll(() {
      h = _steady(_packed(tier: 't2', h7: true));
    });
    test('#20 healthy: dP 1263.2 / 1610.5 Pa, phi 0.6747 / 0.7865, x_D 0.99357, x_B 0.01108; segments = reference', () {
      final sim = _packed(tier: 't2', h7: true);
      final s = _steady(sim);
      final up = _recompute(sim, s, 1), lo = _recompute(sim, s, 2);
      print('H7 healthy: ${_bedLine(s, 1, up)}; ${_bedLine(s, 2, lo)}; x_D ${s.kpis.xD.toStringAsFixed(5)}, x_B '
          '${s.kpis.xB.toStringAsFixed(5)}');
      _matches(s, 1, up);
      _matches(s, 2, lo);
      for (final (v, r, tol) in [
        (s.beds[0].dp, 1263.2, 6.3),
        (s.beds[1].dp, 1610.5, 8.0),
        (s.beds[0].maxFlood, 0.6747, 0.002),
        (s.beds[1].maxFlood, 0.7865, 0.002),
        (s.kpis.xD, 0.99357, 3e-5),
        (s.kpis.xB, 0.01108, 3e-5),
      ]) {
        expect(v, closeTo(r, tol));
      }
    });
    test('#22 F21 upper s 0.5 (f 0.3): E_mal 0.5725 = Kremser on the engine\'s n_th and S; x_D 0.97875; TI span 11.46 -> '
        '8.09 K; own-bed dP within 1 %', () {
      final sim = _packed(tier: 't2', h7: true);
      sim.faults.inject(FaultSpec(type: FaultType.packingMaldistribution, location: const FaultLocation.bed(1), severity: 0.5));
      final s = _steady(sim);
      final up = _recompute(sim, s, 1, f: 0.3);
      print('H7 F21 upper s 0.5: ${_bedLine(s, 1, up)}; x_D ${s.kpis.xD.toStringAsFixed(5)}, TI span '
          '${(h.stages.t[9] - h.stages.t[1]).toStringAsFixed(2)} -> ${(s.stages.t[9] - s.stages.t[1]).toStringAsFixed(2)} K');
      _matches(s, 1, up);
      expect(s.beds[0].eMal, closeTo(up.eMal, 1e-4));
      expect(s.beds[0].eMal, closeTo(0.5725, 2e-4));
      expect(s.kpis.xD, closeTo(0.97875, 3e-5));
      expect(s.stages.t[9] - s.stages.t[1], closeTo(8.09, 0.05));
      expect(h.stages.t[9] - h.stages.t[1], closeTo(11.46, 0.05));
      expect(_rel(s.beds[0].dp, h.beds[0].dp), lessThan(0.01));
    });
    test('#23 F21 lower s 0.5: E_mal 0.5627 (= Kremser), x_B 0.03646, TI span 17.02 -> 12.97 K', () {
      final sim = _packed(tier: 't2', h7: true);
      sim.faults.inject(FaultSpec(type: FaultType.packingMaldistribution, location: const FaultLocation.bed(2), severity: 0.5));
      final s = _steady(sim);
      final lo = _recompute(sim, s, 2, f: 0.3);
      print('H7 F21 lower s 0.5: ${_bedLine(s, 2, lo)}; x_B ${s.kpis.xB.toStringAsFixed(5)}, TI span '
          '${(s.stages.t[18] - s.stages.t[10]).toStringAsFixed(2)} K');
      expect(s.beds[1].eMal, closeTo(lo.eMal, 1e-4));
      expect(s.beds[1].eMal, closeTo(0.5627, 2e-4));
      expect(s.kpis.xB, closeTo(0.03646, 3e-5));
      expect(s.stages.t[18] - s.stages.t[10], closeTo(12.97, 0.05));
    });
    test('#24, #25 F23 upper s 0.3 / lower s 0.3, 0.5: dP 1848.6 / 2534.6 / 3331.6 Pa, phi 0.7529 / 0.8814 / 0.9358 '
        '(segments = reference with F_p,eff = 20 (1 + 1.5 s)); x moves < 0.007', () {
      for (final (bed, sev, dp, phi) in [(1, 0.3, 1848.6, 0.7529), (2, 0.3, 2534.6, 0.8814), (2, 0.5, 3331.6, 0.9358)]) {
        final sim = _packed(tier: 't2', h7: true);
        sim.faults.inject(FaultSpec(type: FaultType.packingCrush, location: FaultLocation.bed(bed), severity: sev));
        final s = _steady(sim);
        final r = _recompute(sim, s, bed, crush: sev);
        print('H7 F23 bed $bed s $sev: ${_bedLine(s, bed, r)}; dP x${(s.beds[bed - 1].dp / h.beds[bed - 1].dp).toStringAsFixed(3)}; '
            'x_D ${s.kpis.xD.toStringAsFixed(5)}, x_B ${s.kpis.xB.toStringAsFixed(5)}');
        _matches(s, bed, r);
        expect(s.beds[bed - 1].dp, closeTo(dp, 0.005 * dp));
        expect(s.beds[bed - 1].maxFlood, closeTo(phi, 0.002));
        expect((s.kpis.xD - h.kpis.xD).abs(), lessThan(0.007));
        expect((s.kpis.xB - h.kpis.xB).abs(), lessThan(0.007));
      }
    }, timeout: _long);
    test('#21, #26 healthy at +10 % / +25 %: lower phi 0.8630 / 0.9747, dP 2953.8 Pa (1.83x), HETP(18) 0.622 m '
        '(= reference g(phi)), x_B 0.01708, Q_C 1599 kW', () {
      final sim = _packed(tier: 't2', h7: true);
      _steady(sim);
      _scaleLoad(sim, 1.1, t2: true);
      final s10 = _steady(sim);
      _scaleLoad(sim, 1.25 / 1.1, t2: true);
      final s = _steady(sim);
      final lo = _recompute(sim, s, 2);
      print('H7 +10 %: lower phi ${s10.beds[1].maxFlood.toStringAsFixed(4)}; +25 %: ${_bedLine(s, 2, lo)}; dP '
          'x${(s.beds[1].dp / h.beds[1].dp).toStringAsFixed(3)}; HETP(18) ${s.stages.hetp[18].toStringAsFixed(4)}, h_L(18) '
          '${h.stages.packHoldup[18].toStringAsFixed(4)} -> ${s.stages.packHoldup[18].toStringAsFixed(4)}; x_B '
          '${s.kpis.xB.toStringAsFixed(5)}, Q_C ${(s.kpis.qc / 1000).toStringAsFixed(1)} kW, D ${(s.kpis.d / _kmolh).toStringAsFixed(2)}');
      _matches(s, 2, lo);
      expect(s10.beds[1].maxFlood, closeTo(0.8630, 0.002));
      expect(s.beds[1].maxFlood, closeTo(0.9747, 0.002));
      expect(s.beds[1].dp, closeTo(2953.8, 0.005 * 2953.8));
      expect(s.stages.hetp[18], closeTo(0.622, 0.002));
      expect(s.beds[1].nTheoretical, closeTo(7.55, 0.03));
      expect(s.kpis.xB, closeTo(0.01708, 3e-5));
      expect(s.kpis.qc / 1000, closeTo(1599, 3));
      expect(s.stages.packHoldup[18], closeTo(0.1193, 0.002));
    }, timeout: _long);
  }, timeout: _long);

  test('G15 o2 after the internals switch (bt T1 full, trays steady): time to o2 and x_D there vs the packed steady '
      '0.99383; the trays state cannot satisfy o2', () {
    final sim = Simulator(Presets.byId('bt').applyOverrides({'tier': 't1', 'hydraulics': 'full'}),
        options: const SimOptions(seed: 3), warmStart: false);
    final s0 = _steady(sim);
    expect(s0.kpis.columnDp, greaterThan(1500), reason: 'trays fail o2 on dP');
    expect(s0.kpis.xD, lessThan(0.993), reason: 'trays fail o2 on x_D');
    sim.setLever('internals', 1);
    final t0 = sim.time;
    var held = 0.0, tO2 = double.nan, xO2 = double.nan, dpMax = 0.0;
    while (sim.time - t0 < 14400 && tO2.isNaN) {
      sim.advance(10);
      final q = sim.snapshot();
      if (sim.time - t0 > 600) dpMax = math.max(dpMax, q.kpis.columnDp);
      held = (q.kpis.xD >= 0.993 && q.kpis.columnDp <= 1500) ? held + 10 : 0;
      if (held >= 300) {
        tO2 = sim.time - t0;
        xO2 = q.kpis.xD;
      }
    }
    sim.advance(7200);
    final x2 = sim.snapshot().kpis.xD;
    print('G15: o2 met ${tO2.toStringAsFixed(0)} s after the switch (par 3600), x_D there ${xO2.toStringAsFixed(5)}, '
        '+2 h ${x2.toStringAsFixed(5)} (steady 0.99383); column dP after 10 min <= ${dpMax.toStringAsFixed(0)} Pa');
    expect(tO2, lessThanOrEqualTo(3600));
    expect(xO2, closeTo(0.99383, 1e-3));
    expect(x2, closeTo(0.99383, 1e-4));
  }, timeout: _long);

  test('H7 near_flood drill (noise off, event at 2700 s): PDT-103 >= 1.7x within 30 min (peak recorded); lower phi >= 0.95; '
      'HETP(18) +20 %; CW valve below 100 %; dP settles near the +25 % steady 2953.8 Pa', () {
    final j = jsonDecode(Scenarios.jsonOf('H7_packed_bed')) as Map<String, Object?>;
    j['noise'] = false;
    j['onsetWindow'] = [600, 600];
    for (final c in j['candidates']! as List<Object?>) {
      final m = c! as Map<String, Object?>;
      m['weight'] = m['id'] == 'near_flood' ? 1 : 0;
    }
    final sim = Simulator(Presets.byId('bt_packed'), options: const SimOptions(seed: 3), warmStart: false);
    sim.startScenario(ScenarioDef.fromJson(j), seed: 3);
    double pdt(String tag) => sim.snapshot().instruments.firstWhere((i) => i.tag == tag).value;
    sim.advance(2690 - sim.time);
    final p0 = pdt('PDT-103'), p20 = pdt('PDT-102'), h0 = sim.snapshot().stages.hetp[18];
    var t17 = double.nan, cwMax = 0.0;
    final trace = <double>[];
    while (sim.time < 2700 + 1800) {
      sim.advance(10);
      trace.add(pdt('PDT-103'));
      if (t17.isNaN && pdt('PDT-103') >= 1.7 * p0) t17 = sim.time - 2700;
      cwMax = math.max(cwMax, sim.control.pc101.op);
    }
    final s = sim.snapshot();
    // shape: peak and its time, values 5 and 10 min after the event
    final at5 = trace[29], at10 = trace[59], pk = trace.reduce(math.max), tPk = 10 * (trace.indexOf(pk) + 1);
    print('H7 near_flood: PDT-103 ${p0.toStringAsFixed(0)} -> x${(trace.last / p0).toStringAsFixed(3)} (1.7x at '
        '${t17.toStringAsFixed(0)} s; +5 min ${at5.toStringAsFixed(0)}, +10 min ${at10.toStringAsFixed(0)}, peak ${pk.toStringAsFixed(0)} Pa at $tPk s), PDT-102 '
        'x${(pdt('PDT-102') / p20).toStringAsFixed(3)}, lower phi ${s.beds[1].maxFlood.toStringAsFixed(4)}, HETP(18) '
        '${h0.toStringAsFixed(3)} -> ${s.stages.hetp[18].toStringAsFixed(3)} m, CW valve max ${cwMax.toStringAsFixed(1)} %');
    expect(t17, lessThanOrEqualTo(1800));
    expect(trace.last, closeTo(2953.8, 0.01 * 2953.8), reason: 'settles near the VC-13.8 +25 % row');
    expect(s.beds[1].maxFlood, greaterThanOrEqualTo(0.95));
    expect(s.stages.hetp[18], greaterThanOrEqualTo(1.2 * h0));
    expect(cwMax, lessThan(100));
  }, timeout: _long);
}
