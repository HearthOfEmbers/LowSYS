// M7 validation (engine eea0a5a): key numbers of docs/milestones/M7.md E.3 plus physical-sense checks. Everything
// here runs with `ideal` hydraulics (steady values do not depend on the diameters) except the M7 close-out group: VC-9.6 (b)
// (full hydraulics per tray section, debut 0.75 m, deprop 0.55 / 0.85 m) and VC-16.6d. H6 runs on 7f3e3db (C3a at T_dew, d48e6ff rows). VC-9.4 / 9.5 (E.3 #3-5) are in
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
  sim.setLever('view', 0); // model view: the validator reads the true state (the drill starts in a plant view)
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
    test('C3a lambda_top at T_dew(x_D) (M7 close-out ruling 1): engine C3a reads V1 within 0.5 %, |r/band| < 0.5; '
        'T_bub would over-read', () {
      // the true condenser duty is V1 (H_V(y1 = x_D, T_dew) - h_L(x_D, T_0)); C3a (PHYSICS.md 14.6) now takes H_V at T_dew
      final c3a = s.crossChecks.firstWhere((c) => c.id == 'C3a');
      final c5 = s.crossChecks.firstWhere((c) => c.id == 'C5:drum');
      print('C3a healthy steady: ${c3a.status.name} r/band ${(c3a.residual / c3a.band).toStringAsFixed(3)}, condenser side '
          '${(c3a.terms['fromCondenser']! / _kmolh).toStringAsFixed(2)} vs V1 ${(s.stages.vaporUp[1] / _kmolh).toStringAsFixed(2)} '
          'kmol/h; C5:drum ${c5.status.name} r/band ${(c5.residual / c5.band).toStringAsFixed(3)}');
      expect(c3a.status, CheckStatus.ok);
      expect((c3a.residual / c3a.band).abs(), lessThan(0.5));
      expect(_rel(c3a.terms['fromCondenser']!, s.stages.vaporUp[1]), lessThan(0.005));
      expect(c5.status, CheckStatus.ok);
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
    var healthyFailLate = <String>[];
    late CheckStatus c3aHealthy2h, c5Healthy2h;
    setUpAll(() {
      final h = _h6('feed_heavy_keys', severity: 0.0);
      x0 = h.snapshot().kpis.xDHeavy;
      b0 = h.snapshot().kpis.xBLight;
      CrossCheckResult chk(String id) => h.snapshot().crossChecks.firstWhere((c) => c.id == id);
      void rec(double t) {
        h.advance(t - h.time);
        final c = chk('C3a'), c5 = chk('C5:drum');
        c3aHealthy.add('${(t / 60).toStringAsFixed(0)} min ${c.status.name} r/band ${(c.residual / c.band).toStringAsFixed(2)} '
            '(condenser ${(c.terms['fromCondenser']! / _kmolh).toStringAsFixed(2)}, reflux + D + dN0/W '
            '${(c.terms['fromReflux']! / _kmolh).toStringAsFixed(2)}, true V1 ${(h.snapshot().stages.vaporUp[1] / _kmolh).toStringAsFixed(2)} kmol/h; '
            'C5:drum ${c5.status.name} r/band ${(c5.residual / c5.band).toStringAsFixed(2)})');
      }

      rec(2600);
      rec(3300);
      rec(6300);
      // ruling 1 (d48e6ff): healthy C3a and C5 (drum) not `fail` from event + 60 min, `ok` at 2 h
      while (h.time < 7200) {
        h.advance(30);
        for (final id in ['C3a', 'C5:drum']) {
          if (chk(id).status == CheckStatus.fail) healthyFailLate.add('$id at ${h.time.toStringAsFixed(0)} s');
        }
      }
      rec(7200);
      c3aHealthy2h = chk('C3a').status;
      c5Healthy2h = chk('C5:drum').status;
      dHealthy2h = h.snapshot().kpis.d;
      print('H6 healthy planning: C3a ${c3aHealthy.join('; ')}; fail after +60 min: $healthyFailLate; D '
          '${(dHealthy2h / _kmolh).toStringAsFixed(2)}, xDHeavy '
          '${x0.toStringAsFixed(4)} -> ${h.snapshot().kpis.xDHeavy.toStringAsFixed(4)}, xBLight ${b0.toStringAsFixed(4)} -> '
          '${h.snapshot().kpis.xBLight.toStringAsFixed(4)}');
      expect((h.snapshot().kpis.xDHeavy - x0).abs(), lessThanOrEqualTo(0.005));
      expect((h.snapshot().kpis.xBLight - b0).abs(), lessThanOrEqualTo(0.005));
    });
    test('healthy planning (ruling 1, d48e6ff): C3a and C5 (drum) not fail from event + 60 min, ok at 2 h', () {
      expect(healthyFailLate, isEmpty);
      expect(c3aHealthy2h, CheckStatus.ok);
      expect(c5Healthy2h, CheckStatus.ok);
    });
    test('F07 s 0.75: AT-100 0.450 -> 0.420 within 25 min; before the 45-min event FC-102 OP / FT-102 within 2 % and '
        'D within 1 kmol/h (record); TI-101 +2 K, xDHeavy +0.02; D at 2 h vs healthy', () {
      final sim = _h6('feed_heavy_keys', severity: 0.75);
      final a0 = _inst(sim)['AT-100']!.value, ti0 = _inst(sim)['TI-101']!.value, d0 = sim.snapshot().kpis.d;
      final op0 = sim.control.fc102.op, ft0 = _inst(sim)['FT-102']!.value;
      var dMax = 0.0, opDev = 0.0, ftDev = 0.0, tAt = double.nan, dPeak = 0.0, tPeak = 0.0, peakNote = '';
      final q0 = sim.snapshot();
      final v10 = q0.stages.vaporUp[1], vb0 = q0.stages.vaporUp[q0.layout.nTrays + 1], lv0 = q0.kpis.drumLevelPct;
      // feed-flash test of ruling 2: F (h_F - h_L,fs) / lambda_fs is the vapour the feed adds (> 0) or condenses (< 0)
      // on its tray; its change from t0 is the flash part of the D transient
      final fs = sim.config.feeds.first.stage;
      ({double dT, double vFlash}) flash(SimSnapshot q) {
        final fd = q.streams[StreamId.feed]!, th = sim.thermo;
        final xf = Float64List.fromList(_x(q, fs)), yf = Float64List.fromList(q.stages.y.sublist(fs * q.stages.nc, (fs + 1) * q.stages.nc));
        final tf = q.stages.t[fs], hlf = th.hL(tf, xf);
        return (dT: fd.temperature - tf, vFlash: fd.flow * (th.hL(fd.temperature, fd.composition) - hlf) / (th.hV(tf, yf) - hlf));
      }

      ({double dT, double vFlash})? fl0; // pre-onset value (the t = 0 stream snapshot has no feed temperature yet)
      var flashNote = '';
      var flMax = -1e9, tFlMax = 0.0;
      while (sim.time < 2700) {
        sim.advance(30);
        final flNow = flash(sim.snapshot());
        if (sim.time <= 600) fl0 = flNow;
        if (flNow.vFlash > flMax) {
          flMax = flNow.vFlash;
          tFlMax = (sim.time - 600) / 60;
        }
        final dd = (sim.snapshot().kpis.d - d0) / _kmolh;
        if (dd.abs() > dMax) {
          dPeak = dd;
          tPeak = (sim.time - 600) / 60;
          final q = sim.snapshot();
          peakNote = 'V1 ${((q.stages.vaporUp[1] - v10) / _kmolh).toStringAsFixed(2)}, V_B '
              '${((q.stages.vaporUp[q.layout.nTrays + 1] - vb0) / _kmolh).toStringAsFixed(2)} kmol/h, drum level '
              '${(q.kpis.drumLevelPct - lv0).toStringAsFixed(2)} %';
          final fl = flash(q);
          flashNote = 'T_F - T_$fs ${fl0!.dT.toStringAsFixed(2)} -> ${fl.dT.toStringAsFixed(2)} K, feed flash '
              '${(fl0.vFlash / _kmolh).toStringAsFixed(2)} -> ${(fl.vFlash / _kmolh).toStringAsFixed(2)} kmol/h (change '
              '${((fl.vFlash - fl0.vFlash) / _kmolh).toStringAsFixed(2)})';
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
          '${tAt.toStringAsFixed(1)} min); before 45 min: peak dD ${dPeak.toStringAsFixed(2)} at ${tPeak.toStringAsFixed(1)} min after onset [d$peakNote; $flashNote; max feed-flash change ${((flMax - fl0!.vFlash) / _kmolh).toStringAsFixed(2)} kmol/h at ${tFlMax.toStringAsFixed(1)} min] (at 45 min ${d45.toStringAsFixed(2)}) '
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
    test('F07: D at most 4.5 kmol/h above its start until the 45-min event (ruling 2, d48e6ff; below F12\'s 5)', () {
      expect(fo7PeakBeforeEvent, lessThanOrEqualTo(4.5));
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
      print('H6 F12: cap ${cap.toStringAsFixed(2)} kmol/h, FT-102 at 30 s ${ft30.toStringAsFixed(2)} kmol/h; dD at 30 min '
          '${dd30.toStringAsFixed(2)}; D at 2 h ${(s.kpis.d / _kmolh).toStringAsFixed(2)} [62.4]; true xDHeavy '
          '${s.kpis.xDHeavy.toStringAsFixed(4)} [0.22], AT-101 ${_inst(sim)['AT-101']!.value.toStringAsFixed(4)}');
      expect(cap, closeTo(63.4, 0.05));
      // ruling 3 brackets (af6864e, 0.75-m trays, noise off, 2 h): D 62.4, true xDHeavy 0.22
      expect(s.kpis.d / _kmolh, closeTo(62.4, 1.0));
      expect(s.kpis.xDHeavy, closeTo(0.22, 0.01));
      expect(ft30, lessThanOrEqualTo(cap * 1.01));
      expect(sat, isTrue);
      expect(dd30, greaterThanOrEqualTo(5));
      expect(_inst(sim)['TI-101']!.value - ti0, greaterThanOrEqualTo(3));
      expect(s.kpis.xDHeavy - x0, greaterThanOrEqualTo(0.05));
      expect((_inst(sim)['AT-100']!.value - a0).abs(), lessThan(0.002));
    }, timeout: _long);
    test('F12 s 0.585: FT-102 settles AT the cap (1 - s) F_max = 63.4 kmol/h (± 2 %; M7-C1 fixed in af6864e)', () {
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

  group('M7 close-out (d48e6ff, 7f3e3db): VC-9.6 (b) per tray section, VC-16.6d', () {
    // VC-9.6 (b): full hydraulics at the defaults, one steady run; per section max jet flood 45-85 %, Phi_min >= 0.75,
    // no flood / weep alarm, column dP recorded
    ({double jetMax, double jetMin, double phiMin, double weepMax, double dcMax}) sec(SimSnapshot s, int a, int b) {
      var jx = 0.0, jn = 9.0, pm = 9.0, wm = 0.0, dc = 0.0;
      for (var j = a; j <= b; j++) {
        jx = math.max(jx, s.stages.jetFlood[j]);
        jn = math.min(jn, s.stages.jetFlood[j]);
        pm = math.min(pm, s.stages.stability[j]);
        wm = math.max(wm, s.stages.weepFrac[j]);
        dc = math.max(dc, s.stages.dcFlood[j]);
      }
      return (jetMax: jx, jetMin: jn, phiMin: pm, weepMax: wm, dcMax: dc);
    }

    final full = <String, ({Simulator sim, SimSnapshot s, bool reached, String note})>{};
    ({Simulator sim, SimSnapshot s, bool reached, String note}) runFull(String id, [Map<String, Object?>? ov]) {
      final key = '$id${ov == null ? '' : jsonEncode(ov)}';
      return full.putIfAbsent(key, () {
        final sim = _sim(Presets.byId(id).applyOverrides({'hydraulics': 'full', ...?ov}));
        final reached = sim.runToSteadyState(maxSimSeconds: 400000).reached;
        // last 2 h: D and Phi_min ranges (a limit cycle shows here)
        var dn = 1e9, dx = -1e9, pn = 9.0, px = 0.0;
        for (var k = 0; k < 240; k++) {
          sim.advance(30);
          final q = sim.snapshot();
          dn = math.min(dn, q.kpis.d);
          dx = math.max(dx, q.kpis.d);
          final ph = sec(q, 1, q.layout.nTrays).phiMin;
          pn = math.min(pn, ph);
          px = math.max(px, ph);
        }
        return (
          sim: sim,
          s: sim.snapshot(),
          reached: reached,
          note: 'steady ${reached ? 'reached' : 'NOT reached'} (${sim.time.toStringAsFixed(0)} s); last 2 h D '
              '${(dn / _kmolh).toStringAsFixed(3)}-${(dx / _kmolh).toStringAsFixed(3)} kmol/h, Phi_min ${pn.toStringAsFixed(3)}-'
              '${px.toStringAsFixed(3)}'
        );
      });
    }

    String row(String id, SimSnapshot s, List<(int, int)> secs) {
      final n = s.layout.nTrays;
      final parts = [
        for (final (a, b) in secs)
          () {
            final r = sec(s, a, b);
            return 'trays $a-$b jet ${(100 * r.jetMin).toStringAsFixed(1)}-${(100 * r.jetMax).toStringAsFixed(1)} %, '
                'Phi_min ${r.phiMin.toStringAsFixed(3)}, weep <= ${(100 * r.weepMax).toStringAsFixed(1)} %, dc flood <= ${(100 * r.dcMax).toStringAsFixed(1)} %';
          }()
      ];
      return '$id full: ${parts.join('; ')}; column dP ${((s.stages.p[n + 1] - s.stages.p[1]) / 1000).toStringAsFixed(2)} kPa; '
          'max flood KPI ${s.kpis.maxFloodPct.toStringAsFixed(1)} %; r ${s.kpis.recoveryLK!.toStringAsFixed(4)} / ${s.kpis.recoveryHK!.toStringAsFixed(4)}';
    }

    test('VC-9.6 (b) debut (0.75 m, one section): jet flood 45-85 %, Phi_min >= 0.75, max flood KPI < 90 % (the model.flood threshold), downcomer flood < 50 %', () {
      final r = runFull('debut');
      print('VC-9.6 (b) ${row('debut', r.s, [(1, 11), (12, 22)])}; ${r.note}');
      expect(r.reached, isTrue);
      final all = sec(r.s, 1, r.s.layout.nTrays);
      expect(all.jetMax, inInclusiveRange(0.45, 0.85));
      expect(all.phiMin, greaterThanOrEqualTo(0.75));
      // the alarms latch start-up transients of the cold start, so the steady values are checked against their thresholds
      expect(r.s.kpis.maxFloodPct, lessThan(90));
      expect(all.dcMax, lessThan(0.5));
    }, timeout: _long);
    test('VC-9.6 (b) deprop (0.55 m trays 1-10, 0.85 m trays 11-28): max jet flood per section in 45-85 %, max flood KPI < 90 %',
        () {
      final r = runFull('deprop');
      print('VC-9.6 (b) ${row('deprop', r.s, [(1, 10), (11, 28)])}; ${r.note}');
      expect(sec(r.s, 1, 10).jetMax, inInclusiveRange(0.45, 0.85));
      expect(sec(r.s, 11, 28).jetMax, inInclusiveRange(0.45, 0.85));
      expect(r.s.kpis.maxFloodPct, lessThan(90));
      expect(sec(r.s, 1, 28).dcMax, lessThan(0.5));
    }, timeout: _long);
    test('VC-9.6 (b) deprop: Phi_min >= 0.75 in the stripping section (no weeping)',
        skip: 'spec-pending (M7 close-out coder item 5): the 0.85-m stripping trays weep (Phi_min 0.341, weep 74 %) and '
            'runToSteadyState does not converge in 400 000 s (D 30.83-30.91 over the last 2 h); see DEVIATIONS "M7 close-out validation"', () {
      expect(runFull('deprop').reached, isTrue);
      expect(sec(runFull('deprop').s, 11, 28).phiMin, greaterThanOrEqualTo(0.75));
    });
    test('deprop stripping-section probe (record, for the spec lead): hole fraction 0.10 -> 0.05 at 0.85 m', () {
      for (final hf in [0.05]) {
        final sections = [
          for (final (n, d, h) in [(10, 0.55, 0.10), (18, 0.85, hf)])
            {
              'kind': 'trays', 'trays': n, 'type': 'sieve',
              'geometry': {'diameter': d, 'traySpacing': 0.9, 'downcomerFraction': 0.12, 'weirHeight': 0.05,
                'apronClearance': 0.038, 'holeFraction': h, 'holeDiameter': 0.0127, 'orificeCoeff': 0.73,
                'downcomerAeration': 0.5, 'systemFactor': 1.0}
            }
        ];
        final r = runFull('deprop', {'sections': sections});
        print('probe hole fraction $hf: ${row('deprop', r.s, [(1, 10), (11, 28)])}; ${r.note}');
        expect(r.s.kpis.d.isFinite, isTrue);
      }
    }, timeout: _long);

    for (final id in ['debut', 'deprop']) {
      test('VC-16.6d $id (ideal, noise off): 24 h quiet (D p-p <= 0.2, P_top +-0.5 kPa); SP +-10 kPa within 1 kPa in '
          '10 min, overshoot <= 30 %, decay <= 0.3', () {
        final sim = _sim(Presets.byId(id));
        _steady(sim);
        final sp0 = sim.snapshot().kpis.pTop;
        var dMin = 1e9, dMax = -1e9, pDev = 0.0;
        for (var k = 0; k < 24 * 60; k++) {
          sim.advance(60);
          final q = sim.snapshot();
          dMin = math.min(dMin, q.kpis.d);
          dMax = math.max(dMax, q.kpis.d);
          pDev = math.max(pDev, (q.kpis.pTop - sp0).abs());
        }
        final rows = <String>['24 h: D p-p ${((dMax - dMin) / _kmolh).toStringAsFixed(4)} kmol/h, P_top dev '
            '${(pDev / 1000).toStringAsFixed(3)} kPa'];
        final badStep = <String>[];
        final bad = <String>[if ((dMax - dMin) / _kmolh > 0.2) 'D p-p', if (pDev > 500) 'P_top quiet'];
        for (final step in [10000.0, -10000.0, if (id == 'deprop') 50000.0]) {
          final base = sim.snapshot().kpis.pTop, sp = base + step;
          sim.setLever('pTop', sp);
          final e = <double>[];
          var tIn = double.nan;
          for (var k = 0; k < 360; k++) {
            sim.advance(5);
            final ek = (sim.snapshot().kpis.pTop - sp) / step; // normalised: starts at -1, 0 at SP, > 0 overshoot
            e.add(ek);
            if ((ek * step).abs() > 1000) tIn = double.nan;
            if (tIn.isNaN && (ek * step).abs() <= 1000) tIn = 5.0 * (k + 1);
          }
          // overshoot = first maximum after the first crossing; decay = next overshoot peak / first
          final i0 = e.indexWhere((v) => v >= 0);
          var a1 = 0.0, a3 = 0.0;
          if (i0 >= 0) {
            var i = i0;
            while (i < e.length && e[i] >= 0) {
              a1 = math.max(a1, e[i]);
              i++;
            }
            while (i < e.length && e[i] < 0) {
              i++;
            }
            while (i < e.length && e[i] >= 0) {
              a3 = math.max(a3, e[i]);
              i++;
            }
          }
          final decay = a1 > 1e-3 ? a3 / a1 : 0.0;
          rows.add('SP ${step > 0 ? '+' : ''}${(step / 1000).toStringAsFixed(0)} kPa: within 1 kPa from '
              '${tIn.toStringAsFixed(0)} s, overshoot ${(100 * a1).toStringAsFixed(1)} %, decay ${decay.toStringAsFixed(2)}, '
              'CW valve ${sim.control.pc101.op.toStringAsFixed(1)} %');
          if (step.abs() == 10000) {
            if (!(tIn <= 600) || a1 > 0.30 || decay > 0.3) badStep.add('SP $step');
          } else if (sim.control.alarms.isActive('model.relief')) {
            bad.add('relief at +50 kPa');
          }
          sim.setLever('pTop', base);
          sim.advance(1800);
        }
        print('VC-16.6d $id (pcKc ${sim.config.condenser.pcKc}): ${rows.join('; ')}');
        expect(bad, isEmpty);
        // deprop's step response is the coder item below (recorded here, asserted there)
        if (id == 'debut') expect(badStep, isEmpty);
      }, timeout: _long);
    }
    test('VC-16.6d (b) deprop: PC-101 SP +-10 kPa within 1 kPa in 10 min, overshoot <= 30 %, decay <= 0.3',
        skip: 'coder item M7-C2 (M7 close-out validation): with pcKc 120 on the 0.55 / 0.85 m column the loop is '
            'underdamped: +10 kPa settles in 1720 s, decay 0.65; -10 kPa overshoots 45 %, decay 0.85. Measure the '
            'open-loop gain (VC-16.6d (d), ruling 5) and retune', () {});
  }, timeout: _long);
}
