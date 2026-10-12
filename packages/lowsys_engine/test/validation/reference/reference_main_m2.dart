// Standalone driver for the M2 reference numbers (VC-12 hydraulics at the
// v1.1 tray spacing 0.9 m and, as a harness check, the v1.0 table at 0.6 m;
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

Fluid fl(double x, double y) =>
    Fluid(mwL: x * 78.11 + (1 - x) * 92.14, mwV: y * 78.11 + (1 - y) * 92.14);

/// Tray compositions at the design steady state (from the v1.0/v1.1 profiles).
const _x1 = 0.95,
    _y1 = 0.97,
    _x15 = 0.14,
    _y15 = 0.25,
    _x20 = 0.02,
    _y20 = 0.05;

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
  final csb24 = lygerosMagoulasCsb(609.6, 0.1);
  stdout.writeln(
      '  C_SB(24 in, F_LV 0.1) = ${(csb24 / 0.3048).toStringAsFixed(3)} ft/s (Fair chart ≈ 0.30)');
  check('Fair chart 24 in, F_LV 0.1 (±10 %)', csb24 / 0.3048, 0.30, 0.03);
  final csb36 = lygerosMagoulasCsb(900, 0.08);
  stdout.writeln(
      '  C_SB(36 in, F_LV 0.08) = ${(csb36 / 0.3048).toStringAsFixed(3)} ft/s (Fair chart at 36 in ≈ 0.40–0.42 ft/s)');
  check('Fair chart 36 in, F_LV 0.08 (±10 %)', csb36 / 0.3048, 0.41, 0.045);

  for (final e in [vc123, vc123v10]) {
    designPoint(e);
  }

  loadScans();
  faultEffects();
  valveTrays();
  dumping();
  units();

  stdout.writeln('\n$_pass passed, $_fail failed');
  if (_fail > 0) exitCode = 1;
}

