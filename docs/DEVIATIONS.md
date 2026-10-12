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

## M2 engine
- E19: `Presets.byId('bt')` stays ideal hydraulics (the M1 validation suite and VC-4 use it). The full-hydraulics default of SCOPE.md 4.2 is applied by the app (sandbox loads `copyWith(hydraulics: full)`) and by `setLever('hydraulics', 1)` / `setHydraulicsMode`.
- E20: A broken tray holds no liquid head: the hydrostatic term of (5.5) is multiplied by (1 - s_broken). Without it a fully broken tray still showed 18.7 % of its normal pressure drop (VC-12.4 expects about 6 %, prototype 664 to 38 Pa).
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
