# LowSYS status and coordinator handoff

Status: COMPLETE

Last updated 2026-10-13 by the final coordinator. M1–M10 are done and validated; see `docs/reports/LowSYS-summary-2026-10-13.md` for the summary and known gaps. The `lowsys-coordinator` scheduled task could not be disabled from an unattended run (needs approval); see Needs user.

## What exists
- Specs: `SCOPE.md` (milestones M1–M10, levers, faults, scenarios, themes), `PHYSICS.md`, `ENGINE_API.md`, `VALIDATION.md`. The coder records deviations in `DEVIATIONS.md`. `OPEN_ITEMS.md` holds spec fixes still waiting for the physics lead.
- Code:
  - Pure-Dart engine in `packages/lowsys_engine`.
  - Flutter app in `app/`.
  - Validation suite in `packages/lowsys_engine/test/validation/`, with independent references in `reference/`.
- Done: M1 (Tier-1 dynamic column, McCabe-Thiele, Blueprint theme), M2 (tray hydraulics, F01–F07, math overlay, units, G11/G12) and M3 (PID loops, instruments/noise, F19/F20/F28, alarms, cross-checks C1–C5, scenarios G1–G6, H9/H10 definitions, save/load).
- Tests: the Tier-1 suites pass (292). The M4 suite (`fixtures_m4.dart`, `vc10_*`, `vc11_vc27_*`, `vc8_tier2_*`, `m4_energy_faults_test.dart`, `vc23_tier2_*`) is written and waits for the M4 engine. Its guessed API names are isolated in `fixtures_m4.dart`.
- The M4 spec is implementation-ready (commit fb00526). The M5 readiness pass was stopped part-way; see the note in SCOPE M5.
- Open from M3 (check DEVIATIONS "M3 handoff"): the frame-time regression at 100× with noise on (12 % of frames over 32 ms; target < 1 %), a few UI polish items, and no Android emulator run of M3.

## Toolchain
- Flutter is at `C:\dev\flutter`. The Android SDK is at `%LOCALAPPDATA%\Android\Sdk`, with AVD `lowsys_pixel`. In PowerShell, refresh PATH first:
  `$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')`.
- Smart App Control is off, the Windows build works and the APK builds. There is no Python on this machine, so scripts are written in Dart.
- Git commits use `git -c user.name=HearthOfEmbers -c user.email=mr.lolderp@gmail.com commit`. Every message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Stage by explicit path only and push to origin main.

## Working rules (the user asked for these to cut token use)
1. **Coding** goes to Sonnet. **Physics and spec** work goes to Opus: effort `high` for routine spec edits and fixes, `xhigh` only for new physics. **Validation** goes to Opus at effort `xhigh` (not Fable).
2. **Start a fresh agent per milestone or task.** Don't keep resuming long-lived agents. Briefs stay short and name only the doc sections needed.
3. **Validation checks key numbers only:** about 20–30 per milestone, plus physical-sense and directional checks. Don't recompute every table.
4. **Ready specs just in time,** only when the coder is about to start that milestone.
5. Running agents in parallel is fine (the user kept this).
6. **Docs per milestone:** agents read `docs/milestones/Mx.md` excerpts, not the whole PHYSICS.md. Create the excerpt before each milestone.
7. **Screenshots:** the coordinator reviews at most 1–2 per milestone, at reduced size.
8. The coordinator keeps its own context small. Update this file at each milestone boundary and hand off to a fresh coordinator when the conversation gets long.

## Relay protocol (the user is asleep or away; run autonomously until the scope is done)
- **Goal:** finish M4–M10 per SCOPE.md. iOS can't be built on Windows: skip it, note it, and do Android, Windows and web.
- **Who starts coordinators:** the scheduled task `lowsys-coordinator` fires every 30 minutes. It starts a new coordinator only when the repo has been quiet for 40 minutes, i.e. the previous coordinator died at a usage limit, or when `docs/.handoff_now` exists.
- **Heartbeat:** touch `docs/.coordinator_heartbeat` whenever you act. Agents keep scratch and prototype work under `<repo>/.scratch/` (gitignored), so their activity counts as liveness.
- **Handing off:** after about one milestone, or when your context is getting long:
  1. Update this file (state and next steps).
  2. Commit and push.
  3. Create `docs/.handoff_now`.
  4. Call the scheduled-tasks tool `run_scheduled_task` for `lowsys-coordinator`. If that tool is unavailable, the next 30-minute tick picks it up.
  5. Stop. Don't start new agents after writing the handoff file.
- **Parallel lanes.** Run lanes whenever their file sets don't overlap:
  - **A:** Sonnet coder on the current milestone (engine plus app), in the main tree.
  - **B:** a second Sonnet coder on disjoint work (themes, UI-only polish, web build), in `isolation: "worktree"`. Merge it to main when done.
  - **C:** Opus `high`/`xhigh` readying the *next* milestone's spec and excerpt (docs only).
  - **D:** Opus `xhigh` validating the previous checkpoint (`test/validation/` only).
