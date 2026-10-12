// Standalone driver for the M4 reference numbers: Tier-2 thermo spot values
// (VC-10), the B-T Tier-2 MESH steady state (VC-11), the methanol–water
// preset and the pressure sweep / utility limits (VC-27), condenser and
// reboiler design, PC-101 tuning (VC-16.6), the tier-switch rule (§13.5,
// VC-8.9), VC-8.7 and the G8 limits, F15/F11 numbers.
//   dart run packages/lowsys_engine/test/validation/reference/reference_main_m4.dart
// No engine imports. Exit code 1 if a comparison fails.
library;

import 'dart:io';
import 'dart:math' as math;

import 'cmo_steady_reference.dart';
import 'pid_reference.dart';
import 'thermo_reference.dart';
import 'tier2_steady_reference.dart';
import 'validation_expectations_m4.dart';

var _fail = 0, _pass = 0, _docDiffs = 0;

/// While true, a mismatch is a documented disagreement with VALIDATION.md
/// ("DIFF (doc)"), not a failure of this reference.
var _docMode = false;

void check(String label, double got, double expected, double tol,
    {bool rel = false}) {
  final t = rel ? tol * expected.abs() : tol;
  final ok = (got - expected).abs() <= t;
  if (ok) {
    _pass++;
  } else if (_docMode) {
    _docDiffs++;
  } else {
    _fail++;
  }
  stdout.writeln(
      '${ok ? 'PASS' : (_docMode ? 'DIFF (doc)' : 'FAIL')}  $label: got ${got.toStringAsPrecision(7)} expected '
      '${expected.toStringAsPrecision(7)} (tol ${rel ? '${100 * tol} %' : tol})');
}

void section(String s) => stdout.writeln('\n=== $s ===');
const kmolh = 1000 / 3600;
const cpW = 4180.0;

void main() {
  spotValues();
  final vc11r = vc11Case();
  methanolWater();
  final sweep = pressureSweep();
  utilities(sweep);
  condenserAndPc();
  tierSwitch(vc11r);
  faults();
  nistCrossCheck();
  sweepConsistency();
  stdout.writeln(
      '\n$_pass passed, $_fail failed, $_docDiffs documented disagreements with VALIDATION.md (VC-27.2/27.3 tables)');
  if (_fail > 0) exitCode = 1;
}

// --------------------------------------------------------------- VC-10
void spotValues() {
  section('VC-10.1 normal boiling points from the vapour-pressure models');
  final comps = {
    'benzene': benzene,
    'toluene': toluene,
    'methanol': methanol,
    'ethanol': ethanol,
    'acetone': acetone,
    'chloroform': chloroform,
    'water': water,
  };
  for (final (id, tb) in vc101) {
    check('T_b $id (°C)', comps[id]!.tbModel() - 273.15, tb, 0.005);
  }
  section('VC-10.2 water');
  check('P_sat(25 °C)', water.psat(298.15), vc102.psat25, 0.0005, rel: true);
  check('P_sat(150 °C)', water.psat(423.15), vc102.psat150, 0.0005, rel: true);
  for (final (barG, tC) in vc102.tsatBarG) {
    check('T_sat at $barG bar(g)', waterTsat(barG * 1e5 + atm) - 273.15, tC,
        0.01);
  }
  section('VC-10.3 B-T bubble points at 1 atm (Raoult)');
  for (final (x, tC, y, al) in vc103) {
    final t = bt.bubbleT(atm, x);
    check('x=$x T', t - 273.15, tC, 0.002);
    check('x=$x y', x * benzene.psat(t) / atm, y, 1e-5);
    check('x=$x α', bt.alpha(t), al, 1e-4);
  }
  for (final (p, tC, al) in vc103Pressure) {
    final t = bt.bubbleT(p, 0.5);
    check('x=0.5 at ${p / 1e5} bar T', t - 273.15, tC, 0.002);
    check('x=0.5 at ${p / 1e5} bar α', bt.alpha(t), al, 1e-4);
  }
  final t07 = bt.bubbleT(0.7e5, 0.5);
  stdout.writeln(
      '  G8: α at x = 0.5: 0.7 bar ${bt.alpha(t07).toStringAsFixed(3)}, 1 atm ${bt.alpha(bt.bubbleT(atm, 0.5)).toStringAsFixed(3)}, '
      '2 bar ${bt.alpha(bt.bubbleT(2e5, 0.5)).toStringAsFixed(3)}, 3 bar ${bt.alpha(bt.bubbleT(3e5, 0.5)).toStringAsFixed(3)}');
  check('G8 α at 0.7 bar ≈ 2.60', bt.alpha(t07), 2.60, 0.01);
  section('VC-10.7 property correlations');
  check('Rackett benzene 80 °C', benzene.rhoL(353.15), vc107.rhoBenzene80, 0.1);
  check(
      'Rackett toluene 110 °C', toluene.rhoL(383.15), vc107.rhoToluene110, 0.1);
  check('Rackett water 100 °C (Z_RA 0.4945)', water.rhoL(373.15),
      vc107.rhoWater100, 0.1);
  check('Pitzer Z saturated benzene vapour 1 atm 353.15 K',
      pitzerZ(353.15, atm, [benzene], [1.0]), vc107.zBenzeneSat, 1e-4);
  check('Watson ΔH_vap benzene at 298.15 K (kJ/mol)',
      benzene.dHvap(298.15) / 1000, vc107.watsonBenzene298, 0.01);
  // implied vapour Cp check of §3.3: Cp_L + dΔH/dT at 353 K ≈ 92 J/mol/K (true ≈ 96)
  final dh = (benzene.hV(353.65) - benzene.hV(352.65)) / 1.0;
  stdout.writeln(
      '  implied benzene vapour Cp at 353 K: ${dh.toStringAsFixed(1)} J/mol/K (doc 92; ideal gas ≈ 96)');
  check('implied vapour Cp ≈ 92', dh, 92, 3);
}

