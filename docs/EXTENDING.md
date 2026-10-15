# Extending LowSYS

A guide for agents and developers who add a module to LowSYS: a theme, a scenario or drill, a column preset, a fault, a
lever, an explain entry, a component or a panel. Each section is a checklist. Line numbers drift, so the guide names
symbols; find them with `grep -n`.

LowSYS is a distillation-column simulator for teaching. A pure-Dart engine computes the column, its controls, faults and
scenarios. A Flutter app draws it and lets the user operate it.

## Repo map

```
packages/lowsys_engine/          pure Dart, no Flutter
  lib/lowsys_engine.dart         the public barrel: the app imports only this
  lib/src/runner/sim_runner.dart SimRunner, the only engine interface the app uses
  lib/src/sim/                   Simulator (levers, stepping), simulator_crude.dart for the crude unit
  lib/src/config/                ColumnConfig, Presets, tray/packed geometry, crude config
  lib/src/data/                  JSON data as Dart raw strings: presets/, scenarios/, components, packings
  lib/src/thermo|model|control|faults|scenario|explain|snapshot/
  test/, test/validation/        engine tests (VALIDATION.md cases are named VC-n)
app/                             Flutter app (package lowsys_app)
  lib/theme/                     LowsysTheme tokens, theme_bridge.dart, themes/*.dart + registry.dart
  lib/controllers/sim_controller.dart   app state, settings, save store
  lib/widgets/, lib/painters/, lib/layout/sim_layout.dart, lib/l10n/strings.dart (class S)
  test/                          widget, contrast and golden tests
docs/                            SCOPE, PHYSICS, ENGINE_API, VALIDATION (specs), OPEN_ITEMS
```

## Golden rules

1. **Determinism.** The engine has no `Random()` and no wall-clock time. Randomness comes from
   `Rng.stream(seed, '<name>')` (see `DrillDraw.draw` in `scenario/drill.dart`). Same seed, same run; VC-20 tests
   check this.
2. **Unique ids.** Theme ids, preset ids, scenario ids, lever ids, fault type names and loop tags are looked up by
   string. Several lookups fall back silently (`themeById` returns Blueprint, a `setLever` id with no branch does
   nothing), so a duplicate or a typo shows up as wrong behaviour, not as an error.
3. **SI units inside.** Engine data, lever values and snapshot values are SI (Pa, K, mol/s, W, J/mol, kg/m3, s). The
   app converts for display only (`UnitSystem`, `u.toSI` / `u.fromSI`).
4. **Engine API through the barrel.** Anything the app needs must be exported from `lib/lowsys_engine.dart`; a new
   engine call the app makes must go on `SimRunner` first.
5. **Specs stay in sync.** `docs/SCOPE.md` (what ships), `docs/ENGINE_API.md` (types and JSON), `docs/PHYSICS.md`
   (equations, data) and `docs/VALIDATION.md` (test cases) describe the product. When you add a module, update the
   matching section. Explain a deliberate departure from a spec, with its reason, in the pull request. Where spec and
   code disagree today, the code is the truth (for example `ENGINE_API.md` §1 and §13.1 list files that do not
   exist, such as `component_db.dart`, `settings_controller.dart`, `home_screen.dart`).
6. **English strings in `S`.** App text goes in `abstract final class S` (`app/lib/l10n/strings.dart`). Engine text
   (briefings, debriefs, alarm messages, explain notes) stays in engine data or code.

## Running tests

```sh
flutter --version                                      # needs Flutter 3.47.7 stable on PATH
cd packages/lowsys_engine && dart test                 # whole engine suite (long)
cd packages/lowsys_engine && dart test test/scenario_test.dart
cd app && flutter test                                 # whole app suite
cd app && flutter test test/m10_theme_test.dart
```

**Goldens fail on Linux.** The five PNGs in `app/test/goldens/` were made on Windows; on
Linux `m5_golden_test.dart` and `m10_crude_golden_test.dart` fail with about 2-3 % pixel difference. Do not run `--update-goldens` on them from Linux, and delete the `app/test/failures/` folder a failed
golden run leaves behind. `test/shot_helpers.dart` `loadFonts` loads the bundled fonts from `assets/fonts/` and skips
missing files (the MaterialIcons path is a Windows path). Set `LOWSYS_SHOTS=1` only to write screenshots to
`docs/screenshots/`.

