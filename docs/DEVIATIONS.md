# LowSYS — Deviations and open choices

Everything in this file is a place where the M1 implementation differs from, or fills a gap in, the specification. Each entry gives the reason. PHYSICS.md is not changed.

## Engine

| # | Where | Deviation / choice | Reason |
|---|---|---|---|
| E1 | ENGINE_API.md 4 preset JSON | The example lists `feeds[0].flow`, `refluxFlow`, `boilup` as 0.0277778 / 0.0277778 / 0.0416667 and says "All JSON values are SI (mol/s)". Those numbers are kmol/s. The shipped preset uses 27.7778 / 27.7778 / 41.6667 mol/s (100 / 100 / 150 kmol/h). | VALIDATION.md 0 says 1 kmol/h = 0.2777778 mol/s; with the spec numbers the column would be fed 1000x too little and PHYSICS.md 5.3's holdup numbers (27.8 mol/s of liquid per tray) would not hold. |
| E2 | PHYSICS.md 10.2 | Ideal flow controllers (FC-101/102/103) use a first-order lag of 1.0 s instead of 3 s. | VC-7.2: tray 1's liquid flow must reach 63 % of a reflux step within 1-4 s *measured from the lever change*. With 3 s the controller lag alone makes it 5.5 s. With 1 s: tray 1 3.5 s, tray 20 31 s (inside 20-45 s). Steady states are unaffected. |
| E3 | PHYSICS.md 13.1/13.3, ENGINE_API.md 6.1 | `runToSteadyState()` runs until the 13.3 monitor declares steady and then keeps marching until the residual is below `polishTolerance` (default 1e-11). `SteadyStateResult.simSeconds` is the time at which the monitor declared steady (VC-7.4: 5.15 h at dt = 0.5), `totalSimSeconds` includes the polish (about 8.3 h). | The monitor criterion alone (delta < 1e-7 for 5 checks) leaves a 2e-6 error in x_D because the slowest mode has tau = 1643 s. VC-4/VC-6 want 1e-6, VC-18 wants 1e-8 on the converged state. |
| E4 | ENGINE_API.md 5.5 | No shipped `steady_cache/*.dart` JSON. The warm start runs `runToSteadyState()` once per distinct configuration and memoises the state in memory (about 0.15 s). | The same code path is exercised; nothing can go stale. A shipped cache can be added when presets multiply (M5+). |
| E5 | ENGINE_API.md 7.1 | `SimSnapshot.streams` (and `Kpis.d`, `b`, `boilup`, reflux) report the flows the solver *used in the last completed step*, not the flows the valves will deliver next. | Integrating snapshot flows then closes the component balance to round-off (a tester found 5e-6 closure error otherwise). |
| E6 | ENGINE_API.md 7.1 | `SimSnapshot` has three extra fields: `levers` (all lever values, SI), `feedQ`, `murphree`. `Kpis.qc`, `qr`, `energyResidual` are NaN in Tier 1; `columnDp` and `maxFloodPct` are 0 (ideal hydraulics). | The McCabe-Thiele builder and the UI need q, E and the lever values without reaching into the simulator. |
| E7 | ENGINE_API.md 6.1 | M1 `Simulator`: `setTier`/`setHydraulicsMode` throw `UnsupportedError` for anything but Tier 1 / ideal. `rewind` returns false. No `faults`, `scenario`, `trends`, `explain`. `SimRunner` has no `injectFault`/`clearFault`/`explain`. | Not in M1 scope (SCOPE.md 8). |
| E8 | ENGINE_API.md 6.6 | `SimRunner` has additions: `levers`, `thermo`, `config`, `rebuild`. `Simulator` has `beginSteadyRun` (resumable run), `advanceFast`, `halted`, `steadyResidual`. | The app needs them; the spec leaves the shape open. |
| E9 | SCOPE.md 8 M1 | `ControlSystem` supports `setMode`/`setOp` on LC-101/LC-102 in the engine API, although the app keeps them AUTO. | VC-3.2 (dynamic total reflux) needs the D and B valves closed with the loops in MAN. |
| E10 | ENGINE_API.md 6.3 | Extra lever ids: `alpha` (custom-alpha preset only, 1.05-10), `refluxMode`, `distillateValve`, `bottomsValve` (OP %, effective in MAN). `setLever` throws `RangeError` outside the `LeverSpec` range and `ArgumentError` for unknown ids. `feedZ.<light>` rescales the other component(s) so z sums to 1. Setting `refluxFlow` does not change the reflux mode; the UI sets `refluxMode` explicitly. | The spec lists the ids but not these semantics. |
| E11 | ENGINE_API.md 7.2/7.3 | Names the spec leaves open: `SteppingResult { stages, count, fractional, feedStage, xIntersection, yIntersection, converged }`, `StageStep(x, y)`, `McCabeThieleMath.gilliland` returns a record `({x, y, n})`, `McCabeThieleMath.qLinePinch` returns `({x, y})`. `McCabeThieleData` has an extra `operatingIntersection`. `StepDebug` fields: `dt, feedFlow, refluxFlow, distillateFlow, bottomsFlow, boilupFlow, feedRate[], distillateRate[], bottomsRate[]` (rates in mol/s per component). `Presets.byId('bt')` loads presets; `ColumnConfig.applyOverrides` implements the dotted-path `overrides` of scenario JSON. `SolverHealth` lives in `core/ids.dart`. | Spec silent. |
| E12 | PHYSICS.md 10.1 | A setpoint change does not kick the PI output through the proportional term (the previous error is re-based). The transmitter filter is 2 s and the valve lag 2 s for the level loops. | Avoids a visible jump when the learner drags a level SP; matches 10.3 for the filter/lag. |
| E13 | ENGINE_API.md 4 | `ColumnConfig` omits the fields of later milestones (`sideDraws`, `pumparounds`, `strippers`, `steam`, `keys`, thermosyphon geometry). | Not used before M6-M9. |
| E14 | PHYSICS.md 12.7 | Step failure handling is implemented (restore, halve up to 3 times, then `halted`) but the "rewind 60 s" history ring is not (M3). | Persistence is M3. |
| E15 | ENGINE_API.md 15 | The "no allocation in `step()`" rule is followed by construction (all scratch preallocated, `Float64List` only) but there is no automated retained-memory test yet. | Time. |

