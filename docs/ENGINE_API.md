# LowSYS — Architecture and Engine API

Status: specification v1.0 (2026-10-12). Read with [PHYSICS.md](PHYSICS.md) (what the engine computes) and [SCOPE.md](SCOPE.md) (what the app shows, milestone by milestone). Dart below is an interface sketch: names, responsibilities and signatures are binding; bodies are not. Where a detail is the implementer's choice it is marked **[impl]**.

---

## 1. Repository layout

```
LowSYS/
  docs/                         SCOPE.md, PHYSICS.md, ENGINE_API.md, VALIDATION.md
  packages/
    lowsys_engine/              pure Dart package, NO Flutter dependency
      pubspec.yaml              dependencies: meta ; dev_dependencies: test, lints
      lib/
        lowsys_engine.dart      public exports (only what is listed in this document)
        src/
          core/                 ids.dart, quantity.dart, units.dart, errors.dart, rng.dart
          math/                 banded_solver.dart (Thomas + one sub-diagonal), roots.dart (newton/bisection/secant), interp.dart
          data/                 components_json.dart, binaries_json.dart, packings_json.dart,
                                presets/*.dart (ColumnConfig JSON as Dart raw strings),
                                scenarios/*.dart (scenario JSON as Dart raw strings),
                                steady_cache/*.dart (cached steady states, §5.5)
          thermo/               component.dart, component_db.dart, thermo_model.dart,
                                tier1_constant_alpha.dart, tier2_raoult.dart, tier3_nrtl.dart,
                                tier3_depriester.dart, crude_thermo.dart, vapour_pressure.dart,
                                enthalpy.dart, properties.dart, flash.dart, petroleum.dart
          config/               column_config.dart, sections.dart, tray_geometry.dart,
                                packing_spec.dart, equipment.dart, control_config.dart, presets.dart
          model/                column_state.dart (SoA buffers), layout.dart,
                                tray_hydraulics.dart, packed_hydraulics.dart,
                                condenser.dart, reboiler.dart, thermosyphon.dart,
                                side_ops.dart (draws, pumparound, strippers, steam)
          sim/                  simulator.dart, stepper.dart, component_solver.dart,
                                hydraulic_solver.dart, initializer.dart, steady_monitor.dart,
                                rebuild.dart, tier_switch.dart, history_ring.dart
          control/              pid.dart, loop.dart, valve.dart, instrument.dart, analyser.dart,
                                field_gauge.dart, fast_layer.dart (PHYSICS.md §10.1), control_system.dart,
                                alarms.dart, cross_checks.dart (PHYSICS.md §14.6)
          faults/               fault_spec.dart, fault_manager.dart, fault_effects.dart
          explain/              trace.dart, explain_engine.dart, equation_catalog.dart
          snapshot/             sim_snapshot.dart, kpis.dart, mccabe_thiele.dart, profiles.dart,
                                fug.dart, crude_products.dart, txy.dart, plant_view.dart (masking, PHYSICS.md §10.9)
          scenario/             scenario_def.dart, predicate.dart, scenario_runner.dart,
                                drill.dart, scoring.dart
          runner/               sim_runner.dart (interface), local_sim_runner.dart,
                                isolate_sim_runner.dart (M10, native only)
      test/                     mirrors lib/src; VALIDATION.md cases live here
  app/                          Flutter application "lowsys_app"
    pubspec.yaml                depends on lowsys_engine via path: ../packages/lowsys_engine
    lib/ ... (§12)
    assets/fonts/ ...           bundled OFL fonts (§12.6)
    test/                       widget and golden tests
```

Rules:
- `lowsys_engine` imports only `dart:core`, `dart:math`, `dart:typed_data`, `dart:convert`, `dart:collection` and `package:meta`. It never imports `dart:io`, `dart:isolate` (except `isolate_sim_runner.dart`, which is excluded from web builds with a conditional import) or Flutter.
- All data (components, presets, scenarios) is JSON stored as Dart raw strings in `src/data`, parsed at startup. Tests can therefore load every preset and scenario without Flutter.
- The app talks to the engine only through `SimRunner` (§6.6), never to `Simulator` directly. This keeps the M10 move to a background isolate a local change.

---

## 2. Core types

```dart
/// Stable identifiers. Strings so JSON and scenarios can refer to them.
typedef ComponentId = String;   // e.g. 'benzene', 'PC4', 'water'
typedef PresetId = String;      // e.g. 'bt', 'debut', 'crude'
typedef LoopTag = String;       // e.g. 'LC-101'
typedef LeverId = String;       // see §6.3
typedef FaultId = String;       // instance id returned by FaultManager.inject

enum ThermoTier { t1, t2, t3 }
enum HydraulicsMode { ideal, full }
enum TrayType { sieve, valve }
enum CondenserType { total, partial }
enum ReboilerType { kettle, thermosyphon }

/// Engine-wide numeric options. Defaults are the PHYSICS.md values.
@immutable
class SimOptions {
  final double dt;                 // 0.5 s
  final double dtFastForward;      // 2.0 s
  final int murphreePasses;        // 2
  final double thermosyphonSubstep;// 0.1 s
  final int seed;                  // PRNG seed (noise, drills), 0 ≤ seed < 2^32 (PHYSICS.md §12.9)
  final bool measurementNoise;     // engine default false (tests); the app's sandbox starts with the
                                   // `noise` lever on (SCOPE.md §4.2); scenarios set it explicitly
  const SimOptions({this.dt = 0.5, this.dtFastForward = 2.0, this.murphreePasses = 2,
      this.thermosyphonSubstep = 0.1, this.seed = 1, this.measurementNoise = false});
}
```

Errors: `ConfigException` (invalid configuration, thrown by constructors/`validate()`), `SolverException` (only escapes when PHYSICS.md §12.7 gives up; the simulator is then paused and `solverHealth.fatal` is set).

---

## 3. Components and thermodynamics

### 3.1 Component data

```dart
enum VaporPressureKind { antoineLog10MmHgC, dippr101, leeKesler }

@immutable
class Component {
  final ComponentId id;
  final String name;
  final double mw;          // g/mol
  final double tb, tc;      // K
  final double pc;          // Pa  (stored in Pa; PHYSICS tables list bar)
  final double omega;
  final double dHvapTb;     // J/mol
  final double cp0, dCp;    // J/mol/K at 298.15 K ; J/mol/K^2
  final double rhoRef, tRef;// kg/m3 at tRef (K)
  final double? zraOverride;
  final double sigmaRef;    // N/m at 298.15 K (named) ; unused for pseudo (uses kW)
  final VaporPressureKind vpKind;
  final List<double> vpCoeffs;        // Antoine [A,B,C] | DIPPR [C1..C5] | []
  final List<double>? mcWilliams;     // [aT1,aT2,aT6,ap1,ap2,ap3] or null
  final bool vaporOnly;               // true for steam in crude
  final PseudoInfo? pseudo;           // crude: cut range, SG, Kw, volume fraction in assay
  const Component({/* all fields */});
}

class ComponentDb {
  static ComponentDb load();                 // parses components_json.dart
  Component operator [](ComponentId id);
  BinaryNrtl? nrtl(ComponentId i, ComponentId j);   // returns parameters oriented i→j
  List<Component> pseudoComponentsFromAssay(AssayDef assay); // PHYSICS.md §9.1
}

@immutable
class BinaryNrtl { final double aij, aji, bij, bji, alpha; }
```

### 3.2 Thermo interface

One `ThermoModel` per tier per system, built by `ThermoFactory.build(systemConfig, tier)`. All methods are allocation-free: callers pass output buffers.

```dart
abstract class ThermoModel {
  ThermoTier get tier;
  int get nc;
  bool get hasTemperature;         // false for Tier 1 (M1–M3)

  /// K-values at (T, P, x). Tier 1 fills alpha_i (relative, not true K).
  void kValues(double t, double p, Float64List x, Float64List kOut);

  /// d ln K_i / dT (gamma treated constant), for the bubble Newton.
  void dLnKdT(double t, double p, Float64List x, Float64List out);

  /// Bubble point. Returns T (K); fills yOut (normalised) and kOut. Uses tGuess.
  /// Records fallbacks in [health]. Tier 1: throws UnsupportedError.
  double bubbleT(double p, Float64List x, double tGuess, Float64List yOut, Float64List kOut, SolverHealth health);
  double dewT(double p, Float64List y, double tGuess, Float64List xOut, SolverHealth health);
  FlashResult flashTP(double t, double p, Float64List z);             // allocates; not on hot path
  double qOfFeed(double tFeed, double p, Float64List z);               // PHYSICS.md (3.15)

  double hL(double t, Float64List x);          // J/mol
  double hV(double t, Float64List y);          // J/mol
  double cpL(double t, Float64List x);         // J/mol/K
  double liquidMolarVolume(double t, Float64List x);   // m3/mol
  double vaporDensity(double t, double p, Float64List y); // kg/m3
  double surfaceTension(double t, Float64List x);      // N/m
  double liquidViscosity();                            // Pa·s (preset constant)
}

/// Tier 1 adds the relative volatilities and constant properties.
abstract class ConstantAlphaThermo implements ThermoModel {
  Float64List get alpha;
  double get rhoL; double get rhoV; double get sigma;
}
```

Implementations: `Tier1ConstantAlpha`, `Tier2Raoult`, `Tier3Nrtl` (binary and general n-component formula), `Tier3DePriester`, `CrudeThermo` (Tier 2 with steam handling: `bubbleT` takes the steam fraction through `setSteamFraction(j, yw)` before the call **[impl: or an extra parameter]**). From M4, Tier 1 also offers `displayBubbleT()` backed by a Tier-2 model, labelled "ideal" in the UI.

---

## 4. Column configuration

`ColumnConfig` is immutable, JSON-serialisable and fully describes a column, its equipment, its controls and its initial lever values. Presets are `ColumnConfig` JSON. `validate()` returns a list of problems (empty = valid).

```dart
@immutable
class ColumnConfig {
  final PresetId presetId;
  final String displayName;
  final List<ComponentId> components;      // order defines index i
  final ThermoTier tier;
  final Float64List? tier1Alpha;            // relative volatilities (heavy key = 1)
  final Tier1Props? tier1Props;             // rhoL, rhoV, sigma
  final double liquidViscosity;             // Pa·s
  final List<SectionConfig> sections;       // top to bottom; trays or packed beds
  final List<FeedConfig> feeds;
  final CondenserConfig condenser;
  final ReboilerConfig reboiler;
  final List<SideDrawConfig> sideDraws;     // crude
  final List<PumparoundConfig> pumparounds; // crude
  final List<StripperConfig> strippers;     // crude
  final List<SteamConfig> steam;            // crude
  final ControlConfig control;              // loops, tunings, modes
  final HydraulicsMode hydraulics;
  final KeyComponents? keys;                // multicomponent LK/HK
  final Map<LeverId, double> initialLevers;
  final double murphree;                    // global E_MV
  List<String> validate();
  factory ColumnConfig.fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson();
  ColumnConfig copyWith({/* any field */});
}

sealed class SectionConfig { int get stageCount; }
class TraySection extends SectionConfig {
  final int trays; final TrayType type; final TrayGeometry geometry;
}
class PackedSection extends SectionConfig {
  final double bedHeight; final String packingId;  // PHYSICS.md §6.2
  final double diameter; final double? designLiquidFlux; // kg/m2/s, for a_w,ref
  // stageCount = max(1, round(bedHeight / HETP_ref))
}

@immutable
class TrayGeometry {
  final double diameter, traySpacing, downcomerFraction, weirHeight, apronClearance;
  final double holeFraction, holeDiameter, orificeCoeff;          // sieve
  final double valveOpenFraction, valveClosedRatio, valveLiftDp, valveCoeff; // valve
  final double downcomerAeration, systemFactor;
}

class FeedConfig { final int stage; final double flow; final Float64List z; final FeedThermal thermal; }
sealed class FeedThermal {}
class FeedQ extends FeedThermal { final double q; }               // Tier 1
class FeedTemperature extends FeedThermal { final double t; }     // Tiers 2/3, K
class FeedVaporFraction extends FeedThermal { final double beta; }

class CondenserConfig { final CondenserType type; final double drumVolume, overheadVolume,
  pTopDesign, reliefSet, cwInletT, cwMaxFlow /*kg/s*/, uaClean /*W/K, from the preset*/, dvMax; }
class ReboilerConfig { final ReboilerType type; final double sumpHeight, sumpArea,
  steamHeaderPressure, uaClean /*W/K, from the preset*/; final ThermosyphonGeometry? thermosyphon; }
```

