# LowSYS: completion summary (2026-10-13)

LowSYS is a Flutter distillation-column simulator with a pure-Dart engine (`packages/lowsys_engine`) and a Flutter app (`app/`). All milestones M1 to M10 in SCOPE.md are coded, validated and merged to `main` (head 9867011 at the time of writing).

## What was built
- **M1–M3:** the Tier-1 dynamic column with McCabe-Thiele, tray hydraulics, faults F01–F07, F19/F20/F28, PID loops, instruments and noise, alarms, scenarios G1–G6 and save/load.
- **M4–M9:** Tier-2 energy and faults, depropaniser and multi-column work, packing, and the crude unit (Brass theme, crude flowsheet, Products tab with TBP/D86 and gap checks, G16/H8).
- **M10:**
  - The engine runs in a background isolate (on web it runs on the UI isolate with a 3 ms budget).
  - OFL fonts are bundled, and the app has a Library of 15 cards and a 5-step tutorial.
  - Accessibility: semantics labels and 130 % text scale, with painter text following the text scale (clamped to 1.0–1.3).
  - Ok colours are safe for colour-blind users, and Brass chart contrast meets 3:1.
  - Text is localised in `app/lib/l10n/strings.dart`.

## Verification
- **Engine suite on Windows:** 843 pass, 2 skip, a count reconciled from the last full run (841 pass / 3 skip) plus the validator's final edits.
- **Engine suite under Chrome:** every test passes when suites run one at a time (`dart test -p chrome -j 1`, about 45 min). Running two at once makes some suites time out while loading.
- **App suite:** 84 pass, including the M10 contrast and accessibility validation tests and the golden tests for the crude flowsheet.
- **Independent validation:** Opus at xhigh validated each milestone. The final pass found no engine defects:
  - The crude F24 and no-steam energy imbalance is about 3e-10, against a 1e-3 tolerance.
  - The vapour-free stages sit exactly at the stage-26 temperature.
  - Clamp counts have explicit upper limits.
- **Platforms:**
  - Windows build: works.
  - Web build: succeeds.
  - Android: the debug APK installs and runs on AVD `lowsys_pixel` with no exceptions (`docs/screenshots/m10/android_pixel_smoke.png`).

## Known gaps
- **iOS:** not built or tested, because the host is Windows and iOS needs a Mac. The user's Mac, Vishnu, can be used; the steps are in STATUS.md, "iOS build on Vishnu".
- **Frame time:** the target is under 1 % of frames over 32 ms. On this machine that target is met only in the best runs. Averages are 4.5 % at 100x and 6.6 % at 1x (idle, 25 s runs, six each). 100x is not worse than 1x, so the floor is this machine's raster cost, not the simulation. Re-check on target hardware in profile/release mode.
- **Android release:** no release APK or full Android validation run has been done, only a debug smoke run.
- **SCOPE §7.1:** it still describes parchment McCabe-Thiele charts. Brass now uses lightened lines on the dark plot instead (DEVIATIONS "M10 coder pass 3").
- **Remaining inline text:** a few captions that are mostly interpolation or symbols, and text that comes from the engine, are still inline (DEVIATIONS "M10 coder pass 2").
- **Unchecked constants:** the packing constants (M8), vapour heat capacities and Daubert constants (M9) were quoted from memory. Check them against the reference books (OPEN_ITEMS.md).

## Where to look
- `docs/STATUS.md`: state and toolchain.
- `docs/DEVIATIONS.md`: every ruling and deviation, by milestone.
- `docs/VALIDATION.md` and `packages/lowsys_engine/test/validation/`: the validation suite.
