# Open spec items (for the physics lead)

Collected by the lead from validation passes. Fix in the docs, then delete the item.

## For coder

- **M4 doc fix, no requirement change (2026-10-12).** PHYSICS.md §13.5: the "Why the top vapour" paragraph had been inserted inside the switch table, which left the T2 ↔ T3 row orphaned below it. The rows are now together and the paragraph follows the table. The T1 ↔ T2 rules are unchanged.
- **E47 ratified, two details (PHYSICS.md §10.7 "PC-101 gain schedule").** (a) Schedule on PC-101's own OP from its previous execution, not on `pv101.position` (`control_system.dart` uses the position now). (b) With a partial condenser PC-101 drives PV-102, and that loop is not scheduled (kcScale 1). Record both in DEVIATIONS.md against E47.
- **E48 ratified as a function of the SP alone (PHYSICS.md §10.7 "PT-101 range").** Re-derive the PT-101 span from the PC-101 SP on *every* SP change: the `pTop` lever, `control.setSp('PC-101', …)` (which does not re-range today) and scenario events. On restore, re-derive it from the saved SP without perturbing the noise or PC-101 state. That is the spec side of V2: one SP must always give one span and bit-identical continuation. PT-101 HI/LO at 1.15 / 0.85 × SP is unchanged.
- **`model.dutyLimited` redefined (PHYSICS.md §8.2, §10.8):** Q_max,0 g(p) > Q_max for 60 s, i.e. without the supply disturbance (1 + d), so that it does not flicker at a fully open valve with noise on. It flags exchanger degradation (F13, F14) only. F15 shows as `FC-103.OPSAT`, which is already implemented.
- **M6 is implementation-ready (2026-10-13): work from `docs/milestones/M6.md`.** It includes the process-driven typical σ (PHYSICS.md §10.5), now with the window and units stated. No M4 or M5 requirement changed.
- **M5: PC-101 at low CW flow (VALIDATION.md VC-28.8).** The E47 schedule is now the physics decision for this path (≈ 3× design loop gain at 9 % CW instead of ≈ 12×). If PC-101 still oscillates there, report it here with the trend. Do not retune Kc/Ti globally.
- **M5: G9/G10 time limits** (ENGINE_API.md §11.8: 172 800 s / 86 400 s) are estimates. The prototype holds P and does not give settling times, so VC-28.8 records the actual times to steady state. Raise an item here if a hint path takes longer than half the limit.

## For validator

- **M6: H9.0/H10.0 in Tier 2** with the process-driven typical σ: four tags judged on 0.33–3; calibration check median 0.7–1.4 over seeds 1–3 (VALIDATION.md H9.0). Not run in the 2026-10-13 pass: engine e1d4ae4 has no σ_proc yet.
- **M6: re-derive VC-14.1 independently.** The table comes from the physics lead's loop prototype (`.scratch/m6/ts.dart`, gitignored), so it is a regression map of PHYSICS.md §8.3, not an independent reference. Spot-check about five rows with your own implementation from the equations: the 75 %, 50 %, 15 % / 100 %, 15 % / 16 % and K_out = 20 rows. Report any row outside the tolerances here, together with the term you suspect.
- **M6: column-coupled thermosyphon numbers are loop-only estimates.** The numbers in VC-14.2, VC-14.3 and the H5 rows (in [ ]) freeze the VC-14.1 inputs. The engine's sump T and P shift I_s by up to ≈ ±0.05, and the ranges allow for that. Record the engine's I_s at 50 % and 15 % level and the G14 times. Report here if I_s at 15 % is below 1.10 (the surge would be too weak for G14) or above 0.90 at 50 %.

## For the physics lead

