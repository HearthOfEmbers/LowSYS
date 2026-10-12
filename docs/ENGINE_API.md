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

```dart
enum LoopMode { man, auto, cas }
enum Action { direct, reverse }

class PidParams { final double kc, ti, td; final Action action; final double pvLo, pvHi; }

class ControlLoop {
  final LoopTag tag;
  final String pvRef;          // metric path, e.g. 'drum.levelPct', 'stage[14].t'
  final String mvRef;          // valve id or 'FC-103.sp' for cascade
  LoopMode mode;
  double sp, op;               // SP in PV units (SI); OP in %
  final PidParams params;
  final bool idealFlow;        // PHYSICS.md §10.2
}

class ControlSystem {
  List<ControlLoop> get loops;
  ControlLoop loop(LoopTag tag);
  void setMode(LoopTag tag, LoopMode mode);   // bumpless
  void setSp(LoopTag tag, double sp);
  void setOp(LoopTag tag, double op);
  void execute(double dt, MeasurementBus pvs); // PHYSICS.md §10.1, called by the stepper (step 12)
}

class Instrument { final String tag; final double lag, deadTime, span; double bias, drift; bool stuck; }
class Valve { final String id; final double maxFlow; final double lag; ValveFault fault; double position; }
class Alarm { final String id, message; final AlarmPriority priority; final bool acknowledged; final double raisedAt; }
```

Loop sets per preset come from `control_config.dart` (PHYSICS.md §10.4). Loops that do not exist in a tier are hidden (e.g. PC-101 in Tier 1).

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
  "levers": {
    "set": {"refluxMode": 1, "refluxRatio": 2.0},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["refluxRatio", "boilup", "feedZ.benzene"]
  },
  "loops": {"LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}},
  "timeLimit": 43200,
  "briefing": "Markdown text …",
  "objectives": [
    {"id": "o1", "text": "Hold xD ≥ 0.95 and xB ≤ 0.05 with the smallest reflux ratio you can.",
     "when": {"all": [{"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 600},
    {"id": "o2", "text": "Report R_min.", "answer": {"type": "number", "metricRef": "answer.rmin",
     "correct": 1.10, "tolerance": 0.055}}
  ],
  "hints": [
    {"after": 1800, "text": "Watch the staircase near the q-line …"},
    {"when": {"metric": "kpi.refluxRatio", "op": "<", "value": 1.12}, "text": "You are close to the pinch …"}
  ],
  "events": [
    {"at": 0, "action": "setLever", "lever": "feedZ.benzene", "value": 0.5}
  ],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1,
              "qualitySpec": {"metric": "kpi.xD", "op": ">=", "value": 0.95}},
  "debrief": "Markdown with live values: {kpi.refluxRatio:0.00}, {answer.rmin:0.00} …"
}
```

Predicates are structured (no expression language): `{"all": [...]}`, `{"any": [...]}`, `{"not": {...}}`, and leaves `{"metric": path, "op": "<"|"<="|"=="|">="|">"|"!=", "value": number|bool}` or `{"metric": path, "op": "between", "lo": a, "hi": b}`. Metric paths: `time`, `steady`, `kpi.<field>`, `stage[<j>].<field>`, `loop[<tag>].<pv|sp|op|mode>`, `condenser.<field>`, `reboiler.<field>`, `alarm.count`, `safety.<reliefLifted|levelViolationSeconds>`, `answer.<id>`, `lever.<id>`. Unknown paths are a schema-test failure.

`overrides` keys use a dotted/indexed path into `ColumnConfig` JSON. Event actions: `setLever`, `setLoopMode`, `setSp`, `injectFault` (with a `FaultSpec`), `clearFault`, `message`.

### 11.2 Drill JSON (extends the scenario schema)

```json
{
  "id": "H2_pressure",
  "kind": "drill",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": true,
  "candidates": [
    {"weight": 1, "fault": {"type": "coolingLoss", "params": {"mode": "temperature"}, "severityRange": [0.6, 1.0], "ramp": 1800},
     "answer": {"category": "cooling", "location": "condenser"}},
    {"weight": 1, "fault": {"type": "condenserFouling", "severityRange": [0.7, 1.0], "ramp": 7200},
     "answer": {"category": "fouling", "location": "condenser"}},
    {"weight": 1, "fault": {"type": "nonCondensables", "severityRange": [0.5, 1.0], "ramp": 0},
     "answer": {"category": "inerts", "location": "condenser"}}
  ],
  "onsetWindow": [600, 2400],
  "diagnosis": {
    "categories": ["cooling", "fouling", "inerts", "foaming", "trayDamage", "instrument", "valve",
                   "feedUpset", "steam", "thermosyphon", "maldistribution", "none"],
    "locations": ["condenser", "reboiler", "rectifying", "stripping", "feed", "instrument:<tag>", "valve:<id>", "packedBed"],
    "attempts": 2
  },
  "timeLimit": 14400
}
```

The candidate and the onset are drawn with the drill seed (`SimOptions.seed` ⊕ a per-attempt counter) so a drill is reproducible for tests.

### 11.3 Runner

```dart
class ScenarioDef { factory ScenarioDef.fromJson(Map<String, Object?> j); List<String> validate(ComponentDb db); }
class ScenarioRunner {
  ScenarioRunner(ScenarioDef def, Simulator sim);
  void update();                                  // called after each step by the simulator
  List<ObjectiveState> get objectives;
  List<String> get unlockedHints;
  void submitAnswer(String objectiveId, Object answer);
  DrillResult submitDiagnosis(Diagnosis d);       // drills
  ScoreCard finish();
}
```

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
  faceplate.dart, alarm_banner.dart, math_overlay.dart (flutter_math_fork), tray_inspector.dart,
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
| control system | internal LC | | ● | PC, TC | | | | | crude loops | |
| faults | | F01–F07 | F19–F20 | F08–F15 | | F16–F18 | | F21–F23 | F24–F27 | |
| explain | | ● | | T2 equations | NRTL | thermosyphon | FUG | packing | crude | |
| snapshot: McCabe–Thiele | ● | | | non-CMO | T-x-y | | Hengstebeck, FUG | | crude charts | |
| scenarios, drills | | | runner + G1–G6, G11–G12 | G7–G8 | G9–G10 | drills H1–H5, G14 | G13, H6 | G15, H7 | G16, H8 | review |
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