// --------------------------------------------------------------- VC-11
Tier2Result vc11Case() {
  section('VC-11 B-T Tier-2 MESH steady state (E = 1, L0 100, D 50, 1 atm)');
  const col = Tier2Column(
      sys: bt,
      nTrays: 20,
      feedTray: 10,
      f: 100 * kmolh,
      z: 0.5,
      l0: 100 * kmolh,
      d: 50 * kmolh,
      p: atm,
      e: 1.0);
  final guess = solveNewton(const CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 141,
          e: 1.0))
      .x;
  final r = solveTier2(col, xGuess: guess);
  stdout.writeln(
      '  Newton: ${r.iterations} iterations, max residual ${r.maxResidual.toStringAsExponential(1)}');
  check('x_D', r.xD, vc11.xD, 5e-5);
  check('x_B', r.xB, vc11.xB, 5e-5);
  check('T_D (°C)', r.t[0] - 273.15, vc11.tD, 0.02);
  check('T_B (°C)', r.t[21] - 273.15, vc11.tB, 0.02);
  check('Q_R (kW)', r.qR / 1000, vc11.qR, 0.001, rel: true);
  check('Q_C (kW)', r.qC / 1000, vc11.qC, 0.002, rel: true);
  check('V_1 (kmol/h)', r.v[1] / kmolh, vc11.v1, 0.001, rel: true);
  check('V_B (kmol/h)', r.v[21] / kmolh, vc11.vB, 0.001, rel: true);
  check('L_10 (kmol/h)', r.l[10] / kmolh, vc11.l10, 0.001, rel: true);
  for (final (j, x, tC, v, l) in vc11Profile) {
    check('stage $j x', r.x[j], x, 1e-4);
    check('stage $j T', r.t[j] - 273.15, tC, 0.02);
    check('stage $j V', r.v[j] / kmolh, v, 0.001, rel: true);
    if (!l.isNaN) check('stage $j L', r.l[j] / kmolh, l, 0.001, rel: true);
  }
  check('energy closure (W) < 1', energyClosure(col, r), 0, 1.0);
  for (final (name, l0, ft, d, xD, xB, qR, qC) in vc11Further) {
    final c2 = Tier2Column(
        sys: bt,
        nTrays: 20,
        feedTray: ft,
        f: 100 * kmolh,
        z: 0.5,
        l0: l0 * kmolh,
        d: d * kmolh,
        p: atm,
        e: 1.0);
    final g2 = solveNewton(CmoColumn(
            alpha: 2.5,
            nTrays: 20,
            feedTray: ft,
            f: 100,
            z: 0.5,
            q: 1,
            l0: l0,
            vB: l0 + d,
            e: 1.0))
        .x;
    final r2 = solveTier2(c2, xGuess: g2);
    check('$name x_D', r2.xD, xD, 5e-5);
    check('$name x_B', r2.xB, xB, 5e-5);
    check('$name Q_R (kW)', r2.qR / 1000, qR, 0.002, rel: true);
    if (!qC.isNaN) check('$name Q_C (kW)', r2.qC / 1000, qC, 0.002, rel: true);
  }
  return r;
}