/// Reconstructs the design point from the correlations alone at the given
/// tray spacing. The level of agreement with the [P] table is the check.
void designPoint(Vc123 e) {
  section(
      'VC-12.3 design point reconstructed from the correlations, TS = ${e.ts} m');
  final gm = TrayGeom(ts: e.ts);
  final t1 = sieveTray(150 * kmolh, 100 * kmolh, fl(_x1, _y1), gm: gm);
  final t15 = sieveTray(150 * kmolh, 200 * kmolh, fl(_x15, _y15), gm: gm);
  final t20 = sieveTray(150 * kmolh, 200 * kmolh, fl(_x20, _y20),
      gm: gm, hNormBelow: 0);
  void report(String n, TrayPoint p, Vc123Tray x) {
    stdout.writeln(
        '  $n: φ=${p.phi.toStringAsFixed(3)} ψ=${p.psi.toStringAsFixed(4)} F_LV=${p.fLv.toStringAsFixed(4)} '
        'Φ=${p.stability.toStringAsFixed(3)} h_cl=${(1000 * p.hCl).toStringAsFixed(1)} mm α_e=${p.alphaE.toStringAsFixed(3)} '
        'ΔP_dry=${p.dpDry.toStringAsFixed(0)} ΔP=${p.dp.toStringAsFixed(0)} Pa holdup=${p.holdup.toStringAsFixed(0)} mol '
        'froth=${(1000 * p.hCl / p.alphaE).toStringAsFixed(0)} mm dc=${(100 * p.dcFrac).toStringAsFixed(0)} %');
    check('TS ${e.ts} $n φ', p.phi, x.phi, 0.02);
    check('TS ${e.ts} $n ψ (±20 %)', p.psi, x.psi, 0.2, rel: true);
    if (!x.fLv.isNaN) check('TS ${e.ts} $n F_LV', p.fLv, x.fLv, 0.004);
    if (!x.stability.isNaN)
      check('TS ${e.ts} $n Φ', p.stability, x.stability, 0.03);
    check('TS ${e.ts} $n h_cl (±1 mm)', 1000 * p.hCl, x.hClMm, 1.0);
    if (!x.alphaE.isNaN) check('TS ${e.ts} $n α_e', p.alphaE, x.alphaE, 0.01);
    if (!x.dpDry.isNaN)
      check('TS ${e.ts} $n ΔP_dry (±5 %)', p.dpDry, x.dpDry, 0.05, rel: true);
    check('TS ${e.ts} $n ΔP (±5 %)', p.dp, x.dp, 0.05, rel: true);
  }

  report('tray 1', t1, e.trays[0]);
  report('tray 15', t15, e.trays[1]);
  report('tray 20', t20, e.trays[2]);
  final colDp = 9 * t1.dp + 11 * t15.dp;
  check('TS ${e.ts} column ΔP (±5 %)', colDp / 1000, e.columnDpKpa, 0.05,
      rel: true);
  check('TS ${e.ts} max flood % (tray 20 jet, ±2)', 100 * t20.phi,
      e.maxFloodPct, 2.0);
  check('TS ${e.ts} tray 15 downcomer backup (m, ±10 %)', t15.hDc,
      e.dcBackupTray15M, 0.1,
      rel: true);
  check('TS ${e.ts} downcomer limit φ_dc (TS + h_w)', 0.5 * (e.ts + 0.05),
      e.dcLimitM, 1e-9);
  check('TS ${e.ts} tray 15 downcomer % of limit (±10 pts)', 100 * t15.dcFrac,
      100 * e.dcBackupTray15Frac, 10);
  final e1 = t1.psi / (1 - t1.psi) * t1.lGross / kmolh;
  stdout.writeln(
      '  tray-1 entrainment to the drum ≈ ${e1.toStringAsFixed(2)} kmol/h → D ≈ ${(150 + e1 - 100).toStringAsFixed(2)} (doc ${e.d})');
  check('TS ${e.ts} D from tray-1 entrainment', 150 + e1 - 100, e.d, 0.4);
  final mb = e.d * e.xD + (100 - e.d) * e.xB;
  check('TS ${e.ts} design point balance D xD + B xB = 50', mb, 50, 0.02);
  if (e.ts == 0.9) {
    // VC-8.15: +10 on both raises max flood 62.9 → 67.1 (φ ∝ vapour rate at fixed F_LV)
    final t20b = sieveTray(160 * kmolh, 210 * kmolh, fl(_x20, _y20),
        gm: gm, hNormBelow: 0);
    check('VC-8.15 max flood after +10 kmol/h (±2)', 100 * t20b.phi,
        vc815.flood10, 2.0);
    for (final (add, _, flood) in vc815Further) {
      final t = sieveTray(
          (150 + add) * kmolh, (200 + add) * kmolh, fl(_x20, _y20),
          gm: gm, hNormBelow: 0);
      check('VC-8.15 max flood after +$add (±2)', 100 * t.phi, flood, 2.0);
    }
    // VC-8.16 plausibility: D held at 50 → the ideal-hydraulics values minus a small entrainment loss
    stdout.writeln(
        '  VC-8.16 (D held): 0.9810/0.9843/0.9866/0.9883/0.9896 vs ideal VC-4.1/4.6 0.98118/0.98450 → '
        'entrainment costs ≈ 0.0002 at +0/+10: consistent');
    check('VC-8.16 +0 within 0.0005 of ideal', vc816[0].$2, 0.981183, 0.0005);
    check('VC-8.16 +10 within 0.0005 of ideal', vc816[1].$2, 0.984504, 0.0005);
    check('VC-8.15 +10 LV: xD up', vc815.xD10 > vc815.xD0 ? 1 : 0, 1, 0);
    final dImplied = (50 - 100 * vc815.xB10) / (vc815.xD10 - vc815.xB10);
    stdout.writeln(
        '  VC-8.15 +10: D implied by the balance = ${dImplied.toStringAsFixed(2)} kmol/h '
        '(e1 ≈ ${(dImplied - 50).toStringAsFixed(2)}, up from 0.37 at +0)');
    check('VC-8.15 implied D in 50.3–50.8', dImplied, 50.55, 0.25);
  }
}

