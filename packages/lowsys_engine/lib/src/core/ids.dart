import 'package:meta/meta.dart';

/// Stable identifiers. Strings so JSON and scenarios can refer to them.
typedef ComponentId = String;
typedef PresetId = String;
typedef LoopTag = String;
typedef LeverId = String;
typedef FaultId = String;

enum ThermoTier { t1, t2, t3 }

enum HydraulicsMode { ideal, full }

enum TrayType { sieve, valve }

enum CondenserType { total, partial }

enum ReboilerType { kettle, thermosyphon }

enum LoopMode { man, auto, cas, iman }

enum Action { direct, reverse }

/// Engine-wide numeric options. Defaults are the PHYSICS.md values.
@immutable
class SimOptions {
  /// Main step (s).
  final double dt;

  /// Fast-forward step (s).
  final double dtFastForward;
  final int murphreePasses;
  final double thermosyphonSubstep;

  /// PRNG seed (noise, drills).
  final int seed;
  final bool measurementNoise;

  /// Physics switches of the full hydraulics (PHYSICS.md 5). With all three off the full model reproduces
  /// the ideal-hydraulics composition result and still reports the pressure drop (VALIDATION.md VC-12.3).
  final bool entrainment, weeping, downcomerLimit;
  const SimOptions({
    this.entrainment = true,
    this.weeping = true,
    this.downcomerLimit = true,
    this.dt = 0.5,
    this.dtFastForward = 2.0,
    this.murphreePasses = 2,
    this.thermosyphonSubstep = 0.1,
    this.seed = 1,
    this.measurementNoise = false,
  });
}

/// Invalid configuration (thrown by constructors / validate()).
class ConfigException implements Exception {
  final String message;
  ConfigException(this.message);
  @override
  String toString() => 'ConfigException: $message';
}

/// Only escapes when PHYSICS.md 12.7 gives up.
class SolverException implements Exception {
  final String message;
  SolverException(this.message);
  @override
  String toString() => 'SolverException: $message';
}

/// Counters for numerical fallbacks (PHYSICS.md 12.7).
class SolverHealth {
  int bubbleFallbacks = 0;
  int negativeClamps = 0;
  int stepRetries = 0;
  int pressureFallbacks = 0;
  bool thermoOutOfRange = false;
  bool fatal = false;
  String? fatalMessage;

  SolverHealth();

  SolverHealth copy() => SolverHealth()
    ..bubbleFallbacks = bubbleFallbacks
    ..negativeClamps = negativeClamps
    ..stepRetries = stepRetries
    ..pressureFallbacks = pressureFallbacks
    ..thermoOutOfRange = thermoOutOfRange
    ..fatal = fatal
    ..fatalMessage = fatalMessage;
}

enum SimEventType {
  steadyReached,
  rebuildDone,
  solverFallback,
  alarmRaised,
  alarmCleared,
  other,
}

@immutable
class SimEvent {
  final SimEventType type;
  final double time;
  final String message;
  const SimEvent(this.type, this.time, this.message);
}
