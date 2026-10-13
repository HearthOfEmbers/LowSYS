// Lever scans around the default (each case solved cold): dart run scan.dart cot|steam|ptop|...
import 'column.dart';
import 'crude.dart';

String row(Crude c) {
  final d = c.d86All();
  return 'ovf ${f(c.overflash)} res ${f(c.yRes)} naph ${f(c.yNaph)} AGO ${f(c.yProd(2))} | FZ ${f(c.t[25] - 273.15, 1)} bot ${f(c.t[29] - 273.15, 1)} '
      'top ${f(c.t[0] - 273.15, 1)} Qc ${f(c.qc / 1e6, 2)} L0 ${f(c.l0 * 3.6, 0)} | 95%: N ${f(d[0][7], 1)} K ${f(d[1][7], 1)} D ${f(d[2][7], 1)} '
      '| gaps ${f(d[1][1] - d[0][7], 1)} ${f(d[2][1] - d[1][7], 1)} ${f(d[3][1] - d[2][7], 1)} | resTBP5 ${f(c.resTbp(5), 1)} '
      'dry ${c.sd.asMap().entries.map((e) => (c.drawReq[e.key] - e.value) > 1e-6 ? "D${e.key + 1}" : "").join()} '
      'L25 ${f(c.l[24] * 3.6, 1)} L21 ${f(c.l[20] * 3.6, 1)} flood ${f(100 * c.flood.reduce((a, b) => a > b ? a : b), 1)} '
      'PA ${f(c.qPA / 1e6, 2)}MW Tr ${f(c.paReturnT - 273.15, 0)} pk ${c.pkAct.map((e) => f(e * 3.6, 1)).join("/")} t ${f(c.settle / 3600, 2)}h';
}

void run(String tag, void Function(Crude) set) {
  final c = Crude();
  set(c);
  c.solve();
  print('$tag: ${row(c)}');
}

void main(List<String> args) {
  final what = args.isEmpty ? 'cot' : args[0];
  if (what == 'cot') {
    for (final cot in [335.0, 340.0, 345.0, 350.0, 355.0, 360.0, 365.0]) run('COT $cot', (c) => c.cotC = cot);
  } else if (what == 'steam') {
    for (final s in [0.0, 1000.0, 2000.0, 3000.0, 5000.0]) run('bottom steam $s', (c) => c.steamBot = s);
  } else if (what == 'ptop') {
    for (final p in [1.2, 1.6, 2.0, 2.5]) run('Ptop $p', (c) => c.pTop = p * 1e5);
  } else if (what == 'pa') {
    for (final q in [0.0, 3.0, 6.0, 9.0, 12.0]) run('PA $q MW', (c) => c.paDuty = q * 1e6);
  } else if (what == 'top') {
    for (final t in [110.0, 120.0, 125.0, 130.0, 140.0]) run('topT $t', (c) => c.tTopSpC = t);
  } else if (what == 'kero') {
    for (final k in [8.0, 9.7, 11.7, 13.7]) run('kero $k', (c) => c.drawPct[0] = k);
  } else if (what == 'cot345') {
    for (final cot in [345.0, 335.0, 330.0, 325.0]) run('COT $cot', (c) => c.cotC = cot);
    run('COT 345 steam 0', (c) => c..cotC = 345..steamBot = 0);
    run('COT 345 PA 0', (c) => c..cotC = 345..paDuty = 0);
  } else if (what == 'grid') {
    for (final cot in [345.0, 350.0]) {
      for (final q in [4.0, 5.0, 6.0]) run('COT $cot PA $q', (c) => c..cotC = cot..paDuty = q * 1e6);
    }
  } else if (what == 'ss') {
    for (final s in [0.0, 300.0, 600.0, 1000.0]) run('SS steam $s', (c) => c.steamSS = [s, s, s]);
  }
}

