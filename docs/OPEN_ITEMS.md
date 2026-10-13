# Open spec items (for the physics lead)

Collected by the lead from validation passes. Fix in the docs, then delete the item.

## For coder

- **M4 doc fix, no requirement change (2026-10-12).** PHYSICS.md §13.5: the "Why the top vapour" paragraph had been inserted inside the switch table, which left the T2 ↔ T3 row orphaned below it. The rows are now together and the paragraph follows the table. The T1 ↔ T2 rules are unchanged.
- **E47 ratified, two details (PHYSICS.md §10.7 "PC-101 gain schedule").** (a) Schedule on PC-101's own OP from its previous execution, not on `pv101.position` (`control_system.dart` uses the position now). (b) With a partial condenser PC-101 drives PV-102, and that loop is not scheduled (kcScale 1). Record both in DEVIATIONS.md against E47.
- **E48 ratified as a function of the SP alone (PHYSICS.md §10.7 "PT-101 range").** Re-derive the PT-101 span from the PC-101 SP on *every* SP change: the `pTop` lever, `control.setSp('PC-101', …)` (which does not re-range today) and scenario events. On restore, re-derive it from the saved SP without perturbing the noise or PC-101 state. That is the spec side of V2: one SP must always give one span and bit-identical continuation. PT-101 HI/LO at 1.15 / 0.85 × SP is unchanged.
- **`model.dutyLimited` redefined (PHYSICS.md §8.2, §10.8):** Q_max,0 g(p) > Q_max for 60 s, i.e. without the supply disturbance (1 + d), so that it does not flicker at a fully open valve with noise on. It flags exchanger degradation (F13, F14) only. F15 shows as `FC-103.OPSAT`, which is already implemented.
- **M6 is implementation-ready (2026-10-13): work from `docs/milestones/M6.md`.** It includes the process-driven typical σ (PHYSICS.md §10.5), now with the window and units stated. No M4 or M5 requirement changed.
- **M7 is implementation-ready (2026-10-13): work from `docs/milestones/M7.md`.** Two changes reach earlier milestones (both are clear errors or additive; no M4–M6 number changes):
  - **DePriester range (PHYSICS.md §3.4.2, M5 code).** Validity is 365–852 °R, not 700 °R. Outside it, evaluate the formula unclamped and only flag `thermoOutOfRange`. A clamped T makes K independent of T, and the bubble-point Newton then has g' = 0 (the prototype's depropanizer bottoms ran away to 514 °C). The engine at e1d4ae4 has no DePriester code yet, so implement it this way from the start. `c4` is unaffected.
  - **Additive.** Theme tokens `seriesDash1…6` (existing themes: solid); KPIs `xDHeavy` / `xBLight` (binary: 1 − xD and xB); diagnosis vocabulary `pump` / `refluxPump`.
- **M8 is implementation-ready (2026-10-13): work from `docs/milestones/M8.md`.** Packed sections exist only from M8, so nothing reaches earlier milestones except these additive items:
  - lever `internals` and `ColumnConfig.internalsTemplates` on `bt` (empty for every other preset);
  - the scenario schema accepts `"fault": null` candidates, the categories `packingDamage` and `flooding`, and the locations `bed:*`;
  - `StageArrays.packHoldup` / `wetFrac` and `SimSnapshot.beds`.

  There is no packing code in the engine yet (checked at this pass), so v1.0's struct250 HETP_ref of 0.45 never reached the code.