---

## 1. Theme

A theme is pure data: a `const LowsysTheme` in `app/lib/theme/themes/`. Painters read tokens and style enums. The
menu, the Material bridge, persistence and the contrast tests all pick a new theme up from `kThemes`.

### Checklist

1. **Create `app/lib/theme/themes/<name>.dart`.** Copy the closest existing theme (`blueprint.dart`,
   `control_room.dart`, `phosphor.dart`, `paper.dart`, `brass.dart`) and change the values.
2. **Register it** in `app/lib/theme/themes/registry.dart`: import the file and add the constant to `kThemes`. The
   list order is the menu order.
3. **Fonts** (only if the theme uses a family that is not bundled): add the `.ttf` to `app/assets/fonts/`, a
   `fonts:` entry in `app/pubspec.yaml`, its licence text to `app/assets/fonts/LICENSES/`, and a `load(...)` line in
   `app/test/shot_helpers.dart` `loadFonts`. Bundled now: Architects Daughter, Share Tech Mono, STIX Two Math,
   Rajdhani (500, 600), JetBrains Mono, Source Serif 4 (roman, italic), Source Sans 3, Cinzel, IM Fell English,
   Courier Prime (400, 700), VT323. Always give `TypeToken` fallback families.
4. **Check the per-theme branches** (below) and decide whether the new theme needs any of them.
5. **Run the theme tests** (below). The contrast tests run for every entry of `kThemes` automatically.
6. **Docs:** add the theme to `docs/SCOPE.md` §7.2 ("The six themes", T-1..T-6; add a T-n block and update the count in the heading and the S-level theme list) with its tokens, and keep the
   VALIDATION.md §U contrast rules satisfied.

No change is needed in `app.dart`, `sim_controller.dart`, `theme_bridge.dart` or `time_bar.dart` to register it.

### Skeleton

Every field without a default is `required`, so the compiler lists anything you missed.

```dart
// app/lib/theme/themes/mytheme.dart
import 'package:flutter/material.dart';
import '../lowsys_theme.dart';

const LowsysTheme mythemeTheme = LowsysTheme(
  id: 'mytheme',          // unique; persisted under settings.theme
  name: 'My Theme',       // shown as "Theme: My Theme" in the time-bar menu (S.menuTheme)
  palette: ThemePalette(
    bg: Color(0xFF...), bgAlt: ..., surface: ..., surfaceAlt: ...,
    ink: ..., inkMuted: ..., inkFaint: ..., grid: ..., gridMajor: ...,
    accent: ..., accent2: ..., steel: ..., liquidLight: ..., liquidHeavy: ..., froth: ..., vapor: ...,
    hot: ..., cold: ..., ok: ..., warn: ..., alarm: ..., info: ..., selection: ...,
    eqCurve: ..., opLine: ..., opLineCmo: ..., qLine: ..., stepLine: ..., diagonal: ..., pseudoEq: ..., marker: ...,
    series: [/* exactly 6 colours */],
    seriesDash: kSolidDash,   // six empty dashes; or six explicit patterns, e.g. phosphor's
  ),
  type: ThemeTypography(display: TypeToken(...), label: TypeToken(...), number: TypeToken(..., tabularFigures: true),
      math: TypeToken('STIX Two Math', [...])),
  column: ColumnStyle(vesselStyle: VesselStyle.outline, liquidStyle: LiquidStyle.hatch,
      vaporStyle: VaporStyle.circles, gaugeStyle: GaugeStyle.numeric),   // stroke widths, particle caps default
  chart: ChartStyle(lineStyle: LineStyle.pen),                           // grid and dash lengths default
  effects: EffectStyle(),                                                // all flags default to off
);
```

Token reference (`app/lib/theme/lowsys_theme.dart`):

- Style enums: `VesselStyle {outline, flat, bevel, vector}`, `LiquidStyle {hatch, gradient, glyph, amber}`,
  `VaporStyle {circles, glowDots, glyphs, puffs, dots}`, `GaugeStyle {numeric, bargraph, dial}`,
  `LineStyle {pen, glow, vector, ink}`. Reuse existing values; a new enum value means updating every painter that
  switches on it.
