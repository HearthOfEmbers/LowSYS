// H8 rows at the middle of each candidate's severity range (noise off): F24 bottom steam s 0.85, F25 s 0.85, F26 s 0.8.
// Also F25 s 0.5 (duty held) for VC-15.5. Times after onset; the engine's own ramps apply (F24 60 s, F26 300 s).
import 'column.dart';
import 'crude.dart';

void run(String tag, void Function(Crude) set, {double ramp = 0, void Function(Crude, double)? rampFn}) {
  final c = Crude()..solve();
  final b0 = [c.t[0], c.t[25], c.t[29], c.qc, c.yRes, c.overflash, c.l0, c.paReturnT];
  final d0 = c.d86All();
  print('$tag');
  var maxTop = c.t[0];
  var t = 0.0;
  for (final at in [300.0, 600.0, 1800.0, 3600.0, 7200.0]) {
    while (t < at) {
      if (rampFn != null) rampFn(c, t);
      if (t == 0) {
        set(c);
        c.setSteam();
      }
      c.step(1.0);
      t += 1;
      if (c.t[0] > maxTop) maxTop = c.t[0];
    }
    c.props();
    final d = c.d86All();
    print('  ${f(at / 60, 0)} min: top ${f(c.t[0] - b0[0], 2)} (peak ${f(maxTop - b0[0], 2)}) FZ ${f(c.t[25] - b0[1], 2)} bot ${f(c.t[29] - b0[2], 2)} K; '
        'Qc ${f(100 * (c.qc / b0[3] - 1), 1)} %; reflux x${f(c.l0 / b0[6], 2)}; res ${f(c.yRes - b0[4], 2)} vol%; ovf ${f(c.overflash, 2)}; '
        'AGO ${f(c.yProd(2), 2)}; PA ${f(c.qPA / 1e6, 2)} MW ret ${f(c.paReturnT - 273.15, 1)} °C; D95 ${f(d[2][7] - d0[2][7], 1)} K; '
        'K95 ${f(d[1][7] - d0[1][7], 1)}; flood ${f(100 * c.flood.reduce((a, b) => a > b ? a : b), 1)}');
  }
}

void main() {
  run('F24 bottom steam s 0.85 (ramp 60 s)', (c) {}, rampFn: (c, t) {
    c.steamBot = 2000 * (1 - 0.85 * (t / 60).clamp(0.0, 1.0));
    c.setSteam();
  });
  run('F25 s 0.85 (step)', (c) => c.paFlowFrac = 0.15);
  run('F25 s 0.5 (step)', (c) => c.paFlowFrac = 0.5);
  run('F26 s 0.8 (-12 K, ramp 300 s)', (c) {}, rampFn: (c, t) => c.cotC = 345 - 12 * (t / 300).clamp(0.0, 1.0));
}