- **M4 close-out spec decisions (2026-10-13), engine 1155f40.**
  - **(7.4) entrainment term (PHYSICS.md §7.2).** N_cond = [V_1 (H_V − H_1) + Q_C − e_1 (h_1 − h_0)] / (H_V − h_0), also inside the §7.4 pressure solve. No change in ideal hydraulics.
  - **Partial condenser CW default (PHYSICS.md §7.2, ENGINE_API.md §4).** New preset field `condenser.cwOpPartial` (default and B-T 30 %); `cwOP` takes it whenever a partial condenser is built (preset load or the `condenserType` switch). Below the total-condensation OP is the rule; 70 % is gone.
  - **Balances with D_V.** `Kpis.balanceResidual` = |F z − D x_D − D_V y_V − B x_B| / F z (y_V: overhead-inventory composition, light component). The Energy card's column balance shows D_V H_V,0 as an out term (this is E50-a).
  - **Cross-checks with a partial condenser (PHYSICS.md §14.6 common rules).** C1, C2 and C3b show `n/a` ("vapour product not metered"); C3a and C5 (drum) stay; C4 PV-101/FT-201 runs on the CW valve (it is skipped now); no C4 row for PV-102. Replaces the "flags D_V as unaccounted" behaviour.
  - **PC-101 → PV-102 Kc 2.0 / Ti 30 s** is now the spec value (§10.7); record it against E50 in DEVIATIONS.md.
  - **T1 → T2 switch:** PC-101's initial OP is the 50 % design value (§13.5 said 70 %). Check what the engine does.
  - **G11 stays Tier 1** (SCOPE.md and M4.md now agree with ENGINE_API.md §11.8). Nothing to change in code.
- **M5 rulings (2026-10-13, DEVIATIONS.md "M5 checkpoint").**
  - **T2 ↔ T3 pressure (PHYSICS.md §13.5).** Engine change: with a total condenser the switch sets PC-101's OP and the CW valve position so that Q_C is continuous (closed form from (7.3) in §13.5; `c4` ≈ 59 %), and sets T^(n−1) := T after the first new-tier bubble-point solve. VC-28.3's ±0.5 kPa stays. If the peak is still above 0.5 kPa after this, report the trend and the cause here; do not retune PC-101.
  - **G9 o3 (ENGINE_API.md §11.8).** Drop `steady` from o3 (now tier == 1 ∧ xD ≥ 0.95, hold 300) and use the new hint 2 text, which no longer says "run to steady state". Time limit unchanged.
- **M5 validation rulings (2026-10-13; see "Resolved 2026-10-13 (M5 validation)" below and DEVIATIONS.md "M5 validation").**
  - **G9 JSON (ENGINE_API.md §11.8).** Time limit 432 000 s, par 216 000. Hint 1 ends "Then fast-forward: at this small D the column takes about a day of simulated time to settle."; hint 3 ends "Fast-forward again: it takes about another day to settle." Objectives unchanged (o1 and o5 keep `steady`). In `m5_hint_players_test` bound the total at half the limit (216 000 s) instead of 2× the limit.
  - **q-line walk (PHYSICS.md §14.1; DEVIATIONS "M5 validation" coder item 5).** Walk towards the side where the curve lies at x = z (s = sign(y*(z) − z); reversed directions for s = −1), treat |q − 1| < 1e-6 as vertical, step in y where |slope| > 1 and end at the frame edge y = 0/1, and return (z, z) when |y*(z) − z| < 1e-9. The old "larger y for q ≤ 0" was also wrong for a normal curve; the new rule covers it.
  - **T-x-y cache (ENGINE_API.md §7.3, PHYSICS.md §14.4b).** Hysteresis: rebuild when |P − P_cached| > 100 Pa (or the tier changes), not on 100-Pa rounding buckets.
  - **§3.6.1 fallback bracket (latent; before M7).** T_hi = 900 K for Lee–Kesler and DePriester (0.98 · min T_c stays for Raoult/NRTL); check the sign change before bisecting, and without one keep the best Newton iterate, count the fallback and set `thermoOutOfRange`.
  - **C5 sump `n/a` with a partial condenser** is ratified (PHYSICS.md §14.6). Nothing to change.

## For validator

