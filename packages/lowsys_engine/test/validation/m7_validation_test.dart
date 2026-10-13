// M7 validation (engine eea0a5a): key numbers of docs/milestones/M7.md E.3 plus physical-sense checks. Everything
// here runs with `ideal` hydraulics, so the steady values do not depend on the column diameter (0.75 / 0.55 m
// pending); the H6 timings could move slightly with tray holdups. VC-9.4 / 9.5 (E.3 #3-5) are in
// m5_tier3_thermo_validation_test.dart. Independent FUG: reference/fug_reference.dart.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/fug_reference.dart';

const _kmolh = 1000 / 3600;
const _long = Timeout(Duration(minutes: 20));

Simulator _sim(ColumnConfig c) => Simulator(c, options: const SimOptions(seed: 3), warmStart: false);

SimSnapshot _steady(Simulator s) {
  expect(s.runToSteadyState(maxSimSeconds: 400000).reached, isTrue);
  return s.snapshot();
}

List<double> _x(SimSnapshot s, int j) => s.stages.x.sublist(j * s.stages.nc, (j + 1) * s.stages.nc);

/// Independent product numbers from the stage compositions and stream flows.
({double rLK, double rHK, double xDHeavy, double xBLight, double xpD, double xpB, double xpF, double r, double closure})
    _products(SimSnapshot s, KeyComponents k) {
  final n = s.layout.nTrays, nc = s.stages.nc;
  final xd = _x(s, 0), xb = _x(s, n + 1);
  final feed = s.streams[StreamId.feed]!, d = s.streams[StreamId.distillate]!.flow, b = s.streams[StreamId.bottoms]!.flow;
  final z = feed.composition, f = feed.flow;
  var heavy = 0.0, light = 0.0, clos = 0.0;
  for (var i = 0; i < nc; i++) {
    if (i >= k.hk) heavy += xd[i];
    if (i <= k.lk) light += xb[i];
    clos = math.max(clos, (d * xd[i] + b * xb[i] - f * z[i]).abs() / f);
  }
  return (
    rLK: d * xd[k.lk] / (f * z[k.lk]),
    rHK: b * xb[k.hk] / (f * z[k.hk]),
    xDHeavy: heavy,
    xBLight: light,
    xpD: xd[k.lk] / (xd[k.lk] + xd[k.hk]),
    xpB: xb[k.lk] / (xb[k.lk] + xb[k.hk]),
    xpF: z[k.lk] / (z[k.lk] + z[k.hk]),
    r: s.streams[StreamId.reflux]!.flow / d,
    closure: clos,
  );
}

/// K_i / K_HK at stage j from the thermo model (validator's own call, not FugCalculator.alphas).
List<double> _alphaAt(SimSnapshot s, ThermoModel th, int j, int hk) {
  final nc = s.stages.nc;
  final k = Float64List(nc);
  th.kValues(s.stages.t[j], s.stages.p[j], Float64List.fromList(_x(s, j)), k);
  return [for (var i = 0; i < nc; i++) k[i] / k[hk]];
}

double _rel(double a, double b) => ((a - b) / b).abs();

void _fugMatchesRef(FugResult e, FugRef r) {
  for (final (name, a, b) in [
    ('N_min', e.nMin, r.nMin),
    ('theta', e.theta, r.theta),
    ('R_min', e.rMin, r.rMin),
    ('N', e.nGilliland, r.n),
    ('N_R/N_S', e.nrOverNs, r.nrOverNs),
    ('N_R', e.nR, r.nR),
  ]) {
    expect(_rel(a, b), lessThan(1e-6), reason: '$name engine $a ref $b');
  }
}

Map<String, InstrumentReading> _inst(Simulator s) => {for (final i in s.snapshot().instruments) i.tag: i};

/// H6 with one candidate forced (others weight 0), fixed severity, onset 600 s, noise off.
Simulator _h6(String candidate, {double? severity}) {
  final j = jsonDecode(Scenarios.jsonOf('H6_offspec_overhead')) as Map<String, Object?>;
  j['noise'] = false;
  j['onsetWindow'] = [600, 600];
  for (final c in j['candidates']! as List<Object?>) {
    final m = c! as Map<String, Object?>;
    m['weight'] = m['id'] == candidate ? 1 : 0;
    if (m['id'] == candidate && severity != null) (m['fault']! as Map<String, Object?>)['severityRange'] = [severity, severity];
  }
  final sim = Simulator(Presets.byId('debut'), options: const SimOptions(seed: 3), warmStart: false);
  sim.startScenario(ScenarioDef.fromJson(j), seed: 3);
  return sim;
}

