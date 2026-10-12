// VC-12.1–12.3, 12.5: tray geometry, correlation spot values, the
// full-hydraulics design-point steady state and valve trays.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m2.dart';
import 'reference/tray_hydraulics_reference.dart' as ref;
import 'reference/validation_expectations_m2.dart';

void main() {
  group('VC-12.1 geometry', () {
    test('A_T, A_a, A_n, L_w from the B-T tray geometry', () {
      final gm = btFull().traySection.geometry;
      final d = TrayGeometryDerived.from(gm);
      expect(d.aT, closeTo(vc121.aT, 1e-4));
      expect(d.aA, closeTo(vc121.aA, 1e-4));
      expect(d.aN, closeTo(vc121.aN, 1e-4));
      expect(d.lW, closeTo(vc121.lW, 1e-4));
    });
  });

  group('VC-12.2 correlation spot checks', () {
    test('Lygeros–Magoulas C_SB', () {
      for (final (ts, fLv, c) in vc122Csb) {
        expect(TrayCorrelations.csbLygerosMagoulas(ts / 1000, fLv),
            closeTo(c, 1e-4),
            reason: 'TS=$ts F_LV=$fLv');
      }
    });
    test('Bennett α_e and C', () {
      expect(TrayCorrelations.bennettAlphaE(0.06),
          closeTo(vc122Bennett.alphaE, 1e-4));
      expect(TrayCorrelations.bennettC(0.05), closeTo(vc122Bennett.c, 1e-4));
    });
    test('entrainment fit ψ', () {
      for (final (f, p, psi) in vc122Psi) {
        expect(TrayCorrelations.psiEq(f, p), closeTo(psi, 1e-4 * psi),
            reason: 'F_LV=$f φ=$p');
      }
    });
    test('weep map', () {
      for (final (s, w) in vc122Weep) {
        expect(TrayCorrelations.weepFraction(s), closeTo(w, 1e-3),
            reason: 'Φ=$s');
      }
    });
    test('engine correlations agree with the independent reference on a grid',
        () {
      for (var ts = 300.0; ts <= 900; ts += 150) {
        for (var f = 0.01; f <= 1.0; f *= 2.5) {
          expect(TrayCorrelations.csbLygerosMagoulas(ts / 1000, f),
              closeTo(ref.lygerosMagoulasCsb(ts, f), 1e-9));
        }
      }
      for (var ks = 0.01; ks < 0.15; ks += 0.01) {
        expect(TrayCorrelations.bennettAlphaE(ks),
            closeTo(ref.bennettAlphaE(ks), 1e-12));
      }
    });
  });

  group('VC-12.3 design-point steady state (full hydraulics)', () {
    late Simulator sim;
    late Hyd h;
    late Profile p;
    setUpAll(() {
      sim = newSim(btFull());
      p = runSteady(sim);
      h = hyd(sim);
    });

    test('xD, xB, D', () {
      expect(p.xD, closeTo(vc123.xD, 0.002));
      expect(p.xB, closeTo(vc123.xB, 0.001));
      expect(p.dKmolh, closeTo(vc123.d, 0.3),
          reason: 'entrained tray-1 liquid reaches the drum');
      expect(p.dKmolh * p.xD + p.bKmolh * p.xB, closeTo(50, 0.02),
          reason: 'light balance');
    });

    test('column ΔP 14.68 kPa ± 5 %', () {
      expect(h.columnDp / 1000,
          closeTo(vc123.columnDpKpa, 0.05 * vc123.columnDpKpa));
      expect(h.sumDp(1, 20), closeTo(h.columnDp, 1e-6 * h.columnDp),
          reason: 'KPI = Σ tray ΔP');
    });

    for (final t in vc123.trays) {
      test('tray ${t.tray} indicators', () {
        expect(h.jetFlood(t.tray), closeTo(t.phi, 0.02), reason: 'φ');
        expect(
            h.entrain(t.tray) /
                (h.s.stages.liquidDown[t.tray] + h.entrain(t.tray)),
            closeTo(t.psi, 0.2 * t.psi),
            reason: 'ψ = e/(L+e)');
        expect(1000 * h.hcl(t.tray), closeTo(t.hClMm, 1.0), reason: 'h_cl mm');
        expect(h.dp(t.tray), closeTo(t.dp, 0.05 * t.dp), reason: 'ΔP');
        if (!t.stability.isNaN)
          expect(h.stability(t.tray), closeTo(t.stability, 0.03), reason: 'Φ');
        if (!t.alphaE.isNaN)
          expect(h.hcl(t.tray) / h.froth(t.tray), closeTo(t.alphaE, 0.01),
              reason: 'α_e = h_cl/h_f');
      });
    }

    test('tray 15 downcomer backup 40 % of the limit ± 10 %', () {
      expect(h.dcFlood(15),
          closeTo(vc123.dcBackupTray15Frac, 0.1 * vc123.dcBackupTray15Frac));
    });

    test('no weeping anywhere (Φ > 1.6)', () {
      for (var j = 1; j <= 20; j++) {
        expect(h.weepFrac(j), 0, reason: 'tray $j');
        expect(h.stability(j), greaterThan(1.6), reason: 'tray $j');
      }
    });

    test('max flood % KPI = 100 × max(φ, dc, fill)', () {
      final m = h.maxOverTrays((j) => [
            h.jetFlood(j),
            h.dcFlood(j),
            h.frothFill(j)
          ].reduce((a, b) => a > b ? a : b));
      expect(h.maxFloodPct, closeTo(100 * m, 1e-6));
      expect(h.maxFloodPct, inInclusiveRange(65, 85));
    });

    test('holdups and froth heights are in the Bennett range', () {
      for (var j = 1; j <= 20; j++) {
        expect(h.holdup(j), inInclusiveRange(140, 230),
            reason: 'tray $j holdup');
        expect(h.froth(j), inInclusiveRange(0.05, 0.12),
            reason: 'tray $j froth height (m)');
      }
    });

    test('pressure profile increases monotonically down the column', () {
      final st = h.s.stages;
      for (var j = 2; j <= 21; j++) {
        expect(st.p[j], greaterThan(st.p[j - 1]), reason: 'P[$j]');
      }
      expect(st.p[1], closeTo(101325, 1e-6));
      expect(st.p[21] - st.p[1], closeTo(h.columnDp, 1e-6 * h.columnDp));
    });

    test(
        'entrainment, weeping and downcomer limit off → exactly the ideal result (VC-4.1)',
        () {
      final s2 = newSim(btFull(),
          options: const SimOptions(
              entrainment: false, weeping: false, downcomerLimit: false));
      final p2 = runSteady(s2);
      expect(p2.xD, closeTo(0.981183, 1e-5));
      expect(p2.xB, closeTo(0.018817, 1e-5));
      expect(hyd(s2).columnDp, greaterThan(10000), reason: 'ΔP still computed');
    });
  });

  group('VC-12.5 valve trays', () {
    test(
        'design load: valves fully open, ΔP_dry ≈ 357 Pa; 35 % load: balancing, no weeping',
        () {
      final sim = newSim(btFull(overrides: {'sections[0].type': 'valve'}));
      runSteady(sim);
      final h = hyd(sim);
      final dpDryMean = (h.s.stages.dpDry[1] + h.s.stages.dpDry[15]) / 2;
      expect(dpDryMean, closeTo(357, 60));
      for (var j = 1; j <= 20; j++) {
        expect(h.s.stages.dpDry[j], greaterThan(190),
            reason: 'tray $j valves open');
      }
      scaleLoad(sim, 0.35);
      sim.advance(1800);
      final h2 = hyd(sim);
      for (var j = 1; j <= 20; j++) {
        expect(h2.s.stages.dpDry[j], closeTo(190, 1.0),
            reason: 'tray $j balancing');
        expect(h2.weepFrac(j), 0,
            reason: 'tray $j no weeping on valve trays at 35 %');
      }
    });

    test('sieve trays weep at 35 % (w ≈ 0.5) where valve trays do not', () {
      final sieve = newSim(btFull());
      runSteady(sieve);
      scaleLoad(sieve, 0.35);
      sieve.advance(1800);
      final hs = hyd(sieve);
      expect(hs.maxOverTrays(hs.weepFrac), inInclusiveRange(0.3, 0.7));
    });

    test('valve trays start weeping below about 18 % load', () {
      final sim = newSim(btFull(overrides: {'sections[0].type': 'valve'}));
      runSteady(sim);
      scaleLoad(sim, 0.25);
      sim.advance(1800);
      expect(hyd(sim).maxOverTrays(hyd(sim).weepFrac), 0);
      scaleLoad(sim, 0.12);
      sim.advance(1800);
      expect(hyd(sim).maxOverTrays(hyd(sim).weepFrac), greaterThan(0));
    });
  });
}