// --------------------------------------------------------------- VC-27.1
void methanolWater() {
  section(
      'VC-27.1 methanol–water preset, Tier 2 Raoult (E 0.7, feed 12, z 0.3, L0 60, D 30)');
  const col = Tier2Column(
      sys: mw,
      nTrays: 20,
      feedTray: 12,
      f: 100 * kmolh,
      z: 0.3,
      l0: 60 * kmolh,
      d: 30 * kmolh,
      p: atm,
      e: 0.7);
  final guess = solveNewton(const CmoColumn(
          alpha: 3.5,
          nTrays: 20,
          feedTray: 12,
          f: 100,
          z: 0.3,
          q: 1,
          l0: 60,
          vB: 80,
          e: 0.7))
      .x;
  final r = solveTier2(col, xGuess: guess);
  stdout.writeln(
      '  Newton: ${r.iterations} iterations, residual ${r.maxResidual.toStringAsExponential(1)}; '
      'Q_R ${(r.qR / 1000).toStringAsFixed(1)} kW, V1 ${(r.v[1] / kmolh).toStringAsFixed(2)}, V_B ${(r.v[21] / kmolh).toStringAsFixed(2)}');
  check('Q_R at D = 30 (kW)', r.qR / 1000, vc271.qR, 0.003, rel: true);
  check('x_D', r.xD, vc271.xD, 1e-4);
  check('x_B', r.xB, vc271.xB, 1e-4);
  check('T_D', r.t[0] - 273.15, vc271.tD, 0.05);
  check('T_B', r.t[21] - 273.15, vc271.tB, 0.05);
  check('V_1', r.v[1] / kmolh, vc271.v1, 0.002, rel: true);
  check('V_B', r.v[21] / kmolh, vc271.vB, 0.002, rel: true);
  check('L_1', r.l[1] / kmolh, vc271.l1, 0.002, rel: true);
  check('L_19', r.l[19] / kmolh, vc271.l19, 0.002, rel: true);
  check('Q_C', r.qC / 1000, vc271.qC, 0.003, rel: true);
  check('boilup/top ratio ≈ 0.88 (G7: "about 12 %")', 1 - r.v[21] / r.v[1],
      0.12, 0.01);
  // utility design values
  final m50 = 0.5 * 41.54;
  final ua = bisect(
      (u) => u * (r.t[0] - 273.15 - 30) / (1 + u / (2 * m50 * cpW)) - r.qC,
      1,
      2e5);
  check('condenser UA_clean at 50 % CW (kW/K)', ua / 1000, vc271.uaCond, 0.3);
  final uaR = r.qR / (0.6 * (148.10 - (r.t[21] - 273.15)));
  check('reboiler UA_R,clean (kW/K)', uaR / 1000, vc271.uaReb, 0.3);
  // Tier 1 on the same column
  final t1 = solveNewton(const CmoColumn(
      alpha: 3.5,
      nTrays: 20,
      feedTray: 12,
      f: 100,
      z: 0.3,
      q: 1,
      l0: 60,
      vB: 90,
      e: 0.7));
  check('Tier 1 same column x_D', t1.xD, vc271.tier1Xd, 1e-4);
  check('Tier 1 same column x_B', t1.xB, vc271.tier1Xb, 1e-4);
}

