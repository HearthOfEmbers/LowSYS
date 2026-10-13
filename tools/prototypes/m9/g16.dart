// G16 "Crude cut points and gaps": searches lever combinations from the default (Tier 2, COT 345, PA 5 MW).
// Specs: kero D86 95 % <= 235 °C, diesel–kero gap >= 0 K, residue yield <= 47.0 vol % (M9 replacement of the undefined
// "residue D86-equivalent IBP >= 340 °C"); residue TBP 5 % is reported as well.
import 'column.dart';
import 'crude.dart';

void run(String tag, {double pa = 5, double kero = 11.7, double dsl = 16.7, double ago = 5.3, double ss2 = 300, double ss1 = 300, double cot = 345, double bot = 2000, double topT = 125}) {
  final c = Crude()
    ..paDuty = pa * 1e6
    ..drawPct = [kero, dsl, ago]
    ..steamSS = [ss1, ss2, 300]
    ..cotC = cot
    ..steamBot = bot
    ..tTopSpC = topT;
  c.solve();
  final d = c.d86All();
  final k95 = d[1][7], gap = d[2][1] - d[1][7];
  final ok = k95 <= 235 && gap >= 0 && c.yRes <= 47.0;
  print('${ok ? "MEETS" : "     "} $tag: K95 ${f(k95, 1)} D-K ${f(gap, 1)} K-N ${f(d[1][1] - d[0][7], 1)} A-D ${f(d[3][1] - d[2][7], 1)} res ${f(c.yRes)} '
      'resTBP5 ${f(c.resTbp(5), 1)} naph ${f(c.yNaph)} ovf ${f(c.overflash)} Qc ${f(c.qc / 1e6, 2)} flood ${f(100 * c.flood.reduce((a, b) => a > b ? a : b), 1)} '
      'D95 ${f(d[2][7], 1)} N95 ${f(d[0][7], 1)} t ${f(c.settle / 3600, 2)}h');
}

void main(List<String> args) {
  run('default');
  run('PA 3', pa: 3);
  run('PA 2', pa: 2);
  run('PA 3, SS2 1000', pa: 3, ss2: 1000);
  run('PA 2, SS2 800', pa: 2, ss2: 800);
  run('SS2 1000', ss2: 1000);
  run('kero 10.7 dsl 17.7', kero: 10.7, dsl: 17.7);
  run('PA 3, kero 10.7, dsl 17.7', pa: 3, kero: 10.7, dsl: 17.7);
  run('PA 3, kero 10.7, dsl 17.7, SS2 800', pa: 3, kero: 10.7, dsl: 17.7, ss2: 800);
  run('PA 4, kero 10.7, dsl 17.7, SS2 1000', pa: 4, kero: 10.7, dsl: 17.7, ss2: 1000);
  run('COT 355, PA 3, SS2 800', cot: 355, pa: 3, ss2: 800);
}