- `EffectStyle` flags with consumers: `blueprintGrid`, `paperGrain`, `scanlines`, `vignette` (each a layer of
  `BlueprintBackdropPainter` in `painters/effects/blueprint_grid.dart`), `alarmBlink` (`alarm_bar.dart`),
  `glowStrokesMax` (glow strokes, active only when `chart.lineStyle == LineStyle.glow`; see `effects/glow.dart`).
  `bloom`, `rivets`, `needlePhysics` and `figureCaptions` exist but nothing reads them.
- Painter text sizes come from `PainterText` (`theme/painter_text.dart`), which follows the text scale clamped to
  1.0-1.3.
- `theme_bridge.dart` `materialThemeFor` maps the palette and type onto Material `ThemeData`; it has no per-id code.

### Per-theme branches (`theme.id ==`)

`docs/ENGINE_API.md` §13.4 says painters read only tokens and there is no `if (theme.id == …)`. The code has five such
branches. A new theme gets the default (else) path in each:

| Where | Branch | Effect |
|---|---|---|
| `app/lib/widgets/time_bar.dart`, settings menu | `sim.themeId.value == 'controlRoom'` | "Composition shading" menu item only in Control Room |
| `app/lib/painters/txy_painter.dart` `paint` | `theme.id == 'paper'` | Paper-specific T-x-y drawing |
| `app/lib/widgets/diagram_head.dart` | `t.id == 'paper'` | Paper-only diagram header (figure export) |
| `app/lib/painters/crude_painter.dart` `paint` | `theme.id == 'brass'` | Brass crude flowsheet look |
| `app/lib/widgets/crude_products_panel.dart` `_CurvePainter` | `t.id == 'brass'` | Charts on `brassParchment` with `brassSepia` ink |

If the new theme needs one of these looks, add a token or style field to `LowsysTheme` (and set it in every theme)
rather than a new `id ==` branch. Find them again with
`grep -rn "id == '" app/lib | grep -i "theme\|t\.id"`.

### Selection and persistence

- `SimController.themeId` (`ValueNotifier<String>`, default `'blueprint'`); `setTheme(id)` sets it and writes
  `settings.theme` to the save store; `restoreSettings()` reads it back.
- The time-bar menu builds one `CheckedPopupMenuItem` per `kThemes` entry with value `'theme:<id>'`.
- `themeById(id)` returns `blueprintTheme` for an unknown id.
- **Boot:** `main.dart` awaits `sim.restoreSettings()` before `runApp` and passes `theme: themeById(sim.themeId.value)`,
  so `_LowsysAppState.initState` (`app.dart`), which sets `themeId` from `widget.theme.id`, writes back the restored id.
  Tests that build `LowsysApp` directly choose the theme through the `theme:` argument.

### Tests

These enumerate `kThemes`, so the new theme is checked without editing them:

| Test | Checks for every theme |
|---|---|
| `app/test/m10_theme_test.dart` | U2: ink/bg >= 7, inkMuted/bg >= 4.5, accent/warn/ok/alarm and every series colour/bg >= 3; U3: alarm vs ok L* difference >= 15 under deuteranopia (Machado 2009) |
| `app/test/validation_m10_contrast_test.dart` | U2 on bg and on the chart fill (`bgAlt` at 55 % over `bg`): ok on `surface`, series and chart-line tokens (eqCurve, opLine, opLineCmo, qLine, stepLine, pseudoEq, marker) >= 3; U3 with Machado and Vienot 1999 |
| `app/test/m7_ui_test.dart` | `series.length == 6` and `seriesDash.length == 6` |

Exemptions are by id: `phosphor` skips the alarm contrast and U3 checks (inverse-video alarms); `brass` adds `qLine`
on parchment. A new exemption needs a reason in `docs/VALIDATION.md` §U.

Tests that name specific themes (`m5_golden_test.dart`, `m10_crude_golden_test.dart`, `validation_m10_a11y_test.dart`,
`m9_ui_test.dart`, the ok-colour hex test) need no change. Optional additions: a `setTheme('<id>')` smoke test modelled
on `m9_ui_test.dart`, or an a11y layout case in `validation_m10_a11y_test.dart` (text scale 1.3 at a small size). Do not
add goldens from Linux (see Running tests).

