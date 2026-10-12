// Standalone driver: recomputes the M1-relevant VALIDATION.md reference
// numbers (VC-1, VC-2, VC-3.1, VC-4, VC-7 end state, VC-18 invariants) with
// the independent calculators in this directory and prints a PASS/FAIL
// comparison against the values written in VALIDATION.md.
//
// Run from anywhere (no pubspec needed):
//   dart run packages/lowsys_engine/test/validation/reference/reference_main.dart
//
// No engine imports. Exit code 1 if any comparison fails.
library;

import 'dart:io';
import 'dart:math' as math;

import 'cmo_steady_reference.dart';
import 'mccabe_thiele_reference.dart';
import 'validation_expectations.dart';

var _fail = 0;
var _pass = 0;

void check(String label, double got, double expected, double tol) {
  final ok = (got - expected).abs() <= tol;
  if (ok) {
    _pass++;
  } else {
    _fail++;
  }
  stdout.writeln(
      '${ok ? 'PASS' : 'FAIL'}  $label: got ${got.toStringAsPrecision(9)}'
      ' expected ${expected.toStringAsPrecision(9)} (tol $tol'
      ', diff ${(got - expected).toStringAsExponential(2)})');
}

void section(String s) => stdout.writeln('\n=== $s ===');

void main() {
  // ---------------------------------------------------------------- VC-1
  section('VC-1 McCabe–Thiele textbook problem (alpha 2.5, z 0.5, q 1, '
      'xD 0.95, xB 0.05, R = 1.5 Rmin)');
  const alpha = 2.5, z = 0.5, xD = 0.95, xB = 0.05;
  final dOverF = (z - xB) / (xD - xB);
  check('D/F', dOverF, 0.5, 1e-12);
  final pinch = qLinePinch(alpha, z, 1.0);
  check('pinch x*', pinch.x, vc1.pinchX, 1e-5);
  check('pinch y*', pinch.y, vc1.pinchY, 1e-5);
  final rMin = rMinFeedPinch(alpha, z, 1.0, xD);
  check('R_min (feed pinch)', rMin, vc1.rMin, 1e-4);
  check('R_min (scan, tangent-pinch safe)', rMinScan(alpha, z, 1.0, xD),
      vc1.rMin, 1e-4);
  final nMin = fenskeNmin(alpha, xD, xB);
  check('N_min Fenske', nMin, vc1.nMin, 1e-4);
  final r = 1.5 * rMin;
  check('R = 1.5 R_min', r, vc1.r, 1e-12);
  final g = gilliland(nMin, r, rMin);
  check('Gilliland X', g.x, vc1.gillilandX, 1e-5);
  check('Molokanov Y', g.y, vc1.molokanovY, 1e-5);
  check('N (Molokanov)', g.n, vc1.nMolokanov, 1e-3);
  final ge = gilliland(nMin, r, rMin, eduljee: true);
  check('N (Eduljee)', ge.n, vc1.nEduljee, 1e-3);
  final st = stepStages(alpha, z, 1.0, xD, xB, r);
  check('L/V', st.lOverV, vc1.lOverV, 1e-5);
  check('Lbar/Vbar', st.lbarOverVbar, vc1.lbarOverVbar, 1e-5);
  check('stepped stages (integer)', st.stages.toDouble(), vc1.stages.toDouble(),
      0);
  check(
      'stepped stages (fractional)', st.fractional, vc1.fractionalStages, 1e-3);
  check('feed stage', st.feedStage.toDouble(), vc1.feedStage.toDouble(), 0);
  for (var i = 0; i < vc1.stageX.length; i++) {
    check('stage ${i + 1} x', st.x[i], vc1.stageX[i], 1e-5);
    check('stage ${i + 1} y', st.y[i], vc1.stageY[i], 1e-5);
  }

  // ---------------------------------------------------------------- VC-2
  section('VC-2 feed condition variants (R = 1.5 Rmin each)');
  for (final row in vc2) {
    final p = qLinePinch(alpha, z, row.q);
    check('q=${row.q} pinch x*', p.x, row.pinchX, 1e-5);
    check('q=${row.q} pinch y*', p.y, row.pinchY, 1e-5);
    final rm = rMinFeedPinch(alpha, z, row.q, xD);
    check('q=${row.q} R_min', rm, row.rMin, 1e-4);
    final nm = fenskeNmin(alpha, xD, xB);
    final gg = gilliland(nm, 1.5 * rm, rm);
    check('q=${row.q} N Molokanov', gg.n, row.nMolokanov, 1e-3);
    final s = stepStages(alpha, z, row.q, xD, xB, 1.5 * rm);
    check('q=${row.q} stepped stages', s.stages.toDouble(),
        row.stages.toDouble(), 0);
    check('q=${row.q} fractional stages', s.fractional, row.fractional, 1e-3);
    check('q=${row.q} feed stage', s.feedStage.toDouble(),
        row.feedStage.toDouble(), 0);
  }

  // -------------------------------------------------------------- VC-3.1
  section('VC-3.1 Fenske identity, symmetric total reflux');
  for (final row in vc31) {
    check('N_s=${row.n} xD', fenskeSymmetricXd(alpha, row.n), row.xD, 1e-6);
  }

  // ---------------------------------------------------------------- VC-4
  section('VC-4 steady state of the B-T column (two independent methods)');
  for (final c in vc4) {
    final col = c.column;
    final newton = solveNewton(col);
    final shoot = solveShooting(col);
    stdout.writeln('  ${c.id}: Newton xD=${newton.xD.toStringAsFixed(7)} '
        'xB=${newton.xB.toStringAsFixed(7)} (res ${newton.maxResidual.toStringAsExponential(1)}, '
        '${newton.iterations} it) | shooting xD=${shoot.xD.toStringAsFixed(7)} '
        'xB=${shoot.xB.toStringAsFixed(7)} (res ${shoot.maxResidual.toStringAsExponential(1)})');
    check('${c.id} Newton vs shooting xD', newton.xD, shoot.xD, 1e-9);
    check('${c.id} Newton vs shooting xB', newton.xB, shoot.xB, 1e-9);
    check('${c.id} xD', newton.xD, c.xD, 1e-5);
    check('${c.id} xB', newton.xB, c.xB, 1e-5);
    check('${c.id} D', newton.d, c.d, 1e-9);
    // mass balance closure of the reference itself
    final mb = (col.f * col.z - newton.d * newton.xD - newton.b * newton.xB) /
        (col.f * col.z);
    check('${c.id} light-component balance (rel)', mb, 0, 1e-12);
    // compositions inside [0, 1] and monotone down the column, except that
    // the feed tray may be richer than the tray above it when the feed
    // (z = 0.5) is richer than the liquid arriving there (feed mismatch).
    var mono = true;
    for (var j = 1; j < newton.x.length; j++) {
      if (j == col.feedTray) continue;
      if (newton.x[j] > newton.x[j - 1] + 1e-12) mono = false;
      if (newton.x[j] < 0 || newton.x[j] > 1) mono = false;
    }
    check('${c.id} x in [0,1], monotone except at the feed tray', mono ? 1 : 0,
        1, 0);
  }

  section('VC-4.14 feed-tray scan (E = 0.7)');
  for (var i = 0; i < vc414FeedTrays.length; i++) {
    final col = btDefault.copyWith(feedTray: vc414FeedTrays[i]);
    final s = solveNewton(col);
    check('feed tray ${vc414FeedTrays[i]} xD', s.xD, vc414Xd[i], 1e-5);
  }

  // ---------------------------------------------------------------- VC-7
  section('VC-7.1 reflux step end state (= VC-4.11) and mass-balance bounds');
  final v711 = solveNewton(btDefault.copyWith(l0: 110));
  check('VC-7.1 final xD', v711.xD, 0.993373, 1e-5);
  check('VC-7.1 final xB', v711.xB, 0.171085, 1e-5);
  check('VC-7.1 final D', v711.d, 40, 1e-9);
  // With D = 40 < F z = 50 the bottoms must carry at least 10/60 benzene.
  final xBfloor = (btDefault.f * btDefault.z - v711.d * 1.0) / v711.b;
  stdout.writeln('  x_B lower bound from the balance with x_D = 1: '
      '${xBfloor.toStringAsFixed(5)} (reference x_B ${v711.xB.toStringAsFixed(5)})');
  check('VC-7.1 x_B above its mass-balance floor', v711.xB > xBfloor ? 1 : 0, 1,
      0);

  // ---------------------------------------------------------------- VC-8
  section('VC-8 direction checks (Tier 1) from the steady-state reference');
  final base = solveNewton(btDefault);
  final up = solveNewton(btDefault.copyWith(l0: 110, vB: 160));
  check('8.1 L0,VB +10 → xD up', up.xD > base.xD ? 1 : 0, 1, 0);
  check('8.1 L0,VB +10 → xB down', up.xB < base.xB ? 1 : 0, 1, 0);
  check('8.1 xD value', up.xD, 0.984504, 1e-5);
  final lOnly = solveNewton(btDefault.copyWith(l0: 110));
  check('8.2 L0 only → D down', lOnly.d < base.d ? 1 : 0, 1, 0);
  check('8.2 L0 only → xD up', lOnly.xD > base.xD ? 1 : 0, 1, 0);
  check('8.2 L0 only → xB up', lOnly.xB > base.xB ? 1 : 0, 1, 0);
  final vOnly = solveNewton(btDefault.copyWith(vB: 155));
  check('8.3 VB only → D up', vOnly.d > base.d ? 1 : 0, 1, 0);
  check('8.3 VB only → xD down', vOnly.xD < base.xD ? 1 : 0, 1, 0);
  check('8.3 VB only → xB down', vOnly.xB < base.xB ? 1 : 0, 1, 0);
  final eLow = solveNewton(btDefault.copyWith(e: 0.5));
  check('8.4 E 0.7→0.5 → xD down', eLow.xD < base.xD ? 1 : 0, 1, 0);
  final zUp = solveNewton(btDefault.copyWith(z: 0.6));
  check('8.6 z 0.6 → xD up', zUp.xD > base.xD ? 1 : 0, 1, 0);
  check('8.6 z 0.6 → xB up', zUp.xB > base.xB ? 1 : 0, 1, 0);

  // --------------------------------------------------------------- VC-18
  section('VC-18 McCabe–Thiele invariants at the reference steady state');
  final e1 = solveNewton(btDefault.copyWith(e: 1.0));
  {
    final col = btDefault.copyWith(e: 1.0);
    final v = col.vapour();
    final l = col.liquid();
    var maxDev = 0.0;
    var maxEq = 0.0;
    for (var j = 0; j <= col.nTrays; j++) {
      // operating locus point (x_j, y_{j+1}) must lie on the CMO line
      final yOp = j < col.feedTray
          ? (l[j] / v[j + 1]) * e1.x[j] + col.d * e1.xD / v[j + 1]
          : (l[j] / v[j + 1]) * e1.x[j] - col.b * e1.xB / v[j + 1];
      maxDev = math.max(maxDev, (yOp - e1.y[j + 1]).abs());
    }
    for (var j = 1; j <= col.nTrays + 1; j++) {
      maxEq = math.max(maxEq, (e1.y[j] - yEq(e1.x[j], col.alpha)).abs());
    }
    check('18.1 operating locus on CMO lines (max dev)', maxDev, 0, 1e-8);
    check('18.1 corners on equilibrium curve (max dev)', maxEq, 0, 1e-8);
  }
  {
    var maxRatioDev = 0.0;
    for (var j = 1; j <= btDefault.nTrays; j++) {
      final ratio =
          (base.y[j] - base.y[j + 1]) / (yEq(base.x[j], alpha) - base.y[j + 1]);
      maxRatioDev = math.max(maxRatioDev, (ratio - 0.7).abs());
    }
    check('18.2 Murphree ratio = 0.7 on every tray (max dev)', maxRatioDev, 0,
        1e-8);
  }

  // ---------------------------------------------- physical plausibility
  section('Physical plausibility of the default column');
  plausibility();

  // ---------------------------------------------- staircase ordering
  section('Staircase ordering at the reference steady state (E = 0.7)');
  {
    // Along the staircase the corner (x_j, y_j) must sit between the
    // operating locus point below it (x_j, y_{j+1}) and the equilibrium
    // curve (x_j, y*_j); x must decrease stage by stage.
    var ok = true;
    for (var j = 1; j <= btDefault.nTrays; j++) {
      final yStar = yEq(base.x[j], alpha);
      if (!(base.y[j + 1] <= base.y[j] + 1e-12 && base.y[j] <= yStar + 1e-12)) {
        ok = false;
      }
      if (base.x[j] > base.x[j - 1]) ok = false;
    }
    check('corners between operating locus and equilibrium curve', ok ? 1 : 0,
        1, 0);
  }

  stdout.writeln('\n$_pass passed, $_fail failed');
  if (_fail > 0) exitCode = 1;
}

