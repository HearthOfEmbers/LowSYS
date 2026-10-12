import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/ids.dart';

enum StageKind { drum, tray, sump }

enum StreamId { feed, reflux, distillate, bottoms, vaporProduct, boilup }

enum AlarmPriority { low, medium, high }

/// Where things are on the column (ENGINE_API.md 7.1).
@immutable
class ColumnLayoutInfo {
  /// Number of trays N; stages are 0..N+1.
  final int nTrays;
  final List<int> feedStages;
  final List<StageKind> kinds;
  final List<String> names;

  /// Index of the last stage of each section (M1: a single section ending at N).
  final List<int> sectionEnds;
  const ColumnLayoutInfo({
    required this.nTrays,
    required this.feedStages,
    required this.kinds,
    required this.names,
    required this.sectionEnds,
  });

  int get stageCount => nTrays + 2;
}

/// Arrays per stage 0..N+1 (ENGINE_API.md 7.1). Fields that do not exist in M1 (ideal hydraulics, Tier 1)
/// are zero (flows, flood) or NaN (temperature, pressure).
@immutable
class StageArrays {
  final int n, nc;

  /// n*nc, row-major by stage
  final Float64List x, y, yStar;

  /// K, Pa. NaN in Tier 1.
  final Float64List t, p;
  final Float64List liquidDown, vaporUp;
  final Float64List entrain, weep;
  final Float64List holdup, hcl, froth;
  final Float64List dp,
      jetFlood,
      dcFlood,
      frothFill,
      stability,
      weepFrac,
      efficiency;
  final Float64List hetp, packFlood;
  final Uint8List flags;

  const StageArrays({
    required this.n,
    required this.nc,
    required this.x,
    required this.y,
    required this.yStar,
    required this.t,
    required this.p,
    required this.liquidDown,
    required this.vaporUp,
    required this.entrain,
    required this.weep,
    required this.holdup,
    required this.hcl,
    required this.froth,
    required this.dp,
    required this.jetFlood,
    required this.dcFlood,
    required this.frothFill,
    required this.stability,
    required this.weepFrac,
    required this.efficiency,
    required this.hetp,
    required this.packFlood,
    required this.flags,
  });

  double xAt(int stage, int comp) => x[stage * nc + comp];
  double yAt(int stage, int comp) => y[stage * nc + comp];
  double yStarAt(int stage, int comp) => yStar[stage * nc + comp];
}

@immutable
class StreamSnapshot {
  final StreamId id;

  /// mol/s
  final double flow;
  final Float64List composition;

  /// K, NaN in Tier 1
  final double temperature;
  const StreamSnapshot(this.id, this.flow, this.composition, this.temperature);
}

@immutable
class CondenserSnapshot {
  /// Drum liquid holdup (mol) and level (%).
  final double drumHoldup, drumLevelPct;
  const CondenserSnapshot(this.drumHoldup, this.drumLevelPct);
}

@immutable
class ReboilerSnapshot {
  final double sumpHoldup, sumpLevelPct;

  /// Starvation factor s_sump (PHYSICS.md 8.1).
  final double starvation;
  const ReboilerSnapshot(this.sumpHoldup, this.sumpLevelPct, this.starvation);
}

@immutable
class LoopSnapshot {
  final LoopTag tag;
  final LoopMode mode;

  /// PV and SP in loop units (% for levels), OP in %.
  final double pv, sp, op;
  const LoopSnapshot(this.tag, this.mode, this.pv, this.sp, this.op);
}

@immutable
class Alarm {
  final String id, message;
  final AlarmPriority priority;
  final bool acknowledged;
  final double raisedAt;
  const Alarm(
      this.id, this.message, this.priority, this.acknowledged, this.raisedAt);
}

@immutable
class FaultInfo {
  final FaultId id;
  final String description;
  const FaultInfo(this.id, this.description);
}

@immutable
class SteadyInfo {
  final bool isSteady;

  /// Last steady-state residual delta (PHYSICS.md 13.3); infinity before the first check.
  final double residual;
  const SteadyInfo(this.isSteady, this.residual);
}

@immutable
class Kpis {
  /// Light component (binary) in the drum and sump.
  final double xD, xB;

  /// mol/s
  final double d, b;

  /// NaN when D is zero.
  final double refluxRatio;
  final double boilup;

  /// W. NaN in Tier 1 (no energy model).
  final double qc, qr;

  /// Pa; zero with ideal hydraulics.
  final double columnDp;

  /// Zero with ideal hydraulics.
  final double maxFloodPct;
  final double drumLevelPct, sumpLevelPct;

  /// Pa; fixed in Tier 1.
  final double pTop;
  final double? recoveryLK, recoveryHK;

  /// |F z - D xD - B xB| / F z for the light component (zero when F = 0).
  final double balanceResidual;

  /// NaN in Tier 1.
  final double energyResidual;
  const Kpis({
    required this.xD,
    required this.xB,
    required this.d,
    required this.b,
    required this.refluxRatio,
    required this.boilup,
    required this.qc,
    required this.qr,
    required this.columnDp,
    required this.maxFloodPct,
    required this.drumLevelPct,
    required this.sumpLevelPct,
    required this.pTop,
    this.recoveryLK,
    this.recoveryHK,
    required this.balanceResidual,
    required this.energyResidual,
  });
}

/// Immutable copy of everything the UI and diagrams need (ENGINE_API.md 7.1).
@immutable
class SimSnapshot {
  final int serial;
  final double time;
  final ThermoTier tier;
  final HydraulicsMode hydraulics;
  final ColumnLayoutInfo layout;
  final List<ComponentId> components;
  final StageArrays stages;
  final Map<StreamId, StreamSnapshot> streams;
  final CondenserSnapshot? condenser;
  final ReboilerSnapshot reboiler;
  final List<LoopSnapshot> loops;
  final List<Alarm> alarms;
  final Kpis kpis;
  final SteadyInfo steady;
  final SolverHealth solverHealth;
  final List<FaultInfo> visibleFaults;

  /// Filled by the runner.
  final double achievedSpeed;

  /// All lever values (SI) at snapshot time. Addition to ENGINE_API.md 7.1 (see DEVIATIONS.md).
  final Map<LeverId, double> levers;

  /// Feed thermal condition q (Tier 1) and Murphree efficiency used by the diagrams.
  final double feedQ, murphree;

  const SimSnapshot({
    required this.serial,
    required this.time,
    required this.tier,
    required this.hydraulics,
    required this.layout,
    required this.components,
    required this.stages,
    required this.streams,
    required this.condenser,
    required this.reboiler,
    required this.loops,
    required this.alarms,
    required this.kpis,
    required this.steady,
    required this.solverHealth,
    required this.visibleFaults,
    this.achievedSpeed = 0,
    required this.levers,
    required this.feedQ,
    required this.murphree,
  });

  /// Copy with the runner-supplied achieved speed.
  SimSnapshot withAchievedSpeed(double v) => SimSnapshot(
        serial: serial,
        time: time,
        tier: tier,
        hydraulics: hydraulics,
        layout: layout,
        components: components,
        stages: stages,
        streams: streams,
        condenser: condenser,
        reboiler: reboiler,
        loops: loops,
        alarms: alarms,
        kpis: kpis,
        steady: steady,
        solverHealth: solverHealth,
        visibleFaults: visibleFaults,
        achievedSpeed: v,
        levers: levers,
        feedQ: feedQ,
        murphree: murphree,
      );
}