```sh
cd app && flutter test test/m10_theme_test.dart test/validation_m10_contrast_test.dart test/m7_ui_test.dart test/m9_ui_test.dart
```

---

## 2. Scenario (guided) and drill

Scenarios are JSON held as Dart raw strings and registered in
`packages/lowsys_engine/lib/src/scenario/scenario_library.dart` (`abstract final class Scenarios`).

### Checklist

1. **Write the JSON** as `const String g17Json = r'''{...}''';` in `lib/src/data/scenarios/scenarios.dart` (guided),
   `drills.dart` (drills) or `crude_scenarios.dart`. Copy a close existing one: `g11Json` (guided), `h9Json`
   (drill). The schema is `docs/ENGINE_API.md` §11.1 (guided) and §11.2 (drill).
   - `"id"`: the convention is `G<n>_<slug>` / `H<n>_<slug>`, for example `G11_flooding`.
   - `"kind"`: `"guided"` or `"drill"`. This field, not the map, decides drill vs guided scoring.
   - `"preset"`: a `Presets` id; `"overrides"` are applied with `ColumnConfig.applyOverrides`.
2. **Register** in `Scenarios`: `_guided` for guided scenarios, `_drills` for drills. Key = JSON `id`.
   `Scenarios.ids` returns only the guided keys (map order); `Scenarios.allIds` adds the drills.
3. **App listing** is automatic: the scenario picker in `app/lib/widgets/scenario_ui.dart` lists `Scenarios.all` and
   then every drill from `allIds`.
4. **Library card** (optional): the concept library is the hand-written list `S.libraryCards` in
   `app/lib/l10n/strings.dart` (`LibraryCard(id, title, body, scenarioId)`); a card opens its scenario. A new
   scenario does not get a card unless you add one.
5. **Docs:** add it to `docs/SCOPE.md` §6.1 / §6.2, and for a drill add its design section to `ENGINE_API.md` §11
   (as §11.6-§11.12 do for H6-H10) with reference numbers in §11.8 for guided objectives.
6. **Tests** (below).

### What `ScenarioDef.validate()` enforces

`ScenarioDef` (`lib/src/scenario/scenario_def.dart`) parses with `fromJson` and returns problem strings from
`validate()`:

- Metric paths in objectives, hints, predicates and templates must match `metricPathPattern`
  (`scenario/predicate.dart`). A new metric needs the regex extended and the value supplied by the metric context.
- Lever ids must match `_leverPattern`; loop tags `_loopPattern` (`(FC|LC|PC|TC)-\d+`); instrument fault kinds
  `_instrumentKinds`; valve fault kinds `_valveKinds` (`stuck`, `failOpen`, `failClosed`); fault types the
  `FaultType` names (`_checkFault`); `loadPreset` events a `Presets.ids` entry; unknown event actions are rejected.
- Drills: candidates with a positive total weight, `onsetWindow` of two values with `onsetWindow[1] + 3600 <=
  timeLimit`, a `diagnosis` block whose categories and locations come from `diagnosisCategories` and
  `diagnosisLocations` (`instrument:*`, `valve:*`, `bed:*`, `steam:*` are prefix wildcards), and each candidate's
  answer category among the offered ones.
- The built config (`buildConfig()` = preset + overrides) must validate.

Scoring weights default per mode and can be overridden by the JSON `scoring` block: guided `objectives 0.6, time 0.2,
safety 0.1, quality 0.1`; drill `category 0.5, location 0.2, time 0.2, safety 0.1` plus `timeFull`, `timeZero`,
`wrongPenalty` and `bonus`. The arithmetic is `scenario/scoring.dart` (`ENGINE_API.md` §11.4).

Runtime: `ScenarioRunner` (`scenario/scenario_runner.dart`) runs after every simulation step (events, objectives,
hints, drill clocks, time limit). A drill's fault comes from `DrillDraw.draw` with `Rng.stream(seed, 'drill')`, so a seed
replays the same fault.

### Tests

- The "every shipped scenario validates" tests (`test/scenario_test.dart`, `test/validation/vc26_scenarios_test.dart`
  VC-26.1, `test/m2_test.dart`) loop over `Scenarios.ids` / `ScenarioLibrary.all`, which are **guided only**. A new
  guided scenario is covered for schema. VC-26.4 ("guided scenarios are completable") is a set of hand-written
  per-scenario checks; add one with the scenario's reference numbers.
