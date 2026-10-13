// VC-15.1–15.3 unit values and the vapour-enthalpy comparison behind the M9 enthalpy rule.
import 'dart:math' as m;
import 'crude.dart';

void main() {
  print('VC-15.1 pseudo-components');
  print('PC   vf      Tb°C    SG      MW      Tc K    Pc bar  omega   dHb kJ  rho     Cp0     dCp    CpV(Tb) A      B');
  var sgNum = 0.0, nTot = 0.0, mTot = 0.0;
  for (final c in pcs) {
    print('${c.id}  ${f(c.vf, 4)}  ${f(c.tb - 273.15, 2)}  ${f(c.sg, 4)}  ${f(c.mw, 2)}  ${f(c.tc, 2)}  ${f(c.pc, 3)}  '
        '${f(c.om, 4)}  ${f(c.dhb / 1000, 3)}  ${f(c.rho, 1)}  ${f(c.cp0, 2)}  ${f(c.dcp, 4)}  '
        '${f(c.cpvA + c.cpvB * c.tb, 1)}  ${f(c.cpvA, 3)}  ${f(c.cpvB, 5)}  Psat(Tb)/101325-1 ${(c.psat(c.tb) / 101325 - 1).toStringAsExponential(2)}');
    sgNum += c.vf * c.sg;
    nTot += c.vf / c.vStd;
    mTot += c.vf / c.vStd * c.mw;
  }
  final sgB = sgNum; // volume-average SG
  print('bulk SG ${f(sgB, 4)} API ${f(141.5 / sgB - 131.5, 2)} mean MW ${f(mTot / nTot, 2)}');
  final z = crudeZ();
  print('z (mol) ${z.map((v) => f(v, 4)).join(' ')}');
  for (final i in [0, 4, 8]) {
    for (final tc in [200.0, 360.0]) {
      print('Psat ${pcs[i].id} ${tc}C = ${pcs[i].psat(tc + 273.15).toStringAsExponential(5)} Pa');
    }
  }
  print('\nVapour enthalpy, PC1 and PC2 (kJ/mol rel. liquid at 25 °C): M9 rule vs v1.0 §3.3 Watson path');
  for (final i in [0, 1]) {
    for (final tc in [100.0, 150.0, 200.0, 230.0, 240.0, 250.0, 280.0, 300.0, 350.0]) {
      final t = tc + 273.15;
      print('  ${pcs[i].id} ${f(tc, 0)} °C: new ${f((pcs[i].hV(t) + pcs[i].hL0(pcs[i].tb)) / 1000, 2)}  watson ${f(pcs[i].hVwatson(t) / 1000, 2)}');
    }
  }
  print('water vapour h (kJ/mol): 100 ${f((water.hV(373.15) + water.hL0(373.15)) / 1000, 3)}  200 ${f((water.hV(473.15) + water.hL0(373.15)) / 1000, 3)}  '
      '350 ${f((water.hV(623.15) + water.hL0(373.15)) / 1000, 3)}; watson path 200 ${f(water.hVwatson(473.15) / 1000, 3)} 350 ${f(water.hVwatson(623.15) / 1000, 3)}');
  print('water Psat 100 °C ${f(water.psat(373.15), 1)} Pa');
  // ideal-gas Cp check (implied by the M9 rule) vs Watson path at 250 °C for PC3, PC5
  for (final i in [2, 4, 6]) {
    final t = 523.15;
    final cw = (pcs[i].hVwatson(t + 0.5) - pcs[i].hVwatson(t - 0.5));
    print('  ${pcs[i].id} CpV at 250 °C: new ${f(pcs[i].cpvA + pcs[i].cpvB * t, 1)}  watson-implied ${f(cw, 1)} J/mol/K');
  }

  print('\nVC-15.2 Daubert');
  final d = d86([150, 165, 180, 200, 220, 240, 255]);
  print('D86 0,5,10,30,50,70,90,95,100: ${d.map((v) => f(v, 2)).join(' ')}');

  print('\nVC-15.3 ideal cuts at 165/240/340/370');
  final cuts = [
    ['Naphtha', 20.0, 165.0],
    ['Kerosene', 165.0, 240.0],
    ['Diesel', 240.0, 340.0],
    ['AGO', 340.0, 370.0],
    ['Residue', 370.0, 760.0]
  ];
  final d5 = <double>[], d95 = <double>[];
  for (final c in cuts) {
    final lo = c[1] as double, hi = c[2] as double;
    final y = volAt(hi) - volAt(lo);
    final dd = idealCutD86(lo, hi);
    d5.add(dd[1]);
    d95.add(dd[7]);
    print('${c[0]} yield ${f(y, 2)} D86 5 ${f(dd[1], 1)} 50 ${f(dd[4], 1)} 95 ${f(dd[7], 1)}  (0 ${f(dd[0], 1)} 100 ${f(dd[8], 1)})');
  }
  print('gaps K-N ${f(d5[1] - d95[0], 1)} D-K ${f(d5[2] - d95[1], 1)} A-D ${f(d5[3] - d95[2], 1)}');
  // residue TBP 5 % of the ideal 370+ cut
  final v370 = volAt(370);
  print('ideal residue TBP 5 % ${f(tbpAt(v370 + 0.05 * (100 - v370)), 1)} °C');
  // how pseudo-components represent the ideal cuts: pseudo shares in each ideal cut
  print('\nIdeal cuts represented by pseudo-components (lumped, trim 1.0): D86 5/95');
  for (final c in cuts.take(4)) {
    final lo = c[1] as double, hi = c[2] as double;
    final x = List<double>.filled(9, 0);
    for (var i = 0; i < 9; i++) {
      final a = m.max(lo, pcs[i].tlo), b = m.min(hi, pcs[i].thi);
      if (b > a) x[i] = (volAt(b) - volAt(a)) / pcs[i].vStd;
    }
    final dd = productD86(x);
    print('${c[0]}: 5 ${f(dd[1], 1)} 95 ${f(dd[7], 1)}');
  }
}
