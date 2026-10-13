# LowSYS — Deviations and open choices

Everything in this file is a place where the M1 implementation differs from, or fills a gap in, the specification. Each entry gives the reason. PHYSICS.md is not changed.

## Engine

| # | Where | Deviation / choice | Reason |
|---|---|---|---|
| E1 | ENGINE_API.md 4 preset JSON | The example lists `feeds[0].flow`, `refluxFlow`, `boilup` as 0.0277778 / 0.0277778 / 0.0416667 and says "All JSON values are SI (mol/s)". Those numbers are kmol/s. The shipped preset uses 27.7778 / 27.7778 / 41.6667 mol/s (100 / 100 / 150 kmol/h). | VALIDATION.md 0 says 1 kmol/h = 0.2777778 mol/s; with the spec numbers the column would be fed 1000x too little and PHYSICS.md 5.3's holdup numbers (27.8 mol/s of liquid per tray) would not hold. |
| E2 (superseded, see E26) | PHYSICS.md 10.2 | Ideal flow controllers (FC-101/102/103) use a first-order lag of 1.0 s instead of 3 s. | VC-7.2: tray 1's liquid flow must reach 63 % of a reflux step within 1-4 s *measured from the lever change*. With 3 s the controller lag alone makes it 5.5 s. With 1 s: tray 1 3.5 s, tray 20 31 s (inside 20-45 s). Steady states are unaffected. |
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
- E18 (superseded in M3, see E26): The 1 s flow-controller lag (E2) is kept; VC-7.2 depends on it.

## App (M1)