- **Drills are not enumerated.** Add the id to a per-id list such as the one in `test/m6_scenarios_schema_test.dart`
  (`expect(Scenarios.byId(id).validate(), isEmpty)`) and, for a run, to the id list in
  `test/m6_drills_smoke_test.dart`.
- Recommended: a "broken copy does not validate" case for any new vocabulary (pattern in `scenario_test.dart`).

```sh
cd packages/lowsys_engine && dart test test/scenario_test.dart test/validation/vc26_scenarios_test.dart test/m6_scenarios_schema_test.dart
```

---

## 3. Column preset

A preset is a JSON `ColumnConfig` in `lib/src/data/presets/`, registered in `lib/src/config/presets.dart`. Ten exist:
`bt`, `bt_custom_alpha`, `mw`, `ew`, `ac`, `c4`, `debut`, `deprop`, `bt_packed`, `crude`.

### Checklist

1. **Write the JSON** as `const String xyzPresetJson = r'''{...}''';` in `lib/src/data/presets/xyz.dart`. Start from
   the closest: `bt.dart` (20 sieve trays, binary), `c4.dart` (60 trays, Tier 3 DePriester), `debut.dart` /
   `deprop.dart` (6 components), `bt_packed.dart` (packed beds), `crude.dart` (crude unit). Key fields:
   `"presetId"`, `"displayName"`, `"components"`, `"tier"`, `"tier3Model"`, `"tier1Alpha"`, `"tier1Props"`.
2. **Register** in `Presets` (`config/presets.dart`): a `static const String xyz = 'xyz';`, an entry in **`ids`**
   and an entry in `_json`. Both lists are hand-maintained. Missing from `ids`, the preset still loads, but lever
   ranges fall back to the B-T values (`Simulator._rangeMax`) and scenario `loadPreset` events reject it.
3. **New components or thermo data** if needed (section 6, and `thermo/tier3_nrtl.dart` `nrtlPairs` /
   `thermo/tier3_depriester.dart` `dePriesterCoeffs` for Tier 3). `Tier3Nrtl.fromIds` throws `ConfigException` for a
   missing pair.
4. **New config field** only if needed: `ColumnConfig` in `config/column_config.dart` (field, constructor,
   `fromJson`, `toJson`, `copyWith`, `validate`).
5. **App menu:** add `Presets.xyz: S.xyzName` to `kPresetNames` in `app/lib/widgets/time_bar.dart` and the string to
   `S`. The preset menu is built from this map, so a preset not in it is not offered in the app.
6. **Docs:** `docs/ENGINE_API.md` §4.1 (presets to ship), `docs/SCOPE.md` §4, `docs/PHYSICS.md` for data, and a
   VALIDATION.md case with its reference numbers.
7. **Tests** (below).

### Validation (`ColumnConfig.validate()`)

`Presets.byId` parses, validates and throws `ConfigException` listing the problems. Rules include: 3-60 trays; feed on
a feedable stage (`feedableStages`); Murphree efficiency in (0, 1]; packing ids from `data/packings_json.dart`
(`pall25m`, `pall50m`, `raschig50c`, `struct250`, `struct500`); bed height 0.5-15 m; a partial condenser needs Tier 2
or higher; Tier 1 needs `tier1Alpha` and `tier1Props`. Crude configs (`_validateCrude`): 30 stages, feed on 26, one
bottom steam point, side-draw rules.

### Column kinds and the app

- Tray columns: `TraySection`s with `TrayGeometry` (defaults are the B-T column).
- Packed: `PackedSection`s; stage count per bed = `max(1, round(bedHeight / hetpRef))`. The simulator builds a packed
  model when the config has packed sections. `bt` and `bt_packed` also carry `internalsTemplates` for the
  `internals` lever.
- Crude: `ColumnConfig.crude != null` (`config/crude_config.dart`); `Simulator._build` hands off to `_buildCrude`
  (`sim/simulator_crude.dart`). `ColumnConfig.availableTiers` offers only Tier 2 for preset id `crude` (keyed by id,
  so a second crude preset needs that check widened).
