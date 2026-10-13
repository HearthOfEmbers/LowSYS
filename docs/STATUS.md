# LowSYS status and coordinator handoff

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

## Next steps
1. Read `DEVIATIONS.md` → "M3 handoff" and `git log -5`. **If there is no "M3 handoff" section yet,** the previous coder is still finishing. Delete `docs/.coordinator_started`, re-enable the `lowsys-coordinator` scheduled task if you disabled it, tell the user in one line, and stop. You'll retry next hour.
2. In parallel:
   - **Opus `high`:** apply `docs/OPEN_ITEMS.md` to the spec docs, then empty the file.
   - **Sonnet:** create `docs/milestones/M4.md`, a self-contained excerpt of only the M4 parts of SCOPE, PHYSICS, ENGINE_API and VALIDATION.
3. **Fresh Sonnet coder:** finish any M3 handoff items (perf first), then build M4 from `docs/milestones/M4.md`, adopting the API names in `fixtures_m4.dart` where reasonable. Push a checkpoint once the Tier-2 engine is in.
4. **Fresh Opus `xhigh` validator:** run the M4 suite against that checkpoint and adjudicate failures (test wrong, engine wrong or spec wrong). Fix only the tests. Spec issues go into OPEN_ITEMS.md; engine bugs go to the coder.
5. Report briefly to the user at each milestone. The user is learning distillation and wants autonomous progress, so ask them only for genuine decisions.