- **M6: H9.0/H10.0 in Tier 2** with the process-driven typical σ: four tags judged on 0.33–3; calibration check median 0.7–1.4 over seeds 1–3 (VALIDATION.md H9.0). Not run in the 2026-10-13 pass: engine e1d4ae4 has no σ_proc yet.
- **M6: re-derive VC-14.1 independently.** The table comes from the physics lead's loop prototype (`tools/prototypes/m6/ts.dart`), so it is a regression map of PHYSICS.md §8.3, not an independent reference. Spot-check about five rows with your own implementation from the equations: the 75 %, 50 %, 15 % / 100 %, 15 % / 16 % and K_out = 20 rows. Report any row outside the tolerances here, together with the term you suspect.
- **M6: column-coupled thermosyphon numbers are loop-only estimates.** The numbers in VC-14.2, VC-14.3 and the H5 rows (in [ ]) freeze the VC-14.1 inputs. The engine's sump T and P shift I_s by up to ≈ ±0.05, and the ranges allow for that. Record the engine's I_s at 50 % and 15 % level and the G14 times. Report here if I_s at 15 % is below 1.10 (the surge would be too weak for G14) or above 0.90 at 50 %.
- **M7: the [I] numbers come from one prototype.** VC-9.3 and VC-9.5–9.8 and the H6 [ ] values come from `tools/prototypes/m7/` (an independent steady-state solver; it reproduces VC-4.1's 0.981183 and VC-9.1/9.2 exactly). Re-derive about four of them with your own code: the VC-9.3 recoveries, the VC-9.5 dew points, and `debut` T_B and Q_R in VC-9.6. Record the engine's G13 settling time (the 86 400-s limit is an estimate) and the H6 timings.
- **M7: PC-101 on the high-pressure presets.** Estimated loop gain against B-T: about 0.6× (`debut`) and 1.0× (`deprop`). The larger PT-101 span (E48) offsets the smaller dT_sat/dP. Record the response to a ±2 % SP step on each. Report here if it oscillates or takes more than 15 min to settle.
- **M8: the [I] numbers come from one prototype.** VC-13.4–13.8 and the H7 [ ] values come from `tools/prototypes/m8/`. It is an independent steady-state solver with the packed hydraulics coupled by fixed-point iteration; it reproduces VC-4.1 and every v1.0 VC-13 number. Re-derive about four of them with your own code: the VC-13.2 G'_fl for struct250, the `bt_packed` Tier-1 x_D and bed ΔPs (VC-13.5), and one F21 row of VC-13.8. Record the dynamic quantities, which the prototype cannot give: the time for holdup and ΔP to settle after a load step near flood (VC-13.4); the G15 settling time after the `internals` switch; the H7 times from onset to the first evidence; the levels reached past flood with carry-over.
- **M8: what flooding with carry-over does.** VC-13.4 n = 6 and the H7 "crushed_lower + event" row run past φ_p = 1, where (6.3)'s carry-over (τ_c 5 s) moves liquid up the bed. The prototype has no carry-over, so these rows are bounds. Report here if the engine oscillates (holdup sloshing between segments), if PDT-103 exceeds its 10 kPa span in H7, or if the step needs more than 100 Newton iterations.
- **M5 validation re-checks (2026-10-13 spec).** Un-skip the two VC-28.8 clauses against their restated text: G9's hint path within half the new limit (216 000 s), and the low-CW path's new criteria (peak |P − SP| ≤ 12 kPa, back within ± 2 kPa within 10 min and staying there, no sustained oscillation, CW 6–15 %). VC-28.1: CW 49.9 %, R 40 on the reference only, the x_B note at 1206.8 kW. VC-9.5 hand-check digits. Once the coder lands them: VC-28.4 `ew` z 0.95 at the live q (1 ± ε), VC-28.5's cache hysteresis case (101 325 → 101 355 / 101 425 reuse, 101 426 rebuilds), and C5 sump `n/a` with a partial condenser.

## For the physics lead

- **M9 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. **Constants quoted from memory, not checked against the sources (no downloads):**
     - Fallon–Watson vapour Cp, c_p = (4 − SG)(t_°F + 670)/6450 (PHYSICS.md (9.2)). Checked against n-hexane: within 3 %.
     - The steam vapour Cp fit 30.2 + 0.0104 T.
     - The Daubert (1994) TBP → D86 constants. They reproduce v1.0's VC-15.2, so v1.0 used the same values.
     - The Riazi–Daubert, Lee–Kesler and Watson–Nelson forms of §9.1 are v1.0's. The prototype reproduces the v1.0 table exactly, but nobody re-read the papers.
  2. **Enthalpy reference.** The crude enthalpy reference is each component's saturated liquid at T_b, and the vapour enthalpy is anchored there (§9.1).
     - *Why:* the §3.3 path (Watson ΔH_vap) gives a vapour enthalpy that falls near T_c, and with the 298 K reference the (4.6) denominator went to −132 kJ/mol on crude stages.
     - *Alternative:* a rigorous ideal-gas Cp (Kesler–Lee) with the same reference: more constants, the same behaviour.
  3. **The ỹ_w filter** (τ_w 30 s, cap 0.98; §9.3) against the steam-stage loop gain (≈ 12 on stage 30). *Alternative:* solve T and V_HC together on steam stages. That is exact, but it is an extra scalar solve per stage, and it does not fit the bottom-up (4.6) sweep.
  4. **Draw levers are product rates**, and the stripper level sets the draw (§9.4). v1.0's FC on the draw made the product 82–85 % of the lever.
  5. **TBP tail trim of 1 %** for product D86 0/100 % (§9.6).
     - Without it, traces wreck the end points (diesel D86 0 % −154 °C).
     - 0.5 % would make the default D–K −24 K instead of −9 K.
     - *Alternative:* convert TBP 5/95 % directly with half-interval Daubert constants. Not standard.
  6. **Defaults.**
     - COT 345 °C (v1.0 360: overflash 10.9 %, against 1–6 %).
     - PA 5 MW (v1.0 6: D–K −25.5 K) on a range of 0–10 MW (v1.0 0–15: the kero tray dries above ≈ 7.5 MW).
     - Stripping section D 1.7 m (3.2 m gave 11–15 % flood).
     - PA circulation 120 m³/h with a 120 °C cooler limit.
     - Q_C,max 15 MW.
     - Steam at 200 °C.
     - Theoretical stages (E = 1).
  7. **Overhead simplified** (§9.7): ideal P_top and drum temperature, with Q_C,max only flagged. A PA trip in the field also raises the top pressure; LowSYS does not show that.
  8. **F26 is a high-reading furnace thermocouple** (TI-320 shows the SP), so that "re-target COT" is the remedy and H8 needs the flash-zone TI. **F25 is a circulation loss** with the duty following (9.3), so s ≤ 0.5 is invisible; H8's range is [0.7, 1.0].
  9. **G16's residue criterion** becomes TBP 5 % ≥ 355 °C. v1.0's "residue D86-equivalent IBP" is undefined, because residues have no D86 (§9.6).
  10. **Tags renumbered to the 300 series** (PHYSICS.md §10.7). v1.0's TC-201/FC-201… collided with TI-201/202, FT-201 and PT-201.
  11. **H8 lab results in plant views** (sample every 1800 s, published 900 s later; ENGINE_API.md §11.12). This is new: v1.0 did not say how D86 appears in a plant view.
- **Open (medium): engine dynamics of the crude column.** Every M9 number is a steady state, or a transient of the prototype's simplified dynamics: holdup weirs, no entrainment or weeping, implicit coupling of the side operations. The engine must record its own settling times (G16 par 7200 s is an estimate) and the H8 times from onset. It must also confirm that the explicit stripper and PA coupling of §9.4 is stable at dt = 0.5 s with the ỹ_w filter.
- **M8 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. **The packing table (PHYSICS.md §6.2) is quoted from memory** of Kister, *Distillation Design* (1992), ch. 8: a, ε and F_p for the five packings, σ_c, and ρ_bed (derived from steel 7900 and ceramic 2300 kg/m³ × (1 − ε)). None of it was checked against the book, and nothing was downloaded. The VC-13 numbers follow the table, so if the owner corrects a value, re-run `tools/prototypes/m8/vc13.dart` and `g15.dart`. *Still open (2026-10-13 rulings): no doc change can verify it; it needs the book. The values match the spec lead's own recollection of Kister's tables, which is not a check.*
  2. **struct250 HETP_ref 0.45 → 0.50 m**, by the doc's own rule (1200/a + 4 in = 0.502 m). *Alternative:* keep a vendor-typical 0.40–0.45 m, which gives 10–11 segments per 4.5 m bed; `bt_packed` and every VC-13.5–13.8 number would then change.
  3. **Robbins and Kister–Gill for structured packing.** Both were fitted mainly to random packings (Kister–Gill's title says "random packings"). From memory, Kister (1992) also applies the 0.115 F_p^0.7 flood ΔP to structured packings; not verified. Stated as a simplification in PHYSICS.md §16.
  4. **G15 in Tier 1**, not Tier 2. Its tray side is VC-12.3's Tier-1 [P] values, and the comparison is hydraulic. In Tier 2 every number would need a new engine run, and the B-T condenser has only 7.9 % of headroom. The lesson is honest and small: about 6 % more capacity in this shell, because trays at 0.9 m spacing are roomy and the lower bed carries L/V 1.33; the ΔP (10×) and the stages (18 against 14) are the wins. *Ruled 2026-10-13: accepted, no change.* The ≈ 6 % follows from the model (Robbins' liquid term on a random-packing basis, PHYSICS.md §16 row "Packing"), and G15's o4, its debrief and VC-13.6 already say so. The o4 distractor reads "always", so it stays wrong even where a real structured packing gains 20–30 %. If the packing table is corrected (item 1), re-run `g15.dart` and update the 6 % / 29 % figures.
  5. **H7 frame.**
     - 1.0 m beds, so that the default lower bed sits at 79 % of flood.
     - CW at 15 °C, so that the condenser can take +25 % (1599 of 1795 kW).
     - A common planning event that *is* the F22 candidate (a null-fault candidate and a rule-7 exception).
     - Severity ranges F21 [0.5, 0.8] (ramp 900 s) and F23 [0.3, 0.5] (step).
     - *Alternative for F22:* a candidate-specific event (planning only in that world). Rejected: a set-point change seen only in one world gives the answer away.
  6. **Model choices in §6.**
     - λ uses the equilibrium slope m, not K. v1.0 used K, which disagreed with §4.2 by a factor of 2–4 near the ends.
     - Wetting enters as max(1, a_w,ref/a_w), with a_w,ref at L'_des and the same properties.
     - Maldistribution uses n = n_th (fractional) and a geometric-mean S.
     - A dry-bed factor min(1, h_L/0.005) applies to E_MV.
     - Each of these is a definition where v1.0 was ambiguous or inconsistent.
- **Open (low): H7 time score for `near_flood`.** Its evidence starts at the planning event (2700 s), but the time score counts from the drawn t₀ (600–1800 s), as for every candidate. Starting its clock at 2700 s would reveal the answer through the score. *Recommendation:* accept it. The alternative is a fixed t₀ = 2700 s for all candidates' time scores in H7.

- **M7 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. The sandbox presets use E = 0.7 tray counts: `debut` 32 / 16, `deprop` 28 / 11, from FUG N / 0.7 and a Tier-3 feed-tray scan. The v1.0 counts (22 / 12, 20 / 8) were the E = 1 designs and gave 0.943 / 0.942 recoveries at E = 0.7. VC-9.3 keeps 22 / 12 at E = 1.
  2. Default tier 3 for `debut` and `deprop`, with UA_clean, UA_R,clean and the table duty from the Tier-3 steady state. `c4` stays Tier 2.
  3. Multicomponent analysers read key cuts: AT-100 is the feed light cut, AT-101 the HK+ in D, AT-102 the LK− in B. These reduce to the binary definitions.
  4. VC-19 uses 40 trays × 7 components. The database has no eighth light hydrocarbon. *Alternative:* add n-octane (§2.1 data plus a McWilliams row). Not recommended before M9, which brings pseudo-components anyway.
  5. H6: ideal hydraulics, plantCalc view and an H10-style planning event (+8 % on F, L₀ and Q_R at 45 min), which is what makes the stuck-valve candidate visible. F07's dz takes light material out of the feed (more nC4/iC5), as SCOPE.md asked. v1.0's VALIDATION row (+nC4, −iC5) made the feed lighter, and its F12 s = 0.5 had no effect with F_max = 2 × default.
- **Resolved 2026-10-13 (DEVIATIONS.md "Spec rulings M7"): D_c 0.75 m `debut`, 0.55 m `deprop` (stripping section 0.85 m from the M7 close-out; valve decks on both sections, M7-S4), PHYSICS.md §2.3; acceptance VC-9.6 geometry note.** Was: `debut`/`deprop` column diameter for full hydraulics. With the B-T geometry (D_c 1.2 m) these presets run at ≈ 20–25 % and ≈ 10–15 % of jet flood (capacity-factor scaling against B-T's 63 %), so full hydraulics would weep. *Recommendation:* D_c ≈ 0.75 m (`debut`) and ≈ 0.55 m (`deprop`), confirmed at ≈ 60 % flood with one engine steady run each before any full-hydraulics content uses these presets. Until then the defaults stay `ideal` and nothing in M7 depends on this. Owner decision.

- **M6 decisions taken in the readiness pass (settled; listed so that the owner can overrule them).**
  1. The exact x_e solve replaces v1.0's 3 fixed-point iterations, which diverged at W_h < 8 kg/s.
  2. The oscillator floor acts only while σ > 0, so a stable thermosyphon column can reach steady state.
  3. FT-103 measures the steam-side duty Q, not Q (1 + u), and the thermosyphon sub-steps run inside the control fast layer (§8.3.4). *If the validator sees FC-103 hunting at the oscillation period, report it.*
  4. "Plant view with engineering calculations" (view 2) for H1, H3 and H5, so that instrument and feed candidates are not given away by model-view truth. *Fallback if the coder finds it costly:* model view with the drill masking of fault parameters (as for H2 and H4), accepting that FT-102 bias (H3), LT-102 drift (H5) and the lighter feed (H1) can then be read off the drawn streams and level. Record the fallback in DEVIATIONS.md.
  5. H5 `lt102_drift` is exempt from rule 1 (ENGINE_API.md §11.5). If its noise-on rows in VALIDATION.md §H fail, set its weight to 0 and record it, as for H9/H10.
- **Low priority, M3 table cell.** PHYSICS.md §14.6, "Which checks fail" row "LT-101 or LT-102 drift": C1 is listed as "fail (∝ W)". r1 is a rate, so it does not grow with the window: 10 %/h on LT-102 is ≈ 1.15 band (`check`) at every window. Only C5 grows with W. The M6 row added below that table states this correctly. Fix the old cell when the table is next touched; no test depends on it.

## Resolved 2026-10-13 (M5 validation, engine fb33c07)

- **G9 over its limit (55.8 h against 48 h):** physical. The 40-tray `ew` column at D ≈ 6 has a 5-h slow mode, and o1 and o5 must wait on `steady`: o1 shows the stall, and o5 without it could latch on Tier-1 leftovers (x_D ≥ 0.95 at the switch back) before the vacuum has done anything. Limit 432 000 s (half = 60 h > 55.8 h), par 216 000; hints 1 and 3 say to fast-forward.
- **VC-28.8 low-CW −8.0 kPa:** the dip is the 38 % duty step at a valve set for the old load, not the loop (no oscillation, back within ± 2 kPa at 261 s). Restated: peak ≤ 12 kPa, within ± 2 kPa within 10 min, no sustained oscillation, CW 6–15 %. Hints stay steps.
- **q-line walk (§14.1):** towards the side of the diagonal where y*(z) lies; |q − 1| < 1e-6 vertical; y-stepping and y-edge end for steep lines.
- **T-x-y cache:** hysteresis |P − P_cached| > 100 Pa (PHYSICS.md wording kept; ENGINE_API §7.3 and VC-28.5 restated).
- **VC-28.1 CW:** 45.5 → 49.9 % ((7.3) at Q_C 1190.0 kW; the 50 % design rule).
- **VC-8.10 / 28.1 R 40:** reference-only (L₀ 400 and Q_R ≈ 4450 kW exceed `ew`'s 2 × default levers).
- **C5 sump with a partial condenser:** `n/a`, ratified in §14.6 (V̂ = V_cw misses D_V).
- **§3.6.1 bracket:** 900 K for Lee–Kesler and DePriester, with a sign-change check.
- **VC-9.5 hand check:** K 1.05131 / 0.43875 / 0.30976, Σ y/K 1.00002.
- **Also closed from the validator's notes:** the DePriester 365–852 °R source (plausible: round chart edges, engine reproduces VC-9.4/9.5; no-clamp stands), VC-28.1 x_B (the table is at 1206.8 kW, D 9.997; the D 10.000 values are now noted in VC-28.1), and prototype provenance (the validator's `test/validation/reference/tier3_reference.dart` now re-derives the M5 [I] numbers, so the lost prototype need not be kept).

## Resolved 2026-10-13 (M4 close-out, validator at 1155f40; M5 engine notes)

- **(7.4) entrainment:** e_1 (h_1 − h_0) added to the condenser balance as proposed (PHYSICS.md §7.2, M4 excerpt). VC-5.4 closes to 1.8e-11 with it.
- **Partial condenser 70 % CW:** per-preset `condenser.cwOpPartial`, B-T 30 % (D_V ≈ a quarter of the design D); at or above ≈ 48.5 % P falling below SP with PV-102 shut is stated as correct behaviour.
- **balanceResidual 0.25 with a partial condenser:** the formula and the Energy card now include the vapour product. Cross-checks that need D_V are `n/a` (no meter).
- **VC-16.6b:** Kc 2.0 / Ti 30 s ratified with explicit criteria (settle ≤ 600 s, overshoot ≤ 30 %, decay ratio ≤ 0.3).
- **G11 tier:** stays Tier 1. In Tier 2 the B-T condenser cannot follow the load (×1.3 needs ≈ 1.67 MW, 1.39 MW at 100 % CW), so the scenario would teach a condenser limit and none of its [P] numbers would hold. SCOPE.md and M4.md corrected. Owner may overrule.
- **M5 `c4` T2 → T3 +5.7 kPa:** a model-switch artefact, not a process event. Fixed by a Q_C-continuous CW initialisation in §13.5; VC-28.3's ±0.5 kPa kept.
- **M5 G9 vs Tier-1 `ew` 83 h to steady:** o3 no longer requires `steady`; x_D ≥ 0.95 already proves the point. Hint 2 and the VALIDATION G9 checkpoint updated. Time limit unchanged.
- **Validator re-checks of these rulings (engine fb33c07): all pass.** VC-5.4 in full hydraulics (design and +20 % load); `cwOpPartial` 30 % from the preset and from the switch; `balanceResidual` with D_V; the partial-condenser checks; T1 → T2 PC-101 at 50 %; `c4` T2 → T3 (CW 49.96 → 59.05 %, peak |P − SP| 142 Pa); G9 o3 latching 0.41 h after the Tier-1 switch.

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
