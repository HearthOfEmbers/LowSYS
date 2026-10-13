import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app.dart';
import 'controllers/save_store.dart';
import 'controllers/sim_controller.dart';

/// Build with `--dart-define=LOWSYS_PERF=60` to run the 100x frame-timing benchmark for 60 s and print
/// the result to stdout (used for the fps numbers in docs/DEVIATIONS.md).
const int _perfSeconds = int.fromEnvironment('LOWSYS_PERF', defaultValue: 0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final sim = SimController();
  try {
    sim.saveStore = FileSaveStore.open();
  } on Object {
    // no writable folder: the sandbox just cannot be saved
  }
  sim.restoreSettings();
  if (_perfSeconds > 0) _runPerf(sim);
  runApp(LowsysApp(controller: sim));
}

void _runPerf(SimController sim) {
  final frames = <FrameTiming>[];
  final sw = Stopwatch();
  SchedulerBinding.instance.addTimingsCallback(frames.addAll);
  Timer.periodic(const Duration(milliseconds: 200), (t) {
    if (!sim.loaded) return;
    if (!sw.isRunning) {
      SimController.perfRecording = true;
      sim.setSpeed(100);
      sw.start();
      frames.clear();
      SimController.perfAdvance.clear();
      SimController.perfSnapshot.clear();
      SimController.perfMccabe.clear();
      SimController.perfNotify.clear();
    }
    if (sw.elapsed.inSeconds >= _perfSeconds) {
      t.cancel();
      final total =
          frames.map((f) => f.totalSpan.inMicroseconds / 1000).toList()..sort();
      final build =
          frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
            ..sort();
      final raster =
          frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
            ..sort();
      double pct(List<double> l, double p) =>
          l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
      final over32 = total.where((v) => v > 32).length;
      stdout.writeln(
        'PERF frames=${frames.length} wall=${sw.elapsed.inSeconds}s '
        'fps=${(frames.length / sw.elapsedMilliseconds * 1000).toStringAsFixed(1)} '
        'total_ms p50=${pct(total, .5).toStringAsFixed(2)} p95=${pct(total, .95).toStringAsFixed(2)} p99=${pct(total, .99).toStringAsFixed(2)} max=${pct(total, 1).toStringAsFixed(2)} '
        'build_p95=${pct(build, .95).toStringAsFixed(2)} raster_p95=${pct(raster, .95).toStringAsFixed(2)} '
        'over32ms=$over32 (${(over32 * 100 / (frames.isEmpty ? 1 : frames.length)).toStringAsFixed(2)}%) '
        'simTime=${sim.snapshot.value?.time.toStringAsFixed(0)}s achieved=${sim.achievedSpeed.value.toStringAsFixed(0)}x',
      );
      String st(List<int> l) {
        final v = l.map((e) => e / 1000).toList()..sort();
        return v.isEmpty ? 'n/a' : 'p50=${pct(v, .5).toStringAsFixed(2)} p95=${pct(v, .95).toStringAsFixed(2)} max=${pct(v, 1).toStringAsFixed(2)}';
      }

      stdout.writeln('PERFPARTS advance_ms ${st(SimController.perfAdvance)} | snapshot_ms ${st(SimController.perfSnapshot)} | notify_ms ${st(SimController.perfNotify)} | mccabe_ms ${st(SimController.perfMccabe)}');
      exit(0);
    }
  });
}
