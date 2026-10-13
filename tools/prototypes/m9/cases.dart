// VC-15.4 direction checks, F24–F27 steady states and transients from the default, the H8 rows.
// dart run cases.dart [steady|transient|f27]
import 'column.dart';
import 'crude.dart';

String kpi(Crude c) {
  final d = c.d86All();
  return 'res ${f(c.yRes)} naph ${f(c.yNaph)} kero ${f(c.yProd(0))} dsl ${f(c.yProd(1))} AGO ${f(c.yProd(2))} ovf ${f(c.overflash)} | '
      'top ${f(c.t[0] - 273.15, 1)} FZ ${f(c.t[25] - 273.15, 1)} bot ${f(c.t[29] - 273.15, 1)} Qc ${f(c.qc / 1e6, 2)} L0 ${f(c.l0 * 3.6, 0)} '
      'PA ${f(c.qPA / 1e6, 2)} | 5/95 N ${f(d[0][1], 1)}/${f(d[0][7], 1)} K ${f(d[1][1], 1)}/${f(d[1][7], 1)} D ${f(d[2][1], 1)}/${f(d[2][7], 1)} '
      'A ${f(d[3][1], 1)}/${f(d[3][7], 1)} | gaps ${f(d[1][1] - d[0][7], 1)} ${f(d[2][1] - d[1][7], 1)} ${f(d[3][1] - d[2][7], 1)} '
      'resTBP5 ${f(c.resTbp(5), 1)} | flood ${f(100 * c.flood.reduce((a, b) => a > b ? a : b), 1)} '
      'dry ${[0, 1, 2].where((k) => c.drawReq[k] - c.sd[k] > 1e-4 || c.pkAct[k] < c.pk[k] * 0.999).map((k) => "D${k + 1}").join()}';
}

Crude base() {
  final c = Crude();
  c.solve();
  return c;
}

void steady(String tag, void Function(Crude) set) {
  final c = base();
  set(c);
  c.solve(cold: false);
  print('$tag (${f(c.settle / 3600, 2)} h): ${kpi(c)}');
}

void transient(String tag, void Function(Crude) set, {List<double> at = const [300, 600, 1200, 1800, 3600, 7200]}) {
  final c = base();
  final b = [c.t[0], c.t[25], c.t[29], c.qc, c.yRes, c.overflash, c.l0];
  print('$tag base: top ${f(b[0] - 273.15, 2)} FZ ${f(b[1] - 273.15, 2)} bot ${f(b[2] - 273.15, 2)} Qc ${f(b[3] / 1e6, 3)} res ${f(b[4], 2)} ovf ${f(b[5], 2)}');
  set(c);
  c.setSteam();
  var tPrev = 0.0;
  var maxTop = -1e9;
  for (final t in at) {
    final steps = (t - tPrev).round();
    for (var n = 0; n < steps; n++) {
      c.step(1.0);
      if (c.t[0] > maxTop) maxTop = c.t[0];
    }
    tPrev = t;
    c.props();
    print('   t ${f(t / 60, 0)} min: dTop ${f(c.t[0] - b[0], 2)} (max ${f(maxTop - b[0], 2)}) dFZ ${f(c.t[25] - b[1], 2)} dBot ${f(c.t[29] - b[2], 2)} '
        'Qc ${f(c.qc / 1e6, 2)} (${f(100 * (c.qc / b[3] - 1), 1)} %) L0 ${f(c.l0 * 3.6, 0)} dRes ${f(c.yRes - b[4], 2)} ovf ${f(c.overflash, 2)} '
        'AGO ${f(c.yProd(2), 2)} K95 ${f(c.d86All()[1][7], 1)} D95 ${f(c.d86All()[2][7], 1)} D5 ${f(c.d86All()[2][1], 1)}');
  }
}

void main(List<String> args) {
  final what = args.isEmpty ? 'steady' : args[0];
  if (what == 'steady') {
    steady('default', (c) {});
    steady('kero +2 % (13.7)', (c) => c.drawPct[0] = 13.7);
    steady('kero -2 % (9.7)', (c) => c.drawPct[0] = 9.7);
    for (final s in [0.5, 1.0]) steady('F24 bottom steam s $s', (c) => c.steamBot = 2000 * (1 - s));
    steady('F24 SS2 steam s 1', (c) => c.steamSS = [300, 0, 300]);
    for (final s in [0.5, 1.0]) steady('F25 PA flow s $s', (c) => c.paFlowFrac = 1 - s);
    for (final s in [0.5, 1.0]) steady('F26 COT s $s (-${15 * s} K)', (c) => c.cotC = 345 - 15 * s);
  } else if (what == 'transient') {
    if (args.length > 1 && args[1] == 'f24') {
      transient('F24 s 1 (bottom steam)', (c) => c.steamBot = 0);
      transient('F24 s 0.7', (c) => c.steamBot = 600);
      transient('F25 s 1 (trip)', (c) => c.paFlowFrac = 0);
      return;
    }
    transient('F24 s 1 (bottom steam)', (c) => c.steamBot = 0);
    transient('F24 s 0.7', (c) => c.steamBot = 600);
    transient('F25 s 1 (trip)', (c) => c.paFlowFrac = 0);
    transient('F25 s 0.7', (c) => c.paFlowFrac = 0.3);
    transient('F26 s 1 (step; engine ramps 300 s)', (c) => c.cotC = 330);
    transient('F26 s 0.6', (c) => c.cotC = 336);
  } else if (what == 'f27') {
    for (final k in [13.7, 15.0, 16.0, 17.0]) steady('kero draw $k', (c) => c.drawPct[0] = k);
    for (final a in [6.0, 7.0, 8.0]) steady('AGO draw $a', (c) => c.drawPct[2] = a);
    for (final q in [7.0, 8.0, 9.0]) steady('PA $q MW', (c) => c.paDuty = q * 1e6);
  }
}
