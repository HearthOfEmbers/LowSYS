import '../config/column_config.dart';
import '../sim/lever_spec.dart';
import '../snapshot/fug.dart';
import '../snapshot/mccabe_thiele.dart';
import '../snapshot/sim_snapshot.dart';
import '../snapshot/txy.dart';

/// What the app wants back with a snapshot (M10): the derived diagram data is built next to the simulator so that a
/// background-isolate runner sends plain data across the isolate boundary and the UI isolate does no engine work.
class FrameRequest {
  /// Build the McCabe-Thiele data (binary and multicomponent, not crude).
  final bool mccabe;
  final bool showRmin;

  /// Build the T-x-y view (binaries in the model view only, when the T-x-y tab is open).
  final bool txy;

  /// Compute the FUG result now (the caller throttles it to every 10 s of simulated time).
  final bool fug;
  final FugTargets? fugTargets;

  /// Trend series the UI shows; a background runner mirrors them into [SimRunner.trends].
  final List<String> trendTags;
  const FrameRequest({
    this.mccabe = true,
    this.showRmin = false,
    this.txy = false,
    this.fug = false,
    this.fugTargets,
    this.trendTags = const [],
  });
}

/// Result of [SimRunner.frame]: the snapshot plus the requested derived data.
class FrameResult {
  final SimSnapshot snapshot;

  /// Simulated seconds actually advanced.
  final double advanced;
  final McCabeThieleData? mccabe;
  final TxyView? txy;
  final FugResult? fug;

  /// Wall time in microseconds spent in advance, snapshot and derived data (perf runs).
  final int advanceMicros, snapshotMicros, derivedMicros;
  const FrameResult(this.snapshot,
      {this.advanced = 0,
      this.mccabe,
      this.txy,
      this.fug,
      this.advanceMicros = 0,
      this.snapshotMicros = 0,
      this.derivedMicros = 0});
}

/// Configuration and levers sent by a background runner when they changed.
class RunnerMeta {
  final ColumnConfig config;
  final List<LeverSpec> levers;
  const RunnerMeta(this.config, this.levers);
}