- **H2 wording, "CW valve rises with P_top at SP" (validator, engine e1d4ae4).** While the valve rises, P is not at SP: PC-101 follows the growing load with a PI ramp lag, and P climbs from +0.1 to +2.1 kPa above SP over the ≈ 17 min (valve 48 → 100 % at 1005 s), then rises to 139 kPa at 1 h. It is the VC-8.1 mechanism. The test judges it on the VC-8.1 Tier-2 transient bound (≤ 5 kPa). Suggest "CW valve rises while P_top stays within ≈ 2 kPa of SP" or the 5-kPa bound.
- **VC-28.1 x_B.** The [P] value is 0.012590 / T_B 96.496 °C. A re-run of the independent Newton MESH solve during the M5 pass gave 0.012564 / 96.502 °C, which is inside the 2×10⁻⁴ tolerance. The likely cause is a difference in feed temperature or ΔP handling between the two prototypes. Reconcile it once the engine's number exists.
- **Prototype provenance.** The M5 [I] numbers (VC-10.9, VC-28.3 Tier 3, VC-28.7, §11.8 G9/G10) come from a binary MESH Newton solver with a numerical Jacobian, with P held and the same ideal enthalpies as Tier 2. It is not in the repo. If it should be kept for re-derivation, add it under `tools/` (owner decision, not the coder's).

- **M6 thermosyphon prototype provenance.** `.scratch/m6/ts.dart` (with `vc14.dart`, `sweep.dart`, `h5.dart` and `g14c.dart`) produced every M6 number in PHYSICS.md §8.3 and §11 (F17/F18), VALIDATION.md VC-14 and §H (H5), and ENGINE_API.md §11.8 G14. `.scratch/` is gitignored and may be cleaned. *Recommendation:* the coordinator copies it to `tools/thermosyphon_proto/` (outside the physics lead's file set), like the M5 MESH solver item above.
- **M6 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. The exact x_e solve replaces v1.0's 3 fixed-point iterations, which diverged at W_h < 8 kg/s.
  2. The oscillator floor acts only while σ > 0, so a stable thermosyphon column can reach steady state.
  3. FT-103 measures the steam-side duty Q, not Q (1 + u), and the thermosyphon sub-steps run inside the control fast layer (§8.3.4). *If the validator sees FC-103 hunting at the oscillation period, report it.*
  4. "Plant view with engineering calculations" (view 2) for H1, H3 and H5, so that instrument and feed candidates are not given away by model-view truth. *Fallback if the coder finds it costly:* model view with the drill masking of fault parameters (as for H2 and H4), accepting that FT-102 bias (H3), LT-102 drift (H5) and the lighter feed (H1) can then be read off the drawn streams and level. Record the fallback in DEVIATIONS.md.
  5. H5 `lt102_drift` is exempt from rule 1 (ENGINE_API.md §11.5). If its noise-on rows in VALIDATION.md §H fail, set its weight to 0 and record it, as for H9/H10.
- **Low priority, M3 table cell.** PHYSICS.md §14.6, "Which checks fail" row "LT-101 or LT-102 drift": C1 is listed as "fail (∝ W)". r1 is a rate, so it does not grow with the window: 10 %/h on LT-102 is ≈ 1.15 band (`check`) at every window. Only C5 grows with W. The M6 row added below that table states this correctly. Fix the old cell when the table is next touched; no test depends on it.

## Resolved 2026-10-12 (M4 validation items, engine c4e1f17)

- **VC-16.6c:** start at the 50 % design OP; target 0.906 ± 0.005 bar(a), the bubble point that UA 29.9 kW/K gives. The 0.966 value belonged to the v1.0 70 % design.
- **VC-8.1 (T2) / VC-16.6:** "returns to SP ± 0.2 kPa at the new steady state; transient ≤ 5 kPa". The ≈ 2.5 kPa peak is set by the integral action needed for +36 % CW.
- **F11:** restated as a transient (PHYSICS.md §11, SCOPE.md F11, H2). The CW valve saturates at ≈ 17 min, then P rises. 1-h numbers at the risen P: 139 kPa, y_I 0.072, +4.3 K subcooling. H2 asks for ≥ 3 K.
- **F15 / dutyLimited:** the Q_max figures are stated at the E = 1 point, with the E = 0.7 offset and "onset" wording. `model.dutyLimited` now means a degraded exchanger. F15's symptom is `FC-103.OPSAT` (SCOPE.md F15, H4).
- **VC-27.3 note:** corrected. 0.5 bar(a) needs CW ≤ ≈ 10.7 °C and holds at 5 °C. G8 is unchanged.
- **VC-11 further references:** stated as perfect-condenser references, with the 50 %-CW inlet rule for the test.
- **H9.12:** 30 min after the event (supersedes spec decision #5's 20 min). The 20-min result is reported for information.
- **E47:** ratified with the physics derivation (dQ_C/dm_cw ∝ a/(m + a)²), on OP and for total condensers only.
- **E48:** ratified, with the span a function of the SP alone and Kc left in % of span.
- **Tier-2 signal looks:** a process-driven typical σ for PT-101, TI-100, FT-201 and TI-202, judged on a 0.33–3 band (M6).