// --------------------------------------------------------------- VC-27.2
List<Tier2Result> pressureSweep() {
  section('VC-27.2 B-T pressure sweep at L0 100, D 50 (E 0.7)');
  final out = <Tier2Result>[];
  _docMode =
      true; // the table's T and x columns are inconsistent (see sweepConsistency)
  for (final (pBar, qR, xD, xB, tD, tB, al) in vc272) {
    final col = Tier2Column(
        sys: bt,
        nTrays: 20,
        feedTray: 10,
        f: 100 * kmolh,
        z: 0.5,
        l0: 100 * kmolh,
        d: 50 * kmolh,
        p: pBar * 1e5,
        e: 0.7);
    final guess = solveNewton(const CmoColumn(
            alpha: 2.5,
            nTrays: 20,
            feedTray: 10,
            f: 100,
            z: 0.5,
            q: 1,
            l0: 100,
            vB: 141,
            e: 0.7))
        .x;
    final r = solveTier2(col, xGuess: guess);
    out.add(r);
    stdout.writeln(
        '  P ${pBar.toStringAsFixed(3)} bar: Q_R ${(r.qR / 1000).toStringAsFixed(1)} kW, x_D ${r.xD.toStringAsFixed(5)}, '
        'x_B ${r.xB.toStringAsFixed(5)}, T_D ${(r.t[0] - 273.15).toStringAsFixed(2)}, T_B ${(r.t[21] - 273.15).toStringAsFixed(2)}, '
        'α(feed tray) ${bt.alpha(r.t[10]).toStringAsFixed(3)} (${r.iterations} it)');
    check('P $pBar Q_R', r.qR / 1000, qR, 0.003, rel: true);
    check('P $pBar x_D', r.xD, xD, 2e-4);
    check('P $pBar x_B', r.xB, xB, 2e-4);
    check('P $pBar T_D', r.t[0] - 273.15, tD, 0.05);
    check('P $pBar T_B', r.t[21] - 273.15, tB, 0.05);
    check('P $pBar α feed tray', bt.alpha(r.t[10]), al, 0.002);
  }
  _docMode = false;
  // VC-8.7 direction: duty falls with pressure at fixed L0 and D; T_B +24.3 K
  check('VC-8.7 Q_R(2 bar) < Q_R(1 atm)', out[3].qR < out[2].qR ? 1 : 0, 1, 0);
  check('VC-8.7 bottom T rise 1 atm → 2 bar (K): doc 24.3, this reference 25.1',
      out[3].t[21] - out[2].t[21], 25.1, 0.15);
  check('VC-8.7 x_D falls', out[3].xD < out[2].xD ? 1 : 0, 1, 0);
  return out;
}

// --------------------------------------------------------------- VC-27.3
void utilities(List<Tier2Result> sweep) {
  section('VC-27.3 what the default utilities can deliver (kW)');
  _docMode = true; // derived from the VC-27.2 temperatures
  final tSt35 = waterTsat(3.5e5 + atm) - 273.15;
  final tSt10 = waterTsat(10e5 + atm) - 273.15;
  for (var i = 0; i < vc273.length; i++) {
    final (pBar, r35, r10, c30, c15) = vc273[i];
    final r = sweep[i];
    final tB = r.t[21] - 273.15, tD = r.t[0] - 273.15;
    final q35 = 57.5 * (tSt35 - tB);
    final q10 = 57.5 * (tSt10 - tB);
    double cond(double tCw) =>
        29.9 * (tD - tCw) / (1 + 29.9 / (2 * 41.54 * 4.18));
    stdout.writeln(
        '  P $pBar: reboiler ${q35.toStringAsFixed(0)} / ${q10.toStringAsFixed(0)}, condenser ${cond(30).toStringAsFixed(0)} / ${cond(15).toStringAsFixed(0)}; need ≈ ${(r.qR / 1000).toStringAsFixed(0)}');
    if (!r35.isNaN) {
      check('P $pBar reboiler Q_max 3.5 bar(g)', q35, r35, 0.01, rel: true);
    } else {
      check('P $pBar reboiler: none (T_B > T_st)', tB > tSt35 ? 1 : 0, 1, 0);
    }
    check('P $pBar reboiler Q_max 10 bar(g)', q10, r10, 0.01, rel: true);
    check('P $pBar condenser max CW 30 °C', cond(30), c30, 0.01, rel: true);
    check('P $pBar condenser max CW 15 °C', cond(15), c15, 0.01, rel: true);
  }
  _docMode = false;
  final need05 = sweep[0].qR / 1000 - 20;
  check(
      'G8: at 0.5 bar the condenser (CW 15 °C, 1194 kW) cannot take ≈ ${need05.toStringAsFixed(0)} kW',
      1194 < need05 ? 1 : 0,
      1,
      0);
  check(
      'G8: at 2 bar the 3.5 bar(g) reboiler (880 kW) cannot deliver ${(sweep[3].qR / 1000).toStringAsFixed(0)} kW',
      880 < sweep[3].qR / 1000 ? 1 : 0,
      1,
      0);
  check('G8: 0.7 bar feasible with CW 15 °C',
      1462 > sweep[1].qR / 1000 - 20 ? 1 : 0, 1, 0);
  check('G8: 3 bar feasible with 10 bar(g) steam',
      2015 > sweep[4].qR / 1000 ? 1 : 0, 1, 0);
}

