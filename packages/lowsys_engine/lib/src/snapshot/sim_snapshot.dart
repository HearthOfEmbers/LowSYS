import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../control/instrument.dart';
import '../faults/fault_spec.dart';

export '../control/instrument.dart'
    show Quality, InstrumentType, InstrumentReading;

enum StageKind { drum, tray, packed, sump }

enum StreamId { feed, reflux, distillate, bottoms, vaporProduct, boilup }

enum AlarmPriority { low, medium, high }

enum AlarmState { unack, acked, rtnUnack }

/// Model view, plant view and (M6, PHYSICS.md 10.9) plant view with engineering calculations (`plantCalc`).
enum SimView { model, plant, plantCalc }

extension SimViewX on SimView {
  /// True in both plant views (the truth is masked).
  bool get isPlant => this != SimView.model;
}

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

  /// K, Pa. In Tier 1 [t] is the display-only T* (Raoult bubble point of x_j at the stage pressure, [idealT] true).
  final Float64List t, p;
  final bool idealT;
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

  /// M8: liquid holdup h_L (volume fraction) and Onda wetted fraction a_w/a per packed segment (NaN on trays); kept in
  /// plant views for the column animation.
  final Float64List packHoldup, wetFrac;
  final Uint8List flags;

  const StageArrays({
    required this.n,
    required this.nc,
    required this.x,
    required this.y,
    required this.yStar,
    required this.t,
    this.idealT = false,
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
    required this.packHoldup,
    required this.wetFrac,
    required this.flags,
  });

  double xAt(int stage, int comp) => x[stage * nc + comp];
  double yAt(int stage, int comp) => y[stage * nc + comp];
  double yStarAt(int stage, int comp) => yStar[stage * nc + comp];
}

/// One packed bed (ENGINE_API.md 7.1, M8). Fault parameters ([eMal], [maldistribution]) are NaN in drills and plant views.
@immutable
class PackedBedSnapshot {
  /// 1-based from the top, as in F21/F23 locations and PDT-(101 + bed).
  final int bed;
  final int firstStage, lastStage;
  final String packingId;
  final double height, diameter;

  /// Pa, sum of the segments' dP (plant view: the PDT reading).
  final double dp;

  /// Max phi_p over the bed (fraction); NaN in plant view, kept in plantCalc.
  final double maxFlood;

  /// n_th = sum min(1, H_k/HETP_k); NaN in plant views.
  final double nTheoretical;
  final double eMal, maldistribution;
  const PackedBedSnapshot({
    required this.bed,
    required this.firstStage,
    required this.lastStage,
    required this.packingId,
    required this.height,
    required this.diameter,
    required this.dp,
    required this.maxFlood,
    required this.nTheoretical,
    required this.eMal,
    required this.maldistribution,
  });
}

@immutable
class StreamSnapshot {
  final StreamId id;

  /// mol/s
  final double flow;
  final Float64List composition;

  /// K, NaN in Tier 1
  final double temperature;

  /// Thermal condition q (PHYSICS.md 3.15) of the feed in Tiers 2/3 (NaN elsewhere).
  final double q;
  const StreamSnapshot(this.id, this.flow, this.composition, this.temperature,
      [this.q = double.nan]);
}

@immutable
class CondenserSnapshot {
  /// Drum liquid holdup (mol) and level (%).
  final double drumHoldup, drumLevelPct;

  /// Tiers 2/3 (PHYSICS.md 7): duty (W), clean and effective UA (W/K), CW inlet and outlet (K), CW flow (kg/s) and
  /// CW valve opening (%), condensing temperature and reflux temperature (K), reflux subcooling (K), inert mole
  /// fraction, condensable vapour inventory (mol), condensation / vent / relief rates (mol/s). NaN in Tier 1.
  final double qC, uaClean, uaEff, tCwIn, tCwOut, cwFlow, cwOp;
  final double tCond, tReflux, subcooling, inertFraction, vaporMoles;
  final double nCond, nVent, nRelief;

  /// Partial condenser (PHYSICS.md 7.2): true, and the vapour-product rate D_V (mol/s; 0 for a total condenser).
  final bool partial;
  final double vaporProduct;

