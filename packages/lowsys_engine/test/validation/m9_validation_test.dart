// M9 validation (validator, engine e16e897..d5ead9a, app 89958b3): crude fractionation, VC-15 key numbers.
// [I] rows are checked against the printed values AND an independent reference written from the spec text
// (reference/crude_reference.dart: 9.1 correlations, LK, (9.1)-(9.2), Daubert, product path, feed flash).
// [P] rows are engine steady states against the prototype values (docs/milestones/M9.md E.3), plus physical-sense and
// direction checks the coder's test/m9_*_test.dart do not cover (COT 360, PA 0 / 6 MW, bottom steam 0 / 3000,
// H - h over the stages, profile shape, dt independence, F25 s = 0.5 timeline, F24 SP raise, G16 timing).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/crude_reference.dart';

double _c(double k) => k - 273.15;

Simulator _sim({Map<String, double> levers = const {}, double dt = 0.5}) {
  final s = Simulator(Presets.byId('crude'), options: SimOptions(seed: 1, measurementNoise: false, dt: dt));
  for (final e in levers.entries) {
    s.setLever(e.key, e.value);
  }
  return s;
}

Simulator _steady(Simulator s) {
  final r = s.runToSteadyState(maxSimSeconds: 172800);
  if (!r.reached && r.residual > 5e-3) throw StateError('no steady state, residual ${r.residual}');
  return s;
}

CrudeProductKpis _k(Simulator s) => s.snapshot().kpis.crude!;
double _ti(Simulator s, String tag) => s.snapshot().instruments.firstWhere((i) => i.tag == tag).value;

