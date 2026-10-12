# LowSYS — Validation Cases

Status: specification v1.0 (2026-10-12). The testing agent turns every case below into automated tests (engine cases: `packages/lowsys_engine/test/`, `dart test`; app cases: `app/test/`). Each test is named after its case id, e.g. `VC-4.1 dynamic steady state matches Newton (default B-T)`.

## 0. How to read this document

- **Units.** Tables give engineering units for readability; tests convert to SI (mol/s, K, Pa, W). 1 kmol/h = 0.2777778 mol/s.
- **Tolerances.** Each case states its tolerance. "abs" = absolute, "rel" = relative. When a case says "± band", any value inside the band passes.
- **Where the reference numbers come from.**
  - **[T]** Textbook / literature value (source given).
  - **[I]** Computed by the physics lead with an *independent* method that does not share code with the simulator algorithm: closed-form formulas, bisection, or a full Newton solve of the steady-state equations with a numerical Jacobian. The method is described so the tester can re-derive the number.
  - **[P]** Produced by the physics lead's prototype of the exact algorithm in PHYSICS.md §12 (Node.js). These pin down model behaviour, not truth; tolerances are wider and a mismatch first triggers a check of whether the implementation follows PHYSICS.md.
- **Configurations.** "B-T default" = preset `bt` as in SCOPE.md §4 and PHYSICS.md §5.1: 20 sieve trays, feed tray 10, F = 100 kmol/h, z = 0.5, q = 1, L₀ = 100 kmol/h, V_B = 150 kmol/h, E_MV = 0.7, α = 2.5, dt = 0.5 s, LC-101/102 PI (Kc = 2, Ti = 1800 s, SP 50 %). "Ideal hydraulics" = `HydraulicsMode.ideal`. Stage counting: N trays + partial reboiler (an equilibrium stage); the total condenser is not a stage.
- **Engine test fixtures.** Tests must be able to (a) build a `Simulator` from a preset with overrides, (b) run until steady (`runToSteadyState`) or for a fixed sim time, (c) read every quantity of `SimSnapshot`, (d) read debug accessors for per-step flows used by the solver (needed for exact conservation accounting, VC-5). Expose (d) through a `@visibleForTesting` `StepDebug` object.

---

## VC-1 McCabe–Thiele textbook problem (q = 1) [I]

Classic benzene–toluene problem (e.g. McCabe, Smith and Harriott, *Unit Operations of Chemical Engineering*; Seader, Henley and Roper, *Separation Process Principles*, ch. 7): α = 2.5, z = 0.5, saturated-liquid feed (q = 1), x_D = 0.95, x_B = 0.05, R = 1.5 R_min. Tested against the engine's shortcut utilities (`McCabeThieleMath`, `FugCalculator`) and the McCabe–Thiele builder.

| Quantity | Value | Tolerance | Derivation |
|---|---|---|---|
| D/F | 0.5000 | 1×10⁻¹² | (z − x_B)/(x_D − x_B) |
| Pinch point (q-line ∩ equilibrium) | x* = 0.50000, y* = 0.71429 | 1×10⁻⁵ | y* = 2.5·0.5/(1 + 1.5·0.5) = 0.714286 |
| R_min | 1.1000 | 1×10⁻⁴ | R_min/(R_min+1) = (x_D − y*)/(x_D − x*) = 0.52381 |
| N_min (Fenske, stages incl. reboiler) | 6.4269 | 1×10⁻⁴ | ln[(0.95/0.05)(0.95/0.05)] / ln 2.5 |
| R = 1.5 R_min | 1.6500 | exact | |
| Gilliland X = (R − R_min)/(R + 1) | 0.20755 | 1×10⁻⁵ | |
| Molokanov Y | 0.45404 | 1×10⁻⁵ | Y = 1 − exp[(1 + 54.4X)/(11 + 117.2X) · (X − 1)/√X] |
| N (Gilliland–Molokanov) | 12.603 | 1×10⁻³ | N = (N_min + Y)/(1 − Y) |
| N (Eduljee form, for comparison only) | 12.319 | 1×10⁻³ | Y = 0.75(1 − X^0.5668) |
| Stage stepping from the top, optimal feed switch | 12 stages (11.675 fractional), feed on stage 6 | exact count; fractional 1×10⁻³ | L/V = 0.62264, L̄/V̄ = 1.37736 |

Stage-by-stage compositions (stepping from (x_D, x_D), switching to the stripping line when x drops below the operating-line intersection x = 0.5):

| Stage | x | y |
|---|---|---|
| 1 | 0.88372 | 0.95000 |
| 2 | 0.79931 | 0.90873 |
| 3 | 0.70424 | 0.85617 |
| 4 | 0.61093 | 0.79698 |
| 5 | 0.53093 | 0.73888 |
| 6 (feed) | 0.46991 | 0.68907 |
| 7 | 0.40345 | 0.62836 |
| 8 | 0.31676 | 0.53683 |
| 9 | 0.22276 | 0.41742 |
| 10 | 0.13924 | 0.28795 |
| 11 | 0.07717 | 0.17291 |
| 12 | 0.03691 | 0.08742 |

Tolerance 1×10⁻⁵ on every entry. Fractional stages: 11 + (x₁₁ − x_B)/(x₁₁ − x₁₂) = 11.675.

## VC-2 Feed condition variants [I]

Same problem, R = 1.5 R_min in each case.

| q | Pinch x*, y* | R_min | N (Molokanov) | Stepped stages (fractional) | Feed stage |
|---|---|---|---|---|---|
| 1.2 (subcooled) | 0.54112, 0.74671 | 0.9888 | 12.785 | 12 (11.798) | 6 |
| 1.0 | 0.50000, 0.71429 | 1.1000 | 12.603 | 12 (11.675) | 6 |
| 0.5 (half vapour) | 0.38743, 0.61257 | 1.4987 | 12.140 | 11 (10.946) | 6 |
| 0 (saturated vapour) | 0.28571, 0.50000 | 2.1000 | 11.736 | 10 (9.950) | 6 |

Tolerances: pinch 1×10⁻⁵, R_min 1×10⁻⁴, N 1×10⁻³. Check also: the q-line passes through (z, z) and has slope q/(q − 1) (vertical at q = 1); for q = 0.5 it is y = −x + 1.

## VC-3 Total reflux and Fenske

**VC-3.1 [I]** Fenske identity: with N_s equilibrium stages at total reflux, (x_D/(1−x_D)) = α^N_s (x_B/(1−x_B)). Symmetric case (x_B = 1 − x_D), α = 2.5: N_s = 6 → x_D = 0.939850; N_s = 10 → 0.989864; N_s = 20 → 0.999895 (tolerance 1×10⁻⁶).

**VC-3.2 [P][I] Dynamic total reflux.** B-T, Tier 1, ideal hydraulics, 5 trays + reboiler, E = 1, feed tray 3, F = 0, D and B valves closed (LC-101/102 in MAN at 0 %), L₀ = V_B = 150 kmol/h, start from z = 0.5 everywhere. Run 6 h. Expected: ln[(x_D/(1−x_D))/(x_B/(1−x_B))]/ln 2.5 = 6.0000 ± 0.001 (prototype: x_D = 0.916057, x_B = 0.042786, 6.00000). x_D and x_B themselves depend on holdups and are not tested.

## VC-4 Dynamic steady state equals the independent steady state (Tier 1) [I]

**Independent method.** Steady-state CMO equations of the column (total condenser, N Murphree trays, equilibrium reboiler) for fixed L₀, V_B, F, z, q: unknowns x_0 … x_{N+1}; y from the Murphree recursion y_{N+1} = y*(x_{N+1}), y_j = y_{j+1} + E (y*(x_j) − y_{j+1}); residuals = component balance of every stage; solved by Newton with a finite-difference Jacobian and line search to max |residual| < 1×10⁻¹¹ mol/s-equivalent. (Successive substitution with tridiagonal solves is *not* adequate: in testing it converged to a wrong root for some feed locations.)

**Test.** Build the B-T preset with the overrides below, ideal hydraulics, run to steady state (dt = 0.5 s), compare drum composition x_D and sump composition x_B.

| Case | Overrides (all else B-T default) | x_D | x_B | D (kmol/h) |
|---|---|---|---|---|
| 4.1 default | – | 0.981183 | 0.018817 | 50 |
| 4.2 | E = 1.0 | 0.995951 | 0.004049 | 50 |
| 4.3 | E = 0.5 | 0.953307 | 0.046693 | 50 |
| 4.4 | feed tray 5 | 0.948400 | 0.051600 | 50 |
| 4.5 | feed tray 15 | 0.967099 | 0.032901 | 50 |
| 4.6 | L₀ = 110, V_B = 160 | 0.984504 | 0.015496 | 50 |
| 4.7 | L₀ = 150, V_B = 200 | 0.991024 | 0.008976 | 50 |
| 4.8 | q = 0.5, V_B = 100 | 0.966910 | 0.033090 | 50 |
| 4.9 | V_B = 155 (D = 55) | 0.907066 | 0.002475 | 55 |
| 4.10 | z = 0.6 | 0.992453 | 0.207547 | 50 |
| 4.11 | L₀ = 110, V_B = 150 (D = 40) | 0.993373 | 0.171085 | 40 |
| 4.12 | E = 1.0, N = 15, feed 8 | 0.986620 | 0.013380 | 50 |
| 4.13 | E = 1.0, N = 11, feed 6, L₀ = 82.5, V_B = 132.5 | 0.953272 | 0.046728 | 50 |

Tolerance: |Δx| ≤ 1×10⁻⁵ for every entry (the prototype matched to 1×10⁻⁶).

**VC-4.14 feed-tray scan [I]** (E = 0.7, defaults otherwise): x_D for feed tray 4…16 = 0.93211, 0.94840, 0.96031, 0.96893, 0.97495, 0.97891, 0.98118, **0.98203 (tray 11, optimum)**, 0.98147, 0.97927, 0.97479, 0.96710, 0.95520. Tolerance 1×10⁻⁵. (Used by scenario G5.)

**VC-4.15 steady cache.** For every preset, `runToSteadyState()` from cold reproduces the shipped cache within 1×10⁻⁶ in every x and 1×10⁻⁶ relative in every holdup.

## VC-5 Conservation

**VC-5.1 Tier 1, exact.** For any run, per component i: |(inventory_i(t₁) − inventory_i(t₀)) − ∫(F z_i) dt + ∫(D x_D,i + B x_B,i + other product flows) dt| / ∫F z_i dt ≤ 1×10⁻¹⁰ over 10 h of sim time. Inventory = Σ_stages m_ij. Outflows must be integrated with the exact values the solver used in each step (`StepDebug`: D · m₀/M̂₀ etc.), not recomputed from the end-of-step state. Run it on: B-T default; B-T full hydraulics at +30 % load (entrainment); 35 % turndown (weeping); tray 5 missing (F04, s = 1); a reflux step mid-run. Prototype: ≤ 1×10⁻¹¹ (default), ≤ 1×10⁻⁹ (fault cases).

**VC-5.2 Tiers 2/3.** Same, with the overhead vapour inventory Σ_i n_V,i included in the inventory. The tolerance is 1×10⁻¹⁰, exact by construction since M4 tracks the inventory per component (PHYSICS.md §7.1). v1.0 counted n_V y₁ and allowed 1×10⁻⁸, which transients would exceed (up to ≈ 2×10⁻⁶).

**VC-5.3 Crude.** Water (steam) in = water out of the drum boot + inventory change, 1×10⁻⁸; each pseudo-component, 1×10⁻⁸.

**VC-5.4 Energy at steady state (Tiers 2/3).** |F h_F + Q_R + Σ Q_steam,in − Q_C − Q_PA − Σ products h| / Q_R ≤ 1×10⁻⁶.

## VC-6 Time-step robustness [P]

B-T default, ideal hydraulics, Tier 1: run to steady state with dt = 0.25, 0.5, 2, 5, 30 s. All give x_D = 0.981183 ± 1×10⁻⁶ and x_B = 0.018817 ± 1×10⁻⁶; no negative-holdup clamps; no NaN. Also with `murphreePasses = 1`: same steady state.

## VC-7 Dynamic responses (Tier 1, ideal hydraulics) [P]

**VC-7.1 Reflux step.** From the B-T default steady state, L₀ 100 → 110 kmol/h at t = 0 with V_B fixed (so D falls to 40 via LC-101).

| t (s) | x_D | x_B | D (kmol/h) |
|---|---|---|---|
| 60 | 0.9815 | 0.0195 | 48.96 |
| 300 | 0.9843 | 0.0385 | 45.45 |
| 600 | 0.9875 | 0.0718 | 42.42 |
| 1800 | 0.9925 | 0.1447 | 38.47 |
| 3600 | 0.9933 | 0.1680 | 39.20 |
| 7200 | 0.99337 | 0.17105 | 39.99 |
| ∞ (Newton, VC-4.11) | 0.993373 | 0.171085 | 40.00 |

Tolerances: x_D ± 0.002, x_B ± 0.01, D ± 1.0 kmol/h at the finite times (they depend on holdups and level tuning); the final state as VC-4. Direction checks (strict): x_D rises monotonically after 60 s; x_B rises; D falls below 40 and recovers (level-loop overshoot).

