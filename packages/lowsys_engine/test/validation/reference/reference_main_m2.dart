// Standalone driver for the M2 reference numbers (VC-12 hydraulics,
// VC-17 units) and the plausibility judgement of the design point.
//   dart run packages/lowsys_engine/test/validation/reference/reference_main_m2.dart
// No engine imports. Exit code 1 if a comparison fails.
library;

import 'dart:io';
import 'dart:math' as math;

import 'tray_hydraulics_reference.dart';
import 'units_reference.dart';
import 'validation_expectations_m2.dart';

var _fail = 0, _pass = 0;
void check(String label, double got, double expected, double tol,
    {bool rel = false}) {
  final t = rel ? tol * expected.abs() : tol;
  final ok = (got - expected).abs() <= t;
  ok ? _pass++ : _fail++;
  stdout.writeln(
      '${ok ? 'PASS' : 'FAIL'}  $label: got ${got.toStringAsPrecision(6)} expected '
      '${expected.toStringAsPrecision(6)} (tol ${rel ? '${100 * tol} %' : tol})');
}

void section(String s) => stdout.writeln('\n=== $s ===');

const kmolh = 1000 / 3600;

void main() {
  const gm = TrayGeom();
  section('VC-12.1 geometry');
  check('A_T', gm.aT, vc121.aT, 1e-4);
  check('A_a', gm.aA, vc121.aA, 1e-4);
  check('A_n', gm.aN, vc121.aN, 1e-4);
  check('L_w', gm.lW, vc121.lW, 1e-4);

  section('VC-12.2 correlation spot checks');
  for (final (ts, fLv, c) in vc122Csb) {
    check('C_SB(TS=$ts, F_LV=$fLv)', lygerosMagoulasCsb(ts, fLv), c, 1e-4);
  }
  check(
      'Bennett α_e(K_s 0.06)', bennettAlphaE(0.06), vc122Bennett.alphaE, 1e-4);
  check('Bennett C(h_w 0.05)', bennettC(0.05), vc122Bennett.c, 1e-4);
  for (final (f, p, psi) in vc122Psi) {
    check('ψ(F_LV=$f, φ=$p)', psiEq(f, p), psi, 1e-4, rel: true);
  }
  for (final (s, w) in vc122Weep) {
    check('w(Φ=$s)', weepFraction(s), w, 1e-3);
  }
  // Fair chart cross-check (literature): 24 in spacing, F_LV = 0.1 → ≈ 0.30 ft/s
  final csb24 = lygerosMagoulasCsb(609.6, 0.1);
  stdout.writeln(
      '  C_SB(24 in, F_LV 0.1) = ${(csb24 / 0.3048).toStringAsFixed(3)} ft/s (Fair chart ≈ 0.30)');
  check('Fair chart 24 in, F_LV 0.1 (±10 %)', csb24 / 0.3048, 0.30, 0.03);

  section('VC-12.3 design point reconstructed from the correlations');
  // Compositions at the prototype steady state: tray 1 x≈0.95/y≈0.97,
  // tray 15 x≈0.14/y≈0.25, tray 20 x≈0.02/y≈0.05; L: 100 (+ entrainment) above
  // the feed, 200 below; V = 150 kmol/h. D = 51.27 means ≈1.27 kmol/h of
  // tray-1 liquid is entrained into the drum.
  Fluid fl(double x, double y) =>
      Fluid(mwL: x * 78.11 + (1 - x) * 92.14, mwV: y * 78.11 + (1 - y) * 92.14);
  final t1 = sieveTray(150 * kmolh, 100 * kmolh, fl(0.95, 0.97));
  final t15 = sieveTray(150 * kmolh, 200 * kmolh, fl(0.14, 0.25));
  final t20 =
      sieveTray(150 * kmolh, 200 * kmolh, fl(0.02, 0.05), hNormBelow: 0);
  void report(String n, TrayPoint p, Vc123Tray e) {
    stdout.writeln(
        '  $n: φ=${p.phi.toStringAsFixed(3)} ψ=${p.psi.toStringAsFixed(4)} F_LV=${p.fLv.toStringAsFixed(4)} '
        'Φ=${p.stability.toStringAsFixed(3)} h_cl=${(1000 * p.hCl).toStringAsFixed(1)} mm α_e=${p.alphaE.toStringAsFixed(3)} '
        'ΔP_dry=${p.dpDry.toStringAsFixed(0)} ΔP=${p.dp.toStringAsFixed(0)} Pa holdup=${p.holdup.toStringAsFixed(0)} mol '
        'u_h=${p.uH.toStringAsFixed(1)} m/s froth=${(1000 * p.hCl / p.alphaE).toStringAsFixed(0)} mm dc=${(100 * p.dcFrac).toStringAsFixed(0)} %');
    check('$n φ', p.phi, e.phi, 0.02);
    check('$n ψ (±20 %)', p.psi, e.psi, 0.2, rel: true);
    if (!e.fLv.isNaN) check('$n F_LV', p.fLv, e.fLv, 0.004);
    if (!e.stability.isNaN) check('$n Φ', p.stability, e.stability, 0.03);
    check('$n h_cl (±1 mm)', 1000 * p.hCl, e.hClMm, 1.0);
    if (!e.alphaE.isNaN) check('$n α_e', p.alphaE, e.alphaE, 0.01);
    if (!e.dpDry.isNaN)
      check('$n ΔP_dry (±5 %)', p.dpDry, e.dpDry, 0.05, rel: true);
    check('$n ΔP (±5 %)', p.dp, e.dp, 0.05, rel: true);
  }

  report('tray 1', t1, vc123.trays[0]);
  report('tray 15', t15, vc123.trays[1]);
  report('tray 20', t20, vc123.trays[2]);
  final colDp = 9 * t1.dp + 11 * t15.dp;
  check('column ΔP (9 rectifying + 11 stripping trays, ±5 %)', colDp / 1000,
      vc123.columnDpKpa, 0.05,
      rel: true);
  check('tray 15 downcomer backup (m clear liquid, ±10 %)', t15.hDc,
      vc123.dcBackupTray15M, 0.1,
      rel: true);
  check('tray 15 downcomer % of limit (±10 pts)', 100 * t15.dcFrac,
      100 * vc123.dcBackupTray15Frac, 10);
  // D = V1 + e1 − L0: entrained liquid from tray 1 reaches the drum
  final e1 = t1.psi / (1 - t1.psi) * t1.lGross / kmolh;
  stdout.writeln(
      '  tray-1 entrainment to the drum ≈ ${e1.toStringAsFixed(2)} kmol/h → D ≈ ${(150 + e1 - 100).toStringAsFixed(2)} (doc 51.27)');
  check('D from tray-1 entrainment', 150 + e1 - 100, vc123.d, 0.4);
  // mass balance of the prototype's design point
  final mb = vc123.d * vc123.xD + (100 - vc123.d) * vc123.xB;
  check('design point balance D xD + B xB = 50', mb, 50, 0.01);
  stdout.writeln(
      '  xD upper bound from D = 51.27: ${(50 / 51.27).toStringAsFixed(4)} (doc xD 0.96725)');

  section('Load scans (sieve, L and V together)');
  final wp = weepPointLoadFraction(150 * kmolh, 100 * kmolh, fl(0.95, 0.97));
  final wpS = weepPointLoadFraction(150 * kmolh, 200 * kmolh, fl(0.14, 0.25));
  stdout.writeln(
      '  weep onset (Φ = 0.75): rectifying trays at ${(100 * wp).toStringAsFixed(0)} % load, stripping at ${(100 * wpS).toStringAsFixed(0)} % → turndown ≈ ${(1 / wp).toStringAsFixed(1)}:1');
  check('sieve turndown about 2:1 (weep at 40–65 % load)', wp, 0.525, 0.125);
  final jf = jetFloodLoadFraction(150 * kmolh, 200 * kmolh, fl(0.14, 0.25));
  stdout.writeln(
      '  jet flood (φ = 1) on stripping trays at ${(100 * jf).toStringAsFixed(0)} % load (doc: max φ 1.00 at +20 %)');
  check('jet flood reached near +20 % load', jf, 1.2, 0.06);
  for (final c in vc124Loads) {
    final a = sieveTray(
        150 * kmolh * c.loadFactor, 100 * kmolh * c.loadFactor, fl(0.95, 0.97));
    final b = sieveTray(
        150 * kmolh * c.loadFactor, 200 * kmolh * c.loadFactor, fl(0.14, 0.25));
    final dp = (9 * a.dp + 11 * b.dp) / 1000;
    stdout.writeln(
        '  ${c.name}: ΔP(no accumulation) ${dp.toStringAsFixed(2)} kPa (proto 10 min ${c.protoDp10}), '
        'max φ ${math.max(a.phi, b.phi).toStringAsFixed(2)}, max w ${math.max(a.weep, b.weep).toStringAsFixed(2)}, Φ rect ${a.stability.toStringAsFixed(2)} strip ${b.stability.toStringAsFixed(2)}');
    if (c.dpRatioMin > 0)
      check('${c.name} ΔP ≥ ${c.dpRatioMin}× base',
          dp / (colDp / 1000) >= c.dpRatioMin ? 1 : 0, 1, 0);
    if (c.weepMin != null) {
      final w = math.max(a.weep, b.weep);
      check('${c.name} weep fraction ≥ ${c.weepMin}', w >= c.weepMin! ? 1 : 0,
          1, 0);
      if (c.weepMax != null)
        check('${c.name} weep fraction ≤ ${c.weepMax}', w <= c.weepMax! ? 1 : 0,
            1, 0);
    }
  }

  section('Fault parameter effects (static)');
  {
    final f3 = sieveTray(150 * kmolh, 200 * kmolh, fl(0.14, 0.25), sFoul: 0.3);
    final f6 = sieveTray(150 * kmolh, 200 * kmolh, fl(0.14, 0.25), sFoul: 0.6);
    final extra3 = 5 * (f3.dp - t15.dp) / 1000;
    stdout.writeln(
        '  F05 holes s=0.3 on 5 trays: +${extra3.toStringAsFixed(2)} kPa → ${(colDp / 1000 + extra3).toStringAsFixed(2)} kPa (proto 16.84); '
        'fouled tray φ ${f3.phi.toStringAsFixed(2)} dc ${(100 * f3.dcFrac).toStringAsFixed(0)} %');
    check('F05 s=0.3 column ΔP +10…+20 %', extra3 / (colDp / 1000), 0.15, 0.05);
    stdout.writeln(
        '  F05 holes s=0.6: fouled-tray ΔP ${f6.dp.toStringAsFixed(0)} Pa, downcomer ${(100 * f6.dcFrac).toStringAsFixed(0)} % of limit → '
        '${f6.dcFrac >= 1 ? 'downcomer flood (liquid backs up, matches proto ΔP 45 kPa)' : 'no downcomer flood'}');
    check('F05 s=0.6 drives the downcomer limit', f6.dcFrac >= 1 ? 1 : 0, 1, 0);
    // F06 foaming s = 0.33: SF 0.85, φ_dc 0.433 ; s = 0.67: SF 0.70, φ_dc 0.367
    final foamA = sieveTray(150 * kmolh, 200 * kmolh, fl(0.14, 0.25),
        sf: 1 - 0.45 * 0.33, phiDcOverride: 0.5 - 0.2 * 0.33);
    final foamB = sieveTray(150 * kmolh, 200 * kmolh, fl(0.14, 0.25),
        sf: 1 - 0.45 * 0.67, phiDcOverride: 0.5 - 0.2 * 0.67);
    stdout.writeln(
        '  F06 s=0.33: max φ ${foamA.phi.toStringAsFixed(2)} (proto 0.98) dc ${(100 * foamA.dcFrac).toStringAsFixed(0)} %; '
        's=0.67: φ ${foamB.phi.toStringAsFixed(2)} (proto 1.48) dc ${(100 * foamB.dcFrac).toStringAsFixed(0)} %');
    check('F06 s=0.33 max φ ≥ 0.95', foamA.phi >= 0.95 ? 1 : 0, 1, 0);
    check('F06 s=0.67 floods (φ > 1)', foamB.phi > 1 ? 1 : 0, 1, 0);
    // F04 broken tray s = 1: hole area = active area, deck area 2 %
    final qV = 150 * kmolh * fl(0.95, 0.97).mwV / 1000 / 2.9;
    final uHb = qV / gm.aA;
    final dpDryB = 2.9 / 2 * math.pow(uHb / gm.c0, 2);
    stdout.writeln(
        '  F04 s=1: ΔP_dry ${dpDryB.toStringAsFixed(1)} Pa (+ residual ${(4 * 0.02 / 0.0127).toStringAsFixed(1)} Pa, little liquid) → tray ΔP ≈ 10–40 Pa (proto 38, ≤ 15 % of 664)');
    check('F04 broken tray ΔP ≤ 15 % of base',
        (dpDryB + 6.3 + 25) / 664 <= 0.15 ? 1 : 0, 1, 0);
  }

  section('VC-12.5 valve trays');
  {
    final qV1 = 150 * kmolh * fl(0.95, 0.97).mwV / 1000 / 2.9;
    final qV15 = 150 * kmolh * fl(0.14, 0.25).mwV / 1000 / 2.9;
    final (d1, r1) = valveDryDrop(qV1, gm, 2.9);
    final (d15, r15) = valveDryDrop(qV15, gm, 2.9);
    stdout.writeln(
        '  design: tray 1 ΔP_dry ${d1.toStringAsFixed(0)} Pa regime $r1, tray 15 ${d15.toStringAsFixed(0)} Pa regime $r15 (doc ≈ 357, fully open; sieve 472–641)');
    check('valves fully open at design', r1 == 2 && r15 == 2 ? 1 : 0, 1, 0);
    check('valve ΔP_dry at design ≈ 357 ± 60 Pa', 0.5 * (d1 + d15), 357, 60);
    final (d35, r35) = valveDryDrop(0.35 * qV15, gm, 2.9);
    check('35 % load: balancing at ΔP_lift', r35 == 1 ? d35 : -1, 190, 1e-9);
    // load at which valves close: Q = C_v A_min √(2 ΔP_lift/ρ_V)
    final qClose =
        gm.cv * gm.rMin * gm.fv * gm.aA * math.sqrt(2 * gm.dpLift / 2.9);
    stdout.writeln(
        '  valves close below ${(100 * qClose / qV15).toStringAsFixed(0)} % of design load (doc: weeping starts below ≈ 18 %)');
    check('valve close point 15–25 % load', qClose / qV15, 0.20, 0.05);
  }

  section('VC-17 units');
  check('373.15 K → °C', kToC(vc17.tK), vc17.tC, 1e-9);
  check('373.15 K → °F', kToF(vc17.tK), vc17.tF, 1e-9);
  check('101325 Pa → bar', paToBar(vc17.pPa), vc17.pBar, 1e-4);
  check('101325 Pa → psia', paToPsia(vc17.pPa), vc17.pPsia, 1e-4);
  check('1 mol/s → kmol/h', molsToKmolh(1), vc17.kmolh, 1e-5);
  check('1 mol/s → lb-mol/h', molsToLbmolh(1), vc17.lbmolh, 1e-5);
  check('1e6 W → kW', wToKw(1e6), vc17.kw, 1e-5);
  check('1e6 W → MMBtu/h', wToMmbtuh(1e6), vc17.mmbtuh, 1e-5);
  check('132.5 m³/h → bbl/d', m3hToBblD(132.5), vc17.bblD, 0.1);
  check('20000 bbl/d → m³/h', bblDToM3h(20000), vc17.bbl20000InM3h, 1e-3);
  check('0.0254 m → mm', mToMm(0.0254), vc17.mm, 1e-9);
  check('0.0254 m → in', mToIn(0.0254), vc17.inch, 1e-9);
  check('800 kg/m³ → lb/ft³', kgm3ToLbft3(800), vc17.lbft3, 1e-3);
  check('10 K → 18 °F', deltaKToDeltaF(10), vc17.dF, 1e-9);
  stdout.writeln(
      '  psi = ${psiToPa.toStringAsFixed(6)} Pa (spec 6894.757293); bbl = ${barrelToM3.toStringAsFixed(9)} m³ (spec 0.158987295)');

  stdout.writeln('\n$_pass passed, $_fail failed');
  if (_fail > 0) exitCode = 1;
}