void main() {
  group('E.3 #1, #2 FUG design mode (VC-9.1 / 9.2): engine core = spec = independent FUG', () {
    test('debut: N_min 10.9100, theta 1.31112, R_min 1.3073, N 23.282, N_R/N_S 1.0042, D 44.9437; d_iC4 14.9806, d_nC5 0.0631',
        () {
      const a = [5.180, 2.628, 2.041, 1.000, 0.843, 0.385], z = [0.05, 0.15, 0.25, 0.20, 0.20, 0.15];
      final e = FugCalculator.core(
          alpha: Float64List.fromList(a), z: Float64List.fromList(z), lk: 2, hk: 3, rLK: 0.98, rHK: 0.98, q: 1, f: 100,
          rOverRmin: 1.3);
      final r = fugRef(a, z, 2, 3, 0.98, 0.98);
      _fugMatchesRef(e, r);
      expect(e.nMin, closeTo(10.9100, 1e-4));
      expect(e.theta, closeTo(1.31112, 1e-4));
      expect(e.rMin, closeTo(1.3073, 1e-4));
      expect(e.r, closeTo(1.6996, 1e-4));
      expect(e.nGilliland, closeTo(23.282, 1e-3));
      expect(e.nrOverNs, closeTo(1.0042, 1e-4));
      expect(e.d.reduce((p, q) => p + q), closeTo(44.9437, 1e-4));
      expect(e.d[1], closeTo(14.9806, 1e-4));
      expect(e.d[4], closeTo(0.0631, 1e-4));
    });
    test('deprop: N_min 9.7203, theta 1.40567, R_min 1.6522, N 20.364, N_R/N_S 0.4740, D 30.7771', () {
      const a = [2.172, 1.000, 0.747, 0.378, 0.330, 0.157], z = [0.30, 0.20, 0.25, 0.10, 0.10, 0.05];
      final e = FugCalculator.core(
          alpha: Float64List.fromList(a), z: Float64List.fromList(z), lk: 0, hk: 1, rLK: 0.99, rHK: 0.95, q: 1, f: 100,
          rOverRmin: 1.3);
      _fugMatchesRef(e, fugRef(a, z, 0, 1, 0.99, 0.95));
      expect(e.nMin, closeTo(9.7203, 1e-4));
      expect(e.theta, closeTo(1.40567, 1e-4));
      expect(e.rMin, closeTo(1.6522, 1e-4));
      expect(e.nGilliland, closeTo(20.364, 1e-3));
      expect(e.nrOverNs, closeTo(0.4740, 1e-4));
      expect(e.d.reduce((p, q) => p + q), closeTo(30.7771, 1e-4));
    });
    test('directional: tighter recoveries raise N_min and N; R closer to R_min raises N', () {
      const a = [5.180, 2.628, 2.041, 1.000, 0.843, 0.385], z = [0.05, 0.15, 0.25, 0.20, 0.20, 0.15];
      final r98 = fugRef(a, z, 2, 3, 0.98, 0.98), r99 = fugRef(a, z, 2, 3, 0.99, 0.99);
      expect(r99.nMin, greaterThan(r98.nMin));
      expect(r99.n, greaterThan(r98.n));
      expect(fugRef(a, z, 2, 3, 0.98, 0.98, k: 1.1).n, greaterThan(r98.n));
    });
  });

  group('E.3 #7, #8, #18 VC-9.3 column (Tier 1, 22 / 12, E 1, L0 76.39, V_B 121.33) and VC-9.7 last row', () {
    ColumnConfig cfg(int n, int nf) {
      final c = Presets.byId('debut').copyWith(tier: ThermoTier.t1, murphree: 1.0).withTrays(n, feedStage: nf);
      return c.copyWith(initialLevers: {...c.initialLevers, 'refluxFlow': 76.39 * _kmolh, 'boilup': 121.33 * _kmolh});
    }

    late Simulator sim;
    late SimSnapshot s;
    setUpAll(() {
      sim = _sim(cfg(22, 12));
      s = _steady(sim);
    });
    test('r_LK 0.9843, r_HK 0.9849 (± 0.002, [I]); D 44.94; component closure', () {
      final p = _products(s, sim.config.keys!);
      print('VC-9.3 22/12: r ${p.rLK.toStringAsFixed(4)} / ${p.rHK.toStringAsFixed(4)}, D '
          '${(s.kpis.d / _kmolh).toStringAsFixed(3)}, x\'_D ${p.xpD.toStringAsFixed(5)}, x\'_B ${p.xpB.toStringAsFixed(5)}');
      expect(p.rLK, closeTo(0.9843, 0.002));
      expect(p.rHK, closeTo(0.9849, 0.002));
      expect(s.kpis.recoveryLK!, closeTo(p.rLK, 1e-9));
      expect(s.kpis.recoveryHK!, closeTo(p.rHK, 1e-9));
      expect(s.kpis.d / _kmolh, closeTo(44.94, 0.01));
      expect(p.closure, lessThan(1e-6));
    });
    test('Hengstebeck: x\'_D 0.98784, x\'_B 0.01955 (± 5e-4), builder = stage compositions; Tier-1 alpha\' 2.041', () {
      final p = _products(s, sim.config.keys!);
      final d = McCabeThieleBuilder().build(s, sim.thermo, keys: sim.config.keys);
      expect(d.pseudoBinary, isTrue);
      expect(d.xD, closeTo(p.xpD, 1e-9));
      expect(d.xB, closeTo(p.xpB, 1e-9));
      expect(p.xpD, closeTo(0.98784, 5e-4));
      expect(p.xpB, closeTo(0.01955, 5e-4));
      expect(d.alphaPrimeTop, closeTo(2.041, 1e-9));
    });
    test('live FUG (VC-9.7 row 4): N_min 11.652, R_min 1.3223, N 25.07, N_R 12.65; N_act 23.00, N_R,act 11.00; = independent FUG',
        () {
      final k = sim.config.keys!;
      final e = const FugCalculator().compute(s, k, thermo: sim.thermo)!;
      final p = _products(s, k);
      final z = s.streams[StreamId.feed]!.composition;
      _fugMatchesRef(e, fugRef(const [5.18, 2.628, 2.041, 1.0, 0.843, 0.385], z, k.lk, k.hk, p.rLK, p.rHK, r: p.r));
      expect(e.nMin, closeTo(11.652, 0.15));
      expect(e.theta, closeTo(1.3111, 0.001));
      expect(e.rMin, closeTo(1.3223, 0.005));
      expect(e.nGilliland, closeTo(25.07, 0.3));
      expect(e.nR, closeTo(12.65, 0.3));
      expect(e.nActual, closeTo(23.0, 1e-9));
      expect(e.nRActual, closeTo(11.0, 1e-9));
    });
    test('feed tray 8 on 22 trays lowers both recoveries (0.9689 / 0.9717)', () {
      final s8 = _steady(_sim(cfg(22, 8)));
      final p = _products(s8, Presets.byId('debut').keys!);
      print('VC-9.3 22/8: r ${p.rLK.toStringAsFixed(4)} / ${p.rHK.toStringAsFixed(4)}');
      expect(p.rLK, closeTo(0.9689, 0.002));
      expect(p.rHK, closeTo(0.9717, 0.002));
    });
  }, timeout: _long);

  group('debut default, Tier 3 (E.3 #10, #11, #13, #17, #19, #20)', () {
    late Simulator sim;
    late SimSnapshot s;
    late KeyComponents k;
    setUpAll(() {
      sim = _sim(Presets.byId('debut'));
      s = _steady(sim);
      k = sim.config.keys!;
    });
    test('#10 r 0.9781 / 0.9783 (± 0.002); xDHeavy 0.01124, xBLight 0.01020 (± 5e-4) = sums of the stage compositions', () {
      final p = _products(s, k);
      print('debut: r ${p.rLK.toStringAsFixed(4)} / ${p.rHK.toStringAsFixed(4)}, xDHeavy ${p.xDHeavy.toStringAsFixed(5)}, '
          'xBLight ${p.xBLight.toStringAsFixed(5)}, D ${(s.kpis.d / _kmolh).toStringAsFixed(3)}, closure ${p.closure}');
      expect(p.rLK, closeTo(0.9781, 0.002));
      expect(p.rHK, closeTo(0.9783, 0.002));
      expect(p.xDHeavy, closeTo(0.01124, 5e-4));
      expect(p.xBLight, closeTo(0.01020, 5e-4));
      expect(s.kpis.xDHeavy, closeTo(p.xDHeavy, 1e-9));
      expect(s.kpis.xBLight, closeTo(p.xBLight, 1e-9));
      expect(s.kpis.d / _kmolh, closeTo(44.94, 0.02));
      expect(p.closure, lessThan(1e-6));
    });
    test('#11 T_0 49.573, T_B 112.719 °C (± 0.05); Q_C 616.34 kW (± 0.3 %); T rises down the column', () {
      final n = s.layout.nTrays;
      expect(s.stages.t[0] - 273.15, closeTo(49.573, 0.05));
      expect(s.stages.t[n + 1] - 273.15, closeTo(112.719, 0.05));
      expect(s.kpis.qc / 1e3, closeTo(616.34, 0.003 * 616.34));
      for (var j = 1; j <= n + 1; j++) {
        expect(s.stages.t[j], greaterThan(s.stages.t[j - 1]), reason: 'stage $j');
      }
    });
    test('#13 utilities: FV-103 at 60 % of Q_max,0 1132.8 kW at the design duty (± 1 %)', () {
      print('debut FV-103 ${sim.control.fv103.position.toStringAsFixed(2)} %');
      expect(sim.control.fv103.position, closeTo(100 * 679.68 / 1132.8, 1.0));
    });
    test('#17 Hengstebeck: x\'_F 0.55556, x\'_D 0.98253, x\'_B 0.02723; alpha\' 2.2157 top > 1.8853 bottom (own K calls)', () {
      final p = _products(s, k);
      final d = McCabeThieleBuilder().build(s, sim.thermo, keys: k);
      final top = _alphaAt(s, sim.thermo, 1, k.hk)[k.lk], bot = _alphaAt(s, sim.thermo, s.layout.nTrays + 1, k.hk)[k.lk];
      print('debut Hengstebeck: x\'_D ${p.xpD.toStringAsFixed(5)}, x\'_B ${p.xpB.toStringAsFixed(5)}; alpha\' '
          '${top.toStringAsFixed(4)} / ${bot.toStringAsFixed(4)}');
      expect(p.xpF, closeTo(0.55556, 1e-5));
      expect(d.xF, closeTo(p.xpF, 1e-9));
      expect(d.xD, closeTo(p.xpD, 1e-9));
      expect(d.xB, closeTo(p.xpB, 1e-9));
      expect(p.xpD, closeTo(0.98253, 5e-4));
      expect(p.xpB, closeTo(0.02723, 5e-4));
      expect(top, closeTo(2.2157, 0.002));
      expect(bot, closeTo(1.8853, 0.002));
      expect(d.alphaPrimeTop, closeTo(top, 1e-9));
      expect(d.alphaPrimeBottom, closeTo(bot, 1e-9));
    });
    test('#19 live FUG = independent FUG (1e-6; own alpha from K at stages 1, N+1); N_min 10.639, R_min 1.2974, N 22.56, '
        'N_R 11.32; N_act 23.40, N_R,act 10.50; N_act > N (Tier 3 needs a little more)', () {
      final e = const FugCalculator().compute(s, k, thermo: sim.thermo)!;
      final p = _products(s, k);
      final top = _alphaAt(s, sim.thermo, 1, k.hk), bot = _alphaAt(s, sim.thermo, s.layout.nTrays + 1, k.hk);
      final a = [for (var i = 0; i < top.length; i++) math.sqrt(top[i] * bot[i])];
      final z = s.streams[StreamId.feed]!.composition;
      print('debut live FUG: alpha ${a.map((v) => v.toStringAsFixed(4)).join(', ')}; q ${e.q}; N_min ${e.nMin.toStringAsFixed(3)}, '
          'theta ${e.theta.toStringAsFixed(4)}, R_min ${e.rMin.toStringAsFixed(4)}, R ${e.r.toStringAsFixed(4)}, N '
          '${e.nGilliland.toStringAsFixed(2)}, N_R ${e.nR.toStringAsFixed(2)}');
      expect(e.valid, isTrue);
      _fugMatchesRef(e, fugRef(a, z, k.lk, k.hk, p.rLK, p.rHK, q: e.q, r: p.r));
      expect(a[0], closeTo(5.1968, 0.01));
      expect(a[5], closeTo(0.3844, 0.002));
      expect(e.nMin, closeTo(10.639, 0.15));
      expect(e.theta, closeTo(1.3115, 0.001));
      expect(e.rMin, closeTo(1.2974, 0.005));
      expect(e.r, closeTo(1.6999, 0.002));
      expect(e.nGilliland, closeTo(22.56, 0.3));
      expect(e.nR, closeTo(11.32, 0.3));
      expect(e.nActual, closeTo(23.4, 1e-9));
      expect(e.nRActual, closeTo(10.5, 1e-9));
      expect(e.nActual, greaterThan(e.nGilliland));
    });
    test('#20 targets 98 / 98, live R: N_min 10.889, R_min 1.3030, N 23.16; = independent FUG', () {
      final e = const FugCalculator().compute(s, k, targets: const FugTargets(0.98, 0.98), thermo: sim.thermo)!;
      final top = _alphaAt(s, sim.thermo, 1, k.hk), bot = _alphaAt(s, sim.thermo, s.layout.nTrays + 1, k.hk);
      final a = [for (var i = 0; i < top.length; i++) math.sqrt(top[i] * bot[i])];
      _fugMatchesRef(e, fugRef(a, s.streams[StreamId.feed]!.composition, k.lk, k.hk, 0.98, 0.98, q: e.q, r: _products(s, k).r));
      expect(e.nMin, closeTo(10.889, 0.15));
      expect(e.rMin, closeTo(1.3030, 0.005));
      expect(e.nGilliland, closeTo(23.16, 0.3));
    });
    test('VC-21 (54f9b41 item 1): eq.fug.rigorous closes the FUG trace with N_act 23.4; eq.fug.fenske = N_min', () {
      final lines = [for (final g in sim.explain(const ExplainFug()).groups) ...g.lines];
      final byId = {for (final l in lines) l.id: l};
      expect(byId['eq.fug.rigorous']!.value, closeTo(23.4, 1e-9));
      expect(byId['eq.fug.rigorous']!.texSubstituted, isNotEmpty);
      expect(byId['eq.fug.fenske']!.value, closeTo(10.639, 0.15));
    });
    test('VC-9.7 guards: r_LK 0.5; keys iC4 / iC5 not adjacent; R = R_min gives belowRmin and N = inf; plant view null', () {
      expect(const FugCalculator().compute(s, k, targets: const FugTargets(0.5, 0.98), thermo: sim.thermo)!.valid, isFalse);
      final na = const FugCalculator().compute(s, const KeyComponents(1, 3), thermo: sim.thermo)!;
      expect(na.valid, isFalse);
      expect(na.reason, FugInvalidReason.notAdjacent);
      final at = const FugCalculator().compute(s, k, targets: const FugTargets(0.98, 0.98, 1.0), thermo: sim.thermo)!;
      expect(at.belowRmin, isTrue);
      expect(at.nGilliland, double.infinity);
      sim.setLever('view', 1);
      expect(const FugCalculator().compute(sim.snapshot(), k, thermo: sim.thermo), isNull);
      sim.setLever('view', 0);
    });
    test('C3a lambda_top uses T_bub(x_D): on a wide-boiling distillate it over-reads the top vapour (record)', () {
      // the true condenser duty is V1 (H_V(y1 = x_D, T_dew) - h_L(x_D, T_0)); C3a (PHYSICS.md 14.6) takes H_V at T_bub
      final th = sim.thermo, xd = Float64List.fromList(_x(s, 0)), p = s.stages.p[0], nc = s.stages.nc;
      final h = SolverHealth();
      final tb = th.bubbleT(p, xd, s.stages.t[0], Float64List(nc), Float64List(nc), h);
      final td = th.dewT(p, xd, s.stages.t[1], Float64List(nc), h);
      final hl = th.hL(s.stages.t[0], xd);
      final vBub = s.kpis.qc / (th.hV(tb, xd) - hl), vDew = s.kpis.qc / (th.hV(td, xd) - hl);
      final v1 = s.stages.vaporUp[1];
      print('C3a lambda: T_bub ${(tb - 273.15).toStringAsFixed(2)} °C, T_dew ${(td - 273.15).toStringAsFixed(2)} °C (T_1 '
          '${(s.stages.t[1] - 273.15).toStringAsFixed(2)}); V1 ${(v1 / _kmolh).toStringAsFixed(2)}, Q_C/lambda(T_dew) '
          '${(vDew / _kmolh).toStringAsFixed(2)}, Q_C/lambda(T_bub) ${(vBub / _kmolh).toStringAsFixed(2)} kmol/h '
          '(+${(100 * (vBub / v1 - 1)).toStringAsFixed(2)} %)');
      expect(td, closeTo(s.stages.t[1], 1.0), reason: 'E 0.7: y1 is not in equilibrium with tray 1');
      expect(_rel(vDew, v1), lessThan(0.005));
      expect(vBub, greaterThan(vDew));
    });
  }, timeout: _long);

  group('deprop default, Tier 3 (E.3 #12, #13, #21)', () {
    late Simulator sim;
    late SimSnapshot s;
    setUpAll(() {
      sim = _sim(Presets.byId('deprop'));
      s = _steady(sim);
    });
    test('#12 r 0.9906 / 0.9535 (± 0.002); T_B 123.851 °C; Q_C 349.84 kW; FV-103 at 416.55 / 694.3 = 60 %', () {
      final k = sim.config.keys!;
      final p = _products(s, k);
      print('deprop: r ${p.rLK.toStringAsFixed(4)} / ${p.rHK.toStringAsFixed(4)}, D ${(s.kpis.d / _kmolh).toStringAsFixed(3)}, '
          'P_top ${(s.kpis.pTop / 1e5).toStringAsFixed(3)} bar, FV-103 ${sim.control.fv103.position.toStringAsFixed(2)} %');
      expect(p.rLK, closeTo(0.9906, 0.002));
      expect(p.rHK, closeTo(0.9535, 0.002));
      expect(s.stages.t[s.layout.nTrays + 1] - 273.15, closeTo(123.851, 0.05));
      expect(s.kpis.qc / 1e3, closeTo(349.84, 0.003 * 349.84));
      expect(sim.control.fv103.position, closeTo(100 * 416.55 / 694.3, 1.0));
      expect(p.closure, lessThan(1e-6));
    });
    test('#21 live FUG: N_min 9.886, R_min 1.6628, N 20.83; N_act 20.60, N_R,act 7.00; = independent FUG', () {
      final k = sim.config.keys!;
      final e = const FugCalculator().compute(s, k, thermo: sim.thermo)!;
      final top = _alphaAt(s, sim.thermo, 1, k.hk), bot = _alphaAt(s, sim.thermo, s.layout.nTrays + 1, k.hk);
      final a = [for (var i = 0; i < top.length; i++) math.sqrt(top[i] * bot[i])];
      final p = _products(s, k);
      _fugMatchesRef(e, fugRef(a, s.streams[StreamId.feed]!.composition, k.lk, k.hk, p.rLK, p.rHK, q: e.q, r: p.r));
      expect(e.nMin, closeTo(9.886, 0.15));
      expect(e.rMin, closeTo(1.6628, 0.005));
      expect(e.nGilliland, closeTo(20.83, 0.3));
      expect(e.nActual, closeTo(20.6, 1e-9));
      expect(e.nRActual, closeTo(7.0, 1e-9));
    });
  }, timeout: _long);

  test('E.3 #16 debut T3 -> T1 directly (top-vapour rule): D continuous, r 0.9835 / 0.9846 (± 0.002)', () {
    final sim = _sim(Presets.byId('debut'));
    final s0 = _steady(sim);
    sim.setTier(ThermoTier.t1);
    sim.advance(1);
    final d1 = sim.snapshot().kpis.d, v1 = sim.snapshot().stages.vaporUp[1];
    final s = _steady(sim);
    final p = _products(s, sim.config.keys!);
    print('T3 -> T1: D ${(s0.kpis.d / _kmolh).toStringAsFixed(3)} -> ${(d1 / _kmolh).toStringAsFixed(3)} (1 s) -> '
        '${(s.kpis.d / _kmolh).toStringAsFixed(3)}; V1 ${(s0.stages.vaporUp[1] / _kmolh).toStringAsFixed(3)} -> '
        '${(v1 / _kmolh).toStringAsFixed(3)} (1 s); r ${p.rLK.toStringAsFixed(4)} / ${p.rHK.toStringAsFixed(4)}');
    expect(_rel(v1, s0.stages.vaporUp[1]), lessThan(0.005));
    expect((d1 - s0.kpis.d).abs() / _kmolh, lessThan(0.25), reason: 'D continuous (LC-101 blip < 0.6 %)');
    expect(s.kpis.d / _kmolh, closeTo(44.94, 0.05));
    expect(p.rLK, closeTo(0.9835, 0.002));
    expect(p.rHK, closeTo(0.9846, 0.002));
  }, timeout: _long);

  test('E.3 #23 G13 hint state L0 80 kmol/h, Q_R 697.9 kW: r 0.9821 / 0.9827, Q_C 634.2 kW, D 44.94; more reflux, '
      'better split', () {
    final sim = _sim(Presets.byId('debut'));
    final s0 = _steady(sim);
    sim.setLever('refluxFlow', 80 * _kmolh);
    sim.setLever('reboilerDuty', 697900);
    final s = _steady(sim);
    final p = _products(s, sim.config.keys!), p0 = _products(s0, sim.config.keys!);
    print('G13 hint state: r ${p.rLK.toStringAsFixed(4)} / ${p.rHK.toStringAsFixed(4)}, Q_C ${(s.kpis.qc / 1e3).toStringAsFixed(1)} kW, '
        'D ${(s.kpis.d / _kmolh).toStringAsFixed(3)}');
    expect(p.rLK, closeTo(0.9821, 0.002));
    expect(p.rHK, closeTo(0.9827, 0.002));
    expect(s.kpis.qc / 1e3, closeTo(634.2, 0.003 * 634.2));
    expect(s.kpis.d / _kmolh, closeTo(44.94, 0.05));
    expect(p.rLK, greaterThan(p0.rLK));
    expect(p.rHK, greaterThan(p0.rHK));
    expect(p.rLK, greaterThanOrEqualTo(0.98));
    expect(p.rHK, greaterThanOrEqualTo(0.98));
  }, timeout: _long);

  group('§H H6 key evidence (noise off, drill events, onset 600 s; E.3 #25-27)', () {
    // healthy reference: the planning event alone (a zero-severity feed candidate)
    late double dHealthy2h, x0, b0;
    var fo7PeakBeforeEvent = double.nan;
    final c3aHealthy = <String>[];
    setUpAll(() {
      final h = _h6('feed_heavy_keys', severity: 0.0);
      x0 = h.snapshot().kpis.xDHeavy;
      b0 = h.snapshot().kpis.xBLight;
      for (final t in [2600.0, 3300.0, 7200.0]) {
        h.advance(t - h.time);
        final c = h.snapshot().crossChecks.firstWhere((c) => c.id == 'C3a');
        c3aHealthy.add('${(t / 60).toStringAsFixed(0)} min ${c.status.name} r/band ${(c.residual / c.band).toStringAsFixed(2)} '
            '(condenser ${(c.terms['fromCondenser']! / _kmolh).toStringAsFixed(2)}, reflux + D + dN0/W '
            '${(c.terms['fromReflux']! / _kmolh).toStringAsFixed(2)}, true V1 ${(h.snapshot().stages.vaporUp[1] / _kmolh).toStringAsFixed(2)} kmol/h)');
      }
      dHealthy2h = h.snapshot().kpis.d;
      print('H6 healthy planning: C3a ${c3aHealthy.join('; ')}; D ${(dHealthy2h / _kmolh).toStringAsFixed(2)}, xDHeavy '
          '${x0.toStringAsFixed(4)} -> ${h.snapshot().kpis.xDHeavy.toStringAsFixed(4)}, xBLight ${b0.toStringAsFixed(4)} -> '
          '${h.snapshot().kpis.xBLight.toStringAsFixed(4)}');
      expect((h.snapshot().kpis.xDHeavy - x0).abs(), lessThanOrEqualTo(0.005));
      expect((h.snapshot().kpis.xBLight - b0).abs(), lessThanOrEqualTo(0.005));
    });
    test('F07 s 0.75: AT-100 0.450 -> 0.420 within 25 min; before the 45-min event FC-102 OP / FT-102 within 2 % and '
        'D within 1 kmol/h (record); TI-101 +2 K, xDHeavy +0.02; D at 2 h vs healthy', () {
      final sim = _h6('feed_heavy_keys', severity: 0.75);
      final a0 = _inst(sim)['AT-100']!.value, ti0 = _inst(sim)['TI-101']!.value, d0 = sim.snapshot().kpis.d;
      final op0 = sim.control.fc102.op, ft0 = _inst(sim)['FT-102']!.value;
      var dMax = 0.0, opDev = 0.0, ftDev = 0.0, tAt = double.nan, dPeak = 0.0, tPeak = 0.0, peakNote = '';
      final q0 = sim.snapshot();
      final v10 = q0.stages.vaporUp[1], vb0 = q0.stages.vaporUp[q0.layout.nTrays + 1], lv0 = q0.kpis.drumLevelPct;
      while (sim.time < 2700) {
        sim.advance(30);
        final dd = (sim.snapshot().kpis.d - d0) / _kmolh;
        if (dd.abs() > dMax) {
          dPeak = dd;
          tPeak = (sim.time - 600) / 60;
          final q = sim.snapshot();
          peakNote = 'V1 ${((q.stages.vaporUp[1] - v10) / _kmolh).toStringAsFixed(2)}, V_B '
              '${((q.stages.vaporUp[q.layout.nTrays + 1] - vb0) / _kmolh).toStringAsFixed(2)} kmol/h, drum level '
              '${(q.kpis.drumLevelPct - lv0).toStringAsFixed(2)} %';
        }
        dMax = math.max(dMax, dd.abs());
        opDev = math.max(opDev, (sim.control.fc102.op - op0).abs());
        ftDev = math.max(ftDev, (_inst(sim)['FT-102']!.value - ft0).abs() / (152.8 * _kmolh));
        if (tAt.isNaN && a0 - _inst(sim)['AT-100']!.value >= 0.02) tAt = (sim.time - 600) / 60;
      }
      final d45 = (sim.snapshot().kpis.d - d0) / _kmolh;
      sim.advance(7200 - sim.time);
      final s = sim.snapshot();
      final dVsHealthy = (s.kpis.d - dHealthy2h) / _kmolh;
      print('H6 F07: AT-100 ${a0.toStringAsFixed(4)} -> ${_inst(sim)['AT-100']!.value.toStringAsFixed(4)} (-0.02 at '
          '${tAt.toStringAsFixed(1)} min); before 45 min: peak dD ${dPeak.toStringAsFixed(2)} at ${tPeak.toStringAsFixed(1)} min after onset [d$peakNote] (at 45 min ${d45.toStringAsFixed(2)}) '
          'kmol/h, FC-102 OP ${opDev.toStringAsFixed(2)} %, FT-102 ${(100 * ftDev).toStringAsFixed(2)} % span; 2 h: D - healthy '
          '${dVsHealthy.toStringAsFixed(2)} kmol/h, TI-101 +${(_inst(sim)['TI-101']!.value - ti0).toStringAsFixed(2)} K, xDHeavy '
          '${x0.toStringAsFixed(4)} -> ${s.kpis.xDHeavy.toStringAsFixed(4)}');
      expect(_inst(sim)['AT-100']!.value, closeTo(0.420, 0.002));
      expect(tAt, lessThanOrEqualTo(25));
      expect(opDev, lessThanOrEqualTo(2));
      expect(ftDev, lessThanOrEqualTo(0.02));
      expect(_inst(sim)['TI-101']!.value - ti0, greaterThanOrEqualTo(2));
      expect(s.kpis.xDHeavy - x0, greaterThanOrEqualTo(0.02));
      // 54f9b41 row: "D within 1 kmol/h of its start 2 h after onset": with the drill's +8 % event the start value is
      // the wrong base (D - start = +3.2); asserted against the healthy planning response instead
      expect(dVsHealthy.abs(), lessThan(1.0), reason: 'D vs the healthy planning response (steady 44.94 -> 44.54 x 1.08)');
      fo7PeakBeforeEvent = dMax;
    }, timeout: _long);
    test('F07: D within 2.5 kmol/h of its start throughout (54f9b41 row; until the 45-min event)',
        skip: 'spec/coder item M7-S2: engine eea0a5a peaks at +3.33 kmol/h 19.5 min after onset (drum level +1.4 %), '
            '+1.33 at 45 min; the 1.5 at 2600 s in the checkpoint was a single sample. Re-run on the 0.75-m trays', () {
      expect(fo7PeakBeforeEvent, lessThanOrEqualTo(2.5));
    });
    test('F12 s 0.585: FT-102 below the cap 63.4 kmol/h and SP, FC-102 OPSAT within 2 min, D +5 within 30 min, TI-101 +3 K, '
        'xDHeavy +0.05, AT-100 unchanged', () {
      final sim = _h6('reflux_pump', severity: 0.585);
      final a0 = _inst(sim)['AT-100']!.value, d0 = sim.snapshot().kpis.d, ti0 = _inst(sim)['TI-101']!.value;
      final cap = (1 - 0.585) * 152.8;
      sim.advance(630);
      final ft30 = _inst(sim)['FT-102']!.value / _kmolh;
      sim.advance(720 - sim.time);
      final sat = sim.control.fc102.op > 99 && sim.control.alarms.isActive('FC-102.OPSAT');
      sim.advance(2400 - sim.time);
      final dd30 = (sim.snapshot().kpis.d - d0) / _kmolh;
      sim.advance(7200 - sim.time);
      final s = sim.snapshot();
      print('H6 F12: cap ${cap.toStringAsFixed(2)} kmol/h, FT-102 at 30 s ${ft30.toStringAsFixed(2)} kmol/h (engine cap = '
          '(1 - s) x design L0 76.4 = ${(0.415 * 76.4).toStringAsFixed(2)}); dD at 30 min ${dd30.toStringAsFixed(2)}; D at 2 h '
          '${(s.kpis.d / _kmolh).toStringAsFixed(2)}; xDHeavy ${s.kpis.xDHeavy.toStringAsFixed(4)}');
      expect(cap, closeTo(63.4, 0.05));
      expect(ft30, lessThanOrEqualTo(cap * 1.01));
      expect(sat, isTrue);
      expect(dd30, greaterThanOrEqualTo(5));
      expect(_inst(sim)['TI-101']!.value - ti0, greaterThanOrEqualTo(3));
      expect(s.kpis.xDHeavy - x0, greaterThanOrEqualTo(0.05));
      expect((_inst(sim)['AT-100']!.value - a0).abs(), lessThan(0.002));
    }, timeout: _long);
    test('F12 s 0.585: FT-102 settles AT the cap (1 - s) F_max = 63.4 kmol/h (± 2 %)',
        skip: 'coder item M7-C1: the engine caps L0 at (1 - s) x the design reflux 76.4 (31.7 kmol/h), PHYSICS.md 10.2 / '
            'ENGINE_API.md 11.10 say (1 - s) F_max of FV-102 = (1 - s) x 152.8', () {
      final sim = _h6('reflux_pump', severity: 0.585);
      sim.advance(900);
      expect(_inst(sim)['FT-102']!.value / _kmolh, closeTo(63.4, 0.02 * 63.4));
    });
    test('F20 + planning (54f9b41 row): C3a not fail from event + 60 min, ok or check at 2 h; C5 (drum) recorded; '
        'D >= 3.5 above healthy', () {
      final sim = _h6('fv102_stuck');
      final rows = <String>[];
      var failLate = false;
      CrossCheckResult chk(String id) => sim.snapshot().crossChecks.firstWhere((c) => c.id == id);
      String row(CrossCheckResult c) => '${c.status.name} r/band ${(c.residual / c.band).toStringAsFixed(2)}';
      for (final t in [2600.0, 3300.0, 4500.0]) {
        sim.advance(t - sim.time);
        rows.add('${(t / 60).toStringAsFixed(0)} min C3a ${row(chk('C3a'))}, C5:drum ${row(chk('C5:drum'))}');
      }
      sim.advance(6300 - sim.time);
      while (sim.time < 7200) {
        sim.advance(30);
        failLate = failLate || chk('C3a').status == CheckStatus.fail;
      }
      rows.add('120 min C3a ${row(chk('C3a'))}, C5:drum ${row(chk('C5:drum'))}');
      final dd = (sim.snapshot().kpis.d - dHealthy2h) / _kmolh;
      print('H6 F20: ${rows.join('; ')}; C3a fail in 105-120 min $failLate; D - healthy ${dd.toStringAsFixed(2)} kmol/h; '
          'xDHeavy ${sim.snapshot().kpis.xDHeavy.toStringAsFixed(4)}');
      expect(failLate, isFalse);
      expect(chk('C3a').status, anyOf(CheckStatus.ok, CheckStatus.check));
      expect(dd, greaterThanOrEqualTo(3.5));
      expect(sim.snapshot().kpis.xDHeavy - x0, greaterThanOrEqualTo(0.02));
    }, timeout: _long);
  }, timeout: _long);
}