  /// n_V,i per component (mol); empty in Tier 1.
  final Float64List vaporInventory;
  const CondenserSnapshot(this.drumHoldup, this.drumLevelPct,
      {this.qC = double.nan,
      this.uaClean = double.nan,
      this.uaEff = double.nan,
      this.tCwIn = double.nan,
      this.tCwOut = double.nan,
      this.cwFlow = double.nan,
      this.cwOp = double.nan,
      this.tCond = double.nan,
      this.tReflux = double.nan,
      this.subcooling = double.nan,
      this.inertFraction = double.nan,
      this.vaporMoles = double.nan,
      this.nCond = double.nan,
      this.nVent = double.nan,
      this.nRelief = double.nan,
      this.partial = false,
      this.vaporProduct = 0,
      required this.vaporInventory});
}

@immutable
class ReboilerSnapshot {
  final double sumpHoldup, sumpLevelPct;

  /// Starvation factor s_sump (PHYSICS.md 8.1).
  final double starvation;

  /// Tiers 2/3 (PHYSICS.md 8.2): delivered duty and the heat-transfer limit Q_max (W), clean and effective UA (W/K),
  /// steam header pressure (Pa abs) and temperature (K), steam valve opening (%), sump temperature (K). NaN in Tier 1.
  final double qDelivered, qMax, uaClean, uaEff, steamP, steamT, steamValveOp;
  final double tSump;

  /// True when the steam valve requests more than the exchanger can transfer (alarm `model.dutyLimited`).
  final bool dutyLimited;

  /// M6 (ENGINE_API.md 7.1). [duty] is Q_R,delivered, [steamSideDuty] the mean of Q_k (what FT-103 measures; equal to the
  /// duty for a kettle). The thermosyphon fields are NaN for a kettle, NaN in plant view and in drills where they would
  /// reveal a fault parameter; plantCalc keeps all of them except [drivingHead] and [sensibleFraction].
  final ReboilerType type;
  final double steamSideDuty;
  final double circulation, exitQuality, riserQuality, instabilityIndex, oscAmplitude, oscPeriod;
  final double inletLineDp, outletLineDp, drivingHead, sensibleFraction;

  /// Inlet valve lever, % open (always visible).
  final double inletValve;
  const ReboilerSnapshot(this.sumpHoldup, this.sumpLevelPct, this.starvation,
      {this.type = ReboilerType.kettle,
      this.steamSideDuty = double.nan,
      this.circulation = double.nan,
      this.exitQuality = double.nan,
      this.riserQuality = double.nan,
      this.instabilityIndex = double.nan,
      this.oscAmplitude = double.nan,
      this.oscPeriod = double.nan,
      this.inletLineDp = double.nan,
      this.outletLineDp = double.nan,
      this.drivingHead = double.nan,
      this.sensibleFraction = double.nan,
      this.inletValve = 100,
      this.qDelivered = double.nan,
      this.qMax = double.nan,
      this.uaClean = double.nan,
      this.uaEff = double.nan,
      this.steamP = double.nan,
      this.steamT = double.nan,
      this.steamValveOp = double.nan,
      this.tSump = double.nan,
      this.dutyLimited = false});
}

/// Column energy balance of Tiers 2/3 in watts (SCOPE.md 8): enthalpy flows in and out and the residual
/// (in minus out). Null in Tier 1.
@immutable
class EnergySnapshot {
  final double feed, reboiler, condenser, distillate, bottoms, residual;

  /// Enthalpy flow of the vapour product D_V H_V,0 of a partial condenser (0 for a total one), included in [residual].
  final double vaporProduct;
  const EnergySnapshot(this.feed, this.reboiler, this.condenser,
      this.distillate, this.bottoms, this.residual,
      {this.vaporProduct = 0});
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

  /// M7 key cuts (PHYSICS.md 10.5): HK and heavier in D, LK and lighter in B (binary: 1 - xD and xB).
  final double xDHeavy, xBLight;

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
    this.xDHeavy = double.nan,
    this.xBLight = double.nan,
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

  /// Tiers 2/3: the column energy balance (null in Tier 1; NaN terms in plant view).
  final EnergySnapshot? energy;

  /// M8: one entry per packed bed, top to bottom (empty for an all-tray column).
  final List<PackedBedSnapshot> beds;

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
    this.energy,
    this.beds = const [],
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
        energy: energy,
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