- **How many lanes:** start with A + C + D, and add B when there is disjoint work. Cut back a lane if you see merge conflicts, duplicated effort, or rework above roughly 15 % of a lane's output. Never run two writers on the same files.
- **When a usage-limit error kills agents:** the coordinator dies too. The next tick after the reset resumes from this file, the git log and the DEVIATIONS handoff notes, starting fresh agents rather than resuming dead ones.
- **When everything is done:**
  1. Write a one-page summary in `docs/reports/`.
  2. Set the status line at the top of this file to "COMPLETE".
  3. Disable the `lowsys-coordinator` scheduled task.

## Next steps
State 2026-10-13 (handoff from the coordinator run of 2026-10-13):
- M6, M7, M8, M9 closed: engine + app coded, validated (Opus xhigh), spec rulings applied. Latest: eba6818. Engine suites 814 pass / 4 skip (validator run 1377203); app 60 tests pass.
- Key rulings this run (all in DEVIATIONS "Spec rulings ..." sections): FT-103 10-s lag; G14 o1 >= 1260 kW & FC-103 < 99 %; deprop valve trays 0.55/0.85 m, condenser.pcKc/pcTi (deprop Kc 120, Ti 400 s, VC-16.6d +-2 kPa); M8 deviations ratified; M9 F24 cap frozen at onset, G16 o1 without steady.
- M10 mostly done (5cc3d20, ae01f95): engine isolate (web on UI isolate, 3 ms budget), OFL fonts bundled, Library (15 cards), tutorial (5 steps), semantics labels, 130 % text scale, colour-blind-safe ok colours (Blueprint/Control Room/Paper changed; SCOPE 7.2 still lists old values), web build succeeds.

Next (run in parallel):
1. **Coder (Sonnet):** finish localisation (strings still inline: panel headings, alarm/fault panels, faceplates, drill/debrief dialogs, painter captions -> app/lib/l10n/strings.dart); Android APK build + emulator smoke run (AVD lowsys_pixel); run the engine suite under Chrome (`dart test -p chrome` or equivalent) if feasible; golden tests for the crude flowsheet. Remove or .gitignore the stray untracked `packages/lowsys_engine/tool/m9_*.dart` and `app/test/failures/`.
2. **Validator (Opus xhigh, worktree):** follow-ups from "Spec rulings M7-S4/M8" (deprop valve trays, VC-16.6d), "Spec rulings M9" (F25 rows, F24 SP-raise row, no-steam closure), M10 acceptance (VALIDATION.md §U contrast, accessibility) and a full-suite run on Windows (+ Chrome if coder enables it).
3. **Spec lead (Opus high):** coder notes in DEVIATIONS "Spec rulings M9 (coder)" (F24 s=1 energy closure 2.3e-3 vs 1e-3 from film-floor mass; negativeClamps ~1.4 M counting every step) and update SCOPE 7.2 theme colours to the new ok colours.
4. 100x frame-time: 21.8 % frames > 32 ms at 100x with isolate (1x idle is 22.4 %, i.e. machine raster floor on a busy machine). Re-measure on an idle machine; if still > 1 %, profile raster cost.
5. When the above is green: write the summary report in docs/reports/, set Status COMPLETE, disable `lowsys-coordinator`. iOS is skipped (Windows host) — note it in the report.

## Needs user
- Disable the `lowsys-coordinator` scheduled task (an unattended run can't; until then each tick just replies "LowSYS complete").
- Packing constants (M8) and vapour heat capacities / Daubert constants (M9) are quoted from memory; check against the reference books (see OPEN_ITEMS.md).
- iOS build/simulator validation needs a Mac. The user has a Mac (**Vishnu**) they can start up for this; see "iOS build on Vishnu" below.

## iOS build on Vishnu
The user can start up their Mac, Vishnu, for the iOS build. Run Claude Code there with a clone of this repo. Steps:
1. Clone `github.com/HearthOfEmbers/LowSYS` (private) and check out `main`.
2. Needs Xcode (with an iOS simulator runtime), CocoaPods and Flutter at the same version as `C:\dev\flutter` on the Windows box (`flutter --version` there). Installs on Vishnu need the user's OK.
3. In `app/`: `flutter pub get`, `cd ios && pod install`, then `flutter build ios --simulator` (no signing needed) and `flutter run` on an iPhone simulator.
4. Smoke check: the app launches, the sim runs, and there are no exceptions in the log. Save a screenshot to `docs/screenshots/m10/ios_sim_smoke.png`.
5. For a device or TestFlight build, signing needs the user's Apple developer team, so ask them.
6. Record results in DEVIATIONS ("iOS build (Vishnu)") and update the summary report's Known gaps. Commit and push following the git rules above.