- `app/lib/widgets/column_view.dart` shows `CrudeFlowsheet` when `config.crude != null`, otherwise the classic
  stage painter (`ColumnGeometry`, `packed_painter.dart`). A column that is neither needs a new branch there.
- The app's sandbox loads every preset with `hydraulics: full` (`SimController._sandboxConfig`); scenarios use the
  preset's own setting plus overrides. Check the preset in both modes.
- The diagram tabs offered depend on the component count (`SimController.diagramTabOrder`: T-x-y for binaries,
  Products for multicomponent and crude).

### Tests

No test enumerates `Presets.ids`. Add one that loads and runs the preset, for example modelled on
`test/m7_presets_test.dart` (`Simulator(Presets.byId(id), options: const SimOptions(seed: 3), warmStart: false)`),
checking steady state and component and energy balance as `conservation_test.dart` does for `bt`.

```sh
cd packages/lowsys_engine && dart test test/m7_presets_test.dart test/m5_columns_test.dart
cd app && flutter test test/m7_ui_test.dart      # preset menu and multicomponent UI
```

---

## 4. Fault

### Checklist

1. **Add the value** to `enum FaultType` in `lib/src/faults/fault_spec.dart` (22 values now, `trayDamage` to
   `cotUpset`; the F-numbers are in `docs/SCOPE.md` §5).
2. **Label:** add a case to `faultLabel` (same file). Its `default: return t.name;` hides a missing case.
3. **Effect:** add a case to `FaultManager.apply` (process effects into `EffectiveParams`) or `applyCrude` (crude
   effects into `CrudeFaultState`) in `faults/fault_manager.dart`. Both switches end in `default: break;`, so a
   missing case compiles and does nothing. New effect fields go in `faults/fault_effects.dart`. Instrument and valve
   faults are handled in the control system instead.
4. **Validation:** `ControlSystem.validateFault` (`control/control_system.dart`) for location and parameter rules; the
   simulator hooks it up as `_faults.validator` (crude: in `simulator_crude.dart`).
5. **Scenarios:** fault names are checked against `FaultType.values` automatically. Add a diagnosis category or
   location to `ScenarioDef.diagnosisCategories` / `diagnosisLocations` if drills will use a new one.
6. **App:** faults are injected from hand-written cards, so add one: `widgets/fault_panel.dart` (tray, packing, feed,
   instrument and valve faults), `widgets/process_fault_card.dart` (`_Def` list for condenser/reboiler faults),
   `widgets/crude_fault_panel.dart` (crude). Stage faults drawn on the column are a switch with `default: break` in
   `painters/column_painter.dart`.
7. **Docs and tests:** PHYSICS.md / ENGINE_API.md §9 for the model; a VC-12 symptom test
   (`test/validation/vc12_fault_symptoms_test.dart`) and cases like `test/m8_faults_test.dart`, `m9_faults_test.dart`.

After adding the value, `grep -rn "FaultType\." packages app/lib` and check every switch, since the `default`
branches hide omissions.

---

## 5. Lever

1. **List it** in `Simulator._buildLevers` (`lib/src/sim/simulator.dart`) as a `LeverSpec` (`id`, `label`,
   `quantity`, `min`, `max`, `defaultValue`, `tiers`, `boundLoop`, `requiresPause`, `group`, `integer`, `options`).
   Values are SI.
2. **Apply it** in `Simulator.setLever`: add a `case '<id>':` to the `switch (id)`. The switch has no default, so a
   listed lever with no case is accepted and does nothing. Crude columns go through `_crudeSetLever`
   (`simulator_crude.dart`) instead.
3. **Scenarios:** add the id to `ScenarioDef._leverPattern` if scenarios may set or lock it, and `lever.<id>` is then
   a valid metric path through `metricPathPattern`.
4. **App:** the lever panel lists `runner.levers`; add any label or help text to `S`.
5. **Docs and tests:** `docs/ENGINE_API.md` §6.3 lever list; a test that sets the lever and checks the response.

---

## 6. Component and packing data