// ------------------------------------------------ condenser design, PC-101
void condenserAndPc() {
  section('Condenser design (PHYSICS.md §7.2) and PC-101 (VC-16.6)');
  final m50 = condenserDesign.opPct / 100 * condenserDesign.mCwMax;
  final ua = bisect(
      (u) =>
          u *
              (condenserDesign.tCond - condenserDesign.tCwIn) /
              (1 + u / (2 * m50 * cpW)) -
          condenserDesign.qC * 1000,
      1,
      2e5);
  check('UA_clean at 50 % CW (kW/K)', ua / 1000, condenserDesign.ua, 0.1);
  check(
      'CW outlet (°C)',
      condenserDesign.tCwIn + condenserDesign.qC * 1000 / (m50 * cpW),
      condenserDesign.tOut,
      0.1);
  double qAt(double op) =>
      ua *
      (condenserDesign.tCond - condenserDesign.tCwIn) /
      (1 + ua / (2 * op / 100 * condenserDesign.mCwMax * cpW));
  final lo = qAt(25) / qAt(50) - 1, hi = qAt(100) / qAt(50) - 1;
  stdout.writeln(
      '  valve authority: 25 % → ${(100 * lo).toStringAsFixed(1)} %, 100 % → +${(100 * hi).toStringAsFixed(1)} % of design duty (doc −13 … +7.9 %)');
  check('duty at 100 % CW: +7.9 %', 100 * hi, 7.9, 0.3);
  check('duty at 25 % CW: −13 %', 100 * lo, -13, 0.5);
  final ua70 = bisect(
      (u) =>
          u *
              (condenserDesign.tCond - condenserDesign.tCwIn) /
              (1 + u / (2 * 0.7 * condenserDesign.mCwMax * cpW)) -
          condenserDesign.qC * 1000,
      1,
      2e5);
  final hi70 = ua70 *
          (condenserDesign.tCond - condenserDesign.tCwIn) /
          (1 + ua70 / (2 * condenserDesign.mCwMax * cpW)) /
          (condenserDesign.qC * 1000) -
      1;
  stdout.writeln(
      '  v1.0 design at 70 % CW: UA ${(ua70 / 1000).toStringAsFixed(1)} kW/K, a fully open valve adds only ${(100 * hi70).toStringAsFixed(1)} % (doc 3.2 %)');
  check('v1.0 70 % design: +3.2 % only', 100 * hi70, 3.2, 0.3);
  check(
      'reboiler UA_R: 1300 kW = 60 % of 57.5 (148.1 − 110.4)',
      0.6 * reboilerDesign.ua * (reboilerDesign.tSt - 110.4),
      reboilerDesign.qDesign,
      3);

  // PC-101 on a first-order pressure plant: gain from the open-loop step (−10 % OP → +5.8 kPa), τ = 190 s
  const span = 202650.0; // Pa
  final kProc = -pc101.openLoopGainKpaPer10Pct * 1000 / 10; // Pa per % OP
  for (final (label, step) in [('+10 kPa', 10000.0), ('−10 kPa', -10000.0)]) {
    final pid = RefPid(
        kc: pc101.kc,
        ti: pc101.ti,
        action: RefAction.direct,
        spKick: false,
        lo: 0,
        hi: span,
        sp: atm,
        op: 50);
    var p = atm;
    var pOut = atm; // plant state (lagged)
    pid.execute(p, 0.5);
    pid.setSp(atm + step);
    double? tSettle;
    var overshoot = 0.0;
    for (var k = 1; k <= 2400; k++) {
      final op = pid.execute(p, 0.5);
      // first-order plant: P_ss = P0 + kProc (OP − 50), τ = 190 s, valve range 25–100 % duty-limited
      final opEff = op.clamp(25.0, 100.0);
      final pSs = atm + kProc * (opEff - 50);
      pOut += (pSs - pOut) * 0.5 / (pc101.openLoopT63 + 0.5);
      p = pOut;
      final err = (p - (atm + step)).abs();
      if (step > 0) overshoot = math.max(overshoot, p - (atm + step));
      if (step < 0) overshoot = math.max(overshoot, (atm + step) - p);
      if (tSettle == null && err < 1000) {
        // require it to stay within 1 kPa
        tSettle = k * 0.5;
      } else if (tSettle != null && err >= 1000) {
        tSettle = null;
      }
    }
    stdout.writeln(
        '  PC-101 $label: settles within ±1 kPa at ${tSettle?.toStringAsFixed(0)} s (doc < 600, proto ${step > 0 ? pc101.settlePlus : pc101.settleMinus}), overshoot ${(overshoot / step.abs() * 100).toStringAsFixed(1)} %');
    check('PC-101 $label settles < 600 s', tSettle ?? 1e9, 300, 300);
    check('PC-101 $label overshoot ≤ 30 %', overshoot / step.abs(), 0, 0.30);
  }
  // linear analysis: ζ ≈ 0.9 for Kc 10, Ti 120 on K = 0.286 %span/%OP, τ 190 s
  final kLoop =
      (pc101.openLoopGainKpaPer10Pct * 1000 / 10) / span * 100 * pc101.kc;
  final wn = math.sqrt(kLoop / (pc101.openLoopT63 * pc101.ti));
  final zeta = pc101.ti * (1 + kLoop) / (2 * pc101.openLoopT63 * pc101.ti * wn);
  stdout.writeln(
      '  linear: K·Kc = ${kLoop.toStringAsFixed(2)}, ω_n = ${wn.toStringAsExponential(2)} rad/s, ζ = ${zeta.toStringAsFixed(2)}, 4/(ζω_n) = ${(4 / (zeta * wn)).toStringAsFixed(0)} s');
  check('PC-101 damping ζ in 0.7–1.2 (no sustained oscillation)', zeta, 0.95,
      0.25);
}

