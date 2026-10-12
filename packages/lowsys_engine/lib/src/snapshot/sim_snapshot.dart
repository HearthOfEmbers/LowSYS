import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../control/instrument.dart';
import '../faults/fault_spec.dart';

export '../control/instrument.dart'
    show Quality, InstrumentType, InstrumentReading;

enum StageKind { drum, tray, sump }

enum StreamId { feed, reflux, distillate, bottoms, vaporProduct, boilup }

enum AlarmPriority { low, medium, high }

enum AlarmState { unack, acked, rtnUnack }

enum SimView { model, plant }

enum CheckStatus { ok, check, fail, notAvailable, transient }

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
      dpDry,
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
    required this.dpDry,
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

  /// PV (the reading, SI; % for levels), SP (SI), OP (%).
  final double pv, sp, op;

  /// In MAN because of a BAD PV.
  final bool shed;
  final Quality pvQuality;
  final double spLo, spHi, opLo, opHi;
  final double kc, ti, td;
  final Action action;

  /// SP was set by MAN to AUTO tracking.
  final bool spTracked;
  final double lastError, lastDeltaOp;
  const LoopSnapshot(
    this.tag,
    this.mode,
    this.pv,
    this.sp,
    this.op, {
    this.shed = false,
    this.pvQuality = Quality.good,
    this.spLo = 0,
    this.spHi = 100,
    this.opLo = 0,
    this.opHi = 100,
    this.kc = 1,
    this.ti = double.infinity,
    this.td = 0,
    this.action = Action.reverse,
    this.spTracked = false,
    this.lastError = 0,
    this.lastDeltaOp = 0,
  });
}

@immutable
class ValveSnapshot {
  final String id;

  /// Command from its loop (%).
  final double op;

  /// Actual position (%); NaN in plant view.
  final double position;
  final double fMax;

  /// F_max g(OP), the C4 reference curve.
  final double expectedFlow;

  /// -1 closed or 0..100.
  final double bypass;
  const ValveSnapshot(this.id, this.op, this.position, this.fMax,
      this.expectedFlow, this.bypass);
}

@immutable
class Alarm {
  final String id, message;
  final AlarmPriority priority;
  final bool acknowledged;
  final double raisedAt;
  final AlarmState state;
  final double changedAt;
  const Alarm(
      this.id, this.message, this.priority, this.acknowledged, this.raisedAt,
      {this.state = AlarmState.unack, this.changedAt = 0});
}

@immutable
class CrossCheckResult {
  /// 'C1' .. 'C7', 'C4:FV-102', 'C5:drum', 'C6:TI-114'.
  final String id;
  final String titleKey;
  final double residual, band;
  final CheckStatus status;
  final List<String> inputs;
  final String? reason;
  final Map<String, double> terms;
  const CrossCheckResult(this.id, this.titleKey, this.residual, this.band,
      this.status, this.inputs, this.reason, this.terms);
}

@immutable
class FieldCheck {
  final String gaugeTag;
  final double requestedAt, readyAt;
  final double? value;
  const FieldCheck(this.gaugeTag, this.requestedAt, this.readyAt, this.value);
}

enum ScenarioKind { guided, drill }

@immutable
class ObjectiveState {
  final String id, text;
  final bool met;
  final double? metAt;
  final double holdProgress;
  final double holdFor;
  const ObjectiveState(this.id, this.text, this.met, this.metAt,
      this.holdProgress, this.holdFor);
}

@immutable
class HintState {
  final int index;
  final bool unlocked, taken;
  final double cost;
  final String? text;
  const HintState(this.index, this.unlocked, this.taken, this.cost, this.text);
}

@immutable
class ScenarioMessage {
  final double time;
  final String text;
  const ScenarioMessage(this.time, this.text);
}

@immutable
class ScenarioSnapshot {
  final String id;
  final ScenarioKind kind;
  final double elapsed, timeLimit;
  final List<ObjectiveState> objectives;
  final List<HintState> hints;
  final List<ScenarioMessage> messages;
  final int diagnosisAttemptsLeft;
  final bool finished;
  const ScenarioSnapshot({
    required this.id,
    required this.kind,
    required this.elapsed,
    required this.timeLimit,
    required this.objectives,
    required this.hints,
    required this.messages,
    this.diagnosisAttemptsLeft = 0,
    this.finished = false,
  });
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

  /// Highest weeping fraction over the trays (PHYSICS.md 5.13).
  final double maxWeepFraction;
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
    this.maxWeepFraction = 0,
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

  /// M3: plant or model view, instrument readings, valves, cross-checks, field checks, scenario state.
  final SimView view;
  final List<InstrumentReading> instruments;
  final List<ValveSnapshot> valves;
  final List<CrossCheckResult> crossChecks;
  final List<FieldCheck> fieldChecks;
  final ScenarioSnapshot? scenario;

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
    this.view = SimView.model,
    this.instruments = const [],
    this.valves = const [],
    this.crossChecks = const [],
    this.fieldChecks = const [],
    this.scenario,
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
        view: view,
        instruments: instruments,
        valves: valves,
        crossChecks: crossChecks,
        fieldChecks: fieldChecks,
        scenario: scenario,
      );
}

extension ObjectiveStateJson on ObjectiveState {
  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'met': met,
        'metAt': metAt,
        'holdProgress': holdProgress,
        'holdFor': holdFor,
      };
}

extension HintStateJson on HintState {
  Map<String, Object?> toJson() => {
        'index': index,
        'unlocked': unlocked,
        'taken': taken,
        'cost': cost,
        'text': text,
      };
}

extension ScenarioMessageJson on ScenarioMessage {
  Map<String, Object?> toJson() => {'time': time, 'text': text};
}

extension ScenarioSnapshotJson on ScenarioSnapshot {
  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'elapsed': elapsed,
        'timeLimit': timeLimit,
        'objectives': [for (final o in objectives) o.toJson()],
        'hints': [for (final h in hints) h.toJson()],
        'messages': [for (final m in messages) m.toJson()],
        'diagnosisAttemptsLeft': diagnosisAttemptsLeft,
        'finished': finished,
      };
}
