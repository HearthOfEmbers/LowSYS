// M9 coder tests: VC-15.1 pseudo-components and enthalpy rule, VC-15.2 Daubert, VC-15.3 ideal and lumped cuts.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

void main() {
  final th = CrudeThermo();
  final prod = CrudeProducts(th);

  test('VC-15.1 table', () {
    // PC: T_b C, SG, MW, Tc K, Pc bar, omega, dHvap kJ/mol, rho, Cp0, dCp, volfrac
    const ref = [
      [0.0833, 61.7, 0.7098, 82.5, 515.8, 36.21, 0.2227, 27.97, 709.1, 176.5, 0.373],
      [0.0936, 119.6, 0.7486, 111.0, 577.5, 28.32, 0.3130, 33.39, 747.8, 231.4, 0.492],
      [0.0769, 175.0, 0.7823, 141.8, 634.1, 23.12, 0.4052, 38.81, 781.5, 289.0, 0.618],
      [0.0795, 225.8, 0.8108, 173.1, 684.2, 19.59, 0.4957, 44.04, 810.0, 345.9, 0.743],
      [0.0833, 275.0, 0.8366, 206.2, 731.3, 16.95, 0.5899, 49.38, 835.7, 404.5, 0.872],
      [0.0833, 325.0, 0.8613, 242.5, 778.0, 14.82, 0.6937, 55.16, 860.4, 467.3, 1.012],
      [0.1333, 386.7, 0.8899, 290.9, 833.9, 12.74, 0.8352, 62.88, 889.0, 549.1, 1.195],
      [0.1524, 471.7, 0.9266, 364.4, 908.7, 10.58, 1.0618, 74.95, 925.7, 669.1, 1.466],
      [0.2143, 613.9, 0.9822, 504.1, 1028.5, 8.08, 1.5647, 100.96, 981.2, 886.6, 1.963],
    ];
    for (var i = 0; i < 9; i++) {
      final r = ref[i];
      final c = th.pcs[i].comp, inf = th.pcs[i].info;
      expect(inf.volFrac, closeTo(r[0], 1e-4), reason: 'vf $i');
      expect(c.tb - 273.15, closeTo(r[1], 0.05), reason: 'tb $i');
      expect(inf.sg, closeTo(r[2], 1e-4), reason: 'sg $i');
      expect(c.mw, closeTo(r[3], 0.05), reason: 'mw $i');
      expect(c.tc, closeTo(r[4], 0.05), reason: 'tc $i');
      expect(c.pc / 1e5, closeTo(r[5], 0.005), reason: 'pc $i');
      expect(c.omega, closeTo(r[6], 1e-4), reason: 'om $i');
      expect(c.dHvapTb / 1000, closeTo(r[7], 0.01), reason: 'dh $i');
      expect(c.rhoRef, closeTo(r[8], 0.1), reason: 'rho $i');
      expect(c.cp0, closeTo(r[9], 0.05), reason: 'cp0 $i');
      expect(c.dCp, closeTo(r[10], 1e-3), reason: 'dcp $i');
      // omega definition: Psat(Tb) = 1 atm
      expect(math.exp(th.lnPsat(i, c.tb)) / 101325, closeTo(1, 1e-6));
    }
    final z = th.feedZ();
    var sg = 0.0, mw = 0.0;
    for (var i = 0; i < 9; i++) {
      sg += th.volFrac[i] * th.pcs[i].info.sg;
      mw += z[i] * th.mw[i];
    }
    expect(sg, closeTo(0.8656, 1e-4));
    expect(mw, closeTo(216.9, 0.1));
    expect(th.pcs[0].info.cpVA, closeTo(37.069, 1e-3 * 37.069));
    expect(th.pcs[4].info.cpVB, closeTo(0.76203, 1e-3 * 0.76203));
    expect(th.pcs[8].info.cpVA, closeTo(207.707, 1e-3 * 207.707));
    // spot Psat
    expect(th.psat(0, 473.15), closeTo(1.9843e6, 1.9843e6 * 1e-4));
    expect(th.psat(4, 633.15), closeTo(4.6417e5, 4.6417e5 * 1e-4));
    expect(th.psat(8, 633.15), closeTo(91.577, 91.577 * 1e-4));
  });

  test('VC-15.1 enthalpy rule', () {
    for (var i = 0; i < 9; i++) {
      expect(th.hLi(i, th.tb[i]), closeTo(0, 1e-9));
      expect(th.hVi(i, th.tb[i]), closeTo(th.dhb[i], 1e-9));
      var prev = th.hVi(i, 300);
      for (var t = 310.0; t <= 700; t += 10) {
        final h = th.hVi(i, t);
        expect(h, greaterThan(prev));
        prev = h;
      }
    }
    expect(th.hVwater(473.15) - th.hVwater(373.15), closeTo(3460, 1));
    // E.3 #4 quotes the M9 vapour enthalpy on the 298 K basis (add h_L,0(T_b)): 65.29 / 67.30 kJ/mol at 240 / 250 C
    double h298(double t) => (th.hVi(0, t) + th.cp0[0] * (th.tb[0] - 298.15) + 0.5 * th.dcp[0] * math.pow(th.tb[0] - 298.15, 2)) / 1000;
    expect(h298(513.15), closeTo(65.29, 0.05));
    expect(h298(523.15), closeTo(67.30, 0.05));
  });

  test('VC-15.2 Daubert', () {
    final d = CrudeProducts.d86([for (final c in [150, 165, 180, 200, 220, 240, 255]) c + 273.15]);
    const ref = [173.46, 175.84, 178.22, 184.23, 196.45, 210.62, 225.28, 232.60, 239.92];
    for (var i = 0; i < 9; i++) {
      expect(d[i] - 273.15, closeTo(ref[i], 0.01), reason: 'pt $i');
    }
  });

  test('VC-15.3 ideal cuts', () {
    const cuts = [165.0, 240.0, 340.0, 370.0];
    final a = th.assay;
    final names = ['naph', 'kero', 'diesel', 'ago'];
    const y = [20.00, 11.67, 16.67, 5.30];
    const d5 = [60.3, 183.7, 259.9, 339.7];
    const d95 = [146.9, 223.9, 316.9, 353.1];
    final bounds = [20.0, ...cuts];
    final d86s = <List<double>>[];
    for (var k = 0; k < 4; k++) {
      final lo = bounds[k], hi = cuts[k];
      expect(a.volAt(hi) - a.volAt(lo), closeTo(y[k], 0.01), reason: names[k]);
      final d = prod.idealCut(lo + 273.15, hi + 273.15);
      d86s.add(d);
      expect(d[1] - 273.15, closeTo(d5[k], 0.1), reason: '${names[k]} 5');
      expect(d[7] - 273.15, closeTo(d95[k], 0.1), reason: '${names[k]} 95');
    }
    expect(d86s[1][1] - d86s[0][7], closeTo(36.9, 0.1));
    expect(d86s[2][1] - d86s[1][7], closeTo(36.0, 0.1));
    expect(d86s[3][1] - d86s[2][7], closeTo(22.8, 0.1));
  });

  test('VC-15.3 lumped cuts', () {
    // each cut as its share of each pseudo-component
    final cuts = [20.0, 165.0, 240.0, 340.0, 370.0];
    const d5 = [59.1, 175.6, 246.4, 324.9];
    const d95 = [158.2, 231.3, 324.6, 396.5];
    final gaps = <double>[];
    double? prev95;
    for (var k = 0; k < 4; k++) {
      final x = Float64List(9);
      var s = 0.0;
      for (var i = 0; i < 9; i++) {
        final lo = math.max(cuts[k], th.tLo[i] - 273.15), hi = math.min(cuts[k + 1], th.tHi[i] - 273.15);
        final pcLo = th.tLo[i] - 273.15, pcHi = th.tHi[i] - 273.15;
        // share of the pseudo-component's cut range [pcLo, pcHi] that lies in the cut, by volume
        final vA = th.assay.volAt(math.max(lo, pcLo)), vB = th.assay.volAt(math.min(hi, pcHi));
        final v = hi > lo ? (vB - vA) / 100 : 0.0; // volume of crude in this cut and this PC (vol fraction)
        x[i] = v / th.vStd[i];
        s += x[i];
      }
      for (var i = 0; i < 9; i++) {
        x[i] /= s;
      }
      final (a5, _, a95) = prod.d86Key(x, 0);
      expect(a5 - 273.15, closeTo(d5[k], 0.15), reason: 'lumped 5 k$k');
      expect(a95 - 273.15, closeTo(d95[k], 0.15), reason: 'lumped 95 k$k');
      if (prev95 != null) gaps.add(a5 - prev95);
      prev95 = a95;
    }
    expect(gaps[0], closeTo(17.4, 0.15));
    expect(gaps[1], closeTo(15.1, 0.15));
    expect(gaps[2], closeTo(0.3, 0.15));
  });
}
