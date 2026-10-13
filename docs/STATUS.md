# LowSYS status and coordinator handoff

Status: IN PROGRESS

Last updated 2026-10-12 by the outgoing coordinator.

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
State 2026-10-13 (handoff from the coordinator run that started 2026-10-12):
- M4 closed (engine validated, 452+ tests; app done incl. emulator pass). M5 closed (fb33c07, 601f80e): Tier 3, presets ew/ac/c4, T-x-y, G9/G10, Paper theme. Spec rulings: 4ee46dd, ce171db.
- M6 engine checkpoint in (601f80e): thermosyphon (VC-14.1 reproduces), F17/F18, plantCalc view, H1–H5, G14. M6 app first pass (23d7368): Equipment card, drill list, HUD, Diagnose dialog. 25 app tests pass.
- M7 spec ready (3062d2c, docs/milestones/M7.md, prototype in tools/prototypes/m7). Open: column diameters (~0.75/0.55 m recommended), 852 °R DePriester limit quoted from memory (validator found it plausible).
- Known failing: `vc18_mccabe_thiele_data_test.dart` compile error and the dt-30 s test in `m5_columns_validation_test.dart` (validator's folder).

Next (run in parallel):
1. **Validator (Opus xhigh):** fix the two failing tests above, un-skip the two VC-28.8 clauses (ce171db), then validate the M6 engine at 23d7368 against docs/milestones/M6.md's 29 reference values. Work in a clean worktree.
2. **Spec lead (Opus high):** rule on the coder's open M6 items in DEVIATIONS.md (low-CW dip 8 kPa at 90 s vs the ce171db criteria; PC-101 limit cycle at dt 30 on the doubled-condenser case; VC-14.2.2 FT-103 5-s bins 8.3 % p-p vs ≤ 2 %; G14 throttling alone meets o1 at 10 % inlet; `eq.raoult` rename).
3. **Coder (Sonnet):** finish the M6 app (loop schematic, HUD countdown, field-check buttons, sandbox plantCalc view toggle), apply the rulings, then start M7.
4. While M7 is coded, ready the M8 spec (Opus xhigh if new physics).