// VC-13 unit-level values: Robbins, Kister–Gill, flood flux, holdup, wetting, HETP, Lewis, maldistribution.
import 'dart:math';
import 'pk.dart';

void main() {
  print('--- Robbins check (fluids example) ---');
  final r = robbinsPaPerM(12.2, 2.03, 1000, 1.1853, 1, 24);
  print('Pa/m ${f4(r, 4)}  over 2 m ${f4(2 * r, 3)}');
  print('--- Kister–Gill flood dP ---');
  for (final fp in [20.0, 27.0, 34.0, 56.0, 65.0]) {
    print('Fp $fp  ${f4(0.115 * pow(fp, 0.7), 4)} inH2O/ft  ${f4(kgFloodPaPerM(fp), 2)} Pa/m');
  }
  print('--- B-T load (G 3.132, L 2.088, rhoL 800, rhoV 2.9, mu 0.27) ---');
  for (final pk in packings) {
    final dp = robbinsPaPerM(2.088, 3.132, 800, 2.9, 0.27, pk.fp);
    final gfl = floodGp(2.088 / 3.132, 800, 2.9, 0.27, pk.fp);
    final hls = holdupS(0.27e-3, pk.a, 2.088 / 800, 800);
    final wet = ondaWet(2.088, pk.a, 800, 0.27e-3, 0.020, pk.sigmaC);
    print('${pk.id.padRight(11)} dP ${f4(dp, 2)} Pa/m  flood ${f4(kgFloodPaPerM(pk.fp), 1)}  Gfl ${f4(gfl, 4)}  phi ${f4(100 * 3.132 / gfl, 2)} %'
        '  hLs ${f4(hls, 5)}  hL ${f4(hls * holdupFactor(3.132 / gfl), 5)}  aw/a ${f4(wet, 4)}');
  }
  print('HETP rule structured: 250 -> ${f4(hetpRuleStructured(250), 4)} m, 500 -> ${f4(hetpRuleStructured(500), 4)} m');
  print('--- struct250 at B-T load: dP vs phi (fixed L/G) ---');
  final gfl = floodGp(2.088 / 3.132, 800, 2.9, 0.27, 20);
  for (final ph in [0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05]) {
    final gp = ph * gfl;
    final dp = robbinsPaPerM(gp * 2.088 / 3.132, gp, 800, 2.9, 0.27, 20);
    final hls = holdupS(0.27e-3, 250, gp * 2.088 / 3.132 / 800, 800);
    print('phi $ph  G ${f4(gp, 4)}  dP ${f4(dp, 2)} Pa/m  hL ${f4(hls * holdupFactor(ph), 5)}  g ${f4(gLoad(ph), 4)}');
  }
  print('--- wetting: struct250, B-T props, L\' scan (ref 2.088) ---');
  final wref = ondaWet(2.088, 250, 800, 0.27e-3, 0.020, 0.075);
  for (final lp in [0.25, 0.5, 1.0, 2.088, 4.0]) {
    final w = ondaWet(lp, 250, 800, 0.27e-3, 0.020, 0.075);
    print('L\' $lp  aw/a ${f4(w, 5)}  HETP factor max(1, ref/aw) ${f4(max(1.0, wref / w), 5)}');
  }
  print('--- Lewis ---');
  for (final c in [[0.5, 0.5], [1.5, 0.7], [2.0, 0.5]]) {
    print('lam ${c[0]} Emv ${c[1]} -> EO ${f4(lewisEO(c[1], c[0]), 5)}');
  }
  print('--- maldistribution table ---');
  for (final c in [
    [1.0, 10, 0.2], [1.0, 10, 0.4], [1.0, 20, 0.2], [1.0, 20, 0.4], [1.5, 10, 0.4], [0.7, 10, 0.4], [1.0, 5, 0.4], [1.2, 20, 0.3],
    [1.0, 9, 0.3], [1.0, 9, 0.6], [1.0, 8.5, 0.4]
  ]) {
    final s = c[0].toDouble(), n = c[1].toDouble(), fr = c[2].toDouble();
    final m = maldistribution(s, n, fr);
    print('S $s n $n f $fr  PhiK ${f4(m.phiU, 5)} Phimal ${f4(m.phiMal, 5)} neff ${f4(m.nEff, 3)} E ${f4(m.eMal, 4)} Emv ${f4(lewisEMV(m.eMal, s), 4)}');
  }
}