Preset JSON example (abbreviated, B-T default):

```json
{
  "presetId": "bt",
  "displayName": "Benzene–toluene (textbook)",
  "components": ["benzene", "toluene"],
  "tier": "t1",
  "tier1Alpha": [2.5, 1.0],
  "tier1Props": {"rhoL": 800, "rhoV": 2.9, "sigma": 0.020},
  "liquidViscosity": 0.00027,
  "sections": [{"kind": "trays", "trays": 20, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.6, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 10, "flow": 0.0277778, "z": [0.5, 0.5], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 28500},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 57500},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 0.0277778, "refluxFlow": 0.0277778, "boilup": 0.0416667}
}
```

All JSON values are SI (mol/s, K, Pa, m, kg/s, W). The UI converts for display.

### 4.1 Presets to ship

`bt` (M1), `bt_custom_alpha` (M1), `mw`, `ew`, `ac`, `c4` (M5), `debut`, `deprop` (M7), `bt_packed` (M8), `crude` (M9), plus scenario-specific variants defined inside scenario JSON as `overrides`.

---

## 5. Internal state (not public)

### 5.1 Storage

`ColumnState` holds every state of PHYSICS.md §1.2 in structure-of-arrays form: one `Float64List` of length `nStages × nc` for component holdups (row-major by stage), separate `Float64List`s for every derived per-stage quantity (x, y, T, P, L, V, e, W, hcl, ΔP, φ, ψ, …), and scalar fields for the drum, sump, pressure inventory, thermosyphon and controllers. `Layout` maps stage index ↔ section/tray/segment and records the feed, draw and return stages.

### 5.2 Step implementation

`Stepper.step(ColumnState s, EffectiveParams p, double dt)` implements PHYSICS.md §12.4 exactly, in that order, with no allocation. `HydraulicSolver` (§12.2) and `ComponentSolver` (§12.3) are separate classes so they can be unit-tested.

### 5.3 History ring

`HistoryRing` keeps a deep copy of `ColumnState` every 60 s of sim time (last 10 copies) for "rewind" (PHYSICS.md §12.7) and for the steady-state monitor.

### 5.4 Trend buffer

`TrendBuffer` stores selected variables every 5 s of sim time for 2 h (1440 points each) in ring `Float64List`s: all loop PV/SP/OP, xD, xB (or key specs), P_top, total ΔP, max flood, Q_C, Q_R, V_B, levels, and up to 6 user-pinned stage variables.

Every instrument reading is stored as **three** series per 5-s bin: mean, min and max of all its updates in that bin (FT: 50 updates; others: 10 at dt = 0.5 s), plus the worst quality seen in the bin. The trend painter draws the min–max envelope per pixel column, so a 1-s spike or the noise band stays visible after decimation (PHYSICS.md §14.6). Cross-checks read the bin means. In plant view the model series (xD, xB, max flood, …) are not sent; the reading series are.

### 5.5 Steady-state cache

`SteadyCache` stores, per preset id and tier, a serialised `ColumnState` produced by `runToSteadyState()`. A tool test (`test/data/steady_cache_test.dart`) regenerates each cache and fails if it differs from the stored one by more than 1×10⁻⁶ (VALIDATION.md VC-4).

---

## 6. Simulator

### 6.1 Class

```dart
class Simulator {
  Simulator(ColumnConfig config, {SimOptions options = const SimOptions(), bool warmStart = true});

  // --- time ---
  double get time;                         // s
  void step();                             // one step of options.dt
  void advance(double simSeconds);         // whole steps; remainder carried to the next call
  SteadyStateResult runToSteadyState({double maxSimSeconds = 172800, bool fastForward = true});
  bool get isSteady;                       // PHYSICS.md §13.3

  // --- inputs ---
  void setLever(LeverId id, double value); // SI value; validated against LeverSpec ranges
  double lever(LeverId id);
  List<LeverSpec> get levers;              // what this configuration offers (depends on tier, equipment)

  // --- structure ---
  ThermoTier get tier;
  void setTier(ThermoTier tier);           // PHYSICS.md §13.5
  void setHydraulicsMode(HydraulicsMode mode);
  void rebuild(ColumnConfig newConfig);    // e.g. tray count change; PHYSICS.md §13.4
  ColumnConfig get config;

  // --- subsystems ---
  ControlSystem get control;               // §10
  FaultManager get faults;                 // §9
  ScenarioRunner? get scenario;            // §11, attached by the scenario layer
  void startScenario(ScenarioDef def);     // builds config + overrides, starts warm, applies levers/loops,
                                           // draws the drill fault (§11.2); replaces any running scenario

  // --- operator actions (all deterministic, all logged in the event journal) ---
  void acknowledgeAlarm(String alarmId);   // PHYSICS.md §10.8
  void acknowledgeAllAlarms();
  void requestFieldCheck(String gaugeTag); // LG-101, LG-102, PG-101: result after 180 s (PHYSICS.md §10.5)
  void requestMaintenance(String tag);     // sandbox only; throws StateError in a drill
  void setCheckWindow(double seconds);     // 300 | 600 | 1800 | 3600 (PHYSICS.md §14.6)
  void setTemperatureReference();          // C6 reference = current 300-s means

  // --- outputs ---
  SimSnapshot snapshot();                  // immutable copy; allocates (call once per frame)
  ExplainResult explain(ExplainTarget target);   // §8; recomputes with tracing on
  TrendBuffer get trends;
  SolverHealth get solverHealth;

  // --- persistence ---
  Map<String, Object?> saveState();        // config + full state + levers + faults + controller states
  factory Simulator.restore(Map<String, Object?> saved, {SimOptions options});
  bool rewind(double simSeconds);          // from the history ring; false if not available
}

class SteadyStateResult { final bool reached; final double simSeconds; final double residual; }
```

### 6.2 Threading

`Simulator` is single-threaded and synchronous. It is never shared across isolates; the isolate runner owns its own instance (§6.6).

### 6.3 Levers

```dart
@immutable
class LeverSpec {
  final LeverId id;
  final String label;            // UI label key
  final Quantity quantity;       // for unit conversion (§12.2)
  final double min, max, defaultValue;   // SI
  final Set<ThermoTier> tiers;
  final LoopTag? boundLoop;      // when set: AUTO edits SP, MAN edits OP
  final bool requiresPause;      // condenser type, reboiler type, geometry
  final String group;            // 'feed' | 'top' | 'bottom' | 'column' | 'advanced' | 'crude'
}
```

Lever ids (SI values): `feedFlow`, `feedZ.<componentId>`, `feedQ`, `feedT`, `feedVaporFraction`, `feedStage`, `refluxFlow`, `refluxRatio`, `refluxMode` (0 flow / 1 ratio), `refluxSubcooling`, `boilup`, `reboilerDuty`, `pTop`, `condenserType`, `drumLevelSp`, `sumpLevelSp`, `distillateValve`, `bottomsValve`, `nTrays`, `murphree`, `trayType.<section>`, `hydraulics`, `cwInletT`, `cwMaxFlow`, `steamHeaderP`, `reboilerType`, `tsInletValve`, `antifoam`, `inertVent`, `tc101Enable`, `tc101Tray`, `tc101Sp`, `noise`, `crudeRate`, `cot`, `topTSp`, `drawRate.<product>`, `paDuty`, `steam.<point>`, `drumTSp`. Ranges and defaults: SCOPE.md §4.

M3 additions:
- `view`: 0 model, 1 plant (PHYSICS.md §10.9).
- `badPvShed`: 1 shed (default) / 0 none (§10.2).
- `bypass.<valveId>`: −1 closed (default) or 0–100 % (§10.3).
- `feedFlowOp`, `refluxOp`, `boilupOp`: OP % of FC-101/102/103, effective in MAN, alongside the existing `distillateValve` and `bottomsValve`.

**Lever-to-loop binding** (M3). Each loop-bound lever edits the SP while its loop is in AUTO and the OP lever while it is in MAN; in CAS the SP lever is read-only and shows the cascade SP.

| SP lever | OP lever | Loop |
|---|---|---|
| `feedFlow` | `feedFlowOp` | FC-101 |
| `refluxFlow` | `refluxOp` | FC-102 |
| `refluxRatio` | – (ratio station) | FC-102 |
| `boilup` / `reboilerDuty` | `boilupOp` | FC-103 |
| `drumLevelSp` | `distillateValve` | LC-101 |
| `sumpLevelSp` | `bottomsValve` | LC-102 |
| `pTop` | – (CW valve via the faceplate) | PC-101 |
| `tc101Sp` | – | TC-101 |

Setting an SP lever while its loop is in MAN stores the value but has no effect until the loop is in AUTO again. The value is then overwritten by setpoint tracking, and the UI disables the SP control in MAN.

### 6.4 Scheduling contract (for the runner)

`advance(s)` performs `floor((carry + s)/dt)` steps. The runner decides how much sim time to request per frame (§13.3). The simulator never reads a wall clock.

### 6.5 Events

```dart
Stream<SimEvent> get events;   // alarm raised/cleared, fault onset (sandbox only), scenario objective met,
                               // steady reached, solver fallback, relief lifting, rebuild done
```

### 6.6 SimRunner (the only thing the app uses)

```dart
abstract class SimRunner {
  Future<void> load(ColumnConfig config, {SimOptions options, bool warmStart});
  Future<void> loadSaved(Map<String, Object?> saved);
  /// Advance by up to [simSeconds] but stop when [wallBudget] is used. Returns the sim time actually advanced.
  Future<double> advance(double simSeconds, Duration wallBudget);
  Future<SimSnapshot> snapshot();
  Future<void> setLever(LeverId id, double value);
  Future<void> setTier(ThermoTier t);
  Future<void> setLoopMode(LoopTag tag, LoopMode mode);
  Future<void> setLoopSp(LoopTag tag, double sp);
  Future<void> setLoopOp(LoopTag tag, double op);
  Future<FaultId> injectFault(FaultSpec spec);
  Future<void> clearFault(FaultId id);
  // M3: operator actions and scenarios (the app never touches Simulator directly)
  Future<void> acknowledgeAlarm(String alarmId);
  Future<void> acknowledgeAllAlarms();
  Future<void> requestFieldCheck(String gaugeTag);
  Future<void> requestMaintenance(String tag);
  Future<void> setCheckWindow(double seconds);
  Future<void> setTemperatureReference();
  Future<void> startScenario(ScenarioDef def, {int? seed});    // seed defaults to a new random value per attempt
  Future<void> takeHint(int index);                            // unlocks and charges its cost (§11.4)
  Future<AnswerResult> submitAnswer(String objectiveId, Object answer);
  Future<DrillResult> submitDiagnosis(Diagnosis d);
  Future<ScoreCard> finishScenario();
  Future<ExplainResult> explain(ExplainTarget target);
  Future<SteadyStateResult> runToSteadyState({void Function(double progress)? onProgress});
  Future<Map<String, Object?>> save();
  Stream<SimEvent> get events;
  Future<void> dispose();
}
class LocalSimRunner implements SimRunner { /* wraps Simulator on the calling isolate; futures complete synchronously */ }
class IsolateSimRunner implements SimRunner { /* M10, native only: engine in a background isolate,
   snapshots transferred as TransferableTypedData; same semantics */ }
```

On the UI isolate (M1–M9) `advance` uses a `Stopwatch` to respect `wallBudget` between steps.

---

## 7. Snapshots and derived data

### 7.1 SimSnapshot

Immutable. Arrays are copies (`Float64List`), so painters may read them at any time.

