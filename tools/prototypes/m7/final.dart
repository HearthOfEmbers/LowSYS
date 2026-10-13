// Digits for the doc tables (VC-9.6–9.8, §H H6). Run: dart run final.dart
import 'hc.dart';
import 'refs.dart' show debut, deprop, solve, imp, heavyD, lightB;

void main() {
  for (final p in [debut, deprop]) {
    final c = solve(p, 2);
    print('${p.id}: QR ${c.qr.toStringAsFixed(1)} W QC ${c.qc.toStringAsFixed(1)} W D ${kmolh(c.d).toStringAsFixed(4)}');
    final cq = solve(p, 2, qr: double.parse((c.qr / 1e3).toStringAsFixed(2)) * 1e3);
    print('   at the duty rounded to 0.01 kW: D ${kmolh(cq.d).toStringAsFixed(4)} rLK ${f4(cq.recD(p.lk))} rHK ${f4(cq.recB(p.hk))}');
  }
  final b = solve(debut, 2);
  final q0 = b.qr;
  print('debut base TI-101 ${f4(b.t[1] - 273.15, 2)} TI-133 ${f4(b.t[33] - 273.15, 2)} tray 16 ${f4(b.t[16] - 273.15, 2)}');
  final z = [for (var i = 0; i < 6; i++) debut.z[i] + 0.75 * [-0.02, -0.04, 0.02, 0.04, 0.0, 0.0][i]];
  final c7 = solve(debut, 2, z: z, qr: q0);
  print('F07 s 0.75: D ${f4(kmolh(c7.d), 2)} ${imp(c7, debut)} TI-101 ${f4(c7.t[1] - 273.15, 2)} tray 16 ${f4(c7.t[16] - 273.15, 2)} TB ${f4(c7.t[33] - 273.15, 2)}');
  final cap = (1 - 0.585) * 2 * debut.l0;
  final c12 = solve(debut, 2, l0: cap, qr: q0);
  print('F12 s 0.585 cap ${f4(cap, 2)}: D ${f4(kmolh(c12.d), 2)} ${imp(c12, debut)} TI-101 ${f4(c12.t[1] - 273.15, 2)} QC ${f4(c12.qc / 1e3, 1)} kW');
  final st = solve(debut, 2, fF: molps(108), qr: q0 * 1.08, d: debut.d * 1.08);
  print('F20 + planning: D ${f4(kmolh(st.d), 2)} ${imp(st, debut)} TI-101 ${f4(st.t[1] - 273.15, 2)} QC ${f4(st.qc / 1e3, 1)} kW');
  final ok = solve(debut, 2, fF: molps(108), l0: debut.l0 * 1.08, qr: q0 * 1.08, d: debut.d * 1.08);
  print('planning healthy: D ${f4(kmolh(ok.d), 3)} QC ${f4(ok.qc / 1e3, 1)} kW ${imp(ok, debut)} (heavyD ${heavyD(ok, 3)} lightB ${lightB(ok, 2)})');
}
