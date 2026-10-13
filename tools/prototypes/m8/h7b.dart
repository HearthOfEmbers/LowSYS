// H7 extras: the throughput that keeps the lower bed near 87 % of flood; F21 at the range top (s = 0.8).
import 'h7.dart' as h7;
import 'pk.dart';

void main() {
  for (final k in [1.05, 1.10, 1.15, 1.20]) {
    final c = h7.mk(dia: 1.0, k: k);
    c.solve(l0kmolh: 100 * k, qrKW: 1300 * k, dGuessKmolh: 50 * k);
    h7.report(c, 'healthy k $k');
  }
  for (final bedI in [0, 1]) {
    final c = h7.mk(dia: 1.0, malBed: bedI, malF: 0.6 * 0.8);
    c.solve(l0kmolh: 100, qrKW: 1300);
    h7.report(c, 'F21 bed ${bedI + 1} s 0.8');
  }
  final c = h7.mk(dia: 1.0, k: 1.25);
  c.solve(l0kmolh: 125, qrKW: 1625, dGuessKmolh: 62.5);
  print('near_flood segment 18: hetp ${f4(c.seg[18].hetp, 4)} hL ${f4(c.seg[18].hL, 5)}; base hL18 below');
  final b = h7.mk(dia: 1.0);
  b.solve(l0kmolh: 100, qrKW: 1300);
  print('base segment 18: hetp ${f4(b.seg[18].hetp, 4)} hL ${f4(b.seg[18].hL, 5)}');
}