- **Component:** add an entry, keyed by id, to the JSON map in `lib/src/data/components_json.dart` (14 named
  components). Fields: `name`, `mw`, `tb`, `tc`, `pc`, `omega`, `dHvapTb`, `cp0`, `dCp`, `rhoRef`, `tRef`,
  `sigmaRef`, `vpKind` (`antoineLog10MmHgC`, `dippr101`, `leeKesler`), `vpCoeffs`; optional `zraOverride`. SI units.
  Parsed by `Component.fromJson` (`thermo/component.dart`) and cached by `ComponentDb.load()`. Record the source in
  `docs/PHYSICS.md` §2.1-§2.2 and add a VC-10 thermo check.
- **Tier 3:** NRTL pairs in `thermo/tier3_nrtl.dart` `nrtlPairs` (methanol-water, ethanol-water, acetone-chloroform),
  DePriester coefficients in `thermo/tier3_depriester.dart` `dePriesterCoeffs` (light hydrocarbons; `kAt` flags
  `outOfRange` instead of clamping). `ThermoFactory` picks the model from `tier3Model` (`nrtl`, `dePriester`,
  `sameAsTier2`).
- **Packing:** `lib/src/data/packings_json.dart`; hydraulics in `model/packed_hydraulics.dart`. The current table is
  quoted from memory (see `docs/OPEN_ITEMS.md`); cite a checked source for new entries.

---

## 7. Explain entry (math overlay)

1. Add a subclass of the sealed `ExplainTarget` in `lib/src/explain/explain_types.dart` and export it if it is new
   public API.
2. Add a case to `ExplainEngine.explain` (`explain/explain_engine.dart`) and implement it, returning an
   `ExplainResult` of `EquationGroup`s. The switch has a `default` that returns "Not available", so a missing case is
   not a compile error. Crude targets go to `ExplainCrude` (`explain/explain_crude.dart`).
3. Open it from the app with `SimController.openMath(target)`; test it like `test/m7_explain_test.dart`.

---

## 8. Instruments, loops and alarms

- Instrument types and fault kinds: `lib/src/control/instrument.dart`. Instrument specs, loops and alarms are built in
  `control/control_system.dart` (`_buildAlarms`; alarm texts are English strings in code). Crude loops are in
  `control/crude_control.dart` (`CrudeControl extends ControlSystem`).
- App maps keyed by loop tag are hand-maintained in `app/lib/widgets/loops_panel.dart`: `kLoopValve`, `kLoopMeter`,
  `kLoopTitle`. Add a new loop there.
- A new loop tag must match `ScenarioDef._loopPattern` to be used in scenarios.
- Specs: `docs/ENGINE_API.md` §10, `docs/PHYSICS.md` §10; tests VC-16 (controllers), VC-22 (instruments), VC-24/25
  (alarms).

---

## 9. App panel or tab

- Control tabs (Levers, Loops, Balance, Trends, Faults, Energy) are `ControlTabs` in `app/lib/widgets/fault_panel.dart`:
  one `btn(label, icon, index)` per tab and a `switch` on `sim.controlTab.value` that builds the panel. Add both.
- Diagram tabs (McCabe-Thiele 0, Products 3, T-x-y 2, ...) are in `app/lib/widgets/diagram_head.dart` (title and body
  switches) with the order in `SimController.diagramTabOrder`.
- Breakpoint layouts are in `app/lib/layout/sim_layout.dart`; they place the column panel, diagram panel and
  `ControlTabs`, so a new tab needs no layout change.
- Panels read state from `SimController` (via `AppScope.of(context).sim`) and its snapshot; colours and text from
  `LowsysThemeScope.of(context)`; strings from `S`.
- Test layout at small sizes and text scale 1.3 (`test/validation_m10_a11y_test.dart`, `test/layout_test.dart`).

---

## 10. Persisted settings

- App settings: `SimController.restoreSettings` reads keys from `saveStore` (`settings.theme`, `onboarding.done`); a
  setter writes them (`setTheme`). A new setting needs both, wrapped in try/catch like the existing ones.
- Stores: `controllers/save_store.dart` (interface; `MemorySaveStore`), `save_store_io.dart` (one file per key under
  `APPDATA`, `XDG_DATA_HOME` or `~/.local/share`, folder `LowSYS`), chosen by `save_store_open.dart`.
- Engine state: `SimRunner.save()` / `loadSaved(...)`; scenario state through `ScenarioRunner.toJson` / `loadJson`. A
  new piece of engine state that must survive a save goes in both.