## App

See the section appended by the app work (fonts, layout choices) below.

## Later engine notes
- E16: Closed valve flows are clamped to exactly 0 below 1e-12 mol/s.
- E17: `runToSteadyState` hitting its cap (default 48 h) is not a failure when the column is just slow: `SteadyStateResult.slowModeTau` (estimated from the residual decay) and `stillConverging` are set, and the app reports "still converging (slow mode tau about X h)" and offers to continue. Callers may pass a larger `maxSimSeconds`.
- E18: The 1 s flow-controller lag (E2) is kept; VC-7.2 depends on it.

## App (M1)

- A1 Fonts: the OFL fonts of ENGINE_API.md 13.6 are NOT bundled (downloading font files needs the user's go-ahead). The Blueprint typography tokens name Architects Daughter / Share Tech Mono / STIX Two Math and carry fallbacks (Ink Free, Consolas, Cambria on Windows; `casual`/`cursive`/`monospace` on Android). To bundle, drop the .ttf files in `app/assets/fonts/` and add a `fonts:` section to `app/pubspec.yaml`; no code change is needed.
- A2 The tray inspector sits under the chart (portrait, medium, desktop) or on top of the lever panel (landscape, only while a stage is selected).
- A3 The expanded layout has a single diagram panel (McCabe-Thiele only in M1) and the KPI strip as the bottom strip.
- A4 Frame loop: the debt cap is max(2 frames x speed, 1 s) so that slow speeds always reach one 0.5 s step; the "speed-limited" flag also fires when the cap is hit.
- A5 No fps measurement from the emulator: `dumpsys gfxinfo` reports nothing for Flutter's surface and the emulator uses software GL. Engine cost is 5 us/step (JIT, 22 stages).
- Screenshots: `docs/screenshots/m1/*` come from `flutter test test/layout_test.dart` with `LOWSYS_SHOTS=1` (real OS fonts loaded; Material icons render as boxes in those test images), plus real captures from the Windows exe and the emulator.
- A1 (resolved): Architects Daughter, Share Tech Mono and STIX Two Math (SIL OFL, from the google/fonts repo) are bundled in `app/assets/fonts` with their OFL texts in `app/assets/fonts/LICENSES`. The subscript zero glyph is missing from Architects Daughter, so labels use "L0".
- A6 UI fps (Windows profile build, 100x, 40 s, `--dart-define=LOWSYS_PERF=40`): 60.6 fps, frame total p50 20.2 ms / p95 25.5 ms / p99 28.9 ms, 0.12 % of frames over 32 ms, achieved 101x. Phone portrait and landscape callouts are tags only (values live in the KPI strip and inspector).