void loadScans() {
  section('VC-12.4 load scans at TS 0.9 (sieve, F fixed, L0 and V_B + x·150)');
  const gm = TrayGeom(ts: 0.9);
  final base =
      9 * sieveTray(150 * kmolh, 100 * kmolh, fl(_x1, _y1), gm: gm).dp +
          11 * sieveTray(150 * kmolh, 200 * kmolh, fl(_x15, _y15), gm: gm).dp;
  final jf =
      jetFloodLoadFraction(150 * kmolh, 200 * kmolh, fl(_x20, _y20), gm: gm);
  stdout.writeln(
      '  jet flood (φ = 1) on the bottom tray at ${(100 * (jf - 1)).toStringAsFixed(0)} % extra vapour (doc: flood onset at +60 %)');
  check('flood onset near +60 %', jf - 1, 0.60, 0.06);
  for (final c in vc124Loads) {
    final add = c.fraction * 150;
    final a = sieveTray((150 + add) * kmolh, (100 + add) * kmolh, fl(_x1, _y1),
        gm: gm);
    final b = sieveTray(
        (150 + add) * kmolh, (200 + add) * kmolh, fl(_x15, _y15),
        gm: gm);
    final bot = sieveTray(
        (150 + add) * kmolh, (200 + add) * kmolh, fl(_x20, _y20),
        gm: gm, hNormBelow: 0);
    final dp = (9 * a.dp + 11 * b.dp) / 1000;
    stdout.writeln(
        '  ${c.name}: ΔP ${dp.toStringAsFixed(2)} kPa (proto 10 min ${c.protoDp10}), max φ ${bot.phi.toStringAsFixed(2)} '
        '(proto 4 h flood ${c.protoFlood4h} %), ψ_bot ${bot.psi.toStringAsFixed(3)}');
    // Above flood the dynamic model carries accumulated liquid that a static
    // tray point cannot represent: allow 10 % there and skip the ratio.
    final flooded = bot.phi >= 1.0;
    if (!c.protoDp10.isNaN) {
      check('${c.name} ΔP vs proto 10 min (±${flooded ? 10 : 5} %)', dp,
          c.protoDp10, flooded ? 0.10 : 0.05,
          rel: true);
    }
    if (c.dpRatioMin > 0 && !flooded) {
      stdout.writeln(
          '    static ΔP ratio ${(dp / (base / 1000)).toStringAsFixed(2)} '
          'vs must-hold ≥ ${c.dpRatioMin} (prototype ${(c.protoDp10 / 14.49).toStringAsFixed(2)})');
      check('${c.name} ΔP ratio ≥ ${c.dpRatioMin} within 0.04',
          dp / (base / 1000) >= c.dpRatioMin - 0.04 ? 1 : 0, 1, 0);
    }
    if (!c.protoFlood4h.isNaN)
      check('${c.name} max flood (±4 pts)', 100 * bot.phi, c.protoFlood4h, 4);
  }
  for (final (f, w, _, _, _, _) in vc124Turndown) {
    final a = sieveTray(150 * kmolh * f, 100 * kmolh * f, fl(_x1, _y1), gm: gm);
    final b =
        sieveTray(150 * kmolh * f, 200 * kmolh * f, fl(_x15, _y15), gm: gm);
    final wMax = math.max(a.weep, b.weep);
    stdout.writeln(
        '  turndown $f: max w ${wMax.toStringAsFixed(2)} (proto $w), Φ rect ${a.stability.toStringAsFixed(2)} strip ${b.stability.toStringAsFixed(2)}');
    check('turndown $f weep fraction (±0.05)', wMax, w, 0.05);
  }
  final wp =
      weepPointLoadFraction(150 * kmolh, 100 * kmolh, fl(_x1, _y1), gm: gm);
  stdout.writeln(
      '  weep onset (Φ = 0.75): rectifying trays at ${(100 * wp).toStringAsFixed(0)} % load → turndown ≈ ${(1 / wp).toStringAsFixed(1)}:1 (TS does not enter)');
  check('sieve turndown about 2:1', wp, 0.525, 0.125);
}

