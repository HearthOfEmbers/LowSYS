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
- **M7 is implementation-ready (2026-10-13): work from `docs/milestones/M7.md`.** Two changes reach earlier milestones (both are clear errors or additive; no M4–M6 number changes):
  - **DePriester range (PHYSICS.md §3.4.2, M5 code).** Validity is 365–852 °R, not 700 °R. Outside it, evaluate the formula unclamped and only flag `thermoOutOfRange`. A clamped T makes K independent of T, and the bubble-point Newton then has g' = 0 (the prototype's depropanizer bottoms ran away to 514 °C). The engine at e1d4ae4 has no DePriester code yet, so implement it this way from the start. `c4` is unaffected.
  - **Additive.** Theme tokens `seriesDash1…6` (existing themes: solid); KPIs `xDHeavy` / `xBLight` (binary: 1 − xD and xB); diagnosis vocabulary `pump` / `refluxPump`.

## For validator

- **M6: H9.0/H10.0 in Tier 2** with the process-driven typical σ: four tags judged on 0.33–3; calibration check median 0.7–1.4 over seeds 1–3 (VALIDATION.md H9.0). Not run in the 2026-10-13 pass: engine e1d4ae4 has no σ_proc yet.
- **M6: re-derive VC-14.1 independently.** The table comes from the physics lead's loop prototype (`tools/prototypes/m6/ts.dart`), so it is a regression map of PHYSICS.md §8.3, not an independent reference. Spot-check about five rows with your own implementation from the equations: the 75 %, 50 %, 15 % / 100 %, 15 % / 16 % and K_out = 20 rows. Report any row outside the tolerances here, together with the term you suspect.
- **M6: column-coupled thermosyphon numbers are loop-only estimates.** The numbers in VC-14.2, VC-14.3 and the H5 rows (in [ ]) freeze the VC-14.1 inputs. The engine's sump T and P shift I_s by up to ≈ ±0.05, and the ranges allow for that. Record the engine's I_s at 50 % and 15 % level and the G14 times. Report here if I_s at 15 % is below 1.10 (the surge would be too weak for G14) or above 0.90 at 50 %.
- **M7: the [I] numbers come from one prototype.** VC-9.3 and VC-9.5–9.8 and the H6 [ ] values come from `tools/prototypes/m7/` (an independent steady-state solver; it reproduces VC-4.1's 0.981183 and VC-9.1/9.2 exactly). Re-derive about four of them with your own code: the VC-9.3 recoveries, the VC-9.5 dew points, and `debut` T_B and Q_R in VC-9.6. Record the engine's G13 settling time (the 86 400-s limit is an estimate) and the H6 timings.
- **M7: PC-101 on the high-pressure presets.** Estimated loop gain against B-T: about 0.6× (`debut`) and 1.0× (`deprop`). The larger PT-101 span (E48) offsets the smaller dT_sat/dP. Record the response to a ±2 % SP step on each. Report here if it oscillates or takes more than 15 min to settle.

## For the physics lead

- **M4 close-out (validator, engine 1155f40; DEVIATIONS.md "M4 validation").**
  1. **(7.4) leaves out the entrained tray-1 liquid.** In full hydraulics, e_1 enters the drum at h_1 ((7.6) counts its mass), but (7.4) treats it as if it arrived at h_0. As a result VC-5.4 fails: 6.8e-6 at the B-T design point and 1.9e-5 at +20 % load. *Proposal:* N_cond = [V_1 (H_V − H_1) + Q_C − e_1 (h_1 − h_0)] / (H_V − h_0). With that term the residual is 1.8e-11.
  2. **The partial condenser's `cwOP` default of 70 % (§7.2) predates the 50 % design.** B-T condenses all of V_1 at CW ≥ ≈ 48.5 %, so at 70 % PV-102 shuts, D_V = 0 and P floats to 94.5 kPa. *Proposal:* a per-preset default below the total-condensation OP. For B-T, 30 % gives D_V 12.6 kmol/h.
  3. **Vapour product in the balances.** `Kpis.balanceResidual` (ENGINE_API.md: |F z − D x_D − B x_B| / F z) is 0.25 at a partial-condenser steady state. The Energy card (SCOPE.md §M4: "Q_C + D h_D + B h_B out") has no D_V h_V either. *Proposal:* add D_V y_V and D_V h_V,0. `Kpis.energyResidual` already includes D_V h_V,0; the snapshot side is Coder item E50-a.
  4. **VC-16.6b tuning.** The engine runs PC-101 → PV-102 at Kc 2.0 / Ti 30 s (spec: 1.0 / 30, [impl-tunable]), and it meets the criteria. Ratify it in the §10.7 table.
  5. **G11 tier.** SCOPE.md says "G11 upgraded to Tier 2" in M4, but ENGINE_API.md §11.8 and the milestone table ship it in Tier 1. Owner decision.

- **M7 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. The sandbox presets use E = 0.7 tray counts: `debut` 32 / 16, `deprop` 28 / 11, from FUG N / 0.7 and a Tier-3 feed-tray scan. The v1.0 counts (22 / 12, 20 / 8) were the E = 1 designs and gave 0.943 / 0.942 recoveries at E = 0.7. VC-9.3 keeps 22 / 12 at E = 1.
  2. Default tier 3 for `debut` and `deprop`, with UA_clean, UA_R,clean and the table duty from the Tier-3 steady state. `c4` stays Tier 2.
  3. Multicomponent analysers read key cuts: AT-100 is the feed light cut, AT-101 the HK+ in D, AT-102 the LK− in B. These reduce to the binary definitions.
  4. VC-19 uses 40 trays × 7 components. The database has no eighth light hydrocarbon. *Alternative:* add n-octane (§2.1 data plus a McWilliams row). Not recommended before M9, which brings pseudo-components anyway.
  5. H6: ideal hydraulics, plantCalc view and an H10-style planning event (+8 % on F, L₀ and Q_R at 45 min), which is what makes the stuck-valve candidate visible. F07's dz takes light material out of the feed (more nC4/iC5), as SCOPE.md asked. v1.0's VALIDATION row (+nC4, −iC5) made the feed lighter, and its F12 s = 0.5 had no effect with F_max = 2 × default.
- **Open: `debut`/`deprop` column diameter for full hydraulics.** With the B-T geometry (D_c 1.2 m) these presets run at ≈ 20–25 % and ≈ 10–15 % of jet flood (capacity-factor scaling against B-T's 63 %), so full hydraulics would weep. *Recommendation:* D_c ≈ 0.75 m (`debut`) and ≈ 0.55 m (`deprop`), confirmed at ≈ 60 % flood with one engine steady run each before any full-hydraulics content uses these presets. Until then the defaults stay `ideal` and nothing in M7 depends on this. Owner decision.
- **DePriester upper limit source.** 852 °R (200 °C) is the range Seader, Henley and Roper state for the McWilliams fit, quoted from memory; v1.0's 365 °R and 870 psia match the same statement. Confirm against the book if it is at hand. The no-clamp policy stands either way.
- **VC-28.1 x_B.** The [P] value is 0.012590 / T_B 96.496 °C. A re-run of the independent Newton MESH solve during the M5 pass gave 0.012564 / 96.502 °C, which is inside the 2×10⁻⁴ tolerance. The likely cause is a difference in feed temperature or ΔP handling between the two prototypes. Reconcile it once the engine's number exists.
- **Prototype provenance.** The M5 [I] numbers (VC-10.9, VC-28.3 Tier 3, VC-28.7, §11.8 G9/G10) come from a binary MESH Newton solver with a numerical Jacobian, with P held and the same ideal enthalpies as Tier 2. It is not in the repo. If it should be kept for re-derivation, add it under `tools/` (owner decision, not the coder's).

- **M6 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. The exact x_e solve replaces v1.0's 3 fixed-point iterations, which diverged at W_h < 8 kg/s.
  2. The oscillator floor acts only while σ > 0, so a stable thermosyphon column can reach steady state.
  3. FT-103 measures the steam-side duty Q, not Q (1 + u), and the thermosyphon sub-steps run inside the control fast layer (§8.3.4). *If the validator sees FC-103 hunting at the oscillation period, report it.*
  4. "Plant view with engineering calculations" (view 2) for H1, H3 and H5, so that instrument and feed candidates are not given away by model-view truth. *Fallback if the coder finds it costly:* model view with the drill masking of fault parameters (as for H2 and H4), accepting that FT-102 bias (H3), LT-102 drift (H5) and the lighter feed (H1) can then be read off the drawn streams and level. Record the fallback in DEVIATIONS.md.
  5. H5 `lt102_drift` is exempt from rule 1 (ENGINE_API.md §11.5). If its noise-on rows in VALIDATION.md §H fail, set its weight to 0 and record it, as for H9/H10.
- **Low priority, M3 table cell.** PHYSICS.md §14.6, "Which checks fail" row "LT-101 or LT-102 drift": C1 is listed as "fail (∝ W)". r1 is a rate, so it does not grow with the window: 10 %/h on LT-102 is ≈ 1.15 band (`check`) at every window. Only C5 grows with W. The M6 row added below that table states this correctly. Fix the old cell when the table is next touched; no test depends on it.

## Resolved 2026-10-13

- **H2 F11 wording:** VALIDATION.md §H now reads "CW valve rises while P_top stays ≤ 5 kPa above SP" (the VC-8.1 Tier-2 transient bound; engine +0.1 → +2.1 kPa). Copied into the M4 and M6 excerpts.
- **M6 prototype provenance:** copied to `tools/prototypes/m6/` (tracked, with a README). VALIDATION.md and the M6 excerpt point there.
- **VC-9.5 (M7 pass):** the distillate dew points were 0.14 K and 0.31 K off and are corrected (55.25 / 49.52 °C); VC-9.4's n-hexane value now sits inside the corrected DePriester range.

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
