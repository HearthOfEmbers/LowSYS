import 'package:flutter/material.dart';

import 'app.dart';
import 'controllers/save_store_open.dart';
import 'controllers/sim_controller.dart';
import 'perf/perf_runner.dart';
import 'theme/themes/registry.dart';
import 'controllers/sim_runner_factory.dart';

/// Build with `--dart-define=LOWSYS_PERF=60` to run the 100x frame-timing benchmark for 60 s and print
/// the result to stdout (used for the fps numbers in docs/DEVIATIONS.md).
const int _perfSeconds = int.fromEnvironment('LOWSYS_PERF', defaultValue: 0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sim = SimController(runner: createSimRunner());
  try {
    sim.saveStore = openSaveStore();
  } on Object {
    // no writable folder: the sandbox just cannot be saved
  }
  await sim.restoreSettings();
  if (_perfSeconds > 0) runPerf(sim, _perfSeconds);
  runApp(LowsysApp(controller: sim, theme: themeById(sim.themeId.value)));
}