// ---------------------------------------------------------- §13.5 / VC-8.9
void tierSwitch(Tier2Result vc11r) {
  section('Tier switch rule (PHYSICS.md §13.5, VC-8.9): keep V1 and D');
  // T1 default steady state (E 0.7): x from the CMO reference, T by bubble point at 1 atm
  final t1 = solveNewton(btDefaultE07);
  final x = t1.x;
  final t = [for (final xi in x) bt.bubbleT(atm, xi)];
  final y1 = t1.y[1];
  const f = 100 * kmolh, d = 50 * kmolh, b = 50 * kmolh, v1 = 150 * kmolh;
  final tF = bt.bubbleT(atm, 0.5);
  final qR = v1 * (bt.hV(t[1], y1) - bt.hL(t[0], x[0])) +
      d * bt.hL(t[0], x[0]) +
      b * bt.hL(t[21], x[21]) -
      f * bt.hL(tF, 0.5);
  stdout.writeln(
      '  Q_R that keeps V1 = 150 kmol/h: ${(qR / 1000).toStringAsFixed(1)} kW (VC-27.2 at 1 atm with E 0.7: 1306.9)');
  check('switch duty ≈ the E 0.7 Tier-2 duty at the same L0, D', qR / 1000,
      1306.9, 0.02,
      rel: true);
  // latent heats top vs bottom → boilup/top ratio and the +4.3 % if V_B were kept
  final lamTop = bt.hV(t[1], y1) - bt.hL(t[1], x[1]);
  final lamBot = bt.hV(t[21], t1.y[21]) - bt.hL(t[21], x[21]);
  stdout.writeln(
      '  λ_top ${(lamTop / 1000).toStringAsFixed(2)} kJ/mol, λ_bottom ${(lamBot / 1000).toStringAsFixed(2)} kJ/mol → V_B/V1 ≈ ${(lamTop / lamBot).toStringAsFixed(3)}');
  // The λ ratio ignores the sensible heat of the liquid warming down the
  // column (VC-11: V_B/V1 = 0.9408 against a λ ratio of 0.928). Use the
  // sump energy balance on the T1 profile with Q_R fixed by the top-vapour
  // rule for the first-step V_B, and the full E 0.7 solve for the steady one.
  final hB = bt.hL(t[21], x[21]);
  // PHYSICS.md (4.7): V_{N+1} = [L_N (h_N − h_B) + Q_R] / (H_B − h_B)
  final vBFirst = (qR + 200 * kmolh * (bt.hL(t[20], x[20]) - hB)) /
      (bt.hV(t[21], t1.y[21]) - hB);
  stdout.writeln(
      '  first-step V_B from the sump balance on the T1 profile: ${(vBFirst / kmolh).toStringAsFixed(1)} kmol/h (doc ≈ 141.9); '
      'keeping V_B = 150 instead would raise V1 by ≈ ${(100 * (150 * kmolh / vBFirst - 1)).toStringAsFixed(1)} % (doc +4.3 %)');
  check(
      'first-step V_B ≈ 141.9 (±2)', vBFirst / kmolh, vc89.vBAfterSwitch, 2.0);
  const colSw = Tier2Column(
      sys: bt,
      nTrays: 20,
      feedTray: 10,
      f: 100 * kmolh,
      z: 0.5,
      l0: 100 * kmolh,
      d: 49.96 * kmolh,
      p: atm,
      e: 0.7);
  final rSw = solveTier2(colSw, xGuess: x);
  stdout.writeln(
      '  new Tier-2 steady state at D 49.96: x_D ${rSw.xD.toStringAsFixed(5)}, V_B ${(rSw.v[21] / kmolh).toStringAsFixed(1)}, Q_R ${(rSw.qR / 1000).toStringAsFixed(1)} kW');
  check('VC-8.9 new steady x_D 0.97838', rSw.xD, vc89.xDNewSteady, 0.0005);
  check(
      'VC-8.9 new steady x_D 0.97838 vs E 0.7 Tier-2 reference 0.97662 at D 50 (D 49.96 lifts it)',
      vc89.xDNewSteady - 0.97662,
      0.0018,
      0.002);
  stdout.writeln(
      '  VC-11 cross-check: λ ratio at E = 1 gives V_B/V1 = ${(vc11r.v[21] / vc11r.v[1]).toStringAsFixed(4)} (0.9408 from the table)');
}

