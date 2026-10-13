// Chooses the runner (M10): a background isolate on native platforms, the UI isolate on the web (no isolates there).
export 'sim_runner_web.dart' if (dart.library.io) 'sim_runner_native.dart';
