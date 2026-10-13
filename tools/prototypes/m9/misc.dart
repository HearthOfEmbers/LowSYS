// Small checks quoted in the docs: drum bubble point, feed rates, Cp_V and enthalpy-reference numbers.
import 'column.dart';
import 'crude.dart';

void main() {
  final c = Crude()..solve();
  final y1 = c.naphthaX;
  print('naphtha bubble T at 1.4 bar ${f(bubbleT(y1, 1.4e5, 350) - 273.15, 2)} °C; at 1.6 bar ${f(bubbleT(y1, 1.6e5, 350) - 273.15, 2)}');
  print('feed ${f(c.fF * 3.6, 2)} kmol/h, ${f(c.massKgh(c.fF, c.z) / 1000, 3)} t/h; steam bottom ${f(c.kgh2mol(2000) * 3.6, 2)} kmol/h, SS ${f(c.kgh2mol(300) * 3.6, 3)}');
  print('drum water ${f((c.kgh2mol(2900)) * 3.6, 2)} kmol/h');
  var hmin = 1e9, hmax = -1e9;
  for (var a = 0; a < ns; a++) {
    final d = c.hv[a] - c.hl[a];
    if (d < hmin) hmin = d;
    if (d > hmax) hmax = d;
  }
  print('H-h range at default (T_b ref): ${f(hmin / 1000, 1)} .. ${f(hmax / 1000, 1)} kJ/mol');
  // same with the 298.15 K reference (v1.0) at the converged state
  var wmin = 1e9;
  for (var a = 0; a < ns; a++) {
    var hv0 = 0.0, hl0 = 0.0;
    for (var i = 0; i < 9; i++) {
      hv0 += c.yy[a][i] * pcs[i].hVwatson(c.t[a]);
      hl0 += c.x[a][i] * pcs[i].hL0(c.t[a]);
    }
    if (hv0 - hl0 < wmin) wmin = hv0 - hl0;
  }
  print('H-h minimum at the same state with the v1.0 reference and Watson path: ${f(wmin / 1000, 1)} kJ/mol');
  // loop gain estimate on stage 30
  final a = 29;
  final s = c.steamUp[a], v = c.v[a], l = c.l[a - 1];
  var cp = 0.0, lam = 0.0, dl = 0.0, sk = 0.0;
  for (var i = 0; i < 9; i++) {
    cp += c.x[a][i] * (pcs[i].cp0 + pcs[i].dcp * (c.t[a] - t0));
    lam += c.yy[a][i] * (pcs[i].hV(c.t[a]) - pcs[i].hL(c.t[a]));
    final kx = c.x[a][i] * pcs[i].psat(c.t[a]);
    sk += kx;
    dl += kx * pcs[i].dlnPsat(c.t[a]);
  }
  final g = (s / (v * (v + s))) / (dl / sk) * l * cp / lam;
  print('stage 30: S ${f(s * 3.6, 1)} V ${f(v * 3.6, 1)} L29 ${f(l * 3.6, 1)} kmol/h, Cp ${f(cp, 0)}, lambda ${f(lam / 1000, 1)} kJ/mol, dlnP/dT ${f(dl / sk, 4)} -> loop gain ${f(g, 2)}');
  print('Tc PC1 ${f(pcs[0].tc - 273.15, 1)} PC2 ${f(pcs[1].tc - 273.15, 1)} °C');
  print('PA return T ${f(c.paReturnT - 273.15, 2)}  PA flow ${f(c.pPA * 3.6, 1)} kmol/h; max duty at full flow ${f(c.pPA * (c.hl[15] - hLmix(c.x[15], 393.15)) / 1e6, 2)} MW');
  print('stripper vapour returns ${[0, 1, 2].map((k) => f(c.v[c.s1(k)] * 3.6, 2)).join("/")}');
  print('residue TBP 5/50 ${f(c.resTbp(5), 1)} / ${f(c.resTbp(50), 1)}');
}
