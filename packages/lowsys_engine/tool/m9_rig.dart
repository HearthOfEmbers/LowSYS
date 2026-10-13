// Scratch rig: crude column + control without the Simulator.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:lowsys_engine/src/control/crude_control.dart';
import 'package:lowsys_engine/src/model/crude_column.dart';

void main(List<String> args) {
  final cfg = Presets.byId('crude');
  final health = SolverHealth();
  final col = CrudeColumn(cfg, health);
  final cc = CrudeControl.build(cfg, col, 1);
  cc.primeInputs(cfg);
  col.initCold();
  cc.initialiseCrude(0);
  final hours = double.parse(args.isEmpty ? '1' : args[0]);
  final dt = double.parse(args.length > 1 ? args[1] : "0.5");
  final sw = Stopwatch()..start();
  var t = 0.0;
  var nextPrint = 0.0;
  while (t < hours * 3600) {
    if (!cc.stepAll(dt, t)) { print('FAILED at $t'); break; }
    t += dt;
    if (t >= nextPrint) {
      nextPrint += 900;
      print('${(t/3600).toStringAsFixed(2)} h T1 ${(col.t[0]-273.15).toStringAsFixed(2)} T8 ${(col.t[7]-273.15).toStringAsFixed(1)} T15 ${(col.t[14]-273.15).toStringAsFixed(1)} T26 ${(col.t[25]-273.15).toStringAsFixed(1)} T30 ${(col.t[29]-273.15).toStringAsFixed(1)} L0 ${(col.l0*3.6).toStringAsFixed(1)} yN ${col.yNaph.toStringAsFixed(2)} yK ${col.yProd(0).toStringAsFixed(2)} yD ${col.yProd(1).toStringAsFixed(2)} yA ${col.yProd(2).toStringAsFixed(2)} yR ${col.yRes.toStringAsFixed(2)} OF ${col.overflash.toStringAsFixed(2)} Qc ${(col.qc/1e6).toStringAsFixed(3)} drum ${col.drumLevelPct.toStringAsFixed(1)} sump ${col.sumpLevelPct.toStringAsFixed(1)}');
    }
  }
  print('wall ${sw.elapsedMilliseconds} ms, ${(sw.elapsedMicroseconds / (t/dt)).toStringAsFixed(0)} us/step, negLatent ${health.negativeLatent} bubbleFB ${health.bubbleFallbacks}');
}