// --------------------------------------------------------------- faults
void faults() {
  section('F15 / F09 / F11 numbers (PHYSICS.md §11, VC-27.4)');
  for (final (s, pBar, tSt, qMax) in f15) {
    final p = (3.5e5 + atm) * (1 - 0.6 * s);
    final t = waterTsat(p) - 273.15;
    check('F15 s=$s header (bar a)', p / 1e5, pBar, 0.01);
    check('F15 s=$s T_st (°C)', t, tSt, 0.1);
    check('F15 s=$s Q_max (kW)', 57.5 * (t - 110.386), qMax, 0.01, rel: true);
  }
  final sLimit = bisect(
      (s) =>
          57.5 * (waterTsat((3.5e5 + atm) * (1 - 0.6 * s)) - 273.15 - 110.386) -
          1300,
      0,
      1);
  check('F15 duty limit starts at s ≈ 0.58', sLimit, f15LimitS, 0.01);
  check(
      'F09 flow: s = 0.5 → a fully open valve delivers exactly the design CW flow (50 % of max)',
      (1 - 0.5) * 100,
      50,
      1e-9);
  final nV = atm * 3.0 / (r * (80.2 + 273.15));
  final inert = 1e-4 * 100 * kmolh * 3600;
  final yI = inert / (nV + inert);
  check('F11 overhead inventory (mol)', nV, f11.overheadMol, 1.5);
  check('F11 inert per hour (mol)', inert, f11.inertPerHour, 0.1);
  check('F11 y_I after 1 h', yI, f11.yI1h, 0.005);
  check('F11 f_blanket = 3 y_I', 3 * yI, f11.fBlanket1h, 0.01);
  check(
      'F11 extra subcooling 20 f_blanket (K)', 20 * 3 * yI, f11.subcool1h, 0.4);
}

const btDefaultE07 = CmoColumn(
    alpha: 2.5,
    nTrays: 20,
    feedTray: 10,
    f: 100,
    z: 0.5,
    q: 1,
    l0: 100,
    vB: 150,
    e: 0.7);