void main() {
  final pcs = pseudoRef();
  final th = CrudeThermo();

  group('VC-15.1-15.3 [I]: engine = independent reference = printed', () {
    test('E.3 #1: PC1 / PC5 / PC9 T_b, MW, omega, dH_vap(T_b); whole 9.1 table within the VC-15.1 tolerances', () {
      const ref = {
        0: [61.67, 82.52, 0.2227, 27.967],
        4: [275.00, 206.17, 0.5899, 49.384],
        8: [613.93, 504.12, 1.5647, 100.963],
      };
      ref.forEach((i, v) {
        expect(_c(pcs[i].tb), closeTo(v[0], 0.01));
        expect(pcs[i].mw, closeTo(v[1], 0.01));
        expect(pcs[i].omega, closeTo(v[2], 1e-4));
        expect(pcs[i].dHvap / 1000, closeTo(v[3], 0.002));
      });
      const tableVol = [0.0833, 0.0936, 0.0769, 0.0795, 0.0833, 0.0833, 0.1333, 0.1524, 0.2143];
      const tablePc = [36.21, 28.32, 23.12, 19.59, 16.95, 14.82, 12.74, 10.58, 8.08];
      for (var i = 0; i < 9; i++) {
        final p = pcs[i];
        expect(p.vol, closeTo(tableVol[i], 1e-4), reason: 'vol PC${i + 1}');
        expect(p.pcBar, closeTo(tablePc[i], 0.005), reason: 'Pc PC${i + 1}');
        expect(th.volFrac[i], closeTo(p.vol, 1e-4));
        expect(th.tb[i], closeTo(p.tb, 0.05));
        expect(th.pcs[i].info.sg, closeTo(p.sg, 1e-4));
        expect(th.mw[i], closeTo(p.mw, 0.05));
        expect(th.tc[i], closeTo(p.tc, 0.05));
        expect(math.exp(th.lnPc[i]) / 1e5, closeTo(p.pcBar, 0.005));
        expect(th.om[i], closeTo(p.omega, 1e-4));
        expect(th.dhb[i] / 1000, closeTo(p.dHvap / 1000, 0.01));
        expect(th.cp0[i], closeTo(p.cp0, 0.05));
        expect(th.dcp[i], closeTo(p.dcp, 1e-3));
        expect(th.psat(i, p.tb) / 101325, closeTo(1, 1e-6), reason: 'omega consistency PC${i + 1}');
      }
    });

    test('E.3 #2: bulk SG 0.8656, 31.96 API, MW 216.87; 132.5 m3/h = 528.36 kmol/h, 114.58 t/h', () {
      final (sg, api, mw, molPerM3, kgPerM3) = bulkRef(pcs);
      expect(sg, closeTo(0.8656, 1e-4));
      expect(api, closeTo(31.96, 0.01));
      expect(mw, closeTo(216.87, 0.01));
      expect(132.5 * molPerM3 / 1000, closeTo(528.36, 0.05));
      expect(132.5 * kgPerM3 / 1000, closeTo(114.58, 0.05));
      final z = th.feedZ();
      var mwE = 0.0;
      for (var i = 0; i < 9; i++) {
        mwE += z[i] * th.mw[i];
      }
      expect(mwE, closeTo(mw, 0.1));
    });

    test('VC-15.1 P_sat spot values (1e-4 rel), reference and engine', () {
      final spots = [(0, 200.0, 1.9843e6), (0, 360.0, 1.6955e7), (4, 200.0, 1.4683e4), (4, 360.0, 4.6417e5), (8, 360.0, 91.577)];
      for (final (i, tC, v) in spots) {
        expect(pcs[i].psat(tC + 273.15) / v, closeTo(1, 1e-4), reason: 'ref PC${i + 1} $tC');
        expect(th.psat(i, tC + 273.15) / v, closeTo(1, 1e-4), reason: 'engine PC${i + 1} $tC');
      }
    });

    test('E.3 #3-4: Cp_V a/b; h_V on the 298 K basis (PC1 240/250 C 65.29/67.30, steam 200/350 C 49.80/55.18); '
        'steam 100->200 C 3.460 kJ/mol; h_L(T_b) = 0; h_V rises 300-700 K', () {
      const ab = {0: (37.069, 0.31724), 4: (89.044, 0.76203), 8: (207.707, 1.77755)};
      ab.forEach((i, v) {
        expect(pcs[i].aV / v.$1, closeTo(1, 1e-3));
        expect(pcs[i].bV / v.$2, closeTo(1, 1e-3));
        expect(th.cvA[i] / v.$1, closeTo(1, 1e-3));
        expect(th.cvB[i] / v.$2, closeTo(1, 1e-3));
      });
      double h298(PcRef p, double tC) => (p.hV(tC + 273.15) - p.hL(298.15)) / 1000;
      expect(h298(pcs[0], 240), closeTo(65.29, 0.01));
      expect(h298(pcs[0], 250), closeTo(67.30, 0.01));
      expect((th.hVi(0, 513.15) - th.hLi(0, 298.15)) / 1000, closeTo(65.29, 0.01));
      expect((th.hVwater(473.15) - th.hLwater(298.15)) / 1000, closeTo(49.80, 0.01));
      expect((th.hVwater(623.15) - th.hLwater(298.15)) / 1000, closeTo(55.18, 0.01));
      expect(hVsteamDiff(373.15, 473.15) / 1000, closeTo(3.460, 0.001));
      expect((th.hVwater(473.15) - th.hVwater(373.15)) / 1000, closeTo(3.460, 0.001));
      for (var i = 0; i < 9; i++) {
        expect(th.hLi(i, th.tb[i]).abs(), lessThan(1e-6));
        expect(th.hVi(i, th.tb[i]), closeTo(th.dhb[i], 1e-6));
        for (var t = 300.0; t < 700; t += 10) {
          expect(th.hVi(i, t + 10), greaterThan(th.hVi(i, t)));
          expect(th.hVi(i, t), closeTo(pcs[i].hV(t), 2.0), reason: 'h_V engine = ref PC${i + 1} ${t}K');
          expect(th.hLi(i, t), closeTo(pcs[i].hL(t), 2.0), reason: 'h_L engine = ref PC${i + 1} ${t}K');
        }
      }
    });

    test('E.3 #5 / VC-15.2: Daubert D86 0/5/10/30/50/70/90/95/100 % (0.01 K), reference and engine', () {
      const tbp = <double>[150, 165, 180, 200, 220, 240, 255];
      const d86 = [173.46, 175.84, 178.22, 184.23, 196.45, 210.62, 225.28, 232.60, 239.92];
      final r = daubertRef(tbp);
      final e = CrudeProducts.d86([for (final t in tbp) t + 273.15]);
      for (var i = 0; i < 9; i++) {
        expect(r[i], closeTo(d86[i], 0.01), reason: 'ref $i');
        expect(_c(e[i]), closeTo(d86[i], 0.01), reason: 'engine $i');
      }
    });

    test('E.3 #6-7 / VC-15.3: ideal cuts (yields, D86 5/50/95, gaps) and lumped cuts (D86 5/95, gaps)', () {
      final products = CrudeProducts(th);
      const cuts = [(20.0, 165.0), (165.0, 240.0), (240.0, 340.0), (340.0, 370.0)];
      const yields = [20.00, 11.67, 16.67, 5.30];
      const d5 = [60.3, 183.7, 259.9, 339.7], d50 = [99.9, 199.2, 282.4, 344.4], d95 = [146.9, 223.9, 316.9, 353.1];
      const l5 = [59.1, 175.6, 246.4, 324.9], l95 = [158.2, 231.3, 324.6, 396.5];
      final ideal = <List<double>>[], lumped = <List<double>>[];
      for (var k = 0; k < 4; k++) {
        final (y, d) = idealCutRef(cuts[k].$1, cuts[k].$2);
        ideal.add(d);
        expect(y, closeTo(yields[k], 0.01));
        expect(d[1], closeTo(d5[k], 0.1));
        expect(d[4], closeTo(d50[k], 0.1));
        expect(d[7], closeTo(d95[k], 0.1));
        final e = products.idealCut(cuts[k].$1 + 273.15, cuts[k].$2 + 273.15);
        for (final j in [1, 4, 7]) {
          expect(_c(e[j]), closeTo(d[j], 0.01), reason: 'engine ideal cut $k point $j');
        }
        final l = lumpedCutRef(pcs, cuts[k].$1, cuts[k].$2);
        lumped.add(l);
        expect(l[1], closeTo(l5[k], 0.1), reason: 'lumped 5 % $k');
        expect(l[7], closeTo(l95[k], 0.1), reason: 'lumped 95 % $k');
        // the same volume shares through the engine's product path (mole fractions x_i = v_i / vStd_i)
        final v = [
          for (final c in pcs)
            math.max(0.0, assayVolAtC(math.min(cuts[k].$2, c.tHiC)) - assayVolAtC(math.max(cuts[k].$1, c.tLoC)))
        ];
        final x = [for (var i = 0; i < 9; i++) v[i] / th.vStd[i]];
        final sx = x.fold(0.0, (a, b) => a + b);
        final eD = products.productD86(Float64List.fromList([for (final xi in x) xi / sx]), 0);
        expect(_c(eD[1]), closeTo(l[1], 0.01));
        expect(_c(eD[7]), closeTo(l[7], 0.01));
      }
      expect(idealCutRef(370, 760).$1, closeTo(46.36, 0.01));
      expect(assayTbpAtC(assayVolAtC(370) + 0.05 * (100 - assayVolAtC(370))), closeTo(382.8, 0.1));
      const gI = [36.9, 36.0, 22.8], gL = [17.4, 15.1, 0.3];
      for (var k = 0; k < 3; k++) {
        expect(ideal[k + 1][1] - ideal[k][7], closeTo(gI[k], 0.1));
        expect(lumped[k + 1][1] - lumped[k][7], closeTo(gL[k], 0.1));
      }
    });

    test('9.2 feed flash at COT 345 C, P_26 1.699 bar: beta 0.6815 molar, 50.10 vol % of the crude', () {
      final (b, vol, _) = feedFlashRef(pcs, 618.15, 1.699e5);
      expect(b, closeTo(0.6815, 5e-4));
      expect(vol, closeTo(50.10, 0.05));
    });
  });

  group('VC-15.4 default steady state [P]', () {
    late Simulator sim;
    late SimSnapshot s0;
    setUpAll(() {
      sim = _sim();
      s0 = sim.snapshot();
    });

    test('E.3 #8-13 key numbers', () {
      final k = s0.kpis.crude!;
      const y = [19.75, 11.70, 16.70, 5.30, 46.55], ty = [0.3, 0.02, 0.02, 0.02, 0.3];
      for (var i = 0; i < 5; i++) {
        expect(k.yieldVolPct[i], closeTo(y[i], ty[i]), reason: 'yield $i');
      }
      expect(k.overflashVolPct, closeTo(4.60, 0.6));
      expect(_c(s0.stages.t[8]), closeTo(182.26, 1.5));
      expect(_c(s0.stages.t[21]), closeTo(322.55, 1.5));
      expect(_c(k.flashZoneT), closeTo(343.25, 1.5));
      expect(_c(k.bottomT), closeTo(331.09, 1.5));
      expect(s0.streams[StreamId.reflux]!.flow * 3.6, closeTo(316.1, 9.5));
      expect(k.qc / 1e6, closeTo(8.945, 0.27));
      expect(_c(k.d86p95[1]), closeTo(238.2, 3));
      expect(_c(k.d86p5[2]), closeTo(229.3, 3));
      expect(k.gapDieselKero, closeTo(-9.0, 4));
      expect(_c(k.residueTbp5), closeTo(358.8, 2));
      expect(s0.stages.p[26] / 1e5, closeTo(1.699, 0.02));
      expect(s0.kpis.maxFloodPct, closeTo(59.3, 4));
      // ignore: avoid_print
      print('default: yields ${k.yieldVolPct.map((v) => v.toStringAsFixed(2)).join(' / ')}, OF '
          '${k.overflashVolPct.toStringAsFixed(2)}, FZ ${_c(k.flashZoneT).toStringAsFixed(2)}, T30 '
          '${_c(k.bottomT).toStringAsFixed(2)}, QC ${(k.qc / 1e6).toStringAsFixed(3)}, gaps '
          '${k.gapKeroNaphtha.toStringAsFixed(1)} / ${k.gapDieselKero.toStringAsFixed(1)} / '
          '${k.gapAgoDiesel.toStringAsFixed(1)}, flood ${s0.kpis.maxFloodPct.toStringAsFixed(1)}');
    });

    test('physical sense: profile, strippers cooler than their draws, PA, D86 order, dew margin', () {
      final k = s0.kpis.crude!;
      for (var j = 1; j < 26; j++) {
        expect(s0.stages.t[j + 1], greaterThan(s0.stages.t[j]), reason: 'T rises down to the flash zone, stage $j');
      }
      for (var j = 26; j < 30; j++) {
        expect(s0.stages.t[j + 1], lessThan(s0.stages.t[j]), reason: 'steam stripping cools below the feed, $j');
      }
      const draw = [8, 15, 21];
      for (var m = 0; m < 3; m++) {
        final st = s0.strippers[m];
        expect(st.t[1], lessThan(s0.stages.t[draw[m]]), reason: 'stripper ${m + 1} bottom below its draw tray');
        expect(st.product, lessThan(st.draw));
        expect(st.draw - st.product, closeTo(st.vaporReturn, 1e-3 * st.draw), reason: 'stripper HC balance (vapour return is HC only)');
      }
      expect(k.paReturnT, lessThan(s0.stages.t[16]));
      for (var i = 0; i < 3; i++) {
        expect(k.d86p50[i + 1], greaterThan(k.d86p50[i]));
      }
      expect(k.waterDewMargin, closeTo(50.1, 2));
      expect(s0.solverHealth.negativeLatent, 0);
    });

    test('E.3 #15: H - h over stages 1-30 (independent enthalpies): min 41.0 +- 2, max 286.8 kJ/mol', () {
      var mn = 1e9, mx = -1e9;
      const nc = 10;
      for (var j = 1; j <= 30; j++) {
        final t = s0.stages.t[j];
        var hv = 0.0, hl = 0.0, yHc = 0.0;
        for (var i = 0; i < 9; i++) {
          hv += s0.stages.y[j * nc + i] * pcs[i].hV(t);
          yHc += s0.stages.y[j * nc + i];
          hl += s0.stages.x[j * nc + i] * pcs[i].hL(t);
        }
        final d = (hv / yHc - hl) / 1000;
        mn = math.min(mn, d);
        mx = math.max(mx, d);
      }
      // ignore: avoid_print
      print('H - h: ${mn.toStringAsFixed(1)} .. ${mx.toStringAsFixed(1)} kJ/mol');
      expect(mn, closeTo(41.0, 2));
      expect(mx, closeTo(286.8, 6));
    });

    test('closure: energy residual in W against Q_C + Q_PA (feed enthalpy from the reference flash); water', () {
      final k = s0.kpis.crude!;
      final (_, _, hF) = feedFlashRef(pcs, k.cot, s0.stages.p[26]);
      final fF = 132.5 / 3600 * bulkRef(pcs).$4; // mol/s
      final absW = s0.kpis.energyResidual * fF * hF;
      // ignore: avoid_print
      print('feed enthalpy ${(fF * hF / 1e6).toStringAsFixed(2)} MW (T_b basis), residual ${absW.toStringAsFixed(0)} W, '
          'Q_C + Q_PA ${((k.qc + k.qPa) / 1e6).toStringAsFixed(2)} MW');
      expect(absW.abs() / (k.qc + k.qPa), lessThan(1e-3));
      expect(s0.kpis.balanceResidual.abs(), lessThan(1e-4));
    });

    test('dt independence: from the dt-0.5 steady state, 1 h at dt 0.25 moves nothing (T 0.05 K, yields 0.01)', () {
      final s = _sim(dt: 0.25);
      final a = s.snapshot();
      s.advance(3600);
      final b = s.snapshot();
      for (var j = 1; j <= 30; j++) {
        expect(b.stages.t[j], closeTo(a.stages.t[j], 0.05), reason: 'stage $j');
      }
      for (var i = 0; i < 5; i++) {
        expect(b.kpis.crude!.yieldVolPct[i], closeTo(a.kpis.crude!.yieldVolPct[i], 0.01));
      }
      expect(a.stages.t[26], closeTo(s0.stages.t[26], 1e-6));
    });
  });

  group('direction checks not in test/m9_* [P]', () {
    test('E.3 #18: COT 360 C gives overflash 10.89 %; overflash rises with COT', () {
      final k = _k(_steady(_sim(levers: {'cot': 633.15})));
      expect(k.overflashVolPct, closeTo(10.89, 0.8));
      expect(k.overflashVolPct, greaterThan(6.56));
      // ignore: avoid_print
      print('COT 360: overflash ${k.overflashVolPct.toStringAsFixed(2)}');
    });

    test('E.3 #19: PA 0 and 6 MW: D-K +9.7 / -25.5 K, Q_C 13.69 / 8.09 MW (Q_C falls as PA duty rises)', () {
      final k0 = _k(_steady(_sim(levers: {'paDuty': 0})));
      final k6 = _k(_steady(_sim(levers: {'paDuty': 6e6})));
      expect(k0.gapDieselKero, closeTo(9.7, 4));
      expect(k0.qc / 1e6, closeTo(13.69, 13.69 * 0.03));
      expect(k6.gapDieselKero, closeTo(-25.5, 4));
      expect(k6.qc / 1e6, closeTo(8.09, 8.09 * 0.03));
      expect(_c(k6.d86p95[1]), closeTo(246.8, 3));
      // ignore: avoid_print
      print('PA 0 / 6 MW: D-K ${k0.gapDieselKero.toStringAsFixed(2)} / ${k6.gapDieselKero.toStringAsFixed(2)}, QC '
          '${(k0.qc / 1e6).toStringAsFixed(3)} / ${(k6.qc / 1e6).toStringAsFixed(3)}, kero95 ${_c(k6.d86p95[1]).toStringAsFixed(2)}');
    });

    test('9.8: bottom steam 0 / 3000 kg/h: residue 49.92 / 46.05 vol %', () {
      final k0 = _k(_steady(_sim(levers: {'steam.bottom': 0})));
      final k3 = _k(_steady(_sim(levers: {'steam.bottom': 3000 / 3600})));
      expect(k0.yieldVolPct[4], closeTo(49.92, 0.5));
      expect(k3.yieldVolPct[4], closeTo(46.05, 0.3));
      // ignore: avoid_print
      print('bottom steam 0 / 3000: residue ${k0.yieldVolPct[4].toStringAsFixed(2)} / ${k3.yieldVolPct[4].toStringAsFixed(2)}');
    });

    test('VC-15.6: PA 3 MW with SS2 steam 1000 kg/h: D-K +12.9 K, meets both specs, residue TBP 5 % >= 355 C', () {
      final k = _k(_steady(_sim(levers: {'paDuty': 3e6, 'steam.ss2': 1000 / 3600})));
      expect(k.gapDieselKero, closeTo(12.9, 3));
      expect(_c(k.d86p95[1]), lessThanOrEqualTo(235));
      expect(_c(k.residueTbp5), greaterThanOrEqualTo(355));
      // ignore: avoid_print
      print('PA 3 + SS2 1000: D-K ${k.gapDieselKero.toStringAsFixed(2)}, kero95 ${_c(k.d86p95[1]).toStringAsFixed(2)}, '
          'resTBP5 ${_c(k.residueTbp5).toStringAsFixed(2)}');
    });
  });

  group('faults and timing [P]', () {
    test('F25 s = 0.5: duty held; top / flash zone / bottom TIs within 1 K after 10 min; PA-zone TIs move ~4 K '
        '(the prototype gives the same steady shifts, so VC-15.5 "every TI" is a wording item)', () {
      final s = _sim();
      final tags = [for (var n = 341; n <= 353; n++) 'TI-$n'];
      final t0 = {for (final g in tags) g: _ti(s, g)};
      s.faults.inject(FaultSpec(
          type: FaultType.pumparoundTrip,
          location: const FaultLocation.equipment('pumparound'),
          severity: 0.5,
          onset: s.time));
      s.advance(600);
      for (final g in ['TI-341', 'TI-349', 'TI-350']) {
        expect(_ti(s, g), closeTo(t0[g]!, 1.0), reason: g);
      }
      expect(_k(s).qPa / 1e6, closeTo(5.0, 0.05));
      _steady(s);
      // prototype (tools/prototypes/m9, paFlowFrac 0.5, steady): stage 11 -4.27 K, stage 15 +3.96 K, stage 18 +1.22 K
      expect(_ti(s, 'TI-344') - t0['TI-344']!, closeTo(-4.27, 0.5));
      expect(_ti(s, 'TI-345') - t0['TI-345']!, closeTo(3.96, 0.5));
      expect(_ti(s, 'TI-346') - t0['TI-346']!, closeTo(1.22, 0.5));
    });

    test('closure at dry-draw states (5 % film floor): F27 kero 16 % and F24 bottom s = 1', () {
      final a = _steady(_sim(levers: {'drawRate.kero': 0.16 * 0.0368056}));
      final b = _sim();
      b.faults.inject(FaultSpec(
          type: FaultType.strippingSteamLoss,
          location: const FaultLocation.steam('bottom'),
          severity: 1.0,
          onset: b.time,
          ramp: 60));
      _steady(b);
      final fF = 132.5 / 3600 * bulkRef(pcs).$4;
      final absW = <double>[];
      for (final s in [a, b]) {
        final q = s.snapshot();
        final k = q.kpis.crude!;
        final w = q.kpis.energyResidual * fF * feedFlashRef(pcs, k.cot, q.stages.p[26]).$3;
        absW.add(w / (k.qc + k.qPa));
        // ignore: avoid_print
        print('dry draw ${k.drawDry}: mass residual ${q.kpis.balanceResidual.toStringAsExponential(2)}, energy '
            '${(w / 1e3).toStringAsFixed(1)} kW = ${(100 * absW.last).toStringAsFixed(3)} % of Q_C + Q_PA; T 26..30 '
            '${[for (var j = 26; j <= 30; j++) _c(q.stages.t[j]).toStringAsFixed(2)].join(' / ')}, V 27..30 '
            '${[for (var j = 27; j <= 30; j++) (q.stages.vaporUp[j] * 3.6).toStringAsFixed(1)].join(' / ')} kmol/h');
        expect(k.drawDry[2], isTrue);
        expect(q.kpis.balanceResidual.abs(), lessThan(1e-4));
      }
      expect(absW[0].abs(), lessThan(1e-3), reason: 'F27 kero 16 %: energy closes');
      // F24 s = 1 (no bottom steam): recorded, not asserted (coder / spec item in DEVIATIONS "M9 validation")
    });

    test('F24 bottom s = 0.5: steam delivered = half the SP; raising the SP (recorded, spec item)', () {
      final s = _sim();
      final ft0 = _ti(s, 'FT-321');
      s.faults.inject(FaultSpec(
          type: FaultType.strippingSteamLoss,
          location: const FaultLocation.steam('bottom'),
          severity: 0.5,
          onset: s.time,
          ramp: 60));
      s.advance(300);
      final ft1 = _ti(s, 'FT-321');
      expect(ft1 / ft0, closeTo(0.5, 0.01));
      expect(s.control.loop('FC-321').op, closeTo(100, 0.5));
      s.setLever('steam.bottom', 4000 / 3600);
      s.advance(300);
      final ft2 = _ti(s, 'FT-321');
      // ignore: avoid_print
      print('F24 s 0.5: FT-321 ${(ft0 * 3600).toStringAsFixed(0)} -> ${(ft1 * 3600).toStringAsFixed(0)} kg/h; '
          'SP 4000 kg/h -> ${(ft2 * 3600).toStringAsFixed(0)} kg/h');
    });

    test('G16 timing: PA 3 MW from the default; when the specs are met, and the state at 2 h vs steady', () {
      final s = _sim();
      s.setLever('paDuty', 3e6);
      double? tMet;
      for (var t = 60; t <= 7200; t += 60) {
        s.advance(60);
        final k = _k(s);
        final met = _c(k.d86p95[1]) <= 235 && k.gapDieselKero >= 0 && _c(k.residueTbp5) >= 355;
        if (met && tMet == null) tMet = t.toDouble();
        if (!met) tMet = null;
      }
      final k2 = _k(s);
      final at2h = (_c(k2.d86p95[1]), k2.gapDieselKero, k2.qc);
      final r = s.runToSteadyState(maxSimSeconds: 172800);
      final kS = _k(s);
      // ignore: avoid_print
      print('G16 PA 3 MW: specs met (and kept) from ${tMet! / 60} min; at 2 h kero95 ${at2h.$1.toStringAsFixed(2)} '
          'D-K ${at2h.$2.toStringAsFixed(2)} QC ${(at2h.$3 / 1e6).toStringAsFixed(3)}; steady after a further '
          '${(r.simSeconds / 3600).toStringAsFixed(2)} h: ${_c(kS.d86p95[1]).toStringAsFixed(2)} / '
          '${kS.gapDieselKero.toStringAsFixed(2)} / ${(kS.qc / 1e6).toStringAsFixed(3)}');
      expect(tMet, lessThan(1800));
      expect(at2h.$1, closeTo(_c(kS.d86p95[1]), 0.5));
      expect(at2h.$2, closeTo(kS.gapDieselKero, 0.5));
      expect(_c(kS.d86p95[1]), closeTo(231.1, 3));
      expect(kS.gapDieselKero, closeTo(6.5, 3));
    });
  });
}