**VC-7.2 Hydraulic lag** (amended 2026-10-12). Same steady state, reflux SP +10 kmol/h at t = 0.

Definitions:
- t63(X) is the first time the change in X reaches 63 % of its final change, measured from the lever change, sampling every step.
- X = L₀, the **delivered** reflux: `streams[reflux].flow`, the flow the solver used (DEVIATIONS.md E5).
- X = L₁ and L₂₀: `stages.liquidDown[1]` and `[20]`.

Pass:
- t63(L₁) − t63(L₀) ∈ [1, 4] s
- t63(L₂₀) − t63(L₀) ∈ [20, 45] s

This checks that the weir hydraulics produce a realistic lag of about 1–2 s per tray.

Reference values:
- [P] M1 engine (1 s ideal flow lag, DEVIATIONS.md E2): t63(L₀) = 2.0 s, t63(L₁) = 3.5 s, t63(L₂₀) = 31.0 s, so the differences are 1.5 s and 29.0 s. A −10 kmol/h step gives 1.5 s and 30.0 s.
- The v1.0 prototype stepped the delivered reflux directly: tray 20 was at 24 % after 20 s and 67 % after 30 s.

Not asserted (information): lever to L₁ 63 % is 3.5 s in M1. With the M3 flow loop (true flow 63 % at 3.0 s, VC-16.4) it is about 4.5–5 s.

*Why amended.* v1.0 timed tray 1 from the lever change (1–4 s). The window came from a prototype with no flow-controller lag, so it silently required an instantaneous flow loop. That conflicts with PHYSICS.md §10.4's ≈ 3 s loop. The tester found it and the M1 coder worked around it with a 1 s lag (DEVIATIONS.md E2/E18). Timing from the delivered flow tests what the case was written for, and holds for every flow-loop speed between 0 and about 5 s: for two first-order lags, the tray's 63 % delay changes by under 0.3 s.

**VC-7.3 Level loop.** Same reflux step: drum level maximum deviation 2–6 points (prototype 3.58 at 17 min), back within ±1 point of SP within 90 min (prototype 56 min), final 50.00 ± 0.01 %. Feed +10 %: sump maximum deviation 2–6 points (prototype 3.53), final 50.00 ± 0.01 %.

**VC-7.4 Time to steady state.** B-T default from cold: the steady-state monitor (PHYSICS.md §13.3) declares steady between 2.5 and 6 h of sim time.

## VC-8 Qualitative direction checks

Each check: start at a steady state, make the change, run to the new steady state, assert the sign of the change (and the stated magnitude when given). Tier 1 checks use B-T default; Tier 2 checks use B-T Tier 2 with constant pressure.

**Hydraulics mode.** VC-8.1 to 8.6 are **ideal-hydraulics** checks (`HydraulicsMode.ideal`, as `Presets.byId('bt')`; DEVIATIONS.md E19): they test the textbook stage model. With full hydraulics, tray-1 entrainment reaches the drum and raises D under LV control (PHYSICS.md §5.6), which can reverse 8.1. Rows 8.15 and 8.16 are the full-hydraulics counterparts at the v1.1 default geometry (TS = 0.9 m).