/// NIST WebBook cross-check (fetched 2026-10-12, phase-change pages): the
/// Majer & Svoboda ΔvapH(T_b), T_b/T_c/P_c and the NIST Antoine sets
/// (log10 P/bar = A − B/(T + C), T in K) against the PHYSICS.md §2.1/§2.2 data.
void nistCrossCheck() {
  section('NIST WebBook cross-check of the §2.1 / §2.2 data');
  check('benzene ΔvapH(T_b) NIST 30.72 kJ/mol', benzene.dHvapTb / 1000, 30.72,
      1e-9);
  check('toluene ΔvapH(T_b) NIST 33.18', toluene.dHvapTb / 1000, 33.18, 1e-9);
  check('methanol ΔvapH(T_b) NIST 35.21', methanol.dHvapTb / 1000, 35.21, 1e-9);
  check('benzene T_b NIST 353.3 ± 0.1 K', benzene.tbModel(), 353.3, 0.15);
  check('toluene T_b NIST 383.8 ± 0.2 K', toluene.tbModel(), 383.8, 0.25);
  check('methanol T_b NIST 337.8 ± 0.3 K', methanol.tbModel(), 337.8, 0.35);
  check('benzene T_c NIST 562.0 ± 0.8', benzene.tc, 562.0, 0.8);
  check('toluene T_c NIST 593 ± 2', toluene.tc, 593, 2);
  check('methanol T_c NIST 513 ± 1', methanol.tc, 513, 1);
  check('benzene P_c NIST 48.9 ± 0.4 bar', benzene.pc / 1e5, 48.9, 0.4);
  check('toluene P_c NIST 41 ± 1 bar', toluene.pc / 1e5, 41, 1);
  check('methanol P_c NIST 81 ± 1 bar', methanol.pc / 1e5, 81, 1);
  // NIST Antoine sets evaluated at the model boiling points: should give ≈ 1.013 bar
  double nist(double a, double b, double c, double t) =>
      math.pow(10, a - b / (t + c)).toDouble();
  final pB = nist(4.01814, 1203.835, -53.226,
      benzene.tbModel()); // Williamham 1945, 287.7–354.07 K
  final pT = nist(4.07827, 1343.943, -53.773,
      toluene.tbModel()); // Williamham 1945, 308.5–384.66 K
  final pM = nist(5.20409, 1581.341, -33.50,
      methanol.tbModel()); // Ambrose & Sprake 1970, 288.1–356.83 K
  stdout.writeln(
      '  NIST Antoine at the model T_b: benzene ${pB.toStringAsFixed(4)} bar, toluene ${pT.toStringAsFixed(4)}, methanol ${pM.toStringAsFixed(4)}');
  check(
      'benzene: Lange and NIST sets agree at T_b (±0.3 %)', pB, 1.01325, 0.003,
      rel: true);
  check('toluene: agree at T_b (±0.3 %)', pT, 1.01325, 0.003, rel: true);
  check('methanol: agree at T_b (±0.5 %, NIST T_b 337.8 vs model 337.65)', pM,
      1.01325, 0.005,
      rel: true);
  // the Williamham benzene set converted to mmHg/°C: A = 4.01814 + log10(750.062) = 6.8932, C = 219.92
  check('benzene Lange C 220.79 vs NIST-converted 219.92 (same family of fits)',
      220.79, 219.92, 1.0);
}

/// Self-consistency of the VC-27.2 table: the bubble point of the table's
/// own x_D (x_B) at the table's pressure must equal its T_D (T_B) if the
/// rows come from one Raoult model.
void sweepConsistency() {
  section(
      'VC-27.2 self-consistency: bubble points of the table\'s own compositions');
  _docMode = true;
  for (final (pBar, _, xD, xB, tD, tB, _) in vc272) {
    final tDc = bt.bubbleT(pBar * 1e5, xD) - 273.15;
    final tBc = bt.bubbleT(pBar * 1e5, xB) - 273.15;
    stdout.writeln(
        '  P $pBar: bubble(x_D ${xD.toStringAsFixed(5)}) = ${tDc.toStringAsFixed(2)} °C vs table T_D $tD; '
        'bubble(x_B ${xB.toStringAsFixed(5)}) = ${tBc.toStringAsFixed(2)} vs table T_B $tB');
    check('P $pBar table T_D consistent with its x_D (±0.05 K)', tD, tDc, 0.05);
    check('P $pBar table T_B consistent with its x_B (±0.05 K)', tB, tBc, 0.05);
  }
  stdout.writeln(
      '  pure benzene boils at ${(benzene.tbModel() - 273.15).toStringAsFixed(2)} °C at 1 atm: a 97.7 % benzene '
      'distillate cannot have T_D = 79.60 °C there.');
  _docMode = false;
  // VC-8.9 says x_D 0.97838 at D = 49.96 after the switch; VC-27.2 says 0.97662 at D = 50.
  const col = Tier2Column(
      sys: bt,
      nTrays: 20,
      feedTray: 10,
      f: 100 * kmolh,
      z: 0.5,
      l0: 100 * kmolh,
      d: 49.96 * kmolh,
      p: atm,
      e: 0.7);
  final r = solveTier2(col, xGuess: solveNewton(btDefaultE07).x);
  stdout.writeln(
      '  this reference at D = 49.96: x_D ${r.xD.toStringAsFixed(5)} (VC-8.9 says 0.97838 ± 0.0005)');
  check('VC-8.9 x_D 0.97838 at D 49.96 agrees with this reference', r.xD,
      0.97838, 0.0005);
}