```dart
@immutable
class SimSnapshot {
  final int serial;                 // increments every snapshot
  final double time;
  final ThermoTier tier;
  final HydraulicsMode hydraulics;
  final ColumnLayoutInfo layout;    // stage kinds, section boundaries, feed/draw/return stages, names
  final List<ComponentId> components;
  final StageArrays stages;         // per stage (0..N+1)
  final Map<StreamId, StreamSnapshot> streams;   // feed, reflux, distillate, bottoms, vaporProduct, side products, steam
  final CondenserSnapshot? condenser;
  final ReboilerSnapshot reboiler;  // kettle or thermosyphon fields
  final List<LoopSnapshot> loops;
  final List<Alarm> alarms;
  final Kpis kpis;
  final SteadyInfo steady;          // isSteady, last residual
  final SolverHealth solverHealth;
  final List<FaultInfo> visibleFaults;  // empty in drills
  final double achievedSpeed;       // filled by the runner
  // M3
  final SimView view;               // model | plant (PHYSICS.md §10.9); in plant view the fields above are masked
  final List<InstrumentReading> instruments;
  final List<ValveSnapshot> valves;
  final List<CrossCheckResult> crossChecks;    // PHYSICS.md §14.6
  final List<FieldCheck> fieldChecks;          // pending and completed field-gauge readings
  final ScenarioSnapshot? scenario;            // objectives, unlocked hints, messages, timer; no fault data in drills
}

enum SimView { model, plant }
enum Quality { good, uncertain, bad, oos }
enum InstrumentType { ftLiquid, ftSteam, ftWater, ltDrum, ltSump, pt, pdt, tiTray, tiLine, at }

@immutable
class InstrumentReading {
  final String tag;                 // 'FT-102'
  final InstrumentType type;
  final Quantity quantity;          // for display units
  final double value;               // v_meas, SI (PHYSICS.md §10.5 step 9); for AT the shown result
  final double lo, hi;              // span, SI
  final double milliamps;           // I_q (NaN for AT)
  final Quality quality;
  final String? qualityText;        // 'IOP−', 'IOP+', 'OOR▲', 'OOR▼', 'STALE', 'OOS' or null
  final double lastGoodValue;       // shown greyed when BAD
  final double sigma5min;           // std of the readings over the last 300 s (signal look)
  final double typicalSigma;        // σ_disp of a healthy transmitter (PHYSICS.md §10.5 table)
  final double digitsAge;           // s since the displayed digits last changed (Fmt resolution)
  final double? resultAge;          // AT only: age of the shown result (s)
  final String? loopTag;            // loop that uses it as PV, if any
}

@immutable
class ValveSnapshot {
  final String id;                  // 'FV-102'
  final double op;                  // command from its loop (%)
  final double position;            // p (%), NaN in plant view
  final double fMax;                // SI; NaN for FV-103 in Tiers 2/3 (see expectedFlow)
  final double expectedFlow;        // F_max g(OP), or Q_max,0 g(OP) for the steam valve (C4 curve)
  final double bypass;              // −1 closed or 0–100
}

@immutable
class LoopSnapshot {
  final LoopTag tag;
  final LoopMode mode;              // man | auto | cas | iman
  final bool shed;                  // in MAN because of a BAD PV
  final double pv, sp, op;          // pv = the reading (SI), sp SI, op %
  final Quality pvQuality;
  final double spLo, spHi, opLo, opHi;
  final double kc, ti, td;
  final Action action;
  final bool spTracked;             // SP was set by MAN→AUTO tracking (faceplate note)
  final double lastError, lastDeltaOp;   // for eq.pid
}

enum AlarmState { unack, acked, rtnUnack }   // NORMAL alarms are not listed
enum AlarmPriority { high, medium, low }

@immutable
class Alarm {
  final String id;                  // '<tag>.<type>' or 'model.<type>' (PHYSICS.md §10.8)
  final String message;             // localisation key + parameters
  final AlarmPriority priority;
  final AlarmState state;
  final double raisedAt, changedAt; // sim time
}

enum CheckStatus { ok, check, fail, notAvailable, transient }

@immutable
class CrossCheckResult {
  final String id;                  // 'C1' … 'C7', 'C4:FV-102', 'C5:drum', 'C6:TI-114'
  final String titleKey;
  final double residual, band;      // SI
  final CheckStatus status;
  final List<String> inputs;        // tags used
  final String? reason;             // e.g. 'BAD input FT-104'
  final Map<String, double> terms;  // the numbers the panel row prints (F, D+B, accumulation, …)
}

@immutable
class FieldCheck { final String gaugeTag; final double requestedAt, readyAt; final double? value; }

@immutable
class ScenarioSnapshot {
  final String id; final ScenarioKind kind; final double elapsed, timeLimit;
  final List<ObjectiveState> objectives;   // id, text, met, metAt, holdProgress (s)
  final List<HintState> hints;             // index, unlocked, taken, cost, text (only when taken)
  final List<ScenarioMessage> messages;    // event messages so far (time, text)
  final int diagnosisAttemptsLeft;         // drills
  final bool finished;
}

@immutable
class StageArrays {
  final int n, nc;
  final Float64List x, y, yStar;          // n*nc, row-major by stage
  final Float64List t, p;                 // K, Pa (t = NaN in Tier 1 without display T)
  final Float64List liquidDown, vaporUp;  // L_j, V_j (mol/s)
  final Float64List entrain, weep;        // e_j, W_j
  final Float64List holdup, hcl, froth;   // M_j (mol), clear liquid (m), froth height (m)
  final Float64List dp, jetFlood, dcFlood, frothFill, stability, weepFrac, efficiency;
  final Float64List hetp, packFlood;      // packed segments (NaN on trays)
  final Uint8List flags;                  // bit 0 dcLimited, 1 dumping, 2 overflowing, 3 dry, 4 flooding
  double xAt(int stage, int comp);
}

@immutable
class Kpis {
  final double xD, xB;              // light component (binary) or LK in D / HK in B (multicomponent)
  final double d, b, refluxRatio, boilup, qc, qr, columnDp, maxFloodPct;
  final double maxWeepFrac;         // max over trays of the weeping fraction w_j (0 in ideal hydraulics); M2/M3
  final double drumLevelPct, sumpLevelPct, pTop;
  final double? recoveryLK, recoveryHK;                 // multicomponent
  final CrudeProductKpis? crude;                        // crude
  final double balanceResidual;     // |F z − D xD − B xB| / F z, light component (should → 0 at steady state)
  final double energyResidual;      // Tiers 2/3, relative
}
```

### 7.2 McCabe–Thiele data

```dart
class McCabeThieleBuilder {
  /// Caches the equilibrium curve per (system, tier, rounded P_top, rounded P_bottom).
  McCabeThieleData build(SimSnapshot s, ThermoModel thermo, {bool showRmin = false});
}

@immutable
class McCabeThieleData {
  final bool pseudoBinary;                   // true for multicomponent (Hengstebeck)
  final String lightLabel, heavyLabel;
  final List<Point2> equilibriumTop;         // at P_top (Tier 1: the single curve)
  final List<Point2>? equilibriumBottom;     // Tiers 2/3
  final List<Point2> localEquilibrium;       // (x_j, y*_j)
  final Segment2? qLine;                     // null if not defined
  final List<Point2> cmoRectifying, cmoStripping;   // dashed reference lines (2 points each)
  final List<Point2> operatingLocus;         // (x_j, y_{j+1})
  final List<Point2> staircase;              // polyline as PHYSICS.md §14.1
  final List<StageCorner> corners;           // (x_j, y_j, stage number, isFeed)
  final List<Point2> pseudoEquilibrium;
  final double xF, xD, xB;
  final RminConstruction? rmin;              // line + value when requested
  final List<RangeX> pinchZones;
  final bool transient;                      // steady-state monitor false
}
```

Builder rules are exactly PHYSICS.md §14.1–14.2. Cost target: ≤ 0.3 ms per build with a warm cache (Tier 2 curves are recomputed only when the pressures change by > 100 Pa or the tier changes).

### 7.3 Other derived data

```dart
/// Closed-form textbook utilities for a binary with constant alpha (used by scenarios, the overlay and VC-1/2/3).
abstract final class McCabeThieleMath {
  static double yEq(double x, double alpha);
  static ({double x, double y}) qLinePinch(double alpha, double z, double q);      // q-line ∩ equilibrium
  static double rMin(double alpha, double z, double q, double xD);                  // feed-pinch R_min
  static double fenskeNmin(double alpha, double xD, double xB);                     // stages incl. reboiler
  static ({double x, double y, double n}) gilliland(double nMin, double r, double rMin, {bool eduljee = false});
  static SteppingResult stepStages(double alpha, double z, double q, double xD, double xB, double r);
      // stage list (x, y), integer and fractional stage count, optimal feed stage (switch at the line intersection)
  static double lewisEo(double emv, double lambda);   static double lewisEmv(double eo, double lambda);
}
class ProfileData { static ProfileData from(SimSnapshot s); /* series per PHYSICS.md §14.5 */ }
class FugResult { final double nMin, theta, rMin, nGilliland, nrOverNs; final Float64List alpha, dToB; /* §14.3 */ }
class FugCalculator { FugResult compute(SimSnapshot s, KeyComponents keys, {FugTargets? targets}); }
class CrudeProductData { /* TBP & D86 curves per product, gaps, yields; PHYSICS.md §9.6 */ }
class TxyData { static TxyData build(ThermoModel m, double p); /* T-x-y and x-y, azeotrope markers */ }
```

---

## 8. Explain API (math overlay)

### 8.1 Types

```dart
sealed class ExplainTarget {}
class ExplainStage extends ExplainTarget { final int stage; final ComponentId? focusComponent; }
class ExplainStream extends ExplainTarget { final StreamId stream; }
class ExplainCondenser extends ExplainTarget {}
class ExplainReboiler extends ExplainTarget {}
class ExplainFeed extends ExplainTarget { final int feedIndex; }
class ExplainLoop extends ExplainTarget { final LoopTag tag; }
class ExplainMcCabe extends ExplainTarget { final McCabeElement element; } // opLine, qLine, rmin, fug…
class ExplainInstrument extends ExplainTarget { final String tag; }   // eq.instrument / eq.analyser
class ExplainValve extends ExplainTarget { final String valveId; }    // eq.valve
class ExplainCheck extends ExplainTarget { final String checkId; }    // eq.check.* (PHYSICS.md §14.6)
// In plant view only ExplainInstrument, ExplainValve, ExplainLoop and ExplainCheck are accepted;
// other targets return an ExplainResult with a single note "Not observable on a real plant".

@immutable
class ExplainResult {
  final String title;                         // "Tray 7 (rectifying section)"
  final List<EquationGroup> groups;           // e.g. "Material balance", "Equilibrium", "Hydraulics"
  final List<String> notes;                   // simplification notes (PHYSICS.md §16) relevant here
  final double time;                          // sim time of the state explained
}

@immutable
class EquationGroup { final String title; final List<EquationLine> lines; }

@immutable
class EquationLine {
  final String id;                 // PHYSICS.md §15 id, e.g. 'eq.bennett'
  final String physicsRef;         // e.g. 'PHYSICS.md (5.2)'
  final String texSymbolic;        // r"h_{cl} = \frac{M_j v_L}{A_a}"
  final String texSubstituted;     // r"h_{cl} = \frac{185.7 \times 1.064\times10^{-4}}{0.8595} = 0.0230"
  final double value;              // SI
  final Quantity quantity;         // for the display-unit echo
  final String? note;              // one short sentence, optional
}
```

### 8.2 How it works