| # | Change | Expected | Tier |
|---|---|---|---|
| 8.1 | Raise reflux *and* boilup by the same amount (D constant): L₀, V_B +10 kmol/h | x_D up (0.981183 → 0.984504), x_B down; T1: boilup up; T2: Q_R up | T1, T2 |
| 8.2 | Raise L₀ only (V_B constant) | D down, x_D up, x_B up | T1 |
| 8.3 | Raise V_B only (L₀ constant) | D up, x_D down, x_B down | T1 |
| 8.4 | Lower E_MV 0.7 → 0.5 | x_D down, x_B up (VC-4.3) | T1 |
| 8.5 | Move feed tray away from optimum | x_D down (VC-4.14) | T1 |
| 8.6 | Feed lighter (z 0.5 → 0.6) at fixed L₀, V_B | x_D up, x_B up a lot (0.2075) | T1 |
| 8.7 | Raise P_top 1.013 → 2 bar(a) at fixed L₀ = 100 and D = 50 kmol/h, **with the steam header at 10 bar(g)** (at the default 3.5 bar(g), T_st = 148.1 °C gives only Q_max ≈ 880 kW at 2 bar, so the reboiler duty-limits) | α down (2.492 → 2.304 at x = 0.5); all T up (bottom 108.49 → 132.79 °C, +24.3 K); separation worse (x_D 0.97662 → 0.96080, x_B 0.02331 → 0.03800); **Q_R slightly down** (1306.9 → 1253.5 kW; latent heats fall with T). v1.0 said "Q_R up", which holds only at constant purity (G8). [P] E = 0.7 | T2 |
| 8.8 | Subcool reflux by 20 K | V₁ < V₂ (extra condensation on tray 1), x_D up, Q_C up | T2 |
| 8.9 | Switch T1 → T2 at the B-T default steady state (PHYSICS.md §13.5, top-vapour rule) | No NaN; V₁ within 0.5 % and D within 0.2 kmol/h of their T1 values at the first T2 step; V profile no longer flat: the stripping section steps by −4 … −6 % (V_B 150 → ≈ 141.9 kmol/h; toluene has the larger latent heat); individual tray liquid flows may step ≤ 15 % in the first step (the liquid profile redistributes; v1.0's "no step > 5 % in any flow" is not physical); P within ± 0.5 kPa of SP; new steady state x_D 0.97838 ± 0.0005 (T1 0.98118), D 49.96 ± 0.05. Back to T1 (V_B = V₁): x_D returns to within 5×10⁻⁴ of its original value (prototype 0.981411 against 0.981183; V_B becomes 149.96 rather than 150 because the Tier-2 V₁ settled 0.04 kmol/h lower). [P] at dt = 0.5, 2 and 30 s | T1↔T2 |
| 8.10 | Ethanol–water, Tier 3, N = 40, E = 1, R large | x_D never exceeds the azeotrope x = 0.8956 (+0.002); Tier 1 with α = 2.4 on the same column exceeds 0.95 | T3, T1 |
| 8.11 | Acetone–chloroform, Tier 3, feed x = 0.6 | bottoms approach the azeotrope (x ≈ 0.33), distillate approaches pure acetone | T3 |
| 8.12 | Debutanizer: raise R at fixed D | LK recovery up, HK in distillate down | T1, T3 |
| 8.13 | Methanol–water: switch T1 (α = 3.5) → T3 | top-section staircase changes (equilibrium curve no longer symmetric); actual operating locus curves | T1→T3 |
| 8.14 | Cut CW flow capacity to 50 % (F09) with PC in AUTO | PC output → 100 %; P_top rises until Q_C balances; all temperatures rise | T2 |
| 8.15 | **Full hydraulics**, default (TS 0.9 m), LV control: L₀ and V_B +10 kmol/h | x_D up 0.97826 → 0.98001 (± 0.0005), x_B down 0.01459 → 0.00997, max flood 62.9 → 67.1 % (no flooding alarm). [P] Further steps of +10: x_D 0.9796 (+20, 71 %), 0.9767 (+30, 75 %), 0.9709 (+40, 80 %). Beyond about +20 kmol/h the carryover into the drum outweighs the better L/V. Assert only the +10 row | T1 full |
| 8.16 | **Full hydraulics**, default, **D held at 50 kmol/h** (adjust L₀ until D = 50 ± 0.01): L₀ and V_B +0, +10, +20, +30, +40 kmol/h | x_D rises monotonically: 0.9810, 0.9843, 0.9866, 0.9883, 0.9896 (± 0.0005) [P]. This is the textbook lesson. The entrainment efficiency loss alone is small; it is D drifting up that turns 8.15 over | T1 full |

## VC-9 Multicomponent shortcut (FUG) [I]

Relative volatilities are fixed in these tests (they were computed once from DePriester K-values at the geometric mean of the top dew point and bottom bubble point; PHYSICS.md §2.3) so the test is deterministic. Saturated liquid feed (q = 1), F = 100 kmol/h.

Procedure (must match the FUG module): Fenske N_min from the key recoveries; non-key distribution from Fenske at N_min; Underwood θ between α_HK = 1 and α_LK (bisection); R_min from Underwood using x_D from the Fenske distribution; R = 1.3 R_min; Gilliland via Molokanov; Kirkbride feed ratio with x_B,LK and x_D,HK from the Fenske distribution.

**VC-9.1 Debutanizer** (LK n-butane 98 % to D, HK isopentane 98 % to B).

| Component | z | α (fixed) | d (kmol/h) | b (kmol/h) | x_D | x_B |
|---|---|---|---|---|---|---|
| propane | 0.05 | 5.180 | 5.0000 | 0.0000 | 0.11125 | 0.00000 |
| isobutane | 0.15 | 2.628 | 14.9806 | 0.0194 | 0.33332 | 0.00035 |
| n-butane (LK) | 0.25 | 2.041 | 24.5000 | 0.5000 | 0.54513 | 0.00908 |
| isopentane (HK) | 0.20 | 1.000 | 0.4000 | 19.6000 | 0.00890 | 0.35600 |
| n-pentane | 0.20 | 0.843 | 0.0631 | 19.9369 | 0.00140 | 0.36212 |
| n-hexane | 0.15 | 0.385 | 0.0000 | 15.0000 | 0.00000 | 0.27245 |

N_min = 10.9100, θ = 1.31112, R_min = 1.3073, R = 1.6996, X = 0.14528, Y = 0.50951, N = 23.282 stages, N_R/N_S (Kirkbride) = 1.0042, D = 44.9437 kmol/h. Tolerances: N_min, θ, R_min 1×10⁻⁴; N 1×10⁻³; d, b 1×10⁻⁴.

**VC-9.2 Depropanizer** (LK propane 99 % to D, HK isobutane 95 % to B), α = 2.172, 1.000, 0.747, 0.378, 0.330, 0.157 for C3, iC4, nC4, iC5, nC5, nC6; z = 0.30, 0.20, 0.25, 0.10, 0.10, 0.05: N_min = 9.7203, θ = 1.40567, R_min = 1.6522, N = 20.364, N_R/N_S = 0.4740, D = 30.7771 kmol/h.

**VC-9.3 Rigorous check [P].** Debutanizer, Tier 1 with the α above, E = 1, ideal hydraulics, 22 trays + reboiler (23 stages ≈ FUG N), feed tray 12, R = 1.6996 (L₀ = 76.39 kmol/h, V_B = 121.33 kmol/h, D = 44.9437). Expected recoveries: n-butane to D 0.984 ± 0.005, isopentane to B 0.985 ± 0.005 (FUG is slightly conservative, as usual). With 30 trays both exceed 0.99; moving the feed to tray 8 or 16 lowers both below 0.975.

**VC-9.4 DePriester spot values [I]** (McWilliams equation, PHYSICS.md (3.9)): n-butane 150 °F, 100 psia → K = 1.0648; isopentane 200 °F, 100 psia → 0.8922; n-pentane 200 °F, 100 psia → 0.7572; propane 100 °F, 200 psia → 1.0073; isobutane 100 °F, 100 psia → 0.7826; n-hexane 250 °F, 100 psia → 0.6301. Tolerance 1×10⁻⁴. (Raoult with Lee–Kesler gives 1.066, 0.911, 0.744, 0.946, 0.731, 0.597 — the DePriester values must be within 10 % of these, which is the consistency check that caught the n-butane coefficient error noted in PHYSICS.md §3.4.2.)

**VC-9.5 Feed bubble/dew points with DePriester at 100 psia [I]:** debutanizer feed bubble point 75.10 °C; with the FUG product compositions, distillate dew point 55.11 °C, bottoms bubble point 112.80 °C (± 0.05 K). Depropanizer at 250 psia: feed bubble point 89.53 °C, top dew 49.21 °C, bottom bubble 123.83 °C.

## VC-10 Thermodynamic spot values

**VC-10.1 Normal boiling points from the vapour-pressure models [I]** (bisection on P_sat = 101 325 Pa): benzene 80.100 °C, toluene 110.625, methanol 64.504, ethanol 78.298, acetone 56.287, chloroform 61.737, water (DIPPR-101) 100.018. Tolerance 0.005 K. [T] literature: 80.08, 110.6, 64.7, 78.37, 56.05, 61.2, 100.00 °C — differences up to 0.5 K are inherent to the published constants.

**VC-10.2 Water [I]:** P_sat(25 °C) = 3170.4 Pa (steam tables 3169.9), P_sat(150 °C) = 475 089 Pa (475 800), saturation temperature at 1, 3.5, 10, 20 bar(g) = 120.48, 148.10, 184.21, 214.99 °C. Tolerance 0.05 % / 0.01 K.

**VC-10.3 Benzene–toluene bubble points at 1 atm (Raoult) [I].**

| x_benzene | T_bubble (°C) | y_benzene | α |
|---|---|---|---|
| 0.0 | 110.625 | 0.00000 | 2.3481 |
| 0.1 | 106.136 | 0.20919 | 2.3807 |
| 0.2 | 102.103 | 0.37609 | 2.4112 |
| 0.3 | 98.457 | 0.51115 | 2.4398 |
| 0.4 | 95.142 | 0.62185 | 2.4667 |
| 0.5 | 92.112 | 0.71363 | 2.4920 |
| 0.6 | 89.328 | 0.79054 | 2.5160 |
| 0.7 | 86.760 | 0.85557 | 2.5388 |
| 0.8 | 84.380 | 0.91105 | 2.5604 |
| 0.9 | 82.166 | 0.95873 | 2.5811 |
| 1.0 | 80.100 | 1.00000 | 2.6007 |

Tolerance: T 0.002 K, y 1×10⁻⁵, α 1×10⁻⁴. Pressure effect at x = 0.5: 0.5 bar(a) → 69.824 °C, α = 2.7053; 2.0 bar(a) → 117.011 °C, 2.3040; 3.0 bar(a) → 133.814 °C, 2.1993. [T] cross-check: the textbook constant α = 2.5 sits in the middle of this range.

**VC-10.4 NRTL infinite-dilution activity coefficients [I]:** ethanol in water at 351.4 K: γ∞ = 5.401; water in ethanol: 2.575; methanol in water at 337.7 K: 2.041; water in methanol: 1.663; acetone in chloroform at 334 K: 0.449; chloroform in acetone: 0.551. Tolerance 1×10⁻³.

**VC-10.5 Azeotropes [I] vs [T].** Found by scanning x on a 1×10⁻⁴ grid for the sign change of y − x, then refining by bisection.

| System | P | Model x_az (light) | Model T_az (°C) | Literature | Pass band (model) |
|---|---|---|---|---|---|
| ethanol–water | 1 atm | 0.8956 | 78.141 | 0.894, 78.15 °C (Horsley; CRC) | x ± 0.0010, T ± 0.02 K |
| ethanol–water | 0.2 atm | 0.9292 | 42.349 | azeotrope shifts to higher ethanol at lower P; disappears below ≈ 0.09 atm | ± 0.002, ± 0.05 K |
| ethanol–water | 3 atm | 0.8713 | 108.586 | | ± 0.002, ± 0.05 K |
| acetone–chloroform | 1 atm | 0.3335 (acetone), maximum-boiling | 64.610 | ≈ 0.34, 64.4–64.5 °C (Horsley) | ± 0.002, ± 0.05 K |
| methanol–water | 1 atm | none | – | none | no sign change on (0, 1) |

The model must also be within the literature values by: ethanol–water x ± 0.005, T ± 0.1 K; acetone–chloroform x ± 0.02, T ± 0.3 K.

**VC-10.6 Methanol–water and ethanol–water VLE at 1 atm (Tier 3) [I] vs [T].**

| System | x | Model T (°C) | Model y | Experiment [T] (Perry's Handbook VLE tables) |
|---|---|---|---|---|
| MeOH–H₂O | 0.02 | 96.52 | 0.1358 | 96.4 °C, 0.134 |
| MeOH–H₂O | 0.10 | 87.77 | 0.4223 | 87.7 °C, 0.418 |
| MeOH–H₂O | 0.20 | 81.88 | 0.5812 | 81.7 °C, 0.579 |
| MeOH–H₂O | 0.50 | 73.11 | 0.7893 | 73.1 °C, 0.779 |
| MeOH–H₂O | 0.90 | 66.05 | 0.9598 | 66.0 °C, 0.958 |
| EtOH–H₂O | 0.10 | 86.26 | 0.4464 | ≈ 86.4 °C, 0.437 (x = 0.0966) |
| EtOH–H₂O | 0.50 | 79.73 | 0.6580 | ≈ 79.8 °C, 0.652 |
| EtOH–H₂O | 0.80 | 78.26 | 0.8190 | ≈ 78.4 °C, 0.818 |

Tolerances: against the model values T ± 0.01 K, y ± 1×10⁻⁴; against experiment, T ± 0.5 K and y ± 0.015 (sanity bands; experimental values are rounded readings).

**VC-10.7 Property correlations [I].**
- Rackett ratio: benzene 80 °C → 816.4 kg/m³ (lit. 815); toluene 110 °C → 779.9 (780); water 100 °C with Z_RA = 0.4945 → 958.4 (958.4). Tolerance 0.1 kg/m³ against the model value.
- Pitzer Z: saturated benzene vapour, 1 atm, 353.15 K → 0.9661; equimolar iC4/nC4 vapour at 7 bar, 330 K (ω = 0.192, Kay's rule) → 0.8597. Tolerance 1×10⁻⁴.
- Watson: ΔH_vap of benzene at 353.24 K = 30.72 kJ/mol (by definition); at 298.15 K = 30.72·((562.05−298.15)/(562.05−353.24))^0.38 = 33.58 kJ/mol (lit. 33.8). Tolerance 0.01 kJ/mol.
- Lee–Kesler + Clausius–Clapeyron ΔH_vap at T_b (used for pseudo-components): benzene 30.72, toluene 33.70, n-heptane 32.13 kJ/mol (lit. 30.72, 33.18, 31.77). Tolerance 0.01 kJ/mol against the model values.
- Lee–Kesler P_sat (bar): propane 10.0209 (300 K), 29.5500 (350 K); isobutane 3.7185, 12.6437; n-butane 2.5831, 9.5116; isopentane 0.9714, 4.2608; n-pentane 0.7205, 3.4105; n-hexane 0.2114, 1.2924; n-heptane 0.0641, 0.5074. Tolerance 1×10⁻⁴ relative.

**VC-10.8 Bubble-point solver robustness.** For every preset system, 1000 random compositions (seeded) and pressures within the preset's lever range: the solver converges (no fallback) in ≤ 6 Newton iterations from a cold guess in ≥ 99 % of cases and always converges with the bisection fallback; result satisfies |Σ K x − 1| < 1×10⁻⁹.

## VC-11 Tier-2 steady state (B-T MESH with energy balances) [I]

**Independent method.** Newton solve of the full steady MESH equations (component and total balances, bubble-point equilibrium, energy balances per tray; E = 1; total condenser with saturated reflux; constant pressure 101 325 Pa; no ΔP; feed saturated liquid at its bubble point 92.112 °C) with unknowns x_j, T_j, V_j, L_j; enthalpies per PHYSICS.md §3.3 with the §2.1 data; specs L₀ = 100 kmol/h and D = 50 kmol/h. One total balance is redundant and is dropped.

**Simulator test.** B-T, Tier 2, E = 1, ideal hydraulics (so ΔP = 0), PC-101 holding 101 325 Pa, FC-103 duty SP = **1301.477 kW**, L₀ = 100 kmol/h; run to steady state. D settles at 50 ± 0.001 kmol/h. The table's 1301.5 kW is the reference Q_R rounded; used as the SP it moves D by 0.002 kmol/h and the mid-column x by 4×10⁻⁴, outside the profile tolerance. **Cross-check [P]:** a JS prototype of the M4 dynamic algorithm (PHYSICS.md §4.5 with the implicit storage term, §7, §12.4 order) reached this steady state from a cold start in 6.1 h. Run at dt = 0.5, 2 and 30 s with SP 1301.477 kW, it matched every row below to ≤ 1×10⁻⁵ in x and ≤ 0.001 K, with energy closure 5×10⁻⁹.

| Quantity | Reference | Tolerance |
|---|---|---|
| x_D | 0.994946 | ± 5×10⁻⁵ |
| x_B | 0.005054 | ± 5×10⁻⁵ |
| T_D (distillate bubble point) | 80.201 °C | ± 0.02 K |
| T_B (reboiler) | 110.386 °C | ± 0.02 K |
| Q_C | 1281.2 kW | ± 0.2 % |
| Q_R | 1301.5 kW | (input) |
| V₁ (top) | 150.000 kmol/h | ± 0.1 % |
| V_B (boilup) | 141.118 kmol/h | ± 0.1 % |
| L₁₀ (below feed) | 193.183 kmol/h | ± 0.1 % |

Profile (selected stages; T in °C, flows in kmol/h):

| Stage | x | T | V (leaving) | L (leaving) |
|---|---|---|---|---|
| 1 | 0.98697 | 80.361 | 150.000 | 99.845 |
| 5 | 0.86543 | 82.914 | 148.560 | 97.706 |
| 9 | 0.55287 | 90.612 | 144.557 | 93.786 |
| 10 (feed) | 0.49166 | 92.355 | 143.786 | 193.183 |
| 11 | 0.44108 | 93.865 | 143.183 | 192.406 |
| 15 | 0.14427 | 104.298 | 140.454 | 190.394 |
| 20 | 0.01003 | 110.152 | 141.036 | 191.118 |
| 21 (reboiler) | 0.00505 | 110.386 | 141.118 | – |

Tolerances: x ± 1×10⁻⁴, T ± 0.02 K, flows ± 0.1 %. The teaching point checked here: V falls from 150 at the top to ≈ 140.4 near tray 16 and the liquid falls from 100 to 93.8 in the rectifying section — not CMO.

Further references (same method): L₀ = 150, D = 50 → x_D = 0.998569, x_B = 0.001431, Q_R = 1727.7 kW, Q_C = 1707.1 kW; feed tray 5 → x_D = 0.971465, x_B = 0.028535, Q_R = 1305.3 kW; D = 55 → x_D = 0.908433, x_B = 0.000804, Q_R = 1362.4 kW. Energy closure of the reference: |F h_F + Q_R − Q_C − D h_D − B h_B| < 1 W.

## VC-12 Tray hydraulics and hydraulic fault symptoms [P]

All on B-T, Tier 1, full hydraulics, sieve trays, defaults of PHYSICS.md §5.1 (D_c = 1.2 m, **TS = 0.9 m** (v1.1; v1.0 used 0.6 m), A_d/A_T = 0.12, h_w = 50 mm, A_h/A_a = 0.10, d_h = 12.7 mm, C₀ = 0.73), ρ_L = 800, ρ_V = 2.9 kg/m³, σ = 0.020 N/m.

The v1.1 numbers below were recomputed on 2026-10-12 with the committed M2 engine. The tester had independently confirmed it against the v1.0 prototype table (DEVIATIONS.md, 180/180), and the same harness reproduces the v1.0 values at TS = 0.6 m. VC-12.1 and VC-12.2 do not depend on TS (VC-12.2's C_SB spot values are at fixed TS).

**VC-12.1 Geometry [I]:** A_T = 1.1310 m², A_a = 0.8595 m², A_n = 0.9953 m², L_w = 0.9171 m (θ from (θ − sin θ)/2π = 0.12). Tolerance 1×10⁻⁴.

**VC-12.2 Correlation spot checks [I]:**
- Lygeros–Magoulas C_SB at TS = 600 mm: F_LV = 0.04 → 0.10279 m/s; F_LV = 0.0803 → 0.09590 m/s; at TS = 610 mm, F_LV = 0.1 → 0.09395 m/s (Fair's chart ≈ 0.30 ft/s = 0.091 m/s [T]).
- Bennett: K_s = 0.06 m/s, h_w = 0.05 m → α_e = 0.37909, C = 0.50145.
- Entrainment fit: F_LV = 0.1, φ = 0.9 → ψ = 0.03416; φ = 1.0 → 0.07232; F_LV = 0.01, φ = 0.5 → 0.01150; φ = 0.95 → 0.33605 (cap 0.6 not reached).
- Weep map: Φ = 0.75 → w = 0; Φ = 0.60 → 0.273; Φ = 0.20 → 1.
Tolerance 1×10⁻⁴ (relative for ψ).

**VC-12.3 Design-point steady state (full hydraulics) [P].** Defaults; run to steady state.

| Quantity | Value | Tolerance |
|---|---|---|
| x_D | 0.97826 | ± 0.002 |
| x_B | 0.01459 | ± 0.001 |
| D | 50.37 kmol/h (the 0.37 kmol/h of entrained liquid from tray 1 reaches the drum) | ± 0.3 |
| Column ΔP (20 trays) | 14.49 kPa | ± 5 % |
| Max flood % (KPI) | 62.9 (tray 20, jet) | ± 2 |
| Tray 1: φ, ψ, F_LV, Φ, h_cl, α_e, ΔP_dry, ΔP | 0.503, 0.0037, 0.0403, 1.681, 21.2 mm, 0.287, 470 Pa, 642 Pa | φ ± 0.02, ψ ± 20 %, h_cl ± 1 mm, ΔP ± 5 % |
| Tray 15: φ, ψ, F_LV, Φ, h_cl, ΔP | 0.599, 0.0042, 0.0832, 1.772, 23.8 mm, 781 Pa | same |
| Tray 20: φ, ψ, h_cl, ΔP | 0.629, 0.0053, 23.2 mm, 827 Pa | same |
| Tray 15 downcomer backup | 0.128 m clear liquid = 27.0 % of the limit φ_dc (TS + h_w) = 0.475 m | ± 10 % |
| Weeping anywhere | none (Φ > 1.6) | – |

v1.0 (TS 0.6 m) for reference: x_D 0.96725, x_B 0.00839, D 51.27, ΔP 14.68 kPa, max flood 83.2 %. Tray hydraulics other than jet flood are unchanged (the same h_cl, α_e, Φ, ΔP_dry within 1 %).

With entrainment, weeping and the downcomer limit switched off, the same run returns exactly the ideal-hydraulics result (VC-4.1, 0.981183 / 0.018817).

**VC-12.4 Fault and operating-condition symptoms [P].** From the design steady state; values after 10 min and after 4 h of sim time.

Terms:
- **"Load +x %"** is a *vapour-load* increment: F stays at 100 kmol/h, and L₀ and V_B each gain x × 150 kmol/h. +20 % means +30 kmol/h on each, so D stays at 50 plus the change in e₁. This is `addLoad` in `fixtures_m2.dart` (DEVIATIONS.md T1).
- **"Turndown to x %"** scales F, L₀ and V_B by x.
- "Max φ" is the highest jet-flood fraction, "w" the highest weeping fraction, "fill" the highest M/M_max, and "dc" the number of trays with the downcomer limit active.

| Case | After 10 min | After 4 h | Must hold (test assertions) |
|---|---|---|---|
| Load +20 % (L₀ 130, V_B 180 kmol/h) | ΔP 18.93 kPa, max φ 0.75, x_D 0.9840 | ΔP 19.29, x_D 0.9768, x_B 0.0039, max flood 75 % | ΔP ≥ 1.25 × base; x_B(4 h) < x_B(base); no flooding alarm |
| Same, entrainment off | ΔP 18.69 | x_D 0.9886, x_B 0.0114 | x_D(4 h) = 0.9886 ± 0.001 (the ideal-hydraulics value), so the gap to the row above is carryover |
| Load +30 % | ΔP 21.56, max φ 0.81 | ΔP 22.25, x_D 0.9668, x_B 0.0020, max flood 82 % | ΔP ≥ 1.45 × base; x_D(4 h) < x_D(4 h) of +20 % |
| Load +45 % | ΔP 26.22, max φ 0.91 | ΔP 27.29, x_D 0.9356, D 53.4 | ΔP ≥ 1.7 × base (engine 1.81, static model 1.77); x_D(4 h) ≤ 0.95; flooding alarm (max flood > 90 %) |
| Load +60 % (flood onset) | ΔP 32.09, max φ 1.01 | ΔP 33.07, x_D 0.8703, D 57.4, max flood 101 % | max flood ≥ 100 %; x_D(4 h) ≤ 0.90 |
| Load +75 % | ΔP 38.99, max φ 1.13 | ΔP 39.67, x_D 0.7323, D 68.3 | ΔP ≥ 2.5 × base; x_D(4 h) ≤ 0.80 |
| Turndown to 50 % (F, L₀, V_B × 0.5) | w 0.09 | x_D 0.9788, x_B 0.0192 (no-weep: 0.9804, 0.0174) | weeping starts (0 < w < 0.2); x_B with weeping > x_B without |
| Turndown to 35 % | w 0.51 | x_D 0.9653, x_B 0.0313 (no-weep: 0.9788, 0.0155) | w ≥ 0.3; x_B(weep) ≥ 1.5 × x_B(no weep); x_D(weep) < x_D(no weep) |
| Foaming F06, s = 0.33 (SF 0.85, φ_dc 0.433) | max φ 0.74 | x_D 0.9746, ΔP 14.18 | max φ ≥ 0.70 at unchanged load; ΔP within ± 10 % of base; no flooding (the headroom absorbs it) |
| Foaming F06, s = 0.67 (SF 0.70, φ_dc 0.367) | max φ 0.90 | x_D 0.9564, ΔP 14.01 | x_D drops ≥ 0.015; max φ ≥ 0.85; ΔP within ± 10 % |
| Foaming F06, s = 1.0 (SF 0.55, φ_dc 0.30) | max φ 1.16, flooding alarm | x_D 0.8171, max φ 1.24, ΔP 14.25 | flooding alarm; x_D(4 h) ≤ 0.90; ΔP within ± 10 % of base (foam floods *without* a pressure-drop rise, unlike load flooding) |
| Fouling F05 holes, s = 0.3, trays 12–16 | ΔP 16.58 | ΔP 16.58, x_D 0.9782 | ΔP +10…+20 %; |Δx_D| ≤ 0.002 (fouling shows in ΔP before separation) |
| Fouling F05 holes, s = 0.6, trays 12–16 | ΔP 22.20 (× 1.53) | the same; x_D 0.9782 | ΔP ≥ 1.4 × base; |Δx_D| ≤ 0.002; no downcomer limit (headroom) |
| Fouling F05 holes, s = 0.8, trays 12–16 | ΔP 57.5 (× 3.97), dc 12, sump 6 % | flooded and cycling: x_D 0.51 | ΔP ≥ 2 × base within 10 min; downcomer limit active on ≥ 5 trays; sump level ≤ 10 % within 10 min |
| Downcomer clearance F05 downcomer mode, s = 1 (90 % blocked), trays 12–16 | ΔP 27.97 (× 1.93), dc 5, sump 20 % | x_D ≈ 0.50, drum 115 % | ΔP ≥ 1.8 × base within 10 min; liquid accumulates above tray 12 (fill ≥ 1 on some tray above 12) |
| Broken tray F04, tray 5, s = 1 | tray-5 ΔP falls to 1.7 % of its base (E20 head factor); column ΔP 13.76 | x_D 0.9743, x_B 0.0186 | tray-5 ΔP ≤ 15 % of its base; both x_D and x_B worse than base |
| Broken tray F04, tray 15, s = 1 | column ΔP 13.73 | x_D 0.9753, x_B 0.0176 | as above |
| Broken tray F04, tray 5, s = 0.5 | | x_D 0.9743, x_B 0.0186; tray-5 weeping fraction 0.68 | tray-5 weeping fraction ≥ 0.5 |

**Dumping law (M3).** The three F04 rows were recomputed with a prototype of PHYSICS.md (5.15) (orifice drainage, implicit threshold, safeguarded u-Newton) on the M2 engine. They are identical to 4 decimals to the v1.0 law. A fully broken tray settles at Φ = 0.208 (tester's value; an earlier note said ≈ 0.25) and does not dump at any dt. They stay [P] until the M3 engine reproduces them.

Robustness assertion for every case: no NaN, no negative holdup, solver fatal flag never set, over 4 h.

**VC-12.5 Valve trays [P/I].** Same column with valve trays (f_v = 0.14, r_min = 0.25, ΔP_lift = 190 Pa, C_v = 0.65): at the design load the valves are fully open and ΔP_dry ≈ 357 Pa (sieve: 472–641 Pa); at 35 % load the valves balance (ΔP_dry = 190 Pa) and w = 0 (sieve: w ≈ 0.5); weeping starts below about 18 % load.

**VC-12.6 Dumping [P]** (M3, PHYSICS.md (5.15), implicit threshold). Design steady state (TS 0.9 m), then boilup cut to 0 with the feed on; after 600 s, at each of dt = 0.5, 2 and 30 s:
- every tray with `dumping` set holds ≤ 2 mol (sieve; prototype ≤ 1.35 mol, h_cl ≤ 0.17 mm at every dt). In a valve-tray column, ≤ 15 mol (prototype h_cl 1.4–1.7 mm);
- the total holdup of trays 10–20 is ≤ 15 mol at every dt (prototype 6.1 / 7.8 / 7.6 mol at dt 0.5 / 2 / 30; normally about 2100 mol). Which alternate trays carry the ≈ 1 mol depends on dt — the bypass checkerboard of PHYSICS.md §5.8 — so per-tray values are not compared across dt;
- no negative holdup and no NaN; the safeguarded Newton converges within 100 iterations (prototype ≤ 47 right after a break at dt = 30 s, ≤ 8 otherwise).

Fully broken tray 5 at TS 0.6 m and 0.9 m: the steady states at dt = 0.5, 2 and 30 s agree within 1×10⁻⁶ in x_D (prototype 0.964776 and 0.974315 at all three), with the tray at Φ = 0.208 ± 0.01 and not dumping.

## VC-13 Packed sections [I]

- **Robbins** (PHYSICS.md (6.1)): L' = 12.2, G' = 2.03 kg/m²/s, ρ_L = 1000, ρ_V = 1.1853 kg/m³, μ = 1 cP, F_pd = 24 ft⁻¹ → 309.83 Pa/m (619.66 Pa over 2 m; matches the reference example of the open-source `fluids` library, `fluids.packed_tower.Robbins`). Tolerance 0.01 Pa/m.
- **Kister–Gill flood ΔP** (6.2): F_p = 20 → 0.9363 in H₂O/ft = 765.2 Pa/m; 27 → 944.0; 56 → 1573.1; 65 → 1746.1 Pa/m. Tolerance 0.1 Pa/m.
- **B-T loads in a 1.2 m packed column** (G' = 3.132, L' = 2.088 kg/m²/s, ρ_L = 800, ρ_V = 2.9, μ = 0.27 cP):

| Packing | ΔP (Pa/m) | Flood ΔP (Pa/m) | Approach to flood | 
|---|---|---|---|
| struct250 (F_p 20) | 148.6 | 765 | 50.2 % |
| pall50m (F_p 27) | 204.7 | 944 | 54.8 % |
| pall25m (F_p 56) | 469.5 | 1573 | 69.9 % |

Tolerance: ΔP ± 0.5 %, flood approach ± 0.5 points. Teaching cross-check: 20 sieve trays at the same load have ΔP = 14.5 kPa and 50–63 % jet flood (VC-12.3, TS 0.9 m); 9 m of struct250 gives ≈ 1.3 kPa and 50 % — the textbook retrofit argument (scenario G15) rests on the pressure drop, about 11× lower.

- **Maldistribution** (parallel-column model, PHYSICS.md (6.6)):

| S | n | f | Φ_K uniform | Φ_mal | n_eff | E_O = n_eff/n | E_MV (Lewis) |
|---|---|---|---|---|---|---|---|
| 1.0 | 10 | 0.2 | 0.90909 | 0.87505 | 7.003 | 0.7003 | 0.7003 |
| 1.0 | 10 | 0.4 | 0.90909 | 0.79421 | 3.859 | 0.3859 | 0.3859 |
| 1.0 | 20 | 0.2 | 0.95238 | 0.89685 | 8.694 | 0.4347 | 0.4347 |
| 1.0 | 20 | 0.4 | 0.95238 | 0.79982 | 3.996 | 0.1998 | 0.1998 |
| 1.5 | 10 | 0.4 | 0.99415 | 0.95597 | 5.200 | 0.5200 | 0.4695 |
| 0.7 | 10 | 0.4 | 0.69395 | 0.63859 | 3.969 | 0.3969 | 0.4401 |
| 1.0 | 5 | 0.4 | 0.83333 | 0.75958 | 3.159 | 0.6319 | 0.6319 |
| 1.2 | 20 | 0.3 | 0.99556 | 0.93856 | 6.943 | 0.3471 | 0.3267 |

Tolerance 1×10⁻⁴ (n_eff 1×10⁻³). Shape checks: E_mal decreases with n and with f; it is lowest near S = 1.

- **Lewis relation** (4.3): λ = 0.5, E_MV = 0.5 → E_O = 0.41504; λ = 1.5, 0.7 → 0.74015; λ = 2.0, 0.5 → 0.58496. Tolerance 1×10⁻⁵.
- **Packing flooding develops over time [P-type check]:** B-T struct250 bed, raise V by steps of 10 % every 30 min: holdup and ΔP rise steeply once φ_p > 0.85; at φ_p ≥ 1 the bed ΔP exceeds the Kister–Gill flood ΔP and keeps rising for ≥ 5 min (not instantaneous); HETP_eff ≥ 1.3 × HETP_ref.

## VC-14 Thermosyphon reboiler

**VC-14.1 Loop unit test with fixed inputs [P].** Run the thermosyphon module alone (PHYSICS.md §8.3) for 1200 s at δ = 0.1 s with frozen column conditions: ρ_L = 780 kg/m³, ρ_V = 2.93 kg/m³, λ = 361 kJ/kg, c_p,L = 1950 J/kg/K, μ_L = 0.27 mPa·s, dT_sat/dP = 3.63×10⁻⁴ K/Pa, T_sump = 383.54 K, T_st = 421.25 K, geometry defaults (N_t = 200, D_i = 21.2 mm, L_t = 3.0 m, A = 47.6 m², U = 1000 W/m²K, z₀ = 1.2 m, h_sump = 2.4 m, z_ret = 4.5 m, D_r = 0.30 m, D_in = 0.20 m, L_in = 6.0 m, K_in = 4, K_out = 3), W₀ = 12 kg/s, u₀ = 1×10⁻³, v₀ = 0. Report means and half-amplitudes over the last 300 s.

| Q_R,SP | Sump level | Inlet valve | W (kg/s) | x_e | Q delivered (kW) | I_s | Oscillation amplitude √(u²+v²) | Period (s) |
|---|---|---|---|---|---|---|---|---|
| 1300 kW | 90 % | 100 % | 19.33 | 0.136 | 1300 | 0.40 | 0.001 (floor) | 9.8 |
| 1300 kW | 75 % | 100 % | 16.79 | 0.169 | 1300 | 0.50 | 0.001 | 9.6 |
| 1300 kW | 75 % | 16 % | 13.05 | 0.231 | 1300 | 0.47 | 0.001 | 10.0 |
| 1300 kW | 50 % | 100 % | 12.98 | 0.241 | 1300 | 0.74 | 0.001 | 9.2 |
| 1300 kW | 30 % | 100 % | 10.19 | 0.325 | 1300 | 1.01 | 0.002 | 8.8 |
| 1300 kW | 15 % | 100 % | 8.23 ± 0.28 | 0.425 ± 0.076 | 1194 ± 288 | 1.28 | 0.140 | 8.5 |
| 1300 kW | 15 % | 16 % | 7.30 ± 0.05 | 0.451 ± 0.046 | 1191 ± 171 | 1.07 | 0.034 | 9.1 |
| 1600 kW | 75 % | 100 % | 15.58 | 0.239 | 1597 (duty-limited, Q_max 1597) | 0.72 | 0.001 | 8.2 |
| 1600 kW | 30 % | 100 % | 9.87 ± 0.26 | 0.376 ± 0.030 | 1443 ± 259 | 1.17 | 0.115 | 8.1 |
| 1300 kW, K_out = 20 | 75 % | 100 % | 7.00 ± 0.28 | 0.454 ± 0.138 | – | 1.39 | 0.159 | 12.7 |
| 1300 kW, R_f = 4×10⁻⁴ m²K/W | 75 % | 100 % | – | 0.138 | 1140 (duty-limited) | 0.41 | 0.001 | – |

Tolerances: W ± 3 %, x_e ± 0.01, I_s ± 0.03, Q ± 1 %, period ± 15 %; amplitudes: stable rows ≤ 0.003, oscillating rows within ± 30 % of the value. The table is a regression map of the specified model, not of a real exchanger.

**VC-14.2 Integrated behaviour [P-type checks].** B-T Tier 2 with the thermosyphon, duty SP 1300 kW:
1. At sump level SP 50 % the column reaches a steady state (monitor passes).
2. Lower LC-102 SP to 15 %: within 10 min the boilup oscillates with peak-to-peak ≥ 10 % of its mean and period 5–15 s; bottom-tray ΔP and sump level oscillate at the same period; the "thermosyphon unstable" alarm is raised. The amplitude grows over ≥ 30 s (not a step).
3. Then throttle the inlet valve to 16 %: amplitude falls by ≥ 50 % within 5 min. Raise the level SP back to 50 %: oscillation decays below 1 % peak-to-peak within 5 min.

## VC-15 Crude fractionation

**VC-15.1 Pseudo-components [I].** From the TBP table and cut points of PHYSICS.md §9.1 with K_W = 11.9, the engine reproduces the PHYSICS.md §9.1 table: vol fractions ± 1×10⁻⁴; T_b ± 0.05 K; SG ± 1×10⁻⁴; MW ± 0.05; T_c ± 0.05 K; P_c ± 0.005 bar; ω ± 1×10⁻⁴; ΔH_vap(T_b) ± 0.01 kJ/mol; Cp₀ ± 0.05 J/mol/K; dCp ± 1×10⁻³. Bulk SG 0.8656 (31.96 °API) ± 1×10⁻⁴; mean MW 216.9 ± 0.1. Each pseudo-component's Lee–Kesler P_sat(T_b) = 101 325 Pa to 1×10⁻⁶ relative (consistency of the ω definition).

Spot P_sat values (Pa): PC1 at 200 °C 1.9843×10⁶, at 360 °C 1.6955×10⁷; PC5 at 200 °C 1.4683×10⁴, at 360 °C 4.6417×10⁵; PC9 at 360 °C 91.577. Tolerance 1×10⁻⁴ relative.

**VC-15.2 TBP → ASTM D86 (Daubert 1994) [I].** For a TBP curve (°C) 0 %: 150, 10 %: 165, 30 %: 180, 50 %: 200, 70 %: 220, 90 %: 240, 100 %: 255, the converter gives D86 (°C) 0 %: 173.46, 10 %: 178.22, 30 %: 184.23, 50 %: 196.45, 70 %: 210.62, 90 %: 225.28, 100 %: 239.92 (5 %: 175.84, 95 %: 232.60). Tolerance 0.01 K.

**VC-15.3 Ideal cut products [I].** Perfect separation at TBP cut points 165 / 240 / 340 / 370 °C of the shipped assay:

| Product | TBP range (°C) | Yield (vol % of crude) | D86 5 % (°C) | D86 50 % | D86 95 % |
|---|---|---|---|---|---|
| Naphtha | IBP–165 | 20.00 | 60.3 | 99.9 | 146.9 |
| Kerosene | 165–240 | 11.67 | 183.7 | 199.2 | 223.9 |
| Diesel | 240–340 | 16.67 | 259.9 | 282.4 | 316.9 |
| AGO | 340–370 | 5.30 | 339.7 | 344.4 | 353.1 |
| Residue | 370+ | 46.36 | (TBP only) | | |

Ideal 5–95 gaps (D86): kerosene–naphtha +36.9 K, diesel–kerosene +36.0 K, AGO–diesel +22.8 K. Tolerance 0.1 K (yields 0.01 %). These are the defaults for the draw levers (SCOPE.md §4.4) and the upper bound for any real gap.

**VC-15.4 Crude column plausibility [checks after M9 tuning].** Default crude preset, Tier 2, run to steady state:
- Material balance: Σ products (mass) = crude feed (mass) within 0.1 %; water out = steam in within 0.1 %.
- Energy closure ≤ 1×10⁻³ relative.
- Simulated gaps strictly below the ideal gaps (no "better than perfect" separation), and: kerosene–naphtha between −15 and +35 K; diesel–kerosene between −30 and +34 K; AGO–diesel between −45 and +20 K (an overlap here is normal).
- Naphtha D86 95 % 130–190 °C; kerosene D86 95 % 215–270 °C; diesel D86 95 % 310–370 °C.
- Overflash 1–6 vol % of crude; residue yield 40–55 vol %.
- Top tray temperature 100–150 °C and at least 5 K above the water dew point at its steam partial pressure.
- Flash-zone temperature within 25 K below the COT; bottom temperature below the flash-zone temperature (steam stripping cools the residue).
- Every main-column tray between 35 % and 85 % jet flood, no weeping, column ΔP 15–60 kPa. If not, the implementer adjusts the preset diameter/geometry (not the physics) and records it.
- Direction checks: kero draw +2 % of crude → kero D86 95 % up, diesel D86 5 % down, kero–naphtha gap unchanged ± 3 K, diesel–kero gap down; PA trip (F25) → top temperature and overhead duty up within 10 min; stripping steam loss (F24) → residue yield up, diesel/AGO yield down, bottom temperature up.

## VC-16 Controllers [I] / [P]

The PID unit tests drive a bare `ControlLoop` with scripted PVs. Unless stated: h = 1 s, span 0–100, Td = 0, OPLO/OPHI 0/100, noise off.

- **16.1 PID arithmetic [I].** Kc = 2, Ti = 10 s, direct action, OP₀ = 50 %, SP = 50.
  - PV steps 50 → 51 at the first execution and holds. OP = 52.2 after 1 execution and 54.0 after 10. PV back to 50: OP = 52.0.
  - Same loop, but the error is made by an SP step 50 → 49 with PV = 50: with `spKick` true, OP = 52.2 after 1 execution and 54.0 after 10. With `spKick` false (re-based), OP = 50.2 after 1 and 52.0 after 10.
  - Tolerance 1×10⁻¹².
- **16.1b Derivative sign [I].** Kc = 1, Ti = ∞, Td = 8 s (τ_f = 1 s), SP 50, PV = 50 + k at execution k, OP₀ = 50.
  - Direct action: OP = 55, 58, 60, 61.5, 62.75, 63.875 after executions 1–6.
  - Reverse action: 45, 42, 40, 38.5, 37.25, 36.125.
  - This pins the corrected sign of (10.1): with v1.0's sign the first value would be 47.
- **16.2 Anti-windup [I].** Kc = 2, Ti = 10 s, direct, OP₀ = 50, PV = 55 and SP = 50 for 100 executions: OP = 61 after 1 execution, 99 after 39, and 100 from execution 40 on. PV then drops to 49.5: OP = 88.9, then 88.8. A positional PI without anti-windup would stay at 100 % for about 490 executions.
- **16.3 Bumpless transfer [I].**
  - (a) MAN with OP = 37.2 %, PV = 62.0 %, SP = 50 %; switch to AUTO: SP becomes 62.0, and with PV constant |ΔOP| < 1×10⁻⁹ per execution for 100 executions.
  - (b) AUTO → MAN: OP unchanged.
  - (c) [P, M4] Enabling TC-101 at a Tier 2 steady state: TC-101 SP = the TI-114 reading at the switch, and FC-103's SP moves < 0.1 kW in the first 60 s. Disabling it holds FC-103's SP.
  - (d) With FC-103 in AUTO, TC-101 is in IMAN and its OP equals 100 (SP_FC-103 − lo)/(hi − lo) to 1×10⁻⁹.
- **16.4 Flow loop [P]** (PHYSICS.md §10.4 settings; prototype of the exact algorithm). FC-102, B-T Tier 1, noise off, steady at 100 kmol/h (OP 33.333 %). The SP steps to 110 kmol/h at t = 0.
  - Sub-step values, read through the `@visibleForTesting` fast-layer trace, ± 0.01 kmol/h:

    | t (s) | 0.5 | 1 | 2 | 3 | 5 | 10 | 20 |
    |---|---|---|---|---|---|---|---|
    | True flow (kmol/h) | 101.186 | 102.566 | 104.820 | 106.432 | 108.323 | 109.748 | 109.994 |

    Measured PV at 3 s: 105.615. OP at 1 s: 35.986 %; final 36.667 %.
  - Main-step means used by the solver (`StepDebug`, ± 0.01): at dt = 0.5 s, 100.596, 102.026, 103.308, 104.418, 105.359, 106.149, 106.808, 107.357; at dt = 2 s, 102.587, 106.418, 108.315, 109.210.
  - The sub-step sequences at dt = 0.5 s and 2 s are bit-identical.
  - 63 % times: true flow 3.0 s, measured 3.5 s. Overshoot ≤ 0.05 %.
  - Tier 2 duty loop (gain 0.722): 63 % in 4.2 ± 0.2 s.
  - With noise off, every M1 steady state (VC-4, VC-6) is reproduced to its stated tolerance with the real flow loops.
- **16.5 Level loops.** VC-7.3, unchanged; the M3 flow loops keep it within its bands.
- **16.6 Pressure loop** (B-T Tier 2, total condenser, PC-101 Kc 10, Ti 120 s; PHYSICS.md §10.7). [P] values from the M4 prototype at the VC-11 steady state:
  - Condenser design point (UA 29.9 kW/K, PHYSICS.md §7.2): CW OP 50 ± 1 % at steady state; CW outlet 44.7 ± 0.3 °C.
  - Open loop (PC-101 in MAN), CW OP 50 → 40 %: P_top rises 5.8 ± 0.6 kPa; 63 % of that is reached in 150–230 s (prototype 190 s; the column's heat storage sets the time constant).
  - PC-101 SP step ±10 kPa (no proportional kick, spKick false): P_top within ± 1 kPa of the new SP within 10 min (prototype 297 s for +10 kPa, 438 s for −10 kPa), overshoot ≤ 30 % (prototype 0 %), and no sustained oscillation (decay ratio ≤ 0.3). With v1.0's 2 / 60 s at the v1.0 design point the +10 kPa step took 695 s and the −10 kPa step never settled (CW saturated).
  - L₀ and boilup +10 kmol/h (VC-8.1 in Tier 2): P_top held at SP ± 0.2 kPa with CW below 95 % (prototype 89.5 %).
  - Loss of cooling F09 mode flow, s = 0.7: CW valve to 100 % within 2 min (prototype 72 s), and P_top rises to a new steady value (prototype 1.167 bar(a)). At s = 0.5 the loss is absorbed: P stays at SP with the valve near 100 %.
  - s = 1.0: P rises until the relief valve lifts (alarm, event; prototype reaches the 3.5 bar(a) set point at 471 s).
  - **16.6b** Partial condenser (PV-102, Kc 1.0, Ti 30 s): the same SP-step criteria; tuning **[impl-tunable]** (not prototyped).
  - **16.6c Flash stability.** From the VC-11 steady state, step the CW OP 70 → 100 % (PC in MAN) at dt = 0.5, 2 and 30 s: P_top falls to 0.966 ± 0.005 bar(a) within 1 h at every dt (prototype 0.9660–0.9662); there is no runaway or step-to-step oscillation, and V₁ stays ≤ 1.1 × its steady value in every step (prototype 1.025–1.029). This is the implicit storage term of PHYSICS.md (4.6); v1.0's lagged term made this case run away.
- **16.7 Cascade.** TC-101 enabled on tray 14 (Tier 2; Kc 4.0 on the 0–200 °C span): feed composition +0.1 → TC-101 holds the TI-114 reading within ± 0.5 K after 60 min by moving FC-103's SP, which stays inside the 20–65 % OP limits.
- **16.8 BAD PV handling [I].**
  - (a) `badPvShed` = 1, LT-101 `signalLossLow`: at the next execution LC-101 is in MAN with OP unchanged (|ΔOP| < 1×10⁻¹²), `LT-101.BAD` (high) and `LC-101.SHED` are raised, and `setMode(AUTO)` throws StateError while the PV is BAD.
  - (b) `badPvShed` = 0, same fault: LC-101 stays in AUTO and its OP is 0 % after the first execution, because e = −52.5 % gives ΔOP = −105. LT-102 `signalLossHigh` drives LC-102's OP to 100 %.
  - (c) Ratio mode with FT-104 BAD: FC-102's SP stays at its last GOOD value.
- **16.9 Valve faults and bypass [I/P].** FC-102 at steady state, noise off.
  - (a) FV-102 `stuck`, then SP +10 kmol/h: the true flow changes by < 1×10⁻⁹. OP rises 2.1 % at the first sub-step (P kick), then 1 %/s, reaches 100 % at 64.7 ± 0.5 s, and `FC-102.OPSAT` is raised 60 s later.
  - (b) `failOpen`: true flow 63 % of the way to 300 kmol/h after 2.1 ± 0.1 s, and OP is driven to 0.
  - (c) `bypass.FV-102` = 33.3: the opening ramps at 2 %/s and the flow settles at 99.9 kmol/h. FC-102 is forced to MAN, and FT-102 reads the bypass flow.

## VC-17 Units [I]

| Conversion | Input (SI) | Expected display | Tolerance |
|---|---|---|---|
| Temperature | 373.15 K | 100.00 °C / 212.00 °F | 1×10⁻⁹ |
| Pressure | 101 325 Pa | 1.01325 bar(a) / 14.6959 psia | 1×10⁻⁴ |
| Molar flow | 1 mol/s | 3.6 kmol/h / 7.93664 lb-mol/h | 1×10⁻⁵ |
| Energy rate | 1×10⁶ W | 1000 kW / 3.41214 MMBtu/h | 1×10⁻⁵ |
| Crude flow | 132.5 m³/h | 20 001.6 bbl/d (20 000 bbl/d = 132.489 m³/h) | 0.1 bbl/d |
| Length | 0.0254 m | 25.4 mm / 1.000 in | 1×10⁻⁹ |
| Density | 800 kg/m³ | 49.942 lb/ft³ | 1×10⁻³ |
| Temperature difference | 10 K | 18 °F | 1×10⁻⁹ |

Round trip toSI(fromSI(v)) = v: linear quantities (every conversion that is a pure factor) to 1×10⁻¹² relative; temperature (an affine conversion, K ↔ °C/°F) to 1×10⁻⁹ K absolute, since the 273.15 offset makes a relative test meaningless near 0 °C. Dimensionless quantities (fractions, ratios, `dimensionless`) convert by 1 and carry no unit symbol: `symbol(q)` returns the empty string, and percent returns "%".

## VC-18 McCabe–Thiele data invariants

- **18.1** Tier 1, E = 1, steady state (VC-4.2): every operating-locus point (x_j, y_{j+1}) lies on the CMO rectifying line (j above the feed) or stripping line (below) within 1×10⁻⁸; every staircase corner (x_j, y_j) lies on the equilibrium curve within 1×10⁻⁸; the two CMO lines intersect on the q-line within 1×10⁻⁸.
- **18.2** Tier 1, E = 0.7 (VC-4.1): corners lie on the pseudo-equilibrium curve y_op + 0.7(y* − y_op) within 1×10⁻⁶; for every tray (y_j − y_{j+1})/(y*_j − y_{j+1}) = 0.7 within 1×10⁻⁸.
- **18.3** Tier 2 steady state (VC-11): the operating locus deviates from the dashed CMO lines by more than 0.002 somewhere in the rectifying section, so non-CMO is visible ([P] max 0.0064 in the rectifying section, 0.0025 in the stripping section). The equilibrium band between P_top and P_bottom has non-zero width when ΔP > 0.
- **18.4** R_min construction: for the VC-1 configuration the builder's R_min = 1.1000 ± 1×10⁻⁴; for ethanol–water at x_D = 0.80, z = 0.10, q = 1, Tier 3, the R_min line touches the equilibrium curve above the feed pinch (tangent pinch), i.e. the touching point has x > the q-line intersection.
- **18.5** Transient flag: true for the first minute after any lever change, false at steady state.
- **18.6** Multicomponent pseudo-binary: at the VC-9.3 steady state the primed compositions are within [0, 1] and the staircase has N + 1 corners.

## VC-19 Performance

| Measure | Target | Platform |
|---|---|---|
| `Simulator.step()` B-T Tier 1, 22 stages | ≤ 30 µs | Windows dev machine (release/AOT) |
| `step()` 40 trays × 8 components Tier 2 (synthetic config from the debutanizer components plus two heavier) | ≤ 100 µs (desktop), ≤ 300 µs (mid-range Android, release) | both |
| `step()` crude, default | ≤ 150 µs desktop, ≤ 450 µs Android | both |
| `snapshot()` for 42 stages × 8 components | ≤ 50 µs | desktop |
| McCabe–Thiele build (warm cache) | ≤ 0.3 ms | desktop |
| `explain(tray)` | ≤ 5 ms | desktop |
| UI at 100× with the McCabe–Thiele tab open | ≥ 55 fps average over 60 s, no frame > 32 ms more than 1 % of frames | Android mid-range, release (e.g. Pixel 6a / Galaxy A54 class) |
| Achievable speed, B-T Tier 1 | ≥ 1000× without the speed-limited flag | Android mid-range |

## VC-20 Determinism

- **20.1** Same build and platform: two runs of 10 000 steps with the same config, lever script and seed give bit-identical `saveState()` JSON.
- **20.2** Across platforms (Windows x64 vs Android arm64), noise off: every state variable agrees to 1×10⁻⁹ relative after 1 h of sim time.
- **20.3 PRNG vectors [I]** (PHYSICS.md §12.9), on native and on the web build (M10):
  - FNV-1a-32("") = 2166136261, ("a") = 3826002220, ("FT-102") = 1498766031.
  - Stream (seed 1, "FT-102") after the warm-up: next32 = 3793846675, 4233283444, 1026389867, 4162901922.
  - A fresh stream with the same seed and key: uniform() = 0.883323766184137, then normal() = −0.6076328127833632 and −0.42066679512424215 (1×10⁻¹⁵ abs).
  - Stream (seed 42, "drill"): uniform() = 0.041090393331688735, 0.8835882459215075.
  - 10⁶ normals from (7, "stats"): mean within ± 0.003, variance within 1 ± 0.005.
- **20.4 Save/restore.** Noise on, a fault active (FT-102 plugged, ramping) and an alarm unacknowledged. Run 1800 s, save, restore into a new simulator, and run both 1800 s more: bit-identical. This covers instrument, valve, PRNG, alarm and scenario state.
- **20.5 Noise-on reproducibility and stream independence.**
  - Same seed: bit-identical. Seeds 1 and 2: the FT-102 readings differ.
  - Injecting a fault on FT-101, or switching TI-107 to spiking, leaves the FT-102 reading series bit-identical.
  - Drills: the same seed draws the same candidate, severity, onset and sign (VC-26.5).
- **20.6 Steady indicator with noise on [P-type]** (PHYSICS.md §13.3, noise-on monitor). B-T Tier 1 default, started steady, noise on:
  - the indicator turns green within 60 min and stays green ≥ 95 % of the time over the next 2 h;
  - after a reflux SP step of +10 % it turns false within 10 min;
  - "Run to steady state" with noise on returns the noise-off steady state (VC-4.1 to 1×10⁻⁵) and leaves the `noise` lever on.

  If the thresholds of §13.3 need tuning to pass, record the values in DEVIATIONS.md.

## VC-21 Explain consistency

For every stage of the B-T default (Tier 1, Tier 2, full hydraulics) and every equation line returned by `explain()`: `line.value` equals the corresponding snapshot value (same state) within 1×10⁻¹² relative; every line has a non-empty `texSymbolic` and `texSubstituted`; every id exists in PHYSICS.md §15's catalogue.

## VC-22 Instruments (M3) [I] / [P]

Unit tests drive a bare `Instrument` with a scripted true value (PHYSICS.md §10.5). Seeds and stream keys are as stated. Values are in % of span unless a unit is given. The statistical tolerances cover sampling error and the discrete-versus-continuous difference (≤ 4 % in the prototype).

- **22.1 4–20 mA and quality [I]**, FT-102 (0–300 kmol/h), noise off:

  | True value (kmol/h) | Current I (mA) | v_meas (kmol/h) | Quality |
  |---|---|---|---|
  | 100 | 9.33333 | 100.000 | GOOD |
  | 300 | 20.0 | 300.000 | GOOD |
  | 305 | 20.2667 | 305.000 | UNCERTAIN, "OOR▲" |
  | 320 | 20.5 (saturated) | 309.375 | UNCERTAIN |
  | −20 | 3.8 | −3.750 | UNCERTAIN, "OOR▼" |
  | `signalLossLow` | 3.6 | −7.500 | BAD, "IOP−" |
  | `signalLossHigh` | 21.0 | 318.750 | BAD, "IOP+" |

  Tolerance 1×10⁻⁹. With noise on, I_q is a multiple of 1/4096 mA.
- **22.2 Noise statistics [P].** Constant true value, noise on, 200 000 s, seed 11, stream keys `inst:<tag>:s` and `:e`. Measured standard deviation within ± 6 % of σ_disp, mean within ± 0.02 % of span, and lag-τ_s autocorrelation in 0.45–0.70:

  | Type | σ_disp | Prototype h = 0.5 s | Prototype h = 2 s |
  |---|---|---|---|
  | FT (h = 0.1 s) | 0.409 | 0.404 | – |
  | LT drum | 0.423 | 0.418 | 0.408 |
  | LT sump | 0.775 | 0.761 | 0.748 |
  | PT | 0.046 | 0.0445 | 0.0446 |
  | PDT | 0.845 | 0.835 | 0.815 |
  | TI | 0.062 | 0.0624 | 0.0610 |

  - The valve disturbance d has standard deviation 0.0100 ± 0.0006 and autocorrelation at 30 s of e⁻¹ ± 0.05.
  - **dt independence:** for every type tested at both h, the two standard deviations agree within ± 6 %.
- **22.3 Noise in a closed flow loop [P].** FC-102 at 100 kmol/h, noise on, seed 3, 1800 s after a 600 s warm-up. Prototype values:
  - reading standard deviation 1.18 kmol/h (pass 1.0–1.4);
  - standard deviation of 0.5-s differences 0.71 (pass 0.6–0.85);
  - true-flow standard deviation 0.88 (pass 0.6–1.2);
  - OP standard deviation 0.47 % (pass 0.3–0.7);
  - every 5-min mean of the true flow within ± 0.4 kmol/h of the SP.
- **22.4 Determinism.** See VC-20.3 to 20.5.
- **22.5 Failure-mode signatures [I unless marked].** Faults are injected at t₀ = 600 s; noise on unless stated.

  | Mode | Setup | Assertion |
  |---|---|---|
  | bias | FT-102, sign +1, s = 0.3 | Mean (reading − true) over 600 s = 9.00 ± 0.1 kmol/h; quality GOOD; noise unchanged (± 6 %) |
  | drift | FT-101, sign +1, s = 0.6 | Reading − true = 15.0 ± 0.1 kmol/h after 3600 s (0.6 × 0.1 × 250), and 7.5 ± 0.1 after 1800 s |
  | stuck | any tag | Every reading after t₀ bitwise equal to the last pre-onset reading; σ_5min = 0 exactly; `digitsAge` ≥ t − t₀ |
  | signal loss | as 22.1 | BAD from the first update after t₀; `<tag>.BAD` raised with 0 on-delay |
  | plugged [P] | FT-102, s = 1, 0.9, 0.75, 0.5, ramp 0, noise off; true value steps +10 % of span 60 s after t₀ | Fraction of the step shown 600 s after the step (t = t₀ + 660 s; with t₀ = 600 s, t = 1260 s) = 0.058, 0.140, 0.451, 0.998 (± 0.01). With noise on and a constant true value, σ_5min/σ_disp ≤ 0.08 for s = 1 (prototype 0.049) |
  | spiking [P] | FT-102 at 33 % of span, 3600 s | s = 1: 180 ± 40 spikes (prototype 186), \|a\| in 10–50 % of span, σ_5min/σ_disp ≥ 10 (prototype 17.8). s = 0.5: 90 ± 28 spikes, ratio ≥ 4 (prototype 6.1). TI-107 at s = 0.5: ratio ≥ 20 (prototype 38). At 33 % of span (I₀ = 9.33 mA) positive spikes never reach BAD; negative spikes larger than 35.8 % of span drive the current below 3.6 mA → BAD for that update (about 35 % of negative spikes at s = 1). A reading at 90 % of span with a spike of +20 % reaches 21.6 mA → BAD |
  | coated | TI, s = 1, h = 0.5 s; true step +10 K | Reading 63 % at 100.5 ± 1 s (healthy 10.5 ± 0.5 s); σ_disp ratio coated/healthy 0.52 ± 0.05 |
  | analyser | AT-101 (phase 100 s), noise off; true value 0.0200 → 0.0700 at the step ending at t = 1000 s | Shown 0.0200 up to 1299.5 s; 0.0204 from 1300 s (0.826 % of the step through the 60-s lag); 0.0697 from 1600 s; 0.0700 from 1900 s. Result age 300–600 s at all times after the first publication. Signal loss: no new result, quality BAD; STALE after 600 s without a result |
  | AT bias | AT-102, sign +1, s = 0.5 | Published results = lagged true + 0.005 ± 1×10⁻⁴ (rounding) |

- **22.6 Field gauges [P].** 1000 requests of LG-101 against a constant true level of 50.0 %: results ready exactly at the first step end ≥ request + 180 s; mean error within ± 0.15 %; standard deviation 1.15 ± 0.1 % (N(0, 1 %) plus 2 % graduation rounding). One pending request per gauge: a second request is ignored until the first returns.
- **22.7 Maintenance.** `requestMaintenance("FT-102")` with a bias active: quality OOS for 1800 s, FC-102 shed to MAN regardless of `badPvShed`, then GOOD with the bias cleared. In a drill it throws StateError.

## VC-23 Cross-checks (M3: C1, C3, C4, C5; M4: C2, C3a, C3b, C6, C7) [I] / [P]

- **23.1 Exact closure [I].** B-T Tier 1 default steady state, noise off, window 600 s: r1, r3, r4 (every pair) and r5 (drum and sump) are each below 1×10⁻⁶ of their band; status `ok`. C2 (after 1800 s steady): \|r2\| ≤ 0.02 kmol/h (analyser rounding). The Tier 2 VC-11 steady state with noise off: \|r3a\|, \|r3b\| ≤ 0.1 band; C7 \|r7\| ≤ 0.05 K.
- **23.2 No false alarms [P].** B-T Tier 1 (and Tier 2 from M4), steady, noise on, 2 h, every window size (300–3600 s) with the band scaling max(1, 600/W) of C1/C3 (PHYSICS.md §14.6): no check ever `fail`; `check` on < 2 % of evaluations (tester's estimate ≈ 1.2 %); the standard deviation of r4 for FV-102 at W = 600 s ≤ 0.25 band.
- **23.3 Detection [P]** (noise on, B-T, default window; Tier 1 rows in M3, Tier 2 rows in M4):

  | Fault (t₀ = 600 s) | Must happen | Must not happen |
  |---|---|---|
  | FT-102 bias +, s = 0.4 (12 kmol/h) | C4:FV-102 and C3 `fail` within 10 min | C1 leaves `ok` |
  | FV-102 `stuck` | C4:FV-102 `fail` within 15 min | C3 or C1 `fail` (≥ 95 % of evaluations `ok`) |
  | FT-102 plugged, s = 1, ramp 300 s | Signal-look ratio ≤ 0.2 within 10 min; C3 `fail` within 20 min | – |
  | FT-101 drift +, s = 0.6 | C1 `fail` within 25 min; C4:FV-101 `fail` within 30 min | C3 `fail` (Tier 1, q = 1) |
  | LT-101 bias +, s = 0.8 | C5:drum `fail` within 10 min; FT-104 excursion ≥ 10 kmol/h; an LG-101 check differs from LT-101 by 8 ± 3 % | C4 any `fail` |
  | LT-102 stuck | σ_5min = 0 within 5 min; C5:sump `fail` within 20 min of a feed SP step of +5 kmol/h | – |
  | PT-101 bias +, s = 0.5 (10.1 kPa) [T2] | r7a and r7b both ≥ 2.7 K (band 1 K) with the same sign within 15 min | C6 flags any TI |
  | TI-114 bias +, s = 0.25 (5 K), TC-101 on [T2] | C6 flags TI-114 within 20 min | C6 flags any other TI |
  | F07 feed +0.08 benzene, ramp 900 s [T1, T2] | – | Any C1, C3, C4, C5 `fail`; C6 flags any TI (if C6 does, widen its factor 0.5 → 0.75 and record it in DEVIATIONS.md) |

## VC-24 Plant view (M3)

B-T Tier 1, view = 1, noise on, a 1-h run with a reflux step:
- In every snapshot, `stages.x/y/yStar/liquidDown/vaporUp/entrain/weep/dp/jetFlood/dcFlood/frothFill/stability/weepFrac/efficiency` are all NaN.
- `stages.t` is NaN (Tier 1) or, in Tier 2, NaN except at instrumented trays, where it equals the TI reading.
- `holdup[0]` and `holdup[N+1]` equal level/100 · V/v_L,design from the LT readings.
- `kpis.d/b/boilup/drumLevelPct/sumpLevelPct` equal the readings.
- `kpis.xD` = 1 − AT-101's shown result; `maxFloodPct`, `balanceResidual` and `energyResidual` are NaN.
- `valves[*].position` is NaN, and `visibleFaults` is empty.
- `McCabeThieleBuilder.build` returns `available == false`.
- `explain(ExplainStage(5))` returns the single "Not observable on a real plant" note.
- No `model.*` alarm except `model.relief` appears.
- In the same run, `MetricContext.read('kpi.xD')` returns the **true** value (it differs from the masked one by the analyser lag).

## VC-25 Alarms (M3) [P]

- **25.1 Chatter.** LT-101 true level held at exactly 85.0 % (the HI limit), noise on, 1 h, 5 seeds: `LT-101.HI` raised ≤ 4 times per hour per seed (prototype 1–2). With delays and deadband removed it would chatter about 200 times per hour. At 84.5 % (inside the deadband): ≤ 15 raises per hour (prototype 5–9).
- **25.2 States.**
  - Raise → UNACK; acknowledge → ACKED; clear → removed.
  - Raise, then clear before acknowledgement → RTN-UNACK; acknowledge → removed.
  - `acknowledgeAll` acknowledges every alarm, and the journal holds each transition with its sim time.
- **25.3 Delays and conditions.**
  - DEV is raised only for loops in AUTO/CAS, after 30 s beyond the limit; switching to MAN clears it.
  - OPSAT is raised after 60 s at a limit with |e| > 2 %.
  - BAD has no on-delay.
  - Ordering: priority, then newest first.
- **25.4 Readings, not truth.** LT-101 bias −10 %: `LT-101.HI` does not fire although the true level reaches 87 %. The safety accumulator (true level) still records any time above 95 %.

## VC-26 Scenario engine (M3) [I]

- **26.1 Schema.** `ScenarioDef.validate()` returns no problems for every shipped scenario and drill. Copies with an unknown metric path, an unknown lever, a candidate with weight 0 only, a template variable that does not exist, or `onsetWindow[1] + 3600 > timeLimit` each return a problem.
- **26.2 Predicates.**
  - `all`/`any`/`not`, `between`, and the numeric `==` tolerance of 1×10⁻⁹.
  - String compares for `mode` and `quality`.
  - `from: "start"` (a metric 0.97 at t = 0 and 0.955 now gives −0.015).
  - NaN → false, except `!=`.
  - `holdFor` resets on a single false evaluation.
  - `latch` true keeps an objective achieved, while `latch` false lets it revert.
- **26.3 Scoring arithmetic** (§11.4 of ENGINE_API.md).
  - **Guided:** weights 0.6/0.2/0.1/0.1, three objectives of weight 1 with two achieved, t_end = 30 000 s, parTime = 10 800 s, timeLimit = 43 200 s, no relief, level violation 0, qualitySpec true 90 % of the time, no hints. Then O = 0.4, T = 0.2 × (2/3) × 0.40741 = 0.054321, S = 0.1, Q = 0.09, so the score is **64**.
  - **Drill** (H9 weights): t₀ = 1200 s. Attempt 1 at 2100 s has the category right and the location wrong; attempt 2 at 2700 s is fully correct with the mode right. Protect is met at 1500 s, t_os = 2000 s, one hint is taken, there is no safety issue. Then C = 0.5, L = 0.2, T = 0.2 × (1 − 900/3000) = 0.14, S = 0.1, B = 0.1 + 0.05, P = 0.1, H = 0.03, so the score is **96**.
  - **Same drill, never diagnosed:** C = L = T = 0, S = 0.1, B = 0.1 (protect met), giving **20**.
- **26.4 Guided scenarios are completable [P].** An automated player applies each M3 scenario's hint values and must achieve every objective within the time limit, using fast-forward. Its checkpoints, against ENGINE_API.md §11.8 (Tier 1, ideal hydraulics, ± 1×10⁻⁴):

  | Scenario | Setting | Expected |
  |---|---|---|
  | G2 | R = 1.30 | xD = 0.99279 |
  | G2 | R = 1.20 | xD = 0.97142 |
  | G2 | R = 1.15 | xD = 0.96071 |
  | G2 | R = 1.12 | xD = 0.95429 |
  | G4 | q = 1.2 / 1.0 / 0.5 / 0 at V_B = 1.02 × V_min (D = 50) | xD ≥ 0.95 and xB ≤ 0.05 at each |
  | G4 | V_B = 0.98 × V_min | xD < 0.95 at each |
  | G6 | N = 28 | xD = 0.98056 |
  | G6 | N = 27 | xD = 0.97761 |

  G11 and G12 run as in M2 (DEVIATIONS.md A9).
- **26.5 Drill draws.** For the H9 JSON and seed s, the candidate, s, t₀ and sign are a pure function of s (two runs agree). Over seeds 1…10 000, each candidate's frequency is within 3σ of weight/Σweights. t₀ is always a multiple of dt inside the onset window. During the drill, no snapshot field and no event names the fault before `finish()`.

## VC-27 Tier-2 references and utility limits (M4) [P]

Computed with the JS prototype of the M4 dynamic algorithm, which reproduces VC-11 to 1×10⁻⁵ (see there). Ideal hydraulics, E = 0.7 unless stated, feeds at their bubble point.

**27.1 Methanol–water preset `mw`, Tier 2 (Raoult; NRTL arrives in M5).**
- Setup: 20 sieve trays, B-T geometry (TS 0.9 m), feed on tray 12, F = 100 kmol/h, z_MeOH = 0.30, P_top = 1 atm, L₀ = 60 kmol/h, FC-103 duty 890.4 kW.
- Steady state (tolerances x ± 1×10⁻⁴, T ± 0.05 K, flows ± 0.2 %):

  | Quantity | Value |
  |---|---|
  | D | 30.00 kmol/h |
  | x_D / x_B | 0.98873 / 0.00481 |
  | T_D / T_B | 64.72 / 99.68 °C |
  | V₁ (top) / V_B (boilup) | 90.00 / 78.95 kmol/h — boilup 12 % below the top: water's latent heat is 15 % larger, the G7 point |
  | L₁ / L₁₉ | 59.83 / 149.06 kmol/h |
  | Q_C | 882.1 kW |
- Utility design values (procedure of PHYSICS.md §7.2, §8.2): condenser UA_clean = 29.76 kW/K at 50 % CW; reboiler UA_R,clean = 30.65 kW/K (60 % of Q_max with 3.5 bar(g) steam).
- Tier 1 on the same column (α = 3.5, V_B = 90 kmol/h): x_D 0.99046, x_B 0.00407.

**27.2 B-T pressure sweep at fixed L₀ = 100 and D = 50 kmol/h** (utilities unconstrained; this is VC-8.7's definition and G8's starting point):

| P_top (bar a) | Q_R (kW) | x_D | x_B | T_D (°C) | T_B (°C) | α on the feed tray |
|---|---|---|---|---|---|---|
| 0.50 | 1352.5 | 0.98617 | 0.01290 | 58.38 | 86.19 | 2.714 |
| 0.70 | 1331.9 | 0.98219 | 0.01720 | 68.11 | 96.46 | 2.607 |
| 1.013 | 1306.9 | 0.97662 | 0.02331 | 79.60 | 108.49 | 2.498 |
| 2.00 | 1253.5 | 0.96080 | 0.03800 | 103.10 | 132.79 | 2.315 |
| 3.00 | 1213.7 | 0.94914 | 0.05113 | 119.19 | 149.18 | 2.211 |

Tolerances: Q_R ± 0.3 %, x ± 2×10⁻⁴, T ± 0.05 K, α ± 0.002.

**27.3 What the default utilities can deliver** (analytic from 27.2, PHYSICS.md (7.3) and (8.2)). Reboiler Q_max = UA_R,clean (T_st − T_B); condenser at 100 % CW = UA_eff(m_cw,max) (T_D − T_cw,in) with UA_clean 29.9 kW/K:

| P_top | Reboiler Q_max, steam 3.5 bar(g) (148.1 °C) | Reboiler Q_max, steam 10 bar(g) (184.2 °C) | Condenser max, CW 30 °C | Condenser max, CW 15 °C |
|---|---|---|---|---|
| 0.50 | 3559 | 5636 | 781 | 1194 |
| 0.70 | 2969 | 5046 | 1049 | 1462 |
| 1.013 | 2277 | 4354 | 1365 | 1778 |
| 2.00 | **880** | 2957 | 2012 | 2425 |
| 3.00 | **none** (T_B > T_st) | 2015 | 2455 | 2868 |

All values are in kW. Needed duties are about Q_R from 27.2 (condenser ≈ Q_R − 20 kW).
- **At 0.5 bar(a)** the condenser cannot condense with any CW the levers allow (≥ 5 °C). G8 therefore starts its sweep at 0.7 bar(a) with CW at 15 °C.
- **At 2–3 bar(a)** the reboiler needs the 10 bar(g) header, which is why G8 and VC-8.7 set it.

These limits are physics, not bugs. A scenario that ignores them leaves the learner with a column that cannot do what the briefing asks.

**27.4 Fault severity floors at the B-T design point** (PHYSICS.md §11):
- F15 starts to limit the duty at s ≈ 0.58 (header 2.95 bar(a), 133.0 °C).
- F09 flow mode starts to raise the pressure at s ≈ 0.5 (a fully open valve then delivers exactly the design CW flow).
- H2 and H4 severity ranges must start above these values: F09 [0.6, 1.0], F15 [0.7, 1.0].

---

## H. Hidden-fault drill symptom tests

For each drill candidate the test injects the fault (fixed seed, onset at 600 s, severity at the middle of its range), runs 2 h with noise off, and asserts the *key evidence* — the observation a learner is expected to use. Direction thresholds are deliberately loose; they check that the evidence exists, not its exact size.

| Drill | Fault | Key evidence to assert |
|---|---|---|
| H1 | F05 fouling, stripping trays 12–18, holes | ΔP across trays 12–18 up ≥ 10 % at constant flows; ΔP of trays 1–11 up < 3 %; x_D change < 0.003 in the first hour |
| H1 | F07 feed lighter (Δz = +0.1 benzene, −0.1 toluene; PHYSICS.md §11 sum-zero convention) | ΔP change < 3 %; T profile shifts (Tier 2: tray 10 T down ≥ 1 K); Tier 2: D rises by ≥ 0.3 kmol/h via LC-101, because the lighter bottoms have the smaller molar latent heat, so the same duty boils more moles. Under Tier-1 LV control D would not move (D = V₁ + e₁ − L₀ is fixed by the flows) and the extra benzene would leave in the bottoms (x_B up). H1 runs in Tier 2 |
| H2 | F09 CW temperature +15 K (s = 1; drill range [0.6, 1.0]) | P_top up (prototype 1.18–1.39 bar(a) for s = 0.6–1); CW valve to 100 % within 2 min; reflux subcooling down |
| H2 | F10 condenser fouling | P_top creeps up over ≥ 30 min; CW valve creeps up; subcooling down |
| H2 | F11 non-condensables | P_top up while CW valve is not saturated at first; reflux subcooling **up** (≥ 5 K); opening the vent restores P within 10 min |
| H3 | F04 broken tray, rectifying (tray 5) | column ΔP down; tray-5 ΔP ≤ 15 % of neighbours; x_D down at constant L/D |
| H3 | F06 foaming s = 0.9 (with the v1.1 headroom, s ≤ 0.67 no longer floods; drill range [0.8, 1.0]) | max flood ≥ 100 % at unchanged load while column ΔP stays within ± 10 % of base ([P]: φ 1.08, ΔP × 0.97); x_D down ≥ 0.03 within 1 h ([P] 0.9783 → 0.908 at 60 min). Antifoam: max φ < 0.75 within 20 min, and x_D back within 0.03 of base within 40 min ([P] 0.953) |
| H3 | F19 FT-102 bias, sign +1, s = 0.5 (+15 kmol/h; F19 biases are additive in % of span, PHYSICS.md §10.6) | displayed reflux = SP, true reflux 15 kmol/h lower; C3a: V₁ from the condenser duty disagrees with displayed L + D by ≥ 8 %; C4:FV-102 `fail` |
| H4 | F13 reboiler fouling | steam valve rises over ≥ 30 min then saturates; duty falls below SP after saturation |
| H4 | F14 condensate backup | duty falls below SP within 5 min with the steam valve at 100 % |
| H4 | F15 steam header loss | header pressure reading down; duty limited; T_st down |
| H5 | F19 LT-102 drift, sign +1 (reads high), s = 1 (10 %/h, the F19 maximum) | displayed sump level steady at SP, true level falling 10 %/h; thermosyphon I_s rising; oscillation appears once the true level is < 25 % (≈ 2.5 h after onset — this case runs 3 h) |
| H5 | F17 inlet restriction | circulation W down ≥ 20 %; x_e up; no oscillation unless the duty is raised |
| H5 | F18 outlet restriction | I_s > 1; boilup oscillation with period 5–15 s |
| H6 | F07 feed upset (debutanizer, +0.05 nC4, −0.05 iC5) | feed analyser trend changes (dead time 300 s); LK recovery changes with reflux unchanged |
| H6 | F12 partial reflux loss (s = 0.5) | reflux flow below SP with FC output at 100 %; top T up; drum level up |
| H6 | F20 reflux valve stuck | FC-102 output moves ≥ 10 % while flow is constant |
| H7 | F21 maldistribution f = 0.4 | bed ΔP change < 5 %; separation worse (x_D down); bed T profile flattens in the middle |
| H7 | F22 near-flood (load +25 %) | bed ΔP rises ≥ 2× while load rises 25 % |
| H7 | F23 crushed packing s = 0.5 | bed ΔP up ≥ 30 % at constant load |
| H8 | F24 stripping steam loss | bottom T up; residue yield up; flash-zone T slightly up |
| H8 | F25 pumparound trip | top T and Q_C up within 10 min; diesel D86 95 % up |
| H8 | F26 COT −15 K | residue yield up; overflash down; AGO yield down |

### H9 and H10: evidence must be detectable with noise on (ENGINE_API.md §11.5)

Unlike the rows above, these run with **noise on**, plant view and the drill's own settings. Each candidate is tested at the **minimum** severity of its range, with sign +1 and with sign −1, onset 600 s, seeds 1–3. "Within" counts from t₀; for drifts, from t₀ + 10 min. All are [P-type] checks for M6. A candidate that fails on the M6 engine gets weight 0 and an entry in DEVIATIONS.md; the drill is not tuned to pass.

| Id | Candidate | Key evidence to assert (default window 600 s) | Also assert |
|---|---|---|---|
| H9.0 | **No fault** (healthy run, 2 h, the feed event included) | No check `fail`; no BAD alarm; the off-spec predicate is never true | Signal-look ratios σ_5min/typicalSigma of every tag in 0.5–2, where FT-104/FT-105 use the level-loop typical σ of PHYSICS.md §10.5 (0.94 % / 1.60 % of span; against plain σ_disp they would read ≈ 2.4) |
| H9.1 | FT-102 bias, s = 0.4 | C3 or C3a `fail` within 10 min; C4:FV-102 `fail` within 10 min | C1 `ok`; off-spec reached within 2 h (so the protect bonus means something) |
| H9.2 | FT-102 plugged, s = 0.9 | Signal-look ratio of FT-102 ≤ 0.2 within 15 min | C3/C3a `fail` within 30 min |
| H9.3 | FT-101 drift, s = 0.6 | C1 `fail` within 20 min | C4:FV-101 `fail` within 30 min |
| H9.4 | FT-103 bias, s = 0.4 | C3b `fail` within 15 min; C4:FV-103 `fail` within 15 min | \|ΔxB\| < 0.01 (the cascade compensates) |
| H9.5 | LT-101 bias, s = 0.8 | C5:drum `fail` within 10 min; LG-101 vs LT-101 ≥ 5 % at any time after 15 min | – |
| H9.6 | LT-102 signal loss low | `LT-102.BAD` at once | With no action, true sump > 95 % within 30 min (safety at stake) |
| H9.7 | LT-102 stuck | σ_5min of LT-102 = 0 within 5 min | C5:sump `fail` within 20 min after the feed event |
| H9.8 | PT-101 bias, s = 0.5 | r7a and r7b ≥ 2.7 K, same sign, within 15 min | – |
| H9.9 | TI-114 bias, s = 0.25 | C6 flags TI-114 within 20 min | Off-spec reached within 2 h |
| H9.10 | TI-114 coated, s = 0.8 | Within 30 min after the feed event, either C6 flags TI-114, or TC-101's OP oscillates with peak-to-peak ≥ 5 %, or TI-114's signal-look ratio ≤ 0.6 | **Weakest candidate**; drop it per the rule above if none of the three holds |
| H9.11 | TI-107 spiking, s = 0.5 | Signal-look ratio of TI-107 ≥ 5 within 5 min | – |
| H9.12 | FT-104 stuck | σ_5min of FT-104 = 0 within 5 min | C1 or C3 `fail` within 20 min after the feed event |
| H9.13 | F07 ± 0.08 benzene | AT-100 shows the change within 15 min | No check `fail` in 2 h; C6 flags nothing |
| H10.0 | **No fault** (healthy run, 2 h, the planning event included) | As H9.0 | – |
| H10.1 | FV-102 stuck | C4:FV-102 `fail` within 20 min, or within 5 min of the planning event | C3/C3a and C1 `ok` ≥ 95 % of evaluations; FT-102 signal-look ratio in 0.5–2 |
| H10.2 | FV-103 stuck | C4:FV-103 `fail` as above | C3b `ok` ≥ 95 %; FT-103 signal look normal |
| H10.3 | FT-102 bias, s = 0.4 | C4:FV-102 **and** C3/C3a `fail` within 10 min | – |
| H10.4 | FT-102 plugged, s = 0.9 | FT-102 signal-look ratio ≤ 0.2 within 15 min | C3/C3a `fail` within 30 min (separates it from H10.1) |
| H10.5 | FT-103 drift, s = 0.6 | C3b `fail` within 25 min | C4:FV-103 `fail` within 30 min |
| H10.6 | FT-103 plugged, s = 0.9 | FT-103 signal-look ratio ≤ 0.2 within 15 min | – |
| H10.7 | F07 ± 0.10 benzene | AT-100 shows the change within 15 min | No C4 `fail`; no C3 `fail` in 2 h |

A healthy run with the drill's scripted event (H9.0, H10.0) must never meet the off-spec predicate, so the protect bonus measures the fault and not the event (ENGINE_API.md §11.5 rule 7). If H9.0 fails, reduce the feed event from +5 to +3 kmol/h and record it.

---

## U. UI and theme checks

- **U1 Layout.** Widget tests at 360×800, 800×360, 1024×768 and 1440×900 logical px: no `RenderFlex` overflow; every lever, the TimeBar and the KPI strip are reachable (scrollable allowed); minimum text size 12 sp at text scale 1.0, no clipping at 1.3.
- **U2 Contrast.** For every theme: ink/bg ≥ 7:1; inkMuted/bg ≥ 4.5:1; accent, alarm, warn, ok and every chart line colour against the chart background ≥ 3:1. Exemptions: inkFaint, grid, gridMajor, diagonal (decorative); phosphor alarm (shown inverse-video). Computed values for the SCOPE.md §7.2 palettes all pass (lowest: Paper warn 3.43, Brass alarm 3.72, Brass q-line on parchment 4.24).
- **U3 Colour-vision.** Under a deuteranopia simulation, the alarm and ok colours of every theme differ in lightness by ≥ 15 L* units or are paired with distinct shapes/labels (all alarm displays carry a text label; required regardless).
- **U4 Goldens.** Golden images for the column and McCabe–Thiele painters, per theme, on the VC-4.1 steady-state snapshot.
- **U5 Frame budget.** The SimController never spends more than 6 ms of a frame in `advance` (measured over 600 frames at 1000×).

---

## Reference sources

- Textbook McCabe–Thiele, Fenske, Underwood, Gilliland, Kirkbride: Seader, Henley and Roper, *Separation Process Principles*, 3rd ed., Wiley (2011), chapters 7 and 9; McCabe, Smith and Harriott, *Unit Operations of Chemical Engineering*, 7th ed. (2005), ch. 21; Molokanov et al., *Int. Chem. Eng.* 12 (1972) 209.
- Vapour pressures and NRTL parameters: PHYSICS.md §2.2 and §3.4.1 sources (Dean, Lange's Handbook; Perry's Handbook Table 2-8; Beneke et al. 2013, App. B).
- Azeotropes: Horsley, *Azeotropic Data III* (ACS Adv. Chem. Ser. 116, 1973); CRC Handbook of Chemistry and Physics, azeotrope tables.
- Methanol–water and ethanol–water VLE: Perry's Chemical Engineers' Handbook, VLE tables (methanol–water at 1 atm; ethanol–water, Carey and Lewis, *Ind. Eng. Chem.* 24 (1932) 882).
- Steam tables: IAPWS-IF97 values for P_sat checks.
- Tray hydraulics: Fair (1961); Lygeros and Magoulas (1986); Bennett et al. (1983); Summers et al. (2010); Coulson & Richardson Vol. 6.
- Packing: Robbins (1991); Kister and Gill (1991); `fluids` Python library documentation, `fluids.packed_tower.Robbins` example (619.662 Pa).
- Crude: Riazi (2005) ASTM MNL50; Daubert (1994); Watkins (1979); Kister, *Distillation Operation* (1990), crude chapters.
- [I] and [P] values: computed by the physics lead for this specification (October 2026) with independent Newton / bisection solvers and with a prototype of PHYSICS.md §12; methods described in each case.