- A1 Fonts: the OFL fonts of ENGINE_API.md 13.6 are NOT bundled (downloading font files needs the user's go-ahead). The Blueprint typography tokens name Architects Daughter / Share Tech Mono / STIX Two Math and carry fallbacks (Ink Free, Consolas, Cambria on Windows; `casual`/`cursive`/`monospace` on Android). To bundle, drop the .ttf files in `app/assets/fonts/` and add a `fonts:` section to `app/pubspec.yaml`; no code change is needed.
- A2 The tray inspector sits under the chart (portrait, medium, desktop) or on top of the lever panel (landscape, only while a stage is selected).
- A3 The expanded layout has a single diagram panel (McCabe-Thiele only in M1) and the KPI strip as the bottom strip.
- A4 Frame loop: the debt cap is max(2 frames x speed, 1 s) so that slow speeds always reach one 0.5 s step; the "speed-limited" flag also fires when the cap is hit.
- A5 No fps measurement from the emulator: `dumpsys gfxinfo` reports nothing for Flutter's surface and the emulator uses software GL. Engine cost is 5 us/step (JIT, 22 stages).
- Screenshots: `docs/screenshots/m1/*` come from `flutter test test/layout_test.dart` with `LOWSYS_SHOTS=1` (real OS fonts loaded; Material icons render as boxes in those test images), plus real captures from the Windows exe and the emulator.
- A1 (resolved): Architects Daughter, Share Tech Mono and STIX Two Math (SIL OFL, from the google/fonts repo) are bundled in `app/assets/fonts` with their OFL texts in `app/assets/fonts/LICENSES`. The subscript zero glyph is missing from Architects Daughter, so labels use "L0".
- A6 UI fps (Windows profile build, 100x, 40 s, `--dart-define=LOWSYS_PERF=40`): 60.6 fps, frame total p50 20.2 ms / p95 25.5 ms / p99 28.9 ms, 0.12 % of frames over 32 ms, achieved 101x. Phone portrait and landscape callouts are tags only (values live in the KPI strip and inspector).

## M2 engine
- E19: `Presets.byId('bt')` stays ideal hydraulics (the M1 validation suite and VC-4 use it). The full-hydraulics default of SCOPE.md 4.2 is applied by the app (sandbox loads `copyWith(hydraulics: full)`) and by `setLever('hydraulics', 1)` / `setHydraulicsMode`.
- E20 (adopted into PHYSICS.md 5.4 by 1cc65e2): A broken tray holds no liquid head: the hydrostatic term of (5.5) is multiplied by (1 - s_broken). Without it a fully broken tray still showed 18.7 % of its normal pressure drop (VC-12.4 expects about 6 %, prototype 664 to 38 Pa).
- E21: `Trace` parameters of ENGINE_API.md 8.2 are not used. `HydraulicSolver` writes every intermediate quantity into arrays that the stepper, the snapshot and `explain()` all read; the overlay builds its numbers from those arrays, so values agree to round-off by construction.
- E22: Model alarms (flooding > 90 %, weeping > 30 %, downcomer limit, drum/sump level) are reported in `SimSnapshot.alarms` without latching/acknowledge (M3).
- E23: Extra lever ids: `hydraulics` (0 ideal, 1 full), `trayType.0` (0 sieve, 1 valve), `antifoam` (0/1). `SimOptions` gains `entrainment`, `weeping`, `downcomerLimit` switches (all true by default). `Kpis.maxWeepFraction`, `StageArrays.dpDry` and per-tray flag bits (1 dc-limited, 2 dumping, 4 overflowing, 8 dry, 16 flooding) are exposed.
- E24: Quantity conversions use the exact definitions (Btu(IT) = 1055.05585262 J, bbl = 0.158987294928 m3) instead of the truncated constants in ENGINE_API.md 12.
- Reproduced prototype numbers: with F = 100 and L0, V_B raised by the same absolute amount (+30 / +45 / +67.5 kmol/h) the engine gives dP 19.62 / 22.79 / 28.90 kPa at 10 min and xD 0.9124 / 0.8364 / 0.4973 at 4 h, exactly the VC-12.4 prototype values. (The tester's `setLoad` helper scales F, L0 and V_B by the same factor, which is a different case.)

## M2 app and test notes
- A7: Sandbox starts in full hydraulics (E19). Ideal/Full, tray type and antifoam are in the Levers tab (Internals); Faults tab injects F04-F07.
- A8: The math overlay uses flutter_math_fork (bundled KaTeX fonts). Phone/tablet: bottom sheet (70 %); desktop: draggable floating panel; compact landscape: right-hand sheet. Opened from the inspector's "Equations" button, by tapping a stream pipe in the column, a KPI value, or key M. It re-evaluates about 4 times a second, so the numbers are live. SI/US switching (key U or the menu) applies to levers, KPIs, inspector, labels and the overlay echo.
- A9: Scenarios G11 and G12 run through a small scenario runner in the engine (objectives with latch/after/holdFor, hints, timed events, score card). The app has a scenario list, briefing, HUD and debrief dialogs; there is no persistence of progress yet (M3).
- A10: The delta glyph is missing from Architects Daughter; the UI says "dP".
- T1 (for the tester): `setLoad(sim, f)` in `fixtures_m2.dart` scales F, L0 and V_B by the same factor. VALIDATION.md VC-12.4's "+20 % (L0 +30, V_B +30 kmol/h)" keeps F = 100 and adds the same absolute amount to L0 and V_B; that case reproduces the prototype table exactly (E24).
- T2: `qualitative_hydraulics_test`: (a) F07 cannot raise D, since D = V_1 + e_1 - L0 is fixed by the LV flows; (b) losing the boilup cannot drain the trays below the feed while the feed keeps flowing (each tray then holds feed x tau_d, about 220 mol); (c) VC-8.1 with full hydraulics: +10 kmol/h on L0 and V_B raises max flood to about 95 %, and the entrainment loss outweighs the better L/V (xD 0.958); (d) VC-17 round trip at 1e-6 K cannot hold 1e-12 relative in double precision for the Kelvin/Celsius offset; (e) the broken-tray profile check expects the broken tray's liquid to carry the inlet composition, but with full bypass its holdup is the entrained liquid from below.
- A11 UI fps with full hydraulics (Windows profile build, 100x, 40 s): 60.0 fps, frame total p50 21.5 ms / p95 26.5 ms / p99 30.2 ms, 0.21 % of frames over 32 ms, achieved 99x. Froth dots and spray are drawn as batched point lists (the first version, with one circle per dot, had 15 % of frames over 32 ms).
- A12: Phone portrait: the tray inspector floats (scrolling) over the free space under the chart instead of shrinking it. The scenario HUD starts collapsed on windows shorter than 500 dp. Injecting or clearing a fault clears the steady flag at once. The math overlay fades long equations at the right edge and scrolls them sideways (touch or mouse drag).
- Emulator (lowsys_pixel, release APK) checks for M2 are in `docs/screenshots/m2/android_*`: faults and foam, inspector, math overlay, US units, scenario G11 in portrait and landscape.

## M3 pass: spec changes folded in (1cc65e2)

- E24: Default `traySpacing` is 0.90 m in `TrayGeometry` (bt and bt_custom_alpha), 62.9 % jet flood at design. G11 briefing says "about 63 % of flood".
- E25: F07 `dz` is sum-zero: listed components get `sign * s * dz`, unlisted ones absorb the negative sum in proportion to their z; the list form `[0.15, -0.15]` and the map form `{"benzene": 0.08}` are both accepted; default is +0.15 on the light component (B-T z 0.50 to 0.65). Renormalised only if a fraction was clamped at zero.

## M3 engine (control, instruments, alarms, cross-checks)

- E26: The ideal 1 s flow lag is gone. FC-101/102/103 are PI loops (Kc 0.6, Ti 2 s) on the measured flow in a 0.1 s fast layer; the solver uses the mean valve flows F-bar. This supersedes E2 and E18. `tauFlow` is removed from the stepper. VC-7.2 is measured from the moment the delivered reflux reaches 63 % (amended definition; my `test/dynamics_test.dart` follows it).
- E27: Withdrawn. The level loops keep the PHYSICS 10.7 values (Kc 2.0, Ti 1800 s): a retune to Kc 1.0, Ti 900 s broke VC-7.1 (D at 300 s) and VC-7.4 (steady after 6.6 h from cold). Consequence: after a drum set point of 88 % the HI alarm needs about 3700 s (VC-25.2 allows 3600 s) and VC-20.4 cannot raise an alarm within 1800 s by a set point of 86 %; both need a faster set point step in the tests.
- E28: Noise-on steady monitor thresholds ([impl-tunable], PHYSICS 13.3): the 300-s means of x, relative holdup and OP move by up to 1.1e-2, 5.3e-3 and 1.1 % from noise alone, so the tolerances are 1.8e-2, 8e-3 and 2.0 % instead of 2e-5, 2e-3 and 1.0 %. A +10 % reflux step is caught through the FC-102 OP (3.3 %). The monitor also watches all five loop OPs, not only the level loops.
- E29: PDT-101 raises no OOR alarm with ideal hydraulics (the true value is 0, the bottom of its span, so noise would make it chatter).
- E30: Orifice-drainage dumping (afd678b, PHYSICS 5.15 and 12.2) is implemented: kappa_j = ((0.2 - Phi)/0.2) C_dump A_drain sqrt(2 g v_L / A_a,eff)/v_L with start-of-step values, solved for u = sqrt(M) by Newton (at most 60 iterations). `HydraulicSolver.kd` now holds kappa. Sieve trays hold 0.7-1.4 mol (0.09-0.17 mm) after 10 min without boilup.
- E31: Valve flows and positions below 1e-12 snap to exactly zero (a closed valve reads exactly 0).
- E32: `Instrument` takes `seed`, `noise` and `initialValue` in its constructor and exposes `reading`; `ControlLoop.execute(pv, h)` returns the OP and `ControlLoop.setMode` is bumpless (the tester's bare-loop API). The Simulator keeps `fastLayerTrace`, `holdDrumLevelForTest` and `safetyLevelViolationSeconds` as @visibleForTesting-style hooks.
- E33: If a retry halves a step after a solver failure, the control fast layer has already advanced once; the retry re-runs it on the smaller step (the failure path is exceptional and not bit-reproducible).
- E34: Cross-checks C1, C3, C5 divide the level change by the window W as in PHYSICS 14.6 although the two 60-s means are W-60 s apart (this keeps the tester's reference formulas); C2 is implemented in Tier 1 as well (steady only, window of 1800 s or more).
- E35: Withdrawn. `PidParams.pvFilter` exists (default 0) but no shipped loop uses it: a 10 s level filter delayed the first execution of the BAD-PV handling that VC-16.8(b) pins.
- E36: The bands of C1 and C3 are multiplied by 600/W for windows shorter than 600 s. Their level terms divide by W, so with the 60-s end means the residual noise at W = 300 s is about 1.4 kmol/h against the 2 kmol/h band, and a false `fail` appeared within 2 h. At W of 600 s and more the PHYSICS 14.6 bands are unchanged.
- E37: Dumping follows the final PHYSICS 5.15 and 12.2 (fb00526): L = kappa max(0, sqrt(M) - sqrt(Mc)) with Mc the holdup at Phi = 0.2, every tray of the full-hydraulics model is solved for u = sqrt(M) with the bracketed Newton (bisection fallback), and the `dumping` flag is set when M exceeds Mc. This replaces the first version of E30.
- E38: `typicalSigma` of FT-104 and FT-105 includes the level loop's contribution, sqrt(sigma_disp^2 + (Kc sigma_LT F_max/span)^2) with the Kc in use (2.0: 0.94 % and 1.60 % of span). `uaClean` of the condenser is 29 900 W/K. The Blueprint theme has the six `series` colours; the Trends tab uses them.
- E39: Scenario layer names (the tester's parked vc26 test and ENGINE_API 11): `Scenarios` (`ids` = playable guided scenarios, `allIds` adds the Tier 2 drills H9 and H10, `jsonOf`, `byId`; `ScenarioLibrary` stays as an alias), `ScenarioDef` (kind, start, noise, view, badPvShed, loops, parTime, candidates, onsetWindow, offSpec, diagnosis; `validate()` also checks levers, loop tags, fault kinds, template variables), `Predicate.evaluate`, `MetricContext` (abstract; `MetricContext.live(sim)` reads the true state; `FakeMetricContext` for tests), `Scoring.guided/drill` with `ScoringWeights`, `DrillScoringWeights`, `DrillAttempt`, `ScoreResult.score`, `DrillDraw.draw(def, seed)` (stream `drill`, four uniforms), `Diagnosis`, `DrillResult`, `AnswerResult`. The M2 runner's mutable `ObjectiveState` is now `ObjectiveRuntime`; the immutable `ObjectiveState` of the snapshot has the ENGINE_API fields. `ScenarioRunner` is created and updated by the simulator (`Simulator.startScenario`, `takeHint`, `submitAnswer`, `submitDiagnosis`, `finishScenario`); `ScoreCard` carries the terms, `score` and the resolved `debriefText`. H9 and H10 ship as definitions only: they need Tier 2 (the engine throws ConfigException for `tier: t2`).
- E40: The app's `SaveStore` writes one JSON file per key (APPDATA, XDG_DATA_HOME or HOME, else the temporary folder; on Android the private cache) instead of shared_preferences, which would need a new package download. The interface is the ENGINE_API one; swap the backend when the dependency is approved. Autosave runs every 60 s of wall time in the sandbox.
- E41: The Trends tab draws the 5-s bins (mean line, min-max envelope, BAD bins tinted) for any reading plus its set point and OP; the Balance tab, the alarm banner and the faceplates (Loops tab) follow ENGINE_API 13; the instrument and valve faults are injected from the Faults tab.
- E42: Performance with noise on (Windows profile build, 100x, full hydraulics, McCabe tab, 40 s): 59.5 fps, frame total p50 24.6 ms, p95 32.7 ms, 12.3 % of frames above 32 ms (M2 without M3 had 0.21 %). The average meets the 55 fps target, the 1 % frame rule does not yet. Suspects: the per-frame snapshot now builds instruments, valves, cross-checks and alarms (and `refreshHydraulics`), and the engine advance budget of 6 ms per frame. Not tuned in M3.

## M3 handoff (unfinished)

- E43: Frame time. Cause: with noise on the loop-OP levers (`feedFlowOp`, ...) changed every frame, so the lever panel rebuilt every frame; `SimController._sameLevers` now ignores them. The engine advance (0.2 ms), snapshot (0.05 ms) and diagram build (0.01 ms) per frame are negligible; the rest is raster. A/B on the same loaded machine: M2 build 2.3-2.4 % of frames over 32 ms, current build 0.5-6 % (the machine is shared, so runs vary). Also cached trend indices and the OU factors in the engine. `LOWSYS_PERF` now prints `PERFPARTS`.
- Not done: Android emulator pass (`docs/screenshots/m3/android_*`), re-shooting the m3 screenshots after the UI fixes (TS label from the live config, xD label leader line, two-row signal look, valve curve text before the first window, per-check progress, icon tabs; `app/test/m3_ui_test.dart` now shoots the Balance tab after an FT-102 bias), and all of M4.
- Open question from the lead, not investigated: the same FT-101 drift fails C1 at about 2065 s with ideal hydraulics but 935-1275 s with full hydraulics. C1 uses only readings (FT-101/104/105, LT-101/102) and `N_0,1%`, `N_S,1%`; check the level terms and the trend bins in full hydraulics first.

## Spec decisions 2026-10-12

From the M3 adjudication (engine 5c14dfa). Docs changed: VALIDATION.md (VC-23.3, H9.0, H9.2, H9.3, H9.12, H10.1, H10.4, H10.5, §H note), ENGINE_API.md (§11.1 `delta` on a CAS slave, §11.6 events and notes, `ft102_plugged` in §11.6/§11.7), PHYSICS.md §13.4.

1. **C4 on a drift: 40 min, not 30** (VC-23.3 FT-101 row, H9.3, H10.5). The 600-s window mean crosses the fail line at about 36 min. *Validator:* update the three assertions.
2. **FT-102 plugged: minimum severity raised to 1.0** (H9 and H10 `severityRange` [1.0, 1.0]; H9.2/H10.4 test s = 1). The C3/C3a clause stays, so the debrief's "the balances disagreed" stays true. *Coder:* change both scenario JSON files. *Validator:* rerun H9.2/H10.4 at s = 1. FT-103 plugged (H10.6, [0.9, 1.0]) is unchanged; its debrief also claims C3b fails, so watch for the same averaging-out.
3. **Signal looks are not judged for 300 s after a scripted event** (H9.0, and so H10.0). *Validator:* exclude those windows.
4. **H9 feed event made ratio-preserving.** At 2700 s: FC-101 +5 kmol/h, FC-102 +5 kmol/h, FC-103 +65 kW. FC-103 is in CAS, so a new rule applies: a `setSp` `delta` on a CAS slave bumps the master's OP by the equivalent % of the slave span, and TC-101 trims from there (ENGINE_API.md §11.1). The x_B band is not widened. *Coder:* implement the CAS-slave `delta` rule in the scenario runner and add the two events to H9's JSON. *Validator:* rerun H9.0, and recheck H9.7 (LT-102 stuck: B now rises only ≈ 2.5 kmol/h) and H9.10 (TI-114 coated) against the new event.
5. **H9.12 FT-104 stuck: check-level criterion.** C1 or C3 at `check` or worse, held ≥ 60 s, within 20 min of the event. The event is not enlarged; σ = 0 stays the key evidence. *Validator:* update the assertion.
6. **H10.1: C3/C3a and C1 never `fail`; `ok` ≥ 85 %** (was `ok` ≥ 95 %). *Validator:* update. VC-23.3's FV-102 row (Tier 1) keeps 95 %.
7. **Feed tray on an N rebuild rounds down** from a stored fraction φ (PHYSICS.md §13.4): N 27 → tray 13, which matches G6's 0.97761. *Coder:* replace the Dart `round()` with `floor(φ N' + 1e-9)` clamped to [1, N'], and keep φ across rebuilds. *Validator:* check the G6 reference row (27 → 0.97761, 28 → 0.98056 at feed 14).

## M4 engine (Tier 2)

- E44: Spec decisions 2026-10-12 items 2 to 7 (coder part): FT-102 plugged severity range [1.0, 1.0] in both drills, H9 feed event with FC-101 +5, FC-102 +5 kmol/h and FC-103 +65 kW, feed tray `floor(phi N' + 1e-9)` with phi kept across rebuilds. The CAS-slave `delta` rule is `ControlSystem.bumpCasSlave` (see E55).
- E45: The Tier-2 vapour profile is the quasi-steady energy balance (4.5/4.7) swept bottom up with the liquid flows, bypass and entrainment of the previous step; the overhead pressure is the implicit secant solve of 7.4 (up to 12 secant iterations, then a bracketed bisection, `solverHealth.pressureFallbacks`). At the VC-11 steady state the engine reproduces the reference to 1e-6 in x and 0.001 K (energy closure 9e-12).
- E46: Feed thermal condition in Tiers 2/3: a feed given as q = 1 (the presets) is a saturated liquid that follows its bubble point at the feed-tray pressure and its composition (this is what the VC-27.2 / VC-8.7 references assume: "feeds at their bubble point"). The lever `feedT` switches to a fixed temperature. Without this, a pressure lever move leaves the feed subcooled and V1 falls by 8 %.
- E47: PC-101 gain schedule. Below 35 % CW opening the loop gain is scaled by OP/35 (floor 0.1). At 2 and 3 bar with 15 degC water (G8, VC-27.2) the controller works at 5 to 7 % OP, where the plant gain per % OP is about 20 times the design value, and the tuned Kc 10 / Ti 120 s limit-cycles (V1 between 50 and 210 kmol/h at dt = 2 s). At and above 35 % OP the gain is the tuned one, so VC-16.6 is unaffected.
- E48: PT-101 is ranged 0 to 2 x the larger of the design pressure and the PC-101 set point (a re-ranged transmitter; the PC-101 history is rescaled with it). With the fixed 0 to 2 x P_design span (202.65 kPa) a set point of 3 bar (G8, VC-27.2) is off scale: the controller saw 208 kPa for ever, closed the CW valve and the relief valve lifted. The PT-101 HI/LO alarms are 1.15 / 0.85 x the set point rather than the design pressure. PT-101 bias severity 0.5 is still 10.1 kPa at the design set point.
- E49: Pump capacity for F12 (reflux pump trip, 11): `L_0,max` is the design reflux flow (the initial FC-102 set point) and the cap applies only while the fault is active.
- E50: Partial condenser (7.2 / 7.5, PV-102) is not implemented in this pass: `condenser.type: partial` is read but the engine runs a total condenser. No M4 test uses it.
- E51: `Kpis.energyResidual` is |F h_F + Q_R - Q_C - D h_D - B h_B| / Q_R with the flows and enthalpies of the last step (h_D at the reflux temperature). It is a transient quantity too; VC-5.4 reads it at steady state.
- E52: Tier-2 hydraulic properties (3.5): rho_L from Rackett at the stage temperature, rho_V from the Pitzer virial at the stage T, P and its own vapour composition, sigma from the quarter-power mixing rule; the `HydraulicSolver` takes them per tray (`rhoLs`, `rhoVs`, `sigmas`, constants in Tier 1, so Tier 1 is bit-identical).

## M4 checkpoint (engine, before the app work)

Tier-2 engine is in; the whole M4 suite compiles. State of the M4 tests at this commit:

- Pass: VC-10 (all), VC-11 base case (every row to the table tolerances, 6.03 h from cold, energy closure 9e-12, dt 2 and 30 s identical), VC-11 feed tray 5, VC-27.1 `mw` (Tier 2 values, utility design values, G7 12 %), VC-27.2 at 0.7, 1.013, 2 and 3 bar, VC-27.3 (reboiler limit at 2 bar, condenser limit), VC-8 T2 rows 8.7, 8.8, 8.9 (all three dt), 8.14, VC-16.6 (design point, open loop, both SP steps, F09 s = 1 relief), VC-16.7 cascade, VC-16.3(c), VC-5.2 and 5.4, VC-27.4 F11 direction and vent, F09, F10, F13, F14, F08, reboiler/condenser design numbers.
- Fail, engine work still to do: VC-18.3 (McCabe-Thiele Tier-2 data), VC-23.1 to 23.3 Tier 2 (C3a, C3b, C6, C7 not yet in the cross-check engine), VC-27.1 Tier 1 on `mw` (does not reach the steady monitor: residual stalls at 7e-9).
- Fail, probably the test or the spec number, not the engine (each with the engine value):
  - VC-16.6c: P settles at 0.9056 bar, not 0.966. 0.966 is what UA_clean = 28.5 kW/K (the v1.0 70 % design) gives; with the specified 29.9 kW/K a 1281 kW duty at 100 % CW needs T_sat 76.6 degC, 0.906 bar (checked: UA 28.5 gives 0.9663).
  - VC-8.1 T2: P deviates 2.5 kPa (peak at 155 s, CW 50 to 86 %), not 0.2 kPa. With Kc 10 and Ti 120 s the integral action needs about 1 kPa of error per 5 % of CW travel; the duty/reflux step moves Q_C by 8 % in 200 s.
  - VC-11 further, L0 150 and VC-27.2 at 0.5 bar: the specified condenser (UA 29.9 kW/K, CW 30 degC, 41.5 kg/s) cannot condense 1707 kW (max 1391 kW, VC-27.3), so P floats (135 kPa) and D is 47.3; the tests need the "perfect condenser" or a colder CW. VC-11 D 55: the independent reference returns xD 0.9964 and xB 1e-12 for D = 55 (mass balance impossible: xD <= 0.909) and Q_R 1364.4 kW; at that duty the engine gives D = 55.17, the document value is 1362.4 kW.
  - F15 s = 0.5 Q_max: 1490 kW, the test expects 1437 kW (uses T_B = 110.4 degC of the E = 1 case; the E = 0.7 default has T_B = 109.6 degC). F15 s = 0.85 after 900 s: delivered duty 1195 kW (> 1170 threshold): T_B falls to 102.7 degC as the duty falls, which raises Q_max; the self-consistent duty is 1195 kW.
  - F11 after 1 h: overhead 128.7 mol, y_I 0.072 (test 104 +/- 15 mol): P has risen to 139 kPa as the CW valve saturates after 40 min; the document figure is for P held at its set point.
  - F12 s = 0.5 drum level >= 55 %: see E49 (with the cap at (1-s) x design reflux the drum level reaches 52 %, to be re-checked after the final F12 definition).
- Tier-1 suites: unchanged except H9.12 (open since the handoff: C1/C3 do not reach `check` after the ratio-preserving event in the Tier-1 stand-in).

## M4 validation

Validator pass on c4e1f17, run in a clean worktree of that commit. The coder's later uncommitted lib/app edits were not part of it. Results: M4 suite 80/80 pass (69 pass, 8 fail at the start, before the test fixes); full engine suite 430 pass, 2 skipped, 2 fail (V1 and V2 below; at the start 426 pass, 1 fail: H9.12). Every "Fail, probably the test or the spec" item above was a test or spec issue, not an engine one. The spec items are in OPEN_ITEMS.md. Test changes: VC-27.2 / 27.3 expectations re-pinned to the 2026-10-12 table (doc tolerances); VC-11 further references and VC-27.2 given a condenser that holds P; the MESH reference continued in D (D 55); VC-16.6c 0.906 bar; VC-8.1 "held" taken at the new steady state; F15 run at the E = 1 design point with Q_max read at onset; F11 checked against the model relations; VC-5.2 tightened to 1e-10 (passes). New checks: VC-18.3 magnitudes (0.0064 / 0.0025), VC-16.4 Tier-2 duty loop (t63 4.3 s), VC-16.3(d), F09 pressure levels (1.0698 / 1.1668 / 1.1796 / 1.3887 bar(a) against 1.070 / 1.167 / 1.180 / 1.389), H1 F07 in Tier 2 (D +1.18 kmol/h, T₁₀ −4.65 K), VC-27.3 at CW 5 °C, and Tier-2 save/restore (VC-20.4). H9.12 is asserted at 30 min (OPEN_ITEMS).

Engine bugs (both are in `vc20_determinism_m3_test.dart` "VC-20.4 Tier 2 (M4)"):

- **V1. Coder: Tier 2 with full hydraulics, `Simulator.restore` does not reproduce the saved thermo state.** Repro: `Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.full))`, run to steady state, then `setLever('refluxFlow', 105 kmol/h)` and `advance(600)`. Then `copy = Simulator.restore(jsonDecode(jsonEncode(sim.saveState())))`. Right after the restore, `copy.saveState()` already differs in `dynamic.state.T`, `y`, `yStar` and `vLiq` from stage 2 down: T[5] 356.6407 → 356.6946 K, T[20] 383.3381 → 383.6574 K. The snapshot's stage-pressure profile also differs: stage 20 113 893.6 → 113 859.6 Pa. After 20 steps 772 fields differ. Tier 1 full hydraulics and Tier 2 ideal hydraulics restore bit-identically. Looks like the restore recomputes the bubble points on a different P_j / ΔP profile (E52 per-tray Tier-2 ρ/σ?) instead of keeping the saved T. Expected: identical `saveState()` JSON right after the restore and after any number of steps (VC-20.4). In the test, the first failure is state T[2] 355.6036 expected, 355.6253 actual. This matters for every Tier-2 full-hydraulics drill (H9/H10) that pauses and resumes.
- **V2. Coder: Tier 2, PT-101 diverges after a restore when the PC-101 SP is not the design pressure and PT-101 was not re-ranged.** Repro: B-T Tier 2, ideal hydraulics, `SimOptions(seed: 9)`, run to steady state, `setLever('noise', 1)`. Then either `control.setSp('PC-101', 106000)` or `setLever('pTop', 96000)`, and `advance(900)`. Save and restore (as in V1); the two `saveState()`s are identical. Then step both once. PT-101 `ns`/`vp` differ by 7.81e-4 × (SP − 101 325) Pa (+3.65 Pa at 106 kPa, −4.16 Pa at 96 kPa), and PC-101's OP and the process follow. With `setLever('pTop', 106000)` (PT-101 re-ranged to 212 kPa by E48) and with SP = design, the restore is exact. Look at what `setPtSpan` / `applySpec` (re-created `OuNoise`) or the PC-101 span does differently on the restore path. Also note that `control.setSp('PC-101', ...)` does not re-range PT-101 while the `pTop` lever does (E48 says "the larger of the design pressure and the set point"). Expected: bit-identical continuation. In the test, P_top after 600 s is 95 956.287 expected, 95 957.966 actual.

Not covered: VC-16.6b (partial condenser, E50); the H9/H10 Tier-2 rows (M6 drills; H9.10 checked once in the Tier-2 drill configuration: TI-114 look 0.22–0.30 ≤ 0.6, so the row holds on that criterion, while C6 and TC-101 oscillation do not trigger).

Revalidation at e1d4ae4 (V1/V2 fixes 7312519, spec da8753e), clean worktree; the coder's later uncommitted lib edits were not part of it. Full engine suite at the start: 431 pass, 2 skipped, 1 fail (VC-20.4 Tier 2 full hydraulics, V4 below, not V3). After the test changes: 433 pass, 2 skipped, 0 fail (one new test). V1 and V2 confirmed fixed (both VC-20.4 Tier-2 rows bit-identical after 600 / 1800 s). Test changes:

- V3 (test): the full-hydraulics VC-20.4 row now compares PT-101, PT-201 and TI-100 readings in plant view, then switches both sims to model view for the inert fraction (> 0) and P_top.
- VC-16.6 ±10 kPa SP steps after E48: `setSp` re-ranges PT-101 (span 222.65 kPa for +10, 202.65 for −10, asserted). Within ±1 kPa at 300 / 440 s, overshoot 0 / 1.7 %. Pass without Kc compensation.
- VC-16.6c from the design OP (50.2 %) to 100 %: P 0.9053 / 0.9053 / 0.9050 bar(a) at dt 0.5 / 2 / 30 s, V₁ peak 1.071 / 1.071 / 1.061 × steady.
- VC-8.1 (T2): steady ±0.2 kPa and transient ≤ 5 kPa, citing the VC-8 row.
- H2 F11 (s = 1): valve 48 → 100 % at 1005 s (≤ 30 min), P_top 139.0 kPa and y_I 0.0721 at 1 h, subcooling ≥ 3 K at 2155 s and 4.33 K at 1 h; vent restores. P is +0.1 to +2.1 kPa above SP while the valve rises (PI ramp lag), judged on the VC-8.1 5-kPa bound; wording item in OPEN_ITEMS.md. `f11` expectations re-pinned to the §11 transient numbers.
- H4 F15 (s 0.7 / 0.85 / 1): `FC-103.OPSAT` at 175 / 155 / 140 s, `model.dutyLimited` never raised. F13 raises `model.dutyLimited` at 10 210 s (ramp 6 h), F14 (s 0.75) at 105 s. A healthy run with noise on and FC-103 at 100 % OP (SP 1.3 Q_max, or MAN 100 %) never raises it (new test). VC-27.3 at 2 bar on the 3.5 bar(g) header now asserts OPSAT and no `model.dutyLimited`.
- VC-27.3 note: 0.5 bar(a) holds at CW 5 and 10 °C and not at 11.5 or 15 °C (engine: CW 95.3 % at 10.5 °C, saturated with P +0.5 kPa at 11 °C), so the limit is ≈ 10.7 °C as stated.
- H9.12 and the re-pinned rows cite VALIDATION.md, not OPEN_ITEMS. M6 signal-look calibration (H9.0/H10.0 Tier 2) left for M6: the engine has no σ_proc yet. Also not covered: the H2/H4 rows restated with drill parameters in 6d43717 (F09 s 0.8 ramp and `cw_flow` s 0.65, F11 at s 0.7, F13 s 0.85 ramp 5400 s), which postdate e1d4ae4; they belong to the M6 drill pass.

Engine item:

- **V4. Coder: Tier 2, full hydraulics, TC-101 on: `runToSteadyState()` never reaches its 1e-11 polish.** Repro: `Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.full), options: SimOptions(seed: 9))`, `setLever('tc101Enable', 1)`, `runToSteadyState()`. The monitor declares steady at 15 540 s, but the residual then dithers at 5e-11 to 1.1e-10 for good, and the run returns `reached: false` after the full 345 600 s (4 days of sim time). Every 60 s, P_top moves by ±5e-6 Pa and the OPs of PC-101, TC-101 and FC-103 by ±1e-10 (relative), with x and holdups following. This looks like the overhead-pressure secant (`_t2PressureSolve` stops at |Δp| < 0.1 Pa) leaving ≈ 5e-11 relative jitter in P, which PC-101's integral and the TC-101 cascade keep alive. At 7312519 the same run got down to 9.67e-12, just under the tolerance. The only lib change since then is E47 on `pc101.op`, which moves the start-up path, not the steady state. With TC-101 off it reaches 9.6e-12 at 14 820 s. Fix the floor: a tighter or residual-based stop for the P solve, or a polish tolerance that the Tier-2 solve can reach. Expected: `reached: true` at about the same time as with TC-101 off. The VC-20.4 full-hydraulics test now polishes to 1e-9 so that it tests the restore. App impact: "Run to steady state" in the Tier-2 drill configuration runs for the whole 96-h budget.

Close-out at 1155f40 (E50, display T*, V4 fix), clean worktree; later commits not included. Full engine suite at the start: 438 pass, 2 skipped (H9/H10 Tier-2 rows and VC-26.5 drill draws, both M6), 0 fail. New `test/validation/m4_e50_v4_test.dart` (15 tests): 14 pass, 1 fail (E50-a). VC-20.4 Tier-2 full hydraulics is back on the default 1e-11 polish. Suite after: 452 pass, 2 skipped, 1 fail (E50-a).

- E50 (B-T Tier 2, CW 30 %): P 101 325 Pa, D_V 12.62, D 37.18, B 50.20 kmol/h, PV-102 at 25.24 %, Q_C 1174.8 kW. D_V follows (7.5) to 1e-9 at P_design, at 1.113 bar and open loop at 97 kPa. P_down is 0.713 bar(a), D_V,max 50 kmol/h, PC-101 Kc 2 / Ti 30 s, not scheduled. The drum vapour is the bubble-point vapour of x_0 (1e-9), at the bubble T (1e-6 K). Steady closure: total mass 5e-11, benzene 8e-13, energy with D_V H_V 1.7e-11 (independent enthalpies). VC-5.2 including D_V, 3 h from cold with CW and SP steps: < 1e-10. Directions: CW 30 → 40 % gives D_V 12.6 → 4.6 and D 37.2 → 45.2; duty +5 % gives D_V 14.8; SP +10 kPa gives D_V 3.9 and T_cond +3.2 K. VC-16.6b: settle ≤ 600 s, overshoot ≤ 30 %, decay ratio ≤ 0.3. Results at dt 0.5, 2 and 30 s are identical. D_V reaches 0 at CW ≈ 48.5 % (see OPEN_ITEMS for the 70 % default).
- V4 confirmed fixed. Cold start with TC-101 on reaches the steady state at 25 800 s (declared at 15 540 s; with TC-101 off, 25 680 s). For the next hour the residual stays ≤ 9.4e-12, ΔP ≈ 1e-9 Pa and every OP moves ≤ 7e-9 %. Warm start + TC-101 + feed z 0.55 reaches it at 24 180 s, with FC-103 SP +45 kW.
- Display T*: each Tier-1 stage T is the Raoult bubble point at p_j (1e-6 K). Taking snapshots leaves the engine state bit-identical.
- VC-5.4 in full hydraulics: energyResidual 6.8e-6 at design and 1.9e-5 at +20 % load (limit 1e-6). The gap is exactly e_1 (h_1 − h_0) (1.8e-11 without it): a spec gap in (7.4), see OPEN_ITEMS. The test accepts either form.

Engine item:

- **E50-a. Coder: `SimSnapshot.energy` leaves out the vapour product.** Repro: B-T Tier 2 with `condenser.type: partial` and `cwOP` 30, run to steady state. `energy.residual` is 135 408 W (10.4 % of Q_R) = D_V h_V,0, while `kpis.energyResidual` is 1.8e-11. Add a D_V h_V,0 term to `EnergySnapshot` and subtract it in `residual` (`simulator.dart` around line 2404), and show it on the Energy card. Test: "EnergySnapshot (Energy card) residual equals …".

M4 acceptance (SCOPE.md "### M4") at 1155f40: every engine acceptance row has a passing test: VC-10, VC-11, VC-8 Tier 2 (8.1, 8.7, 8.8, 8.9 switching, 8.14), VC-5.2, VC-5.4, VC-16.6 / 16.6b / 16.6c, VC-18.3, VC-27.1–27.4, and dt 0.5 / 2 / 30. Gaps:

1. Energy closure ≤ 1e-6 fails in full hydraulics (spec (7.4)).
2. E50-a.
3. `kpis.balanceResidual` is 0.25 with a partial condenser, because its formula has no D_V y_V (spec).
4. With a partial condenser, C1/C2/C3a and C4 PV-101 are not adapted (coder's known deviation).
5. SCOPE says "G11 upgraded to Tier 2", but ENGINE_API 11.8 ships it in Tier 1.
6. The app rows were not run here (Dart only); the coder reports `m4_ui_test` passing.

## M4 validation: fixes (coder)

- V1 fixed: `ColumnState` now saves and restores the Tier-2 thermo arrays (K~, h, H, tau, stage pressures); a restore rebuilds only the derived values (`Stepper.t2RestoreDerived`: efficiencies, rho/sigma for the hydraulics, inert fraction), so `saveState()` is identical right after a restore and after any number of steps, in full hydraulics too.
- V2 fixed: the control system's design pressure is `condenser.pTopDesign` (it was the initial `pTop` lever, so a restored sim re-ranged PT-101 to 2 x the saved SP). `ControlSystem.setSp('PC-101', ...)` now re-ranges PT-101 like the `pTop` lever, and `loadJson` re-ranges before loading the instruments' noise state.
- V3 (test, open): `VC-20.4 Tier 2 full hydraulics` asserts `condenser.inertFraction > 0` with `view = 1` (plant). In plant view the engine hides the inert fraction (NaN; it is not measurable, PHYSICS.md 10.9), so that line needs `view 0` (or a different observable such as a PT-101 reading). Everything before it in that test (exact `saveState()` equality after 1800 s) passes.
- E47 detail (ratified): the PC-101 gain schedule uses PC-101's own OP from its previous execution (it used the valve position). With a partial condenser PC-101 drives PV-102 unscheduled; the partial condenser is not implemented yet (E50). E48 as a function of the SP alone: `setSp('PC-101')`, the `pTop` lever and scenario events all re-range PT-101 through `ControlSystem.setSp`/`setPtSpan`, and a restore re-derives the span from the saved SP before loading the noise state. `model.dutyLimited` already compares Q_max,0 g(p) (no supply disturbance, post-F15 steam temperature) with the fouled/flooded Q_max, so F15 alone leaves it clear.

## M4 app (coder, status 2026-10-13)

Done: Control Room theme (palette, ISA-101 grey liquid and pipes, flat fills, glow on McCabe-Thiele and trend lines, SP dashed ink, alarm glyphs diamond / triangle / square with 1 Hz blink for UNACK, theme switch in the menu, composition-shading option); T1/T2 badge; Tier-2 levers (feed T and q read-out, P_top, subcooling, duty, utilities, vent, TC-101); Energy tab (condenser, reboiler, column balance, readings-only in plant view); PC-101 / TC-101 faceplates with CAS and IMAN; Balance tab with C3a, C3b, C7 and the C6 temperature card (Set reference); Profiles T, V, L with the previous tier's V and L as ticks; McCabe-Thiele band, local equilibrium points and curved locus; F08 to F15 injection card and info-blue flags on equipment; G7 and G8 in the scenario list; Tier-2 equation overlay. `app/test/m4_ui_test.dart` passes at 360x800 and 1440x900.
Not done / deviations: Rajdhani and JetBrains Mono are not bundled (fallbacks); no level bar graphs, tag bubbles or Settings screen (the theme is in the menu); Tier 1 shows no display-only T* ("ideal") temperatures; G11 stays Tier 1 as ENGINE_API 11.8 ships it; the partial condenser (E50) and the screenshots and emulator pass for m4 are open.

## M4 handoff (coder, 2026-10-13)

M4 is complete on the coder side.

- E50 (partial condenser) is implemented, replacing the "not implemented" note above. `condenser.type: partial` is honoured in Tiers 2/3 (Tier 1 and `setTier(t1)` refuse it; `validate()` rejects a Tier-1 partial config). The drum is an equilibrium stage (drum row of 7.4, y_0 = K~ x_0 in the vapour inventory), N_cond uses H_V(y_0), the vapour product is D_V = meanValveFlow * sqrt((P - P_down)/(P_design - P_down)) (7.5), with P_down = P_design - 30 kPa. PC-101 drives PV-102 (full scale `dvMax`), unscheduled (kcScale 1). Implementation: `ControlSystem.pv101` is "PC-101's valve" (PV-102 when partial) and `cwValve` is the CW valve (the same object when total; with a partial condenser it is held at `cwManualOp`, lever `cwOP`, default 70 %). New lever `condenserType` (0/1, requires pause, rebuilds the column). Snapshot: `condenser.partial`, `condenser.vaporProduct`, `StreamId.vaporProduct`. `energyResidual` includes D_V h_V,0.
- PC-101 tuning with a partial condenser is Kc 2.0 / Ti 30 s, not v1.0's 1.0 / 30 (VC-16.6b is [impl-tunable]): with 1.0 the +10 kPa step took 710 s to settle within 1 kPa; with 2.0 both ±10 kPa steps settle in 505 / 515 s with 15 % / 12.5 % overshoot (B-T, CW 30 %).
- At the specified default CW OP of 70 % the B-T condenser over-condenses (more than V1 at P_design): PV-102 closes, D_V = 0 and P floats at 94.5 kPa below the SP. The partial-condenser test uses CW 30 % (D_V 12.6 kmol/h, D 37.2). Suggest a lower preset default or a note in the lever.
- Not done for the partial condenser: no vapour-product flow transmitter, so C1/C2/C3a (mass and energy cross-checks built on FT-104/FT-105) flag D_V as unaccounted; C4 for PV-101 is skipped. Tests: `packages/lowsys_engine/test/partial_condenser_test.dart`.
- V4 fixed: the overhead pressure secant now stops at |dp| < 1e-4 Pa (was 0.1), and the Tier-2 bubble-point solve at |ln S| < 1e-13 (was 1e-10); the latter was the real source of the ~5e-11 jitter. Tier 2 + full hydraulics + TC-101 `runToSteadyState()` reaches true at 25 800 s total (probe). Full engine suite 438 pass, 2 skipped.
- Tier 1 shows the display-only T* (`StageArrays.t`, `idealT: true`): the Tier-2 Raoult bubble point of every stage liquid at its stage pressure, never used by the engine. The profile chart and tray inspector label it "T*, ideal".
- Control Room theme: vertical level bar graphs (drum LT-101, sump LT-102) with accent SP marker and HI/LO ticks at 85/15 % (HIHI/LOLO 95/5), grey-blue fill that turns warn/alarm only past a limit; ISA tag bubbles (FIC 101, LIC 102, FIC 102, LIC 101, FIC 103, PIC 101 in Tier 2) outlined by loop mode (AUTO grey, MAN warn, CAS accent, shed alarm). Bubbles are hidden on narrow (phone portrait) panels. Still no Settings screen (theme is in the menu).
- Fonts: Rajdhani (Medium, SemiBold) and JetBrains Mono (variable font, default weight) bundled from github.com/google/fonts (OFL), licences in `app/assets/fonts/LICENSES`. This resolves the Control Room part of A1.
- Loops panel overflow fixed (title row, value block, bypass row; also the instrument-fault "Reads" row); `m3_ui_test` and `m4_ui_test` now scroll the fault panel's own list (the sixth tab made the tab strip the last `Scrollable`). All app tests pass.
- Screenshots: `docs/screenshots/m4/` (made by `LOWSYS_SHOTS=1 flutter test test/m4_ui_test.dart`; running it with the other UI tests also rewrites m1 to m3, which was reverted). Android: AVD `lowsys_pixel` booted, the debug APK installed and runs (`android_emulator.png`, Tier 1 Blueprint, phone portrait).
- G11 still ships in Tier 1 as ENGINE_API 11.8 says.

## M5 checkpoint (engine, 2026-10-13)

Engine side of M5 is in; the app side (Paper theme, T-x-y tab, T1/T2/T3 badge) follows. Full engine suite: 445 pass, 2 skipped, 1 file fails to compile (below).

- Thermo: `Tier2Raoult` gained overridable `kAt` / `dLnKAt` / `xDependent`; `Tier3Nrtl` (general n-component formula, parameters for the three binaries of 3.4.1, gamma held constant in dlnK/dT) and `Tier3DePriester` extend it, so enthalpies, properties and the whole stepper are shared. Dew points and flashes iterate on x when K depends on it. `ThermoFactory.buildTier3`, `ColumnConfig.tier3Model`, `tier1CannotRepresent`, `availableTiers`. The bubble-point Newton now stops at |dT| < 1e-9 K (was 1e-6) so that |sum Kx - 1| < 1e-9 holds for NRTL (VC-10.8); Tier-2 results are unchanged to 1e-12. DePriester follows the 2026-10-13 OPEN_ITEMS item: validity 365-852 degR, evaluated unclamped.
- Presets `ew`, `ac`, `c4` (table of 2.3; feed given as q = 1, which the engine treats as a saturated liquid at the feed-tray pressure, the same thing as beta = 0); `mw` gains Tier 3 NRTL. Steady states match VC-28.1 (ew), 28.2 (ac), 28.3 (c4 T2 and T3), 28.7 (mw T3) to the table tolerances; T1 to T3 on `mw` and the ew T3 -> T1 -> T3 round trip (D 9.72, x_D 0.88716, duty 1202.7 kW) match 8.13 and 28.6.
- Tier switching T1/T2/T3 (`Simulator.setTier`, `availableTiers` enforced). T2 <-> T3 keeps the duty and rescales the vapour inventory so that P_top does not jump. **c4 T2 -> T3 pressure:** P rises by up to 5.7 kPa within about 70 s and settles in about 15 min (VC-28.3 asks for +-0.5 kPa throughout). The cause is physical in this model: at the same P the NRTL/DePriester temperatures are lower (T_D -1.4 K), so Q_C = UA (T_sat - T_cw) falls by 6 % until PC-101 opens the CW valve (50 -> 59 %). The +-0.5 kPa figure presumably came from a held-pressure prototype; to be adjudicated.
- T-x-y and R_min: `TxyData`, `Azeotrope`, `TxyBuilder` (`snapshot/txy.dart`; `TxyData.build` 1.4 ms warm, 3 ms cold; its azeotrope scan uses a 2e-3 grid, `findAzeotropes` keeps 1e-4); `McCabeThieleBuilder.build(..., xDTarget:, xBTarget:)`; `RminConstruction` is now the ENGINE_API 7.2 form (`sMin`, `rMin` null when blocked, `pinch`, `tangentPinch`, `line`, `blocked: RminBlock`). VC-28.4 values reproduced: blocked at x_D 0.90 (0.8956), tangent pinch 0.7527 / R_min 1.873 at 0.85, feed pinch R_min 1.021 at 0.80, `ac` bottoms banner. **The validator's `vc18_mccabe_thiele_data_test.dart` line 186 (`greaterThan(mt.rmin!.rMin)`) no longer compiles because `rMin` is `double?`: it needs `rMin!`.** `SimRunner.idealThermo` (the Raoult model) was added for the Tier-1 T-x-y.
- Explain: `eq.nrtl` and `eq.depriester` replace `eq.equilibrium.T2` for Tier-3 systems. `thermoOutOfRange` is now set on the snapshot (Antoine component outside 0.1 to 5 bar, DePriester stage outside its range).
- Scenarios `G9_azeotrope_wall` and `G10_other_azeotrope` (JSON as ENGINE_API 11.8) and the G8 debrief line. Not run through hint players yet. **G9 o3 note:** Tier 1 `ew` (40 trays, R about 11) has a 5 h slow mode (residual tau 18 350 s): the steady monitor declares at about 83 h of simulated time, longer than G9's 48 h limit. The hold-300 s predicate needs `steady`, so a learner at 300x may not reach it; the time limit or the steady tolerance for this case needs a decision.
- Display T* and the partial condenser from M4 are unchanged.

## M5 checkpoint 2 (app, 2026-10-13)

- E50-a fixed: `EnergySnapshot.vaporProduct` (D_V H_V,0) is subtracted in `residual` and shown on the Energy card; `m4_e50_v4_test.dart` passes (15/15).
- App: T1/T2/T3 badge cycling the tiers of `config.availableTiers` (key `T` too), T-x-y tab with the x-y sub-view (binaries only; diagram tab ids 0 McCabe-Thiele, 2 T-x-y, 1 Profiles, shown in that order; keys 1 to 3 follow the visible order), "Tier 1 cannot represent this system" banner on `ac`, R_min "beyond the azeotrope" banner and tangent-pinch ring, Paper theme (palette, ink style, captions, margin note, export button). All app tests pass (`m5_ui_test` at 360x800 and 1440x900); screenshots in `docs/screenshots/m5/`.
- Paper deviations: "Source Serif 4" and "Source Sans 3" are not bundled (only Rajdhani and JetBrains Mono were cleared for download); platform serif / sans fallbacks apply (the screenshot tests load Georgia italic and Segoe UI as stand-ins). "Export figure" does not use `path_provider` (a new package download): Windows writes to Downloads (Documents as fallback), Android to `/storage/emulated/0/Android/data/dev.lowsys.lowsys_app/files/figures`, other platforms to `~/Downloads`. The margin note has no leader line to the stage marker. No Paper golden images yet (U4), and U2 contrast for Paper is not asserted by a test yet.
- Not done in M5: hint-player runs of G9/G10 (VC-28.8), `vc28_*` style validation tests, T-x-y tab keyboard/touch targets audit, G9 steady-time issue (see M5 checkpoint).

## M5 handoff (coder, 2026-10-13)

M5 is complete on the coder side. Engine suite and all app tests pass; the only red file is the validator's `test/validation/vc18_mccabe_thiele_data_test.dart` (line 186 needs `rMin!`, see "M5 checkpoint").

- **Hint players (VC-28.8)**, `packages/lowsys_engine/test/m5_hint_players_test.dart`. G10: o1 at 21 780 s, D 48.0, x_D 0.8567, x_B 0.3630, x_B never below 0.3335, o3 from `TxyData.findAzeotropes` = 0.333, no safety events. G9: all checkpoints hold (after hint 1 x_D 0.8902, R 17.6; Tier 1 x_D >= 0.99 after 2160 s; after hint 3 P 50 000 +-500 Pa, D 5.97, x_D 0.9005, CW 37.3 %), no relief, level or `thermoOutOfRange` events. **Times: o1 94 620 s, o3 1500 s after the switch, o5 105 360 s after hint 3, total 203 640 s, over the 172 800-s limit** (o1 and o5 wait on the steady monitor, whose slow-mode estimate is 5-8 h on `ew`). Needs a spec decision (raise the limit to about 259 200 s, or loosen `steady` for o1/o5). The test only bounds the total at 2x the limit.
- **Low-CW path** (feed 60 kmol/h with the CW valve at 9.3 %): no oscillation (amplitude of the last 20 min 0 against 6.8 kPa in the first 20), but the peak is 8.0 kPa at 90 s after the feed/reflux/duty step, not +-2 kPa. The peak is the step itself (duty and reflux change together); the E47 schedule is in force. Reported, not retuned.
- **G9 bug found by the player:** T2 -> T1 turned a saturated feed (q = 1 preset) into q = 1 +- 1e-12, so a later T1 -> T3 lost `feedSat` and the feed stayed at its 1-atm temperature. At 0.5 bar that feed flashed and the condenser collapsed (P 73 kPa at CW 100 %, x_D 0.30). Fixed: `inp.feedSat` forces q = 1.0 on the way down.
- **Spec rulings applied (OPEN_ITEMS.md "For coder", 4ee46dd):** (7.4) entrainment term `- e_1 (h_1 - h_0)` (also in the pressure solve); `condenser.cwOpPartial` (30 %, preset field, used by preset load and the `condenserType` switch; `ControlData.cwManualOp` default 30); `balanceResidual` includes D_V y_V (overhead-inventory composition); with a partial condenser C1, C2, C3b and the sump C5 are `n/a` ("vapour product not metered"; I made the sump C5 n/a as well because its vapour term is V_B = condensate + D_V; drum C5 and C3a stay), C4 PV-101 runs on the CW valve at `cwOP`; T1 -> T2 starts PC-101 and the hidden CW valve at 50 %; T2 <-> T3 with a total condenser sets the CW valve and PC-101's OP for a continuous Q_C (7.3 inverted, `ControlSystem.setCwFlowBumpless`; `c4` 50 -> 59.0 %, peak |dP| 142 Pa over 30 min, VC-28.3 +-0.5 kPa holds); G9 o3 without `steady` and the new hint 2 text. The "T^(n-1) := T" step is moot here: the stepper stores no previous temperature (the heat-storage term is tau dP/dt). E47 (a) was already on PC-101's own OP (`pc101.op`), (b) kcScale 1 with a partial condenser; E48 re-ranging already runs on every SP change (`setSp`, lever, restore). `dutyLimited` already omits (1 + d). PC-101 -> PV-102 Kc 2.0 / Ti 30 s recorded against E50.
- **Fonts:** Source Serif 4 (roman and italic variable) and Source Sans 3 (variable) from github.com/google/fonts (OFL, licences in `app/assets/fonts/LICENSES`); the screenshot tests now load the bundled files.
- **Paper tests:** `app/test/m5_golden_test.dart`: U2 contrast for all three themes (Paper numbers of SCOPE 7.2 reproduced) and U4 goldens (`app/test/goldens/<theme>_column_mccabe.png`, the whole 1440x900 screen at the B-T steady state, so column and McCabe-Thiele painters together; regenerate with `--update-goldens`).
- Screenshots refreshed: `docs/screenshots/m5/`.
- Still open: Paper margin-note leader line; T-x-y touch-target audit; `vc28_*` validation tests belong to the validator.

## M5 validation

Validator pass on engine 9348b7c in a clean worktree. It was re-run at fb33c07 (the coder's M5 close-out, which landed during the pass), and the statuses below are at fb33c07.

- **Start.** With the `vc18_mccabe_thiele_data_test.dart` fix (`rMin!`), the suite at 9348b7c was 473 pass, 2 skipped, 0 fail.
- **New tests.** Four validation files: `m5_tier3_thermo_validation_test.dart`, `m5_columns_validation_test.dart`, `m5_mccabe_txy_validation_test.dart`, `m5_g9_g10_validation_test.dart`. They rest on an independent reference, `reference/tier3_reference.dart`: binary NRTL, McWilliams DePriester, Lee–Kesler and a MESH Newton with a numerical Jacobian (P held). The M4 close-out re-checks are in `m4_e50_v4_test.dart` (spec 4ee46dd).
- **End state at fb33c07: 547 pass, 4 skipped, 5 fail.**
  - Skips: the two old ones, plus two VC-28.8 clauses that fail for spec reasons (OPEN_ITEMS.md, M5 validation, items 1 and 2).
  - Failures: all engine-side, coder items 1, 5, 6 and 7 below.

**Pass (engine against the docs and against the independent reference):**
- VC-10.4: γ∞ (6 values); engine γ equals the reference to 1e-12 on a T × x grid.
- VC-10.5: all 9 azeotrope rows through `TxyData.findAzeotropes`, including 0.1 / 0.08 atm, the T values, the maximum-boiling flags and the literature bands. `mw` has none.
- VC-10.6: within the experiment bands (± 0.5 K, ± 0.015), and equal to the reference to 1e-6 K.
- VC-10.8: over each preset's P_top range (mw/ew/ac 0.2–5 bar, c4 3–25 bar), from the cold guess Σ x T_sat(P) and from the engine's own cold start. No fallback; |ΣKx − 1| < 1e-9.
  - §3.6.1 Newton iterations per 1000 points: mw ≤ 6, ew ≤ 6, ac ≤ 7 (26.5 % need 7), c4 ≤ 3.
- VC-10.9: all three rows. DePriester α 1.36 / 1.33 against Lee–Kesler 1.379 / 1.354 at the c4 T3 top and bottom.
- VC-9.4 (6 K values) and VC-9.5 (6 bubble and dew points, ± 0.05 K) with the six-component DePriester model. For the 852 °R limit see OPEN_ITEMS.md (DePriester source).
- VC-28.1:
  - Table rows, VC-5.4, and CW 49.90 %, which equals (7.3) applied to the reference Q_C.
  - dt: the dt-2 steady state stays steady at dt 0.5, and dt 30 agrees to 1e-6.
  - R 20 at D 10: 0.89074 with utilities ×1.9. R 40 checked against the reference only: 0.89231.
  - Tier 1: 0.983063.
  - 0.5 atm, R 10: 0.900211 / 61.624 °C / 1246.7 kW, with 15 °C water.
  - x_B [P] against [I]: reconciled (OPEN_ITEMS.md).
- VC-28.2:
  - L₀ 150: T_D / T_B.
  - L₀ 300 with utilities ×1.8: D 38.0, x_D 0.99993, x_B 0.35488; x_B stays above 0.3335 throughout.
- VC-28.3 (± 0.05 K, ± 0.1 kmol/h):
  - Tier 2: T_D, T_B, V₁ and V_B.
  - Tier 3 at D 40, run at the reference duty 1553.95 kW: every row.
  - Tier 3 at 1542.6 kW: T_D, T_B and V_B.
  - T2 → T3 switch at fb33c07: CW 49.96 → 59.05 %, peak |P − SP| 142 Pa.
- VC-28.6 [P]: Tier 1 x_D 0.98335; back in Tier 3, duty 1202.1 ± 1 kW, D 9.67 ± 0.1, x_D 0.88720 ± 5e-4.
- VC-28.7:
  - The D 30 row, run at the reference duty 902.39 kW: D 30.000, x_D 0.994611, x_B 0.002309, 64.585 / 99.569 °C, V_B 79.71.
  - Preset duty: the temperatures and V_B.
  - Tier 1: x_B.
- VC-18.4:
  - Builder R_min 1.1000 on the VC-1 case.
  - `ew` tangent pinch 0.7527 / 1.873, equal to the reference.
  - Feed pinch alone at x_D 0.85: 1.165. At x_D 0.80 the feed pinch governs (1.021); by 0.82 the tangent pinch has taken over.
- VC-28.4:
  - The q-line at q 0.5 (feed T from (3.15)) ends at x 0.385, with |y_line − y*| < 1e-8 and no other crossing.
  - The "blocked" banners use the finder's azeotrope x at P_top.
- VC-28.5:
  - mw, ew, ac: the dew curve comes from the bubble sweep; the engine's dewT agrees to 1e-6 K; the markers equal `findAzeotropes`.
  - Grid refinement; spot values from VC-10.3 and 10.6.
  - `ew` at 0.5 atm: 0.9105 / 61.62 °C.
  - One build takes < 2 ms (median of 21).
  - Tier-1 ideal view: every T* lies on the bubble curve to 1e-6 K.
  - c4: the end points are where K_i = 1.
- VC-21: `eq.nrtl` / `eq.depriester` equal y* on every tray of ew, ac and c4; each line has TeX, and every id is in the §15 catalogue.
- VC-28.8 G10: D 48.0, x_D 0.8567, x_B 0.3630; x_B never below 0.3335; o3 = round(findAzeotropes, 3) = 0.333; no safety events; o1 at 6.05 h of 24 h.
- VC-28.8 G9 (fb33c07):
  - The shipped JSON has the new o3 and hint 2.
  - After hint 1: x_D 0.8902, R 17.6.
  - o3 (x_D ≥ 0.95 held 300 s) 0.41 h after the Tier-1 switch.
  - At 0.5 bar(a): P 50 000 Pa, D 5.970, x_D 0.90050, T_D 61.33 °C, CW 37.3 % of m_cw,max.
  - No safety events.
  - Times: o1 26.28 h, o5 55.81 h, over the 48-h limit (OPEN_ITEMS.md item 1).
  - Low-CW path: no oscillation, CW 9.3 %; the −8.0 kPa dip is OPEN_ITEMS.md item 2.
- M4 close-out re-checks (spec 4ee46dd): all pass at fb33c07.
  - VC-5.4 in full hydraulics ≤ 1e-6 at design and at +20 % load.
  - `cwOpPartial` 30 % from the preset and from the switch.
  - `balanceResidual` ≤ 1e-9.
  - C1/C2/C3b `n/a`, C3a / C5 drum `ok`, C4:PV-101, no C4:PV-102.
  - T1 → T2 PC-101 at 50 %.
  - VC-16.6b.
- VC-4.1 and every other M1–M4 test: unchanged, pass.

**Coder items (repro in the named test):**
1. **Open: per-preset lever ranges and FT/valve spans (PHYSICS.md §2.3 "Lever ranges") are not implemented.** Every preset keeps the B-T maxima: L₀ 300, V_B 300, F 250 kmol/h, Q_R 3 MW. The spec range is 0–2 × the preset default.
   - Effect: `c4` in Tier 1 starts at the table V_B of 320 but delivers 300. The result is D 20.000, x_D 0.99314, x_B 0.25172, against the VC-28.3 Tier-1 row of D 40, 0.92631 / 0.04913.
   - Repro: `Simulator(Presets.byId('c4').copyWith(tier: ThermoTier.t1))`, then `runToSteadyState()`.
   - Tests: `m5_columns_validation_test`, "Tier 1 (α 1.35) …" and "lever ranges …".
2. **Fixed at fb33c07: the feed after a T2/T3 → T1 → T3 round trip.** At 9348b7c the feed stayed at its 1-atm temperature and G9 hint 3 failed (drum 108 %, D pinned at 20 kmol/h, P 82 kPa, x_D 0.300). Confirmed by the G9 player.
3. **Fixed at fb33c07: the c4 T2 → T3 Q_C-continuous CW initialisation.** At 9348b7c the CW stayed at 49.96 % and the peak was 5729 Pa.
4. **Fixed at fb33c07: the G9 JSON** (o3 without `steady`, hint 2 text).
5. **Open: the q-line with q = 1 ± ε.** `ew`, z 0.95, saturated liquid: at t = 1 s the live q is 1.0000037. `_qPinchT2` then walks in x (slope 2.7e5) and ends at the frame corner (1, 1), not at ≈ (0.95, y*(0.95) = 0.944). At t = 0, where q is exactly 1, it is correct.
   - Fix: a tolerance on |q − 1| (e.g. 1e-6), and for |slope| > 1 a frame end on y = 0/1.
   - Test: `m5_mccabe_txy_validation_test`, "ew, z 0.95 …". For the walk direction see OPEN_ITEMS.md item 3.
6. **Open: dt 30 s robustness.**
   - Repro: `ac` at E 1 with the condenser ×2 (UA 167.4 kW/K, CW max 83.08 kg/s) and dt = dtFastForward = 30 s. From its steady state, step L₀ 150 → 300 kmol/h and the duty ×1.8.
   - At dt 30, `runToSteadyState` returns "reached" at P 141 kPa, D 0.14 kmol/h, drum 2.6 %, energy residual 0.72, with 418 negative clamps after the step (and 615 more during the dt-30 cold start).
   - At dt 2 and 10 s the same step ends at D 16.32 with P at its SP and an energy residual of 5e-12.
   - Cause: the n_V,i ≥ 0 clamp hides an overshoot that §12.7 should catch by halving the step, and the steady monitor accepts a state whose energy balance does not close.
   - A related, physically infeasible case (duty ×1.8 at L₀ 150, boil-up beyond F + L₀) never settles at any dt: 660–6178 clamps, and the drum at 2085 % at dt 30.
   - Test: `m5_columns_validation_test`, "dt 30 s after a large step …".
7. **Open: explain (minor).** The §15 tray row lists `eq.bubblePoint` (the 3.6.1 result), but no Tier-2/3 tray returns it. Tier 2 also uses `eq.equilibrium.T2` where §15 says `eq.raoult` (the M4 VC-21 id check).
8. **Fixed at fb33c07: the M4 close-out items of 4ee46dd** ((7.4) entrainment, `cwOpPartial`, D_V in `balanceResidual`, partial-condenser cross-checks). The coder also made C5 sump `n/a` with a partial condenser; OPEN_ITEMS.md item 7 asks the lead to ratify that.
9. **Open, minor: `coldGuess` uses Σ x T_b, not Σ x T_sat(P) (§3.6.1).** It is harmless: VC-10.8 converges from either guess over the full ranges with no fallback. Record it, or switch.

## M6 checkpoint (engine, 2026-10-13)

The M6 engine is in; the app (Equipment tab, Drill HUD, Diagnose dialog, plantCalc labels) follows. Engine suite green except the validator's `vc18_mccabe_thiele_data_test.dart` compile error (`rMin!`).

- **Loop:** `lib/src/model/thermosyphon.dart` (`ThermosyphonLoop`, `ThermosyphonProps`), ported from `tools/prototypes/m6/ts.dart` to PHYSICS.md 8.3 as written (exact x_e solve, dry-out cap, W >= 0, floor only while I_s > 1, R_f,R in K/W). `ThermosyphonGeometry` is in `ReboilerConfig.thermosyphon` (every preset has the B-T defaults; extra fields `muL`, `rhoLDesign`, `dTsatDpDesign` for the loop viscosity and the C4 check). Test: `test/m6_thermosyphon_loop_test.dart` reproduces all 13 VC-14.1 rows within the tolerances, the spot values, delta independence at 0.025 s, no jitter and the 400-set robustness sweep.
- **Coupling (8.3.4):** the loop runs inside the fast layer between FV-103's request and FT-103 (`ControlSystem.runFastLayer`); FT-103 and `fv103.flow` carry Q_k, the column gets the mean of Q_k (1 + u_k). The stepper freezes the sump properties at the start of the step (`_tsProps`: rho_L from the sump holdup volume, lambda and c_p from the Tier-2/3 enthalpies, dT_sat/dP with the molar latent heat). Initialisation per 13.1 step 7 (`initThermosyphon`, 600 s) in `_enterTier2Control` (build, Tier 1 -> 2/3) and after a kettle -> thermosyphon rebuild. Loop states are in the control JSON, so they ride on save/restore and the warm-start caches (VC-14.2.6 bit-identical, tested).
- **Levers:** `reboilerType` (pause) and `tsInletValve` (5-100 %); `view` 2 = `SimView.plantCalc` (`SimView.isPlant` is the new test for "either plant view"; app uses updated). `sumpLevelSp` existed.
- **Faults:** F17 (K_in += 300 s), F18 (K_out += 40 s) via `EffectiveParams.kInAdd/kOutAdd`; F13/F14 act through `rfK` and `fFlooded` in the loop. Injecting F17/F18 into a kettle column throws `ConfigException`; `ScenarioDef.validate()` also rejects F17/F18 drills or events without `levers.set.reboilerType` 1.
- **Snapshot and alarms:** `ReboilerSnapshot` carries the ENGINE_API 7.1 fields (circulation, exitQuality, riserQuality, instabilityIndex, oscAmplitude, oscPeriod, inletLineDp, outletLineDp, drivingHead, sensibleFraction, inletValve, steamSideDuty, type). Plant view NaNs the loop fields; plantCalc keeps all but `drivingHead` and `sensibleFraction` and also keeps per-stage dp/jetFlood/dcFlood/frothFill/stability/weepFrac, `maxFloodPct`, `maxWeepFraction` and the alarms `model.flood/weep/dcLimited/tsUnstable`. In drills `qMax`, `uaEff` (reboiler and condenser) and the inert fraction are NaN (PHYSICS 10.9). Alarm `model.tsUnstable` (on at I_s > 1, off below 0.98, 30 s / 30 s). Metric paths `reboiler.circulation|exitQuality|instabilityIndex|oscAmplitude|oscPeriod|inletValve`. C4 of FV-103 on a thermosyphon uses Q_max,0 = U A (T_st - T_sump - dT_sub/2) from LT-102 and the design constants.
- **Explain:** `eq.ts.subcooling|exitQuality|drivingHead|friction|instabilityIndex` (plus `eq.boilup`) replace `eq.kettleDuty` for a thermosyphon.
- **Typical sigma (10.5):** PT-101, TI-100, FT-201, TI-202 use sqrt(sigma_disp^2 + sigma_proc^2) from 300-s window means (`ControlSystem._updateProcSigma`; constants 0.0015 and 0.022 as specified). New `CondenserConfig.dTbubDp` (3.2e-4 K/Pa, the B-T value; the other presets use it until M7 gives them their own).
- **Content:** drills H1-H5 (ENGINE_API 11.9 copied verbatim into `data/scenarios/drills.dart`), G14 (`g14Json`, written from the 11.8 row), registered as `H1_creeping_dp`, `H2_pressure`, `H3_lost_separation`, `H4_reboiler`, `H5_bottoms_swings`, `G14_thermosyphon`. `ScenarioDef.validate()` now checks the diagnosis vocabulary (categories incl. `restriction`, `condensate`; locations incl. `column`, `steamSupply`, `tsInletLine`, `tsOutletLine`), that every candidate's answer is offered, and the view name. `fault.magnitude` for a CW temperature fault is K (15 s). The M3 runner was read against 11.2-11.4 (draw order, protect and off-spec clocks, wrong-answer penalty, debrief variables, hidden faults) and needed nothing else; drill smoke tests in `test/m6_drills_smoke_test.dart`.
- **Column results (record for the validator, `test/m6_thermosyphon_column_test.dart`):** B-T Tier 2 steady (E = 0.7, ideal hydraulics): W 13.1 kg/s, x_e 0.240, I_s 0.73, FV-103 at 77.6 % (Q_max,0 1677 kW). Drain to 15 %: amplitude 0.12 and a 9-s period within 6 min, I_s 1.27-1.36; throttling to 16 % does not stop it; level back above about 28-30 % clears it (alarm included). dt = 2 s agrees. G14: start I_s 0.913, FC-103 at 100 %, **qr 1157 kW** (spec 1040-1140), surge 0.05 at about 5 min; hint player: o1 at 3060 s, I_s < 1 at 28.2 % level, score 100; throttle-only at 16 %: stays 0.07 (not met).
- **Spec points to rule on:**
  1. **VC-14.2.2 FT-103 steadiness.** The loop's steam-side Q_k itself swings 8 % at 15 % level (loop alone: 1192-1300 kW, the mist-flow limit D(x_e) Q_0 moves with x_e), and 5-s bins of FT-103 show 8.3 % p-p, not <= 2 %. The delivered Q (1 + u) range of 1025-1483 kW matches the VC-14.1 table (1277 +- 229). The 2 % criterion needs either an FT-103 that reads a filtered Q, or a looser limit. The test bounds it at 10 %.
  2. **G14 at 10 % inlet.** The engine delivers 1200 kW (spec 1147), above the 1170 kW of o1, so a throttle-only player at 10 % meets o1 (it is stable and 1200 kW). The cause is the column's sump temperature (E = 0.7: T_B 109.6 C against 110.4 C in the loop prototype), which raises Q_0 and softens the mist-flow limit; the same offset puts the G14 start at 1157 kW. Options: start inlet 6-7 % (stable, lower duty), raise the o1 duty to about 1230 kW, or lower the sump level SP of the start. Not changed.
  3. **Kettle duty design.** FV-103's thermosyphon Q_max,0 is 1677 kW at the engine's steady state (spec 1636 kW at 50 %), the valve sits at 77.6 % (spec about 79 %).
- Not done in M6 yet: app work; `h_drills_symptoms`/`noise` tests and `vc14_*` validation files belong to the validator; `view_masking`/schema tests of mine are `test/m6_*`.

## M5 validation: fixes (coder, 2026-10-13)

- **Item 1, per-preset ranges: fixed.** Flow and duty levers, FV-101/102/103 `fMax`, FT-101/102/103 spans, FC set-point limits and the FT-103 duty span (Tiers 2/3) run 0 to 2 x the preset default for every preset except `bt` (`Simulator._rangeMax`, `ControlDesign.feedMax/refluxMax/boilupMax/dutyMax`). `c4` Tier 1 now starts at V_B 320 and delivers it (the "lever ranges" and Tier-1 c4 tests).
- **Item 5, q-line with q = 1 +- epsilon: fixed.** `|q - 1| < 1e-6` is vertical in `_qPinchT2`, `qLinePinch` and the R_min line (was 1e-9 / 1e-12).
- **Item 6, dt 30 s false "steady": the false result is fixed, the limit cycle is not.** A negative inventory clamp beyond 1e-6 mol now fails the step so that it is halved (PHYSICS.md 12.7; `Stepper.strictClamp`, relaxed on the last retry), so the monitor no longer sees a state that the clamp had flattened. The validator's `ac` case (condenser x 2, L0 150 -> 300, duty x 1.8) now reports `reached` false at dt 30 instead of "reached" at P 141 kPa. It ends in a pressure limit cycle of about +-0.5 kPa (D 16.3, drum 50 %, residual 1e-3 to 1e-2), because doubling the condenser UA doubles PC-101's loop gain and PC-101 at Kc 10 / Ti 120 s executes only every 30 s at dt 30. At dt 2 and 10 s it settles (D 16.32, residual 5e-12). Not retuned (PC-101 is the physics lead's, and "do not retune globally"); the test's `negativeClamps == 0` clause still fails because of this cycle. Needs a decision: sub-step PC-101 at dt 30, or accept dt 30 only for presets at their own condenser.
- **Item 7, explain: `eq.bubblePoint` added** to the Tier 2/3 tray trace (sum K x = 1 -> T_j). `eq.equilibrium.T2` keeps its id (the M4 tests and the overlay use it); the catalogue name `eq.raoult` is a rename for the physics lead to confirm.
- **M5 validation rulings (ce171db) applied:** G9 JSON time limit 432 000 s / par 216 000 with the fast-forward sentences in hints 1 and 3; `m5_hint_players_test` bounds the G9 path (203 640 s) at 216 000 s. q-line walk rewritten (side of the diagonal where the curve lies at x = z, steps in y for |slope| > 1, frame edge, (z, z) when |y*(z) - z| < 1e-9, |q - 1| < 1e-6 vertical); the validator's q-line test passes. T-x-y cache rebuilds only when |P - P_cached| > 100 Pa (one slot each for the top and the bottom curves). Bubble and dew fallback bracket 150-900 K for Lee-Kesler and DePriester models (0.98 Tc cap kept for Raoult/NRTL); with no sign change the Newton iterate is kept and `thermoOutOfRange` is set.

## M6 app (coder, 2026-10-13)

Done: Equipment tab thermosyphon card (W, x_e with the 0.30 mist-flow note, x_r, I_s with a bar to the 1.0 limit and a SURGING flag, oscillation amplitude and period, inlet and outlet line dP, inlet valve, steam-side duty; plantCalc shows the calculated values with a "(calc)" label, plain plant view shows only the inlet valve and a note); scenario list includes drills H1-H5, H9, H10 and G14; drill briefing, drill HUD (attempts left, Diagnose, Give up) and the Diagnose dialog (category, location expanded from `instrument:*` / `valve:*`, optional mode, M6 vocabulary labels); drill score card rows (Category / Location). Test `app/test/m6_ui_test.dart`; screenshots `docs/screenshots/m6/`.
Not done: a thermosyphon loop schematic drawing, the lever panel's pause-gated reboiler switch UI check, drill HUD timer countdown to the limit, field-check buttons for LG gauges in the HUD, the app's own saved-attempt seed list; the sandbox view toggle still offers 0/1 only (plantCalc comes from drills).

## Spec rulings M6 (2026-10-13)

Physics/spec lead on the open items of "M6 checkpoint" (spec points 1–3), "M5 validation: fixes" items 6–7 and STATUS.md. Spec text changed in PHYSICS.md §8.3.4, §10.1, §10.3, §10.5, §12.5; ENGINE_API.md §7.1 (`steamSideDuty`), §11.8 G14; VALIDATION.md §0, VC-14.2.2, VC-14.3.1, VC-14.3.4; docs/milestones/M6.md copies and E.3 rows 7 and 28.

1. **VC-14.2.2 FT-103 steadiness: add a steam-chest buffer, keep ≤ 2 %.** The spec's "FT-103 sees the mean duty" contradicted its own Q_k = min(Q_v, D(x_e) Q_max,0), which swings ≈ 8 % with x_e. New state Q_st,k = Q_st,k−1 + (δ_c/τ_st)(Q_k − Q_st,k−1), τ_st = 10 s, thermosyphon only (attenuates an 8.6-s swing to ≤ 0.14, a 15-s one to ≤ 0.23; FC-103 keeps ≈ 55° phase margin, tuning unchanged).
   - Coder: in `ControlSystem.runFastLayer`, after the thermosyphon sub-step update Q_st and feed FT-103 with it (kettle: FT-103 still reads Q_k). `ReboilerSnapshot.steamSideDuty` = sub-step mean of Q_st. Initialise Q_st = Q_k at the end of `initThermosyphon` and after a kettle → thermosyphon rebuild; add it to the loop's control JSON (save/restore, warm-start caches). Column energy unchanged (mean of Q_k (1 + u_k)). `ThermosyphonLoop` itself unchanged, so VC-14.1 is unaffected. Tighten the M6 test bound from 10 % back to 2 %.
   - Validator: VC-14.2.2 asserts ≤ 2 % on FT-103's 5-s bins and records the unbuffered Q_k peak to peak; VC-14.2.4 and VC-14.2.6 (Q_st in the bit-identical restore) as written.
2. **G14 throttle-only meets o1 at 10 %: change o1, keep the start at 8 %.** Lowering the start inlet only fixes the start duty, not the throttle path, and a 1230-kW o1 sits on the engine's estimated stable-throttle edge (≈ 1230 kW). New o1: `reboiler.oscAmplitude < 0.02 ∧ reboiler.instabilityIndex < 1 ∧ kpi.qr ≥ 1 260 000 W ∧ loop[FC-103].op < 99`, hold 300, latch. Every stable throttled state is mist-limited, so FC-103 sits at 100 %; the level fix holds 1300 kW with FC-103 at ≈ 78 %. The duty term blocks lowering the FC-103 SP instead. Hint 3 reworded without numbers (ENGINE_API §11.8 row). Start text: ≈ 1090 kW loop-only, ≈ 1160 kW column-coupled.
   - Coder: update `g14Json` o1 and hint 3; re-run the hint player (o1 must still be met with FC-103 < 99 % at LC-102 SP 40 %; if FC-103 stays saturated at 40 %, report it here, do not change the hint) and the throttle-only player.
   - Validator: VC-14.3.1 duty band now 1040–1180 kW [engine 1157]; VC-14.3.4 adds the sweep `tsInletValve` 8…16 % at 900 s (none meets o1 in 2 h) and the "FC-103 SP 1150 kW + inlet 10 %" case (not met).
3. **Q_max,0 1677 vs 1636 kW: accept the engine.** Same cause as item 2 (column sump ≈ 0.8 K cooler at E = 0.7: 47.6 kW/K × 0.86 K ≈ 41 kW). 1636 kW / ≈ 79 % stay as the VC-14.1-input values; column-coupled 1677 kW / 77.6 % ratified (PHYSICS §10.3, M6 E.3 row 28).
   - Coder: nothing.
   - Validator: E.3 row 28 checks the identity Q_max,0 = 47.6 kW/K × (T_st − T_b,mean) against the engine's own T_b,mean to 0.5 % and OP 75–81 %, not 1636 kW.
4. **Low-CW dip (VC-28.8, 8.0 kPa at 90 s): passes the ce171db criteria, no change.** Peak 8.0 ≤ 12 kPa, back within ± 2 kPa at 261 s (< 10 min), no sustained oscillation, CW 9.3 % (6–15 %).
   - Coder: nothing (no retune).
   - Validator: un-skip the clause with the ce171db text as written in VALIDATION.md VC-28.8 and record the engine values.
5. **PC-101 limit cycle at dt 30 (`ac`, condenser ×2): restrict dt 30 to steady-state robustness; no sub-stepping, no retune.** Sub-stepping PC-101 is useless while the pressure is solved once per main step (the PID would see a frozen PV), and dt 30 is never used by the app (dt ≤ 2 s). PHYSICS §12.5 now states the dt-30 contract: same steady states, no NaN/fatal, no false "steady"; closed-loop transients of dt-rate loops may limit-cycle and then `runToSteadyState` must return reached = false. The strict-clamp fix (item 6 of the M5 fixes) stays.
   - Coder: nothing beyond the strict clamp already in; confirm `runToSteadyState` returns reached = false for this case at dt 30.
   - Validator: in `m5_columns_validation_test` ("dt 30 s after a large step"), at dt 30 assert only no NaN, no fatal and reached = false or within 0.05 kmol/h (D) / 0.5 kPa (P) of the dt-2 result; record `negativeClamps`. At dt 2 and 10 s assert D 16.32 ± 0.05 and P at SP ± 0.5 kPa, and `negativeClamps` == 0 at dt 2 (VALIDATION.md §0).
6. **`eq.raoult` rename: confirmed; `eq.equilibrium.T2` is retired (no alias).** §15 ids are the API. Tier 2/3 tray traces use the K model's own id: K = P_sat/P (Antoine or Lee–Kesler P_sat) → `eq.raoult`, NRTL → `eq.nrtl`, DePriester → `eq.depriester`; Tier 1 keeps `eq.equilibrium.T1`. `eq.bubblePoint` follows it as added.
   - Coder: rename in the tray trace, the math overlay and the M4 tests that check `eq.equilibrium.T2`.
   - Validator: VC-21's id check uses the §15 ids per K model.

## M6 app 2 (coder, 2026-10-13)

Done: thermosyphon loop schematic at the top of the Equipment tab card (sump, inlet valve, heater tubes, riser shaded by x_e and red while surging; in plain plant view only the inlet valve opening is labelled). Reboiler-type switch (Kettle / Thermosyphon) in the lever panel's UTILITIES group (Tiers 2/3), enabled only while paused (the label says "pause to switch"); the engine only flags `requiresPause`, so the gate is in the UI. Drill HUD shows `elapsed / time limit` (alarm colour in the last 5 minutes) and "Check LG-101 / LG-102" field-check buttons with the walking countdown and the reading. Saved attempts: each finished drill stores its seed and score in the save store (`drill.attempts.<id>`, last 12); the drill briefing lists them as chips and Start replays the chosen seed. Sandbox View toggle now has a third option, "Plant + calculations" (view 2). Tests in `app/test/m6_ui_test.dart` (second test). No new screenshots.
Choices: the LG buttons are shown for every drill (the engine accepts any gauge tag); the HUD does not check which LGs the preset has. App tests: 26 pass; engine untouched.

## M6 validation

Validator pass on engine 23d7368 / 0d2f7db (worktree). Files: `vc14_thermosyphon_loop_validation_test.dart`, `vc14_thermosyphon_column_validation_test.dart`, independent loop reference `reference/thermosyphon_reference.dart` (PHYSICS.md 8.3 re-implemented from the text). M6 files: 40 pass, 3 skipped, 0 fail. Rebased on 2044f1a ("Spec rulings M6") and e9d0fbe; the rulings that need no engine change are applied below.

**M5 follow-ups.**
- `vc18_mccabe_thiele_data_test.dart`: no compile error at 0d2f7db (`RminConstruction.rMin` is `double?`, `rMin!` is valid); 13/13 pass. Nothing changed.
- dt 30 (coder item 6), per ruling 2044f1a item 5 (VALIDATION.md §0): pass.
  - dt 2 and 10 s settle: D 16.317 / 16.317, P at SP, residual 5e-12, 0 clamps at dt 2.
  - dt 30 is finite and returns `reached` false: D 16.263, P +79 Pa, residual 1.5e-3. No false steady.
  - `negativeClamps` at dt 30 is recorded, not asserted: 2576.
- VC-28.8 (ce171db) un-skipped, both pass: G9 o5 at 55.81 h < 216 000 s (limit 432 000, par 216 000); low-CW hour peak −8.03 kPa at 91 s, within ± 2 kPa from 260 s, last-20-min p-p 0.1 Pa, CW 9.3 %, no safety events.

**E.3 reference values (29)**

| # | Engine | Result |
|---|---|---|
| 1, 2, 4–12 | every VC-14.1 row within tolerance (e.g. 75 %: 16.789 / 0.1695 / 0.505 / 9.59 s; 15 %: I_s 1.283, amp 0.141, 8.65 s, 1277.0 ± 229.2 (1269.5) kW; F18: 1.563 / 0.180 / 11.51 s / 1096 kW) | pass |
| — | engine = independent reference on all 14 rows (stable rows 1e-8, oscillating 2e-3; printed digits identical) | pass |
| 3 | I_s 1.031 / 1.012 / 0.996 / 0.980 at 29 / 30 / 31 / 32 %: crossing ≈ 30.8 % | spec text wrong (S2) |
| 13 | ΔT_sub 8.330 / 6.664 K, Q_max,0 1596.7 / 1636.4 kW | pass (spec "6.67" should be 6.66) |
| 14–17 | 3.628e-4 K/Pa; A_t 0.07060 m², 39.96 m²; A_sat rule 0.140 / 0.082 = simulated ± 10 %; W_h 8.21 / 8.70 kg/s | pass |
| 18 | cycle mean u ≤ 0.0031; delivered vs steam side 0.59 % / 0.92 % / 1.10 % (15 %, K_out 20, F18) | u pass; "≤ 0.5 %" fails in the spec's own table (S1) |
| 19 | G14 start I_s 0.913, FC-103 100 %, I_s > 1 at 10 s (spec 17), amplitude 0.05 at 314 s; qr 1157 kW | pass (duty inside the new 1040–1180 kW band, 2044f1a item 2) |
| 20 | not re-run (coder: I_s < 1 at 28.2 % level, spec ≈ 31 %) | — |
| 21, 22 | amplitude < 0.01 at 219 s; 0.141 → 0.085 at 16 % | pass |
| 23 | W −10.7 % at 1 h; I_s > 1 at 1.98 h / 30.2 %; p-p ≥ 10 % at 2.56 h / 24.4 % | pass |
| 24 | F17 s 0.55: W −40 %, x_e 0.240 → 0.424, max I_s 0.732, inlet ΔP × 12.2, no oscillation | pass |
| 25 | F18 s 0.4: I_s > 1 at 6.4 min, 0.05 at 14.1 min, outlet ΔP × 2.77, period 10.9 s, p-p 30 %, 1098 kW at FC-103 100 % | pass |
| 26 | kettle F13: duty < SP from 50.7 min, FV-103 saturates at 53.8 min (s(t) 0.508, spec 0.44); valve flat at 58.7 % until then | time pass (+14 %); "creeps open" fails (S3) |
| 27 | C5 (sump) `fail` with the 3600-s window at 75 min | pass (r/band not recorded) |
| 28 | Q_max,0 1677.3 kW, FV-103 77.6 % | pass: identity to 0.5 %, OP 75–81 % (column-coupled values ratified in 2044f1a item 3); offset = 47.6 kW/K × (110.39 − 109.51 °C), the column's sump T |
| 29 | σ_proc PT-101 152.0 Pa, TI-100 0.0486 K; FT-201 1.636 m³/h (2.27 %); TI-202 0.340 K (0.022 × 15.52 K rise) | pass |

**VC-14.2 (B-T Tier 2, thermosyphon):** 14.2.1 I_s 0.732, amplitude 0; 14.2.2 boilup p-p 30.6 %, period 8.53 s, `model.tsUnstable` raised, growth 10 → 90 % over 212 s, column ΔP and stage-20 ΔP at 8.68 s (full hydraulics); 14.2.3 0.152 → 0.095 at 16 % (min 0.091), < 0.005 at 252 s after 35 %, alarm cleared; 14.2.4 FT-103 vs qr −0.77 %, C3b ok. All pass. Skipped: FT-103 5-s bins ≤ 2 % p-p. It is 7.8 % because FT-103 still reads the unbuffered Q_k; the Q_st buffer (2044f1a item 1) is not in the engine yet.

**Physical sense (pass):** W rises and x_e, I_s fall with level (15 → 90 %); inlet throttling lowers W and I_s and raises x_e; K_out and F18 raise I_s; fouling cuts Q; more duty raises x_e; a stable loop closes Q = W (c_p ΔT_sub + λ x_e) to 1e-6.

**Coder items:** none new. Still to land from 2044f1a, each with its validator follow-up:
- the Q_st buffer, then un-skip the VC-14.2.2 FT-103 check;
- the G14 o1 change, then run the VC-14.3.4 sweep (8–16 %) and the FC-103 SP 1150 kW case;
- the `eq.raoult` rename, then the VC-21 id check.

**Spec lead items:**
- S1. §8.3.4 / E.3 #18: "delivered and FT-103 differ by ≤ 0.5 %" fails in the VC-14.1 table itself, because Q_k and u_k correlate. Suggest ≤ 1.5 % ("inside C3b's 2 %").
- S2. §8.3.4 / E.3 #3: "I_s crosses 1 at ≈ 29.5 %" contradicts the 30 % row (1.01). It is ≈ 30.8 %.
- S3. §H H4 row and the H4 `reb_foul` debrief say the steam valve creeps open for ≈ 45 min. Under §10.3 (Q_v from the clean Q_max,0, Q = min(Q_v, Q_max)), the valve is flat until Q_max < Q_v, then saturates within seconds. Reword the evidence and debrief, or change the valve model. The M4 test reads "rises over ≥ 30 min" as "saturates ≥ 30 min after onset".
- 2044f1a ruled on the FT-103, G14 and dt-30 items. What was applied, and what still waits for the coder, is listed above.

## Spec rulings M6 validation (2026-10-13)

Physics/spec lead on S1–S3 of "M6 validation" (f5fcd32) and the M8 readiness items in OPEN_ITEMS.md. Spec text changed in PHYSICS.md §8.2, §8.3.4 and §16; VALIDATION.md VC-14.1 spot values and §H H4; ENGINE_API.md §11.9 H4 `reb_foul` debrief; SCOPE.md F13; docs/milestones/M6.md copies and E.3 rows 3, 13, 18, 26. M4.md copies left as history.

1. **S1, delivered vs FT-103: the bound becomes ≤ 1.5 %.** Q_k and u_k move together with x_e, so the mean of Q_k (1 + u_k) differs from the mean of Q_k by more than the cycle mean of u. The engine's 0.59 / 0.92 / 1.10 % is the model, not a defect. ≤ 1.5 % keeps a margin inside C3b's 2 %. The u ≤ 0.005 check stays.
   - Coder: nothing.
   - Validator: E.3 row 18 asserts u ≤ 0.005 and delivered vs steam side ≤ 1.5 % in every oscillating row (VALIDATION.md VC-14.1 spot values).
2. **S2, I_s = 1 level: ≈ 30.8 %.** Interpolating 1.012 (30 %) and 0.996 (31 %). The "≥ 32 %" advice in §8.3.4 stands. ΔT_sub at 50 % is printed as 6.66 K (engine 6.664).
   - Coder: nothing (check any hint or Equipment-tab text that quotes 29.5 %; none found in the spec).
   - Validator: E.3 row 3 crossing 30.8 % ± 0.5 points; row 13 6.66 K.
3. **S3, H4 "valve creeps open": fix the text, keep the model.** Physically the creep is real: fouling raises the shell temperature needed for the duty, the steam-chest pressure climbs toward the header, and the valve opens over the fouling time. LowSYS has no chest pressure (§10.3: Q_v from the clean Q_max,0 at the header, Q = min(Q_v, Q_max)), so FV-103 holds its clean position and saturates within minutes once Q_max < Q_v. A chest model would move every validated FV-103 OP (kettle 60 %, thermosyphon 77.6 %, G14 o1's FC-103 < 99) and needs an implicit solve, for a symptom whose duty, saturation time and `model.dutyLimited` are unchanged. PHYSICS.md §8.2 and §16 now state the missing creep; SCOPE.md F13, the H4 debrief and §H describe the modelled symptom. The drill stays solvable: onset speed (hint 2), PT-201 (hint 1) and `model.dutyLimited` (hint 3) separate the three candidates.
   - Coder: replace the `reb_foul` debrief in the H4 scenario data with ENGINE_API.md §11.9's new text (no engine change).
   - Validator: §H H4 F13 row as rewritten: FV-103 within ± 3 % of its pre-onset mean (1-min means) for ≥ 30 min, then 100 % within 5 min of the duty first falling below SP; `model.dutyLimited` raised. The engine's 53.8 min (s(t) 0.508 at 58.7 % OP) passes E.3 row 26.
4. **PHYSICS.md §16 thermosyphon row** still described the steam side as a perfect buffer with ≤ 0.5 %. It now names the τ_st = 10 s chest buffer and ≤ 1.5 %. No action.
5. **M8, G15 ≈ 6 % capacity gain: accepted, no change.** It follows from Robbins' liquid term (§16 "Packing" row), and G15's o4, its debrief and VC-13.6 already teach it as "in this shell". OPEN_ITEMS.md item 4 marked ruled.
   - Coder / validator: nothing beyond VC-13.6 as written.
6. **M8, packing table from memory: still open.** No doc change can verify it; it needs Kister (1992) ch. 8. OPEN_ITEMS.md item 1 stays flagged for the owner. If a value changes, re-run `tools/prototypes/m8/vc13.dart` and `g15.dart` before the M8 validation.

## M6 coder: spec rulings applied (coder, 2026-10-13)

- FT-103 steam-chest lag: Q_st (tau 10 s) is updated after each thermosyphon sub-step, feeds FT-103 and `steamSideDuty`, is initialised in `initThermosyphon` (so also after a kettle to thermosyphon rebuild) and saved in the control JSON (`qSt`). The M6 FT-103 steadiness test is back at 2 %; it passes.
- G14 o1 now needs `kpi.qr >= 1 260 000` and `loop[FC-103].op < 99`; hint 3 reworded. The hint player (LC-102 SP 40 %) meets o1 at 3060 s with FC-103 below 99 % and Q_R >= 1260 kW, so the hints stay as they are. Throttle-only at inlet 10 %: 1200 kW, not met.
- `eq.equilibrium.T2` is now `eq.raoult` in the tray trace (no alias). The M5 validation test `m5_mccabe_txy_validation_test.dart` line ~338 asserts the old id is absent in a way that should be reviewed by the validator.
- H4 `reb_foul` debrief replaced with the ENGINE_API.md 11.9 text.
- `runToSteadyState` at dt 30 on the ruling-5 case returns reached = false (dt 2: reached, D 16.317).

## M7 checkpoint (engine, coder, 2026-10-13)

Done: `debut` / `deprop` presets (Tier 3 default, keys, E 0.7, utilities from PHYSICS.md 2.3), `ColumnConfig.keys` / `KeyComponents`, key-cut analysers (AT-100/101/102 plus the full GC composition in `InstrumentReading.components`, aged like the value), `kpi.xDHeavy` / `xBLight` / `recoveryLK` / `recoveryHK`, C2/C3b/C5 on the GC compositions, `FugCalculator` / `FugResult` / `FugTargets`, Hengstebeck pseudo-binary data (`McCabeThieleBuilder.build(..., keys:)`), `ExplainFug` and `eq.hengstebeck`, G13 and H6 JSON, `pump` / `refluxPump` vocabulary. Tests: `test/m7_*` (presets, fug, hengstebeck, scenarios, explain, perf). Reference numbers VC-9.1, 9.2, 9.6, 9.7 and the VC-9.3 Hengstebeck values reproduce without adjustment; the DePriester model was already unclamped from M5.

Decisions and deviations:
1. **PC-101 gain (the "PC-101 at 7-17 bar" gap).** With Kc 10 `deprop` limit-cycles (V1 15 to 145 kmol/h, period 30 min), and Kc 70 to 100 still shows a slow 22-h cycle of D (27 to 34 kmol/h) fed by pressure wander (Tier-3 K depends on P). The small condenser and 34 bar span give a process gain of about 0.04 % span per % OP against B-T's 0.29. New `condenser.pcKc` (default 10, so every existing preset is unchanged): `debut` 30, `deprop` 120; both settle exactly to the VC-9.6 values. Questions for the spec lead: ratify per-preset PC-101 gains (suggest PHYSICS 10.2 states Kc scaled by the B-T gain ratio, here 3.8 and about 12), and note that `deprop` still overshoots a +50 kPa SP step by about 30 kPa because the CW valve saturates.
2. **Pressure lever range** for presets with P_design above 5 bar: 3 to 25 bar (SCOPE 4.1), PC-101 SP limit 25 bar. This also changes `c4` (lever max was 5 bar, below its 7 bar default).
3. **`kpi.xD` / `kpi.xB`** on multicomponent presets are the light key's fractions in D and B (x_D,LK, x_B,LK); the balance residual uses the light cut. Binary values are unchanged. Plant-view `kpi.xD`/`xB` are NaN for nc > 2, `xDHeavy`/`xBLight` carry the analyser values.
4. **TI-101 on `debut`.** The B-T tray scaling gives trays 2, 6, 11, 16, ... (no tray 1), so the preset lists `temperatureTrays` 1, 6, 11, 16, 19, 22, 27, 32 (VALIDATION H6 rows use TI-101 = tray 1).
5. **FugCalculator needs the thermo model**: `compute(snapshot, keys, {targets, required thermo})` (the snapshot has no K values). Adjacency is tested on the top and bottom alphas separately. The `eq.fug.*` values are alpha_LK, N_min, the Fenske D, R_min, N, N_R and the closing line `eq.fug.rigorous` (value N_act). **Question:** `eq.fug.rigorous` is not in the PHYSICS.md 15 catalogue; add it or give the closing line another id.
6. **T2 to T3 switch at constant duty** (PHYSICS 13.5) does not reproduce VC-9.6's "T2 0.9933 / 0.9948": that row is the T2 steady state at the same L0 and D with Q_R 681.4 kW. My test sets 681.4 kW after the switch; T1 uses the V1 rule as written.
7. **H6 evidence differences** (noise off, seed 3, drill events included):
   - F07: D has moved 1.5 kmol/h at 2600 s (the 900-s ramp is still settling; the spec's 44.94 to 44.54 is the steady value); asserted < 2.
   - F20 + planning: D exceeds the healthy case by 3.97 kmol/h at 2 h (spec steady 52.6 vs 48.5 = 4.1), asserted >= 3.9. C3a is `fail` 10 min after the event and `check` at 2 h, not `ok` as the §H row says (the meters are honest, but the condenser balance sees the transient and a 1 % drift at the higher D). Validator: decide whether C3a must be `ok` or just not `fail`.
   - Rule 1 (noise on, seeds 1 to 3): C4:FV-102 leaves ok within 10 s of the event; FT-102 sigma ratio 1.2 to 1.8, a bit above the 0.5 to 2 window's middle but inside it. `fv102_stuck` keeps weight 2.
   - F12: D 81.6 and x_D,heavy 0.40 at 2 h with the pump cap 63 kmol/h (steady prototype 54.0 / 0.168 is at fixed L0 and Q_R, not with LC-101 and the 8 % planning event on top). All the asserted thresholds hold.
8. **G13 hint player:** o1 is met at 14 400 s (par 21 600, limit 86 400) with the hint values; the three hint-state numbers match VC-9.8.
9. **Performance (VC-19):** 40 trays x 7 components Tier 3 takes 165 us/step in the JIT test VM including the control layers (target 100 us desktop AOT); not yet measured in release.
10. **Open spec points used as recommended:** column diameters unchanged at the B-T 1.2 m with `ideal` hydraulics (the 0.75 / 0.55 m diameters only matter for full hydraulics, not wired in yet; app/hydraulics decision pending); 852 degR DePriester limit kept as in the code, `thermoOutOfRange` set outside 365 to 852 degR / 14.7 to 870 psia.

## Spec rulings M7 (2026-10-13)

Rulings on the open items of "M7 checkpoint (engine, coder, 2026-10-13)" at eea0a5a.

1. **`eq.fug.rigorous`** (item 5): ratified as the id of the FUG closing line (value N_act; N_R,act and R_act substituted). Added to PHYSICS.md §15 and the M7 excerpt. The `compute(snapshot, keys, {targets, thermo})` signature is accepted.
2. **PC-101 per-preset gain** (item 1): ratified. `condenser.pcKc` (default 10) is PC-101's Kc on PV-101; `debut` 30, `deprop` 120, Ti 120 s, the OP/35 schedule on top. Rule: pcKc ≈ 10 × 0.29 / (preset process gain, % span per % OP at 50 % CW). PHYSICS.md §10.7 (table row and new paragraph), ENGINE_API.md §4 `CondenserConfig.pcKc`. The `deprop` +50 kPa overshoot (CW saturated) is the condenser's limit and is recorded, not asserted. New check VC-16.6d. Note: the checkpoint's "about 0.04 % span per % OP" does not give the stated ratio 12 (0.29 / 0.04 = 7.3); record the measured gains.
3. **Pressure lever** (item 2): ratified as SCOPE.md §4.1 already reads: light-hydrocarbon presets (Tier-3 model DePriester: `c4`, `debut`, `deprop`) 3–25 bar(a), PC-101 SP limits the same. `c4`'s 0.2–5 bar was a code error (below its 7-bar default). The range may exceed the relief set (as B-T's does). PHYSICS.md §2.3 lever bullet.
4. **H6 evidence** (item 7): engine right on all four; spec rows changed (VALIDATION.md §H and M7 excerpt):
   - F07: D within 1 kmol/h of start 2 h after onset (steady 0.40), within 2.5 kmol/h throughout (engine 1.5 at 2600 s).
   - F20: D ≥ 3.5 kmol/h above the healthy run at 2 h (engine 3.97, steady 4.1). C3a: not `fail` from event + 60 min, `ok` or `check` at 2 h. C3a has no drum-level term; with FV-102 stuck the extra vapour fills the drum until LC-101 (averaging tuning) raises D, so C3a `fail` right after the event is physics, not a meter symptom. The discriminator is C4:FV-102 with FT-102 flat. §14.6 fault table and the H6 F20 debrief (ENGINE_API.md §11.10) changed to match.
   - F12: brackets now carry the engine's 2-h values (D 81.6, xDHeavy 0.40); thresholds unchanged.
   - Rule 1 (σ ratio 1.2–1.8, weight 2): accepted as is.
5. **852 °R DePriester limit** (item 10): final; no clamping, `thermoOutOfRange` informational only (PHYSICS.md §3.4.2). Near 25 bar the `debut` bottoms approach it.
6. **Column diameters** (item 10, OPEN_ITEMS.md): ruled D_c 0.75 m `debut`, 0.55 m `deprop`; rest of the §5.1 geometry B-T (TS 0.9 m), sump/drum/overhead unchanged. Default hydraulics stay `ideal`. PHYSICS.md §2.3, ENGINE_API.md §11.10, VALIDATION.md VC-9.6 geometry note.
7. Items 3, 4, 6, 8, 9 noted; no spec change.

**Coder actions**
- Ship `condenser.pcKc` 30 / 120 as ruled, re-tuned (±50 %) only if VC-16.6d fails **on the 0.75 / 0.55 m diameters**; record each preset's measured open-loop process gain.
- Lever `pTop` and PC-101 SP limits 3–25 bar(a) for `c4`, `debut`, `deprop`, keyed on the DePriester family, not P_design.
- Apply D_c 0.75 / 0.55 m (only D_c changes), then re-run `m7_*` tests: VC-9.6 in `ideal` unchanged; H6 timings, G13 hint player and PC-101 checks on the new holdups. One full-hydraulics steady run per preset (VC-9.6 geometry note); report flood %, Φ_min, ΔP.
- H6 test asserts per the new rows (F07 2-h / 2.5 band, F20 ≥ 3.5 and C3a rule, report C5 (drum) for F20).
- Update the F20 debrief text and the `eq.fug.rigorous` explain id as in the spec.

**Validator actions**
- VC-16.6d (a)–(d) on both presets; VC-9.6 geometry note (a) and (b).
- H6 rows as changed: F07, F20 (C3a timing, C5 (drum) recorded), F12 brackets; rule 1 unchanged.
- `c4` lever range 3–25 bar with the M5 `c4` tests still passing at 7 bar.
- VC-21 covers `eq.fug.rigorous`; with `pTop` 25 bar on `debut`, `thermoOutOfRange` set and no NaN.

## M7 validation

Validator pass on engine eea0a5a, rebased on 54f9b41 ("Spec rulings M7"). New: `test/validation/m7_validation_test.dart` and an independent FUG `reference/fug_reference.dart` (PHYSICS.md §14.3, regula falsi for θ). Result: 23 pass, 2 skipped (M7-C1, M7-S2). Every check runs `ideal` hydraulics, so the steady values do not depend on the 0.75 / 0.55 m diameters. The H6 timings and the F07 transient may move with the smaller holdups, so they get a re-run after the diameter commit. VC-9.4 and 9.5 (E.3 #3–5) still pass in `m5_tier3_thermo_validation_test.dart`.

**M6 follow-ups (30d7cb6, d2cc6b5): all pass.**
- FT-103 5-s bins (Q_st buffer): un-skipped. 1.07 % p-p, limit 2 %. Unbuffered `kpi.qr` bins are 21.6 %.
- E.3 #3: I_s = 1 at 30.76 %, limit 30.8 ± 0.5.
- E.3 #13: printed value now 6.66 K.
- E.3 #18: every oscillating row has u ≤ 0.005 and delivered vs steam side ≤ 1.5 %. The old 0.5 % skip is removed.
- §H H4 F13 / E.3 #26: FV-103 1-min means stay flat (0.00 %) for 51 min, then reach 100 % 3.2 min after the duty drops below SP; `model.dutyLimited` is raised. The creep skip is replaced.
- G14 o1:
  - VC-14.3.4 sweep, inlet 8–16 %: o1 is never met. Inlet 8–11 % are stable but duty-limited (1157–1214 kW, FC-103 100 %). Inlet 12 %: I_s 0.995, 1238 kW, FC-103 100 %. Inlet 13–16 % surge (amplitude 0.034–0.070).
  - Inlet 10 % with SP 1150 kW: stable at 1150 kW, FC-103 57 %, o1 not met (duty term).
- `eq.raoult`: the stale `eq.equilibrium.T2` negative assertion is replaced. A new c4 Tier-2 test checks that `eq.raoult` = y* on three trays and that the old id is gone.
- `m4_energy_faults_test.dart` F12 now uses s 0.6 instead of 0.5, so it passes with either cap (see M7-C1).

**E.3 key numbers**

| # | Quantity | Engine | Result |
|---|---|---|---|
| 1 | `debut` FUG design: N_min, θ, R_min, N, N_R/N_S, D; d_iC4, d_nC5 | 10.9100, 1.31112, 1.3073, 23.282, 1.0042, 44.9437; 14.9806, 0.0631 (spec tolerances); engine core matches the independent FUG to 1e-6 | pass |
| 2 | `deprop` FUG design | 9.7203, 1.40567, 1.6522, 20.364, 0.4740, 30.7771 | pass |
| 7, 8 | VC-9.3 (T1, 22/12, E 1): r_LK / r_HK; 22/8 | 0.9843 / 0.9849, D 44.940; 0.9689 / 0.9717 | pass |
| 18 | Hengstebeck (VC-9.3 column): x′_D, x′_B | 0.98784, 0.01955; builder = stage compositions to 1e-9; α′ 2.041 | pass |
| VC-9.7 r4 | live FUG (VC-9.3 column): N_min, θ, R_min, N, N_R; N_act, N_R,act | within tolerance; 23.00, 11.00; matches the independent FUG to 1e-6 | pass |
| 10 | `debut` T3: r_LK / r_HK; xDHeavy, xBLight | 0.9781 / 0.9782; 0.01125, 0.01020 (KPIs = sums of the stage compositions to 1e-9); D 44.944; component closure 4e-11 | pass |
| 11 | T_0, T_B; Q_C | 49.57, 112.72 °C (± 0.05); 616.3 kW; T rises monotonically down the column | pass |
| 13 | FV-103 at the design duty = 60 % of Q_max,0 | `debut` 60.01 %, `deprop` 60.05 % | pass |
| 17 | Hengstebeck `debut`: x′_F, x′_D, x′_B; α′ top / bottom (own K calls) | 0.55556, 0.98252, 0.02723; 2.2157 / 1.8853 | pass |
| 19 | live FUG `debut`: α; N_min, θ, R_min, R, N, N_R; N_act, N_R,act | 5.1968 … 0.3844; 10.639, 1.3115, 1.2974, 1.6999, 22.56, 11.32; 23.4, 10.5; matches the independent FUG to 1e-6; N_act > N | pass |
| 20 | targets 98/98: N_min, R_min, N | within ± 0.15 / 0.005 / 0.3; matches the independent FUG | pass |
| VC-9.7 | guards: r_LK 0.5; keys iC4/iC5; R = R_min; plant view | invalid; `notAdjacent`; `belowRmin`, N = ∞; null | pass |
| VC-21 | `eq.fug.rigorous` = N_act 23.4 (54f9b41 item 1) | yes | pass |
| 12 | `deprop`: r_LK / r_HK; T_B; Q_C | 0.9906 / 0.9534; 123.85 °C; in band; P_top 17.24 bar | pass |
| 21 | live FUG `deprop`: N_min, R_min, N; N_act, N_R,act | within tolerance; 20.6, 7.0; matches the independent FUG | pass |
| 16 | `debut` T3 → T1 directly | V₁ continuous (121.344 → 121.344); D 44.944 → 44.794 at 1 s (LC-101 blip, 0.3 %) → 44.944; r 0.9835 / 0.9846 | pass |
| 23 | G13 hint state (L₀ 80, 697.9 kW) | 0.9822 / 0.9826; Q_C 634.2 kW; D 44.946; both recoveries above the default and ≥ 0.98 | pass |
| 25 | H6 F07 s 0.75 | AT-100 0.450 → 0.420 (−0.02 at 20 min); FC-102 / FT-102 unchanged before the event; TI-101 +4.7 K; xDHeavy 0.0626; D at 2 h −0.57 vs healthy | pass; "≤ 2.5 kmol/h throughout" fails (M7-S2) |
| 26 | H6 F12 s 0.585 | FT-102 31.7 kmol/h, not the 63.4 cap; OPSAT; D +39.7 at 30 min; xDHeavy 0.10 (over-range) | evidence passes; cap wrong (M7-C1) |
| 27 | H6 F20 + planning | D +3.97 vs healthy; xDHeavy 0.078; C3a fail at +10 min, check at 2 h (r/band 1.33), no fail from +60 min | pass (54f9b41 rows) |
| healthy | planning event alone | xDHeavy / xBLight ± 0.0001; D 48.72 | pass |

**Physical sense (pass):**
- Tighter recoveries raise N_min and N.
- R closer to R_min raises N.
- More reflux at the same D improves both recoveries.
- Moving the feed off its optimum tray lowers both recoveries.
- On Tier 3, α′ falls down the column, so N_act > the FUG N.
- The heavier feed raises TI-101 and xDHeavy while FC-102 stays put.

**Coder items**
- **M7-C1 (F12 cap).** `Stepper.refluxCapacity` is the design L₀ (simulator.dart: `refluxCapacity: l0`).
  - Effect: F12 caps the reflux at (1 − s) × 76.4 = 31.7 kmol/h for s 0.585.
  - Spec: PHYSICS.md §10.2 says F_cap = (1 − s) F_max of FV-102, and ENGINE_API.md §11.10 says (1 − s) × 152.8 = 63.4 (`{fault.magnitude}` 68.8–58.1 kmol/h).
  - Fix: use FV-102's F_max, then re-run H6 F12 and un-skip the at-cap test.
  - The checkpoint's "pump cap 63 kmol/h" for the D 81.6 / xDHeavy 0.40 result was really 31.7.
- **H6 re-run.** Re-run H6 F07 and F20 on the 0.75-m trays and report the F07 D transient. M7-S2 asks whether that transient is physical.

**Spec lead items**
- **M7-S1, the C3a / C5 (drum) explanation in 54f9b41 item 4.** The explanation does not hold. The engine's C3a does carry the drum term: `vRefl = L0 + D + ΔN0/W` in cross_checks.dart. The healthy planning run, with FV-102 working, also fails C3a at +10 min:
  - r/band 3.06: condenser side 138.2 vs 130.2 kmol/h;
  - ok again at 2 h (r/band 0.95).
  The planning step itself trips C3a in every candidate. So the F20 debrief's "C3a green" and the healthy row are misleading.

  Two causes:
  - (a) The overhead transient after +8 % with the CW near its limit.
  - (b) A steady bias. §14.6 takes λ_top = H_V(x_D, **T_bub**) − h_L. The vapour leaves at its dew point, and `debut`'s distillate has T_bub 49.6 / T_dew 55.3 °C. So V_cw reads +1.9 % high (123.65 vs V₁ 121.34; with T_dew, 120.93, −0.3 %). C3a therefore sits at r/band 0.95 in normal operation, and the heavier F20 overhead pushes it to `check`.

  C5 (drum) has the same pattern (−0.92 steady, fail −4.19 at +10 min, check −1.38 at 2 h), so it is not `ok` as expected.

  Suggest:
  - λ_top with H_V at T_dew(x_D, P̄_101), or at TI-101. This is unchanged for near-pure binaries.
  - A rule for the post-event C3a / C5 transient: ignore it, or slow the planning event.
  - Debrief text that does not promise C3a green.
- **M7-S2, F07 "D within 2.5 kmol/h throughout".**
  - Before the 45-min event, D peaks at +3.33 kmol/h 19.5 min after onset (drum level +1.4 %) and is +1.33 at 45 min. The 1.5 at 2600 s was one sample.
  - "D within 1 kmol/h of its start at 2 h" ignores the +8 % event: D − start = +3.2, against −0.57 vs the healthy run (asserted that way).
  - Suggest wording against the healthy response. Ask the coder whether a 7 % D swing from a dz ramp at fixed L₀ / Q_R is physical, once the 0.75-m holdups are in.
- **M7-S3.** The F12 brackets "D 81.6, xDHeavy 0.40" in 54f9b41 come from the M7-C1 cap. Replace them after the fix.
- **VC-9.6 tier-switch bullet** (checkpoint item 6, not ruled). VC-9.6 says the T2 numbers keep V₁ and D, but §13.5 keeps the duty on T2 ↔ T3. Say "at Q_R 681.4 kW" there. The T3 → T1 row is fine as is (validated directly).
- **Still open.** These wait for the coder's diameter and pressure-lever commit:
  - VC-16.6d;
  - VC-9.6 geometry (a) and (b);
  - `c4` 3–25 bar;
  - `pTop` 25 bar on `debut` with `thermoOutOfRange`;
  - VC-19 release timing.

## M7 app (coder, 2026-10-13)

Done: Phosphor theme (`phosphor.dart`, in the theme menu; scanline raster in the backdrop; VT323 not bundled, so the monospace fallbacks apply, and test screenshots use Share Tech Mono as a stand-in); `ThemePalette.seriesDash` (required, solid for the other three themes); Products tab (diagram tab id 3, multicomponent only): FUG panel (live / targets 98 % / 98 % with R = 1.3 R_min, recomputed every 10 s of sim time, invalid-key and below-R_min messages, rigorous N_act line) and the AT-100/101/102 GC lists with LK/HK marked; component profile chart (Profiles chip `x(i)`, series colour and dash per component, markers from the seventh); all presets (ew, ac, c4, debut, deprop) in the preset menu; G13 and H6 are in the scenario list. Tests `app/test/m7_ui_test.dart`; shots in `docs/screenshots/m7/`.

Decisions:
1. **Diameters** 0.75 / 0.55 m applied as ruled (only D_c changes). **Full-hydraulics steady runs** (`test/m7_hydraulics_test.dart`; seed 3, design levers): `debut` jet flood 54 % (rectifying) to 83 % (stripping), no weeping (0.00), dP 3.3 kPa/tray at the top, steady state reached. `deprop`: jet flood 59 % at the top, 121 % at tray 13 and 165 % at the bottom; no weeping; `runToSteadyState` does not reach steady in 400 000 s (D about 30.7). The spec's 60 % estimate (scaling against B-T) is wrong for the stripping section of `deprop` (liquid load plus a denser vapour). Scans (0.65 to 0.9 m, hole fraction 0.05 to 0.075) trade flooding at the bottom against weeping at the top; no single D_c gives both clean. **Question for the spec lead:** a larger D_c with fewer holes, or a taller sump section; hydraulics stay `ideal` by default as ruled.
2. Because of 1 the app sandbox loads `debut` and `deprop` with the preset's `ideal` hydraulics instead of the sandbox-default Full (SCOPE 4.2); the Hydraulics lever still switches. Other presets unchanged.
3. `pTop` lever limits (3 to 25 bar) now key on `tier3Model == dePriester` (or P_design above 5 bar); PC-101's own SP limit still keys on P_design (every DePriester preset is above 5 bar, so identical today).
4. Measured open-loop PC-101 process gains were not re-measured (VC-16.6d is the validator's); pcKc stays 30 / 120 and the `m7_*` steady states still hold on the new diameters.
5. H6 tests follow the rulings: F07 D within 2.5 kmol/h through 2600 s and within 1 kmol/h of the healthy run at 2 h (the planning event at 45 min raises D by about 3.6 on its own, so the "start value" comparison in the ruling needs the healthy run as the reference; **spec lead to confirm the row text**); F20 D at least 3.5 above healthy, C3a not `fail` at 2 h, C5 printed. F20 debrief text updated.
6. The McCabe-Thiele tab on multicomponent presets now gets `keys:` from the config (Hengstebeck data).

## M7 app 2 (coder, 2026-10-13)

- **M7-C1 fixed.** `Stepper.refluxCapacity` is now FV-102's F_max (152.8 kmol/h), so F12 caps the reflux at (1 - s) x 152.8 = 63.4 kmol/h for s 0.585 (FT-102 settles at the cap). H6 F12 on the 0.75 m trays, noise off, drill events included: D 62.44 kmol/h and true x_D,heavy 0.2196 at 2 h (AT-101 itself reads its 0.10 over-range); D is above 5 kmol/h over the start within 30 min. These replace the "D 81.6 / xDHeavy 0.40" brackets (they came from the 31.7 kmol/h cap). `m7_scenarios_test` asserts the cap-based thresholds.
- **H6 re-run on 0.75 m** (ideal hydraulics, as the drill uses): F07 s 0.75 at 2 h: AT-100 0.420, x_D,heavy 0.0628, D 48.19; the difference to the healthy run at 2 h is below 1 kmol/h (asserted). F20 + planning: D 52.79 vs healthy 48.68 (+4.11), x_D,heavy 0.0791; C5 at 2 h: drum `check`, sump `fail` (printed, not asserted). Rule 1 (noise on) unchanged: C4:FV-102 leaves ok within 10 s; sigma ratio 1.2 to 1.8.
- M7-S1 (C3a bias, T_dew) and M7-S2 (the F07 transient) are spec-lead items; the coder has not changed the C3a latent-heat rule.
- **Validator follow-up:** with the M7-C1 fix `test/validation/m4_energy_faults_test.dart` "F12 partial reflux loss (s 0.6)" fails on the B-T preset (FC-102 OP 33 %, no symptom): B-T's FV-102 F_max is 3 x the design reflux, so the cap (1 - 0.6) F_max is above the design reflux. The test needs s of about 0.75 or more (the spec's rule is unchanged). The coder does not edit that directory.

## Spec rulings M7 close-out (2026-10-13)

Rulings on the open items of "M7 validation" (2eff06f) and "M7 app" / "M7 app 2" (af6864e).

1. **M7-S1 (C3a / C5 drum).** The validator is right: C3a carries ΔN_0/W, and 54f9b41's "no drum-level term" was wrong. Two rulings:
   - **Bias fixed in the check:** λ_top = H_V(x_D, **T_dew**(x_D, P̄_101)) − h_L(x_D, T̄_100) (PHYSICS.md §14.6, C3a row). The top vapour leaves tray 1 at its dew point; T_bub read V_cw 1.9 % high on `debut` (r/band 0.95 healthy). C5 (drum) uses V_cw, so it follows. Unchanged for near-pure binaries; B-T rows keep their values within tolerance.
   - **Rate-step transient accepted, not masked:** new §14.6 bullet "Rate steps". C3a / C5 (drum) may sit at `check` / `fail` for up to about an hour after the +8 % planning event on a healthy column. Hints and debriefs never promise them green after a rate change; the F20 debrief (ENGINE_API.md §11.10) and the §14.6 fault-table row are reworded. VALIDATION.md H6: healthy row asserts C3a and C5 (drum) not `fail` from event + 60 min and `ok` at 2 h; F20 keeps "not `fail` from + 60 min, `ok` or `check` at 2 h", C5 recorded only.
2. **M7-S2 (F07 D transient).** Physical: the heavier feed moves the column profile (V₁ ≈ +0.6 kmol/h, and LC-101 draws down a drum level that rose ≈ 0.7 %). Mechanism reworded under M7-S5, "Spec rulings M7-S4/M8"; the first text's feed flash was refuted. Row now: D within 1 kmol/h of the **healthy run** at 2 h (the coder's reading confirmed), and until the planning event at most 4.5 kmol/h above its start (peak recorded). Below F12's ≥ 5 kmol/h, so the candidates stay apart.
3. **M7-S3 (F12).** Brackets replaced: af6864e, 0.75-m trays, noise off, at 2 h: D 62.4, true xDHeavy 0.22 (AT-101 over-range 0.10). Thresholds unchanged. The B-T test in `m4_energy_faults_test.dart` uses **s = 0.8** (cap 0.2 × 300 = 60 kmol/h, 0.6 × B-T's design reflux 100); the spec's F12 rule is unchanged.
4. **`deprop` tray design.** Two tray sections: trays 1–10 at D_c 0.55 m, trays 11–28 (feed tray and below) at **0.85 m**, the rest B-T geometry. Jet flood ∝ 1/A, so the stripping section drops from 121–165 % to ≈ 50–70 % while the top keeps its 59 % and does not weep. VC-9.6 (b) band is now 45–85 % per section (`debut`'s 83 % stripping is accepted, the normal design range; `debut` keeps a single 0.75 m). If 0.85 m fails (b), the coder may pick 0.80–0.95 m (smallest that passes) and record it. With (b) passing, the sandbox loads `debut` and `deprop` with Full hydraulics like every other preset (SCOPE.md §4.2); drills and guided scenarios stay `ideal`. PHYSICS.md §2.3, VALIDATION.md VC-9.6, M7.md, OPEN_ITEMS.md.
5. **PC-101 open-loop gains.** Not needed. The §10.7 rule is a design aid; VC-16.6d is the acceptance. Measure a gain only if VC-16.6d fails and a retune is needed.

**Coder actions**
- C3a λ_top at T_dew(x_D, P̄_101) (C5 drum follows); re-run the H6 F20 and healthy-planning tests with the new asserts; record C3a r/band at +10 min with the true and the measured TI-202 (one line, to name the transient's source).
- F07 test: D vs healthy at 2 h ≤ 1; D − start ≤ 4.5 until 2700 s; print the peak and its time on 0.75 m. Confirm the feed-flash mechanism in one line (feed enthalpy minus feed-tray liquid enthalpy during the ramp).
- F20 debrief text as in ENGINE_API.md §11.10.
- `deprop` preset: two tray sections (0.55 m trays 1–10, 0.85 m trays 11–28); if the engine takes only one tray section, add multi-tray-section support (the `sections` list already allows it). Re-run `m7_hydraulics_test` (flood % per section, Φ_min, ΔP, steady reached) and the `deprop` `ideal` tests (VC-9.6 (a), VC-16.6d on the new holdups). Then load both presets with Full hydraulics in the sandbox (reverts "M7 app" decision 2).

**Validator actions**
- VC-9.6 (a) and (b) on the two-section `deprop` and on `debut` (45–85 %); VC-16.6d on both presets.
- H6 rows as changed: F07 (healthy reference, 4.5 pre-event cap), F12 brackets, F20 and healthy-planning C3a / C5; B-T C3a rows (H3, H9, H10) still pass with λ_top at T_dew.
- `m4_energy_faults_test.dart` F12: s = 0.8.

## M7 close-out (coder, 2026-10-13)

Coder actions of "Spec rulings M7 close-out" (d48e6ff).

1. **C3a / C5 (drum) lambda_top at T_dew.** `cross_checks.dart`: lambda_top = H_V(x_D, T_dew(x_D, P-bar_101)) - h_L(x_D, T-bar_100). H6 on `debut` (noise off, seed 3): healthy planning C3a is `check` at +10 min (r/band 1.95; TI-202 true 34.07 C, measured 34.07 C, so the transient is the process side, not the meter) and C3a and C5 (drum) are `ok` at 2 h. F20 at 2 h: C3a `ok` or `check` (asserted), C5 `ok` (printed).
2. **F07.** Peak D - start before the 2700 s event: 1.64 kmol/h at 1600 s (limit 4.5, asserted); D within 1 kmol/h of the healthy run at 2 h. The flash mechanism is **not seen**: at the peak the feed (bubble point) is 4.7 K cooler than the feed tray, not hotter. The small D rise is the heavier-feed transient of the profile, not extra feed flash. Please re-read the ruling's mechanism sentence.
3. **F12** on af6864e at 2 h: D 62.44 kmol/h, true xDHeavy 0.2196. Thresholds unchanged. F20 debrief reworded as ENGINE_API.md 11.10.
4. **Multi-tray-section support.** The hydraulic solver and stepper take the tray geometry per stage (`geomAt`); `withTrays` changes the last tray section; the `trayType.0` lever sets every tray section. `deprop` now has trays 1-10 at 0.55 m and 11-28 at 0.85 m.
5. **`deprop` VC-9.6 (b) at 0.85 m (full hydraulics, design levers, steady run converges):** jet flood 59-68 % in the top section and 33-52 % in the stripping section (max 52 %, inside 45-85 %), but the stripping trays **weep** (weeping fraction 49-74 %, Phi < 0.75). Scan of the stripping D_c: 0.60 m 90-146 % jet, weep 7 %; 0.65 m 85-113 %, weep 8 %; 0.70 m 43-79 %, weep 60 %; 0.75 m 45-73 %, 56 %; 0.80 m 38-61 %, 66 %. No D_c in the allowed 0.80-0.95 m passes "no weeping" (weeping only gets worse with a larger tray). The preset keeps the ruled 0.85 m. **Question for the spec lead:** relax Phi_min for `deprop` (stripping at the low vapour load), reduce the stripping hole fraction, or accept the weeping. Until ruled, the **sandbox keeps `deprop` on its ideal hydraulics**; `debut` (0.75 m, jet 54-83 %, no weeping) now loads with **Full** hydraulics.

## M8 checkpoint (engine, 2026-10-13)

Engine side of M8 (docs/milestones/M8.md). `test/m8_*` reproduces VC-13.1-13.3 and 13.7 (correlations), VC-13.5 (T1 and T2 steady states, mixed template), VC-13.8 (all F21/F23 rows, +10 % and +25 %), VC-13.4 and the VC-13.6 / H7 evidence rows. Every [I] number of the prototype is matched inside its tolerance: `bt_packed` T1 x_D 0.993834, bed dP 587.4 / 818.6 Pa, column dP 1405.96 Pa; T2 x_D 0.99339, T_B 110.56 C, TI-101/109/110/118 80.44 / 91.80 / 93.37 / 110.06 C; H7 healthy 1263.2 / 1610.5 Pa, phi_p 0.6747 / 0.7865; the F21/F23 rows; +25 % lower bed phi_p 0.9747, dP 2953.8 Pa, HETP(18) 0.622 m, Q_C 1599 kW.

1. **Lag on the holdup factor (new, needed).** Evaluated literally, the explicit chain holdup -> L_k (6.4) -> phi_p -> factor 1 + 1.2 phi^13 oscillates with a 1-s limit cycle (phi_p alternating 1.08 / 0.69) once a segment sits above phi_p ~ 0.9 (e.g. H7 `crushed_lower` s 0.5, F23 at +10 %). The factor that sets the outflow coefficient of (6.4) now follows its raw value with a first-order lag of tau = 10 s (`PackedModel.tauFactor`). Steady states are unchanged; only the holdup response near flood is slower. The raw factor is what (6.3) and the snapshot report.
2. **phi_p, G'_fl and E_mal are recomputed every step**, not every 10 steps (6.3, 6.6): at about 40 flux evaluations per segment it costs less than 1 % of a step, and a refresh counter would make results depend on the step length.
3. **Dry-segment factor** min(1, h_L / 0.005) uses the volume fraction h_L (0.005 = 0.5 % holdup); the spec text reuses the tray's 5 mm.
4. **Carry-over** (phi_p > 1.05): the holdup above the value at phi_p = 1 (factor 2.2) is lifted with tau_c = 5 s into the segment above (the drum from segment 1), capped at 0.3 M/dt like the tray entrainment. The factor in (6.3) is capped at phi_p = 2 so that 1.2 phi^13 stays finite. No holdup sloshing was seen with the lag of item 1. Past flood (VC-13.4 n = 6, 30 min at +61 % of the design load): phi_p 1.062, lower-bed dP 4112 Pa (no-carry-over bound 3688), HETP(18) 0.734 m; phi_p crossed 1 during step 6 at dP 3477 Pa and the dP kept rising: 3863 Pa 5 min later and 3926 Pa after 10 min. Hardest H7 case (`crushed_lower` s 0.5 + event, 4 h): phi_p 1.131 at the lower bed, PDT-103 peaked at 6088 Pa (inside its 10 kPa span), no NaN and no negative holdup; the Newton step of the packed holdup never needs more than 100 iterations (bracketed, <10 in practice).
5. **Settling times.** VC-13.4 n = 4 -> 5 load step: lower-bed dP reaches 90 % of its new value in 40 s, the segment-18 holdup in 100 s (the drainage time). **G15:** after the `internals` switch x_D passes 0.993 and holds for 300 s at 3180 s of process time (par 3600 s is fine); the engine's `steady` monitor (1e-7 per 60 s) needs about 8 h after the switch because of the level loops (tau about 3200 s), which exceeds G15's 14 400 s limit. G15's o2 therefore reads `lever.internals == 1`, x_D >= 0.993 and column dP <= 1500 Pa (hold 300 s) instead of `steady`, and the hint says "wait until x_D has settled (about 50 minutes)". G15 o1 uses the quantity `pressureDelta` (kPa and psi, no gauge offset) rather than `pressure`.
6. **H7 evidence times** (noise off, bottom of each range, onset 600 s): `maldist_upper` TI span down 2 K at +810 s, x_D down 0.008 at +1020 s; `maldist_lower` TI span down 2 K at +690 s, x_B up 0.01 at +790 s (AT-102 reads 0.035 at 2600 s); `crushed_upper` / `crushed_lower` PDT-102 +30 % / PDT-103 +40 % within 10 s of the step. `near_flood` (event at 2700 s): PDT-103 1.84x, lower-bed calc flood 97.5 %, HETP(18) 1.25x, Q_C 1599 kW, PC-101 holds P_top (CW valve below 100 %).
7. **Feed in Tiers 2/3** stays `FeedQ(1.0)` (the engine's saturated-liquid feed at its bubble point), which is `FeedVaporFraction(0)` in effect, as for the M5 presets.
8. **Instruments.** PDT-(101 + b) read the bed dP (0 in ideal hydraulics), span 0-10 kPa, as PDT-101. The bus now starts PDT-101 and the bed PDTs at the true dP (the old start value 0 gave the first minutes of a full-hydraulics scenario a false "rise"). Bed TIs are the tray-TI tag rule on `temperatureTrays`.
9. **API shape.** `ColumnConfig.internals` holds the active template id (-1: none); `sections` is the template's. `LeverSpec.options` lists the offered integers of `feedStage` and `internals`; `trayType.<i>` carries the index of the first tray section (the mixed template: `trayType.1`) and sets every tray section. `FaultLocation.bed`, `CandidateDef.faultType == null` (a no-fault candidate) and `SimSnapshot.beds` follow ENGINE_API.md 4, 7.1, 9 and 11.2. `explain` for a packed segment returns the component balance, the equilibrium lines and `eq.robbins`, `eq.kisterGill`, `eq.packHoldup`, `eq.hetp`, `eq.lewis` and (model view, visible fault) `eq.maldistribution`; `eq.murphree` is not shown for packed segments.
10. **Plant views.** Bed `dP` in plant view is the PDT reading, in plantCalc the calculated sum; `maxFlood` NaN in plant, kept in plantCalc; `nTheoretical` NaN in both plant views; `eMal` and `maldistribution` NaN in plant views and in every drill. Stage `efficiency` is NaN in both plant views (E_mal inside).

## M8 app (coder, 2026-10-13)

1. **Packed-bed rendering** (`app/lib/painters/packed_painter.dart`, ENGINE_API.md 13.5). The static vessel layer draws, per bed, the packing texture (ring glyphs for random packings, zigzag corrugated sheets with alternating angle for structured packing, finer pitch for 500 m2/m3), a distributor trough with spray holes above the bed (it doubles as the redistributor of the bed above) and a support grid below; stages inside a bed have no decks, weirs or downcomers. The live layer draws per segment a liquid film on a fraction of 14 vertical strips (all strips wetted at a_w/a near 1, dry strips below 0.7), rivulets (3 to 16, count with the segment liquid load relative to the median, width with h_L) sliding down with the flow phase, vapour dots rising at a rate with the vapour flow, a HETP tick on the left bed edge (length with HETP relative to the bed's smallest HETP; model view and plantCalc only, since `hetp` is NaN in plant view), and, at phi_p >= 1, an alarm-coloured hatched pool over the segment (spreading half a segment upward at phi_p >= 1.1). The F21 bias (rivulet positions u^(1 + 3f)) is read only from `PackedBedSnapshot.maldistribution`; `test/m8_ui_test.dart` checks that a NaN paints exactly like f = 0 and that a visible f changes the picture. The feed arrow lands on the bed top.
2. **Levers.** `nTrays` and `murphree` are shown only when the engine offers them. A segmented Internals control (Trays / Packing / Mixed) appears in the INTERNALS group on `bt` and `bt_packed`; as for the reboiler type it acts only while paused (the label says so). The feed tray slider snaps to the offered stages (`LeverSpec.options`: trays and bed tops). The tray-type control uses whichever `trayType.<i>` the column offers.
3. **Faults tab.** Two sandbox cards, "Packing maldistribution" (F21, ramp 900 s) and "Crushed packing" (F23, step), with a bed slider; they appear when the column has beds. The broken-tray, fouling and foaming cards are disabled on a column without trays.
4. **Inspector, caption, dimension.** A packed segment shows dP, flood %, HETP, liquid holdup and wetted % instead of the tray rows. The McCabe caption reads "packed (HETP)" instead of "E = 0.70" when there are no trays; the vertical dimension on the column reads "HETP 0.50 m" on a bed.
5. **Menus and drills.** `bt_packed` is in the preset menu; G15 and H7 appear in the scenario list from `Scenarios`. Diagnose vocabulary: `packingDamage` "Packing damage (crushed)", `flooding` "Flooding (operating limit)", `bed:*` expands from the snapshot to "Upper bed (PDT-102)", "Lower bed (PDT-103)", "Bed 3 (PDT-104)".
6. **Sandbox hydraulics.** `debut` now loads with Full hydraulics (M7 close-out ruling, "M7 close-out (coder)" above); `deprop` stays ideal until the spec lead rules on its weeping. `m7_ui_test` follows.
7. **Screenshots** (docs/screenshots/m8/, 1000 x 700 at 0.8): `bt_packed` after loading, and a crushed lower bed at +50 % load with the flooding overlay (flood 112 %, column dP 10.2 kPa).
8. Not done: the Balance and Trends tabs list PDT-102 and PDT-103 only through the generic instrument lists; there is no dedicated bed chart. The mixed template has no theme-specific art beyond the shared bed drawing.

## M7 close-out validation

Validator pass on 0de364f (coder 7f3e3db, rulings d48e6ff). Changed: `test/validation/m7_validation_test.dart` (H6 rows as ruled, new group "M7 close-out": VC-9.6 (b) per tray section, VC-16.6d) and `m4_energy_faults_test.dart` (F12 s 0.8). The two skipped M7 tests (M7-S2, M7-C1) are un-skipped and pass. The H6 helper now switches the drill to model view (`view` lever), because drills start in a plant view and `kpis.xDHeavy` is then AT-101 (over-range 0.10 for F12).

**Pass**
- B-T F12, s 0.8: FT-102 sits at the cap 0.2 × 300 = 60 kmol/h, FC-102 OP 100 %, top T and drum level up.
- C3a λ_top at T_dew, `debut` healthy steady: C3a `ok`, r/band −0.17; condenser side 120.93 vs V₁ 121.34 kmol/h (−0.3 %, as predicted; T_bub would give +1.9 %). C5 (drum) `ok`, 0.19. The B-T C3a rows (H3, H9, H10) still pass.
- H6 healthy planning: C3a `check` at +10 min (r/band 1.95; C5 drum `fail`, −2.04, the accepted rate-step transient); no `fail` from +60 min; both `ok` at 2 h (−0.17 / 0.18); D 48.68.
- H6 F20 + planning: C3a `fail` at +10 min (2.57), `ok` from +30 min and at 2 h (−0.33); C5 (drum) `ok` at 2 h; D +4.11 vs healthy; xDHeavy 0.0789.
- H6 F07, s 0.75 (0.75-m trays):
  - D before the 2700-s event peaks at +1.64 kmol/h, 16.5 min after onset (limit 4.5).
  - D − healthy at 2 h: −0.49 kmol/h.
  - AT-100 drops 0.02 at 20 min; TI-101 +4.72 K; xDHeavy 0.0112 → 0.0628.
- H6 F12, s 0.585: FT-102 sits at the cap 63.41 kmol/h. At 2 h D is 62.44 and the true xDHeavy 0.2196 (AT-101 0.100). This confirms the ruling-3 brackets 62.4 / 0.22.
- VC-9.6 (a): every `ideal` E.3 row of `debut` and `deprop` (#10–#21) passes unchanged on the new geometry.
- VC-9.6 (b) `debut` (0.75 m, full, seed 3, cold start): steady at 35 880 s. Jet flood 54.0–74.5 %, Φ_min 1.017, no weeping, downcomer flood ≤ 25 %, column ΔP 11.81 kPa (r 0.9764 / 0.9784 in full hydraulics). The coder's "83 %" is the max-flood KPI (82.9 %); jet flood peaks at 74.5 %.
- VC-9.6 (b) `deprop` flood band: jet flood 59.0–68.3 % (trays 1–10) and 32.6–52.0 % (11–28), so both sections are inside 45–85 %. Max-flood KPI 68.3 %, downcomer ≤ 22 %, column ΔP 6.63 kPa. The `model.flood` alarm is still set at the end of the run: it latched during the cold start, and the KPI shows no flooding.
- VC-16.6d `debut` (Kc 30):
  - 24 h quiet: D p-p 0.0000 kmol/h; P_top within 0.000 kPa.
  - SP +10 kPa: inside ±1 kPa from 290 s; overshoot 7.3 %; decay 0.00.
  - SP −10 kPa: inside ±1 kPa from 590 s; overshoot 11.2 %; decay 0.01.
- VC-16.6d (a) `deprop`: quiet over 24 h.

**Coder open points (checked)**
- **`deprop` weeping fails VC-9.6 (b): confirmed, with one addition.** Stripping Φ_min is 0.341 (weeping 74.3 %); the top section is at 0.909.
  - **New:** `runToSteadyState` does **not** converge in 400 000 s (seed 3, cold start). Over the last 2 h D drifts 30.83–30.91 kmol/h. The coder's "steady run converges" does not hold for this start.
  - Mechanism: Φ = √(h_dry/h_cl) scales with the hole velocity. The 0.85-m stripping trays have 2.39× the area of the 0.55-m top trays, so u_h falls 2.4× at a similar vapour flow, and a larger D_c only makes it worse (the coder's scan agrees).
  - Probe (record only), stripping hole fraction cut from 0.10 to 0.05 at 0.85 m: Φ_min 0.536, weeping 39 %, jet flood 44–83 %. D then limit-cycles at 28.5–33.3 kmol/h and the recoveries fall to 0.943 / 0.979.
  - At hole fraction 0.06 (an earlier run): Φ 0.44, weeping 57 %, D cycles 28.2–33.6.
  - Cutting the hole area alone therefore gives no clean tray either.
- **F07 feed-flash mechanism (ruling 2): refuted. The coder's "not seen" is confirmed with numbers.**
  - Before onset, the feed is 3.54 K below its tray (tray 16). Its vapour term F (h_F − h_L,16)/λ₁₆ is −3.41 kmol/h: the feed condenses vapour.
  - At the D peak the feed is 4.65 K below its tray and the term is −4.81 kmol/h, a change of −1.40. The heavier feed condenses more vapour, not less. The term's largest rise during the ramp is +0.11 kmol/h, 2 min after onset.
  - The +1.64 kmol/h D peak is V₁ +0.64 kmol/h plus LC-101 drawing down a drum level that rose 0.70 %; V_B rose 0.25.
  - The row's numbers stand (1.64 ≤ 4.5, well below F12's 5); only the mechanism sentence needs new wording.

**Coder items**
- **M7-C2 (VC-16.6d `deprop`, fail).** With pcKc 120 on the 0.55 / 0.85-m column, PC-101 is underdamped:
  - SP +10 kPa: inside ±1 kPa only after 1720 s (limit 600); overshoot 28.5 %; decay 0.65 (limit 0.3).
  - SP −10 kPa: not inside ±1 kPa within 30 min; overshoot 44.8 %; decay 0.85.
  - SP +50 kPa (c, record): overshoot 37 % (18.5 kPa); no relief.

  Ruling 5's condition applies: measure the open-loop gain (VC-16.6d (d)) and retune pcKc / Ti. The test is skip-flagged with these numbers.
- **`deprop` D limit cycle at reduced hole fraction (question).** Say whether the 5 kmol/h D cycle with weeping stripping trays (hole fraction 0.05–0.06) is physical tray dumping or a numerical coupling of weep flow and h_cl. It matters if the spec lead picks a hole-fraction fix.

**Spec lead items**
- **M7-S4 (`deprop` stripping trays).** Weeping plus no convergence at 0.85 m. Options:
  - (i) accept the weeping for `deprop` and relax Φ_min for its stripping section in VC-9.6 (b); the sandbox stays `ideal`, as now;
  - (ii) valve trays, or a Φ_min suited to high-pressure service (ρ_V ≈ 36 kg/m³ at 17 bar);
  - (iii) D_c 0.65–0.70 m with a larger tray spacing against the jet flood.

  The validator suggests (i). The VC-9.6 (b) weeping test is skip-flagged spec-pending.
- **M7-S5 (F07 wording).** Replace the feed-flash sentence of ruling 2. Suggested: "the heavier feed's transient: V₁ +0.6 kmol/h while the trays heat up, plus the drum-level response of LC-101".

## M8 validation

Validator pass on 0de364f (engine 9eb2b6e, f1fbc23). New files:
- `test/validation/m8_validation_test.dart`, 16 tests.
- `reference/packed_reference.dart`. It holds PHYSICS.md §6.3–6.6 and (4.3) written from the spec text, with no engine imports: Illinois regula falsi for G′_fl (1e-13), closed-form Kremser / parallel-column, and a Newton CMO column with per-stage E.

Every column check recomputes each packed segment's ΔP, φ_p, h_L, HETP, λ and E_MV, and each bed's n_th, S and E_mal, from the engine's own state (flows, x, y, T, P; Tier-2 properties from the thermo model). The engine matches everywhere: ΔP 0.1 %, φ_p and E_MV 1e-4, HETP 1e-4 relative. The coder's full M8 suite (VC-13 rows, H7 evidence, G15 hint player) also passes. **Result: pass; no blocking item.**

| E.3 # | Quantity | Engine (reference) | Result |
|---|---|---|---|
| 1, 2 | Robbins 309.8307 Pa/m; Kister–Gill 765.17 … 1746.13 | same; engine G′_fl (40 bisections) = reference to 1e-9 | pass |
| 3–6 | struct250 / pall25m / pall50m at the B-T load; flood-line ΔP and h_L at φ 0.8 / 0.95 / 1.0 | every value within its VC-13 tolerance | pass |
| 7, 8 | wetting factor 1.10535 / 1.25427 / 1.46463; HETP rule 0.5016 / 0.3016 m | same | pass |
| 9–11 | E_mal 0.5579 / 0.2559 / 0.4423 (n 8.5, n_eff 3.760); Lewis 0.74015 | same | pass |
| 12 | `bt` 20/10, E 0.7 | reference Newton 0.981183 | pass |
| 13, 14 | `bt_packed` T1 full: x_D, x_B; bed ΔP; column ΔP; φ_p; S | 0.993834 = CMO with E_O 1 on 18 stages (0.993834); 0.006166; 587.4 / 818.6 Pa; 1406.0 Pa; 0.4882 / 0.5938; S 0.7685 / 1.1714 (validator's own λ); min L′ 1.924 / 4.201 | pass |
| 15, 16 | T2 full: x_D, x_B, D, T_B, column ΔP; TI-101 / 109 / 110 / 118; λ | 0.99339, 0.01063, 49.796, 110.56 °C, 1276.2 Pa; 80.44 / 91.80 / 93.37 / 110.06 °C; λ 0.590 … 1.638; min L′ 1.920 / 4.054 | pass |
| 17 | Mixed template, T1 ideal; `murphree` 0.5 | 0.991331 = CMO; 0.980869 = CMO with E 0.5 on the trays only; segments keep E 1 | pass |
| 18 | G15: ΔP ratio; k = 0.629 / 0.5938 | 10.31; k 1.0593 gives a lower-bed φ_p of exactly 0.6290 (upper bed × k) | pass |
| 19 | VC-13.4 n = 5: φ_p, ΔP, HETP(18), h_L(18), x_B | 0.9555, 2692.7 Pa, 0.5968 m, 0.10265, 0.00832 | pass |
| 20 | H7 healthy | 1263.2 / 1610.5 Pa, 0.6747 / 0.7865, 0.99357 / 0.01108 | pass |
| 21, 26 | H7 +25 %; +10 % | ΔP 2953.8 Pa (×1.834), φ_p 0.9747, HETP(18) 0.6221 m, n_th 7.547, h_L 0.0627 → 0.1193, x_B 0.01708, Q_C 1599.3 kW, D 62.05; +10 %: φ_p 0.8630 | pass |
| 22, 23 | F21 upper / lower, s 0.5: E_mal; x; TI span; own-bed ΔP | E_mal 0.5725 / 0.5627 = Kremser on the engine's n_th 9 and the validator's S (0.7508 / 1.0392); x_D 0.97875, x_B 0.03646; spans 11.46 → 8.09 and 12.97 K; ΔP +0.3 % | pass |
| 24, 25 | F23 upper 0.3 / lower 0.3 / lower 0.5 | 1848.6 / 2534.6 / 3331.6 Pa; φ_p 0.7529 / 0.8814 / 0.9358; n_th 8.595 / 8.329 / 7.502 (H_bed × (1 − 0.15 s)); x moves < 0.007 | pass |
| 28 | L′_des 1.9 / 4.0 | below every segment L′ at the T1 and T2 defaults | pass |

Not checked: #27 (condenser 1795 / 1382 kW at 100 % CW). It belongs to the condenser model validated in M3 / M4. In `near_flood` the CW valve peaks at 44 % with Q_C 1599 kW.

**Physical sense and directions (pass)**
- **ΔP vs load.** d ln ΔP / d ln G′ at fixed L′/G′ rises from about 2 at φ 0.5 to above 3 at flood. 1.61× the load (n 0 → 5) gives 3.3× the lower-bed ΔP.
- **Flooding.** F23's F_p,eff lowers G′_fl, so φ_p rises at constant load.
  - `near_flood` drill: PDT-103 rises ×1.839 and reaches 1.7× 70 s after the event. It peaks at 3062 Pa 210 s after the event, 3.7 % over the value it settles to, and is within 1 % of VC-13.8's 2953.8 Pa after 30 min.
  - At the same time PDT-102 is ×1.679, the lower-bed φ_p 0.9751, HETP(18) 0.500 → 0.623 m, and the CW valve ≤ 44 %.
  - Past flood, the coder's VC-13.4 dynamic row: φ_p crosses 1 at 3477 Pa, then 3863 Pa (+5 min) and 3926 Pa (+10 min).
- **HETP modifiers.**
  - Turndown to 50 % (ratio-preserving): HETP(1) 0.550 m (wetting) and HETP(18) 0.526 m; n_th 8.22 / 8.53; x_D 0.99383 → 0.99145; ΔP 321 Pa.
  - Loading: g(φ) gives HETP(18) 0.597 m at n = 5 and 0.622 m at H7 +25 %.
- **Maldistribution.** E_mal falls with n and with f and is lowest near S = 1. In the column it equals Kremser on the bed's own n_th and S, and the bed's ΔP and φ_p move by less than 1 %.
- **Mixed columns.** `murphree` acts on the trays only.
- **G15 o2.**
  - The trays state fails o2 (14.5 kPa, x_D 0.978).
  - The packed steady state has margins of +0.00083 in x_D and 94 Pa in ΔP.
  - After the switch (10-s sampling), o2 is met at 3150 s (coder 3180 s; par 3600 s) with x_D 0.99312; at +2 h x_D is 0.99377 (steady 0.99383).
  - The new o2 is sound.

**Coder deviations**
1. **Holdup-factor lag (τ 10 s): physically sound as a numerical device; steady states unchanged.**
   - The validator's loop gain of the explicit chain holdup → L_k → φ_p → factor is 3 × (d ln φ/d ln L = 0.099 at fixed G′) × d ln f/d ln φ: 0.04 at φ 0.7, 0.90 at 0.9, 1.47 at 0.95, 2.67 at 1.05. So a 1-s update goes period-2 just above φ_p 0.9, exactly what the coder saw.
   - Cost: τ is long against a segment's film drainage time. At n = 5 the whole lower bed has Σ M/(3L) ≈ 15 s, so about 1.7 s per segment. Near flood the holdup response is therefore lag-dominated (coder: holdup at 90 % in 100 s, ΔP in 40 s).
   - The lagged update stays monotone for τ ≥ dt (1 + gain) ≈ 4.3 s at the hardest case (φ 1.13, gain ≈ 3.3). **Optional (coder):** τ = 5 s halves the distortion.
2. **φ_p, G′_fl and E_mal every step: accepted.** This is the spec's model without the cost-saving refresh, and it removes the step-length dependence. PHYSICS.md §6.3 / §6.6 still say "every 10 steps" (spec text).
3. **Dry-segment factor h_L/0.005: accepted.** §6.1 should say "0.005 volume fraction", not reuse the tray's 5 mm (spec text).
4. **Carry-over, G15 o2 via x_D / ΔP, PDT start at the true ΔP: accepted.**

**Spec lead items**
- **M8-S1 (text only).** §6.3 / §6.6 refresh "every 10 steps" → "every step"; §6.1 dry-segment threshold as a volume fraction.
- **M8-S2 (optional).** G15 o5 says x_D rose "from 0.978 to 0.994". When o2 latches, x_D is 0.9931; it reaches 0.9938 about 2 h later. Say "to about 0.994 once settled", or leave as is.

## M9 checkpoint (engine, 2026-10-13)

Engine side of M9 (docs/milestones/M9.md). `test/m9_*` reproduces VC-15.1-15.3 (assay, enthalpy rule, Daubert, ideal and lumped cuts), the VC-15.4 table, the direction checks, VC-15.5 (F24 bottom 1 / 0.5 / ss2, F25 1 / 0.85 / 0.5, F26 1 / 0.6, F27 by levers), the H8 rows, VC-15.6 (G16), VC-15.7 (structure, lever and fault extremes, no alternation), VC-26.1 and VC-21 for the crude equation ids. All prototype values are matched inside their tolerances; most to the printed digit (yields 19.75 / 11.70 / 16.70 / 5.30 / 46.55, D86 and gaps, Q_C 8.945 MW).

1. **Architecture.** The crude unit is a separate model (`model/crude_column.dart`, `control/crude_control.dart`, `thermo/crude_thermo.dart`), not an extension of `Stepper`/`ColumnState`; `Simulator` branches to it (`sim/simulator_crude.dart`, a `part` file). `ControlSystem` got a public `generic(...)` constructor plus `indexAll`, `runLoop` and `pushTrends`; `CrudeControl` extends it. The snapshot maps the column to 32 stages (drum, 30 trays, sump) and 10 components (water is the 10th; its y is the steam fraction, its x is 0). `Kpis.crude`, `SimSnapshot.strippers` and `SimSnapshot.crudeProducts` carry the M9 data; `energy` is null and the cross-checks, field gauges and McCabe data are absent for `crude`.
2. **Step and settling.** `step()` is 44 us (AOT, desktop, whole simulator step with control and instruments; 43 us in JIT). VC-19 target 150 us met; Android 450 us not measured. The explicit coupling of 9.4 is stable at dt = 0.5 s. A cold start declares steady after 4.2 h (<= 8 h). The steady run uses **dt = 0.5 s for `crude`** (the 2 s fast-forward step rings on empty draw trays and moves the dry-draw states); `advanceFast` likewise.
3. **Semi-implicit weir outflow (new, needed).** The explicit weir relation of 4.6 is unstable above dt of about 1 s on the 1.0 and 1.7 m trays. The holdup update uses L_out(M_new) = L_out + dL/dM dM, top-down. A dry tray keeps a film of 5 % of its static weir holdup (otherwise its composition wanders and the AGO tray hopped between three dry states at 8, 14 and 28 h).
4. **Stripper level.** The boot is 1.0 m3 at 100 % with SP 50 %, as specified. The product cut uses the prototype's law in fractions of the SP, clamp((M/M_SP - 0.2)/0.3, 0, 1); read literally in percent (9.4: "(level - 20 %)/30 %") it gave AGO 5.1 instead of 3.20 vol % for F24 s = 1. The draw limit is 0.5 (M - 0.3 M_0)/dt as written.
5. **F24 semantics.** Delivered steam = min(valve flow, (1 - s) x demand) (demand = FC SP, or the valve flow in MAN), so FC-32x saturates at every s and s = 0.5 gives the reference +0.52 vol %. A pure (1 - s) factor on the valve flow would be compensated by the loop up to s = 0.5. F25 follows (9.3) with FC-314 on a 15 MW cooler valve; F26 shifts the true COT only.
6. **Control.** FC loops Kc 0.5 / Ti 3 s (FC-314: 0.4 / 4 s) at the main step, valves tau 2 s. TC-301 is a 50 K span master (Kc 1, Ti 300 s) on FC-301 (CAS; FC-301 in AUTO puts TC-301 in IMAN, going back to CAS is bumpless). LC-301/302: Kc 2, Ti 1800 s (the B-T values) on a 10 m3 drum and a 20 m3 sump, which have their own holdups (the prototype's levels were ideal). TC-320 is a first order (tau 60 s) with the OP shown as the COT in %; in MAN the OP sets the COT. New tags not named in 10.7: `FT-300` (crude rate), `FT-301` (reflux), `FT-311..313` (product volume flows), `QT-314` (PA duty, the FC-314 PV), `FT-321..324` (steam, kg/s), `LT-301/302/311..313`, `PDT-301`. Valve spans: reflux 684 kmol/h, products 25 / 30 / 15 % of 265 m3/h, bottom steam 5000 kg/h, stripper steam 1000 kg/h, cooler 15 MW. Instruments use the generic transmitter model (TI sigma 0.075 % of 0-400 C).
7. **Hydraulics.** Pressure drop, jet flood and froth use the prototype's valve-tray relations, refreshed every 10 s. Entrainment and the downcomer limit are not modelled for `crude`; the weeping fraction is a simple function of the dry drop against the lift pressure (zero at the default). The `hydraulics` lever is offered: ideal gives 700 Pa per tray and no flood or weep figures.
8. **Products and plant views.** Lab D86 (naphtha-AGO, 5 / 50 / 95 %) and residue TBP 5 % are sampled every 1800 s and published 900 s later; a lab result from before the start is shown until the first publish. Plant views draw three lab points per product instead of a curve, and TBP curves of products are not drawn. `plantCalc` keeps Q_C, flood and the PA limit (true values stand in for the calculated ones; CW is not modelled); plant keeps neither. Yields in the plant views come from FT-311..313; naphtha and residue yields stay model values.
9. **Ideal yields (Products tab).** Naphtha cut fixed at TBP 165 C, then the three product levers as cumulative yields: at the defaults 20.00 / 11.70 / 16.70 / 5.30 and cut points 165 / 240 / 340 / 370 C.
10. **Times.** G16: PA 3 MW alone meets the specs after 19 min but the steady monitor (1e-7 per minute) needs about 3.75 h, so `o1` (with `steady`, hold 600 s) completes after about 4 h of process time against par 7200 s; the par is the spec's estimate and is left unchanged. H8 off-spec predicate (hold 300 s) fires 420 s (F24 s 0.85), 390 s (F25 s 0.85), 560 s (F26 s 0.8) after onset. F24 s = 1 and F26 s = 1 leave the AGO tray at the dry edge and the monitor does not declare steady within 48 h (residual 1e-3); the states themselves are flat.
11. **Save/restore** of a crude run continues within 1e-5 relative (the hydraulic refresh phase is not stored).
12. **Pre-existing:** `test/validation/m5_columns_validation_test.dart` "dt 30" still fails (validator's folder, known).

## M9 app (coder, 2026-10-13)

1. **Brass theme** (`app/lib/theme/themes/brass.dart`): the SCOPE.md T-4 palette, a bevelled shell with rivets, amber liquid, steam puffs on the vents and the strippers' steam inlets, a flame sprite on the furnace that follows the COT, a dial with a damped needle (zeta 0.6, 0.4 s) for the COT, porthole sight glasses on the stripper boots, and charts on a parchment inset with sepia ink and a brass frame. **"Cinzel", "IM Fell English" and "Courier Prime" are not bundled** (no downloads, as for VT323): the serif and monospace fallbacks apply. The screenshot helper maps them to bundled fonts. Drum and sump levels are drawn as fills, not portholes; the dial gauges for pressure and the other key temperatures are not drawn (the COT dial and the numeric labels carry them).
2. **Crude flowsheet** (`crude_painter.dart`, `crude_geometry.dart`, `crude_flowsheet.dart`) replaces ColumnView for `crude`: 30 stages with the 1.7 m section swaged in below stage 26, three two-stage strippers beside the column with level fills and sight glasses, the pumparound loop with a cooler symbol (duty and return T), the furnace on the feed line (COT, flash-zone T, overflash), steam inlets with flows, the drum with the naphtha, and product labels with yields; liquid colour follows the mean boiling point of the stage liquid. Tap hit-tests open the math overlay with the crude equation ids: a stage (and it selects it for the inspector), a stripper stage, a product line, the pumparound, the drum and condenser, the overflash band; the furnace and the bottom steam open stage 26 and stage 30. Pinch zoom through `InteractiveViewer`. The column panel is 36 % wide on the expanded layout for `crude` (25 % otherwise). The draw lines are not clickable on their own; the stripper boxes are.
3. **Products tab** (`crude_products_panel.dart`): TBP curves (feed and five products, ideal cut temperatures as ticks on the right edge of the plot, not vertical ticks on the volume axis), D86 curves of the four distillates, the three gap bars (green >= 0, red < 0, labelled in K), and the yield table against the ideal yields with the overflash and the residue TBP 5 %. In the plant views the tab shows the lab result with its sample time; its D86 is the three points 5 / 50 / 95 % as markers, and only the feed TBP is drawn. `crude` has only the Products and Profiles tabs, and opens on Products; McCabe-Thiele, T-x-y and the FUG panel are not built for it.
4. **Panels.** The Levers tab shows the crude groups (feed, top, draws as product rates, pumparound, steam, hydraulics, instruments); the draw levers' ranges follow the current crude rate. The KPI strip shows yields, overflash, kero D86 95 %, the diesel-kero gap, residue TBP 5 %, Q_C, drum and flood. The Faults tab has the F24 (steam point chips), F25 and F26 cards and a note that F27 is not injectable. The Loops, Balance, Trends and Energy tabs build from the generic snapshot (no crude-specific content; the Balance tab has no cross-checks for `crude`, the Energy tab is empty).
5. **Vocabulary and menus.** The diagnosis vocabulary has `steamLoss`, `pumparound`, `furnace` and `steam:*` expanding to the four points ("Bottom stripping steam (FC-321)", "Kero stripper steam (FC-322)", ...). The preset menu has "Crude unit (20 000 bbl/d)"; G16 and H8 are in the scenario lists (they come from `Scenarios`).
6. **Tests.** `app/test/m9_ui_test.dart` (render, Products tab, panels, taps to the math overlay, every control tab, faults, G16 / H8, plant-view lab note, layouts at 360 x 800, 800 x 360 and 900 x 700). The full app suite passes (39 tests).
7. **Screenshots** (docs/screenshots/m9/, 1440 x 900 at 0.5 and 0.4): the Brass crude flowsheet with the Products tab, and the same screen in Blueprint.
8. Not done: golden image tests of the flowsheet; the Android emulator run; phone-specific art for the flowsheet (the portrait layout shows the same drawing in the 40 % column slot, at small type).

## Spec rulings M7-S4/M8 (2026-10-13)

Rulings on the open items of "M7 close-out validation" and "M8 validation" (15ba03a) and on "M8 checkpoint" (f1fbc23). Evidence:
- a scratch copy of the engine at e2b6e63, used for full-hydraulics `deprop` runs with overridden decks and PC-101 tuning (seed 3, cold start, `runToSteadyState` 400 000 s; not committed);
- `tools/prototypes/m7/deprop_trays.dart`, PHYSICS.md §5.1–5.8 at the `deprop` design flows (pure Dart). It reproduces the engine: valve Φ_min 0.916, jet 66 / 64 %, ΔP 10.52 kPa; sieve f_h 0.05 Φ_min 0.638 against the engine's 0.642.

1. **M7-S4: `deprop` gets valve decks on both sections. D_c stays 0.55 / 0.85 m and the rest of the geometry is unchanged** (B-T valve data f_v 0.14, r_min 0.25, ΔP_lift 190 Pa, C_v 0.65; TS 0.9 m, f_d 0.12, h_w 0.05 m).
   - **Why it never converged: PC-101, not the trays.** With PC-101 at Ti 120 s even a weep-free valve column cycles: P ± 0.6 kPa, CW 46–54 %, period ≈ 1100 s, D 30.53–30.83 kmol/h, and it does not reach steady in 400 000 s. With Ti 400 s (item 3), the present sieve column reaches steady at 21 900 s and still weeps 74 % (Φ_min 0.341). The two items are coupled.
   - **Why it weeps.** Φ = √(h_dry/h_cl). At 17 bar ρ_V is 37–41 kg/m³, so the 0.85-m sieve deck has a dry drop of 24–43 Pa (h_dry 5–10 mm) against h_cl 44–51 mm.
   - **Layouts** (prototype at the design load; engine values in brackets):

     | Trays 1–10 / 11–28 | Jet max top / stripping | Φ_min stripping (weeping) | ΔP | Verdict |
     |---|---|---|---|---|
     | sieve 0.55 / 0.85, f_h 0.10 (now) | 66 / 64 % | 0.32 (78 %) [0.341, 74 %] | 7.0 kPa | fails weeping |
     | sieve, stripping f_h 0.05 | 66 / 86 % | 0.64 (20 %) [0.642, 19.7 %; no steady even at Ti 400] | 8.8 kPa | fails both |
     | sieve, stripping f_h 0.045, h_w 25 mm | 66 / 88 % | 0.86 (0) | 8.3 kPa | jet above 85 %; weeps 11 % at 80 % load |
     | sieve, stripping 0.70 m, f_h 0.06, h_w 25 mm | 66 / 118 % | 0.96 (0) | 8.8 kPa | floods |
     | **valve 0.55 / 0.85** | **66 / 64 %** [66.3 / 64.2] | **0.916 (0)** [0.916] | **10.5 kPa** [10.52] | **ruled**; no weeping down to ≈ 75 % of the design vapour load |
     | valve 0.55 / 0.75 | 66 / 82 % [82.4] | 0.939 (0) | 10.3 kPa | passes and has more turndown (no weeping at 60 %), but sits 3 points from the band edge and changes the holdups |

   - **The other levers.** Weir height lowers h_cl (25 mm: −30 %), but alone it does not reach Φ 0.75. Hole diameter enters only ΔP_σ = 4σ/d_h (≈ 1 Pa), so it does nothing for weeping in this model. Tray spacing enters only jet flood, M_max and the downcomer. The engine has single-pass trays only, and f_d moves A_a and L_w only a little.
   - **Valves are the natural deck for high-pressure light ends.** Between closed and fully open they balance at ΔP_dry = ΔP_lift. The engine takes one deck type per column (the `trayType` lever sets every section), so both sections are valve. Above the feed, Φ is 1.17 against 0.91 on sieve.
   - **Engine check** (valve, Ti 400 s): steady at 37 200 s. Jet flood 58.6–66.3 % (1–10) and 45.1–64.2 % (11–28), Φ_min 1.173 / 0.916, downcomer ≤ 31.5 %, ΔP 10.52 kPa, D 30.676 kmol/h, r_LK / r_HK 0.9893 / 0.9562. `ideal` is identical for sieve and valve: D 30.780, 0.9906 / 0.9534, so VC-9.6 (a) is unchanged.
   - **VC-9.6 (b) alarm rule.** "No downcomer-backup or flooding alarm" means none active at the end of the run. An alarm that latched during the cold start and has returned to normal does not count; the validator's `model.flood` note was this case.
   - The close-out ruling 4's "0.80–0.95 m" clause is superseded. The sandbox loads `deprop` with Full hydraulics, as it does `debut`.
   - **The validator's D-cycle question.** The 5-kmol/h cycle at f_h 0.05–0.06 was PC-101 (Ti 120 s) amplified by the weeping. With Ti 400 s it shrinks to D 30.60–30.83 but still does not converge (Φ_min 0.64, weeping 20 %). Φ stays above 0.2 on every tray, so it is not tray dumping. What remains is a weep-law coupling at partial weeping. No preset default runs there, so it is recorded, not fixed.
   - Edits: PHYSICS.md §2.3 (table note and M7 geometry bullet), VALIDATION.md VC-9.6 geometry note, M7.md, OPEN_ITEMS.md.
2. **M7-S5 (F07 wording).** The validator's refutation stands, and close-out ruling 2's mechanism sentence is replaced. New wording: the heavier feed moves the column profile; it is not a feed flash. The feed stays 3.5–4.7 K below its tray and, as it gets heavier, condenses slightly more vapour (−3.4 → −4.8 kmol/h). The D peak (+1.64 kmol/h at 16.5 min) is V₁ ≈ +0.6 kmol/h plus LC-101 drawing down a drum level that rose ≈ 0.7 %. Numbers and thresholds are unchanged. Edits: VALIDATION.md §H H6 F07 row and M7.md (the peak reference is now the 0.75-m value).
3. **M7-C2 (PC-101 `deprop`): Kc 120 stays, Ti becomes 400 s through a new `condenser.pcTi`** (default 120 s; only `deprop` changes). Edits: PHYSICS.md §10.7 (table row and the new paragraph "`deprop` PC-101 Ti 400 s"), ENGINE_API.md §4, VALIDATION.md VC-16.6d.
   - **Measured process.** Open loop (`ideal`, MAN, CW OP ± 2 % at the 49.7 % point), P_top moves at 2.05 Pa/s per % OP (k′ = 5.95 × 10⁻⁵ % span/s per % OP) for ≈ 20 min. It peaks at −2.53 kPa per % OP at 24 min (0.073 % span per % OP), then recovers to ≈ −0.45 kPa per % OP by 53 min. Over the loop's time scale this is an integrator.
   - **Why Ti, not Kc.** With the proportional term on the PV, ζ = ½ √(Kc k′ Ti): 0.46 at Kc 120 / Ti 120. Lowering Kc lowers ζ: Kc 40 cycled the CW valve over its full range in full hydraulics, and the sieve column diverged. So the ±50 % Kc retune cannot work. New rule: Kc k′ Ti ≥ 2.8 (ζ ≥ 0.84).
   - **Grid** (`ideal`, noise off, VC-16.6d metric; full = the valve column from cold):

     | Kc / Ti | ±10 kPa: ±2 kPa / ±1 kPa | Overshoot, decay | Noise on: OP σ, P σ | Full hydraulics |
     |---|---|---|---|---|
     | 120 / 120 (now) | — / 1720 s, −10 not in 30 min | 28.5 % 0.65; 44.8 % 0.85 | 6.5 %, 0.82 kPa | cycles, no steady |
     | 120 / 300 | 460 / 1520 s | 9.2 %, 0.56 | | steady 65 100 s |
     | **120 / 400** | **565 / 1590 s; 545 / 1705 s** | **0, 0** | **5.6 %, 0.69 kPa** | **steady 37 200 s** |
     | 150 / 360 | 510 / 1450 s | 1.8 %, 0 | | steady 29 100 s |
     | 90 / 400 | 590 / 1760 s; −10: 1665 s / not in 30 min | 3.8–5.9 %, 0 | | steady 72 060 s |
     | 250 / 300 | ±1 kPa in 520–530 s | ≤ 2.7 %, 0 | 35 %, 11.8 kPa (valve saturates) | valve steady; sieve diverged |
     | 300 / 300 | ±1 kPa in 530–535 s | 0.5–1.8 %, decay 0.53 on a 0.5 % overshoot | | diverged |

   - **Why 120 / 400.** It is the best damped, keeps today's noise behaviour, and converges every full-hydraulics run (sieve and valve). Its +50 kPa step overshoots 1.4 % with CW 22–63 % (Ti 120: 37 %, CW 11–100 %), and it is quiet over 6 h.
   - **The ±1 kPa-in-10-min band is not reachable** by any usable tuning. The slow process mode sets the tail, and 1 kPa is 0.03 % of the 0–34.5 bar PT-101 span, below its 1.6-kPa noise. VC-16.6d (b) for `deprop` is now ±2 kPa within 10 min, with the ±1 kPa time recorded; (d) records k′ (± 20 %) and checks Kc k′ Ti ≥ 2.8; new (e) is VC-9.6 (b) converging. `debut` (Kc 30 / Ti 120) passes and is unchanged.
4. **M8 coder deviations: all ratified.**
   - **Holdup-factor lag (checkpoint item 1): ratified at τ_f = 10 s; the validator's optional 5 s is not taken.** The monotone bound τ_f ≥ dt (1 + gain), at gain ≈ 3.3 (φ_p 1.13), is 2.2 s at the 0.5-s step but 8.6 s at the 2-s fast-forward step that `runToSteadyState` and the 300× scenarios use. 5 s would bring back the period-2 alternation there. Edit: PHYSICS.md §6.3, new paragraph "Lag on the holdup factor of (6.4)".
   - **φ_p, G′_fl and E_mal every step (item 2): ratified (M8-S1).** Edits: §6.3 and §6.6 now say "every step".
   - **Dry-segment factor (item 3): ratified (M8-S1).** h_L/0.005 is a volume fraction (0.5 % holdup), not the tray's 5 mm. Edit: §6.1.
   - **Carry-over details (item 4): ratified and written into §6.3.** The details are factor 2.2, into the segment above or the drum, cap 0.3 M/dt, φ_p capped at 2 in (6.3). The PDT start at the true ΔP (item 8) is ratified too.
   - **G15 (item 5): ratified.** o1 uses `pressureDelta`; o2 is `lever.internals` == 1 ∧ `kpi.xD` ≥ 0.993 ∧ `kpi.columnDp` ≤ 1500 Pa, hold 300 s; the hint says to wait until x_D has settled (about 50 minutes). M8-S2: o5 now reads "from 0.978 to about 0.994". Edits: ENGINE_API.md §11.8 G15 row, M8.md and VALIDATION.md VC-13.6 (o2 at 3150–3180 s).
   - Items 6, 7, 9 and 10: noted, no spec change.

**Coder actions**
- `deprop` preset: `"type": "valve"` in both tray sections, geometry unchanged.
- Add `condenser.pcTi` (JSON `pcTi`, default 120 s; `deprop` 400) as PC-101's Ti on PV-101. PV-102 keeps 30 s.
- Sandbox: load `deprop` with Full hydraulics, as for `debut`. This reverts "M7 close-out (coder)" item 5 and "M8 app" item 6; update `m7_ui_test`.
- `m7_hydraulics_test`, `deprop`: steady reached; report jet flood and Φ_min per section and ΔP (reference in VC-9.6).
- Re-run the `deprop` `ideal` tests. VC-9.6 (a) is unchanged, since valve decks do not act in `ideal`.
- G15 o5 text "to about 0.994". `PackedModel.tauFactor` stays 10 s.

**Validator actions**
- VC-9.6 (b) `deprop` on valve decks: un-skip the weeping check and use the active-at-end alarm rule. Reference: steady ≈ 37 000 s; jet 58.6–66.3 / 45.1–64.2 %; Φ_min 1.173 / 0.916; ΔP 10.52 kPa.
- VC-16.6d `deprop` at Kc 120 / Ti 400 s: (a)–(e) as amended; un-skip the M7-C2 test.
  - (b): ±2 kPa within 600 s (reference 565 / 545 s); record the ±1 kPa time.
  - (d): k′ = 5.95 × 10⁻⁵ % span/s per % OP ± 20 %, and Kc k′ Ti ≥ 2.8.
- H6 F07: row text only, numbers unchanged.
- M8: no new check. The §6 text now matches the engine (τ_f 10 s, every-step refresh, h_L volume fraction).