/// Order-of-magnitude checks that the default column (20 sieve trays,
/// 1.2 m, F = 100 kmol/h, V = 150 kmol/h) is a sensible design.
void plausibility() {
  const kmolhToMols = 1000 / 3600;
  const rhoL = 800.0, rhoV = 2.9, mwB = 78.11, mwT = 92.14;
  const dC = 1.2, fd = 0.12, hW = 0.05;
  final aT = math.pi * dC * dC / 4;
  final aD = fd * aT;
  final aN = aT - aD;
  final aA = aT - 2 * aD;
  // weir length from (θ − sin θ)/2π = f_d
  var th = 2.0;
  for (var i = 0; i < 50; i++) {
    final fn = (th - math.sin(th)) / (2 * math.pi) - fd;
    final dfn = (1 - math.cos(th)) / (2 * math.pi);
    th -= fn / dfn;
  }
  final lW = dC * math.sin(th / 2);
  stdout.writeln('  A_T=${aT.toStringAsFixed(4)} A_a=${aA.toStringAsFixed(4)} '
      'A_n=${aN.toStringAsFixed(4)} m², L_w=${lW.toStringAsFixed(4)} m');
  check('VC-12.1 A_T', aT, 1.1310, 1e-4);
  check('VC-12.1 A_a', aA, 0.8595, 1e-4);
  check('VC-12.1 A_n', aN, 0.9953, 1e-4);
  check('VC-12.1 L_w', lW, 0.9171, 1e-4);

  // vapour loading at V = 150 kmol/h, y ≈ 0.5
  final mwV = 0.5 * mwB + 0.5 * mwT;
  final vMol = 150 * kmolhToMols;
  final qV = vMol * mwV / 1000 / rhoV;
  final uN = qV / aN;
  final ks = (qV / aA) * math.sqrt(rhoV / (rhoL - rhoV));
  final csbN = uN * math.sqrt(rhoV / (rhoL - rhoV));
  stdout.writeln('  Vapour 150 kmol/h → ${qV.toStringAsFixed(3)} m³/s, '
      'u_n=${uN.toStringAsFixed(2)} m/s, C_SB(net)=${csbN.toStringAsFixed(4)} m/s '
      '(Fair at 0.6 m spacing ≈ 0.10 m/s → ≈ ${(100 * csbN / 0.10).toStringAsFixed(0)} % of flood)');
  check('design point between 50 and 90 % of jet flood',
      (csbN / 0.10 > 0.5 && csbN / 0.10 < 0.9) ? 1 : 0, 1, 0);

  // Bennett froth density, clear liquid height, tray holdup, time constant
  final alphaE = math.exp(-12.55 * math.pow(ks, 0.91));
  final cW = 0.501 + 0.438 * math.exp(-137.8 * hW);
  check('VC-12.2 Bennett C at h_w 50 mm', cW, 0.50145, 1e-4);
  for (final (name, lKmolh, xMean) in [
    ('rectifying', 100.0, 0.75),
    ('stripping', 200.0, 0.25)
  ]) {
    final mw = xMean * mwB + (1 - xMean) * mwT;
    final vL = mw / 1000 / rhoL;
    final lMol = lKmolh * kmolhToMols;
    final qw = lMol * vL;
    final hOw = cW * math.pow(qw / (lW * alphaE), 2 / 3);
    final hCl = alphaE * (hW + hOw);
    final mHold = hCl * aA / vL;
    final dLdM = 1.5 * lW * math.sqrt(hOw / cW) / (cW * aA);
    stdout.writeln('  $name L=$lKmolh kmol/h: α_e=${alphaE.toStringAsFixed(3)} '
        'h_cl=${(1000 * hCl).toStringAsFixed(1)} mm, holdup=${mHold.toStringAsFixed(0)} mol, '
        'residence=${(mHold / lMol).toStringAsFixed(1)} s, weir τ=1/(dL/dM)=${(1 / dLdM).toStringAsFixed(2)} s');
    check('$name hydraulic lag per tray 1–3 s', (1 / dLdM), 2.0, 1.0);
  }

  // drum and sump holdups and the level-loop response (VC-7.3 sanity)
  final vLD = (0.98 * mwB + 0.02 * mwT) / 1000 / rhoL;
  final mDrum = 0.5 * 3.0 / vLD;
  final vLB = (0.02 * mwB + 0.98 * mwT) / 1000 / rhoL;
  final mSump = 0.5 * (aT * 2.4) / vLB;
  stdout.writeln('  Drum holdup at 50 %: ${mDrum.toStringAsFixed(0)} mol, '
      'sump: ${mSump.toStringAsFixed(0)} mol; column ≈ 3600 mol; feed ${(100 * kmolhToMols).toStringAsFixed(2)} mol/s'
      ' → total residence ≈ ${((mDrum + mSump + 3600) / (100 * kmolhToMols) / 60).toStringAsFixed(0)} min');
  // integrating level process with PI (Kc = 2 %/%, Ti = 1800 s, D_max = 100 kmol/h)
  final kLevel = vLD * 100 / 3.0; // % per mol
  final kProc = kLevel * kmolhToMols; // % per s per kmol/h
  final kc = 2.0 * 100 / 100; // kmol/h per % (D_max = 2 × design D = 100)
  final loopGain = kProc * kc; // 1/s
  final wn = math.sqrt(loopGain / 1800);
  final zeta = loopGain / (2 * wn);
  // peak of e(t) for an integrating process under a step load d with PI:
  // numerically integrate
  var lvl = 0.0, integ = 0.0, peak = 0.0, tPeak = 0.0, tBack = -1.0;
  const dLoad = 10.0; // kmol/h reflux step
  for (var t = 0.0; t < 7200; t += 0.5) {
    final err = lvl; // lvl is PV − SP; level falls → error negative
    integ += err * 0.5;
    final dD = kc * (err + integ / 1800); // direct action: D falls
    final net = -dLoad - dD; // kmol/h into the drum (reflux up, D down)
    lvl += kProc * net * 0.5;
    if (-lvl > peak) {
      peak = -lvl;
      tPeak = t;
    }
    if (tBack < 0 && t > tPeak + 60 && lvl.abs() < 1.0 && peak > 1.0) {
      tBack = t;
    }
  }
  stdout.writeln(
      '  Level loop: ω_n=${wn.toStringAsExponential(2)} rad/s, ζ=${zeta.toStringAsFixed(2)}; '
      'reflux +10 kmol/h → drum level deviation peak ${peak.toStringAsFixed(2)} points at ${(tPeak / 60).toStringAsFixed(0)} min, '
      'back within ±1 point at ${(tBack / 60).toStringAsFixed(0)} min');
  check('VC-7.3 drum max deviation 2–6 points (linear model)', peak, 4.0, 2.0);
  check('VC-7.3 back within ±1 point before 90 min', tBack < 90 * 60 ? 1 : 0, 1,
      0);

  // shortcut consistency of the default steady state
  final base = solveNewton(btDefault);
  final rMinDef = rMinFeedPinch(2.5, 0.5, 1.0, base.xD);
  final nMinDef = fenskeNmin(2.5, base.xD, base.xB);
  final rDef = btDefault.l0 / base.d;
  final gDef = gilliland(nMinDef, rDef, rMinDef);
  stdout.writeln(
      '  Default steady state: R=${rDef.toStringAsFixed(2)}, R_min=${rMinDef.toStringAsFixed(3)} '
      '(R/R_min=${(rDef / rMinDef).toStringAsFixed(2)}), N_min=${nMinDef.toStringAsFixed(2)}, '
      'Gilliland N=${gDef.n.toStringAsFixed(1)} theoretical stages vs 20 trays × 0.7 + reboiler ≈ 15');
  check('Gilliland stage count consistent with 20×0.7+1 (±3)', gDef.n, 15, 3);
}
