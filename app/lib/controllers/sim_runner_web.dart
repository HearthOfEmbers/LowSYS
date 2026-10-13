import 'package:lowsys_engine/lowsys_engine.dart';

/// Web: the engine runs on the UI isolate with a smaller per-frame budget (SCOPE.md M10).
SimRunner createSimRunner() => LocalSimRunner();

/// Engine time per frame in milliseconds.
int get kEngineBudgetMs => 3;

/// True when the engine runs in a background isolate.
bool get kBackgroundEngine => false;
