// Engine-free regression of the M2 reference calculators against the
// VALIDATION.md VC-12 / VC-17 numbers (`reference_main_m2.dart` prints the
// full comparison).
library;

import 'package:test/test.dart';

import 'reference/tray_hydraulics_reference.dart';
import 'reference/units_reference.dart';
import 'reference/validation_expectations_m2.dart';

void main() {
  const kmolh = 1000 / 3600;
  test('reference: VC-12.1 geometry', () {
    const gm = TrayGeom();
    expect(gm.aT, closeTo(vc121.aT, 1e-4));
    expect(gm.aA, closeTo(vc121.aA, 1e-4));
    expect(gm.aN, closeTo(vc121.aN, 1e-4));
    expect(gm.lW, closeTo(vc121.lW, 1e-4));
  });
  test('reference: VC-12.2 spot values', () {
    for (final (ts, f, c) in vc122Csb) {
      expect(lygerosMagoulasCsb(ts, f), closeTo(c, 1e-4));
    }
    expect(bennettAlphaE(0.06), closeTo(vc122Bennett.alphaE, 1e-4));
    expect(bennettC(0.05), closeTo(vc122Bennett.c, 1e-4));
    for (final (f, p, psi) in vc122Psi) {
      expect(psiEq(f, p), closeTo(psi, 1e-4 * psi));
    }
    for (final (s, w) in vc122Weep) {
      expect(weepFraction(s), closeTo(w, 1e-3));
    }
  });
  test('reference: VC-12.3 design point reconstructs within the doc tolerances',
      () {
    // v1.0 table at TS 0.6 (the v1.1 default is 0.9)
    const gm06 = TrayGeom(ts: 0.6);
    final t1 = sieveTray(
        150 * kmolh,
        100 * kmolh,
        const Fluid(
            mwL: 0.95 * 78.11 + 0.05 * 92.14, mwV: 0.97 * 78.11 + 0.03 * 92.14),
        gm: gm06);
    final t15 = sieveTray(
        150 * kmolh,
        200 * kmolh,
        const Fluid(
            mwL: 0.14 * 78.11 + 0.86 * 92.14, mwV: 0.25 * 78.11 + 0.75 * 92.14),
        gm: gm06);
    // v1.1 default (TS 0.9): only jet flood changes
    final b20 = sieveTray(
        150 * kmolh,
        200 * kmolh,
        const Fluid(
            mwL: 0.02 * 78.11 + 0.98 * 92.14, mwV: 0.05 * 78.11 + 0.95 * 92.14),
        hNormBelow: 0);
    expect(100 * b20.phi, closeTo(vc123.maxFloodPct, 2));
    expect(b20.dp, closeTo(827, 0.05 * 827));
    expect(t1.phi, closeTo(0.666, 0.02));
    expect(t1.dp, closeTo(645, 0.05 * 645));
    expect(1000 * t1.hCl, closeTo(21.1, 1.0));
    expect(t15.phi, closeTo(0.804, 0.02));
    expect(t15.dp, closeTo(798, 0.05 * 798));
    expect(t15.hDc, closeTo(0.131, 0.013));
    expect((9 * t1.dp + 11 * t15.dp) / 1000, closeTo(14.68, 0.05 * 14.68));
  });
  test('reference: VC-17', () {
    expect(paToPsia(101325), closeTo(14.6959, 1e-4));
    expect(molsToLbmolh(1), closeTo(7.93664, 1e-5));
    expect(wToMmbtuh(1e6), closeTo(3.41214, 1e-5));
    expect(m3hToBblD(132.5), closeTo(20001.6, 0.1));
    expect(kgm3ToLbft3(800), closeTo(49.942, 1e-3));
  });
}