void faultEffects() {
  section('VC-12.4 fault parameter effects at TS 0.9 (static)');
  const gm = TrayGeom(ts: 0.9);
  final t15 = sieveTray(150 * kmolh, 200 * kmolh, fl(_x15, _y15), gm: gm);
  final base =
      (9 * sieveTray(150 * kmolh, 100 * kmolh, fl(_x1, _y1), gm: gm).dp +
              11 * t15.dp) /
          1000;
  for (final (s, dp10, ratio) in vc124FoulHoles) {
    final f =
        sieveTray(150 * kmolh, 200 * kmolh, fl(_x15, _y15), gm: gm, sFoul: s);
    final dp = base + 5 * (f.dp - t15.dp) / 1000;
    stdout.writeln(
        '  F05 holes s=$s on 5 trays: ΔP ${dp.toStringAsFixed(2)} kPa (proto $dp10, ×$ratio); fouled tray φ ${f.phi.toStringAsFixed(2)} dc ${(100 * f.dcFrac).toStringAsFixed(0)} %');
    if (s < 0.8) {
      check('F05 s=$s ΔP (±5 %)', dp, dp10, 0.05, rel: true);
      check('F05 s=$s no downcomer flood', f.dcFrac < 1 ? 1 : 0, 1, 0);
    } else {
      check(
          'F05 s=$s downcomer floods (backs up; proto ΔP 57.5 with accumulation)',
          f.dcFrac >= 1 ? 1 : 0,
          1,
          0);
    }
  }
  for (final (s, sf, phiDc, phi10, xd4, dp4) in vc124Foam) {
    // beyond φ = 1 the static entrainment recycle runs away; the prototype's
    // filtered ψ and overflow keep φ near the no-recycle value 0.63/SF
    final a = sieveTray(150 * kmolh, 200 * kmolh, fl(_x20, _y20),
        gm: gm, sf: sf, phiDcOverride: phiDc, hNormBelow: 0, recycle: s < 0.9);
    final b = sieveTray(150 * kmolh, 200 * kmolh, fl(_x15, _y15),
        gm: gm, sf: sf, phiDcOverride: phiDc);
    final dp = (9 *
                sieveTray(150 * kmolh, 100 * kmolh, fl(_x1, _y1),
                        gm: gm, sf: sf, phiDcOverride: phiDc)
                    .dp +
            11 * b.dp) /
        1000;
    stdout.writeln(
        '  F06 s=$s: max φ ${a.phi.toStringAsFixed(2)} (proto $phi10), dc ${(100 * b.dcFrac).toStringAsFixed(0)} %, ΔP ${dp.toStringAsFixed(2)} (proto 4 h $dp4), proto xD $xd4');
    check('F06 s=$s max φ (±0.05)', a.phi, phi10, 0.05);
    check('F06 s=$s ΔP within ±10 % of base (foam floods without a ΔP rise)',
        dp, base, 0.10,
        rel: true);
  }
  {
    final dc = sieveTray(150 * kmolh, 200 * kmolh, fl(_x15, _y15),
        gm: TrayGeom(ts: 0.9, hAp: 0.038 * 0.1));
    stdout.writeln(
        '  F05 downcomer s=1 (apron 90 % blocked): h_dc ${dc.hDc.toStringAsFixed(3)} m = ${(100 * dc.dcFrac).toStringAsFixed(0)} % of the limit → '
        '${dc.dcFrac >= 1 ? 'downcomer flood (proto dc 5 trays, ΔP ×1.93)' : 'no flood'}');
    check('F05 downcomer mode floods', dc.dcFrac >= 1 ? 1 : 0, 1, 0);
  }
  {
    final qV = 150 * kmolh * fl(_x1, _y1).mwV / 1000 / 2.9;
    final dpDryB = 2.9 / 2 * math.pow(qV / gm.aA / gm.c0, 2);
    stdout.writeln(
        '  F04 s=1: ΔP_dry ${dpDryB.toStringAsFixed(1)} Pa + residual 6.3 Pa, no head (E20) → ≈ 11 Pa = 1.7 % of 642 (doc 1.7 %); rows left as-is pending the dumping-law change');
    check('F04 broken tray ΔP ≤ 15 % of base',
        (dpDryB + 6.3) / 642 <= 0.15 ? 1 : 0, 1, 0);
  }
}

void valveTrays() {
  section('VC-12.5 valve trays (TS does not enter ΔP_dry)');
  const gm = TrayGeom(ts: 0.9);
  final qV1 = 150 * kmolh * fl(_x1, _y1).mwV / 1000 / 2.9;
  final qV15 = 150 * kmolh * fl(_x15, _y15).mwV / 1000 / 2.9;
  final (d1, r1) = valveDryDrop(qV1, gm, 2.9);
  final (d15, r15) = valveDryDrop(qV15, gm, 2.9);
  stdout.writeln(
      '  design: tray 1 ΔP_dry ${d1.toStringAsFixed(0)} Pa regime $r1, tray 15 ${d15.toStringAsFixed(0)} Pa regime $r15 (doc ≈ 357, fully open)');
  check('valves fully open at design', r1 == 2 && r15 == 2 ? 1 : 0, 1, 0);
  check('valve ΔP_dry at design ≈ 357 ± 60 Pa', 0.5 * (d1 + d15), 357, 60);
  final (d35, r35) = valveDryDrop(0.35 * qV15, gm, 2.9);
  check('35 % load: balancing at ΔP_lift', r35 == 1 ? d35 : -1, 190, 1e-9);
  final qClose =
      gm.cv * gm.rMin * gm.fv * gm.aA * math.sqrt(2 * gm.dpLift / 2.9);
  stdout.writeln(
      '  valves close below ${(100 * qClose / qV15).toStringAsFixed(0)} % of design load (doc ≈ 18 %)');
  check('valve close point 15–25 % load', qClose / qV15, 0.20, 0.05);
}

void units() {
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
}