- Every model function that appears in PHYSICS.md §15 has an optional `Trace? trace` parameter. When `trace` is null (the normal step) the function does nothing extra. When non-null it records `TraceItem`s (symbol name, SI value) as it computes.
- `Simulator.explain()` re-evaluates the relevant functions for the target on the **current state** with a `Trace`, then `EquationCatalog` turns the trace into `EquationLine`s using per-equation templates (`String Function(TraceValues v)` producing the TeX strings).
- Substitutions are always in SI (the equations are SI). The overlay additionally prints the result in the user's unit system, e.g. "= 0.0230 m (0.90 in)".
- Consistency rule (tested, VALIDATION.md VC-21): every `EquationLine.value` equals the corresponding value in the snapshot (same state) to 1×10⁻¹² relative, because the same code path computes both.
- Number formatting in TeX: 4 significant figures, scientific notation outside [1×10⁻³, 1×10⁵].
- `explain()` must complete in < 5 ms (one tray's worth of model evaluations).

---

## 9. Faults

```dart
enum FaultType { trayDamage, trayFouling, foaming, feedComposition, feedThermal, coolingLoss,
  condenserFouling, nonCondensables, refluxPumpTrip, reboilerFouling, condensateBackup,
  steamHeaderLoss, tsInletRestriction, tsOutletRestriction, instrument /* F19 */, transmitter /* F28 */,
  valve /* F20 */, packingMaldistribution, packingCrush, strippingSteamLoss, pumparoundTrip, cotUpset }

// Location and params for the control faults (PHYSICS.md §10.6), JSON form:
//   F19: {"type": "instrument",  "location": {"tag": "FT-102"}, "params": {"kind": "bias"|"drift"|"stuck", "sign": 1|-1}}
//   F28: {"type": "transmitter", "location": {"tag": "TI-114"},
//         "params": {"kind": "signalLossLow"|"signalLossHigh"|"signalLoss"(AT)|"plugged"|"spiking"|"coated"}}
//   F20: {"type": "valve",       "location": {"valve": "FV-102"}, "params": {"kind": "stuck"|"failOpen"|"failClosed"}}
// "sign" is required for bias/drift (1 = reads high). A kind that does not apply to the tag's type
// (e.g. coated on an FT) is a ConfigException. At most one F19/F28 fault per tag at a time
// (injecting a second replaces the first).
//   F07: {"type": "feedComposition", "params": {"dz": {"benzene": 0.08}, "sign": 1|-1|"random"}}
//        z ← normalise(z + sign · s · dz) (PHYSICS.md §11); "random" only inside drill candidates.

@immutable
class FaultSpec {
  final FaultType type;
  final FaultLocation location;        // stage range | loop/instrument tag | equipment id | packed bed index
  final double severity;               // s_f in (0, 1]
  final double onset;                  // sim time (s)
  final double ramp;                   // s; 0 = step
  final Map<String, Object?> params;   // e.g. {'mode': 'holes'}, {'kind': 'bias', 'sign': -1}, {'dz': {...}}
  final bool hidden;                   // drills: not reported in snapshots
}

class FaultManager {
  FaultId inject(FaultSpec spec);
  void clear(FaultId id);              // operator actions that clear (antifoam, trap bypass) call this with delays
  List<FaultInfo> get active;          // empty view for hidden faults
  EffectiveParams apply(double t, BaseParams base);   // PHYSICS.md §11 table; called at step start
}
```

`EffectiveParams` is a flat, preallocated parameter set (per-tray hole area, apron clearance, bypass fractions, SF, φ_dc, UA values, K_in/K_out, instrument biases, …) rebuilt into the same buffers every step; faults never mutate `ColumnConfig`.

---

## 10. Control system

Behaviour: PHYSICS.md §10 (M3 contract). The classes below are the binding shape.

```dart
enum LoopMode { man, auto, cas, iman }      // iman: master tracking a slave that is not in CAS
enum Action { direct, reverse }
enum ValveCharacteristic { linear, equalPercentage }

class PidParams {
  final double kc, ti, td;                  // ti = double.infinity disables integral
  final Action action;
  final bool spKick;                        // true for FC loops, false for LC/PC/TC (PHYSICS.md §10.2)
  final double opLo, opHi;                  // default 0, 100
}

class InstrumentSpec {                      // one row of the PHYSICS.md §10.5 table, per tag, from control_config
  final String tag;  final InstrumentType type;  final String measures;   // metric path, e.g. 'stream.reflux.flow'
  final double lo, hi;                      // span, SI
  final double tauM, sigmaS, tauS, sigmaE;  // σ in % of span
  final double? analyserPhase;              // AT only
}

class Instrument {                          // state of one transmitter; update(h, trueValue, t) = §10.5 pipeline
  final InstrumentSpec spec;
  // state: ns, vp, vm, frozen outputs, spike schedule, OOS timer, streams (PHYSICS.md §12.9)
  InstrumentReading get reading;
}

class Valve {
  final String id; final double fMax; final double tau;   // tau = 2.0 s
  final ValveCharacteristic characteristic;
  double position, command, bypass;  ValveFault fault;    // none | stuck | failOpen | failClosed
  double d;                                               // supply disturbance state
}

class ControlLoop {
  final LoopTag tag;
  final String pvTag;                       // instrument tag, e.g. 'FT-102'
  final String mvRef;                       // valve id, or 'FC-103.sp' for the TC-101 cascade
  final String? masterTag;                  // set on slaves (FC-103 ← TC-101)
  final PidParams params;
  final bool fastLayer;                     // FC loops: executed every δ_c sub-step
  LoopMode mode;  bool shed;  double sp, op;
}

class ControlSystem {
  List<ControlLoop> get loops;  List<Instrument> get instruments;  List<Valve> get valves;
  ControlLoop loop(LoopTag tag);
  void setMode(LoopTag tag, LoopMode mode); // bumpless per PHYSICS.md §10.2; throws StateError for AUTO/CAS on a BAD PV
                                            // and for iman (engine-internal only)
  void setSp(LoopTag tag, double sp);       // clamped to the SP limits; re-bases if !spKick
  void setOp(LoopTag tag, double op);       // MAN only; clamped to opLo..opHi
  /// PHYSICS.md §10.1 fast layer: n_c sub-steps; returns mean flows (F̄) per valve in [out].
  void runFastLayer(double dt, FastLayerInputs frozen, Float64List out);
  /// PHYSICS.md §10.1 main layer at step 12.
  void runMainLayer(double dt, MeasurementBus truth, double t);
}

class AlarmManager {                        // PHYSICS.md §10.8
  List<Alarm> get active;                   // every alarm not NORMAL
  void acknowledge(String id);  void acknowledgeAll();
  List<JournalEntry> get journal;           // raise / clear / ack / mode change / operator action, with sim time
}

class CrossCheckEngine {                    // PHYSICS.md §14.6; reads TrendBuffer bins only
  double window;                            // 300 | 600 | 1800 | 3600
  void setTemperatureReference(double t);
  List<CrossCheckResult> evaluate(TrendBuffer bins, LeverView levers, bool steady);
}
```

- Loop sets, instrument specs and valves per preset come from `control_config.dart`: PHYSICS.md §10.5 and §10.7 for B-T, a `temperatureTrays` list and the design molar volumes N_0,1%/N_S,1% for C5. Loops and instruments that do not exist in a tier are hidden (PC-101, TC-101, PT/TI/CW instruments in Tier 1).
- `MeasurementBus` maps metric paths to true values at the end of the step. Path names: `stream.<id>.flow`, `drum.levelPct`, `sump.levelPct`, `pTop`, `columnDp`, `stage[<j>].t`, `stream.distillate.x[<i>]`, `cw.flow`, `cw.tIn`, `cw.tOut`, `steam.headerP`, `reboiler.duty`.
- `saveState()` contains every field above, including PRNG stream states and the alarm journal, so save → restore → continue is bit-identical (VC-20.4).

---

## 11. Scenarios and drills

### 11.1 Scenario JSON schema

```json
{
  "id": "G2_min_reflux",
  "kind": "guided",
  "title": "Minimum reflux",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal", "murphree": 1.0,
                "sections[0].trays": 60, "feeds[0].stage": 30},
  "start": "steady",
  "noise": false,
  "levers": {
    "set": {"refluxMode": 1, "refluxRatio": 1.3, "boilup": 31.9444},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["refluxRatio", "boilup", "feedZ.benzene"]
  },
  "loops": {"LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}},
  "timeLimit": 86400,
  "parTime": 43200,
  "briefing": "Markdown text …",
  "objectives": [
    {"id": "o1", "text": "Hold xD ≥ 0.95 and xB ≤ 0.05 at steady state with R ≤ 1.20.",
     "when": {"all": [{"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "kpi.refluxRatio", "op": "<=", "value": 1.20},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 600},
    {"id": "o2", "text": "Report R_min.", "answer": {"type": "number", "correct": 1.10, "tolerance": 0.055}}
  ],
  "hints": [
    {"after": 0, "text": "Each time you change R, set boilup = 50 × (R + 1) kmol/h so that D stays at 50."},
    {"after": 14400, "text": "Watch the staircase near the q-line …"},
    {"when": {"metric": "kpi.refluxRatio", "op": "<", "value": 1.12}, "text": "You are close to the pinch …"}
  ],
  "events": [],
  "scoring": {"objectives": 60, "time": 20, "safety": 10, "quality": 10,
              "qualitySpec": {"metric": "kpi.xD", "op": ">=", "value": 0.95}},
  "debrief": "Markdown with live values: {kpi.refluxRatio:0.00}, {answer.o2:0.00} …"
}
```

(G2 used to start at R = 2.0. With 60 equilibrium stages the products are then 0.9999999 pure and the steady-state monitor does not pass for days of sim time. From R = 1.3, the column is steady 10 h after a cold start and 2.8–4.4 h after each step down; numbers in §11.8.)

**Top-level fields**

| Field | Type | Default | Meaning |
|---|---|---|---|
| `id`, `kind`, `title`, `topic`, `milestone` | string / `"guided"`\|`"drill"` / string / string / int | required | |
| `preset`, `overrides` | PresetId, map | required, {} | `overrides` uses dotted/indexed paths into `ColumnConfig` JSON (`ColumnConfig.applyOverrides`) |
| `start` | `"steady"` \| `"cold"` | required | `steady`: run to steady state from cold with `levers.set` applied, noise off, memoised per (preset, overrides, levers.set); then t := 0 |
| `noise` | bool | false | value of the `noise` lever from t = 0 |
| `view` | `"model"` \| `"plant"` | `"model"` | `view` lever (PHYSICS.md §10.9) |
| `badPvShed` | bool | true | `badPvShed` lever (PHYSICS.md §10.2) |
| `levers.set` | map LeverId → SI value | {} | applied **before** the steady start |
| `levers.lock` | list | [] | shown read-only |
| `levers.show` | list | all | only these levers (plus the OP levers bound to them) appear in the Levers tab |
| `loops` | map tag → `{mode, sp?, op?}` | {} | applied after the steady start, in tag order |
| `timeLimit` | s | required | the scenario ends automatically |
| `parTime` | s | 0.25 × timeLimit | time-score reference (§11.4) |
| `briefing`, `debrief` | Markdown (debrief: template, §11.4) | required | |
| `objectives` | list | required for guided; absent for drills | |
| `hints`, `events` | list | [] | |
| `scoring` | object | required | §11.4 |

Start order: config with overrides → levers.set → steady start (or cold) → loops → `noise`, `view`, `badPvShed` → t = 0 → events at 0 → draws (drills, §11.2).

**Objectives**

| Field | Meaning |
|---|---|
| `id`, `text` | |
| `when` | Predicate. The objective is met once it has held continuously for `holdFor` s (default 0); the hold clock resets whenever it is false |
| `after` | Id of another objective. This one is not evaluated before that one is met (sequencing, e.g. G4) |
| `weight` | Default 1 |
| `answer` | Instead of `when`: met when a correct answer is submitted |

Objectives latch: once met they stay met.

**Answers**
- `{"type": "number", "correct": x, "tolerance": t, "toleranceKind": "abs"|"rel", "quantity": "<Quantity>"}`. The learner types in display units; the value is converted to SI before comparison. The default quantity is dimensionless.
- `{"type": "choice", "options": ["…", "…"], "correct": i}`.
- `{"type": "stage", "correct": [j, …]}`: the learner taps a stage on the column or a staircase corner, numbered as in PHYSICS.md §0.2.
- `attempts` defaults to 3. Wrong answers cost nothing, but after the last wrong attempt the objective can no longer be met. The submitted value of objective `o2` is readable as metric `answer.o2`.

**Predicates** (no expression language):
- Composites: `{"all": [...]}`, `{"any": [...]}`, `{"not": {...}}`.
- Leaves: `{"metric": path, "op": "<"|"<="|"=="|">="|">"|"!=", "value": v}` and `{"metric": path, "op": "between", "lo": a, "hi": b}`. `v` is a number or a bool. For `mode` and `quality` metrics it is a string, and only `==` and `!=` are allowed.
- Optional `"from": "start"` on a leaf compares (current value − value at t = 0) instead of the value itself.
- Numbers are SI. Booleans compare `true`/`false`. A NaN metric makes every comparison false, except `!=`.

**Metric paths**
- `time`, `steady`
- `kpi.<field>`: always the **true** model value, also in plant view. Fields: xD, xB, d, b, refluxRatio, boilup, qc, qr, columnDp, maxFloodPct, maxWeepFrac (new in M2/M3: max over trays of w_j), drumLevelPct, sumpLevelPct, pTop, recoveryLK, recoveryHK, balanceResidual.
- `stage[<j>].<t|p|x|holdup|weepFrac|jetFlood>` (x = light component)
- `loop[<tag>].<pv|sp|op|mode>` (pv is the reading)
- `instrument[<tag>].<value|quality>`
- `valve[<id>].<op|position>`
- `check[<id>].<residual|status>`
- `condenser.<drumLevelPct|qc>`, `reboiler.<qr|steamValveOp>`
- `alarm.count`, `alarm[<id>].active`
- `safety.reliefLifted`, `safety.levelViolationSeconds`
- `answer.<objectiveId>`, `lever.<id>`

An unknown path is a schema-test failure.

**Hints**: `{"after": s}` (absolute scenario time) or `{"when": predicate}`, plus `"text"` and `"cost"` (points deducted when the learner opens the hint; default 0 for guided, 3 for drills). A hint becomes available when its condition is met, and is charged once.

**Events**

| Field | Meaning |
|---|---|
| `id` | Optional, for `clearFault` |
| Timing | `{"at": s}`, `{"atRandom": [lo, hi]}` (stream `scenario:events`, drawn at t = 0 in event order), or `{"when": predicate}` (fires once) |
| `action` | `setLever` (`lever`, `value` or `delta`), `setLoopMode` (`loop`, `mode`), `setSp` (`loop`, `value` or `delta`), `injectFault` (`fault`: FaultSpec JSON), `clearFault` (`faultRef`: event id), `message` |
| `message` | Optional text shown with any action (the timeline and HUD show it) |

`delta` is an SI increment applied to the current value. A `setSp` on a loop in MAN stores the SP (PHYSICS.md §10.2).

### 11.2 Drill JSON (extends §11.1)

```json
{
  "id": "H2_pressure",
  "kind": "drill",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": true,
  "candidates": [
    {"id": "cw_temp", "weight": 1,
     "fault": {"type": "coolingLoss", "params": {"mode": "temperature"}, "severityRange": [0.6, 1.0], "ramp": 1800},
     "answer": {"category": "cooling", "location": "condenser"}, "debrief": "…"},
    {"id": "cond_foul", "weight": 1,
     "fault": {"type": "condenserFouling", "severityRange": [0.7, 1.0], "ramp": 7200},
     "answer": {"category": "fouling", "location": "condenser"}, "debrief": "…"},
    {"id": "inerts", "weight": 1,
     "fault": {"type": "nonCondensables", "severityRange": [0.5, 1.0], "ramp": 0},
     "answer": {"category": "inerts", "location": "condenser"}, "debrief": "…"}
  ],
  "onsetWindow": [600, 2400],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "diagnosis": {
    "categories": ["cooling", "fouling", "inerts", "foaming", "trayDamage", "instrument", "valve",
                   "feedUpset", "steam", "thermosyphon", "maldistribution", "none"],
    "locations": ["condenser", "reboiler", "rectifying", "stripping", "feed", "instrument:*", "valve:*", "packedBed"],
    "modes": [],
    "attempts": 2
  },
  "scoring": {"category": 50, "location": 20, "time": 20, "safety": 10, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 10, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "timeLimit": 14400
}
```

**Candidate fields**

| Field | Meaning |
|---|---|
| `id` | |
| `weight` | > 0; 0 disables the candidate |
| `fault` | A FaultSpec (§9) with `severityRange: [lo, hi]` instead of `severity`, no `onset` (it is drawn), and `params.sign` allowed as `"random"` |
| `answer` | `{category, location, mode?}` |
| `protect` | Optional list of `{"loop": tag, "modes": [...]}`. The MAN-before-off-spec bonus is earned when, at some time t with t₀ ≤ t < t_os, any listed loop is in one of its listed modes |
| `debrief` | Markdown template shown when this candidate was drawn |

**Diagnosis**
- Locations `"instrument:*"` and `"valve:*"` expand to every instrument tag and valve id visible in the drill, in tag order.
- `modes` lists the failure-mode choices offered when the category is `instrument`: `bias`, `drift`, `stuck`, `signalLoss`, `plugged`, `spiking`, `coated`. An empty list hides the mode question.
- The `Diagnosis` object is `{category, location, mode?}`.

**Draw procedure** (reproducible). The stream is `drill` (PHYSICS.md §12.9), seeded with the attempt seed, which is `SimOptions.seed`. The app makes a new seed per attempt and stores it with the attempt, so a drill can be replayed. Exactly four uniforms are drawn at t = 0, whatever the outcome:
1. u0 selects the candidate: the first i with u0 · Σw < Σ_{k ≤ i} w_k, in listed order.
2. u1 sets the severity s = lo + u1 (hi − lo).
3. u2 sets the onset t₀ = dt · floor((a + u2 (b − a))/dt) for `onsetWindow` [a, b].
4. u3 sets the sign = −1 if u3 < 0.5, else +1 (used when `sign` is `"random"`).

The fault is injected with `hidden: true` at t₀. Snapshots carry no fault data, the `drill` stream is not exposed, and the debrief template is resolved only after the drill ends.

**Off-spec time** t_os is the first time ≥ t₀ at which `offSpec.when` has held for `holdFor` s, or ∞ if that never happens. Predicates use true values.

**Drill end**: a fully correct diagnosis, the last attempt used, the time limit, or "Give up". After a fully correct diagnosis the simulation pauses and the debrief opens.

### 11.3 Runner

```dart
class ScenarioDef { factory ScenarioDef.fromJson(Map<String, Object?> j); List<String> validate(ComponentDb db); }
class ScenarioRunner {
  ScenarioRunner(ScenarioDef def, Simulator sim);   // performs the start order of §11.1 and the drill draws
  void update();                                    // after each step (PHYSICS.md §12.4 step 13): events, objectives,
                                                    // hints, off-spec clock, protect clock, safety accumulators
  List<ObjectiveState> get objectives;
  List<HintState> get hints;
  void takeHint(int index);
  AnswerResult submitAnswer(String objectiveId, Object answer);
  DrillResult submitDiagnosis(Diagnosis d);         // {fullyCorrect, categoryOk, locationOk, attemptsLeft}
  ScoreCard finish();                               // §11.4; resolves the debrief template
}
```

`validate()` checks that every metric path, lever id, loop tag, instrument tag, valve id, fault type/kind combination, objective reference and template variable exists. It also checks that candidate weights sum to > 0 and that `onsetWindow[1] + 3600 ≤ timeLimit`. The schema test (VC-26.1) runs `validate()` on every shipped scenario.

### 11.4 Scoring (exact)

**Guided**, on a 0–100 scale; the weights come from `scoring`:

```
W   = Σ weight of all objectives ;  Wm = Σ weight of the met objectives
O   = objectives · Wm / W
T   = time · (Wm / W) · clamp( 1 − (t_end − parTime)/(timeLimit − parTime), 0, 1 )      (t_end = finish time)
S   = safety · ( 1 − ½ [relief ever lifted] − ½ [true drum or sump level < 5 % or > 95 % for > 60 s in total] )
Q   = quality · ( 1 − min(1, 2 f_os) ),  f_os = time with qualitySpec false / t_end   (Q = quality if no qualitySpec)
H   = Σ cost of opened hints
Score = round( clamp(O + T + S + Q − H, 0, 100) )
```

**Drills**:

```
Attempt a: C_a = category · [category ok],  L_a = location · [location ok]; "fully correct" = both ok
f   = the first fully correct attempt, else the last attempt made
P   = wrongPenalty × (number of attempts made that were not fully correct)
C   = C_f ,  L = L_f   (0 and 0 if no attempt was made)
T   = time · clamp( 1 − (max(0, t_f − t₀) − timeFull)/(timeZero − timeFull), 0, 1 )  if f is fully correct, else 0
S   = as guided
B   = bonus.protectBeforeOffSpec · [candidate has `protect` and it was met for some t, t₀ ≤ t < min(t_os, t_f)]
    + bonus.mode · [f fully correct and Diagnosis.mode == answer.mode]
H   = Σ cost of opened hints
Score = round( clamp(C + L + T + S + B − P − H, 0, 100) )
```

The ScoreCard lists every term, t₀, t_os, the protect time and each attempt, so the debrief can show them. SCOPE.md §6.2 states the same weights in words.

**Debrief templates.** `{path}` prints a metric (§11.1 paths, at finish time) with `Fmt.value` and units in the user's unit system. `{path:0.00}` prints fixed decimals without a unit. `{path:time}` prints h:mm:ss of sim time ("never" for ∞). Drills add:
- `fault.tag`, `fault.valve`, `fault.mode`, `fault.severity`, `fault.sign` ("+" / "−")
- `fault.magnitude`: the bias in display units with sign, the drift per hour, or the severity
- `fault.onset`
- `result.offSpecTime`, `result.protectTime`, `result.diagnosisTime`, `result.firstFlaggedCheck` (id and time of the first cross-check that went `fail` after t₀)

### 11.5 Drill design rules (noise on, played on a phone)

Every candidate in a drill must satisfy these rules. VALIDATION.md §H tests them with noise **on**, at the minimum severity of each range.

1. **Signal-to-noise.** Within 20 min of t₀ (for drifts: of t₀ plus 10 min), the key evidence reaches at least one of the following with the default 600-s window:
   - a cross-check residual ≥ 2 × its band (status `fail`) held for ≥ 60 s;
   - a signal-look ratio σ_5min/σ_disp ≤ 0.2 (frozen or too steady) or ≥ 5 (erratic);
   - a BAD alarm.

   The minimum magnitudes that follow from the PHYSICS.md §14.6 bands are:
   - flow-meter bias ≥ 4 % of span;
   - flow drift ≥ 6 % of span per hour;
   - level bias ≥ 8 % (paired with a field gauge);
   - PT bias ≥ 3 % of span (6 kPa on PT-101, so C7 moves by 2 K);
   - TI bias ≥ 5 K;
   - plugged s ≥ 0.85.
2. **One screen.** The evidence must be readable on one compact-portrait screen: a Balance-tab row, a faceplate with its signal look and valve curve, one trend, or the C6 chart. Nothing may require the learner to overlay two trends.
3. **Persistence.** Evidence that only exists for one window after onset (level bias) must have a second, permanent source (the field gauge, or the LC output move in the trend history).
4. **Time.** `onsetWindow[1] + 3600 ≤ timeLimit`, so a learner gets at least an hour after the latest onset.
5. **Hints** point at a check or a habit, never at a tag. Their costs make a guess cheaper than three hints only if the guess is right.
6. **Decoys.** A drill whose title asks "process or instrument?" must contain at least one candidate whose answer is a process fault. Otherwise the category question answers itself.
7. **Disturbance events.** Fixed-time events that reveal frozen or slow sensors must not, by themselves, make the product go off-spec. VALIDATION.md §H checks this with a healthy run.

### 11.6 Drill H9 "Don't trust the gauge" (M6)

```json
{
  "id": "H9_dont_trust_the_gauge",
  "kind": "drill",
  "title": "Don't trust the gauge",
  "milestone": 6,
  "topic": "instruments",
  "preset": "bt",
  "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": true,
  "view": "plant",
  "badPvShed": false,
  "levers": {
    "set": {"tc101Enable": 1, "tc101Tray": 14},
    "lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Tray"]
  },
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "cas"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"},
            "TC-101": {"mode": "auto"}},
  "timeLimit": 7200,
  "briefing": "You are taking over the board of the benzene–toluene column. Every loop is in AUTO and tray-14 temperature control (TC-101) sets the reboiler duty through FC-103. At some point during your shift either **one instrument starts lying** or **the process really changes**. Decide which, name the tag if it is an instrument, and keep the products on spec while you work it out.\n\nThis plant's old DCS does **not** put a loop in manual when its signal fails. Your tools: the **Balance** tab (every check uses meters only), each faceplate's **signal look** and **valve curve**, the trends, the temperature-profile chart with its reference, and **field checks** of the sight glasses LG-101 and LG-102 and the local gauge PG-101 (3 minutes each). You have two diagnosis attempts.",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "ft102_bias", "weight": 2,
     "fault": {"type": "instrument", "location": {"tag": "FT-102"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.7], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-102", "mode": "bias"},
     "protect": [{"loop": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102 (reflux flow) read {fault.magnitude} wrong from {fault.onset:time}.** FC-102 kept the *reading* at its set point, so the real reflux moved the other way by the same amount. The tell-tales: C4 for FV-102 went red (the valve's OP no longer matched the flow it should give), and C3 (vapour to the top: reboiler vs reflux + distillate) disagreed by the same amount, while every other check stayed green. The trend itself looked normal — a bias has normal noise. Right response: FC-102 to MAN, then set the OP from the valve curve, for example {valve[FV-102].op:0.0} %."},
    {"id": "ft102_plugged", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "FT-102"}, "params": {"kind": "plugged"}, "severityRange": [0.9, 1.0], "ramp": 300},
     "answer": {"category": "instrument", "location": "instrument:FT-102", "mode": "plugged"},
     "protect": [{"loop": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102's impulse line plugged at {fault.onset:time}.** The reading stopped following the process: its 5-minute σ dropped from about 1.2 kmol/h to under 0.1 (\"too steady\"). FC-102 then kept integrating the small offset between its set point and the trapped value, and walked the real reflux far away while the reading sat on the set point. C4 (FV-102) and C3 both failed. A stuck *valve* would have looked similar on the OP trend, but its flow reading would still have had normal noise and the balances would have agreed."},
    {"id": "ft101_drift", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-101"}, "params": {"kind": "drift", "sign": "random"}, "severityRange": [0.6, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-101", "mode": "drift"},
     "protect": [{"loop": "FC-101", "modes": ["man"]}],
     "debrief": "**FT-101 (feed flow) drifted by {fault.magnitude} per hour from {fault.onset:time}.** FC-101 held the reading, so the real feed walked away. C1 (feed in vs distillate + bottoms out) grew steadily, and so did C4 for FV-101. The sump level-vs-flows check (C5) failed in proportion to the window: drifts show best with a 30-min window."},
    {"id": "ft103_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-103"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.6], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-103", "mode": "bias"},
     "debrief": "**FT-103 (steam / reboiler duty) read {fault.magnitude} wrong from {fault.onset:time}.** This one hides well: TC-101 sets FC-103's set point from the tray-14 temperature, so it trimmed the duty set point until the real duty was right again — the product barely moved. The evidence is the energy balance: C3b (reboiler duty vs condenser duty + products) failed, and FV-103's OP did not match the duty it should give (C4). With temperature control in the loop, the right response is to *keep* the cascade and get the meter fixed."},
    {"id": "lt101_bias", "weight": 2,
     "fault": {"type": "instrument", "location": {"tag": "LT-101"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.8, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-101", "mode": "bias"},
     "protect": [{"loop": "LC-101", "modes": ["man"]}],
     "debrief": "**LT-101 (reflux drum level) read {fault.magnitude} wrong from {fault.onset:time}.** The reading jumped with no flow change to explain it. LC-101 then moved the distillate flow to bring the *reading* back to its set point, which shifted the real level by the same amount. C5 (drum level vs integrated flows) failed for one window after the jump, and the sight glass LG-101 disagreed with LT-101 at any time afterwards. That field check is the permanent proof."},
    {"id": "lt102_loss", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "LT-102"}, "params": {"kind": "signalLossLow"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-102", "mode": "signalLoss"},
     "protect": [{"loop": "LC-102", "modes": ["man"]}],
     "debrief": "**LT-102 (sump level) lost its signal at {fault.onset:time}.** The DCS flagged BAD PV (IOP−) at once. This plant does not shed the loop, so LC-102 saw −2.5 % and closed the bottoms valve, and the real sump began to fill. Diagnosis was the easy part; the score was in the response. LC-102 to MAN at the old OP within minutes, then LG-102 field checks to steer the level by hand."},
    {"id": "lt102_stuck", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "LT-102"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-102", "mode": "stuck"},
     "protect": [{"loop": "LC-102", "modes": ["man"]}],
     "debrief": "**LT-102 froze at {fault.onset:time}.** The trend became a perfectly flat line — the same digits for minutes, σ = 0 against a typical 0.8 %. LC-102 stopped correcting, so when the feed went up at 45 min the real sump level started to climb while the reading stayed put. C5 for the sump failed from then on."},
    {"id": "pt101_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "PT-101"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.3, 0.5], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:PT-101", "mode": "bias"},
     "protect": [{"loop": "PC-101", "modes": ["man"]}],
     "debrief": "**PT-101 (top pressure) read {fault.magnitude} wrong from {fault.onset:time}.** PC-101 moved the real pressure the other way, so every temperature shifted together, smoothly — that looks like a process change. What gave it away was C7: the drum temperature and the bottom temperature no longer matched the bubble points of the analysed products *at the measured pressure*, both off with the same sign (about 0.33 K per kPa). The local gauge PG-101 confirmed it."},
    {"id": "ti114_bias", "weight": 2,
     "fault": {"type": "instrument", "location": {"tag": "TI-114"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.25, 0.4], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:TI-114", "mode": "bias"},
     "protect": [{"loop": "TC-101", "modes": ["man"]}, {"loop": "FC-103", "modes": ["auto", "man"]}],
     "debrief": "**TI-114 read {fault.magnitude} wrong from {fault.onset:time}.** It is TC-101's measurement, so TC-101 moved the reboiler duty until the *reading* was back at its set point. The real stripping section was then several kelvin off, and the bottoms followed. In C6, TI-114's change since the reference sat near zero while TI-112 and TI-117 moved together: a lone bar in a quiet neighbourhood. Right response: break the cascade (TC-101 to MAN, or FC-103 to AUTO) and hold the duty."},
    {"id": "ti114_coated", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "TI-114"}, "params": {"kind": "coated"}, "severityRange": [0.8, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:TI-114", "mode": "coated"},
     "protect": [{"loop": "TC-101", "modes": ["man"]}, {"loop": "FC-103", "modes": ["auto", "man"]}],
     "debrief": "**TI-114's thermowell coated over from {fault.onset:time}:** its time constant went from 10 s to 10 × (1 + 9 × {fault.severity:0.00}) s. At steady state it reads right, so the evidence only appears in transients. When the feed rose at 45 min, TI-114 lagged its neighbours in C6 and TC-101 started to swing the duty. The fuzz on TI-114 also halved (signal look ≈ 0.5 of typical)."},
    {"id": "ti107_spiking", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "TI-107"}, "params": {"kind": "spiking"}, "severityRange": [0.5, 0.8], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:TI-107", "mode": "spiking"},
     "debrief": "**TI-107 went erratic at {fault.onset:time}:** spikes of tens of kelvin, several a minute, with BAD flickers. It controls nothing, so the process never noticed. The signal look (σ many times typical) and C6 flagged it at once."},
    {"id": "ft104_stuck", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-104"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-104", "mode": "stuck"},
     "debrief": "**FT-104 (distillate flow) froze at {fault.onset:time}.** It controls nothing in flow mode, so the column was fine. But the flat line (σ = 0) and the balances told the story: once LC-101 moved the real distillate after the feed change, C1 and C3 disagreed while C4 for LV-101 showed the valve moving with no change in the reading."},
    {"id": "feed_real", "weight": 2,
     "fault": {"type": "feedComposition", "params": {"dz": {"benzene": 0.08}, "sign": "random"}, "severityRange": [1.0, 1.0], "ramp": 900},
     "answer": {"category": "feedUpset", "location": "feed"},
     "debrief": "**Nothing was lying — the feed really changed** by {fault.sign}0.08 benzene from {fault.onset:time}, over 15 minutes. Every balance stayed green, the temperature profile moved as a smooth wave (C6, no lone bar), and the feed analyser AT-100 showed the change about 7–10 minutes later. When all the cross-checks agree, believe the instruments."}
  ],
  "events": [
    {"id": "feed_up", "at": 2700, "action": "setSp", "loop": "FC-101", "delta": 1.38889,
     "message": "Upstream raised the feed: FC-101 set point +5 kmol/h."}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1200, "cost": 3, "text": "Open the **Balance** tab. Each row uses only meters. When a row turns red, ask which instruments feed it — the liar is one of them, unless a valve is involved."},
    {"after": 2400, "cost": 3, "text": "Check every loop's **valve curve** (C4). A lying flow meter fails its own valve check *and* a balance; a real process change fails neither."},
    {"after": 3300, "cost": 3, "text": "Look at the **signal look** on each faceplate: σ = 0 means frozen, far below typical means plugged, far above means erratic. For temperatures, compare each TI's change since the reference with its neighbours (C6)."},
    {"after": 4200, "cost": 3, "text": "Levels and pressure have field gauges. A field check takes 3 minutes and settles any argument about LT-101, LT-102 or PT-101."}
  ],
  "diagnosis": {
    "categories": ["instrument", "valve", "feedUpset", "fouling", "foaming", "trayDamage", "none"],
    "locations": ["instrument:*", "valve:*", "feed", "rectifying", "stripping", "reboiler", "condenser"],
    "modes": ["bias", "drift", "stuck", "signalLoss", "plugged", "spiking", "coated"],
    "attempts": 2
  },
  "scoring": {"category": 50, "location": 20, "time": 20, "safety": 10, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 10, "bonus": {"protectBeforeOffSpec": 10, "mode": 5}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; product off-spec: {result.offSpecTime:time}; affected loop protected: {result.protectTime:time}; diagnosed: {result.diagnosisTime:time}."
}
```

Notes:
- **Tier 2, not "T1 or T2".** Tier 1 has no temperatures or pressure, so the TI and PT candidates and checks C3b, C6 and C7 need Tier 2. SCOPE.md §6.2 is changed accordingly.
- **The decoy** (`feed_real`, weight 2 of 17, about 12 %) makes the "process or instrument?" choice real (rule 6 of §11.5).
- **Bonus.** The protect bonus is available in 9 of the 13 draws: those where the lying tag is a loop PV and putting that loop in MAN is the right response. For `ft103_bias` the cascade protects the product by itself, so there is no bonus and no penalty.
- **Feed event.** The +5 % feed step at 45 min exists so that frozen, plugged and coated sensors get a change they fail to follow. It is never later than 15 min after the latest onset. VALIDATION.md H9.0 checks that, with no fault, it does not trip the off-spec test.

### 11.7 Drill H10 "Bad valve or bad meter?" (M6)

```json
{
  "id": "H10_valve_or_meter",
  "kind": "drill",
  "title": "Bad valve or bad meter?",
  "milestone": 6,
  "topic": "instruments",
  "preset": "bt",
  "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": true,
  "view": "plant",
  "badPvShed": true,
  "levers": {"lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 7200,
  "briefing": "The reflux and steam loops on this column have been acting up. The night shift wrote: *\"FC-102 and FC-103 — one of them doesn't do what it says.\"* Maybe a control valve is sticking, maybe a flow meter is lying, maybe the feed changed and nobody told you. At 45 minutes planning will raise the reflux and duty set points by 5 %. Find out which it is: valve, meter or process.",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "fv102_stuck", "weight": 2,
     "fault": {"type": "valve", "location": {"valve": "FV-102"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "valve", "location": "valve:FV-102"},
     "protect": [{"loop": "FC-102", "modes": ["man"]}],
     "debrief": "**The reflux valve FV-102 stuck at {fault.onset:time}.** FC-102's OP started to wander, and later ran off when planning raised the set point, while the flow reading stayed within its normal noise of its old value. The flow *reading* was honest: it still had normal noise, and C3 (top vapour) and C1 stayed green. Only C4 for FV-102 failed — an OP that no longer matches the flow. The fix is the bypass: open `bypass.FV-102` and set the reflux by hand."},
    {"id": "fv103_stuck", "weight": 2,
     "fault": {"type": "valve", "location": {"valve": "FV-103"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "valve", "location": "valve:FV-103"},
     "protect": [{"loop": "FC-103", "modes": ["man"]}],
     "debrief": "**The steam valve FV-103 stuck at {fault.onset:time}.** FC-103's OP wandered and then ran to its limit when the duty set point went up, but the duty reading did not follow. The duty meter was honest: normal noise, and the energy balance C3b green. Only C4 for FV-103 failed."},
    {"id": "ft102_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-102"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.7], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-102"},
     "protect": [{"loop": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102 read {fault.magnitude} wrong from {fault.onset:time}.** The valve was fine and moved as told, but FC-102 controlled a lie, so the real reflux was off by that amount. Two checks failed together: C4 for FV-102 (OP vs flow) *and* C3/C3a (reflux + distillate vs condenser duty). A sticking valve fails only the first."},
    {"id": "ft102_plugged", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "FT-102"}, "params": {"kind": "plugged"}, "severityRange": [0.9, 1.0], "ramp": 300},
     "answer": {"category": "instrument", "location": "instrument:FT-102"},
     "protect": [{"loop": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102's impulse line plugged at {fault.onset:time}.** On the OP trend this looks exactly like a stuck valve: OP moving, reading flat. The difference was the *noise*: the reading became far too smooth (σ under a tenth of typical) and the balances disagreed. With a stuck valve the meter keeps its normal noise and the balances agree."},
    {"id": "ft103_drift", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-103"}, "params": {"kind": "drift", "sign": "random"}, "severityRange": [0.6, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-103"},
     "protect": [{"loop": "FC-103", "modes": ["man"]}],
     "debrief": "**FT-103 (duty) drifted by {fault.magnitude} per hour from {fault.onset:time}.** FC-103 held the reading, so the real duty crept away. The energy balance C3b and FV-103's valve curve (C4) both diverged steadily — a meter fault, not a valve fault."},
    {"id": "ft103_plugged", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "FT-103"}, "params": {"kind": "plugged"}, "severityRange": [0.9, 1.0], "ramp": 300},
     "answer": {"category": "instrument", "location": "instrument:FT-103"},
     "protect": [{"loop": "FC-103", "modes": ["man"]}],
     "debrief": "**FT-103's impulse line plugged at {fault.onset:time}.** As with FT-102, the OP moved while the reading stayed flat, but the reading was too smooth, and C3b failed as the real duty wandered."},
    {"id": "feed_real", "weight": 2,
     "fault": {"type": "feedComposition", "params": {"dz": {"benzene": 0.10}, "sign": "random"}, "severityRange": [1.0, 1.0], "ramp": 600},
     "answer": {"category": "feedUpset", "location": "feed"},
     "debrief": "**Valves and meters were fine — the feed changed** by {fault.sign}0.10 benzene from {fault.onset:time}. All the C4 valve curves stayed on their lines, the balances closed, and AT-100 showed the new feed about 7–10 minutes later. The products moved because the column was separating a different feed."}
  ],
  "events": [
    {"id": "planning", "at": 2700, "action": "setSp", "loop": "FC-102", "delta": 1.38889,
     "message": "Planning: reflux +5 kmol/h and duty +65 kW to firm up the distillate."},
    {"at": 2700, "action": "setSp", "loop": "FC-103", "delta": 65000}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1200, "cost": 3, "text": "For FC-102 and FC-103, open the faceplate's **valve curve** (C4). Is the operating point on the line?"},
    {"after": 2400, "cost": 3, "text": "A point off the valve line means the valve *or* the meter. Now look at the balances (C3a, C3b): an honest meter keeps them green."},
    {"after": 3600, "cost": 3, "text": "Compare the noise on the suspect flow with its typical value. Sticking valves leave the meter's noise alone; plugged meters go quiet."}
  ],
  "diagnosis": {
    "categories": ["valve", "instrument", "feedUpset", "steam", "fouling", "none"],
    "locations": ["valve:FV-102", "valve:FV-103", "instrument:FT-102", "instrument:FT-103", "instrument:FT-104",
                  "instrument:AT-100", "feed", "reboiler", "condenser"],
    "modes": [],
    "attempts": 2
  },
  "scoring": {"category": 50, "location": 20, "time": 20, "safety": 10, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 10, "bonus": {"protectBeforeOffSpec": 10, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; product off-spec: {result.offSpecTime:time}; loop protected: {result.protectTime:time}; diagnosed: {result.diagnosisTime:time}."
}
```

Notes:
- The planning event (reflux and duty +5 %) moves both products *toward* purity, so it cannot trip the off-spec test by itself (VALIDATION.md H10.0). It forces both valves to move, which turns a quietly stuck valve into an obvious one.
- A stuck valve and a plugged meter look the same on the OP trend. The candidates are paired on purpose, so that the noise and balance checks are what decide.

### 11.8 Guided scenarios: objective definitions and reference numbers

All of these are Tier 1 B-T with ideal hydraulics unless stated, `noise: false`, model view. Reference numbers marked [P] were computed with the committed M1 engine (2026-10-12) and are checked by VC-26.4.

| Id | Start | Objectives (predicates in shorthand) | Hints (essentials) | Reference numbers |
|---|---|---|---|---|
| G1 Meet the column | `cold`; murphree 1.0 | o1 `steady == true`; o2 answer `stage`: "Tap the feed stage on the McCabe–Thiele diagram" correct [10] | "Use 300× and watch the staircase settle"; "The feed stage is where the staircase switches lines" | Steady after 2.5–6 h (VC-7.4) |
| G2 Minimum reflux | as §11.1 (60 trays, feed 30, E = 1, ratio mode, R = 1.3, boilup 115 kmol/h) | o1 xD ≥ 0.95 ∧ xB ≤ 0.05 ∧ R ≤ 1.20 ∧ steady, hold 600 s; o2 number R_min = 1.10 ± 0.055 | "boilup = 50 (R + 1)"; pinch hint | [P] xD at steady state: R 1.30 → 0.99279, 1.20 → 0.97142, 1.15 → 0.96071, 1.12 → 0.95429, 1.105 → 0.95107; 60 trays reach xD = 0.95 at R = 1.1000. Steady 10.2 h from cold at R = 1.3; 4.4, 3.5, 3.1, 2.8 h after each step down. Time limit 86 400 s, par 43 200 s |
| G3 Total reflux and Fenske | `steady`; trays 5, feed 3, E = 1 | o1 lever.feedFlow ≤ 0.001 ∧ loop[LC-101].mode == man ∧ loop[LC-101].op ≤ 0.1 ∧ loop[LC-102].mode == man ∧ loop[LC-102].op ≤ 0.1 ∧ steady, hold 300 s; o2 number N_min = 6.0 ± 0.05 | "With nothing leaving, reflux must equal boilup"; Fenske formula | VC-3.2: 6.0000 |
| G4 The q-line | `steady` (defaults) | o1 lever.feedQ between 1.19 and 1.21 ∧ xD ≥ 0.95 ∧ xB ≤ 0.05 ∧ steady ∧ kpi.boilup ≤ 1.05 V_min(1.2), hold 300; o2 (after o1) the same at q = 1.0; o3 (after o2) at q = 0.5; o4 (after o3) at q = 0; o5 choice "Where does the q-line pivot?" → "(z, z) on the diagonal" | "Keep D = 50: reflux = boilup + (1 − q) × 100 − 50 kmol/h" | [P] minimum boilup (D = 50, specs exactly met): q 1.2 → V_B 129.0, L₀ 59.0; q 1.0 → 115.5, 65.5; q 0.5 → 87.05, 87.05; q 0 → 66.96, 116.96 kmol/h. Limit 172 800 s |
| G5 Where to feed | `steady` (defaults) | o1 answer `stage`/number: "Which feed tray gives the highest xD?" correct [11]; o2 feedStage == 11 ∧ steady, hold 300 | "The optimum is where the staircase crosses the operating-line intersection" | VC-4.14 scan (x_D 0.98203 at tray 11). Limit 172 800 s |
| G6 Real trays (Murphree) | `steady`; murphree 0.5 (locked), feedStage locked (it follows the fractional rule of PHYSICS.md §13.4) | o1 xD ≥ 0.98 ∧ steady, hold 300; o2 number "fewest trays that reached 0.98" = 28 ± 1; o3 choice "What stays about constant?" → "N × E (the equilibrium stages)" | "Add trays a few at a time" | [P] E = 0.5: N 20 → 0.95331, 24 → 0.96968, 26 → 0.97568, 27 → 0.97761, **28 (feed 14) → 0.98056**. 20 × 0.7 = 28 × 0.5 = 14 |
| G7 What CMO hides (M4) | B-T T1 → T2, then mw | o1 tier == t2 ∧ steady; o2 choice "Why is V at the bottom smaller than at the top?" → "toluene's latent heat is larger"; o3 choice for methanol–water | | VC-11 profile |
| G8 Pressure and volatility (M4) | B-T T2 | o1 lever.pTop ≥ 199 000 ∧ xD ≥ xD(start) − 0.002 ∧ xB ≤ xB(start) + 0.002 (use `from: start`) ∧ steady, hold 300; o2 choice "What happened to α?" → "it fell" | v1.0 said "hold specs" without defining them: they are now the 1-atm start values ± 0.002 | VC-10.3 α 2.71 (0.5 bar) → 2.20 (3 bar) |
| G9 The azeotrope wall (M5) | ew T3, N 40, E 1 | o1 number "highest x_D you could reach" = 0.8956 ± 0.01; o2 choice "Tier 1 went past it. Why?" → "constant α cannot represent an azeotrope"; o3 choice "Lower pressure moves the azeotrope to…" → "higher ethanol" | | VC-10.5 |
| G10 The other azeotrope (M5) | ac T3 | o1 choice "Where does the azeotrope leave?" → "in the bottoms"; o2 number x_B,acetone = 0.33 ± 0.03 | | VC-10.5, VC-8.11 |
| G11 Flooding (M2/M3, Tier 1, full hydraulics) | `steady` (defaults, full hydraulics) | o1 kpi.maxFloodPct ≥ 100 (reach flood); o2 (after o1) maxFloodPct between 80 and 88 ∧ steady, hold 600; o3 number "throughput at flood onset (% of design)" = 120 ± 10 | "Raise F, L₀ and V_B together by 10 %: 110/110/165, 120/120/180, 130/130/195 kmol/h" | Uniform scaling keeps F_LV constant, so φ scales with the vapour rate: design max φ 0.832 (VC-12.3) → flood at ≈ 1/0.832 = 120 % |
| G12 Turndown and weeping (M2/M3) | `steady`, full hydraulics, sieve | o1 throughput 35 % (F 35, L₀ 35, V_B 52.5 kmol/h) ∧ steady ∧ kpi.maxWeepFrac ≥ 0.3; o2 choice "What did weeping do to x_B?" → "raised it"; o3 (after o1) trayType.0 == valve ∧ steady ∧ kpi.maxWeepFrac < 0.05; o4 choice "Why don't valve trays weep yet?" → "closed valves keep the hole velocity up" | "Tray type can only be changed while paused" | VC-12.4 (w 0.51 sieve), VC-12.5 (w 0 valve at 35 %) |

Every guided scenario's JSON carries these objectives verbatim. Its hints must, followed literally, complete it (SCOPE.md M3 acceptance; VC-26.4 plays G1–G6 automatically by applying the hint values).

---

## 12. Units and formatting

```dart
enum Quantity { temperature, temperatureDelta, pressure, pressureDelta, molarFlow, massFlow,
  volumeFlowLiquid, volumeFlowCrude, energyRate, enthalpyMolar, length, smallLength, area, volume,
  density, molarAmount, mass, time, fraction, percent, surfaceTension, viscosity, heatTransferCoeff, ua,
  velocity, specificArea, dimensionless }

class UnitSystem {
  static const si = UnitSystem._('SI');
  static const usField = UnitSystem._('US');
  String symbol(Quantity q);
  double fromSI(Quantity q, double v);
  double toSI(Quantity q, double v);
}
```

| Quantity | SI display | US field display | Conversion (from SI base) |
|---|---|---|---|
| temperature | °C | °F | °C = K − 273.15 ; °F = K × 9/5 − 459.67 |
| temperatureDelta | K | °F (Δ) | × 1.8 |
| pressure | bar(a) (kPa for ΔP-scale values) | psia | bar = Pa/1×10⁵ ; psia = Pa/6894.757293 |
| pressureDelta | kPa (column), mbar (per tray) | psi, in H₂O | in H₂O = Pa/249.0889 |
| molarFlow | kmol/h | lb-mol/h | kmol/h = mol/s × 3.6 ; lb-mol/h = mol/s × 3600/453.59237 |
| massFlow | kg/h | lb/h | lb/h = kg/s × 3600/0.45359237 |
| volumeFlowLiquid | m³/h | US gpm | gpm = m³/s / 6.30901964×10⁻⁵ |
| volumeFlowCrude | m³/h | bbl/d | bbl/d = m³/s × 86400/0.158987295 |
| energyRate | kW (MW above 10 MW) | MMBtu/h | MMBtu/h = W × 3600/1.05505585×10⁹ |
| length | m | ft | ft = m/0.3048 |
| smallLength | mm | in | in = m/0.0254 |
| density | kg/m³ | lb/ft³ | lb/ft³ = kg/m³ / 16.01846 |
| surfaceTension | mN/m | dyn/cm | numerically equal |
| viscosity | mPa·s | cP | numerically equal |
| heatTransferCoeff | W/m²K | Btu/h·ft²·°F | ÷ 5.678263 |

`Fmt.value(q, v, system)` returns a string with sensible precision (mole fractions 4 decimals, or 6 above 0.99; temperatures 1 decimal; flows 3 significant figures; pressures 4 significant figures).

---

## 13. App layer

### 13.1 Structure (`app/lib`)

```
main.dart                      runApp(LowsysApp())
app.dart                       MaterialApp with theme bridging (LowsysTheme → ThemeData), routes
app_scope.dart                 AppScope (InheritedWidget) exposing the controllers below
controllers/
  sim_controller.dart          SimController (ChangeNotifier): owns SimRunner, Ticker loop, speed,
                               selection, mode (sandbox/scenario/drill); exposes ValueNotifier<SimSnapshot>
  settings_controller.dart     theme id, unit system, quality, default speed, haptics (persisted)
  scenario_controller.dart     wraps ScenarioRunner state for the HUD
  progress_store.dart          completion and best scores (persisted)
  save_store.dart              SaveStore interface; SharedPrefsSaveStore (all platforms)
theme/
  lowsys_theme.dart            LowsysTheme (tokens) + style enums (§13.4)
  themes/blueprint.dart, control_room.dart, phosphor.dart, brass.dart, paper.dart
  theme_bridge.dart            LowsysTheme → Material ThemeData (for standard widgets)
layout/
  breakpoints.dart             compact portrait / compact landscape / medium / expanded (SCOPE.md §3.3)
  sim_layout.dart              arranges ColumnView, DiagramPanel, ControlPanel, KpiStrip per class
screens/
  home_screen.dart, sandbox_setup_screen.dart, sim_screen.dart, scenario_list_screen.dart,
  briefing_screen.dart, debrief_screen.dart, settings_screen.dart, library_screen.dart (M10)
painters/
  column_painter.dart          trays/packing/drum/sump/reboiler/condenser/strippers, flows, particles
  mccabe_painter.dart          draws McCabeThieleData
  profile_painter.dart, trend_painter.dart, txy_painter.dart, fug_panel_painter.dart,
  crude_chart_painter.dart, thermosyphon_painter.dart, gauge_painter.dart
  effects/                     blueprint_grid.dart, paper_grain.dart, scanlines.dart, glow.dart,
                               rivets.dart, vignette.dart (all cached; quality-aware)
widgets/
  time_bar.dart, kpi_strip.dart, lever_tile.dart (slider + ± + numeric entry + SP/OP badge),
  faceplate.dart (PV/SP/OP, mode, quality badge, signal look, valve-curve mini plot, field check),
  alarm_banner.dart, alarm_list.dart, balance_panel.dart (cross-checks, window selector, C6 chart),
  math_overlay.dart (flutter_math_fork), tray_inspector.dart,
  fault_panel.dart, scenario_hud.dart, drill_hud.dart, diagnose_dialog.dart
```

Dependencies: `flutter`, `flutter_math_fork` (TeX rendering in the math overlay), `shared_preferences` (settings, progress, sandbox saves). No state-management package, no routing package. Pin versions in `pubspec.yaml` to the latest stable at implementation time and commit `pubspec.lock`.

### 13.2 State management

- `AppScope` is an `InheritedWidget` created in `main.dart` holding `SimController`, `SettingsController`, `ProgressStore`, `SaveStore`. Widgets read them with `AppScope.of(context)`.
- Coarse UI state (running, speed, tier, selected stage, active tab, mode) lives in `SimController` as a `ChangeNotifier`; widgets rebuild with `ListenableBuilder` only when it changes.
- The per-frame path never rebuilds widgets: `SimController.snapshot` is a `ValueNotifier<SimSnapshot>`; every painter is `CustomPaint(painter: XPainter(snapshot: controller.snapshot, theme: …))` and `XPainter` passes the notifier to `super(repaint: snapshot)`. KPI text uses `ValueListenableBuilder` around small `Text` widgets.
- Each panel is wrapped in a `RepaintBoundary`. Static decoration layers (grids, textures, vessel outlines) are separate `CustomPaint`s with `isComplex: true, willChange: false`.

### 13.3 Frame loop (`SimController`)

```
onTick(elapsedWall):                                   // Ticker from the SimScreen State
  if paused: return
  debt += elapsedWall × speed                           // sim seconds owed
  debt  = min(debt, 2 × frameWall × speed)              // never build an unbounded backlog
  advanced = await runner.advance(debt, budget: 6 ms)   // whole steps only
  debt -= advanced
  achievedSpeed = smooth(advanced / elapsedWall)
  speedLimited  = advanced < 0.9 × requested
  snapshot.value = await runner.snapshot()              // once per frame
```

"Run to steady state" shows a progress dialog and calls `runner.runToSteadyState()` in slices of 50 ms wall time so the UI stays responsive.

### 13.4 Theme token system

```dart
@immutable
class LowsysTheme {
  final String id, name;
  final ThemePalette palette;      // every colour token of SCOPE.md §7.1
  final ThemeTypography type;      // display, label, number, math (family, weight, letterSpacing, sizes)
  final ColumnStyle column;        // vesselStyle, liquidStyle, vaporStyle, gaugeStyle, stroke widths, particle density
  final ChartStyle chart;          // lineStyle, grid density, marker shapes, dash patterns, persistence frames
  final EffectStyle effects;       // blueprintGrid, paperGrain, scanlines, bloom, vignette, rivets,
                                   // needlePhysics, figureCaptions, alarmBlink, glowStrokesMax
  const LowsysTheme({...});
}
@immutable class ThemePalette { final Color bg, bgAlt, surface, surfaceAlt, ink, inkMuted, inkFaint,
  grid, gridMajor, accent, accent2, steel, liquidLight, liquidHeavy, froth, vapor, hot, cold, ok, warn,
  alarm, info, selection, eqCurve, opLine, opLineCmo, qLine, stepLine, diagonal, pseudoEq, marker; }
enum VesselStyle { outline, flat, bevel, vector }
enum LiquidStyle { hatch, gradient, glyph, amber }
enum VaporStyle { circles, glowDots, glyphs, puffs, dots }
enum GaugeStyle { numeric, bargraph, dial }
enum LineStyle { pen, glow, vector, ink }
```

Painters read only tokens and style enums; there is no `if (theme.id == …)` anywhere. Themes are `const` instances in `themes/*.dart` with the values in SCOPE.md §7.2. Composition colour = `Color.lerp(liquidLight, liquidHeavy, x_heavy)` (binary) or the LK/HK pseudo-binary x (multicomponent) or the mean boiling point (crude).

`theme_bridge.dart` maps tokens onto Material `ThemeData` (colorScheme, textTheme) so standard widgets (sliders, dialogs, tabs) match.

### 13.5 Column painter contract

Input: `SimSnapshot`, `LowsysTheme`, viewport, selection. It draws, per stage: tray deck, weir, downcomer (with backed-up liquid height from `dcFlood`), clear liquid (`hcl`) and froth (`froth`) with the composition colour, vapour particles whose spawn rate ∝ V_j and rise speed ∝ hole velocity, entrainment spray when ψ > 0.02, weep drips when weepFrac > 0.05, dumping and dry states, flooding overlay when frothFill ≥ 1 or jetFlood ≥ 1. Packed beds: bed texture with wetted fraction shading and HETP ticks. Drum and sump levels; condenser with CW flow animation; reboiler (kettle or thermosyphon loop with circulation arrows and quality-coloured riser). Hit-testing returns `ExplainTarget`s for taps. Particle positions use the UI clock (smooth at any sim speed); particle counts per SCOPE.md §7.3.

### 13.6 Fonts and assets

Bundled (SIL OFL 1.1, licences in `assets/fonts/LICENSES/`): Architects Daughter, Share Tech Mono, Rajdhani, JetBrains Mono, VT323, Cinzel, IM Fell English, Courier Prime, Source Serif 4, Source Sans 3, STIX Two Math. Only the weights used are bundled. Small tiled textures (paper grain, blueprint grain, rivets) are generated procedurally at startup into `ui.Image`s (no image assets needed) **[impl]**.

### 13.7 Persistence

`SaveStore` keys: `settings` (JSON), `progress` (JSON: scenario id → best score, completed), `sandbox.slot.<n>` (JSON from `Simulator.saveState()`, about 50–200 kB). Autosave the sandbox every 60 s of wall time and on app pause.

### 13.8 App tests

Widget tests for each layout class (no overflow at 360×800, 800×360, 1440×900 logical px); golden tests per theme for the McCabe–Thiele and column painters on a fixed snapshot (golden files committed); a smoke test that runs the B-T preset at 100× for 600 frames with a fake clock.

---

## 14. Module ↔ milestone map

| Module | M1 | M2 | M3 | M4 | M5 | M6 | M7 | M8 | M9 | M10 |
|---|---|---|---|---|---|---|---|---|---|---|
| core, math, units (SI only in M1) | ● | units US | | | | | | | | |
| thermo: Tier 1 | ● | | | | | | | | | |
| thermo: Tier 2, enthalpy, flash | | | | ● | | | ● (LK HC) | | ● (crude) | |
| thermo: Tier 3 | | | | | ● NRTL | | ● DePriester | | | |
| config, presets | bt | | | mw (T2) | mw, ew, ac, c4 | | debut, deprop | bt_packed | crude | |
| tray hydraulics | weir only | full | | | | | | | | |
| packed hydraulics | | | | | | | | ● | | |
| condenser / pressure | Tier-1 drum | | | ● | | | | | | |
| reboiler kettle / thermosyphon | Tier-1 sump | | | kettle | | thermosyphon | | | | |
| side ops, strippers, steam | | | | | | | | | ● | |
| control system | internal LC | | ● loops, valves, fast layer, instruments + noise, analysers, field gauges, alarms, cross-checks C1–C5, plant view, PRNG | PC, TC, T2 instruments, C3a/b, C6, C7 | | | | | crude loops | |
| faults | | F01–F07 | F19, F20, F28 | F08–F15 | | F16–F18 | | F21–F23 | F24–F27 | |
| explain | | ● | | T2 equations | NRTL | thermosyphon | FUG | packing | crude | |
| snapshot: McCabe–Thiele | ● | | | non-CMO | T-x-y | | Hengstebeck, FUG | | crude charts | |
| scenarios, drills | | | runner, scoring, schema test + G1–G6, G11–G12 | G7–G8 | G9–G10 | drills H1–H5, H9, H10, G14 | G13, H6 | G15, H7 | G16, H8 | review |
| runner | Local | | | | | | | | | Isolate |
| app themes | Blueprint | | | Control Room | Paper | | Phosphor | | Brass | |

---

## 15. Conventions for the implementer

- Follow `package:lints/recommended.yaml`; `dart format`; no `dynamic` in engine code.
- Engine public API is exactly what `lowsys_engine.dart` exports; everything else is `src/`.
- Every PHYSICS.md equation implemented gets a doc comment with its number, e.g. `/// PHYSICS.md (5.2) Bennett weir.`
- Every VALIDATION.md case gets a test named after its id (`VC-4 dynamic steady state matches Newton`).
- Hot-path code (`Stepper.step` and everything it calls) must not allocate; a test runs 10 000 steps under `--observe` **[impl: or counts allocations via a debug counter]** and asserts no growth in retained memory.
- When the implementer must deviate from PHYSICS.md (a tuning value, a safeguard), record it in `docs/DEVIATIONS.md` with the reason and the failing test that motivated it. Do not change PHYSICS.md silently.
