import 'dart:io' show Platform;

import 'package:lowsys_engine/lowsys_engine.dart';

import 'isolate_sim_runner.dart';

/// Environment variable LOWSYS_LOCAL=1 runs the engine on the UI isolate (A/B measurements of the isolate, docs/DEVIATIONS.md M10).
final bool _local = Platform.environment['LOWSYS_LOCAL'] == '1';

/// Native platforms: the engine runs in a background isolate, so the UI isolate only paints.
SimRunner createSimRunner() => _local ? LocalSimRunner() : IsolateSimRunner();

/// Engine time per frame in milliseconds (the isolate has a whole core to itself; on the UI isolate 6 ms as before M10).
int get kEngineBudgetMs => _local ? 6 : 10;

/// True when the engine runs in a background isolate.
bool get kBackgroundEngine => !_local;