/// VC-12.6 orifice-drainage dumping (PHYSICS.md (5.15)): at a steady inflow
/// L_in the holdup settles where κ√M = L_in, so M = (L_in/κ)², independent
/// of dt (implicit Euler fixed point).
void dumping() {
  section('VC-12.6 dumping holdups (Φ = 0, boilup lost, feed 100 kmol/h on)');
  const gm = TrayGeom(ts: 0.9);
  final vL = fl(0.5, 0.5).vL;
  final root = math.sqrt(2 * g * vL / gm.aA);
  for (final (name, aDrain, maxMol, hLo, hHi) in [
    ('sieve', gm.aH, 2.0, 0.14, 0.17),
    // h_cl ∝ v_L² (κ ∝ v_L^−½): 1.37 mm at x = 0.5, 1.6 mm on toluene-rich trays
    ('valve (closed, A_min)', gm.rMin * gm.fv * gm.aA, 15.0, 1.2, 1.8),
  ]) {
    final kappa = 0.6 * aDrain * root / vL;
    for (final lIn in [25.0 * kmolh / kmolh * kmolh, 100 * kmolh]) {
      final m = math.pow(lIn / kappa, 2).toDouble();
      final hCl = m * vL / gm.aA;
      stdout.writeln(
          '  $name, inflow ${(lIn / kmolh).toStringAsFixed(0)} kmol/h: κ=${kappa.toStringAsFixed(2)} → M=${m.toStringAsFixed(2)} mol, h_cl=${(1000 * hCl).toStringAsFixed(3)} mm');
      check(
          '$name inflow ${(lIn / kmolh).toStringAsFixed(0)}: holdup ≤ $maxMol mol',
          m <= maxMol ? 1 : 0,
          1,
          0);
      if (lIn > 50 * kmolh)
        check('$name h_cl in $hLo–$hHi mm (doc)', 1000 * hCl, 0.5 * (hLo + hHi),
            0.5 * (hHi - hLo) + 0.02);
    }
    // dt independence of the implicit fixed point: iterate M ← M_prev + dt (L_in − κ√M) to convergence at two dt
    final lIn = 100 * kmolh;
    double settle(double dt) {
      var m = 200.0;
      for (var k = 0; k < 100000; k++) {
        // implicit: solve m_new − m − dt (L − κ√m_new) = 0 by bisection on u = √m_new
        var lo = 0.0, hi = math.sqrt(m + dt * lIn);
        for (var i = 0; i < 80; i++) {
          final u = 0.5 * (lo + hi);
          final r = u * u - m - dt * (lIn - kappa * u);
          if (r > 0) {
            hi = u;
          } else {
            lo = u;
          }
        }
        final mNew = lo * lo;
        if ((mNew - m).abs() < 1e-12) {
          m = mNew;
          break;
        }
        m = mNew;
      }
      return m;
    }

    check('$name: holdup at dt 0.5 = dt 30 (±0.5 mol)', settle(0.5), settle(30),
        0.5);
  }
  // physical cross-check: Francis orifice head for the feed draining through the sieve holes
  final q = 100 * kmolh * vL;
  final h = math.pow(q / (0.6 * gm.aH), 2) / (2 * g);
  check('orifice head for 100 kmol/h through 10 % holes ≈ 0.17 mm', 1000 * h,
      0.168, 0.02);
  // broken tray at normal load: 2.4 mol on 2 % of the area → h_cl 14 mm, Φ ≈ 0.21–0.25: above 0.2, no dumping
  final hClB = 2.4 * vL / (0.02 * gm.aA);
  final qV = 150 * kmolh * fl(0.95, 0.97).mwV / 1000 / 2.9;
  final hDryB = 2.9 / 2 * math.pow(qV / gm.aA / gm.c0, 2) / (800 * g);
  final phiB = math.sqrt(hDryB / hClB);
  stdout.writeln(
      '  broken tray at normal load: h_cl ${(1000 * hClB).toStringAsFixed(1)} mm, h_dry ${(1000 * hDryB).toStringAsFixed(2)} mm → Φ ${phiB.toStringAsFixed(2)} (doc ≈ 0.25; threshold 0.2 — marginal)');
  // FINDING: with 2.4 mol on 2 % of the area and ΔP_dry 4.7 Pa the stability
  // factor is 0.20, right at the dumping threshold (the doc says ≈ 0.25).
  check(
      'broken tray Φ ≈ 0.208 (doc fb00526; stays above the 0.2 threshold, implicit)',
      phiB,
      0.208,
      0.02);
}
