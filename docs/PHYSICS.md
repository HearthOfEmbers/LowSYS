# LowSYS — Physics and Numerical Model

Status: specification v1.0 (2026-10-12). This is the model contract. The coding agent implements exactly what is written here; where a choice is left open it is marked **[impl]**. Every simplification is stated with its reason. Reference numbers that prove the model are in [VALIDATION.md](VALIDATION.md).

Several algorithms here were prototyped by the physics lead before writing (dynamic Tier-1 column with the exact step algorithm of §12, tray hydraulics with flooding/weeping/downcomer limits, the thermosyphon loop of §8.3, Newton steady-state reference solvers). The prototypes converged to the independent steady-state solutions to 1×10⁻⁶, conserved every component to 1×10⁻¹² relative, and stayed stable from dt = 0.25 s to dt = 30 s. Where a first design failed in prototyping (explicit entrainment with unbounded ψ, checkerboard holdups when the downcomer limit used the neighbour's current holdup, density-wave oscillations from a lumped loop), the failure and the chosen fix are noted.

---

## 0. Conventions

### 0.1 Units inside the engine

All engine arithmetic is SI with these base units: amount **mol**, time **s**, temperature **K**, pressure **Pa**, energy **J**, power **W**, length **m**, mass **kg**. Molar masses are stored in g/mol (= kg/kmol) and converted where needed (`MW/1000` → kg/mol). Display conversion happens only in the UI layer (ENGINE_API.md §12).

Constants: R = 8.314462618 J/(mol·K); g = 9.80665 m/s²; 1 atm = 101 325 Pa; 1 mmHg = 133.322368 Pa.

### 0.2 Stage numbering

The main column is one chain of stages, numbered from the top:

| j | Stage |
|---|---|
| 0 | Condenser + reflux drum (holds liquid; not an equilibrium stage for a total condenser) |
| 1 … N | Trays or packed segments, top to bottom |
| N+1 | Sump + reboiler (equilibrium stage) |

Side strippers (crude) are separate chains (§9.4). "Tray j" means stage j for 1 ≤ j ≤ N.

### 0.3 Symbols

| Symbol | Meaning | Unit |
|---|---|---|
| m_ij | holdup of component i on stage j | mol |
| M_j = Σ_i m_ij | total liquid holdup | mol |
| x_ij = m_ij / M_j | liquid mole fraction | – |
| y_ij | mole fraction in vapour **leaving** stage j | – |
| y*_ij | vapour in equilibrium with x_j at T_j, P_j | – |
| L_j | liquid flowing down from stage j to j+1 (weir + dump drain); L_0 = reflux | mol/s |
| V_j | vapour flowing up from stage j to j−1; V_{N+1} = boilup | mol/s |
| e_j | entrained liquid carried from tray j up to tray j−1 | mol/s |
| f_j, W_j | bypass fraction of tray j and bypass flow W_j = f_j L_{j−1} (inlet liquid falling straight to tray j+1: weeping, broken deck) | –, mol/s |
| F_j, z_ij, h_F,j | feed to stage j, its composition, its molar enthalpy | mol/s, –, J/mol |
| T_j, P_j | stage temperature; pressure in the vapour space **above** stage j | K, Pa |
| h_j, H_j | liquid and vapour molar enthalpy on stage j | J/mol |
| K_ij, K̃_ij | equilibrium ratio; normalised K (§4.3) | – |
| E_j | Murphree vapour efficiency of stage j | – |
| v_L | liquid molar volume | m³/mol |
| ρ_L, ρ_V | liquid, vapour mass density | kg/m³ |
| σ | surface tension | N/m |
| dt | main time step | s |

Superscript n is the value at the start of the step, n+1 at its end.

---

## 1. Model overview

### 1.1 What is dynamic and what is algebraic

| Quantity | Treatment | Why |
|---|---|---|
| Component holdups m_ij on every stage, drum, sump | **Dynamic state** (ODE), implicit Euler | Composition dynamics are the core of what learners watch |
| Liquid flows L_j (weir hydraulics) | Algebraic function of the holdup (Bennett weir); holdup–flow coupling solved implicitly | Gives the real hydraulic lag (seconds per tray) and the vapour–liquid "froth" coupling |
| Vapour flows V_j | Algebraic: CMO (Tier 1) or quasi-steady energy balance (Tiers 2/3) with lagged sensible-heat storage | Vapour holdup time constants are milliseconds; resolving them would force tiny steps |
| Stage temperature T_j | Algebraic: bubble point of x_j at P_j | Liquid on a tray is at its bubble point to within a fraction of a kelvin |
| Tray pressures P_j | Algebraic: P_top + Σ tray ΔP (from hydraulics) | Same reason as vapour |
| Overhead pressure P_top | **Dynamic state**: overhead vapour inventory n_V (and inert inventory n_I) | Gives pressure dynamics: loss-of-cooling, non-condensables, PC loop |
| Entrainment fraction ψ_j, filtered liquid load | **Dynamic** (first-order filters, τ = 5 s and 10 s) | Prevents numerical feedback through lagged hydraulic coefficients (prototype finding) |
| Thermosyphon loop circulation, riser quality, oscillator | **Dynamic states**, sub-stepped at 0.1 s | Loop time constants are 1–10 s |
| Controller integral terms, valve positions, instrument filters | **Dynamic states** | Control behaviour |
| Fault progress | Time functions (onset + ramp) | |

### 1.2 State vector

For a column with N trays/segments, n_c components, S side-stripper stages, and the optional equipment:

```
X = [ m_ij for j = 0..N+1, i = 1..n_c          (component holdups, main chain)
      m_ik for stripper stages k, i = 1..n_c     (crude only)
      n_V, n_I                                    (overhead vapour and inert inventory; Tier 2/3)
      ψ_j, L̄_j for j = 1..N                      (entrainment fraction, filtered liquid load)
      W, x_r, u, v                                (thermosyphon: circulation kg/s, riser quality, oscillator)
      controller OPs and PID histories (e_{k−1}, PVf), valve positions, bypass openings
      instrument states: sensed noise n_s, impulse-line and damping lags v_p, v_m, analyser v_ss / pending / shown result,
        spike schedule, frozen outputs (stuck), field-check requests        (§10.5)
      valve disturbances d, PRNG stream states                             (§12.9)
      alarm states and the event journal                                    (§10.8)
      T_j^{n-1} for j = 0..N+1                     (previous stage temperature, for sensible storage; Tier 2/3)
      fault clocks ]
```

Everything else (x, y, T, P, L, V, enthalpies, densities, hydraulic indicators) is derived from X and the inputs. For 40 trays and 8 components the main block has 42 × 8 = 336 states.

### 1.3 Tiers

| | Tier 1 "Textbook" | Tier 2 "Ideal + energy" | Tier 3 "Non-ideal" |
|---|---|---|---|
| VLE | constant relative volatility α_i | Raoult: K_i = P_i^sat(T)/P | polar binaries: modified Raoult with NRTL γ_i; light hydrocarbons: DePriester K(T, P) |
| Energy balance | none (constant molar overflow) | enthalpy balances on every stage | same as Tier 2 |
| Temperature | not computed in M1; from M4 a display-only Tier-2 bubble point ("T*, ideal") | bubble point | bubble point |
| Physical properties for hydraulics | constants from the preset | from component correlations (§3.5) | same as Tier 2 |
| Pressure | fixed (display only) | dynamic overhead + ΔP profile | same |

The state X is the same in all tiers, so switching tier keeps the column where it is and only changes how the derived quantities and flows are computed (§13.5).

---

## 2. Component and system data

### 2.1 Named components

Sources: critical constants, ω, T_b and ΔH_vap(T_b) from Poling, Prausnitz and O'Connell, *The Properties of Gases and Liquids*, 5th ed. (2001), Appendix A, cross-checked with the NIST Chemistry WebBook; liquid heat capacities from NIST (298 K values) with slopes fitted to NIST data between 298 K and the normal boiling point; liquid densities and surface tensions at 25 °C from the CRC Handbook. Values are rounded to the precision shown; the engine stores exactly these numbers.

| id | Name | MW (g/mol) | T_b (K) | T_c (K) | P_c (bar) | ω | ΔH_vap(T_b) (kJ/mol) | Cp_L,298 (J/mol/K) | dCp (J/mol/K²) | ρ_L,298 (kg/m³) | σ_298 (mN/m) | Psat model |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| benzene | Benzene | 78.11 | 353.24 | 562.05 | 48.95 | 0.210 | 30.72 | 135.69 | 0.22 | 873.6 | 28.2 | Antoine A |
| toluene | Toluene | 92.14 | 383.78 | 591.75 | 41.08 | 0.264 | 33.18 | 157.29 | 0.26 | 862.3 | 27.9 | Antoine A |
| methanol | Methanol | 32.04 | 337.69 | 512.50 | 80.84 | 0.565 | 35.21 | 81.1 | 0.25 | 786.6 | 22.1 | Antoine A |
| ethanol | Ethanol | 46.07 | 351.44 | 514.00 | 61.37 | 0.644 | 38.56 | 112.3 | 0.30 | 785.1 | 22.0 | Antoine A |
| water | Water | 18.015 | 373.15 | 647.10 | 220.64 | 0.345 | 40.66 | 75.3 | 0.01 | 997.0 | 72.0 | DIPPR-101 |
| acetone | Acetone | 58.08 | 329.22 | 508.10 | 47.00 | 0.307 | 29.10 | 126.3 | 0.15 | 784.5 | 23.0 | Antoine A |
| chloroform | Chloroform | 119.38 | 334.33 | 536.40 | 54.72 | 0.222 | 29.24 | 114.2 | 0.08 | 1479.0 | 26.7 | Antoine A |
| propane | Propane | 44.10 | 231.10 | 369.83 | 42.48 | 0.152 | 19.04 | 117.8 | 0.60 | 493.0 | 7.0 | Lee–Kesler |
| isobutane | Isobutane | 58.12 | 261.40 | 407.80 | 36.40 | 0.184 | 21.30 | 140.0 | 0.35 | 551.0 | 9.6 | Lee–Kesler |
| nbutane | n-Butane | 58.12 | 272.70 | 425.12 | 37.96 | 0.200 | 22.44 | 140.9 | 0.35 | 573.0 | 11.9 | Lee–Kesler |
| isopentane | Isopentane | 72.15 | 301.00 | 460.40 | 33.80 | 0.227 | 24.69 | 164.8 | 0.30 | 616.0 | 14.4 | Lee–Kesler |
| npentane | n-Pentane | 72.15 | 309.20 | 469.70 | 33.70 | 0.252 | 25.79 | 167.2 | 0.30 | 621.0 | 15.5 | Lee–Kesler |
| nhexane | n-Hexane | 86.18 | 341.90 | 507.60 | 30.25 | 0.301 | 28.85 | 195.6 | 0.30 | 655.0 | 17.9 | Lee–Kesler |
| nheptane | n-Heptane | 100.20 | 371.60 | 540.20 | 27.40 | 0.350 | 31.77 | 224.7 | 0.30 | 680.0 | 19.7 | Lee–Kesler |

Override: water uses Z_RA = 0.4945 in the Rackett ratio (§3.5.1), fitted so that ρ(100 °C) = 958.4 kg/m³; the ω-based Z_RA gives 924.6 kg/m³ (water's density is anomalous).

### 2.2 Vapour-pressure constants

**Antoine A** (log₁₀, mmHg, °C): log₁₀(P/mmHg) = A − B / (t/°C + C).

| id | A | B | C | Source | Check: T at 1 atm (°C) |
|---|---|---|---|---|---|
| benzene | 6.90565 | 1211.033 | 220.790 | Lange's Handbook (Dean); same in Beneke et al. (2013) App. B | 80.100 |
| toluene | 6.95464 | 1344.800 | 219.482 | as above | 110.625 |
| methanol | 8.07240 | 1574.990 | 238.870 | Beneke et al. (2013) Table B.4 | 64.504 |
| ethanol | 8.11220 | 1592.864 | 226.184 | Beneke et al. (2013) Table B.4 | 78.298 |
| acetone | 7.23160 | 1277.030 | 237.230 | Beneke et al. (2013) Table B.4 | 56.287 |
| chloroform | 6.93710 | 1171.200 | 227.000 | Beneke et al. (2013) Table B.4 | 61.737 |

The alcohol, ketone and chloroform sets come from the same source as the NRTL parameters in §3.4.1, so the pair (Antoine, NRTL) is used as published.

**DIPPR-101** (water; Perry's Chemical Engineers' Handbook, 8th ed., Table 2-8): ln(P/Pa) = C1 + C2/T + C3 ln T + C4 T^C5 with C1 = 73.649, C2 = −7258.2, C3 = −7.3037, C4 = 4.1653×10⁻⁶, C5 = 2. Valid 273.16–647.1 K. Checks: T_b = 100.018 °C; P(25 °C) = 3170.4 Pa; P(150 °C) = 475 089 Pa.

**Lee–Kesler** (hydrocarbons and crude pseudo-components; Lee and Kesler, AIChE J. 21 (1975) 510):

```
ln(P_sat / P_c) = f0(T_r) + ω f1(T_r)
f0(T_r) = 5.92714 − 6.09648/T_r − 1.28862 ln T_r + 0.169347 T_r^6
f1(T_r) = 15.2518 − 15.6875/T_r − 13.4721 ln T_r + 0.43577 T_r^6
```

Used for T_r ≥ 0.30. Above T_c the formula is evaluated as is (smooth extrapolation; this happens only for propane above 370 K and is flagged in the snapshot as `supercriticalComponent`).

**Range policy.** Antoine sets are fitted near 1 atm. They are used from 0.1 to 5 bar; outside that the snapshot flags `thermoOutOfRange` (no clamping, since the extrapolation is smooth).

### 2.3 System presets

| Preset id | Components | Tier-1 α (light : heavy) | Tier 3 model | Default P_top | Notes |
|---|---|---|---|---|---|
| `bt` | benzene, toluene | 2.50 : 1 | = Tier 2 (Raoult is accurate for B-T) | 1.01325 bar | Textbook pair |
| `mw` | methanol, water | 3.50 : 1 | NRTL | 1.01325 bar | Non-ideal, no azeotrope |
| `ew` | ethanol, water | 2.40 : 1 | NRTL | 1.01325 bar | Minimum-boiling azeotrope |
| `ac` | acetone, chloroform | 1.19 : 1 | NRTL | 1.01325 bar | Maximum-boiling azeotrope; Tier 1 shows a banner "Tier 1 cannot represent this system" |
| `c4` | isobutane, n-butane | 1.35 : 1 | DePriester | 7.0 bar | Close boilers (C4 splitter) |
| `debut` | propane, isobutane, nbutane, isopentane, npentane, nhexane | 5.180, 2.628, 2.041, 1.000, 0.843, 0.385 | DePriester | 6.895 bar | LK nbutane, HK isopentane |
| `deprop` | same six | 2.172, 1.000, 0.747, 0.378, 0.330, 0.157 | DePriester | 17.24 bar | LK propane, HK isobutane |
| `crude` | PC1…PC9 + water (steam) | – (Tier 1 locked) | = Tier 2 | 1.6 bar | §9 |

**Operating defaults of each preset** (M5 readiness; the steady states are VALIDATION.md VC-27 and VC-28). Every preset uses the B-T tray geometry (D_c 1.2 m, TS 0.9 m), drum 3 m³, sump 1.131 m² × 2.4 m and overhead 3 m³. Feeds are saturated liquid, F = 100 kmol/h; the steam header is 3.5 bar(g) and CW enters at 30 °C. UA values follow the procedure of §7.2 (50 % CW) and §8.2 (60 % of Q_max).

| Preset | Trays / feed tray | z (light) | P_top | L₀ (kmol/h) | Tier-1 V_B | Tier-2/3 duty | D | UA_clean (kW/K) | UA_R,clean (kW/K) | Relief set |
|---|---|---|---|---|---|---|---|---|---|---|
| `bt` | 20 / 10 | 0.50 | 1.01325 bar | 100 | 150 | 1301.5 kW (E = 1) | 50 | 29.9 | 57.5 | 3.5 bar(a) |
| `mw` | 20 / 12 | 0.30 | 1.01325 bar | 60 | 90 | 890.4 kW (T2) | 30 | 29.76 | 30.65 | 3.5 bar(a) |
| `ew` | 40 / 30 | 0.10 | 1.01325 bar | 100 | 110 | 1206.8 kW (T3, E = 1) | 10 | 28.83 | 38.98 | 3.5 bar(a) |
| `ac` | 30 / 15 | 0.60 | 1.01325 bar | 150 | 188 | 1515.9 kW (T3, E = 1) | 38 | 83.7 | 30.24 | 3.5 bar(a) |
| `c4` | 60 / 30 | 0.40 | 7.0 bar | 280 | 320 | 1542.6 kW (T2 Lee–Kesler, E = 0.7) | 40 | 122.8 | 30.15 | 10.5 bar(a) (1.5 × P_design) |
| `debut` (M7) | 32 / 16 | SCOPE.md §4.3 (light cut 0.45) | 6.895 bar | 76.4 | 121.3 | 679.7 kW (T3 DePriester, E = 0.7) | 44.94 | 38.47 | 32.02 | 10.34 bar(a) (1.5 × P_design) |
| `deprop` (M7) | 28 / 11 | SCOPE.md §4.3 (light cut 0.30) | 17.24 bar | 66.1 | 96.9 | 416.6 kW (T3 DePriester, E = 0.7) | 30.78 | 22.03 | 28.63 | 25.86 bar(a) (1.5 × P_design) |
| `bt_packed` (M8) | 2 beds × 4.5 m struct250 (9 + 9 segments) / feed stage 10 (top of the lower bed) | 0.50 | 1.01325 bar | 100 | 150 | 1300 kW (T2) | 50 (T1), 49.80 (T2) | 29.9 | 57.5 | 3.5 bar(a) |

- **Lever ranges.** SCOPE.md §4.1's flow ranges are the B-T ones. For every other preset, the flow and duty levers (and the matching FT spans) run from 0 to 2 × the preset's default. Example: the `c4` boilup goes up to 640 kmol/h, so its default of 320 is not outside the B-T range of 300.
- **`ac`** has a small condenser ΔT (57 °C distillate against 30 °C CW), hence the large UA; `c4` likewise (51 °C).
- **`c4` Tier 3** (DePriester), at the same L₀ and D: x_D 0.91129, x_B 0.05914, Q_R 1554.0 kW; at the same L₀ and the table duty: D 38.12, x_D 0.93266, x_B 0.07192 (VALIDATION.md VC-28.3, [I]). DePriester makes isobutane slightly less volatile than Lee–Kesler Raoult does (at 7 bar, α 1.36 at the top and 1.33 at the bottom, against 1.38 and 1.35 with Lee–Kesler; VALIDATION.md VC-10.9).
- **Rules for the M5 presets** (`ew`, `ac`, `c4`; `mw` keeps its M4 JSON and gains Tier 3):
  - Default tier: `ew` and `ac` Tier 3, `c4` Tier 2 (its table duty is the Tier-2 value). `mw` stays Tier 1.
  - Murphree efficiency 0.70, the sandbox rule (SCOPE.md §9). The reference cases VC-28.1, 28.2, 28.4 and scenarios G9 and G10 set E = 1.
  - Hydraulics `ideal`, as for `bt`. The `ew` and `ac` columns are not meant to show flooding.
  - Feed thermal condition: vapour fraction β = 0 (`FeedVaporFraction(0)`), i.e. saturated liquid at the feed-tray pressure. T_F then follows the pressure, which every reference at another pressure assumes (VC-28.1 at 0.5 atm, G9).
  - CW: m_cw,max = 41.54 kg/s (150 m³/h) and T_cw,in = 30 °C for every preset; the UA values in the table were sized with these.
  - Initial levers: L₀ and the duty (Tiers 2/3) or V_B (Tier 1) from the table; level SPs 50 %. A Tier-1 start uses the table's V_B and a Tier-2/3 start the table's duty; both settle near the table's D.
- **Rules for the M7 presets** (`debut`, `deprop`; M7 readiness pass 2026-10-13; prototype `tools/prototypes/m7/`, steady states in VALIDATION.md VC-9.6):
  - Default tier 3 (DePriester, the light-hydrocarbon model). The table duty is the Tier-3 value at the table L₀ and D with E = 0.7. At the same L₀ and D, Tier 2 needs 681.4 / 396.4 kW and Tier 1 needs V_B 121.34 / 96.88 kmol/h.
  - **Trays at the sandbox efficiency.** The FUG designs of VC-9.1/9.2 need 23.28 and 20.36 theoretical stages (reboiler included). Divided by E = 0.7: (23.28 − 1)/0.7 = 31.8 → 32 trays, and (20.36 − 1)/0.7 = 27.7 → 28 trays. Feed trays 16 and 11 are the Tier-3 optima of a feed-tray scan (VC-9.6). With these, the defaults sit near the design recoveries (debut 0.978 / 0.978, deprop 0.991 / 0.954), and the FUG panel compares like with like: 32 × 0.7 + 1 = 23.4 effective stages against Gilliland's 22.6–23.2 (§14.3). VC-9.3 keeps its 22-tray, E = 1 column as an explicit configuration. v1.0 had 22 / 12 and 20 / 8, the E = 1 counts; at E = 0.7 they gave only 0.943 / 0.942 (debut, Tier 3).
  - E = 0.70 (sandbox rule), hydraulics `ideal`, feed β = 0 at the feed-tray pressure, CW and steam as for the M5 presets, level SPs 50 %.
  - Keys: `debut` LK nbutane, HK isopentane; `deprop` LK propane, HK isobutane. Each pair is adjacent in volatility, as the FUG panel requires (§14.3).
  - Geometry: the B-T tray geometry, like every preset. At these vapour loads (ρ_V 15–36 kg/m³) the column runs at only about 20–25 % (`debut`) and 10–15 % (`deprop`) of jet flood, estimated by scaling the capacity factor against B-T's 63 %, so full hydraulics would weep. The default stays `ideal`; the diameter question is in OPEN_ITEMS.md.
  - dT_bub/dP for the process-driven σ of TI-100 (§10.5): `debut` 0.062 K/kPa, `deprop` 0.026 K/kPa. This is the slope of the design distillate's Tier-3 bubble point at P_top.
  - The `deprop` bottoms (≈ 124 °C) are above propane's T_c (96.7 °C). In Tier 2, Lee–Kesler extrapolates and flags `supercriticalComponent`. In all tiers the Watson λ of propane is 0 there (§3.3). With x_B,C3 ≈ 0.004 the effect on the reboiler balance is below 0.3 %. DePriester covers this range (§3.4.2).
  - The analysers read key cuts (§10.5). At the defaults AT-101 reads 0.0112 / 0.0344 and AT-102 reads 0.0102 / 0.0041, so neither reaches the 0.05 HI alarm.
- **Rules for the M8 preset** (`bt_packed`; M8 readiness pass 2026-10-13; prototype `tools/prototypes/m8/`, values in VALIDATION.md VC-13):
  - `bt_packed` is `bt` with lever `internals` = 1 (§13.4): the B-T shell (D 1.2 m), drum, sump, utilities, loops and feed, with the 20 sieve trays replaced by two beds of struct250, 4.5 m each. With HETP_ref 0.50 m (§6.2) the beds give 9 + 9 segments, so N = 18 stages. The feed enters stage 10, the top of the lower bed, through a distributor. 9 m of packing replaces 18 m of trays (20 × TS 0.9 m).
  - `designLiquidFlux` (L'_des, §6.4): 1.9 kg/m²/s for the upper bed and 4.0 for the lower bed. These are the smallest segment L' at the defaults (Tier 1: 1.924 and 4.201; Tier 2: 1.920 and 4.054), rounded down, so every segment has HETP = 0.50 m and E_O = 1 at the defaults.
  - Default tier 1, as for `bt`. Default hydraulics `full`, unlike `bt`: ΔP, flooding and the HETP modifiers are what the preset is for.
  - Feed: q = 1 (Tier 1); in Tiers 2/3, vapour fraction β = 0 at the feed-stage pressure (`FeedVaporFraction(0)`), as for the M5 presets. The bed ΔP is small (≈ 0.6 kPa above the feed), so this is within 0.2 K of `bt`'s 92.1 °C.
  - Instruments: tray-TI list `temperatureTrays` [1, 3, 5, 7, 9, 10, 12, 14, 16, 18] (five per bed, top and bottom of each; tags TI-1jj, sump TI-119); PDT-101 (column) plus PDT-102 and PDT-103 (one per bed, §10.5).
  - Steady states (L₀ 100 kmol/h): Tier 1 (V_B 150) x_D 0.99383, x_B 0.00617, column ΔP 1406 Pa, max flood 59.4 % (lower bed). Tier 2 (1300 kW) x_D 0.99339, x_B 0.01063, D 49.80 kmol/h, ΔP 1276 Pa, T_B 110.56 °C. `bt` with 20 trays at E = 0.7 gives 0.98118 (Tier 1, ideal), because 18 theoretical stages beat 20 × 0.7 = 14.
  - **H7 column** (drill H7, ENGINE_API.md §11.11): `bt_packed` in Tier 2, full hydraulics, with both beds at D_bed = 1.0 m (L'_des unchanged) and CW at 15 °C. At the defaults the lower bed runs at φ_p 0.787 and the upper at 0.675 (bed ΔP 1.61 and 1.26 kPa; x_D 0.99357, x_B 0.01108, T_B 111.09 °C). At +25 % throughput the lower bed reaches 0.975 (g = 1.25, n_th 7.55 of 9) and Q_C 1599 kW, which the condenser covers only with the colder water (1795 kW at 100 % CW and 15 °C; 1382 kW at 30 °C).
  - Templates on `bt` and `bt_packed` (lever `internals`, §13.4): 0 = 20 sieve trays (the `bt` sections); 1 = the two beds above; 2 = mixed, the upper bed (4.5 m struct250, 9 segments) above 11 sieve trays, feed on stage 10 (the first tray). Tier 1 ideal hydraulics, mixed: x_D 0.99133, x_B 0.00867.

Tier-1 α values for the non-ideal binaries are the geometric mean of the Tier-3 α at x = 0.1, 0.5 and 0.9 (1 atm); for `debut`/`deprop` they are the geometric mean of the DePriester α at the top and bottom temperatures of the FUG design case (VALIDATION.md VC-9). They are stored constants, not recomputed. (M7 check: with the corrected VC-9.5 temperatures (distillate dew 55.25 / 49.52 °C, bottoms bubble 112.77 / 123.84 °C) the recomputed geometric means agree with the stored values within 0.003.)

Tier-1 constant properties (used for hydraulics in Tier 1, and as the initial guess elsewhere):

| Preset | ρ_L (kg/m³) | ρ_V (kg/m³) | σ (N/m) | μ_L (mPa·s) |
|---|---|---|---|---|
| bt | 800 | 2.90 | 0.020 | 0.27 |
| mw | 850 | 1.00 | 0.040 | 0.35 |
| ew | 820 | 1.30 | 0.035 | 0.40 |
| ac | 1150 | 3.50 | 0.020 | 0.30 |
| c4 | 530 | 15.0 | 0.008 | 0.12 |
| debut | 560 | 15.0 | 0.009 | 0.13 |
| deprop | 470 | 36.0 | 0.005 | 0.10 |

μ_L is a per-preset constant in **all** tiers. Viscosity enters only through weak exponents (Robbins μ^0.1, packing holdup μ^(1/3), thermosyphon friction Re^−0.25), so a constant is honest at this fidelity.

---

## 3. Thermodynamics

### 3.1 Tier 1 — constant relative volatility, CMO

For component i with constant α_i (the heaviest key has α = 1):

```
y*_ij = α_i x_ij / Σ_k α_k x_kj                       (3.1)
```

Binary form: y* = α x / (1 + (α − 1) x). Constant molar overflow means vapour flow changes only where feed vapour enters (§4.4). No temperatures, enthalpies or pressure effects on VLE. Hydraulic properties are the preset constants in §2.3; liquid molar volume is v_L = Σ_i x_i MW_i / (1000 ρ_L) with the preset ρ_L.

### 3.2 Tier 2 — Raoult's law

```
K_i(T, P) = P_i^sat(T) / P                            (3.2)
```

P_i^sat from §2.2. Vapour is an ideal gas for equilibrium (fugacity coefficients = 1); vapour density uses a virial Z (§3.5.2). Poynting corrections are neglected (under 1 % for the low-pressure systems, a few % for the depropanizer; Tier 3 DePriester K-values include pressure effects empirically).

### 3.3 Enthalpy model (Tiers 2 and 3)

Reference state: each pure component as liquid at T₀ = 298.15 K has h = 0.

```
h_L,i(T) = Cp0_i (T − T0) + ½ dCp_i (T − T0)²                     (3.3)
ΔH_vap,i(T) = ΔH_vap,i(T_b,i) · [ (T_c,i − T) / (T_c,i − T_b,i) ]^0.38   for T < T_c,i ; 0 otherwise   (3.4, Watson)
h_V,i(T) = h_L,i(T) + ΔH_vap,i(T)                                  (3.5)
h_L(T, x) = Σ_i x_i h_L,i(T)      H_V(T, y) = Σ_i y_i h_V,i(T)       (3.6)
```

Path: heat the liquid to T, then vaporise at T. This is exact for an ideal system if Cp and ΔH_vap are consistent; with these correlations the implied vapour Cp (Cp_L + dΔH_vap/dT) is within about 10 % of the true ideal-gas value (benzene at 353 K: 92 vs about 96 J/mol/K). Heat of mixing is neglected in all tiers (ethanol–water |h^E| ≲ 0.8 kJ/mol, about 2 % of the latent heat). These two simplifications are stated in the math overlay.

### 3.4 Tier 3

#### 3.4.1 NRTL (polar binaries)

Renon and Prausnitz, AIChE J. 14 (1968) 135. For components i, j:

```
τ_ij = a_ij + b_ij / T          G_ij = exp(−α_ij τ_ij)          τ_ii = 0, G_ii = 1
ln γ_i = [Σ_j x_j τ_ji G_ji] / [Σ_k x_k G_ki]
       + Σ_j { x_j G_ij / [Σ_k x_k G_kj] · ( τ_ij − [Σ_m x_m τ_mj G_mj] / [Σ_k x_k G_kj] ) }      (3.7)
K_i = γ_i P_i^sat(T) / P                                                                         (3.8)
```

Binary form (1 = first component listed):

```
ln γ1 = x2² [ τ21 (G21/(x1 + x2 G21))² + τ12 G12 / (x2 + x1 G12)² ]
ln γ2 = x1² [ τ12 (G12/(x2 + x1 G12))² + τ21 G21 / (x1 + x2 G21)² ]
```

Parameters (T in K) from Beneke, Peters, Glasser and Hildebrandt, *Understanding Distillation Using Column Profile Maps*, Wiley (2013), Appendix B, Tables B.1–B.3 (regressed Dortmund Data Bank values via Aspen Plus):

| i – j | a_ij | a_ji | b_ij (K) | b_ji (K) | α_ij |
|---|---|---|---|---|---|
| methanol – water | −0.693 | 2.732 | 173.0 | −617.3 | 0.3 |
| ethanol – water | −0.801 | 3.458 | 246.2 | −586.1 | 0.3 |
| acetone – chloroform | 0.965 | 0.538 | −590.0 | −106.4 | 0.3 |

With the vapour-pressure models of §2.2 these give: ethanol–water azeotrope x = 0.8956, 78.14 °C at 1 atm (experiment 0.894, 78.15 °C); acetone–chloroform maximum-boiling azeotrope x_acetone = 0.3335, 64.61 °C (experiment ≈ 0.34, 64.4 °C); methanol–water y = 0.4223 at x = 0.10 (experiment 0.418). See VALIDATION.md VC-10.

**Validation and sources (M5 readiness, 2026-10-12).** The parameters are Dortmund Data Bank regressions (via Aspen Plus, tabulated by Beneke et al. 2013), which is the same family of fits as the DECHEMA Chemistry Data Series; the DECHEMA tables themselves are not openly available, so the check is against experiment. An independent re-implementation reproduces every VC-10.4–10.6 value to the printed digits:
- ethanol–water: azeotrope 0.8956 / 78.141 °C at 1 atm, against Horsley (1973) and the CRC Handbook: 95.57 wt% ethanol = x 0.8947, 78.15 °C;
- acetone–chloroform: maximum-boiling azeotrope 0.3334 / 64.61 °C, against Horsley: 20 wt% acetone ≈ x 0.34, 64.4–64.7 °C;
- methanol–water: Perry's VLE to ± 0.01 in y.

**Pressure dependence is qualitative.** The azeotrope moves the right way: ethanol–water 0.9292 at 0.2 atm, 0.9105 at 0.5 atm, 0.8713 at 3 atm; acetone–chloroform 0.359 at 0.5 atm, 0.246 at 3 atm. But the 1-atm parameters keep the ethanol–water azeotrope down to at least 0.08 atm (x 0.946), whereas experiments have it vanishing below about 70 mmHg (≈ 0.09 atm). Scenarios and debriefs may say "lower pressure moves the azeotrope to more ethanol"; they must not say "vacuum breaks it" (G9).

**Bubble-point Newton.** γ depends on T only through τ, and inside the bubble-point Newton dγ/dT is ignored (§3.6). Convergence is then linear when τ varies strongly with T: acetone–chloroform has b_ij = −590 K. Measured on a 2001-point grid at 0.1, 1 and 5 atm, with the cold guess Σ x_i T_sat,i(P) and no fallback anywhere:

| System | Cold start | Warm start |
|---|---|---|
| ethanol–water, methanol–water | ≤ 6 iterations | ≤ 5 |
| acetone–chloroform | ≤ 7 iterations (25 % of points need 7) | ≤ 6 |

The 20-iteration cap of §3.6.1 is ample.

#### 3.4.2 DePriester K-values (light hydrocarbons)

Ships in M5 (`c4`); the multicomponent presets use it from M7. McWilliams, Chem. Eng. 80(25) (1973) 138, fit of the DePriester (1953) charts; table as reproduced in Seader, Henley and Roper, *Separation Process Principles*. T_R in °R (T_R = 1.8 T), p in psia (p = P / 6894.757):

```
ln K = a_T1 / T_R² + a_T2 / T_R + a_T6 + a_p1 ln p + a_p2 / p² + a_p3 / p          (3.9)
```

| id | a_T1 | a_T2 | a_T6 | a_p1 | a_p2 | a_p3 |
|---|---|---|---|---|---|---|
| propane | −970 688.5625 | 0 | 7.15059 | −0.76984 | 0 | 6.90224 |
| isobutane | −1 166 846 | 0 | 7.72668 | −0.92213 | 0 | 0 |
| nbutane | −1 280 557 | 0 | 7.94986 | −0.96455 | 0 | 0 |
| isopentane | −1 481 583 | 0 | 7.58071 | −0.93159 | 0 | 0 |
| npentane | −1 524 891 | 0 | 7.33129 | −0.89143 | 0 | 0 |
| nhexane | −1 778 901 | 0 | 6.96783 | −0.84634 | 0 | 0 |
| nheptane | −2 013 803 | 0 | 6.52914 | −0.79543 | 0 | 0 |

Note: some online copies list a_p1 = −0.93159 for n-butane; that is a transcription error (it duplicates isopentane and gives K = 1.24 instead of 1.06 at 150 °F, 100 psia, where Raoult gives 1.05). Use −0.96455.

Validity: 365–852 °R (−70 to 200 °C) and 14.7–870 psia (101.3–6000 kPa), as Seader, Henley and Roper state for the fit. Outside that range, evaluate the formula as it is (smooth extrapolation, as for Lee–Kesler in §2.2) and set `thermoOutOfRange`. **M7 correction:** v1.0 gave 700 °R and clamping. 700 °R is 115.6 °C, which is below the depropanizer bottoms (≈ 124 °C, 715 °R). A clamped T also makes K independent of T, so the bubble-point Newton has g' = 0: the M7 prototype's depropanizer bottoms bubble point ran away to 514 °C. VC-9.4 (n-hexane at 250 °F) and VC-9.5 (depropanizer bottoms) were already computed with the formula unclamped. The `c4` defaults (≈ 50–65 °C at 7 bar) lie inside both ranges, so nothing in M5 changes. K depends on T and P only (no composition dependence), which is why DePriester charts are fast; the non-ideality they capture is the pressure effect on light hydrocarbons near their critical points.

#### 3.4.3 Crude

Tier 3 = Tier 2 for crude: pseudo-components are hydrocarbon mixtures with near-ideal mixing, and the column runs at 1–2.5 bar.

### 3.5 Physical properties (Tiers 2 and 3)

#### 3.5.1 Liquid density — Rackett ratio

```
Z_RA,i = 0.29056 − 0.08775 ω_i            (override for water: 0.4945)
ρ_L,i(T) = ρ_ref,i · Z_RA,i ^ [ (1 − T_ref/T_c,i)^(2/7) − (1 − T/T_c,i)^(2/7) ]        (3.10)
v_L(T, x) = Σ_i x_i MW_i / (1000 ρ_L,i(T))        ρ_L = (Σ_i x_i MW_i / 1000) / v_L        (3.11)
```

T_ref = 298.15 K for named components, 288.71 K (60 °F) for pseudo-components. Checks: benzene 816.4 kg/m³ at 80 °C (literature 815); toluene 779.9 at 110 °C (780).

#### 3.5.2 Vapour density — Pitzer virial

```
ρ_V = P · MW_V / (1000 Z R T)      MW_V = Σ y_i MW_i
Z = 1 + (B0 + ω_m B1) P_r / T_r      B0 = 0.083 − 0.422/T_r^1.6      B1 = 0.139 − 0.172/T_r^4.2      (3.12)
T_r = T / Σ y_i T_c,i     P_r = P / Σ y_i P_c,i     ω_m = Σ y_i ω_i      (Kay's rule)
Z is clamped to [0.30, 1.05].
```

For steam (crude) water's constants are used in the mixing. Checks: saturated benzene vapour at 1 atm Z = 0.966; C4 vapour at 7 bar, 330 K Z = 0.860. This correction matters for flooding at the hydrocarbon presets (ρ_V enters U_nf as √(1/ρ_V)).

#### 3.5.3 Surface tension

```
σ_i(T) = σ_ref,i · [ (T_c,i − T) / (T_c,i − T_ref) ]^1.22          (named components)
σ_i(T) = (673.7 / K_W) · [ (T_c,i − T) / T_c,i ]^1.232  mN/m        (pseudo-components; Riazi 2005)
σ_mix^(1/4) = Σ_i x_i σ_i^(1/4)                                    (3.13)
```

The quarter-power average reduces, but does not remove, the overestimate for aqueous–organic mixtures (surface enrichment of the organic is not modelled). σ enters flooding as σ^0.2 and wetting weakly.

#### 3.5.4 Viscosity

Per-preset constant μ_L (§2.3). Not temperature dependent (see the reason in §2.3).

### 3.6 Bubble point, dew point, flash

#### 3.6.1 Bubble temperature (the workhorse; called for every stage every step)

Solve g(T) = ln(Σ_i K_i(T, P, x) x_i) = 0.

```
Start:   T = T_j^n (previous value of this stage)  [cold: mole-fraction average of pure-component T_sat(P)]
Newton:  S = Σ K_i x_i ;   g = ln S ;   g' = Σ (K_i x_i · d ln K_i/dT) / S ;   T ← T − g / g'
         with |ΔT| clamped to 30 K per iteration
Stop:    |ΔT| < 1×10⁻⁶ K  or |g| < 1×10⁻¹⁰ ;  max 20 iterations
Fallback: bisection on [T_lo, T_hi] = [150 K, 0.98 · min_i T_c,i] for Antoine-based K (Raoult, NRTL)
          and [150 K, 900 K] for Lee–Kesler, DePriester and crude (M5, 2026-10-13); 60 iterations;
          set solverHealth.bubbleFallbacks += 1. Check g(T_lo) < 0 < g(T_hi) before bisecting; with no
          sign change keep the Newton iterate of smallest |g|, count the fallback and set thermoOutOfRange
Output:  T, K_i, y*_i = K_i x_i / S   (normalised)
```

**Fallback bracket (M5 validation, 2026-10-13).** 0.98 · min T_c lies below real bubble points as soon as a light component is supercritical there: `debut` bottoms 385.9 K and `deprop` bottoms 397.0 K against 0.98 T_c,propane = 362.4 K, and `c4` at 25 bar 417.7 K against 399.6 K. A fallback would then have returned the bracket end without a warning. Lee–Kesler and DePriester extrapolate smoothly above T_c (§2.2, §3.4.2), so 900 K brackets them. Newton has converged on every tested point, so this matters only if the fallback ever runs.

d ln K_i / dT (γ treated as constant in the derivative):

| Model | d ln K / dT |
|---|---|
| Antoine A | ln(10) · B / (T − 273.15 + C)² |
| DIPPR-101 | −C2/T² + C3/T + C4·C5·T^(C5−1) |
| Lee–Kesler | (1/T_c) [6.09648/T_r² − 1.28862/T_r + 1.016082 T_r⁵ + ω (15.6875/T_r² − 13.4721/T_r + 2.61462 T_r⁵)] |
| DePriester | 1.8 · (−2 a_T1 / T_R³ − a_T2 / T_R²) |

Steam present (crude): the hydrocarbon liquid boils at its partial pressure, so use P_HC = P (1 − y_w) in K_i = P_i^sat/P_HC for hydrocarbons, where y_w is the steam mole fraction in the vapour leaving the stage, taken from the previous step (§9.3).

#### 3.6.2 Dew temperature

Solve ln(Σ_i y_i / K_i) = 0, same Newton/bisection pattern. For NRTL iterate x = (y_i/K_i)/Σ and recompute γ (successive substitution, max 30 iterations, tolerance 1×10⁻⁹ on x).

#### 3.6.3 Isothermal flash and feed condition

Rachford–Rice for vapour fraction β at given T, P, z:

```
f(β) = Σ_i z_i (K_i − 1) / (1 + β (K_i − 1)) = 0,   β ∈ [0, 1]       (3.14)
```

Solve with Newton safeguarded by bisection (f is monotone decreasing). If f(0) < 0 the feed is subcooled (β = 0); if f(1) > 0 superheated (β = 1). For NRTL iterate x_i = z_i/(1 + β(K_i − 1)), y_i = K_i x_i, update γ(x) and repeat until max |Δx| < 1×10⁻⁹.

Thermal condition (Tiers 2/3), computed at the feed-tray pressure:

```
q = (H_V,sat − h_F) / (H_V,sat − h_L,sat)                              (3.15)
h_L,sat = h_L(T_bub(z), z)      H_V,sat = H_V(T_dew(z), z)      h_F = (1 − β) h_L(T_F, x) + β H_V(T_F, y)
```

q > 1 subcooled, 0 < q < 1 two-phase, q < 0 superheated. In Tier 1, q is the lever.

---

## 4. Stage model (MESH dynamics)

### 4.1 Component balances

For tray j (1 ≤ j ≤ N), with all flow symbols as in §0.3 and S_j a liquid side draw:

```
dm_ij/dt = (1 − f_j) L_{j−1} x_{i,j−1} + f_{j−1} L_{j−2} x_{i,j−2}
         + V_{j+1} y_{i,j+1} + e_{j+1} x_{i,j+1}
         + Σ_feeds F_j z_ij + Σ_returns R_j r_ij
         − (L_j + e_j + S_j) x_ij − V_j y_ij                                   (4.1)
```

- `f_j` is the **bypass fraction** of tray j: the fraction of the liquid arriving from the downcomer above that falls through the deck at the tray inlet without crossing it (weeping, §5.8; plus the opening of a broken tray, §11). That liquid lands on tray j+1 with the composition it arrived with, x_{j−1}. W_j = f_j L_{j−1} is the bypass flow. For j = 1 the arriving liquid is the reflux (L_0, x_0), and f_0 = 0; the bypass of tray N lands in the sump.
- Because bypassed liquid keeps its inlet composition, weeping costs efficiency even in a perfectly mixed tray model. This is the inlet-weeping mechanism (Billingham, Banik and Lockett, AIChE Annual Meeting 1994, "The effect of inlet weeping on distillation tray efficiency").
- The bypass couples tray j−2 to tray j, so the component solve has one extra sub-diagonal (§12.3). Treating it implicitly is what keeps it conservative and positive: in prototyping, an explicit (lagged-composition) bypass leaked 0.9 % of a component per hour on a tray with almost no holdup (missing tray).
- `R_j r_ij` are liquid returns (pumparound return, §9.5) and vapour returns (side-stripper vapour, §9.4).
- Feeds always enter the tray's balance as a whole; the tray (an equilibrium mixing stage) splits them. In Tier 1 the vapour fraction (1 − q)F is added to V_j by CMO (§4.4); in Tiers 2/3 the feed enthalpy enters the energy balance (§4.5).

Total holdup: dM_j/dt = Σ_i (4.1), using Σ_i x_ij = Σ_i y_ij = 1.

### 4.2 Murphree vapour efficiency

```
y_ij = y_{i,j+1} + E_j^eff ( y*_ij − y_{i,j+1} )                              (4.2)
E_j^eff = E_j · (1 − b_V,j) · min(1, h_cl,j / 0.005 m)
```

- E_j: lever value (global) times fault multipliers; packed segments get E from HETP (§6.4).
- b_V,j: vapour bypass fraction (broken-tray fault, §11), vapour passing uncontacted.
- min(1, h_cl/5 mm): a tray with almost no liquid cannot contact vapour (dry or dumped tray).
- The reboiler (j = N+1) is an equilibrium stage: y_{N+1} = y*_{N+1}.
- The vapour leaving a tray is at the tray liquid temperature T_j, whatever its composition (standard assumption).

Overall-to-Murphree (Lewis, Ind. Eng. Chem. 28 (1936) 399), used for packed segments and in the math overlay, with stripping factor λ = m V / L (m = local slope of the equilibrium curve, dy*/dx; the exact definition used for packed segments is λ_k of §6.4):

```
E_O = ln[1 + E_MV (λ − 1)] / ln λ          E_MV = (λ^E_O − 1) / (λ − 1)          (λ → 1: E_O = E_MV)    (4.3)
```

O'Connell (Trans. AIChE 42 (1946) 741) estimate shown in the overlay as a reality check: E_O ≈ 0.492 (μ_L[cP] · α)^−0.245.

### 4.3 Normalised K for the implicit solve

The component solve (§12.3) needs a linear relation between y* and x. At the start of the step:

```
K̃_ij = K_ij / Σ_k K_kj x^n_kj         (so Σ_i K̃_ij x^n_ij = 1 exactly)          (4.4)
Tier 1: K̃_ij = α_i / Σ_k α_k x^n_kj
y*_ij ≈ K̃_ij x_ij^(n+1)
```

At steady state x^(n+1) = x^n, so the linearisation is exact there; during transients it is a first-order-accurate lag of the nonlinearity, which the prototype showed to be stable at all tested steps (0.25–30 s).

### 4.4 Vapour flows, Tier 1 (CMO)

```
V_{N+1} = V_B · s_sump            (boilup lever; s_sump = sump-starvation factor §8.1)
V_j     = max(0, V_{j+1} + (1 − q_j) F_j)        j = N … 1                          (4.5)
```

(1 − q)F is negative for subcooled feed (q > 1): the feed condenses vapour.

### 4.5 Vapour flows, Tiers 2/3 (quasi-steady energy balance)

Energy balance on tray j, liquid holdup only (vapour holdup neglected):

```
d(M_j h_j)/dt = L_{j−1} h_{j−1} + V_{j+1} H_{j+1} + F_j h_F,j + Q_j + (other in) − L_j h_j − V_j H_j − (other out)
```

Subtract h_j × (total material balance). The unknown L_j cancels, which is why this form is used:

```
V_j = [ L_{j−1}(h_{j−1} − h_j) + V_{j+1}(H_{j+1} − h_j) + F_j (h_F,j − h_j)
      + e_{j+1}(h_{j+1} − h_j) + f_{j−1} L_{j−2}(h_{j−2} − h_j) − f_j L_{j−1}(h_{j−1} − h_j)
      + Σ R_j (h_R − h_j) + Q_j
      − C_j τ_j (P_top^(n+1) − P_top^n) / dt ] / (H_j − h_j)                              (4.6)

C_j = M_j · Cp_L,j + m_metal,j · 500 J/(kg·K)            (sensible heat of liquid + tray metal)
m_metal,j = 75 kg/m² × A_T  (tray, shell share and supports)
τ_j = (∂T_j/∂P)|_x = S_j / (P_j Σ_i K_ij x_ij (d ln K_ij/dT))    (bubble-point sensitivity at state n, S_j = Σ_i K_ij x_ij;
      the bubble-point Newton of §3.6.1 already computes the denominator; B-T near 1 atm ≈ 3.3×10⁻⁴ K/Pa)
```

- Evaluated bottom-up (j = N … 1) with all enthalpies and T at the start of the step, L_{j−1} and the other liquid flows from the previous step, and V_{j+1} just computed. One sweep, no iteration.
- H_j uses the vapour actually leaving (y_j at T_j). The two bypass terms come from the bypass split of §4.1: tray j receives (1 − f_j) L_{j−1} from above plus the liquid f_{j−1} L_{j−2} that fell through tray j−1.
- **The storage term** makes the column flash when the pressure falls and absorb vapour when it rises. It is written for the temperature change caused by the pressure change *within this step*, and it is **implicit**: P_top^(n+1) is the unknown of the overhead pressure solve (§7.4), which re-runs this bottom-up sweep for every trial pressure. Pressure is uniform up to the tray ΔP, which does not change within a step, so P_j^(n+1) − P_j^n = P_top^(n+1) − P_top^n.
- **Why implicit (M4 prototype finding).** v1.0 used the lagged change C_j (T_j^n − T_j^(n−1))/dt with a bound of 0.5 × numerator per tray. In the prototype that coupling was unstable from the first step at dt = 0.5 s: a 4 kPa dip flashed about 135 mol/s the next step, the pressure jumped 60 kPa, and the column ran away to 15 bar with V_B = 0. The 0.5 bound does not help, because it compounds up 20 trays. The column's liquid and metal act as a vapour capacitance Σ C_j τ_j/λ ≈ 0.016 mol/Pa, about 16 times the overhead gas volume (≈ 0.001 mol/Pa). Coupled explicitly to an implicit pressure solve, that has a loop gain far above 1. Made implicit, the same physics gives the right result: a pressure time constant of about 2.5 min (open-loop CW step), and identical steady states at dt = 0.5, 2 and 30 s.
- Composition-driven temperature changes are not in the storage term. They are slow (a few K over 10 min, under 1 kW per tray against about 1300 kW through the column), and leaving them out keeps the sweep a pure function of P^(n+1). At steady state the term is zero in either form.
- V_j is clamped to ≥ 0.
- At steady state the storage term is zero and (4.6) is the exact steady energy balance, so energy closure at steady state is exact (VALIDATION.md VC-11).

Sump/reboiler (j = N+1):

```
V_{N+1} = s_sump · [ L_N (h_N − h_B) + f_N L_{N−1} (h_{N−1} − h_B) + Q_R,delivered − C_B τ_{N+1} (P^(n+1) − P^n)/dt ] / (H_B − h_B)   (4.7)
C_B = M_{N+1} Cp_L,B          (sump liquid only; reboiler and sump metal neglected)
```

Why quasi-steady energy: the energy states are fast compared with composition (seconds), and treating V as algebraic removes the stiffest part of the system while keeping the physically important non-CMO effects (latent-heat differences, subcooled reflux, feed enthalpy) and the heat storage that matters for pressure transients.

### 4.6 Liquid flows

L_j comes from tray hydraulics (§5) or packing hydraulics (§6). It is solved together with the holdup in the implicit hydraulic step (§12.2). In "ideal hydraulics" mode (M1 and textbook scenarios) only the Bennett weir relation of §5.3 is used: no ΔP, no entrainment, no weeping, no downcomer limit, no flooding.

### 4.7 Stage temperature and pressure

T_j = bubble point of x_j at P_j (§3.6.1), computed at the end of each step. In Tier 1, T is not part of the model.

---

## 5. Tray hydraulics

All tray hydraulic quantities are computed per tray from the state at the start of the step (`state n`), except where §12.2 says the quantity is part of the implicit holdup solve (the weir flow and the dump drain).

### 5.1 Geometry

Inputs per tray section (defaults for the B-T preset in brackets):

| Input | Symbol | Default |
|---|---|---|
| Column diameter | D_c | 1.20 m |
| Tray spacing | TS | 0.90 m (v1.1; was 0.60 m, see below) |
| Downcomer area fraction | f_d = A_d/A_T | 0.12 |
| Weir height | h_w | 0.050 m |
| Downcomer clearance (apron) | h_ap | 0.038 m |
| Sieve: hole area / active area | f_h | 0.10 |
| Sieve: hole diameter | d_h | 0.0127 m |
| Sieve: orifice coefficient | C₀ | 0.73 |
| Valve: full-open slot area / active area | f_v | 0.14 |
| Valve: closed-valve area / full-open area | r_min | 0.25 |
| Valve: balancing (lift) pressure drop | ΔP_lift | 190 Pa |
| Valve: orifice coefficient | C_v | 0.65 |
| Downcomer froth density (aeration) | φ_dc | 0.5 |
| System (foaming) factor | SF | 1.0 |

**Why TS = 0.90 m (v1.1, 2026-10-12).** With 0.60 m spacing the default column ran at 83 % of jet flood. VC-8.1's "+10 kmol/h on L₀ and V_B" then reached 89 %, and xD *fell* (0.9673 → 0.9583): the tray-1 entrainment carried into the drum raises D under LV control, D = V₁ + e₁ − L₀. The physics is real, but the learner's first slider pull would contradict the textbook. Options compared with the engine:

| Option | Design max flood | VC-8.1 xD | Other effects |
|---|---|---|---|
| D_c 1.4 m | 60.9 % | rises | Φ_min falls to 1.10, so weeping starts at about two-thirds load; ideal-mode holdups change, and VC-7.1 and VC-7.4 fail (cold start 6.3 h > 6 h) |
| D_c 1.3 m, TS 0.75 m | 60.7 % | rises | Φ_min 1.33; ideal-mode dynamics shift |
| TS 0.75 m | 71.3 % | still falls | |
| **TS 0.90 m** | **62.9 %** | **0.97826 → 0.98001** | Tray spacing enters only jet flood (C_SB), the froth-fill limit M_max and the downcomer limit. Every ideal-hydraulics number (VC-3 to VC-7, xD 0.981183), all weeping and turndown behaviour and the pressure drop (14.49 kPa vs 14.68) stay as they were |

0.9 m (36 in) is on the generous side for a 1.2 m column, but it is a standard spacing, and it buys the headroom without touching anything a textbook scenario measures.

Derived:

```
A_T = π D_c² / 4      A_d = f_d A_T      A_n = A_T − A_d (net, for flooding)      A_a = A_T − 2 A_d (active)
θ solves (θ − sin θ)/(2π) = f_d          (Newton from θ = 2.0)
L_w = D_c sin(θ/2)                         (weir length; 0.9171 m for the defaults)
A_h = f_h A_a  (sieve)
```

### 5.2 Vapour loading

For tray j, vapour enters from below at V_{j+1} (composition y_{j+1}) and leaves at V_j:

```
Q_in  = V_{j+1} MW_V(y_{j+1}) / (1000 ρ_V)        Q_out = V_j MW_V(y_j) / (1000 ρ_V)        (m³/s)
U_s   = Q_in / A_a              (superficial velocity over the bubbling area)
K_s   = U_s √(ρ_V / (ρ_L − ρ_V))                                                         (5.1)
```

ρ_L, ρ_V and σ are evaluated at tray j (Tier 1: preset constants).

### 5.3 Clear-liquid height and weir flow (Bennett)

Bennett, Agrawal and Cook, AIChE J. 29 (1983) 434:

```
α_e = exp(−12.55 K_s^0.91) · SF_froth                (effective froth density)
C   = 0.501 + 0.438 exp(−137.8 h_w)
h_cl = M_j v_L / A_a                                  (clear-liquid height from the holdup)
q_w = L_w α_e [ (h_cl/α_e − h_w) / C ]^1.5   if h_cl > α_e h_w,   else 0      (m³/s)          (5.2)
L_weir = q_w / v_L                                                                       (mol/s)
dL_weir/dM = 1.5 L_w [ (h_cl/α_e − h_w)/C ]^0.5 / (C · A_a)                    (for the Newton solve)
```

This is a Francis-type weir on aerated liquid. Its useful property: when the vapour rate rises, α_e falls, the froth expands and the same holdup pushes more liquid over the weir. That is the real "inverse response" of tray hydraulics and comes for free. SF_froth = 1 normally, < 1 when foaming (§11).

Typical values at the B-T default (V = 150 kmol/h): α_e ≈ 0.26, h_cl ≈ 21 mm, holdup ≈ 190 mol per tray, liquid residence ≈ 7 s.

Bennett's correlation was fitted to air–water data and tends to under-predict clear-liquid height on valve trays; LowSYS accepts this because the holdup only sets time constants, which remain realistic (seconds per tray).

### 5.4 Dry and total tray pressure drop

Sieve tray (orifice equation):

```
u_h = Q_in / A_h,eff          ΔP_dry = (ρ_V / 2) (u_h / C₀)²                          (5.3)
```

A_h,eff = A_h × (1 − 0.8 s_foul) under fouling (§11).

Valve tray (three regimes, after Bolles 1976):

```
A_min = r_min f_v A_a          A_max = f_v A_a
closed:     ΔP_c = (ρ_V/2) (Q_in / (C_v A_min))²
if ΔP_c < ΔP_lift:               ΔP_dry = ΔP_c                      (valves closed, A_eff = A_min)
else  A_bal = Q_in / (C_v √(2 ΔP_lift / ρ_V))
      if A_bal ≤ A_max:          ΔP_dry = ΔP_lift                   (valves balancing, A_eff = A_bal)
      else                       ΔP_dry = (ρ_V/2) (Q_in / (C_v A_max))²   (fully open)            (5.4)
```

Total tray drop and the pressure profile:

```
ΔP_σ = 4 σ / d_h                     (bubble-formation residual; valve trays use d_h = 0.040 m)
ΔP_j = ΔP_dry + (1 − s_broken,j) ρ_L g h_cl + ΔP_σ                                   (5.5)
P_1 = P_top        P_{j+1} = P_j + ΔP_j        P_{N+1} = P_N + ΔP_N
```

(ρ_L g h_cl is the hydrostatic head of the froth: the clear-liquid equivalent.) In ideal-hydraulics mode ΔP_j = 0. The factor (1 − s_broken,j) (F04, §11; DEVIATIONS.md E20) is there because an open deck holds no liquid head. The small liquid it still carries sits on the 2 % residual active area A_a,eff, where h_cl = M v_L/A_a,eff would otherwise look like a large head; without the factor a fully broken tray kept 18.7 % of its pressure drop instead of about 6 %.

### 5.5 Jet flooding (Fair)

Fair, Petro/Chem Engineer 33(10) (1961) 45; curve fit by Lygeros and Magoulas, Hydrocarbon Processing 65(12) (1986) 43. The fit reproduces Fair's chart at 24-in spacing (C_SB = 0.094 m/s at F_LV = 0.1 versus about 0.30 ft/s = 0.091 m/s read from the chart).

```
F_LV = (L̄_j · MW_L / (V_j · MW_V)) √(ρ_V / ρ_L)     clamped to [0.01, 2.0]
C_SB = 0.0105 + 8.127×10⁻⁴ · TS_mm^0.755 · exp(−1.463 F_LV^0.842)           (m/s, TS in mm)
f_hole = 1                                 if A_h,eff/A_a ≥ 0.10
       = max(0.5, 5 A_h,eff/A_a + 0.5)       otherwise                         (Fair's hole-area correction; fouling lowers it)
U_nf = C_SB (σ / 0.020)^0.2 √((ρ_L − ρ_V)/ρ_V) · SF · f_hole                  (m/s)
φ_j  = (Q_out / A_n) / U_nf          (fractional approach to jet flood)              (5.6)
```

L̄_j is the liquid load filtered with a first-order lag (τ = 10 s): dL̄_j/dt = (L_j − L̄_j)/10. **Why:** F_LV feeds back from liquid flow to entrainment to liquid flow; using the raw lagged L made the hydraulics oscillate in prototyping.

### 5.6 Entrainment

Fractional entrainment ψ = e / (L + e). LowSYS uses a smooth fit anchored to Fair's (1961) entrainment chart (ψ ≈ 0.01 at 50 % flood and 0.3–0.5 at 95 % flood for F_LV = 0.01; ψ ≈ 0.03–0.04 at 90 % and 0.07 at 100 % flood for F_LV = 0.1; much lower at F_LV ≥ 0.5). The chart itself is uncertain to about a factor of two; this fit stays inside that band from 40 % to 110 % flood:

```
ψ_eq = min(ψ_max, 4.0×10⁻⁵ · (F_LV / 0.1)^−0.83 · exp(7.5 φ_j))          ψ_max = 0.60       (5.7)
dψ_j/dt = (ψ_eq − ψ_j) / τ_ψ          τ_ψ = 5 s                         (filter; state)
e_j = ψ_j / (1 − ψ_j) · L_j^n  +  e_ov,j                                                   (5.8)
e_j ≤ 0.3 M_j / dt                                                         [safeguard]
```

Entrained liquid has the tray's composition and goes to the tray above (from tray 1: into the overhead line, i.e. the reflux drum). The separation loss from entrainment is therefore *emergent*: the same recycle physics from which Colburn's (Ind. Eng. Chem. 28 (1936) 520) formula E_a = E_MV / (1 + E_MV ψ/(1 − ψ)) is derived. The overlay shows E_a for explanation; the model does not apply it separately.

ψ_max = 0.6 bounds the recycle ratio ψ/(1−ψ) at 1.5. Prototyping with ψ_max = 0.95 (ratio 19) made the explicit entrainment coupling unstable. Above jet flood the "full tray" overflow below carries the rest.

**Full-tray overflow (flooding).** The froth cannot be taller than the tray spacing:

```
M_max,j = TS · α_e · A_a / v_L
e_ov,j  = (M_j − M_max,j) / max(τ_c, 4 dt)   if M_j > M_max,j and Φ_j ≥ 0.2 (vapour present),  else 0      (5.9)
τ_c = 5 s
```

Liquid pushed above a full tray accumulates on the tray above, so flooding propagates upward over minutes. A flooded column carries liquid into the drum: xD drops and the drum level rises — the textbook symptoms.

**How the two floods look.** In this model, *jet* flood (φ ≥ 1) happens through entrainment recycle: ψ climbs towards ψ_max = 0.6 while the froth fill M/M_max is still only about 0.35. The trays do not fill to the spacing; liquid is sprayed up and carried over (at tray 1, into the drum). *Downcomer* flood and full-tray overflow (dc fraction ≥ 1, M ≥ M_max) are the cases where froth really stacks up to the tray above. The column painter must draw them differently (ENGINE_API.md §13.5).

**Carryover into the drum** is why VC-8.1 depends on headroom. Under LV control the drum receives V₁ + e₁, so D = V₁ + e₁ − L₀ rises with e₁. In a near-balanced split (D/F ≈ z) each extra kmol/h of D costs about 0.01 in xD. With D held constant, raising L₀ and V_B improves xD all the way to flood (VALIDATION.md VC-8.16).

### 5.7 Downcomer backup

Downcomer j carries liquid from tray j to tray j+1. Liquid in it must balance the tray-j pressure drop, the liquid head on tray j+1 and the head loss under the apron (Coulson and Richardson, *Chemical Engineering* Vol. 6 (Sinnott), §11.13: h_dc = h_t + h_w + h_ow + h_dc,apron with h_apron = 166 (L_wd/(ρ_L A_m))² mm):

```
u_ap   = q / (L_w h_ap,eff)                         (velocity under the apron)
h_dc,j = ΔP_j / (ρ_L g) + h_norm,j+1 + 0.166 u_ap²          (m of clear liquid)
downcomer flood when h_dc,j / φ_dc ≥ TS + h_w                                         (5.10)
```

Liquid-rate cap (solved for q):

```
head_j  = φ_dc (TS + h_w) − ΔP_j/(ρ_L g) − h_norm,j+1
L_max,j = L_w h_ap,eff √(max(head_j, 0) / 0.166) / v_L                                 (5.11)
```

- All terms are evaluated at state n.
- h_norm,j+1 is the clear-liquid height tray j+1 **would have at its current inflow** (Bennett (5.2) solved for h_cl at q = L_j^n v_L with tray j+1's α_e), not its actual holdup. **Why:** using the neighbour's actual holdup locked pairs of trays into an alternating full/half-full checkerboard in prototyping. With the normal head, flooding still propagates upward because ΔP_j contains tray j's own (growing) liquid head.
- For the bottom tray, the receiving stage is the sump: h_norm,N+1 = 0.
- Downcomer fraction of flood for display: h_dc,j / (φ_dc (TS + h_w)).

### 5.8 Weeping and dumping

Weep onset uses the tray stability factor (Summers et al., "Tray stability at low vapor load", Distillation & Absorption 2010, which also defines it as the hole Froude number in pressure form):

```
h_dry = ΔP_dry / (ρ_L g)          Φ_j = √(h_dry / h_cl)                                   (5.12)
```

Summers et al. found that across 688 data points (sieve and valve decks) Φ ≥ 0.6 gives less than 30 % of the liquid weeping. LowSYS maps Φ to the weeping fraction of the tray's inlet liquid with a piecewise-linear anchor fit (0 at Φ = 0.75, 0.27 at Φ = 0.60, 1 at Φ ≤ 0.20):

```
w_j = clamp( (0.75 − Φ_j) / 0.55 , 0 , 1 )                                              (5.13)
f_j = min( 1 , w_j + s_broken,j )          (bypass fraction; s_broken from fault F04, else 0)
W_j = f_j · L_{j−1}                                                                      (5.14)
```

Φ_j and hence w_j are evaluated at the start of the step; W_j uses the current step's L_{j−1} (known in the top-down sweep, §12.2). W_j is the inlet liquid that falls through the holes to tray j+1 without crossing the deck, keeping its arrival composition (§4.1). From the bottom tray it falls into the sump. Feed liquid is assumed to reach the deck (it does not bypass).

**Dumping** (revised v1.1, M3; threshold made implicit 2026-10-12). When the vapour can no longer hold liquid on the deck (Φ < 0.2, e.g. boilup lost), the tray drains through its open area like an orifice. Φ itself depends on the holdup, Φ = √(h_dry/h_cl) with h_cl = M v_L/A_a,eff, so Φ is evaluated at the **end-of-step** holdup. The drain then becomes a continuous, threshold-free function of M:

```
L_dump,j(M) = κ_j · max(0, √M − √M_c,j)                                                   (5.15)
κ_j   = C_dump · A_drain,j · √(2 g v_L,j / A_a,eff,j) / v_L,j          C_dump = 0.6
M_c,j = 25 · h_dry,j · A_a,eff,j / v_L,j        (the holdup at which Φ = 0.2, i.e. h_cl = 25 h_dry; h_dry at state n)
A_drain,j = sieve: f_h A_a · holeScale_j · (1 − s_broken) + s_broken A_a          (the area of (5.3) and §11)
            valve: r_min f_v A_a · holeScale_j · (1 − s_broken) + s_broken A_a    (valves closed)
```

- This is exactly ((0.2 − Φ)/0.2) · C_dump A_drain √(2 g h_cl)/v_L with Φ at M^(n+1), rewritten.
- Every tray in full hydraulics carries the term. On a normal tray M_c is thousands of mol (B-T design: M_c ≈ 13 000 mol against M ≈ 190), so it is zero. The `dumping` flag (bit 2) is set when M̂ > M_c.
- **Why implicit** (tester finding, VALIDATION.md VC-12.6). A fully broken tray sits at Φ = 0.208, almost on the threshold. With Φ taken from the start-of-step holdup (the first v1.1 text), draining raised Φ, which stopped the drain, and trays flipped between bypass and dumping. The result depended on dt: one tray held 1.65 mol at dt = 2 s against about 0 at 0.5 s, and a dumping tray reached 52 mol at coarse dt. With Φ implicit there is nothing to flip.
- **What it gives** (scratch prototype on the M2 engine, B-T):
  - a fully broken tray 5 gives the same steady state at dt = 0.5, 2 and 30 s, both at TS 0.6 m (x_D 0.964776, x_B 0.010936) and at TS 0.9 m (0.974315, 0.018575). The tray holds 2.42 mol at Φ = 0.208 and does not dump;
  - after boilup is cut to 0 with the feed on, no dumping tray holds more than 1.35 mol (sieve, h_cl ≈ 0.15 mm) at any dt. Valve trays hold about 1.4–1.7 mm.

  Real dumping trays look like this: nearly empty, with liquid raining through. The Murphree factor min(1, h_cl/5 mm) of §4.2 removes almost all contact.
- **Checkerboard.** Which alternate trays hold the ≈ 1 mol in that test depends on dt. It is an artifact of the bypass model in this regime: a dumping tray passes its downcomer inflow straight to the tray below. Every tray is nearly empty in either phase, so the tests assert totals, not per-tray values.
- v1.0 used L_dump = k_d M with k_d = ((0.2 − Φ)/0.2)/8 s. A tray still receiving inlet liquid then kept about 220 mol (h_cl ≈ 28 mm), more than a normal tray.

Valve trays reach low Φ only when the valves are closed (§5.4), which is why they turn down further (about 5:1 versus 2:1 for sieve trays with the defaults).

### 5.9 Downflow summary

```
L_j = smin( L_weir(M_j), L_max,j ) + L_dump,j(M_j)      smin = plain min [impl may smooth]       (5.16)
```

### 5.10 Indicators reported per tray

φ_j (jet flood), ψ_j, downcomer flood fraction, M_j/M_max,j (froth fill), Φ_j and w_j (weeping), ΔP_j, h_cl, α_e, froth height h_f = h_cl/α_e, u_h, E_j^eff, and booleans `dcLimited`, `dumping`, `overflowing`. "Max flood %" in the KPI strip = 100 × max over trays of max(φ_j, dc flood fraction, M_j/M_max,j).

---

## 6. Packed sections

### 6.1 Discretisation

A packed bed of height H_bed with reference HETP_ref is split into n_seg = max(1, round(H_bed / HETP_ref)) segments of height H_k = H_bed / n_seg. Each segment is a stage in the chain (same component balance (4.1), same energy balance (4.6)) whose Murphree efficiency comes from the HETP (§6.4). A liquid feed or reflux enters the top segment of a bed through an ideal distributor unless the maldistribution fault is active (§6.6). Packed segments have no weeping, no downcomer and no entrainment terms.

**Sections and mixed columns** (M8 readiness, 2026-10-13):
- `ColumnConfig.sections` lists tray sections and packed beds from top to bottom. Stage numbers run on across sections (§0.2): a bed of n_seg segments takes n_seg consecutive stage numbers.
- A feed enters a tray or the **top segment** of a bed (a feed distributor between beds). `validate()` rejects a feed into any other segment, and the `feedStage` lever offers only trays and bed tops.
- Between two beds, and between a bed and a tray section, the liquid is collected and redistributed: it is perfectly mixed, so the maldistribution of one bed does not carry into the next. Supports, collectors and distributors add no ΔP and no holdup.
- The global `murphree` lever applies to tray stages only. Packed segments take E from §6.4 in every tier. The lever is not offered when the column has no tray section; `nTrays` is not offered when it has a packed section (beds are edited in the Advanced drawer or through `internals`, §13.4).
- Tray stages keep all of §5. In ideal hydraulics trays use only the Bennett weir and packed segments use (6.3) with φ_p = 0 and HETP = HETP_ref: no ΔP, no wetting or loading modifier, no flooding. Maldistribution (§6.6) still applies, because it is a distributor fault, not a hydraulic effect.
- Metal heat capacity in (4.6) for a packed segment: m_metal,k = ρ_bed A_T H_k (ρ_bed from §6.2) instead of the tray's 75 kg/m² × A_T.
- A dry segment cannot transfer mass. As the tray rule min(1, h_cl/5 mm) of (4.2), E_MV,k is multiplied by min(1, h_L,k / 0.005).

### 6.2 Packing data

Packing factors F_p (ft⁻¹) and areas from Kister, *Distillation Design*, McGraw-Hill (1992), chapter 8, and vendor bulletins as summarised there; HETP rules of thumb from Kister (random: HETP[ft] ≈ 1.5 × nominal size [in]; structured: HETP[in] ≈ 1200/a[ft²/ft³] + 4). Values are representative, not vendor-certified. **The a, ε and F_p values are quoted from memory of Kister's tables and have not been checked against the book** (OPEN_ITEMS.md).

| id | Packing | a (m²/m³) | ε | F_p (ft⁻¹) | Material σ_c (mN/m) | HETP_ref (m) | ρ_bed (kg/m³) |
|---|---|---|---|---|---|---|---|
| pall25m | 25 mm metal Pall rings | 205 | 0.94 | 56 | 75 (steel) | 0.46 | 474 |
| pall50m | 50 mm metal Pall rings | 105 | 0.96 | 27 | 75 | 0.91 | 316 |
| raschig50c | 50 mm ceramic Raschig rings | 92 | 0.74 | 65 | 61 (ceramic) | 0.91 | 598 |
| struct250 | Structured, 250 m²/m³ (Mellapak 250Y class) | 250 | 0.98 | 20 | 75 | 0.50 | 158 |
| struct500 | Structured, 500 m²/m³ (Mellapak 500Y class) | 500 | 0.975 | 34 | 75 | 0.30 | 198 |

- **struct250 HETP_ref is 0.50 m** (M8 readiness; v1.0 had 0.45). The rule quoted above gives 1200/76.2 + 4 = 19.75 in = 0.502 m, and 0.30 m for struct500 (which the table already had); 0.45 m was the only value off the stated rule. The owner may restore a vendor value (OPEN_ITEMS.md).
- **ρ_bed** (M8) is the solid mass per m³ of bed, ρ_solid (1 − ε) with ρ_solid = 7900 kg/m³ for steel and 2300 kg/m³ for ceramic. It is used only for the metal heat capacity in (4.6) (§6.1), with c_p = 500 J/(kg·K) for both.

### 6.3 Holdup, pressure drop, flooding

Superficial velocities: u_L = L v_L / A_T, u_V = V MW_V/(1000 ρ_V A_T); mass fluxes L' = L MW_L/(1000 A_T), G' = V MW_V/(1000 A_T) (kg/m²/s).

Which flows (M8 readiness), for segment k of a bed with cross-section A_T = π D_bed²/4:
- Liquid: L = L_k, the segment's outflow from (6.4), with MW_L(x_k). Because L_k follows the holdup, ΔP and φ_p lag a change in the liquid arriving from above by the bed's drainage time. This is how "ΔP keeps rising" near flood arises below.
- Vapour: V = V_{k+1}, the vapour entering from below, with MW_V(y_{k+1}), as for trays (§5.2).
- Properties at segment k: ρ_L(T_k, x_k), ρ_V(T_k, P_k, y_k), σ(T_k, x_k), and the preset's μ_L, in cP inside (6.1). Tier 1 uses the preset constants (§2.3).
- Pressure: ΔP_k = (ΔP/H)_k · H_k, and P_{k+1} = P_k + ΔP_k exactly as (5.5) does for trays. The bed ΔP is the sum over its segments. PDT-(101 + b) reads it (§10.5).
- φ_p, G'_fl and the holdup factor are evaluated per segment. The bed's flood fraction is the maximum over its segments.

**Pressure drop** — Robbins, Chem. Eng. Prog. 87(5) (1991) 87, in its US-unit form (in. H₂O per ft of packing), with F_pd taken equal to F_p:

```
G_f = G'·737.338 · √(0.075 / ρ_V,lb) · √(F_pd/20)                      (lb/ft²/h)
L_f = L'·737.338 · (62.4 / ρ_L,lb) · √(F_pd/20) · μ_L[cP]^0.1            (lb/ft²/h)
t   = 7.4×10⁻⁸ G_f² · 10^(2.7×10⁻⁵ L_f)
ΔP/H [in H₂O/ft] = t + 0.4 (L_f/20000)^0.1 t⁴                                              (6.1)
ΔP/H [Pa/m] = 817.22 × ΔP/H [in H₂O/ft]
```

ρ_lb = ρ / 16.01846. Check: L' = 12.2, G' = 2.03 kg/m²/s, ρ_L = 1000, ρ_V = 1.1853, μ = 1 cP, F_pd = 24 → 309.83 Pa/m (the `fluids` library reference example gives 619.66 Pa for 2 m).

**Flood point** — Kister and Gill, Chem. Eng. Prog. 87(2) (1991) 32:

```
ΔP_flood [in H₂O/ft] = 0.115 F_p^0.7                                                        (6.2)
```

The flood vapour flux G'_fl at the current L'/G' ratio solves ΔP(G'_fl · L'/G', G'_fl) = ΔP_flood (bisection on [0.01, 30] kg/m²/s, 40 iterations; refresh every 10 steps). Approach to flood φ_p = G'/G'_fl.

F23 (§11) replaces F_p by F_p,eff = F_p (1 + 1.5 s) in **both** (6.1) and (6.2): the flood ΔP rises as F_p^0.7, more slowly than the operating ΔP, so a crushed bed reaches flood at a lower load.

Robbins (1991) and Kister and Gill (1991) were both fitted mainly to random packings. Using them for the structured entries is a simplification, stated in the math overlay (OPEN_ITEMS.md). At the B-T load (VC-13), (6.1) gives 148.7 Pa/m for struct250 against the 765.2 Pa/m flood ΔP. That is the right order for a 250Y-class packing at half of flood.

**Liquid holdup** (volume fraction of the bed). Pre-loading: laminar falling-film (Nusselt) holdup as used by Billet and Schultes; above the loading point the Billet–Schultes (Trans IChemE 77A (1999) 498) increase with h_L,Fl ≈ 2.2 h_L,S:

```
h_L,S = ( 12 μ_L a² u_L / (ρ_L g) )^(1/3)
h_L   = h_L,S · (1 + 1.2 φ_p^13)                                                              (6.3)
M_k   = h_L · A_T · H_k / v_L
```

The implicit holdup solve (§12.2) needs the outflow as a function of holdup; invert (6.3):

```
L_k(M_k) = [ M_k v_L / (A_T H_k (1 + 1.2 φ_p^13)) ]³ · ρ_L g A_T / (12 μ_L a² v_L)            (6.4)
```

with φ_p at state n. Near flood the same holdup drains more slowly, so liquid accumulates and ΔP rises steeply over time: packing flooding develops dynamically. Carry-over above flood: if φ_p > 1.05 the excess holdup above the h_L(φ = 1) value is carried up with τ_c = 5 s, like (5.9).

### 6.4 HETP and segment efficiency

```
HETP = HETP_ref · max(1, a_w,ref / a_w) · g(φ_p)                                              (6.5)
a_w/a = 1 − exp[ −1.45 (σ_c/σ)^0.75 Re_L^0.1 Fr_L^−0.05 We_L^0.2 ]       (Onda, Takeuchi and Okumoto, J. Chem. Eng. Japan 1 (1968) 56)
Re_L = L'/(a μ_L)    Fr_L = L'² a / (ρ_L² g)    We_L = L'² / (ρ_L σ a)        (μ_L in Pa·s, σ and σ_c in N/m)
a_w,ref = a_w at L' = L'_des (the bed's designLiquidFlux), with segment k's current ρ_L, μ_L, σ
g(φ) = 1                       φ ≤ 0.80
     = 1 + 8 (φ − 0.80)²         0.80 < φ ≤ 1.0
     = 1.32 + 3 (φ − 1.0)       φ > 1.0
```

The wetting term makes HETP rise at low liquid loads (poor wetting); g makes it rise above about 80 % of flood (entrainment, back-mixing). The g shape is empirical; packing HETP has no first-principles model at this fidelity.

M8 rules for (6.5):
- **max(1, ·)**: HETP_ref is the catalogue value at the design load. Better wetting at higher loads does not take HETP below it. v1.0's plain ratio let segments above L'_des pass E_O = 1 and those below fall under it, a jitter with no physical meaning.
- **Same properties in a_w and a_w,ref.** The factor then measures the load effect. It is driven by L'/L'_des, and the properties and the packing material (σ_c) only set how steeply wetting falls off.
- **L'_des** is `PackedSection.designLiquidFlux` (kg/m²/s). A preset stores the bed's smallest segment L' at its defaults, rounded **down** to 0.1, so that the design point has HETP = HETP_ref in every tier. `bt_packed`: 1.9 (upper bed) and 4.0 (lower bed) (§2.3). When it is null the wetting factor is 1.
- Check values (struct250, B-T Tier-1 properties, L'_des = 2.088): a_w/a = 0.8858; L' = 1.0 → factor 1.105; L' = 0.5 → 1.254; L' = 0.25 → 1.465 (VALIDATION.md VC-13).

Segment efficiency: the overall efficiency of segment k is E_O,k = min(1, H_k / HETP_k) × E_mal (§6.6), converted to Murphree with (4.3).

**λ_k for (4.3) and (6.6)** (M8 readiness; v1.0 wrote K̃_LK V_k/L_k here and m V/L in §4.2, which differ by a factor of 2–4 near the column ends). λ is the stripping factor of the equilibrium **slope**, as in (4.3):

```
λ_k = m_k V_k / L_k        m_k = α′_k / [1 + (α′_k − 1) x′_k]²
α′_k = K_LK,k / K_HK,k      x′_k = x_LK,k / (x_LK,k + x_HK,k)      (x′ = 0.5 if the key sum is below 1×10⁻⁹)
```

For a binary the keys are components 0 and 1. In Tier 1 α′ is the ratio of the stored α. m is the slope of the constant-α curve with the local α′, the standard linearisation. λ_k is clamped to [10⁻³, 10³]. `bt_packed` at its Tier-2 defaults: λ runs from 0.59 at the top of the upper bed to 1.64 at the bottom of the lower bed (VALIDATION.md VC-13).

### 6.5 Packed-section indicators

φ_p per segment, ΔP per segment and per bed, h_L, HETP, a_w/a, E_O,k, and `flooding` when φ_p ≥ 1.

Per bed (M8): ΔP_bed, max φ_p, n_th = Σ_k min(1, H_k/HETP_k) (theoretical stages before maldistribution), S (§6.6) and E_mal. E_mal and the F21 split f are fault parameters: they are NaN in drills and in plant views (§10.9). The KPI "max flood %" takes 100 φ_p for packed segments, next to the tray terms of §5.10.

### 6.6 Maldistribution — parallel-column model

A plugged distributor sends more liquid to one side of the bed. LowSYS uses the parallel-column model (Hoek, Wesselingh and Zuiderweg, Chem. Eng. Res. Des. 64 (1986) 431): the bed behaves as two half-columns, A and B, with liquid fractions (1 + f)/2 and (1 − f)/2 and equal vapour. Each half is a Kremser cascade of n stages with stripping factor S_A = S/(1 + f), S_B = S/(1 − f).

M8 definitions (v1.0 said n = n_seg and S = "K̃_LK V/L, the bed average"):
- **n = n_th = Σ_k min(1, H_k/HETP_k)** over the bed's segments: the theoretical stages the bed would have with a perfect distributor. n may be fractional, and the Kremser formulas below accept that. With n_seg, a bed already weakened by loading (g > 1) or by F23 would be charged for stages it no longer has.
- **S = exp(mean_k ln λ_k)**, the geometric mean of the λ_k of §6.4 over the bed's segments. λ varies along a bed, and a geometric mean is the usual effective factor for a Kremser cascade.
- **S = 1** when |ln S| < 10⁻⁹, using the limit forms given below. S_B → ∞ (f → 1) gives Φ_K = 1.

```
Kremser fraction stripped:  Φ_K(S, n) = (S^(n+1) − S) / (S^(n+1) − 1)        (S = 1: n/(n+1))
Mixed outlet:               Φ_mal = [ (1 + f) Φ_K(S_A, n) + (1 − f) Φ_K(S_B, n) ] / 2
Equivalent stages:          n_eff = ln[ (S − Φ_mal)/(1 − Φ_mal) ] / ln S − 1    (S = 1: Φ_mal/(1 − Φ_mal))
E_mal = n_eff / n                                                                              (6.6)
```

Recomputed every 10 steps per bed. The effect is physical rather than a fixed multiplier: it is largest when S ≈ 1 (near a pinch) and when the bed has many stages, which is the known behaviour. With f = 0.2 and S = 1, a 10-stage bed keeps 70 % of its stages and a 20-stage bed only 43 % (VALIDATION.md VC-13).

F21 (§11) sets f = 0.6 s on one bed. ΔP and φ_p use the bed-mean flows, so they do not change; the evidence is the separation and the bed's temperature profile. Example, the H7 column (§2.3): f = 0.3 on the upper bed gives E_mal = 0.57, x_D 0.9936 → 0.9788, and the bed's TI span falls from 11.5 K to 8.1 K, while its ΔP moves by 0.3 % (VALIDATION.md §H, H7).

---

## 7. Condenser, reflux drum and overhead pressure (Tiers 2/3)

### 7.1 Overhead vapour inventory

The condenser shell, overhead line and drum vapour space form one well-mixed vapour volume V_ovh (default 3.0 m³ for the B-T preset; preset value) at pressure P_top. It holds condensable vapour n_V and inert gas n_I (mol):

```
P_top = (n_V + n_I) R T_0 / V_ovh                       (ideal gas)
y_I   = n_I / (n_V + n_I)
dn_V/dt = V_1 − N_cond − D_V − N_vent (1 − y_I) − N_relief (1 − y_I)                   (7.1)
dn_I/dt = ε_I F − (N_vent + N_relief) y_I                                                (7.2)
```

T_0 is the drum temperature: the bubble point of the drum liquid x_0 at the condensable partial pressure P_top (1 − y_I), minus any reflux subcooling (§7.3). ε_I = 0 normally; the non-condensables fault sets ε_I = 1×10⁻⁴ s (mol inert per mol feed).

**Component inventory of the vapour (exact conservation, M4).** The condensable inventory is tracked per component, n_V,i, with Σ n_V,i = n_V. After the component step (§12.3):

```
n_V,i^(n+1) = n_V,i^n + dt [ V_1 y_c,i − N_cond y_c,i − (D_V + N_vent(1 − y_I) + N_relief(1 − y_I)) y_V,i^n ]
y_c,i = (1 − E_1) ŷ_i2 + E_1 K̃_i1 m_i1^(n+1)/M̂_1       (the vapour leaving tray 1 exactly as the final Murphree pass used it)
y_V,i^n = n_V,i^n / n_V^n                                (composition of the inventory, for anything leaving it)
clamp n_V,i ≥ 0 (count in solverHealth.negativeClamps)
```

With a partial condenser the drum is an equilibrium stage (§12.3 drum row), and the vapour it does not condense leaves the drum at y_0 = K̃_0 x_0. There, replace y_c by y_0,i = K̃_i0 m_i0^(n+1)/M̂_0 in the V_1 − N_cond term. The condensate is given the composition y_c, as v1.0 did. The overhead residence time is n_V/V_1 ≈ 2.5 s, so the condensate is in effect the tray-1 vapour. Tracking n_V,i makes conservation exact, so VC-5.2 can use the Tier-1 tolerance. v1.0 counted the inventory as n_V · y_1 with the *current* y_1, which leaks n_V Δy_1 (up to about 2×10⁻⁶ relative in transients).

**Inert vent.** Lever `inertVent` (0–100 %) opens a line to a vent header:

```
N_vent = (OP_vent/100) · N_vent,max · √( max(P_top − P_vent, 0) / 50 kPa )        N_vent,max = 2 mol/s (at 50 kPa)
P_vent = 0.5 bar(a) (vacuum vent system) for presets with P_design < 3 bar; 1.01325 bar(a) otherwise
```

Venting therefore works at the B-T operating pressure (there is no driving force to atmosphere at 1 atm). The vent removes inerts and condensables in proportion to the overhead composition.

**Relief valve capacity:** N_rel,max = 2 × the design top vapour V_1 (B-T: 83.3 mol/s); see §7.4.

### 7.2 Condenser duty

Cooling water flow m_cw = (OP_cw/100) m_cw,max (kg/s), inlet temperature T_cw,in, c_p,w = 4180 J/(kg·K). Using the mean water temperature T_cw,in + Q/(2 m_cw c_p,w):

```
UA_eff = UA_clean / (1 + UA_clean R_f) · (1 − f_blanket)          f_blanket = min(0.95, 3 y_I)
Q_C    = UA_eff (T_0,sat − T_cw,in) / (1 + UA_eff / (2 m_cw c_p,w))      clipped to ≥ 0               (7.3)
```

T_0,sat is the condensing temperature (drum bubble point before subcooling). Inerts act twice, as in a real condenser: they lower the condensable partial pressure (lower condensing temperature, smaller ΔT) and they blanket the tubes.

Condensation rate from the energy balance of condenser and drum (vapour enters at H_1, liquid entrained from tray 1 enters at h_1, all liquid leaves at h_0, uncondensed vapour stays at H_V):

```
N_cond = [ V_1 (H_V − H_1) + Q_C − e_1 (h_1 − h_0) ] / ( H_V − h_0 )          (7.4)
H_V = H_V(y_V, T_0,sat)    y_V = y_1 (total condenser), y_0 = K̃_0 x_0 (partial condenser)
h_0 = h_L(x_0, T_0)        h_1 = h_L(x_1, T_1)        e_1 = tray-1 entrainment (§5.6; 0 in ideal hydraulics)
```

The first term is the (usually small) desuperheating of the incoming vapour. The entrainment term was added at the M4 close-out (2026-10-13): (7.6) counts e_1 in the drum's mass, so its enthalpy belongs here too. Tray 1 is hotter than the drum, so the sensible heat e_1 (h_1 − h_0) uses part of Q_C and that much less vapour condenses. Without it, full hydraulics closed VC-5.4 only to 6.8×10⁻⁶ (B-T design) and 1.9×10⁻⁵ (+20 % load); with it, to 1.8×10⁻¹¹. Ideal hydraulics is unchanged. H_V(y_0) for the partial condenser is what engine 1155f40 already uses.

Design values (stored in the preset): UA_clean is chosen so that at the design point the condenser uses **50 %** of the CW valve. For B-T: Q_C ≈ 1.281 MW, T_0 ≈ 80.2 °C, T_cw,in = 30 °C, m_cw,max = 150 m³/h (41.5 kg/s; 50 % → 20.8 kg/s, outlet 44.7 °C) → UA_clean = 29.9 kW/K. For a new preset, the value is found once, offline: run the Tier-2 preset to steady state with the pressure held at P_top (a "perfect condenser" debug option), read Q_C and T_0,sat, solve (7.3) for UA at OP_cw = 50 %, and store the result in the preset JSON (mw: 29.76 kW/K, VALIDATION.md VC-27.1).

**Why 50 %, not v1.0's 70 %** (M4 prototype finding). This condenser is limited by its UA, so CW flow only acts through the water's temperature rise. At 70 % (UA 28.5 kW/K, outlet 40.5 °C) a fully open valve added only **3.2 %** duty. PC-101 then saturated on any duty increase above about 3 % (VC-8.1 in Tier 2 let P float to 1.066 bar), and a −10 kPa SP step could never be reached. At 50 % the valve covers −13 % … +7.9 % of the design duty (25 % → 100 % OP): the same steps hold P at 1.013 bar with CW at 89.5 %, and ±10 kPa SP steps settle in 5–7 min.

Total condenser: D_V = 0. Partial condenser: vapour product through the pressure-control valve

```
D_V = (OP_DV/100) D_V,max √( max(P_top − P_down, 0) / (P_design − P_down) )                 (7.5)
```

P_down = P_design − 30 kPa (vapour-product header; B-T 0.713 bar(a)). v1.0 had 1.01325 bar, which gives no flow at all at the B-T design pressure. D_V,max = the design distillate rate (B-T 50 kmol/h). PC-101 then manipulates PV-102 (§10.7); the CW flow comes from its own lever (`cwOP`, 0–100 %). When a partial condenser is built (preset load or the `condenserType` switch) the lever starts at the preset value `condenser.cwOpPartial` (default and B-T: 30 %). v1.0's 70 % predates the 50 % design. Rule for a preset: the OP at which the partial-condenser steady state at P_design sends about a quarter of the design distillate as vapour (B-T at 30 %: D_V 12.6, D_L 37.2 kmol/h, PV-102 25 %; engine 1155f40). At or above the total-condensation OP (B-T ≈ 48.5 %) the condenser takes all of V_1 at P_design: PC-101 shuts PV-102, D_V = 0 and P falls below the SP (B-T at 70 %: 94.5 kPa). That is correct behaviour, not an error state: the CW, not PV-102, then sets the pressure.

### 7.3 Reflux drum

Drum liquid (stage 0) component balance:

```
dm_i0/dt = N_cond y^c_i + e_1 x_i1 − (L_0 + D_L) x_i0                                         (7.6)
total condenser: y^c = y_1 (all of the vapour that condenses has the overhead composition)
partial condenser: drum is an equilibrium stage; the vapour in the inventory has y_0 = K̃_0 x_0 and (7.6) becomes
dm_i0/dt = V_1 y_i1 + e_1 x_i1 − (V_1 − N_cond) y_i0 − (L_0 + D_L) x_i0
```

Reflux temperature: T_0 = T_0,sat − ΔT_sub, where ΔT_sub = lever value + 20 K × f_blanket (blanketed tubes subcool the condensate: the classic non-condensables symptom). Reflux enthalpy h_L(x_0, T_0) enters tray 1's energy balance (4.6): subcooled reflux condenses extra vapour on tray 1 and raises the internal reflux.

Drum level: level% = 100 · M_0 v_L(x_0, T_0) / V_drum (B-T: V_drum = 3.0 m³). Above 100 % the drum is "full" (alarm); the excess backs into the condenser and reduces the free tube area: UA_eff × max(0.2, 1 − (level − 100)/30).

The reflux pump cannot take more than the drum holds: L_0 ≤ (M_0 + dt(N_cond + e_1)) / dt, and likewise for D_L; when the drum empties, reflux is lost (alarm "reflux pump cavitating").

### 7.4 Pressure solve

P_top^(n+1) comes from an implicit scalar solve each step. The condenser on its own is fast (τ ≈ 2–10 s). Coupled to the column's heat storage (4.6), the overall pressure time constant is about 2–3 min (B-T prototype: 150 s for a CW-valve step). The solve runs at step 6 of §12.4, *before* the hydraulic and component steps, because both need N_cond.

```
Unknown P. For a trial P:  V_1(P) from the vapour sweep (4.6)/(4.7) with the storage term at P;  T_0,sat(P) = bubble T of x_0^n at P(1 − y_I);
           Q_C(P) from (7.3);  N_cond(P) from (7.4) with V_1(P);  D_V(P) from (7.5)
Residual:  r(P) = n_V(P) − n_V^n − dt [ V_1(P) − N_cond(P) − D_V(P) − N_vent(P)(1 − y_I) − N_relief(P)(1 − y_I) ]
           with n_V(P) = P V_ovh (1 − y_I) / (R T_0,sat(P))
Secant iteration from P^n and 1.001 P^n, keeping P ≥ 1 kPa; stop at |ΔP| < 0.1 Pa; max 12 iterations (prototype: ≤ 5 at dt = 0.5 s, ≤ 3 at 30 s); fallback: keep P^n and flag.
After convergence the sweep is run once more at P^(n+1); its V_j are this step's vapour flows.
```

Relief valve: set pressure P_set (preset; B-T 3.5 bar(a)), N_relief = N_rel,max · clamp((P − P_set)/(0.1 P_set), 0, 1). Venting composition y_1. Alarm and scenario safety penalty.

### 7.5 Tier 1

No pressure model: P_top is fixed at the preset value and the drum receives all of V_1 (total condenser).

---

## 8. Sump and reboilers

### 8.1 Sump

Stage N+1 holds the sump liquid (well mixed). Level% = 100 · M_{N+1} v_L / V_sump (B-T: V_sump = A_T × 2.4 m = 2.714 m³).

Sump starvation: a reboiler cannot boil liquid it does not have.

```
s_sump = clamp( M_{N+1} / M_min , 0 , 1 )      M_min = 0.05 V_sump / v_L                           (8.1)
```

applied to the boilup (4.4)/(4.7). The bottoms pump is limited the same way as the reflux pump.

### 8.2 Kettle reboiler (default, Tiers 2/3)

Steam at header pressure P_hdr condenses at T_st = T_sat,water(P_hdr) (DIPPR-101 inverse; 3.5 bar(g) → 148.10 °C).

```
UA_R,eff = UA_R,clean / (1 + UA_R,clean R_f,R) · (1 − f_flooded)
Q_max    = UA_R,eff (T_st − T_{N+1})
Q_R,delivered = min(Q_R,SP , Q_max)                                                               (8.2)
steam valve OP (display) = 100 · Q_R,delivered / Q_max          ("duty limited" alarm when Q_R,SP > Q_max)
```

From M3, Q_R,SP is replaced by the steam valve's duty request Q_v = Q_max,0 g(p)(1 + d), and FC-103 positions the valve on the *measured* duty (§10.3). The delivered duty is the sub-step mean of min(Q_v, Q_max), and the "display OP" line above is superseded by the real valve position. "Duty limited" means Q_max,0 g(p) > Q_max for 60 s (`model.dutyLimited`; the supply disturbance d is left out so that the flag does not flicker with noise at a fully open valve). Because Q_max,0 is the clean maximum at the *current* header, the flag means "the exchanger is degraded" (fouling F13, condensate backup F14). A header loss (F15) lowers Q_v and Q_max together and never raises it. Every duty shortfall, whatever its cause, shows on the plant as FC-103 at 100 % OP with the duty below SP (`FC-103.OPSAT`); that is F15's symptom.

**No steam-chest pressure (ruling 2026-10-13).** On a plant, fouling raises the shell temperature needed for the same duty, so the chest pressure climbs toward the header and the steam valve creeps open over the fouling time. LowSYS takes Q_v from the clean Q_max,0 at the header and caps Q = min(Q_v, Q_max), so FV-103 stays at its clean position while Q_max > Q_v and runs to 100 % within minutes once Q_max < Q_v. The duty, the time of saturation and `model.dutyLimited` are the same as with a chest model; only the creep is missing. The model stays (a chest model would move every validated FV-103 OP and needs an implicit solve per sub-step), and the F13 / H4 texts describe the modelled symptom (§16).

UA_R,clean is stored in the preset, chosen so that the design duty uses 60 % of Q_max (B-T: Q = 1.30 MW at T_B = 110.4 °C and T_st = 148.1 °C → UA_R,clean = 57.5 kW/K); for a new preset it is found offline from a steady-state run, like the condenser UA (§7.2). Fouling raises R_f,R; condensate backup raises f_flooded (§11).

In Tier 1 the boilup lever V_B is used directly; heat-transfer limits do not apply.

### 8.3 Thermosyphon reboiler (M6)

A vertical thermosyphon draws sump liquid down an inlet line, heats it in tubes, and returns a two-phase mixture through a riser to the column above the liquid level. Nothing pumps it: the driving force is the density difference between the liquid leg and the two-phase leg. Tiers 2/3 only. In Tier 1 the boilup lever V_B is used as for the kettle; the loop state is kept, and it is re-initialised (§13.1 step 7) when the tier returns to 2 or 3.

#### 8.3.1 Geometry and properties (B-T defaults)

| Item | Symbol | Default |
|---|---|---|
| Tubes: number, inner diameter, length | N_t, D_i, L_t | 200, 0.0212 m, 3.0 m |
| Heat-transfer area: the outside area of 1" tubes. It is an input; N_t π D_i L_t would give 40.0 m² | A | 47.6 m² |
| Overall clean U (steam → boiling organic), referred to A | U | 1000 W/(m²·K); UA_R,clean = U A = 47.6 kW/K (used by F13 and C4) |
| Liquid surface height above bottom tubesheet | z = z_0 + (level%/100) h_sump | z_0 = 1.2 m, h_sump = 2.4 m (75 % level → z = 3.0 m = top tubesheet) |
| Return nozzle height above bottom tubesheet | z_ret | 4.5 m (riser length L_r = z_ret − L_t = 1.5 m) |
| Inlet line diameter, length | D_in, L_in | 0.20 m, 6.0 m |
| Riser diameter | D_r | 0.30 m |
| Inlet loss coefficient (entry, bends) | K_in | 4 |
| Inlet valve loss coefficient | K_valve | K_valve = 1/(OP/100)² (1 at 100 % open, 400 at 5 %) |
| Outlet loss coefficient (bends, nozzle) | K_out | 3 |
| Exit-quality onset of mist-flow degradation | x_c | 0.30 |

Liquid properties are those of the sump liquid:
- ρ_L and c_p,L (J/(kg·K)).
- The **mass** latent heat λ = (H_V − h_L)/M̄_L (J/kg) at the sump, where M̄_L is the sump liquid's mean molar mass (kg/mol).
- ρ_V at P_{N+1}; μ_L is the preset constant.

Clausius–Clapeyron needs the **molar** latent heat: dT_sat/dP = R T_sump² / (λ M̄_L P_{N+1}) in K/Pa (B-T: 3.63×10⁻⁴ K/Pa at 383.5 K and 1 atm). v1.0 wrote R T²/(λ P) with the same λ that the loop uses per kg, which is off by M̄_L.

Flow areas: A_t = N_t π D_i²/4 (0.0706 m²), A_in = π D_in²/4, A_r = π D_r²/4. g = 9.80665 m/s².

#### 8.3.2 Loop model (sub-stepped)

**States:** circulation W (kg/s), riser quality x_r, exit quality x_e of the previous sub-step, the filters x̄_e, r̄_out and r̄_in, and the oscillator (u, v). All of them belong to the column state, the save data and the warm-start cache.

**Sub-step:** δ = 0.1 s, equal to the control fast-layer sub-step δ_c (§10.1): 5 sub-steps per main step at dt = 0.5 s, 20 at 2.0 s. Within a main step the column conditions (sump T, composition, P, level) are frozen at their start-of-step values.

```
Static head subcooling at the tube inlet:  ΔT_sub = (dT_sat/dP) ρ_L g z                     (K)
Mean boiling temperature:                   T_b,mean = T_sump + ΔT_sub / 2
Effective heater flow:                      W_h = max(W (1 + u), 0.3 kg/s)

Heat and exit quality (exact solve). The requested duty Q_R,SP is the steam valve's request Q_v of this sub-step (§8.3.4):
  D(x) = 1                                   x ≤ x_c
       = max(0.35, 1 − k (x − x_c))          x > x_c,  k = 0.65/0.35           (mist-flow loss of wall wetting)
  Q_0  = (1 − f_flooded) / (1/U + A R_f,R) · A (T_st − T_b,mean)
         (without mist-flow loss; R_f,R in K/W and f_flooded as in §8.2)
  H = W_h λ ,  S = W_h c_p,L ΔT_sub
  x_e = (min(Q_R,SP, Q_0) − S) / H
  if x_e > x_c:
      x_SP = (Q_R,SP − S) / H
      if Q_R,SP ≤ D(x_SP) Q_0 :  x_e = x_SP                                    (duty met despite mist flow)
      else:                      x_e = (Q_0 (1 + k x_c) − S) / (H + k Q_0)     (on the sloped part of D)
                                 if x_e > x_c + 0.35 :  x_e = (0.35 Q_0 − S) / H   (on the D = 0.35 floor)
  x_e   = clamp(x_e, 0, 1)
  Q_max = D(x_e) Q_0
  Q     = min(Q_R,SP , Q_max , W_h (c_p,L ΔT_sub + λ))       (the last term is dry-out: all of W_h vaporised)
Sensible fraction of tube length:           f_sc = clamp(W c_p,L ΔT_sub / Q, 0, 1)    (1 when Q = 0)

Two-phase density with Zivi slip S_Z = (ρ_L/ρ_V)^(1/3):
  α_void(x) = 1 / (1 + ((1 − x)/x)(ρ_V/ρ_L) S_Z),  α_void(0) = 0      ρ_tp(x) = α_void ρ_V + (1 − α_void) ρ_L
  boiling-zone mean ρ̄_b = average of ρ_tp(x_e (k + ½)/8), k = 0..7     (8-point midpoint, linear x profile)

Riser transport (first-order lag, implicit):
  M_r = A_r L_r ρ_tp(x_r) ;   x_r ← (M_r x_r + δ W_h x_e) / (M_r + δ W_h)

Driving head:
  ΔP_drive = g [ ρ_L z − ρ_L L_t f_sc − ρ̄_b L_t (1 − f_sc) − ρ_tp(x_r) L_r ]          (Pa)

Friction (homogeneous two-phase multiplier φ² = 1 + ½ x_e (ρ_L/ρ_V − 1) averaged over the boiling zone):
  f_D = 0.316 Re^−0.25,  Re = max(2000, |W| D_i / (A_t μ_L))
  c_in   = (K_in + K_valve) / (2 ρ_L A_in²)                 (every c is in 1/(kg·m), so c W² is in Pa)
  c_tube = f_D L_t (f_sc + (1 − f_sc) φ²) / (D_i · 2 ρ_L A_t²)
  c_acc  = (v_h(x_e) − 1/ρ_L) / A_t²                   v_h(x) = x/ρ_V + (1 − x)/ρ_L
  c_out  = K_out v_h(x_r) / (2 A_r²)
Momentum (implicit in W, coefficient frozen):
  I = L_in/A_in + L_t/A_t + L_r/A_r                                               (1/m)
  W ← (W + (δ/I) ΔP_drive) / (1 + (δ/I)(c_in + c_tube + c_acc + c_out) |W|)
  W ← max(W, 0)                                     (reverse circulation is not modelled)                (8.3)
```

**Why an exact solve instead of v1.0's "3 fixed-point iterations on x_e"** (M6 readiness pass):
- On the sloped part of D the fixed-point map has slope −k Q_0/(W_h λ). That slope passes −1 at W_h ≈ 8–9 kg/s (B-T: 8.2 kg/s at 75 % level, 8.7 kg/s at 15 %).
- Below that the iteration diverges into a period-2 jitter between sub-steps. In the prototype at 15 % level, Q alternated 1054 ↔ 1300 kW every 0.1 s. This inflated v1.0's VC-14.1 half-amplitudes and shifted the means of the oscillating rows.
- Q_max does not increase with x_e, while the left side H x_e + S increases, so the root above is unique.
- The result does not depend on δ: δ = 0.025 s reproduces every VC-14.1 row.

#### 8.3.3 Instability index and oscillator

Why not first-principles: thermosyphon surging is mainly density-wave oscillation and flow-pattern intermittency. Resolving density waves needs dozens of axial cells and millisecond steps. In prototyping, a 14-cell implicit loop model (with flashing in the riser and hydrostatic subcooling) was stable everywhere in the operating map; the implicit transport on a coarse mesh damps the delay that drives the instability. LowSYS therefore keeps the loop hydraulics physical (8.3) and adds an explicit, physically indexed instability:

```
Filtered exit quality and loss ratios (a = δ/(τ_F + δ), τ_F = 30 s; W is the value after the momentum update;
a = 1 on the first sub-step after initialisation):
  x̄_e   ← x̄_e   + a (x_e − x̄_e)
  r̄_out ← r̄_out + a (c_out W² / (0.5 ρ_L g z) − r̄_out)      (outlet two-phase loss vs half the static head)
  r̄_in  ← r̄_in  + a (c_in W² / (ρ_L g z) − r̄_in)          (inlet single-phase loss vs static head)

Instability index:
  I_s = max( x̄_e / 0.30 , r̄_out ) / (1 + 3 r̄_in)                                                (8.4)
```

Order inside one sub-step: subcooling and T_b,mean → W_h → heat/x_e solve → f_sc → ρ̄_b → riser update → driving head → friction coefficients → momentum update (8.3) → filters and I_s (8.4) → oscillator (8.5). The sub-step's Q is paired with the u used in W_h, i.e. the value before the oscillator update.

The index encodes three practitioner rules (Kister, *Distillation Troubleshooting*, Wiley 2006, reboiler chapters): high vaporisation (above about 25–35 % for hydrocarbons) causes surging; a restrictive outlet line causes surging; adding inlet restriction stabilises the loop (at the cost of circulation). Low sump level acts through all three: lower head → lower circulation → higher x_e.

Oscillator (Stuart–Landau normal form of a Hopf bifurcation), relative modulation u of the heater flow:

```
period T_osc = 2 (M_heater + M_riser) / max(W, 0.3 kg/s)          (twice the transit time; typical of density waves)
   M_heater = A_t L_t (ρ_L f_sc + ρ̄_b (1 − f_sc))      M_riser = M_r
ω = 2π / T_osc          σ = (I_s − 1) / τ_s        τ_s = 20 s
κ = (max(σ, 0) + 1/τ_s) / A_sat²                     A_sat = 0.30
Sub-step update (exact rotation, then growth):
  [u, v] ← rotate([u, v], ω δ) · exp((σ − κ (u² + v²)) δ)
  r = √(u² + v²)
  if σ > 0 and r < 1×10⁻³ :  rescale to r = 1×10⁻³; if r = 0, set [u, v] = [1×10⁻³, 0]
                             (deterministic seed so that growth can start; no random numbers)
  if σ ≤ 0 and r < 1×10⁻¹² : [u, v] = [0, 0]                                                       (8.5)
```

**Floor only while unstable** (M6 readiness pass). v1.0 applied the 1×10⁻³ floor at every I_s. A stable loop then carried a permanent ±0.1 % duty ripple at ≈ 9 s. That ripple moves holdups, P and x by far more than the 1×10⁻⁷ of the steady-state monitor (§13.3), so a thermosyphon column could never be "steady" (VC-14.2 step 1, warm-start caches). The floor now acts only while the loop is unstable.

Below I_s = 1 any oscillation decays with time constant ≈ τ_s / (1 − I_s). Above it the amplitude grows at rate σ to the limit √(u²+v²) ≈ A_sat √(σ/(σ + 1/τ_s)) = A_sat √((I_s − 1)/I_s). The growth time constant τ_s/(I_s − 1) is ≈ 70 s at I_s 1.28 and ≈ 250 s at 1.08. Surging therefore *develops over minutes*, and it stops when the operator raises the level, throttles the inlet or cuts duty.

#### 8.3.4 Coupling to the column and the steam valve

The thermosyphon sub-steps run **inside the control fast layer** (§10.1, §12.4 step 2), one per control sub-step k, right after the valve update:

```
Q_R,SP,k = Q_v,k = Q_max,0 g(p_k)(1 + d_k)            steam valve request (§10.3)
Q_max,0  = UA_R,clean (T_st − T_b,mean),  UA_R,clean = U A    (clean exchanger, D = 1, start-of-step T_b,mean)
thermosyphon sub-step k (8.3)–(8.5) → Q_k, u_k
Q_st,k = Q_st,k−1 + (δ_c/τ_st)(Q_k − Q_st,k−1)     steam-chest buffer, τ_st = 10 s (ruling 2026-10-13)
FT-103 (Tiers 2/3) measures Q_st,k                    the steam-side duty, without the (1 + u) factor
Q_R,delivered = mean over k of Q_k (1 + u_k)          used by the sump energy balance (4.7) in step 6
```

The column's sump energy balance (4.7) uses Q_R,delivered. The boilup and every tray's vapour flow therefore oscillate, and with them the tray ΔPs, the column ΔP and, through the sump pressure, the bottom temperatures. The sump level moves only slightly, because the loop's liquid inventory is not coupled to the sump: the extra boilup over half a cycle is ≈ 8 mol, about 0.03 % of level at 15 %. The loop's own vapour generation W x_e is a diagnostic (shown in the Equipment tab), not a second boilup.

**Why FT-103 does not see the (1 + u) swing.** The steam side has a chest and condensate volume that the process-side surging works against. The shell pressure swings, and the steam valve's flow follows only weakly at periods of 5–20 s.
- LowSYS models the chest as a first-order buffer between the condensing duty Q_k and the metered steam flow: Q_st with τ_st = 10 s (ruling 2026-10-13). Q_k itself still swings when the loop surges, because the mist-flow limit D(x_e) Q_max,0 moves with x_e (engine 601f80e: ≈ 8 % peak to peak at 15 % level). The buffer passes ≤ 0.14 of an 8.6-s swing and ≤ 0.23 of a 15-s one, so FT-103's 5-s bins vary by ≤ 2 % (VALIDATION.md VC-14.2.2). FT-103 and FC-103 see the mean duty, and its slow fall when mist flow limits Q_max.
- Q_st applies to the thermosyphon only; with a kettle FT-103 keeps measuring Q_k (no fast component, so the M4 FC-103 results stand). Q_st is set to Q_k at the end of the 13.1 step-7 initialisation and after a kettle → thermosyphon rebuild, is part of the saved loop state (VC-14.2.6), and `ReboilerSnapshot.steamSideDuty` is the sub-step mean of Q_st,k. FC-103 (Kc 0.6, Ti 2 s) on the lagged PV keeps a phase margin of ≈ 55° (process gain ≈ 0.55 % of span per % OP), so its tuning is unchanged.
- FC-103 (Ti 2 s) therefore does not fight a 9-s oscillation. A real flow loop with a filtered PV would not fight it either.
- The price is a small energy mismatch. The cycle mean of u is ≤ 0.005 in every VC-14.1 row, but Q_k and u_k are correlated (both move with x_e), so the mean of Q_k (1 + u_k) differs from the mean of Q_k by more than the mean of u: 0.6–1.1 % in the oscillating rows (validator, 2026-10-13). The bound is ≤ 1.5 %, inside the 2 % band of C3b (§14.6). A stable loop (u = 0) has no mismatch.

**Prototype map** at the B-T defaults with Q_R,SP = 1300 kW. VALIDATION.md VC-14.1 gives the fixed-input unit test; the numbers come from the M6 readiness prototype, with the exact solve and the σ > 0 floor.
- Sump level 75 % → W ≈ 16.8 kg/s, x_e ≈ 0.17, I_s ≈ 0.50 (stable). 50 % → I_s ≈ 0.74. I_s crosses 1 at ≈ 30.8 % level (I_s 1.012 at 30 %, 0.996 at 31 %).
- 15 % → I_s ≈ 1.28 and a sustained oscillation: relative amplitude ≈ 0.14, delivered duty swinging about ±230 kW, period ≈ 8.6 s.
- Throttling the inlet valve to 16 % open at 15 % level lowers I_s only to ≈ 1.08. The amplitude settles at ≈ 0.08 (−42 %), so **throttling alone does not stop it**. At 8 % open the loop is stable (I_s ≈ 0.87), but mist flow limits the duty to ≈ 1090 kW.
- Raising the level to ≥ 32 % with the inlet fully open removes the surge without losing duty. As a step from 15 to 50 %, the amplitude is below 0.01 after ≈ 220 s.
- An outlet restriction (K_out = 20) at 75 % level gives I_s ≈ 1.42.

---

## 9. Crude fractionation (M9)

### 9.1 Assay and pseudo-components

The shipped assay is a synthetic light crude (about 32 °API, similar in shape to Arab Light), defined by its TBP curve (vol % distilled versus °C, linear interpolation between points):

| vol % | 0 | 5 | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 95 | 100 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TBP (°C) | 20 | 70 | 100 | 165 | 230 | 290 | 350 | 405 | 465 | 535 | 620 | 680 | 760 |

It is assumed stabilised (no C1–C4; light ends are out of scope).

Cut boundaries (°C): 20, 90, 150, 200, 250, 300, 350, 425, 525, 760 → nine pseudo-components PC1…PC9. For each cut:

```
volume fraction = V(T_hi) − V(T_lo)              (V = inverse of the TBP curve)
T_b = TBP at the cut's mid-volume
SG  = (1.8 T_b)^(1/3) / K_W           constant Watson factor K_W = 11.9
MW  = 1.6607×10⁻⁴ T_b^2.1962 SG^−1.0164                     (Riazi–Daubert 1980; T_b in K)
T_c = 19.06232 T_b^0.58848 SG^0.3596                          (K)
P_c = 5.53027×10⁷ T_b^−2.3125 SG^2.3201                       (bar)
ω   = ( ln(1.01325/P_c) − f0(T_br) ) / f1(T_br)                 (so that Lee–Kesler gives P_sat(T_b) = 1 atm exactly)
ΔH_vap(T_b) = R T_c ψ(T_br) ΔZ          (Lee–Kesler + Clausius–Clapeyron, consistent with the vapour pressure)
   ψ(T_r) = T_r² [ f0'(T_r) + ω f1'(T_r) ]
   f0' = 6.09648/T_r² − 1.28862/T_r + 1.016082 T_r⁵ ;  f1' = 15.6875/T_r² − 13.4721/T_r + 2.61462 T_r⁵
   ΔZ = √(1 − P_r/T_r³) evaluated at T_b
ρ_ref (15.6 °C) = 999.0 · SG                                  (kg/m³)
Cp_L (Watson and Nelson, Ind. Eng. Chem. 25 (1933) 880):
   c_p [kJ/kg/K] = 4.1868 (0.055 K_W + 0.35) [ (0.6811 − 0.308 SG) + (0.000815 − 0.000306 SG)(1.8 T − 459.67) ]
   → Cp0 (J/mol/K at 298.15 K) and dCp (J/mol/K²) by multiplying by MW
σ (§3.5.3, Riazi form)
```

Sources: Riazi and Daubert, Hydrocarbon Processing 59(3) (1980) 115; Riazi, *Characterization and Properties of Petroleum Fractions*, ASTM MNL50 (2005); Lee and Kesler (1975). Constant K_W is the standard simple characterisation; real naphthas are slightly more paraffinic.

The LK + Clausius–Clapeyron latent heat reproduces benzene's 30.72 kJ/mol exactly and n-heptane within 1.1 %; Riedel's equation was rejected because it diverges for heavy cuts (T_br → 0.93).

Resulting table (the engine must reproduce it; VALIDATION.md VC-15):

| PC | TBP cut (°C) | vol frac | T_b (°C) | SG | MW | T_c (K) | P_c (bar) | ω | ΔH_vap(T_b) (kJ/mol) | ρ_15.6 (kg/m³) | Cp_L,298 (J/mol/K) | dCp (J/mol/K²) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PC1 | 20–90 | 0.0833 | 61.7 | 0.7098 | 82.5 | 515.8 | 36.21 | 0.2227 | 27.97 | 709.1 | 176.5 | 0.373 |
| PC2 | 90–150 | 0.0936 | 119.6 | 0.7486 | 111.0 | 577.5 | 28.32 | 0.3130 | 33.39 | 747.8 | 231.4 | 0.492 |
| PC3 | 150–200 | 0.0769 | 175.0 | 0.7823 | 141.8 | 634.1 | 23.12 | 0.4052 | 38.81 | 781.5 | 289.0 | 0.618 |
| PC4 | 200–250 | 0.0795 | 225.8 | 0.8108 | 173.1 | 684.2 | 19.59 | 0.4957 | 44.04 | 810.0 | 345.9 | 0.743 |
| PC5 | 250–300 | 0.0833 | 275.0 | 0.8366 | 206.2 | 731.3 | 16.95 | 0.5899 | 49.38 | 835.7 | 404.5 | 0.872 |
| PC6 | 300–350 | 0.0833 | 325.0 | 0.8613 | 242.5 | 778.0 | 14.82 | 0.6937 | 55.16 | 860.4 | 467.3 | 1.012 |
| PC7 | 350–425 | 0.1333 | 386.7 | 0.8899 | 290.9 | 833.9 | 12.74 | 0.8352 | 62.88 | 889.0 | 549.1 | 1.195 |
| PC8 | 425–525 | 0.1524 | 471.7 | 0.9266 | 364.4 | 908.7 | 10.58 | 1.0618 | 74.95 | 925.7 | 669.1 | 1.466 |
| PC9 | 525–760 | 0.2143 | 613.9 | 0.9822 | 504.1 | 1028.5 | 8.08 | 1.5647 | 100.96 | 981.2 | 886.6 | 1.963 |

Bulk: SG 0.8656 (31.96 °API), mean MW 216.9 g/mol.

### 9.2 Column topology (theoretical stages, numbered from the top)

| Item | Stage / value |
|---|---|
| Total condenser + drum with water boot | stage 0; drum at 45 °C target (CW), pressure 1.4 bar(a) (P_top − 0.2 bar line loss) |
| Main column | stages 1–30, valve trays, D_c = 3.2 m, TS = 0.75 m (preset; checked by VALIDATION.md VC-15 sanity limits) |
| Kerosene draw → side stripper SS1 (2 stages) | draw from stage 8, SS1 vapour returns to stage 7 |
| Diesel draw → SS2 (2 stages) | draw from stage 15, SS2 vapour returns to stage 14 |
| AGO draw → SS3 (2 stages) | draw from stage 21, SS3 vapour returns to stage 20 |
| Pumparound (one, around the diesel section) | draw from stage 16, cooled by Q_PA, returned to stage 14 |
| Flash zone (feed) | stage 26: crude from the furnace at COT, two-phase |
| Stripping section | stages 27–30; bottom stripping steam enters below stage 30 |
| Residue | liquid from stage 30 into the sump (stage 31), level-controlled |
| Naphtha | liquid distillate from the drum, level-controlled |

Feed enthalpy: isothermal flash of the crude (plus no steam) at COT and flash-zone pressure P_26 (§3.6.3); the two-phase feed enters stage 26's balances. Overflash (displayed KPI) = liquid flowing from stage 25 to 26 as vol % of crude.

### 9.3 Steam

Water (steam) is a vapour-only component in the column: it never appears in hydrocarbon liquid (immiscible and above its dew point). Per stage, steam flow S_j passing upward = sum of all steam injected at or below stage j. The vapour leaving stage j is V_j = V_HC,j + S_j with steam mole fraction y_w,j = S_j / V_j. Hydrocarbons boil at their partial pressure (§3.6.1). Energy: steam enters at its injection temperature (default 200 °C superheated, h_V,water) and cools to each stage temperature; in (4.6) replace V by V_HC and add S_{j+1}(h_V,w(T_{j+1}) − h_V,w(T_j)) to the numerator.

Water dew-point check on stage 1: if P_1 y_w,1 > P_sat,water(T_1) the snapshot raises "water condensing in top trays" (corrosion risk; free water is not modelled). In the drum all steam condenses and leaves through the water boot.

### 9.4 Side strippers

Each stripper is a 2-stage chain with tray hydraulics (weir holdup, no ΔP coupling to the main column), stripping steam below its bottom stage, liquid product from its bottom stage (weir outflow; no level control).

Coupling with exact conservation (each flux appears once, identically, on both sides):
1. Strippers are solved **first** each step. Their liquid feed is the draw S_d with the main column's draw-stage composition at the start of the step, x_d^n.
2. Their top-stage vapour V_s with composition y_s^(n+1) is then a known vapour feed to the main column's return stage in the same step.
3. The main column's draw is an explicit sink S_d x_d^n (limited to 0.5 M_d/dt; if the tray cannot supply it, the draw falls short and the FC saturates — "draw tray dry", F27).

### 9.5 Pumparound

Draw P_PA from stage d_PA with composition x^n_{d} (explicit sink, same limit), cooled by Q_PA, returned as liquid to stage r_PA with the same composition and enthalpy h_L(x_d, T_d) − Q_PA/P_PA (the return temperature follows; displayed). Exact conservation by construction. Energy: the return enters (4.6) on stage r_PA as a liquid return R with h_R.

### 9.6 Product properties

For each product stream (naphtha, kerosene, diesel, AGO, residue):

1. Volume fractions of pseudo-components: v_i = x_i MW_i/ρ_ref,i, normalised.
2. Product TBP curve: each pseudo-component occupies its volume share spread linearly over its assay cut range [T_lo,i, T_hi,i]; components are ordered by T_b; the cumulative curve is piecewise linear.
3. ASTM D86 by the Daubert (Hydrocarbon Processing 73(9) (1994) 75) TBP→D86 inversion (temperatures in °F):

```
D86_50 = (TBP_50 / 0.8718)^(1/1.0258)
ΔD86   = (ΔTBP / A)^(1/B)       for the intervals:
  50→30: A = 3.0305, B = 0.8008      30→10: A = 4.9004, B = 0.7164      10→0:  A = 7.4012, B = 0.6024
  50→70: A = 2.5282, B = 0.8200      70→90: A = 3.0419, B = 0.7550      90→100: A = 0.1180, B = 1.6606
D86_5  = (D86_0 + D86_10)/2      D86_95 = (D86_90 + D86_100)/2
```

4. Gaps: gap(heavy, light) = D86_5(heavy) − D86_95(light). Positive = gap, negative = overlap.
5. D86 is shown for naphtha, kerosene, diesel and AGO only; residue shows TBP (D86 is not run on residues).

---

## 10. Control system and instruments

This section is the M3 contract (revised 2026-10-12, v1.1). It replaces the v1.0 "ideal flow controller"; §10.4 says why. Tags, spans and tunings are for the B-T preset; other presets list theirs in `control_config.dart` (ENGINE_API.md §10). Everything here is deterministic for a given seed (§12.9).

### 10.1 Objects and timing

| Object | B-T tags | Updated in |
|---|---|---|
| Valves | FV-101 feed, FV-102 reflux, FV-103 boilup (T1) / steam (T2/3), LV-101 distillate, LV-102 bottoms, PV-101 cooling water (T2/3, total condenser), PV-102 vapour product (partial condenser) | fast layer |
| Flow transmitters | FT-101 feed, FT-102 reflux, FT-103 boilup / reboiler duty, FT-104 distillate, FT-105 bottoms, FT-201 cooling water (T2/3) | fast layer |
| Flow loops | FC-101, FC-102 (with the ratio station), FC-103 | fast layer |
| Other instruments | LT-101, LT-102, PDT-101, AT-100, AT-101, AT-102; from M4 PT-101, PT-201, TI-100, tray TIs, TI-201, TI-202 | main layer |
| Other loops | LC-101, LC-102; from M4 PC-101, TC-101 | main layer |
| Alarms, cross-check bins | | main layer |

**Fast layer.** Sub-step δ_c = 0.1 s; n_c = round(dt/δ_c) sub-steps per main step (5 at dt = 0.5 s, 20 at 2 s, 300 at 30 s). It runs at step 2 of the main step (§12.4) and covers the interval [t, t + dt]. Everything it needs from the column (pump limits, Q_max) is frozen at the start-of-step state, as for the thermosyphon (§8.3). Order inside one sub-step:

1. For every valve, in the fixed order FV-101, FV-102, FV-103, LV-101, LV-102, PV-101, PV-102: position update from the current command (§10.3), then valve flow F_k (§10.3), then the flow transmitter on that line (§10.5). With a thermosyphon reboiler (M6), FV-103's step runs one thermosyphon sub-step (§8.3.4) between its valve flow Q_v,k and FT-103, so FT-103 measures that sub-step's steam-chest duty Q_st,k (§8.3.4).
2. For every flow loop in tag order: ratio station (FC-102 in ratio mode, §10.2), then PID execution (§10.2) with h = δ_c. The new OP acts on the valve from the next sub-step.

The flow that every column balance uses in the main step is the mean over the sub-steps:

```
F̄ = (1/n_c) Σ_{k=1..n_c} F_k                                                          (10.0)
```

F_k is the valve flow after the position update of sub-step k. `StepDebug` and the snapshot report F̄ (DEVIATIONS.md E5), so conservation stays exact (VC-5).

**Main layer**, at step 12 with the end-of-step state: every non-flow instrument updates with h = dt, then the loops LC-101, LC-102, PC-101, TC-101 execute in that order (h = dt). Their OPs reach their valves, or for TC-101 the FC-103 setpoint, in the next step's fast layer. Alarms are evaluated last (§10.8).

**Why a fast layer.** A real flow loop has a closed-loop time constant of 2–5 s, shorter than the fast-forward step (2 s). Executed once per main step it would respond differently at every dt and go unstable at dt = 2 s. With a fixed 0.1 s sub-step the loop behaves identically at every main step: with noise off and constant inputs, the sub-step sequence is bit-identical at dt = 0.5 s and 2 s (VC-16.4). Cost: about 30 flops per valve per sub-step, ≈ 1 µs per main step.

### 10.2 PID algorithm (velocity form)

PV and SP are normalised to percent of the span [lo, hi] of the loop's PV instrument. OP is percent.

```
PV%_k = 100 (PV_k − lo)/(hi − lo)            SP%_k likewise
s = +1 for direct action (OP rises when PV rises), −1 for reverse action
e_k = s (PV%_k − SP%_k)
PVf_k = PVf_{k−1} + (PV%_k − PVf_{k−1}) h/(τ_f + h)        τ_f = Td/8       (only when Td > 0)
ΔOP_k = Kc [ (e_k − e*_{k−1}) + (h/Ti) e_k + s (Td/h)(PVf_k − 2 PVf_{k−1} + PVf_{k−2}) ]          (10.1)
OP_k  = clamp(OP_{k−1} + ΔOP_k, OPLO, OPHI)
```

- h is the execution interval: δ_c for flow loops, dt for all other loops. Kc is %OP per %span. Ti and Td are in seconds; Ti = ∞ disables the integral term.
- **Derivative sign.** The derivative acts on the filtered PV, so a setpoint change gives no derivative kick. It carries the same sign s as the error, so for direct action a rising PV raises OP. v1.0 printed "− s"; that was wrong. Every default loop has Td = 0, so no existing behaviour changes.
- **Proportional kick on setpoint changes.** e*_{k−1} is normally e_{k−1}. If the loop's `spKick` is false, any setpoint change by the operator (lever, faceplate), a scenario event or setpoint tracking re-bases it: e*_{k−1} = s (PV%_{k−1} − SP%_new). A setpoint step then acts through the integral term only, so the output does not jump when the learner drags a level SP. Cascade setpoint updates never re-base. Defaults: `spKick` = true for flow loops (normal PI on error) and false for LC, PC and TC loops (DEVIATIONS.md E12 is adopted here).
- **Anti-windup** is the clamp itself: the velocity form stores no integral, so OP leaves a limit on the first execution after the error changes sign (VC-16.2).
- **Execution in MAN or IMAN.** PV%, e and PVf are updated every execution, but OP is not changed by the PID. Switching to AUTO is therefore bumpless.

**Modes and transfers.**

| Mode | OP comes from | SP comes from |
|---|---|---|
| MAN | the user (lever bound to the loop, or the faceplate) | held |
| AUTO | the PID | the user |
| CAS | the PID | the master: SP = lo + (OP_master/100)(hi − lo) of this loop's span, clamped to the SP limits |
| IMAN (masters only) | tracks the slave's SP: OP = 100 (SP_slave − lo_s)/(hi_s − lo_s) | held |

- MAN → AUTO: SP := current PV, and e*_{k−1} := 0. This is setpoint tracking; the faceplate shows "SP tracked PV". OP does not move on the switch (VC-16.3).
- AUTO → MAN: OP is held.
- A master is in IMAN whenever its slave is not in CAS. Its OP tracks the slave SP, so switching the slave to CAS gives no SP bump. The master's own requested mode (AUTO or MAN) is remembered and resumes when the slave returns to CAS.
- CAS → AUTO: the slave SP is held at its last cascade value.
- `tc101Enable` = 1 sets TC-101 to AUTO with SP := TI PV, and sets FC-103 to CAS; both transfers are bumpless. `tc101Enable` = 0 sets FC-103 to AUTO with its SP held.
- SP limits are the bound lever's range (SCOPE.md §4). OP limits OPLO/OPHI default to 0/100. TC-101 uses 20/65 % of the FC-103 span (600–1950 kW for B-T), so a lying temperature cannot drive the duty to zero or full.

**BAD PV handling.** This is set per simulation by the lever `badPvShed`: 1 = shed (default), 0 = none.

- Shed: on the execution where the PV quality becomes BAD or OOS (§10.5), the loop drops to MAN with OP held. The faceplate shows "MAN (shed)" and alarm `<loop>.SHED` is raised. AUTO and CAS cannot be selected while the PV is BAD. The master of a shed slave goes to IMAN. This is modern DCS behaviour.
- None: the loop keeps executing on the converted failure value (−2.5 % or 106.25 % of span, §10.6), which drives its valve to a limit. This is the behaviour of old systems without failure detection; drill H9 uses it.
- In both cases the instrument's own BAD alarm is raised (§10.8).

**Ratio station** (FC-102 in ratio mode, `refluxMode` = 1): FC-102 SP = R × (FT-104 reading), updated every sub-step before FC-102 executes. When FT-104 is BAD or OOS, the station holds the last SP computed from a GOOD reading. Ratio SP updates count as cascade updates: no re-basing.

### 10.3 Valves

```
command   c = OP                                      (normal)
            = 100 (failOpen), 0 (failClosed)          (F20)
position  p ← p + (c − p) h/(τ_v + h)                 τ_v = 2.0 s, implicit, every sub-step; frozen when F20 'stuck'
flow      F_valve = F_max · g(p) · (1 + d)
          g(p) = p/100                                (linear; every shipped valve)
          [option g(p) = (R^(p/100) − 1)/(R − 1), R = 50, "modified equal-percentage", g(0) = 0, g(100) = 1]
          d: supply disturbance (pump head and header pressure), Ornstein–Uhlenbeck with σ_d = 0.010, τ_d = 30 s
             (§10.5 discretisation); d = 0 when noise is off
          F_k = clamp(F_valve, 0, F_cap)                                                   (10.2)
```

- **F_cap.** F_cap is +∞, except in three cases:
  - Fault F12 sets F_cap = (1 − s) F_max for FV-102.
  - If the main step's hydraulic stage had to cut this valve's flow in the previous step (pump limit of §7.3/§8.1: the drum or sump could not supply it), F_cap = the flow actually delivered in that step.
  - The hydraulic stage keeps the exact holdup ≥ 0 limit. When it cuts a flow, the cut value is what the balances, the snapshot and `StepDebug` use, and the transmitter sees it from the next step on.
- **Steam valve FV-103, Tiers 2/3.** It delivers duty, not a molar flow:
  - F_max·g(p) becomes the duty request Q_v = Q_max,0 · g(p)(1 + d), where Q_max,0 = UA_R,clean (T_st − T_{N+1}) is the clean-exchanger maximum at the start of the step.
  - The delivered duty is Q_k = min(Q_v, Q_max), with Q_max the fouled/flooded value of (8.2) (kettle) or of §8.3 (thermosyphon, where Q_v takes the place of Q_R,SP).
  - Thermosyphon (M6, §8.3.4): Q_max,0 = UA_R,clean (T_st − T_b,mean) with UA_R,clean = U A (B-T 47.6 kW/K; Q_max,0 ≈ 1636 kW at 50 % level with the VC-14.1 inputs, so the 1300 kW design duty sits at ≈ 79 % open; column-coupled at E = 0.7 the sump is ≈ 0.8 K cooler, Q_max,0 ≈ 1677 kW and the OP ≈ 77.6 %, ratified 2026-10-13). Q_k comes from the thermosyphon sub-step. FT-103 measures the steam-chest duty Q_st (§8.3.4), and the column receives the sub-step mean of Q_k (1 + u_k).
  - Q_R,delivered = Q̄. This replaces "min(Q_R,SP, Q_max)" in (8.2). The duty limit now shows physically: FC-103 opens the valve to 100 % and the duty still falls short.
  - The v1.0 "steam valve OP (display) = 100 Q/Q_max" is no longer needed, because the valve position is real.
- **Tier 1 FV-103** delivers boilup V_B = F_max g(p)(1 + d) with F_max = 300 kmol/h. In both tiers, the FT-103 reading is what V_B or Q_R becomes.
- **No position feedback.** The DCS sees OP only, as on most plants; the snapshot carries p for the model view. Plant view masks it (§10.9).
- **Bypass** (F20 fix, operator action). Lever `bypass.<valve>` takes −1 (closed, default) or 0–100 % opening. When it is ≥ 0, the control valve is isolated and the line flow is F_max g(b)(1 + d). The opening b follows the lever at most 2 %/s, the speed of a person turning a hand wheel. The loop is forced to MAN, and the transmitter keeps measuring the line flow.

| Valve | F_max (B-T) | Characteristic |
|---|---|---|
| FV-101 | 250 kmol/h (= FT-101 span) | linear |
| FV-102 | 300 kmol/h (= FT-102 span) | linear |
| FV-103 | T1: 300 kmol/h (= FT-103 span); T2/3: Q_max,0 (≈ 2170 kW at design, so design duty is at 60 % open, §8.2) | linear |
| LV-101 | D_max = 2 × design D = 100 kmol/h | linear |
| LV-102 | B_max = 100 kmol/h | linear |
| PV-101 | ṁ_cw,max (150 m³/h) | linear (§7.2 already uses ṁ_cw = OP/100 · ṁ_cw,max) |
| PV-102 | D_V,max | linear, with the √ΔP term of (7.5) |

Valve F_max equals the FT span on the three flow loops, so their process gain is 1 %span per %OP (Tier 1). This makes the valve-characteristic cross-check (§14.6) a straight line a learner can read.

### 10.4 Flow loops

FC-101 (FT-101 → FV-101), FC-102 (FT-102 → FV-102) and FC-103 (FT-103 → FV-103) are real PI loops on the *measured* flow, executed in the fast layer. Settings: reverse action, Kc = 0.6, Ti = 2.0 s, Td = 0, spKick = true.

Closed-loop response (prototype of this exact algorithm). Reflux SP step 100 → 110 kmol/h, noise off:

| Measure | Value |
|---|---|
| True flow reaches 63 % of the step | 3.0 s |
| Measured flow reaches 63 % | 3.5 s |
| Overshoot | none |
| Within 1 % of the step | 12.5 s |

This is the τ_FC ≈ 3 s of v1.0, now produced by a loop instead of being imposed. In Tier 2 the duty loop has gain Q_max,0/3000 kW ≈ 0.72 and reaches 63 % in 4.2 s (v1.0: "5 s for duty"). At steady state with noise off, the integral action makes measured flow = SP exactly, so every v1.0 steady state is unchanged.

**Why v1.0's ideal flow controller was dropped.** Instrument and valve faults (F19, F20, F28) and drills H3, H6, H9 and H10 need a controller that acts on the measured flow and has an OP that can move while the flow does not. An ideal controller (flow = lag(SP)) has neither.

**VC-7.2 and τ_FC.** The tester found the conflict: tray 1 must reach 63 % within 1–4 s of the lever change, which held with M1's 1 s ideal lag (DEVIATIONS.md E2/E18) but gives ≈ 4.7 s with a 3 s flow loop. VC-7.2 was derived from a prototype that stepped the *delivered* reflux directly, and its stated purpose is the weir hydraulics. It is therefore redefined to time each tray from the moment the delivered reflux reaches 63 % (VALIDATION.md VC-7.2). With that definition it holds for M1's 1 s lag (1.5 s and 29.0 s) and for this loop. The lever-to-flow dynamics have their own test (VC-16.4). From M3 on, E2/E18 are superseded.

Initialisation (cold start, warm start, rebuild, tier switch): each valve's p and c are set to the OP that gives the initialised flow, transmitter lags start at the true value, and e_{k−1} = 0.

### 10.5 Instrument model

Every transmitter runs the same pipeline on its true value v (SI) at each update (h = δ_c for FT, dt otherwise). Fault hooks are marked [F19]/[F28] (§10.6).

```
1  sensed signal     v_s = v + n_s                     n_s: OU(σ_s, τ_s) of the signal at the sensor
                                                       (turbulence, surface waves, froth temperature); 0 with noise off
2  impulse line      v_p = v_s                         [F28 plugged: v_p ← v_p + (v_s − v_p) h/(τ_plug + h)]
3  damping           v_m ← v_m + (v_p − v_m) h/(τ_m,eff + h)          τ_m,eff = τ_m   [F28 coated: τ_m (1 + 9 s)]
4  calibration       v_c = v_m + b                     [F19 bias / drift: b(t)]
5  4–20 mA           I = 4 + 16 (v_c − lo)/(hi − lo) + 0.16 n_e      n_e: white N(0, σ_e), % of span (electronics);
                                                                       0 with noise off
6  saturation        I = clamp(I, 3.8, 20.5)          (NAMUR NE43 measuring range: a process outside the span
                                                       reads −1.25 % or 103.125 %, UNCERTAIN, never BAD)
7  spikes            I = I + 0.16 a_spike             [F28 spiking], a_spike in % of span; may leave 3.8–20.5 mA
8  failure current   [F28 signal loss: I = 3.6 mA (low) or 21.0 mA (high)]
9  A/D               I_q = clamp(round(4096 I)/4096, 0, 24)   (65 536 counts over 4–20 mA; input card 0–24 mA)
                     — only with noise on; with noise off I_q = clamp(I, 0, 24) unrounded, so a noise-free run is
                       exact (a quantised PV would make every PI loop dither by one count forever and the
                       §13.3 monitor would never pass)
10 value             v_meas = lo + (I_q − 4)/16 · (hi − lo)
11 quality           BAD if I_q ≤ 3.6 or I_q ≥ 21.0 ; UNCERTAIN ("out of range") if I_q < 4.0 or I_q > 20.0 ;
                     OOS during maintenance ; else GOOD
[F19 stuck: steps 1–11 are skipped; v_meas, I_q and quality stay at their last values before the onset]
```

- Noise processes use the exact Ornstein–Uhlenbeck discretisation, so their statistics do not depend on h:

  ```
  n ← a n + σ √(1 − a²) ξ,      a = exp(−h/τ),   ξ ~ N(0, 1) from the instrument's own stream (§12.9)
  ```
- **Typical σ of flows set by a level loop.** FT-104 and FT-105 measure flows that LC-101 and LC-102 move in response to level noise (P action: σ_OP = Kc σ_disp,LT). Their healthy σ — `typicalSigma` in the snapshot and the "typical" of the signal look — is therefore σ_typ = √(σ_disp² + (Kc_LC · σ_disp,LT · F_max/span)²). B-T: FT-104 √(0.409² + (2 × 0.423)²) = 0.94 % of span; FT-105 √(0.409² + (2 × 0.775)²) = 1.60 % (tester measured ≈ 2.4 × σ_disp for FT-104).
- **Typical σ of process-driven tags, Tiers 2/3** (decided 2026-10-12 from the M4 validation). PT-101, TI-100, FT-201 and TI-202 read quantities that the pressure loop and the CW supply disturbance keep moving. Their transmitter noise is tiny (TI-202: 0.044 K), so against σ_disp alone a healthy Tier-2 drill read 1.2–3.8 (PT-101), 0.7–2.4 (TI-100), 2.4–8.4 (FT-201) and 3.2–14.7 (TI-202), and the signal look would call them erratic. Their σ_typ = √(σ_disp² + σ_proc²), with σ_proc built from window means of readings only (no truth leaks into the "typical"):

  | Tag | σ_proc | B-T design value |
  |---|---|---|
  | PT-101 | σ_P = 0.0015 · SP (healthy pressure wander under PC-101) | 0.15 kPa |
  | TI-100 | (dT_bub/dP) · σ_P, slope of the design distillate's bubble point at the design pressure (preset constant) | 0.32 K/kPa → 0.05 K |
  | FT-201 | c_F · F̄_201, with c_F = σ_d = 0.010 when PC-101 is in MAN (supply disturbance only, §10.3), and 0.022 in AUTO/CAS (the loop adds its own movement) | AUTO, 75 m³/h: 1.65 m³/h |
  | TI-202 | c_F · (T̄_202 − T̄_201) (water rise × relative flow σ, at constant duty) | AUTO: 0.32 K |

  F̄_201, T̄_201 and T̄_202 are means of the readings over the same 300-s window as σ_5min. SP and PC-101's mode are taken at the time of evaluation. σ_typ is re-evaluated whenever σ_5min is (each 5-s trend bin), so it changes with time. Units: σ_P in Pa (PT-101 span), TI σ in K, FT-201 σ in the meter's SI unit; the snapshot carries σ_typ in the same SI unit as `sigma5min`.

  0.0015 and 0.022 are **[impl-tunable]**, calibrated on the B-T H9 drill configuration so that the median healthy ratio is ≈ 1. TI-202's windows still spread by a factor ≈ 4.6, more than the 0.5–2 band allows, so H9.0/H10.0 judge these four tags on 0.33–3 (VALIDATION.md). That stays well clear of the fault thresholds (≤ 0.2 frozen or plugged, ≥ 5 erratic). Every other tag uses σ_disp, or the level-loop rule above for FT-104/105.
- **Displayed noise.** For a healthy transmitter (continuous-time value):

  ```
  σ_disp = √( σ_s² τ_s/(τ_s + τ_m) + σ_e² )
  ```

  The discrete pipeline stays within 4 % of it at h ≤ 2 s.
- **Noise switch.** Lever `noise` (0/1) enables n_s, n_e and the valve disturbances d together. When it is off they are 0 and their streams draw nothing. When switched on, every noise state starts at 0. Fault randomness (spikes, drill draws) uses separate streams and does not depend on this lever.
- **Initialisation.** v_m = v and v_p = v at the start. With noise off, a healthy transmitter reads v to round-off (no quantisation, step 9), so every noise-off steady state and validation number of M1/M2 is unchanged.

**Parameters by type** (B-T spans; % of span unless stated):

| Type | Tags and spans | τ_m | σ_s | τ_s | σ_e | σ_disp | Physical source |
|---|---|---|---|---|---|---|---|
| FT, liquid (orifice ΔP, √-extracted) | FT-101 0–250 kmol/h, FT-102 0–300, FT-103 (T1) 0–300, FT-104 0–100, FT-105 0–100 | 0.5 s | 0.50 | 1 s | 0.02 | 0.409 % (FT-102: 1.23 kmol/h) | turbulence at the orifice |
| FT, steam (duty) | FT-103 (T2/3) 0–3000 kW | 0.5 s | 0.50 | 1 s | 0.02 | 0.409 % (12.3 kW) | as above |
| FT, cooling water (magnetic) | FT-201 0–150 m³/h | 0.5 s | 0.30 | 1 s | 0.02 | 0.246 % | |
| LT, drum (ΔP cell) | LT-101 0–100 % | 2 s | 0.50 | 5 s | 0.02 | 0.423 % | surface waves from the reflux return |
| LT, sump (ΔP cell, boiling liquid) | LT-102 0–100 % | 2 s | 1.00 | 3 s | 0.02 | 0.775 % | boiling and vapour disengagement |
| PT | PT-101 0–2 max(P_design, SP_PC-101) (§10.7; B-T at design 0–202.65 kPa abs), PT-201 steam header 0–1000 kPa g | 1 s | 0.05 | 2 s | 0.02 | 0.046 % (PT-101: 0.09 kPa) | |
| PDT | PDT-101 column ΔP 0–40 kPa (top vapour space to sump) | 2 s | 1.00 | 5 s | 0.02 | 0.845 % (0.34 kPa) | froth fluctuations |
| PDT, packed bed (M8) | PDT-(101 + b) for packed bed b = 1, 2, … from the top: 0–10 kPa | 2 s | 1.00 | 5 s | 0.02 | 0.845 % (0.085 kPa) | two-phase flow fluctuations |
| TI, tray and sump (RTD in a thermowell) | TI-1jj, TI-1(N+1): 0–200 °C | 10 s | 0.075 (0.15 K) | 20 s | 0.01 (0.02 K) | 0.062 % (0.124 K) | froth temperature fluctuations |
| TI, liquid line | TI-100 reflux (drum outlet), TI-201/202 CW in/out: 0–200 °C | 10 s | 0.025 | 20 s | 0.01 | 0.022 % | |
| AT, process GC | AT-100 feed light component 0–1; AT-101 heavy impurity in D 0–0.10; AT-102 light impurity in B 0–0.10 (mol frac) | see below | – | – | 0.5 per result | 5×10⁻⁴ (AT-101/102) | repeatability |

Tag rule for tray TIs: TI-(100 + j) for tray j, TI-100 for the drum, TI-(100 + N + 1) for the sump (B-T: TI-121). Packed segments follow the same rule (a bed thermocouple at the height of segment j; `bt_packed`: TI-101 … TI-118, sump TI-119). PDT-(101 + b) measures the ΔP of packed bed b, the sum of its segments' ΔP_k (0 in ideal hydraulics).

Instrumented trays come from the control config list `temperatureTrays`; B-T uses [1, 4, 7, 10, 12, 14, 17, 20]. On a tray-count rebuild (§13.4) each entry keeps its fractional height, the result is de-duplicated, and the TC-101 tray is always included. The `tc101Tray` lever only offers instrumented trays.

Measured quantities:
- PDT-101 measures P_{N+1} − P_top (0 in ideal hydraulics).
- TI-100 measures the reflux temperature T_0 (§7.3, after subcooling).
- TI-202 measures T_cw,in + Q_C/(ṁ_cw c_p,w).
- FT-201 measures ṁ_cw/ρ_w with ρ_w = 995 kg/m³.
- FT-103 measures the delivered boilup (T1) or, in T2/3, the steam-side duty: Q_k with a kettle, the steam-chest duty Q_st (§8.3.4) with a thermosyphon.
- **Analysers on multicomponent presets (M7).** The GC separates every component, and the three tags carry key cuts. For a binary these reduce exactly to the definitions in the table.
  - AT-100: the feed light cut, Σ z_i over the LK and every lighter component.
  - AT-101: the heavy cut in D, Σ x_D,i over the HK and every heavier component (`kpi.xDHeavy`).
  - AT-102: the light cut in B, Σ x_B,i over the LK and every lighter component (`kpi.xBLight`).
  - Each published result also carries the full sampled composition. The Products tab lists it, aged like the tag value.
  - Design values: `debut` 0.450 / 0.0112 / 0.0102; `deprop` 0.300 / 0.0344 / 0.0041.

**Analysers (AT).** A sample system plus a cyclic gas chromatograph, updated in the main layer:

```
v_ss ← v_ss + (v − v_ss) dt/(τ_ss + dt)              τ_ss = 60 s sample-line mixing   [F28 plugged: τ_ss + τ_plug]
sample times t_k = φ + k T_c,  T_c = 300 s           phase φ: AT-100 0 s, AT-101 100 s, AT-102 200 s
at the first main step ending at or after t_k:  r_k = v_ss + b(t_k) + σ_a ξ_k   (σ_a = 0.5 % of span; noise on only)
publish r_k, rounded to 1×10⁻⁴ and clamped to [lo, hi], at the first step ending at or after t_k + T_c (analysis time);
hold it until the next publication
quality: GOOD ; UNCERTAIN ("stale") when the shown result is older than 2 T_c ; BAD on signal loss
         ("analyser fault": no further results; the held value is flagged)
```

A displayed analysis is therefore 300–600 s old (mean ≈ 450 s, plus the 60 s sample lag): composition control by analyser is slow, which is why TC-101 exists.

**Field gauges** (the redundant instruments of the F19/F28 "fix" column):
- LG-101 is the drum sight glass, LG-102 the sump sight glass, and PG-101 a local overhead pressure gauge (T2/3).
- A "field check" request returns the true value 180 s of sim time later (the operator's walk).
- Readings are rounded to the glass graduations (2 % level) with a reading error N(0, 1 %), or to 0.01 bar with N(0, 0.005 bar). Errors are drawn from stream `field:<tag>`.
- Gauges never fail, and only one request per gauge can be pending at a time. Requests are logged in the drill timeline; good practice is not penalised.

**Maintenance** (sandbox only; it is the "flag instrument for maintenance" fix). The instrument goes OOS for 1800 s; loops on it shed to MAN whatever `badPvShed` says. Then every fault on that tag clears, and the transmitter returns GOOD with fresh lag and noise states. Maintenance is disabled in drills, where the Diagnose button takes its place.

### 10.6 Instrument failure modes (F19, F28) and valve faults (F20)

A fault acts on one tag. s is the current severity (11.1) and σ = ±1 the fault's sign (`params.sign`, or drawn in drills).

| Mode | Fault | Applies to | Model | Default τ_r |
|---|---|---|---|---|
| `bias` | F19 | every transmitter, AT | b = σ · s · 0.10 (hi − lo), pipeline step 4 | 0 |
| `drift` | F19 | every transmitter, AT | b(t) = σ · s · 0.10 (hi − lo) · (t − t₀)/3600 s | 0 (the drift is its own ramp) |
| `stuck` | F19 | every transmitter, AT | outputs frozen at their last pre-onset values (no noise, no quantisation flicker) | 0 |
| `signalLossLow` | F28 | every transmitter | I = 3.6 mA → v_meas = lo − 0.025 (hi − lo) (step 8 overrides saturation) | 0 |
| `signalLossHigh` | F28 | every transmitter | I = 21.0 mA → v_meas = lo + 1.0625 (hi − lo) | 0 |
| `signalLoss` | F28 | AT | analyser fault: no new results | 0 |
| `plugged` | F28 | FT, LT, PT, PDT; AT (sample line) | extra lag τ_plug = 10^(4s) − 1 s (s = 0.5: 99 s; 0.75: 999 s; 0.9: 3980 s; 1: 9999 s). The state starts at the sensed value at onset. A step in the true value shows only 45 % (s = 0.75), 14 % (0.9) or 6 % (1.0) after 10 min | 300 s |
| `spiking` | F28 | FT, LT, PT, PDT, TI | Spikes arrive as a Poisson process with rate s/20 s⁻¹. Each spike adds a_spike = σ_k · s · (10 + 40 u) % of span to the current for 1.0 s (at least one update). σ_k = ±1 and u ∈ [0, 1) are drawn from stream `inst:<tag>:spike`. σ_e × 5 while the fault is active | 0 |
| `coated` | F28 | TI | τ_m,eff = τ_m (1 + 9 s): 100 s instead of 10 s at s = 1 | 0 |

**What the learner sees, and what the DCS shows.**

| Mode | On the trend and faceplate | Loop on this PV (AUTO) | DCS quality / alarm |
|---|---|---|---|
| bias | A step at onset with no process cause; noise looks normal | Moves the true value by −b: for FT-102 at σ = +1, s = 0.3 (+9 kmol/h), the true reflux settles at 91 kmol/h and the OP at 30.3 % instead of 33.3 % | GOOD; nothing |
| drift | Slow creep; noise normal | Walks the true value away at the drift rate | GOOD until the current saturates (UNCERTAIN, `<tag>.OOR`) |
| stuck | Perfectly flat line: the same digits for minutes, 5-min σ = 0 | Integrates the frozen error, so its OP ramps while nothing responds | GOOD; nothing |
| signal loss | Jumps to −2.5 % or 106.25 % of span | Shed to MAN (`badPvShed` = 1) or driven to a valve limit (= 0) | BAD: PV digits grey; red "BAD" badge with "IOP−" (low) or "IOP+" (high); BAD segments dashed in trends; alarm `<tag>.BAD` (high) |
| plugged | Stops following the process; the fuzz collapses from σ_disp to σ_e, 20× smaller ("too steady"); fast 0.5-s differences fall from 0.71 to 0.09 kmol/h on FT-102 | A flow loop keeps integrating the small offset between SP and the trapped value. Prototype (FC-102, s = 1, noise on): the true reflux swung between ≈ 50 and 150 kmol/h over 30 min while the reading stayed at SP | GOOD; nothing |
| spiking | Spikes of up to 50 % of span; a spike reaches BAD when it carries the current past 3.6 or 21.0 mA, i.e. a negative spike larger than (I₀ − 3.6 mA)/0.16 % of span or a positive one larger than (21.0 mA − I₀)/0.16 (I₀ the pre-spike current; at 33 % of span: negative spikes > 35.8 %, positive never). Intermittent BAD or out-of-range flicker | Proportional action kicks the valve at each spike | Intermittent BAD / OOR alarms (they latch, §10.8) |
| coated | Lags its neighbours after any change (t63 82–100 s instead of 10 s); fuzz about halved (0.033 vs 0.062 % of span at s = 1) | A TC loop on it becomes sluggish and may cycle | GOOD; nothing |

**Valve faults (F20).** Location is a valve id; `params.kind` is one of:
- `stuck`: p frozen at its onset value. OP keeps moving, because the loop integrates the supply disturbance d, while the flow follows only d. Prototype, FC-102 with noise on: OP wandered 34–45 % within 10 min while the reflux stayed within ±2 %.
- `failOpen`: c = 100. Flow goes to F_max within about 5 s, and the loop drives OP to 0.
- `failClosed`: c = 0.

The DCS shows no valve fault (there is no position feedback). The only signs are OP versus flow (§14.6, C4) and `<loop>.OPSAT` once OP saturates.

**Comparing look-alikes** (the H10 logic):
- A stuck valve and a plugged flow transmitter both show OP moving while the reading barely moves. The plugged meter's trend is too smooth and the balances disagree. The stuck valve's trend has normal noise and the balances agree.
- A biased meter fails both its own valve check and a balance.
- A real upset fails nothing.

### 10.7 Loops of the B-T preset

| Tag | PV instrument (span) | MV | Action | Default mode | Kc | Ti (s) | Td | spKick | OP limits | Rate | Tier |
|---|---|---|---|---|---|---|---|---|---|---|---|
| FC-101 | FT-101 (0–250 kmol/h) | FV-101 | reverse | AUTO | 0.6 | 2.0 | 0 | yes | 0–100 | δ_c | all |
| FC-102 | FT-102 (0–300 kmol/h) | FV-102 | reverse | AUTO (ratio mode: SP = R × FT-104) | 0.6 | 2.0 | 0 | yes | 0–100 | δ_c | all |
| FC-103 | FT-103 (T1 0–300 kmol/h; T2/3 0–3000 kW) | FV-103 | reverse | AUTO (CAS when TC-101 is enabled) | 0.6 | 2.0 | 0 | yes | 0–100 | δ_c | all |
| LC-101 | LT-101 (0–100 %) | LV-101 | direct | AUTO | 2.0 | 1800 | 0 | no | 0–100 | dt | all |
| LC-102 | LT-102 (0–100 %) | LV-102 | direct | AUTO | 2.0 | 1800 | 0 | no | 0–100 | dt | all |
| PC-101 | PT-101 (0–2 max(P_design, SP), below) | PV-101 (total condenser) / PV-102 (partial) | direct | AUTO | 10, scheduled below 35 % OP (below) / 2.0 | 120 / 30 | 0 | no | 0–100 | dt | T2/3 |
| TC-101 | TI on the chosen tray (0–200 °C) | FC-103 SP (cascade) | reverse | disabled (MAN) | 4.0 | 900 | 0 | no | 20–65 | dt | T2/3 |

TC-101's Kc = 4.0 on the 200 K TI span equals v1.0's 1.0 on the old 50 K span (T_top − 10 K … T_bottom + 10 K): 30 kW per 0.5 K.

**PC-101, total condenser: Kc 10, Ti 120 s** (M4 prototype; v1.0: 2 / 60 s). Even at the 50 % design point (§7.2) the CW valve is a weak handle: about 580 Pa per % OP (0.29 % of span per % OP), with an open-loop time constant of about 190 s set by the column's heat storage. With v1.0's tuning a +10 kPa SP step took 695 s to settle within ±1 kPa (VC-16.6 asks for 10 min). With 10 / 120 it settles in 297 s (+10 kPa) and 438 s (−10 kPa) without overshoot. PV-102 for the partial condenser acts directly on the vapour flow: **Kc 2.0, Ti 30 s** (ratified 2026-10-13 from the M4 engine, 1155f40; v1.0: 1.0 / 30 s, which took 710 s to settle a +10 kPa step within ±1 kPa). With 2.0 the ±10 kPa steps settle in 505 / 515 s with 15 % / 12.5 % overshoot (B-T, CW 30 %, VC-16.6b).

**PC-101 gain schedule, total condenser** (ratified 2026-10-12 from DEVIATIONS.md E47). The CW valve gets far stronger as it closes. From (7.3), dQ_C/dm_cw ∝ a/(m_cw + a)² with a = UA_eff/(2 c_p,w) (B-T 3.3 kg/s; linear valve, m_cw,max 41.5 kg/s). Relative to the 50 % design point that is ≈ 1.8× at 35 % open, ≈ 12× at 9 % and ≈ 17× at 6 %. The tuned controller limit-cycles down there: G8 at 2–3 bar with 15 °C water works at 5–7 % OP (V₁ swung between 50 and 210 kmol/h at dt = 2 s), and G9 turned down at 1 atm sits near 9 % (VALIDATION.md VC-28.8). PC-101 therefore uses

```
Kc_eff = Kc · clamp(OP/35, 0.1, 1)          OP = PC-101's own output at the previous execution
```

That keeps the B-T loop gain within ≈ 1.8–3× the design value from 35 % down to 3.5 % open. The schedule uses the controller's OP, not the valve position, as a DCS would; the two differ only through the actuator rate and valve faults (F20). In the velocity form (§10.2) a changing Kc is bumpless. Ti is unchanged. At and above 35 % OP the tuning is the plain one, so VC-16.6 is unaffected. It applies to every preset with a total condenser. With a partial condenser PC-101 drives PV-102, and (7.5) is linear in OP, so it is not scheduled.

**PT-101 range and alarms follow the pressure set point** (ratified 2026-10-12 from E48). PT-101 spans 0 to 2 · max(P_design, SP), where SP is PC-101's set point. A fixed 0–2 P_design span puts G8's 3 bar off scale: the controller then saw 208 kPa for ever, closed the CW valve and the relief valve lifted. Rules:
- The span is a function of the SP alone. It is re-derived whenever the SP changes, by any route (the `pTop` lever, `setSp`, a scenario event), and from the saved SP on restore, so one SP always gives one span. For SP ≤ P_design it is the design span.
- It is a transmitter re-range. σ_s, σ_e and F19 biases stay in % of span, the PC-101 history is rescaled, and PC-101's Kc stays in % of span, so its Pa-gain falls as 1/span above design. That is accepted: the higher pressures also have the larger condenser ΔT. The +10 kPa SP step of VC-16.6 therefore runs on a 222.65 kPa span.
- PT-101 `HI` / `LO` alarms sit at 1.15 / 0.85 × SP (§10.8), so a learner who moves the operating pressure does not live in alarm.

Crude (M9): TC-201 top temperature → FC reflux (direct, Kc 1.0 on a 50 K span, Ti 300 s); LC-201 drum → naphtha; LC-202 sump → residue; FC-201…203 side draws; FC-204 PA duty; TC-202 COT (ideal first-order, τ = 60 s: the furnace is not modelled); FC-205…208 steam. Every FC uses the flow-loop settings of §10.4.

Level loops are tuned for averaging: they absorb flow upsets instead of passing them on, which is normal practice for drum and sump levels. These are starting values. If a VC-16 loop check fails, the implementer may retune within ±50 % and must record the change in the preset JSON and DEVIATIONS.md.

### 10.8 Alarms

Each alarm has a stable id `<tag>.<type>` (or `model.<type>`), a priority (H/M/L), an on-delay, an off-delay and a deadband. It follows ISA-18.2 states:
- NORMAL → UNACK (raised; blinks in themes with `alarmBlink`)
- UNACK → ACKED (acknowledged, still active)
- ACKED → NORMAL when it clears
- UNACK → RTN-UNACK when it clears before acknowledgement (shown grey with "RTN" until acknowledged; acknowledgement removes it)

"Latch until acknowledged" means exactly the RTN-UNACK state.

| Type | Condition (on the measured PV unless stated) | Priority | On / off delay | Deadband |
|---|---|---|---|---|
| `HIHI` / `LOLO` | Levels > 95 % / < 5 % | H | 5 s / 10 s | 1 % |
| `HI` / `LO` | Levels > 85 % / < 15 %; PT-101 > 1.15 / < 0.85 × the PC-101 SP (§10.7); flows > 90 % of span (no LO for flows); AT-101, AT-102 > 0.05 | M | 5 s / 10 s | 1 % of span |
| `DEV` | Loop in AUTO/CAS and \|PV − SP\| > limit: flows 5 % of span, levels 10 %, PT-101 3 %, TC-101 2 K | M | 30 s / 10 s | clears below 80 % of the limit |
| `OPSAT` | Loop in AUTO/CAS, OP at OPLO or OPHI, and \|e\| > 2 % | M | 60 s / 10 s | – |
| `BAD` | Quality BAD (on a loop PV: H; display-only: M) | H/M | 0 / 10 s | – |
| `OOR` | Quality UNCERTAIN | L | 5 s / 10 s | – |
| `SHED` | Loop shed to MAN on BAD PV | M | 0 / – (clears when the learner acknowledges and the PV is GOOD) | – |
| `STALE` | Analyser result older than 2 T_c | L | 0 / 0 | – |
| `model.flood`, `model.weep`, `model.dcLimited`, `model.dutyLimited`, `model.tsUnstable`, `model.waterCondensing`, `model.drawDry` | As in v1.0: max flood % > 90, weep fraction > 0.3, any downcomer limited, Q_max,0 g(p) > Q_max for 60 s (§8.2), I_s > 1 (`tsUnstable` clears only below I_s 0.98, M6), crude conditions | M (dcLimited L) | 30 s / 30 s | – |
| `model.relief` | Relief valve lifting | H | 0 / 30 s | – |
| `model.solver` | Solver fallback (developer overlay only) / fatal (H) | L/H | 0 | – |

- With noise on, the delays and deadbands keep a level sitting near a limit from making an alarm chatter. The tests in VC-25 check this.
- The alarm list holds every alarm not in NORMAL, sorted by priority and then newest first. The banner shows the newest UNACK alarm of the highest priority.
- Every state change goes into the event journal with its sim time, and the journal feeds the debrief timeline.
- Acknowledge works for one alarm or for all.
- **Truth versus readings.** The safety score and the scenario predicates use true values (§10.9). Alarms use readings, so a lying transmitter raises or hides alarms exactly as on a real plant.

### 10.9 Plant view and model view

Lever `view`: 0 = model view (default), 1 = plant view, 2 = plant view with engineering calculations (M6, below). Drills H9 and H10 use plant view, and H1, H3 and H5 use view 2. The sandbox offers 0 and 1 as a toggle.

- **Model view**: the snapshot carries the model's true values everywhere (as in M1) plus the instrument readings.
- **Plant view**: the engine masks the snapshot *before* it leaves the simulator, so no UI code can leak the truth:
  - `stages.x`, `y`, `yStar`, `liquidDown`, `vaporUp`, `entrain`, `weep`, `dp`, `jetFlood`, `dcFlood`, `frothFill`, `stability`, `weepFrac`, `efficiency`, `hetp`, `packFlood` become NaN.
  - `stages.t` is NaN except on instrumented trays, which carry the TI reading.
  - `stages.holdup`, `hcl`, `froth` and `flags` (and, M8, `packHoldup` and `wetFrac`) keep their model values for the column animation, except stage 0 and stage N+1. Their holdups are rewritten from the LT-101 and LT-102 readings (holdup = level/100 · V/v_L,design), so the painter draws the *measured* levels.
  - `streams` flows are the FT readings; compositions are NaN, except where an analyser reads them (D, B, feed: last published result).
  - `kpis`: d, b, boilup, qr and refluxRatio (from FT-102/FT-104), drumLevelPct, sumpLevelPct, pTop, columnDp and qc (from CW) are computed from readings. xD and xB are the analyser results (x_D = 1 − AT-101 for B-T). maxFloodPct, balanceResidual and energyResidual are NaN; their measured counterparts are the cross-checks (§14.6).
  - Valve positions p are removed; loops show OP only.
  - `visibleFaults` is empty (already the case in drills). The McCabe–Thiele builder returns `available = false`, and the diagram panel says "Not available on a real plant — the analysers are on the Products tab".
  - The math overlay offers only `ExplainInstrument`, `ExplainLoop` and `ExplainCheck` targets.
  - Model-only alarms (`model.*` except `model.relief`) are suppressed.
  - The reboiler snapshot keeps only duty-side readings (FT-103, steam valve OP, header pressure); the thermosyphon fields of ENGINE_API.md §7.1 become NaN.
- **Plant view with engineering calculations** (`view` = 2, "plantCalc", M6; drills H1, H3 and H5). This is plant view with one exception: a plant's online rating model would also compute the tray and reboiler hydraulics, so the following stay at their model values, labelled "calc" in the UI:
  - per-stage `dp`, `jetFlood`, `dcFlood`, `frothFill`, `stability`, `weepFrac`, `flags`;
  - M8, packed beds: per-stage `packFlood` and `hetp` (the HETP of (6.5), without E_mal), and per bed ΔP and max flood. E_mal, the F21 split and `efficiency` stay masked: a rating model does not know the distributor is plugged;
  - `kpis.maxFloodPct`, `kpis.maxWeepFraction`;
  - the thermosyphon fields `circulation`, `exitQuality`, `riserQuality`, `instabilityIndex`, `oscAmplitude`, `oscPeriod`, `inletLineDp`, `outletLineDp` (not `drivingHead`);
  - the alarms `model.flood`, `model.weep`, `model.dcLimited`, `model.tsUnstable`.
  Everything else is masked exactly as in plant view, including the sump level (the painter draws LT-102) and the feed composition (AT-100 only). The thermosyphon's static head z is not shown, because it would reveal the true sump level.
- **Drills in model view** (H2, H4): the snapshot never carries fault parameters, i.e. UA_eff, R_f, f_flooded, the exchangers' Q_max, the overhead inert inventory n_I / y_I, K_in and K_out. Those fields are NaN while `scenario.kind == drill`. The symptoms they cause (P, valve OPs, subcooling, duty, alarms such as `model.dutyLimited`) stay visible.
- In all views, scenario predicates, scoring, safety and drill off-spec tests read the **unmasked** state inside the engine.

---

## 11. Fault models

A fault has a type, a location, a final severity s_f ∈ (0, 1], an onset time t₀ and a ramp time τ_r. Its current severity is

```
s(t) = s_f · clamp( (t − t₀) / τ_r , 0 , 1 )          (τ_r = 0: step)                         (11.1)
```

Faults act only by changing physical parameters or adding physical flows. No fault applies a cosmetic multiplier to a displayed number.

| ID | Location | Parameter changes (applied every step from s(t)) | Default τ_r |
|---|---|---|---|
| F04 Broken / missing tray | tray j | Opening fraction s of the deck: liquid bypass s_broken,j = s added to the bypass fraction f_j (5.14) (the arriving liquid falls through with its inlet composition, like weeping); vapour bypass b_V,j = s in (4.2); hole area A_h,eff = A_h (1 − s) + s · A_a (the opening is a large hole, so ΔP_dry falls); active area A_a,eff = A_a · max(1 − s, 0.02), used for h_cl, the weir relation and M_max; liquid head in ΔP × (1 − s) (5.5); the opening also counts in the dumping drain area A_drain (5.15). At the B-T design load a fully broken tray sits at Φ = 0.208, just above the dumping threshold; with the implicit threshold of (5.15) that is harmless | 0 (sudden damage) |
| F05 Fouled / plugged trays | trays j₁…j₂; mode holes / downcomer / both | holes: A_h,eff = A_h (1 − 0.8 s) (valve trays: A_min and A_max × (1 − 0.8 s)); downcomer: h_ap,eff = h_ap (1 − 0.9 s) | 4 h of sim time (represents weeks) |
| F06 Foaming | section or whole column | SF = SF_froth = 1 − 0.45 s; φ_dc = 0.5 − 0.2 s. Antifoam on: after 300 s dead time s decays with τ = 600 s | 600 s |
| F07 Feed composition upset | feed | z ← z + σ s Δz with **Σ Δz = 0**. Components listed in `params.dz` get their value; unlisted components share −Σ(listed) in proportion to their current z (for a binary, the other component gets exactly −Δz). Any negative z_i is clamped to 0 and the result renormalised (only then does normalisation act). Default Δz: light component +0.15, so B-T z = 0.50 → 0.65. v1.0 added +0.15 to one component and then normalised, which gave 0.565 | 0 or ramp |
| F08 Feed thermal upset | feed | T_F += s ΔT (Tier 2/3, default −40 K) or q += s Δq (Tier 1, default +0.3) | 0 |
| F09 Loss of cooling | condenser | mode flow: m_cw,max × (1 − s); mode temperature: T_cw,in + 15 s K. B-T prototype (UA 29.9 kW/K at 50 % CW, PC-101 at 10/120): flow s = 0.5 is absorbed (the valve opens towards 100 %, P stays at SP); s = 0.6 → CW 100 % after 125 s, P → 1.070 bar(a); s = 0.7 → 72 s, 1.167 bar(a); s = 1 → relief set point 3.5 bar(a) reached after 471 s. Temperature mode: s = 0.6 → P 1.180 bar(a); s = 1 → 1.389 bar(a). Drill ranges therefore start at s = 0.6 | 0 (pump trip) / 1800 s |
| F10 Condenser fouling | condenser | R_f = s · 1.5/UA_clean (at s = 1, UA_eff = 0.4 UA_clean) | 6 h |
| F11 Non-condensables | overhead | ε_I = 1×10⁻⁴ s (mol inert per mol feed), §7.1. At s = 1 about 10 mol of inert per hour accumulates (B-T). It is a transient: PC-101 first holds P by opening the CW valve, but the 50 % condenser (§7.2) has only +7.9 % of reserve, which blanketing (3 y_I) plus the lower condensable partial pressure use up at y_I ≈ 0.02. The valve saturates after ≈ 17 min and P then rises. At 1 h (engine c4e1f17, matching n_I = ε_I F t, P = n R T₀/V, ΔT_sub = 20 f_blanket): P_top ≈ 139 kPa, overhead 138.7 mol (128.7 condensable + 10.0 inert), y_I ≈ 0.072, f_blanket ≈ 0.22, extra subcooling ≈ 4.3 K. (With P held at 1 atm the same inert would give y_I ≈ 0.09 and ≈ 5 K; that needs a larger condenser.) Opening the vent (§7.1) removes it | 0 |
| F12 Reflux pump trip | reflux | L_0 ≤ (1 − s) L_0,max | 0 |
| F13 Reboiler fouling | reboiler | R_f,R = s · 1.5/UA_R,clean (K/W). For the thermosyphon UA_R,clean = U A, and U_eff uses A R_f,R (§8.3.2), so s = 1 again gives 0.4 UA. The kettle's design duty uses 60 % of Q_max, so it becomes duty-limited at s ≈ 0.44 | 6 h (drill H4: 5400 s, §11.9 of ENGINE_API.md) |
| F14 Condensate backup (failed trap) | reboiler | f_flooded = 0.8 s. "Open trap bypass" action: s → 0 over 300 s | 60 s |
| F15 Steam header pressure loss | steam | P_hdr (absolute) × (1 − 0.6 s) → lower T_st (water saturation, DIPPR-101 inverse). B-T, with Q_max taken at T_B = 110.4 °C (the E = 1 VC-11 point where UA_R is sized, and the first step after onset): s = 0.5 → 3.16 bar(a), 135.4 °C, Q_max 1437 kW, which still covers the 1300 kW design duty; the duty limit starts at s ≈ 0.58 (engine: between 0.55 and 0.6). Drill ranges therefore start at s = 0.7 (2.62 bar(a), 129.0 °C, Q_max ≈ 1070 kW; s = 1: 1.81 bar(a), 117.1 °C, 384 kW). At the E = 0.7 default (T_B 109.6 °C) each Q_max is ≈ 50 kW higher (s = 0.5: 1490 kW). "Limited" is an onset statement: once the duty falls short, T_B falls and Q_max partly recovers (s = 0.6: 1299 kW after 15 min; s = 0.85 on the default preset ≈ 1200 kW). The plant symptom is `FC-103.OPSAT`, not `model.dutyLimited` (§8.2) | 120 s |
| F17 Thermosyphon inlet restriction | loop | K_in += 300 s. Loop-only prototype (VC-14.1 inputs, 50 % level, 1300 kW): circulation W falls 30 % at s = 0.3, 38 % at 0.5 and 49 % at 1; x_e 0.24 → 0.36 / 0.41 / 0.46. I_s *falls* (0.74 → ≈ 0.65), because inlet friction stabilises (8.4), so there is no surge. Mist flow starts to limit the duty at s ≈ 0.5 (s = 0.5: 1297 kW; 0.7: 1236 kW; 1: 1164 kW). Drill range [0.3, 0.8] | 1800 s |
| F18 Thermosyphon outlet restriction | loop | K_out += 40 s. Same conditions: I_s 1.09 at s = 0.1, 1.33 at 0.2, 1.56 at 0.4 and 1.85 at 1. The limit amplitude is 0.09 / 0.15 / 0.18 / 0.20, with a period of 9.5 / 10.1 / 11.5 / 15.0 s. W falls 27 % / 40 % / 54 % / 70 %, and the mean duty falls to 1243 / 1096 / 844 kW from s ≈ 0.15. With the 1800-s ramp at s_f = 0.4, I_s passes 1 about 6 min after onset and the amplitude reaches 0.05 after ≈ 14 min (s_f = 0.2: 12 and 23 min). Drill range [0.2, 0.6] | 1800 s |
| F19 Instrument calibration fault | instrument tag | `bias`: b = σ s · 10 % of span; `drift`: σ s · 10 % of span per hour; `stuck`: outputs frozen at t₀ (§10.6) | 0 |
| F28 Transmitter hard failure | instrument tag | `signalLossLow` / `signalLossHigh` (3.6 / 21.0 mA, BAD), `plugged` (extra lag 10^(4s) − 1 s on the sensed signal), `spiking` (Poisson spikes, rate s/20 s⁻¹, 10–50 % s of span), `coated` (TI lag × (1 + 9 s)) (§10.6) | 0; `plugged` 300 s |
| F20 Valve fault | valve id | `stuck` (position frozen at t₀) / `failOpen` (command 100 %) / `failClosed` (command 0 %); the actuator lag still applies (§10.3, §10.6) | 0 |
| F21 Packing maldistribution | packed bed b (1 = top bed) | f = 0.6 s in (6.6), on bed b only (the redistributor below it mixes the liquid again, §6.1). ΔP and φ_p use the bed-mean flows and do not change. H7 column (§2.3 M8 rules, D_bed 1.0 m), upper bed, s = 0.5 (f = 0.3): E_mal 0.57, x_D 0.9936 → 0.9788, x_B 0.0111 → 0.0280, bed ΔP +0.3 %, TI-101 − TI-109 11.5 K → 8.1 K; lower bed, s = 0.5: x_D 0.9742, x_B 0.0365, TI-110 − TI-118 17.0 K → 13.0 K. Drill range [0.5, 0.8] | 0 or 1800 s (drill H7: 900 s) |
| F23 Packing crushed | packed bed b | F_p,eff = F_p (1 + 1.5 s) in (6.1) **and** (6.2); H_bed × (1 − 0.15 s) (fewer metres of packing, same segment count, so H_k and E_O = H_k/HETP fall); a unchanged. H7 column, s = 0.3: upper-bed ΔP +46 % (1.26 → 1.85 kPa), max φ_p 0.67 → 0.75; lower bed +57 % (1.61 → 2.53 kPa), φ_p 0.79 → 0.88; separation changes by less than 0.003. Drill range [0.3, 0.5] | 0 |
| F24 Stripping steam loss | steam injection point | steam × (1 − s) | 60 s |
| F25 Pumparound trip | pumparound | P_PA × (1 − s) (and Q_PA with it) | 0 |
| F26 COT upset | furnace | COT += s ΔT (default −15 K) | 300 s |

F01, F02, F03, F16, F22 and F27 are operating conditions that emerge from the models in §5, §6, §8 and §9. Scenarios provoke them by changing loads. F22 (packing flooding): a bed floods when its φ_p reaches 1 (§6.3). Drill H7 provokes it with a +25 % planning event, which takes the H7 column's lower bed from φ_p 0.79 to 0.97 (ENGINE_API.md §11.11). Drill symptom expectations for every injectable fault are tabulated in VALIDATION.md §H.

Faults are stored on the snapshot only in sandbox mode. In a drill the snapshot carries no fault information; the UI cannot reveal it.

---

## 12. Numerical integration

### 12.1 Stiffness and the choice of method

Time constants in a typical column (B-T default unless noted):

| Mode | Time constant | Treatment |
|---|---|---|
| Vapour holdup, vapour flow between trays | 0.01–0.1 s | Algebraic (quasi-steady) |
| Tray liquid hydraulics (dL/dM) | 1–3 s per tray; ≈ 25 s to pass a step down 20 trays | Implicit |
| Tray composition (own holdup / throughput) | 2–10 s | Implicit |
| Overhead pressure | 2–10 s | Implicit scalar |
| Thermosyphon loop | 1–10 s | Sub-stepped implicit, 0.1 s |
| Flow loops (PI + valve + transmitter) | 2–4 s closed loop | Sub-stepped at 0.1 s (§10.1) |
| Level and composition dynamics of the column | 30 min – 3 h (B-T: ≈ 0.6 h) | Implicit (same equations) |

The stiffness ratio is about 10⁴. The physics that learners care about is in the slow modes and in the hydraulic modes of seconds. Two more facts decide the method:

- Holdups can shrink towards zero (dumping, drying, emptied drum). An explicit method's stable step shrinks with the holdup; an implicit one does not.
- At 1000× and 60 fps the simulator must advance 16.7 s of process time per frame on a phone.

**Choice: a linearly implicit, operator-split scheme with a fixed step.**

1. Algebraic vapour flows from the state at the start of the step (§4.4, §4.5).
2. Implicit Euler on the liquid holdups, coupled through downward liquid flow only, so it is solved by a top-down sweep of scalar Newton problems (§12.2).
3. Implicit Euler on the component holdups with frozen flows and linearised equilibrium (K̃), which is one banded system per component (tridiagonal plus one extra sub-diagonal for the tray bypass), solved by a Thomas-type elimination, with two Murphree passes (§12.3).
4. Small implicit or sub-stepped solves for the fast lumped units (pressure, thermosyphon).
5. Algebraic updates (bubble points, enthalpies) at the end of the step.

Entrainment flows (upward liquid) are part of the banded matrix (they couple adjacent stages). The weeping/broken-tray bypass (stage j−1 → j+1) is the extra sub-diagonal. Only the crude side operations that couple distant stages (pumparound, side strippers, side draws) are evaluated from the start-of-step compositions, and each of those is applied with the identical value as a sink on one stage and a source on the other. Each component is therefore conserved exactly (to round-off) whatever the step size.

Prototype evidence (Node.js reference implementation of §12.2–12.3 for the B-T default, Tier 1): the dynamic steady state equals the independent Newton solution to 1×10⁻⁶ for dt = 0.5, 2, 5, 10 and 30 s; component conservation error below 1×10⁻¹¹ relative over 10 h (below 1×10⁻⁹ with weeping, entrainment and a missing tray active); no negative holdups; 38 µs per step in unoptimised JavaScript (22 stages × 2 components).

### 12.2 Hydraulic (holdup) step

The total-material balance of tray/segment j is

```
dM_j/dt = (1 − f_j) L_{j−1} + f_{j−1} L_{j−2} + e_{j+1} + F_j + (V_{j+1} − V_j) + R_j − L_j(M_j) − e_j − S_j        (12.1)
```

where F_j is the total feed (all phases), R_j the liquid and vapour returns (pumparound, stripper vapour), S_j the explicit draws (side product, pumparound draw), f_j the bypass fraction (5.14). In Tier 1, V_{j+1} − V_j + F_j = q_j F_j by (4.5); in Tiers 2/3, V comes from (4.6). Everything on the right-hand side except L_j(M_j) is known when tray j is processed: e_j, S_j and f_j are start-of-step values; L_{j−1} and L_{j−2} were computed earlier in this sweep.

For j = 1 … N in order (top-down):

```
In_j  = (1 − f_j) L_{j−1}^(n+1) + f_{j−1} L_{j−2}^(n+1) + e_{j+1} + F_j + V_{j+1} − V_j + R_j
        (L_0 = reflux; the second term is absent for j = 1)
Out_j = e_j + S_j
Solve R(M) = M − M_j^n − dt [ In_j − Out_j − L_j(M) ] = 0
   Newton from M = M_j^n:  M ← M − R(M) / (1 + dt · dL_j/dM)
   if a step gives M ≤ 0, use M ← ½ M instead
   stop when |ΔM| < 1×10⁻¹⁰ · max(1, M);  at most 40 iterations
M̂_j = M,   L_j^(n+1) = L_j(M̂_j)
```

L_j(M) is the downflow function of §5.9 for trays (weir capped by L_max, plus the dump drain L_dump(M) of (5.15); dL/dM = dL_weir/dM when the weir is below the cap, 0 when capped) or (6.4) for packed segments. L_j is monotone non-decreasing in M, so R is monotone and the Newton iteration converges.

**Full hydraulics: solve every tray for u = √M with a safeguarded Newton.** L_dump has an infinite slope at M = 0, and the downcomer cap smin(L_weir, L_max) puts a concave kink into the residual. In tests, plain Newton cycled at dt = 30 s and halted the simulator. In u the residual is monotone increasing, so a bracketed Newton always converges:

```
G(u)  = u² − M_j^n − dt [ In_j − Out_j − L_w,cap(u²) − κ_j max(0, u − √M_c,j) ]
G'(u) = 2u + dt [ 2u · dL_w,cap/dM |_(u²) + (u > √M_c ? κ_j : 0) ]           (dL_w,cap/dM = 0 when capped)
if G(0) ≥ 0: u = 0 (the tray empties within the step)
else: lo = 0; hi = √(M_j^n) + 1, doubled (hi ← 2 hi + 1) until G(hi) > 0; u = √(M_j^n)
      repeat (max 100): if G(u) > 0 then hi = u else lo = u
                        u_new = u − G(u)/G'(u); if u_new ∉ (lo, hi) then u_new = (lo + hi)/2      (bisection fallback)
                        stop when |u_new − u| < 1×10⁻¹² max(1, u) or hi − lo < 1×10⁻¹³ max(1, u)
M̂_j = u²,   L_j^(n+1) = L_w,cap(M̂_j) + κ_j max(0, u − √M_c,j)       (the same u in both: the balance closes exactly)
```

- In the prototype this needed ≤ 8 iterations in normal operation and ≤ 47 (with bisections) right after a tray broke at dt = 30 s.
- Ideal hydraulics (no dump term, no cap) may keep the M-Newton above.

**Stability at large dt.** The step is implicit Euler with the drain and the threshold at the end of the step, so it is stable for any dt (results above). The component step (§12.3) then sees M̂ of about 1 mol on dumping trays, with throughputs of about 30 mol/s. That is very stiff, but the banded implicit solve handles it as it handles any small holdup, and the existing floor M̂ ≥ 1×10⁻⁹ mol stays.

### 12.3 Component step (banded: tridiagonal plus one sub-diagonal)

Unknowns m_ij^(n+1), j = 0 … N+1, one banded system per component i. Liquid composition in the solve is x_ij = m_ij/M̂_j. The vapour leaving stage j is linearised with K̃ and a lagged composition ŷ of the vapour entering from below (taken from the previous pass):

```
y_ij ≈ (1 − E_j) ŷ_{i,j+1} + E_j K̃_ij m_ij / M̂_j            E_j = E_j^eff,  E_{N+1} = 1
```

Write the system as g_j m_{i,j−2} + a_j m_{i,j−1} + b_j m_ij + c_j m_{i,j+1} = d_j (g is the bypass sub-diagonal).

**Tray rows** (1 ≤ j ≤ N):

```
g_j = − dt f_{j−1} L_{j−2} / M̂_{j−2}                 (j ≥ 2: the bypass that fell through tray j−1; g_1 = 0)
a_j = − dt (1 − f_j) L_{j−1} / M̂_{j−1}
b_j = 1 + dt ( L_j + e_j + V_j E_j K̃_ij ) / M̂_j
c_j = − dt ( V_{j+1} E_{j+1} K̃_{i,j+1} + e_{j+1} ) / M̂_{j+1}            (e_{N+1} = 0)
d_j = m_ij^n + dt [ F_j z_ij
                    + V_{j+1} (1 − E_{j+1}) ŷ_{i,j+2} − V_j (1 − E_j) ŷ_{i,j+1}
                    + Σ R_j r_ij − S_j x^n_ij ]
```

Note on the first rows: the liquid arriving at tray 1 is the reflux from the drum (stage 0), so tray 1's bypass f_1 L_0 carries drum liquid to tray 2: g_2 = − dt f_1 L_0 / M̂_0. In general g_j couples row j to stage j−2 for every j ≥ 2 (stage 0 is the drum). The sump row has g_{N+1} = − dt f_N L_{N−1} / M̂_{N−1}.

(For j = N the term ŷ_{i,j+2} is absent because the reboiler is an equilibrium stage: E_{N+1} = 1.)

The last line of d_j holds the explicit crude side operations (start-of-step compositions, identical value on the sending and receiving stage, so they conserve exactly).

**Drum row** (j = 0):

```
Total condenser (the condensing vapour has the composition of the vapour leaving tray 1):
  b_0 = 1 + dt (L_0 + D_L) / M̂_0
  c_0 = − dt ( N_cond E_1 K̃_{i1} + e_1 ) / M̂_1
  d_0 = m_i0^n + dt N_cond (1 − E_1) ŷ_{i2}
Partial condenser (drum is an equilibrium stage; uncondensed vapour leaves at y_0 = K̃_0 x_0):
  b_0 = 1 + dt ( L_0 + D_L + (V_1 − N_cond) K̃_{i0} ) / M̂_0
  c_0 = − dt ( V_1 E_1 K̃_{i1} + e_1 ) / M̂_1
  d_0 = m_i0^n + dt V_1 (1 − E_1) ŷ_{i2}
```

In the total-condenser case the vapour that does not condense in a step, (V_1 − N_cond), joins the overhead inventory n_V with composition y_1 (§7.1); the conservation check in Tiers 2/3 counts n_V y_1 as inventory.

**Sump row** (j = N+1):

```
g_{N+1} = − dt f_N L_{N−1} / M̂_{N−1}
a_{N+1} = − dt L_N / M̂_N
b_{N+1} = 1 + dt ( B + V_{N+1} K̃_{i,N+1} ) / M̂_{N+1}
d_{N+1} = m_{i,N+1}^n
```

**Solve** by elimination without pivoting (Thomas algorithm extended by one sub-diagonal). Rows are reduced top-down to the form m_j + c'_j m_{j+1} = d'_j:

```
for j = 0 … n−1:
    a* = a_j ;  d* = d_j
    if j ≥ 2:  a* = a* − g_j c'_{j−2} ;  d* = d* − g_j d'_{j−2}      (remove the m_{j−2} entry using reduced row j−2)
    b* = b_j
    if j ≥ 1:  b* = b* − a* c'_{j−1} ;   d* = d* − a* d'_{j−1}      (remove the m_{j−1} entry using reduced row j−1)
    c'_j = c_j / b* ;  d'_j = d* / b*
back-substitute: m_{n−1} = d'_{n−1} ;  m_j = d'_j − c'_j m_{j+1}  for j = n−2 … 0
```

Eliminating the g entry only adds to the existing a entry (row j−2 has non-zeros on its diagonal and super-diagonal only), so there is no fill-in. The matrix is column-diagonally dominant (for each stage, b_j − 1 equals the sum of the magnitudes of the off-diagonal entries that carry its outflows to other stages), so no pivoting is needed and the solution is non-negative whenever d ≥ 0. Clamp m_ij ≥ 0 and count clamps in `solverHealth.negativeClamps` (it stays 0 in normal operation).

**Murphree passes.** Pass 1 uses ŷ = y^n. After it, recompute y bottom-up from the pass-1 compositions with (4.2), using normalised x, and normalise each y to Σ = 1. Pass 2 re-solves with this ŷ. Two passes are the default; the prototype converged to the same steady state with one pass, and two passes improve transients at large dt.

After the solve the new state is m_ij^(n+1); M_j = Σ_i m_ij (not M̂_j); x = m/M; y is recomputed once from the final x with (4.2).

### 12.4 Order of operations in one step

```
 1. Faults: update s(t) for every active fault; build the effective parameter set.
 2. Inputs: apply lever changes and scenario events; then the control fast layer (§10.1): n_c sub-steps of
    valves, flow transmitters, ratio station and flow loops over [t, t + dt], using the start-of-step pump
    limits and Q_max → the mean flows F̄ (10.0) used by every balance of this step. With a thermosyphon, each
    sub-step also runs one loop sub-step (8.3)–(8.5) between FV-103 and FT-103 (§8.3.4), with the column
    conditions of the start of the step.
 3. Thermo (from end of previous step, cached): T_j, K̃_ij, y_j, h_j, H_j, ρ, σ, v_L.
 4. Hydraulic coefficients at state n: Bennett α_e, ΔP_j, P_j profile, φ_j, ψ filter update, e_j,
    bypass fractions f_j, L_max,j, the dumping factor (0.2 − Φ_j)/0.2, M_max; packing φ_p, ΔP, holdup factor, HETP, E.
 5. Reboiler: kettle Q (8.2), or for the thermosyphon the mean of Q_k (1 + u_k) over the sub-steps already run in
    step 2 (§8.3.4) → Q_R,delivered.
 6. Vapour profile bottom-up: (4.4) Tier 1; Tiers 2/3: the overhead pressure solve (§7.4), which calls the
    sweep (4.6)/(4.7) for each trial P → P_top^(n+1), n_V^(n+1), N_cond, Q_C and the final V_j; sump-starvation factor.
 7. Side strippers (crude): hydraulic + component step for each stripper chain.
 8. Main hydraulic step (§12.2) → M̂_j, L_j; drum and sump M̂.
 9. Component step (§12.3), two Murphree passes → m_ij^(n+1).
10. Overhead inventory update (§7.1): n_V,i^(n+1) per component, n_I^(n+1) (Tier 2/3). [v1.0 had the pressure solve
    here, after steps 8–9 had already used N_cond; it moved to step 6.]
11. Thermo update at n+1: bubble points (§3.6.1) at P_j, enthalpies, densities, K̃ for the next step, y via (4.2).
12. Control main layer (§10.1): non-flow instruments (LT, PT, PDT, TI, AT, field checks) from the end-of-step
    state; loops LC-101, LC-102, PC-101, TC-101 (10.1) → OPs and the FC-103 cascade SP for the next step's
    fast layer; alarms (§10.8).
13. Diagnostics: KPIs, steady-state monitor (§13.3), trend buffer bins (every 5 s; mean/min/max of every
    reading), cross-checks (§14.6, every 5 s), scenario runner update, solver health.
14. t ← t + dt.
```

Tier 1 skips 5 (V_B lever instead), 10 and 11 (no T, fixed P), and uses K̃ from (4.4). In ideal-hydraulics mode step 4 computes only α_e and C.

### 12.5 Time step

- Main step dt = 0.5 s at all speeds up to the frame budget. Fixed, so a run is reproducible regardless of the speed it was watched at.
- Fast-forward ("Run to steady state", and speeds ≥ 300× when the user enables "coarse fast-forward" in Settings) uses dt = 2.0 s. Prototype: identical steady states; transients differ by under 1 % in composition.
- Thermosyphon sub-step 0.1 s; control fast layer sub-step 0.1 s (§10.1); pressure solve once per main step.
- Tests use dt = 0.5 s unless stated.
- **dt = 30 s is a test-only robustness step** (ruling 2026-10-13). The app never uses it (dt ≤ 2 s). At 30 s the engine must give the same steady states as at 0.5 and 2 s from the same start, no NaN, no fatal and no false "steady" (§13.3, §12.7 strict clamp). Closed-loop transients need not match: loops executed at rate dt (PC-101, LC-101/102, TC-101) sample every 30 s, and where a configuration raises their loop gain (e.g. a condenser with twice its preset UA doubles PC-101's gain) they may limit-cycle; `runToSteadyState` must then return reached = false. PC-101 is not sub-stepped (the pressure is solved once per main step, so a faster PID would only see a frozen PV), and no tuning depends on dt.

### 12.6 Cost per step: 40 trays, 8 components, Tier 2

| Work item | Count per step | Approx. cost on a 2.0 GHz Cortex-A76-class core (Dart AOT) |
|---|---|---|
| Bubble points (Newton, warm start, 2–3 iterations × 8 P_sat + derivatives) | 42 stages | 40–60 µs |
| Enthalpies (h_L,i, h_V,i with one `pow` each) | 42 × 8 × 2 | 15–25 µs |
| Hydraulic coefficients (≈ 60 flops, 3 `pow`/`exp`, 2 `sqrt` per tray) | 40 | 15–25 µs |
| Holdup Newton (2–4 iterations, 1 `pow` each) | 40 | 10–15 µs |
| Tridiagonal solves (8 components × 2 passes × 42 rows × ~12 flops) | 16 | 10–15 µs |
| Pressure solve (≈ 4 bubble points of the drum) | 1 | 5 µs |
| Controllers, diagnostics, bookkeeping | – | 10–20 µs |
| **Total** | | **≈ 0.1–0.2 ms** (≈ 2.5×10⁴ flops and ≈ 1500 transcendental calls) |

Tier 3 NRTL binaries cost less (2 components); DePriester K is cheaper than Lee–Kesler. Crude (38 stages × 10 components including steam) is ≈ 0.2–0.3 ms.

Consequences at dt = 0.5 s: 100× needs 200 steps per wall second (20–40 ms/s, 2–4 % of one core); 1000× needs 2000 steps/s (0.2–0.4 s/s). The UI scheduler gives the engine at most 6 ms per 16.7 ms frame (M1–M9: on the UI isolate; M10: background isolate on native platforms) and shows the achieved speed when the budget caps it. Performance targets are verified in VALIDATION.md VC-19.

Implementation rules for speed **[impl]**: structure-of-arrays storage in `Float64List`; no allocation inside `step()`; precompute per-component constants (ln 10 · B, etc.); warm-start every Newton solve from the previous step; reuse scratch buffers for Thomas.

### 12.7 Safeguards and failure handling

- After each step, check all states for NaN/Inf and negative holdups beyond −1×10⁻¹².
- On failure: restore the start-of-step state, halve dt, retry; up to 3 halvings (dt = 0.0625 s), then advance the same total time with the smaller steps.
- If it still fails: pause the simulation, set `solverHealth.fatal = true` with the stage and quantity that failed, and show "The model could not continue from this state — rewind 60 s?" (the engine keeps a ring buffer of states at 60 s intervals, last 10 min). A ring entry is the complete state of §1.2, including controller, instrument, alarm and PRNG states, so a rewound run continues deterministically.
- A halved step re-runs the control fast layer with the same δ_c (n_c = round(dt_half/δ_c), at least 1).
- Every fallback is counted in `solverHealth` and shown in a developer overlay (Settings → Developer).

### 12.8 Determinism

The engine uses only IEEE-754 double arithmetic, fixed iteration orders, and its own seeded PRNG (§12.9). With the same build on the same platform a run is bit-identical. Across platforms `exp`/`log`/`pow` may differ in the last bit; results then agree to 1×10⁻⁹ relative after 1 h of sim time (VALIDATION.md VC-20). With noise on, a last-bit difference in a Gaussian draw can grow, so the cross-platform tolerance applies only to noise-off runs. Noise-on runs must be bit-identical on the same platform.

### 12.9 Random numbers

v1.0 named xorshift64*. That generator needs 64-bit integer arithmetic, which Dart compiled to JavaScript (web, M10) does not have. LowSYS therefore uses **xoshiro128\*\*** (Blackman and Vigna), which needs only 32-bit operations. Every operation below must be exact on both native and web.

```
32-bit helpers (all results reduced mod 2^32, i.e. "& 0xFFFFFFFF" after each operation):
  rotl(x, k) = ((x << k) | (x >>> (32 − k))) & 0xFFFFFFFF
  products only with small constants (5, 9, 403, 69069), so x·c < 2^53 is exact in a double on the web

next32():                                   state s0, s1, s2, s3 (unsigned 32-bit)
  result = rotl((s1 · 5) & M, 7) · 9 & M
  t = (s1 << 9) & M
  s2 ^= s0;  s3 ^= s1;  s1 ^= s2;  s0 ^= s3;  s2 ^= t;  s3 = rotl(s3, 11)
  return result

uniform():   a = next32() >>> 5 ;  b = next32() >>> 6 ;  return (a · 67108864 + b) / 9007199254740992      ∈ [0, 1)
normal():    Box–Muller with a cached second value:
             u1 = 1 − uniform(), u2 = uniform(), r = √(−2 ln u1);
             return r cos(2π u2), and cache r sin(2π u2) for the next call

stream seeding, for an integer seed (0 ≤ seed < 2^32) and a string key:
  h = FNV-1a-32(UTF-8 bytes of key): h = 2166136261; for each byte b: h = (h ^ b); h = ((h << 24) + 403·h) mod 2^32
      (= h · 16777619 mod 2^32 without a 57-bit product)
  x = (seed ^ h) mod 2^32 ;  for i = 0..3: x = (69069 x + 1) mod 2^32 ;  s_i = x
  discard the first 16 outputs of next32()
```

Test vectors (VC-20.3): FNV-1a-32("a") = 3826002220; FNV-1a-32("FT-102") = 1498766031. Stream (seed 1, key "FT-102") gives next32() = 3793846675, 4233283444, 1026389867, 4162901922 after the warm-up. A fresh stream with the same seed and key gives uniform() = 0.883323766184137, then normal() = −0.6076328127833632, −0.42066679512424215.

**Streams.** Each random process has its own stream, so adding an instrument, switching noise on one tag or injecting a fault never changes the numbers another process sees:

| Key | Used for |
|---|---|
| `inst:<tag>:s`, `inst:<tag>:e` | sensed and electronic noise of a transmitter or analyser |
| `inst:<tag>:spike` | spike arrival times, amplitudes and signs (F28 `spiking`) |
| `valve:<id>:d` | supply disturbance d of a valve |
| `field:<tag>` | field-gauge reading errors |
| `drill:<attempt>` | drill draws (ENGINE_API.md §11.2) |
| `scenario:events` | randomised event times in scenarios |

The seed is `SimOptions.seed`. Stream states are part of the saved state (§1.2).

---

## 13. Initialisation, convergence and structural changes

### 13.1 Cold initialisation (from a configuration only)

1. Every stage gets the feed composition z (crude: also every stripper stage).
2. Flows by CMO from the levers: L_j = L_0 above the feed, L_0 + qF below; V_j from V_B (Tier 1) or V_B = Q_R,SP / (H − h)_sump estimate (Tiers 2/3).
3. Pressure: P_top = SP; P_j from the tray ΔP at these flows (Tier 2/3); n_V from the ideal-gas law.
4. Temperatures: bubble point of z at each P_j.
5. Holdups: trays from Bennett at the estimated L_j and V_j; packed segments from (6.3); drum and sump at 50 % level.
6. Controllers: OPs set to the values that give the estimated flows; valve positions p = c = OP; PID histories e = 0, PVf = PV; filters at their inputs (ψ_j = ψ_eq, L̄_j = L_j); instrument lags v_p = v_m = v_ss = true value; noise states 0; each analyser shows the current true value as a result of age 0; no alarms.
7. Thermosyphon: run the loop model alone for 600 s with the column frozen and Q_R,SP = the duty from step 2. Start from W₀ = Q_R,SP / (0.25 λ) (B-T 14.4 kg/s), x_r = x_e = 0, u = 1×10⁻³, v = 0, and filters set from the first sub-step (§8.3.3). The same initialisation runs when the reboiler type is switched to thermosyphon (the lever needs a pause) and when the tier returns from 1 to 2 or 3.

From there the dynamic model itself is the solver (pseudo-transient continuation): it is physically stable, so marching in time converges to the steady state for any physically feasible lever set. "Run to steady state" marches with dt = 2 s until the monitor (§13.3) passes, or 48 h of sim time; it reports "no steady state" if the cap is hit (e.g. an oscillating thermosyphon or a flooded column).

Expected time to steady state (B-T default, Tier 1, from cold): about 3 h of sim time (prototype: xD within 1×10⁻⁴ of the final value after 2.5 h), i.e. under 2 s of wall time at fast-forward on desktop.

### 13.2 Warm start

Every preset ships with a cached steady state (the full state vector X as JSON) produced by the engine's own "Run to steady state". A test re-runs the preset and fails if the cache differs by more than 1×10⁻⁶ (VALIDATION.md VC-4), so caches cannot go stale silently.

### 13.3 Steady-state monitor

Every 60 s of sim time compute

```
δ = max( max_ij |x_ij(t) − x_ij(t − 60)| ,  max_j |M_j(t) − M_j(t − 60)| / M_j ,  |P_top(t) − P_top(t − 60)| / P_top ,
         max_loops |OP(t) − OP(t − 60)| / 100 )
```

Steady when δ < 1×10⁻⁷ for 5 consecutive checks. The TimeBar shows the indicator; scenario objectives can require it.

The monitor always uses true (model) values. **With noise on**, controllers act on noisy readings and the valve disturbances move the real flows, so the state never stops moving at the 1×10⁻⁷ level and the test above would never pass. With noise on, the monitor instead compares successive 300-s means (each quantity averaged over 300 s, checked every 300 s):

```
δ̄ = max( max_ij |x̄_ij − x̄_ij,prev| / 2×10⁻⁵ ,  max_j |M̄_j − M̄_j,prev| / (2×10⁻³ M̄_j) ,
         |P̄_top − P̄_top,prev| / (1×10⁻⁴ P̄_top) ,  max_loops |OP̄ − OP̄_prev| / 1.0 % )
steady when δ̄ < 1 for 3 consecutive checks
```

These thresholds are **[impl-tunable]**: VC-20.6 fixes the required behaviour, and any change goes into DEVIATIONS.md. "Run to steady state" always runs with noise and valve disturbances suspended. The noise streams draw nothing during the run and the noise states are 0 afterwards; the lever value is restored when the run ends. The noise-free monitor is used for that run.

### 13.4 Changing the number of trays, feed tray, internals

- Feed tray change: no rebuild; the feed moves to the new stage at the next step.
- Number of trays N → N': rebuild the stage arrays. For each new tray at fractional height s' = (j' − ½)/N', interpolate liquid composition and h_cl linearly from the old profile at s = s'; drum, sump, controllers, pressure inventory unchanged; the feed tray keeps its fractional position, rounded **down**: feedStage' = clamp(⌊φ N' + 10⁻⁹⌋, 1, N'), where φ = feedStage/N is stored whenever the feed tray is set explicitly (config or lever) and is not changed by a rebuild, so a sequence of rebuilds does not drift. B-T feed 10 of 20 (φ = 0.5) gives N' = 27 → tray 13 (G6 reference x_D 0.97761), 28 → 14. Then continue. Allowed while running; the UI pauses for the rebuild frame.
- On a rebuild, tray TIs are remapped as in §10.5. A TI that keeps its tag keeps its state. A new TI starts at the true value, and a TI that disappears loses its faults and alarms. The sump TI is renamed TI-(100 + N' + 1) and keeps its state.
- Tray type or section geometry changes: allowed only while paused; holdups re-initialised from Bennett at current flows.
- **Internals template** (lever `internals`, M8; only on configs that carry templates, `bt` and `bt_packed`): allowed only while paused. Rebuild the stage arrays from the template's sections. Each new stage interpolates the liquid composition from the old profile at its fractional height, as for N → N'. Holdups are re-initialised at the current flows: trays from Bennett, packed segments from (6.3). The feed stage, `temperatureTrays` and the PDTs come from the template, not from φ. TIs that keep their tag keep their state, as above. Drum, sump, controllers and the pressure inventory are unchanged. Overriding `sections` (scenario `overrides`) removes the templates, and the lever is then not offered.

### 13.5 Switching thermodynamic tier at runtime

The state X is the same in every tier. On a switch:

| From → To | Actions |
|---|---|
| T1 → T2/T3 | Compute bubble points and enthalpies from the current x and P_top (= preset P); T^(n−1) := T. Set FC-103 SP (duty) so that the **top vapour V_1 (and hence D) is continuous**: Q_R = V_1 (H_V(y_1, T_1) − h_L(x_0, T_0)) + D h_D + B h_B − F h_F, the steady energy balance evaluated with Tier-2 enthalpies on the current state. Initialise n_V and n_V,i = n_V y_1 from P_top. PC-101 SP = P_top, OP at the 50 % design value (§7.2; v1.0 70 %). |
| T2/T3 → T1 | Set the boilup lever V_B = current V_1 − (1 − q)F (top vapour continuous). Vapour flows become CMO at the next step, so the learner sees the profile flatten (the teaching point), while D and the product split stay put. |
| T2 ↔ T3 | Only the K model changes; temperatures re-converge in the next bubble-point solve. The duty SP is kept, so D drifts to the new tier's value: `c4` T2 → T3 at 1542.6 kW goes from D 40.0 to 38.1 kmol/h, x_D 0.9299 → 0.9327, x_B 0.0467 → 0.0719 (VALIDATION.md VC-28.3). The learner sees the bottoms, not the distillate, pay for the less volatile DePriester K. **Pressure** (2026-10-13, from the M5 engine): at the same P the new K model gives a different condensing temperature (`c4` T2 → T3: T_D −1.4 K, so Q_C = UA (T_sat − T_cw) falls ≈ 6 %), and PC-101 alone took ≈ 15 min with a 5.7-kPa peak. A model switch must not look like a process upset, so with a total condenser the switch also sets the CW valve for a continuous Q_C: ΔT_new = T_0,sat(P_top) − T_cw,in with the new K, Q_C,old from the last step of the old tier, m_cw = UA_eff / (2 c_p,w (UA_eff ΔT_new / Q_C,old − 1)) from (7.3), OP = 100 m_cw / m_cw,max clamped to 0–100 % (100 % when UA_eff ΔT_new ≤ Q_C,old). PC-101's OP and the valve position are set to it bumplessly (`c4`: 50 → ≈ 59 %). As in T1 → T2, T^(n−1) := T after the first bubble-point solve of the new tier, so the column's heat storage does not turn the temperature step into vapour. With a partial condenser the CW lever belongs to the learner and is not moved; PC-101 absorbs the step through PV-102. |

The T1 ↔ T3 switches (M5) follow the T1 ↔ T2 rows with the Tier-3 model. On azeotropic systems the top-vapour rule is approximate, because the two tiers' compositions differ a lot: `ew` T3 → T1 → T3 returns at D 9.67 instead of 10 kmol/h (VALIDATION.md VC-28.6).

**Why the top vapour, not the boilup** (M4 prototype finding). Keeping V_B continuous (v1.0) lets the non-CMO top vapour grow: at the new Tier-2 steady state V₁ = 156.4 kmol/h, +4.3 % on its Tier-1 value of 150, with V_B settling at 149.1. Under LV control D rises by the same kmol/h: B-T default went from D 50 → 56.4 and xD 0.981 → 0.883, a collapse caused by the switch alone. Keeping V_1 gives D 49.96, xD 0.9784 and P within 0.25 kPa of SP. V_B steps to 141.9 kmol/h at the first Tier-2 step (−5.4 %) and settles at 141.0; this −4 … −6 % is the non-CMO profile appearing. Liquid flows on individual trays step by up to 13 % at dt = 0.5 s as the liquid profile redistributes (VALIDATION.md VC-8.9).

Available tiers per preset: T1, T2 and T3 for `mw`, `ew`, `ac`, `c4` (and the multicomponent presets from M7); T1 and T2 for `bt` (Tier 3 = Tier 2, so the T3 badge is hidden); T2 only for `crude`.

Switching never resets compositions or holdups.

Control on a tier switch:
- FT-103 changes quantity: T1 boilup kmol/h ↔ T2/3 duty kW. FV-103's position is re-initialised so the delivered boilup or duty is continuous. FT-103's lag and noise states restart at the new true value, and FC-103's PID history restarts (e = 0).
- Instruments whose quantity does not exist in Tier 1 (PT, TI, CW instruments, PC-101, TC-101) are hidden in Tier 1. They start at their true values when Tier 2/3 is entered. Faults on hidden instruments are kept and resume when the instruments reappear.

---

## 14. Diagrams and derived diagnostics

### 14.1 McCabe–Thiele (binary)

All series are produced by the engine (`McCabeThieleData`, ENGINE_API.md §7) from a snapshot, so the UI only draws. Axes: x and y of the light component, 0–1.

| Series | Definition | Notes |
|---|---|---|
| Diagonal | y = x | |
| Equilibrium curve | Tier 1: y = αx/(1 + (α − 1)x). Tiers 2/3: bubble-point y*(x) on 101 points (refined near the ends) at P_top, plus a second curve at P_{N+1}; the band between them is shaded | The band shows that a real column does not have one equilibrium curve |
| Local equilibrium points | (x_j, y*_j) for every stage at its own T_j, P_j (hollow circles) | |
| q-line | Through (z, z) with slope q/(q − 1) (vertical at q = 1), from (z, z) to its intersection with the equilibrium curve at the feed-tray pressure. Tiers 2/3 use q from (3.15). **Azeotropic curves can cross the line more than once:** walk along the q-line from (z, z) towards the side of the diagonal on which the curve lies at x = z, s = sign(y*(z) − z) (M5, 2026-10-13). For s = +1 that is larger x for q > 1, straight up for |q − 1| < 1×10⁻⁶ (treated as vertical) and smaller x for q < 1; for s = −1 (the feed lies on the y* < x side of an azeotrope, e.g. `ew` with z > 0.8956) every direction is reversed. Step 1×10⁻³ in x where |slope| ≤ 1 and in y otherwise, take the *first* sign change of y_line − y*, and refine it by bisection to 1×10⁻⁸. If |y*(z) − z| < 1×10⁻⁹ (z at an azeotrope) the pinch is (z, z). No sign change before the frame edge (x or y = 0 or 1): draw the line to that edge and show no pinch | |
| CMO reference operating lines (dashed) | Rectifying: y = (L_0/V_1) x + D x_D / V_1 with the *external* flows (reflux L_0, V_1 = L_0 + D, x_D = drum liquid). Stripping: y = (L̄/V̄) x − B x_B / V̄ with V̄ = V_{N+1}, L̄ = V̄ + B. Drawn from x_D to their intersection and from there to x_B | What a textbook would draw from the product flows |
| Actual operating locus (solid, dots) | Passing-stream points (x_j, y_{j+1}) for j = 0 … N | Tier 1 at steady state: lies exactly on the CMO lines. Tiers 2/3: a curve; the gap to the dashed lines is "what CMO hides" |
| Live staircase | (x_0, x_0) → (x_0, y_1) → (x_1, y_1) → (x_1, y_2) → (x_2, y_2) → … → (x_{N+1}, y_{N+1}) → (x_{N+1}, x_{N+1}). Corner (x_j, y_j) is labelled with the stage number; the feed stage is highlighted | Built from live compositions, so it moves during transients |
| Murphree pseudo-equilibrium | Tier 1: y_pe(x) = y_op(x) + E (y*(x) − y_op(x)) with y_op the CMO lines, on 101 points (dotted). Tiers 2/3: a line through the corners (x_j, y_j) | Corners sit on it at steady state |
| Murphree gap markers | For the selected tray: vertical bars showing (y_j − y_{j+1}) and (y*_j − y_{j+1}); their ratio is E_j | Visual definition of Murphree efficiency |
| Markers | x_F = z, x_D, x_B on the diagonal | |
| Minimum-reflux construction (toggle) | s_min = max over x ∈ [x_q, x_D) of (x_D − y*(x))/(x_D − x) on the equilibrium curve (x_q = q-line intersection); R_min = s_min/(1 − s_min); draw the line from (x_D, x_D) with slope s_min. **Azeotropes:** if the equilibrium curve meets or crosses the diagonal anywhere in (x_q, x_D) (y*(x) ≤ x there; ethanol–water with x_D ≥ 0.8956), then x_D cannot be reached by any reflux: R_min = ∞; draw no line and show the banner "x_D is beyond the azeotrope (x = 0.8956): no reflux ratio reaches it". For a maximum-boiling system (acetone–chloroform) the same test applies to the stripping side: with x_B < x_az and the feed above it, show "x_B is beyond the azeotrope (x = 0.333)". The x in the banners is the azeotrope finder's value at P_top (§14.4b), not a constant. Tiers 2/3 evaluate the maximum on the cached P_top curve, then refine the best interior point by golden-section search on fresh bubble points to 1×10⁻⁶ in x; x_q itself is always a candidate (feed pinch) | Handles tangent pinches (ethanol–water below the azeotrope) as well as feed pinches |
| Pinch shading | Shade where ≥ 3 consecutive steps advance x by < 0.002 | |
| Transient flag | When the steady-state monitor is false: caption "transient — operating lines are not yet consistent" | |

### 14.2 Multicomponent: key-component pseudo-binary (Hengstebeck)

Hengstebeck, Trans. AIChE 42 (1946) 309. With light key LK and heavy key HK:

```
x'_j = x_LK,j / (x_LK,j + x_HK,j)      y'_j = y_LK,j / (y_LK,j + y_HK,j)
y*'_j = K_LK,j x_LK,j / (K_LK,j x_LK,j + K_HK,j x_HK,j)
```

Plot: diagonal; "equilibrium locus" through (x'_j, y*'_j) sorted by x' (it is a stage-by-stage locus, not a closed-form curve); actual operating locus (x'_j, y'_{j+1}); staircase as in §14.1 with primed values; markers x'_F, x'_D, x'_B; a q-line through (z'_F, z'_F) drawn dashed with the caption "approximate for multicomponent". A banner explains that non-key components distort the pseudo-binary. Next to it: composition profile (all components versus stage), K-value / α profile, T profile.

**Builder rules (M7 readiness pass).**
- `McCabeThieleData.pseudoBinary` is true whenever nc > 2, and the labels are the key names.
- **Tier 1:** K_LK/K_HK = α_LK/α_HK =: α′ on every stage, so y*′ = α′x′/(1 + (α′ − 1)x′) holds exactly. The builder draws this curve (101 points), and the stage points lie on it.
- **Tiers 2/3:** the stage locus only, with no `equilibriumBottom`. The caption gives α′ at the top and bottom stages, e.g. "α′ 2.22 (top) → 1.89 (bottom)" for the `debut` default.
- **Not drawn for a pseudo-binary:**
  - the CMO reference lines (empty lists; they would need key-only external flows);
  - the Tier-1 Murphree pseudo-equilibrium curve (the Tiers 2/3 rule applies: a line through the corners);
  - the R_min construction (`rmin` is null even when requested; the caption points to the FUG panel, §14.3).
- The q-line is drawn clipped to the frame, with no intersection.
- Murphree gap markers, pinch shading, the transient flag and stage taps all work on primed values.
- Plant views: `available = false`, as for binaries (§10.9).
- Reference values: VALIDATION.md VC-9.3 and VC-9.6.

### 14.3 FUG shortcut panel (multicomponent, M7)

Recomputed every 10 s of sim time from the live column:

```
α_i = √(α_i,top · α_i,bottom)    relative to HK, from K at stage 1 and stage N+1
Recoveries: r_LK = D x_D,LK / (F z_LK)  ,  r_HK = B x_B,HK / (F z_HK)   (live) — or user targets
Fenske:     N_min = ln[ (d_LK/b_LK)(b_HK/d_HK) ] / ln(α_LK/α_HK)
Non-keys:   d_i/b_i = α_i^N_min · d_HK/b_HK
Underwood:  Σ_i α_i z_i / (α_i − θ) = 1 − q,   root θ ∈ (α_HK, α_LK) by bisection (80 iterations)
            R_min + 1 = Σ_i α_i x_D,i / (α_i − θ)
Gilliland (Molokanov et al., Int. Chem. Eng. 12 (1972) 209):
            X = (R − R_min)/(R + 1),  Y = 1 − exp[ (1 + 54.4 X)/(11 + 117.2 X) · (X − 1)/√X ],  N = (N_min + Y)/(1 − Y)
Kirkbride:  N_R/N_S = [ (z_HK/z_LK) (x_B,LK/x_D,HK)² (B/D) ]^0.206
```

Shown next to the rigorous column: actual stages × average efficiency, actual R, actual feed stage.

**Exact rules (M7 readiness pass).** VALIDATION.md VC-9 already fixed the procedure. This text states it once, for the panel and the tests alike:
- **Keys.** The keys must be adjacent in volatility: no component may have an α between α_HK and α_LK, at stage 1 or at stage N+1. Otherwise the panel shows "keys must be adjacent" and returns `valid = false`. With adjacent keys, Underwood's equation has exactly one root in (α_HK, α_LK).
- **α by tier.**
  - Tier 1: the preset constants.
  - Tiers 2/3: α_i = √(α_i,1 · α_i,N+1), where α_i,j = K_ij / K_HK,j is evaluated at T_j and P_j of stage 1 (the top tray) and stage N+1 (the reboiler). Stage 1 is used, not the drum, because a total condenser's drum is not an equilibrium stage.
- **Feed.** z is the live feed composition (after any F07). q is the lever in Tier 1 and (3.15) in Tiers 2/3.
- **Recoveries and R.**
  - Live mode: r_LK = D x_D,LK/(F z_LK) and r_HK = B x_B,HK/(F z_HK) from the true product flows and compositions, with R = L₀/D.
  - Target mode (`FugTargets`): the user's r_LK and r_HK, with either the live R or R = k R_min (k default 1.3, as in VC-9).
- **Fenske split.** The x_D and x_B used in Underwood and Kirkbride come from the Fenske distribution (d_i, b_i above), *not* from the live products. This makes the panel a self-consistent shortcut design for the stated recoveries. N_min, N and N_R count equilibrium stages including the reboiler; a total condenser is not a stage (VALIDATION.md §0).
- **Kirkbride.** N_R = N (N_R/N_S)/(1 + N_R/N_S) is the number of stages above the feed stage; the feed stage is the first stripping stage.
- **Guards.**
  - The result is valid only if 0.5 < r_LK < 1 − 10⁻⁹, 0.5 < r_HK < 1 − 10⁻⁹ and (d_LK/b_LK)(b_HK/d_HK) > 1. Otherwise `valid = false` and the panel shows "no key split to analyse". This covers start-up, F = 0 and a collapsed column.
  - R ≤ R_min gives N = ∞ and `belowRmin = true`, with the banner "below minimum reflux: no finite number of stages".
- **The rigorous column next to it.**
  - N_act = Σ_j E_j^eff + 1: the trays' effective Murphree efficiencies (4.2) plus the reboiler. The `debut` default gives 32 × 0.7 + 1 = 23.4.
  - N_R,act = Σ_{j < n_F} E_j^eff: the stages above the feed tray. The `debut` default gives 15 × 0.7 = 10.5.
  - R_act = L₀/D.
  - The panel states that N × E_MV is the textbook approximation; the Lewis relation (4.3) differs from it by a few % at these stripping factors.
- **Refresh and cost.** The panel is recomputed every 10 s of sim time and whenever the targets change. One evaluation is under 0.1 ms.
- **Views.** In plant and plantCalc views the panel is not available (`FugCalculator` returns null), because it needs model compositions. The Products tab then shows the analyser results only.
- **Reference values.** VALIDATION.md VC-9.1/9.2 (design mode) and VC-9.7 (live mode on the preset defaults and in G13).

### 14.4 Crude diagrams

TBP curves (feed and each product), D86 curves (naphtha to AGO), 5–95 gap/overlap bars between adjacent products (green = gap, red = overlap), temperature profile with draw and return stages marked, internal reflux (liquid traffic) profile, overflash and product yields (vol % of crude) versus the ideal TBP-cut yields.

### 14.4b T-x-y and x-y diagrams (M5)

`TxyData.build(model, P)` makes, for a binary at pressure P:
- the bubble curve T_bub(x) and the dew curve T_dew(y), on 201 points in x;
- the x-y equilibrium curve;
- azeotrope markers, with their x and T.

Points:
- The grid is uniform with spacing 0.005.
- It is refined with 21 extra points within ± 0.02 of each azeotrope, and with 10 log-spaced points in (0, 0.01) and (0.99, 1).

Curves:
- The dew curve is computed as the bubble point at each grid x paired with its y*: the point (y*, T) lies on the dew curve, so both curves come from one bubble-point sweep, without a separate dew solve. The pairs are sorted by y before drawing.
- Azeotropes are found as in VALIDATION.md VC-10.5: sign changes of y* − x on the grid, refined by bisection to 1×10⁻⁸.

Overlays:
- The column's stages at their own (x_j, T_j); the drum and sump points labelled D and B.
- A second pair of curves at P_{N+1} when the column pressure drop exceeds 1 kPa.

Caching and limits:
- Recomputed only when |P − P_cached| > 100 Pa, P_cached being the pressure of the last build, or when the tier changes (cost ≈ 400 bubble points ≈ 1 ms). This is a hysteresis, not 100-Pa buckets: noise or a slow drift across a rounding boundary must not rebuild (2026-10-13).
- Constant α has no temperatures, so in Tier 1 the curves come from the Tier-2 (Raoult) model and are labelled "ideal (Raoult)" (SCOPE.md §7.2b); the stage points use the display-only T* of §1.3 (the same Raoult bubble point), so they sit on the drawn bubble curve. The x-y sub-view shows the constant-α curve the column actually uses. For `ac` the tab also shows the Tier-1 banner of §2.3.
- Multicomponent presets get no T-x-y, only the profile charts.

### 14.5 Profiles (all systems)

Per stage: T, P, x (all components), L, V, L/V, holdup, ΔP, φ (jet), downcomer flood fraction, weeping fraction, E_eff, HETP (packing). Tier 2/3 vs Tier 1 comparison overlay (ghost line) is available when the learner has just switched tier. In plant view (§10.9) the Profiles tab shows only the instrumented temperatures (C6 below).

### 14.6 Cross-checks: catching a lying instrument

The engine computes these checks from **readings only** (instrument values and quality, plus lever values a real operator also knows: feed q or T_F, reflux subcooling, design constants). They therefore work in plant view and cannot leak the truth. The app shows them in the **Balance** panel (a ControlPanel tab from M3), and each one opens in the math overlay (`ExplainCheck`, ids `eq.check.*`) with the readings substituted.

**Common rules**
- **Window.** W ∈ {300, 600, 1800, 3600} s, selectable in the panel, default 600 s. Checks are recomputed every 5 s of sim time from the 5-s trend bins (bin means).
- **Notation.** X̄ is the mean of reading X over the window. X_start and X_end are the means over the first and last 60 s of the window. ∫X is Σ over bins of (bin mean × 5 s).
- **Level to moles.** N_0,1% and N_S,1% are the mol per 1 % of drum and sump level, from the preset's design steady state (constant; B-T Tier 1: 307 mol and 236 mol). ΔN_0 = (LT-101_end − LT-101_start) N_0,1%, and likewise ΔN_S.
- **Status and band.** Each check has a residual r and a band. Status is `ok` for |r| ≤ band, `check` for band < |r| ≤ 2 band and `fail` for |r| > 2 band, shown green, amber and red with the number r/band.
- **Bad inputs.** If any input is BAD or OOS, the status is `n/a` with the tag named. UNCERTAIN inputs are used but flagged.
- **Partial condenser (M4, 2026-10-13).** The vapour product D_V has no flow transmitter. C1, C2 and C3b need every product stream, so they show `n/a` ("vapour product not metered"). So does C5 (sump), ratified 2026-10-13 from the M5 validation: its V̂ = V_cw stands for the boil-up, which with a partial condenser is V_cw + D_V (B-T at 30 % CW reads ≈ −8 % against a band of 1.5). C3a and C5 (drum) stay: V_cw is the condensed vapour, which balances L_0 + D + ΔN_0/W with either condenser. C4 PV-101/FT-201 runs on the CW valve (held at `cwOP`); PV-102 has no meter and no C4 row. A vapour-product meter is not planned before M9.
- **Steady-only check.** C2 shows `transient` while the steady indicator (§13.3) is false; the column inventory absorbs composition changes for about an hour.
- **Band sizes.** Bands are 3–10× the noise of the windowed residual at the default window. A fault larger than about twice the band is unambiguous on a phone, and drill severities are chosen to meet that (ENGINE_API.md §11.5).

| Id | Check | Residual (B-T notation) | Band | What the learner sees |
|---|---|---|---|---|
| C1 | **Total material balance** (all tiers) | r1 = F̄ − D̄ − B̄ − (ΔN_0 + ΔN_S)/W with F = FT-101, D = FT-104, B = FT-105 | max(2.0 kmol/h, 0.02 F̄) · max(1, 600 s/W). The level term's noise scales as 1/W (fixed end-point averages divided by W): ≈ 0.83 kmol/h at W = 600 s. Scaling the band keeps band/noise ≈ 2.4 at every window ≤ 600 s; without it, W = 300 s gave 18 % `check` and 1.2 % `fail` on a healthy column (tester) | Row "In F 100.2 · Out D + B 99.9 · Accumulating +0.1 · Unaccounted +0.2 kmol/h (band ±2.0)" |
| C2 | **Component balance** (light component; for multicomponent the light cut, LK and lighter, read by AT-100/101/102 as in §10.5; exact for adjacent keys); steady only, W ≥ 1800 s | r2 = F̄ z̄ − D̄ x̄_D − B̄ x̄_B, with z = AT-100, x_D = 1 − AT-101, x_B = AT-102 (B-T). Also D/F from meters, D̄/F̄, against D/F from analysers, (z − x_B)/(x_D − x_B) | 0.01 F̄ z̄; D/F ± 0.01 | "Benzene in 50.1, out 49.6 kmol/h; D/F: meters 0.502, analysers 0.499" |
| C3 | **Top vapour, Tier 1**: boilup vs reflux + distillate (CMO) | V_boil = V̄_B + (1 − q) F̄ (V_B = FT-103, q = feed lever); V_refl = L̄_0 + D̄ + ΔN_0/W (L_0 = FT-102); r3 = V_boil − V_refl | max(2.0 kmol/h, 0.015 V_refl) · max(1, 600 s/W) (same reason as C1) | Three numbers: "Vapour to the top: from boilup 150.1 · from reflux + distillate 149.8 · difference +0.3 (band ±2.3)" |
| C3a | **Top vapour, Tiers 2/3**: condenser duty vs reflux + distillate | Q_C,cw = ρ_w FT-201 c_p,w (TI-202 − TI-201) (windowed means; ρ_w 995 kg/m³, c_p,w 4180 J/kg/K); λ_top = H_V(x_D, T_cond) − h_L(x_D, T̄_100), T_cond = T_bub(x_D, P̄_101); V_cw = Q_C,cw/λ_top; r3a = V_cw − V_refl | max(2.0 kmol/h, 0.02 V_refl) · max(1, 600 s/W) | "Condenser 1282 kW ≈ 150.3 kmol/h of vapour · reflux + distillate 149.9" |
| C3b | **Column energy balance**, Tiers 2/3 | r3b = Q̄_R + F̄ h_F − Q_C,cw − D̄ h_D − B̄ h_B; Q_R = FT-103; h_F from the feed lever (T_F) and z = AT-100 with the simulator's own feed-enthalpy function; h_D = h_L(x_D, T̄_100); h_B = h_L(x_B, T̄_121) | 0.02 Q̄_R | "Reboiler 1301 kW + feed −12 kW = condenser 1282 kW + products 4 kW · unaccounted +3 kW (band ±26)" |
| C4 | **Valve characteristic**, one per valve–meter pair: FV-101/FT-101, FV-102/FT-102, FV-103/FT-103, LV-101/FT-104, LV-102/FT-105, PV-101/FT-201 | F_exp = F_max g(OP̄); for FV-103 in Tiers 2/3, Q_exp = Q_max,0 g(OP̄) with Q_max,0 = UA_R,clean (T_st(P̄_201) − T̄_121); thermosyphon (M6): Q_max,0 = U A (T_st(P̄_201) − T̄_121 − ΔT_sub/2), with ΔT_sub from (8.3) at the LT-102 window mean and the design dT_sat/dP and ρ_L (preset constants); r4 = F̄_meas − F_exp | 0.015 F_max (10-min noise of r4 from d: ≈ 0.32 % of the flow) | On each faceplate, a small plot of flow vs OP with the straight characteristic, a band and the window-mean operating point. Panel row: "FV-102: OP 30.3 % → expects 90.9 kmol/h; meter says 100.0 (−9.1, band ±4.5)" |
| C5 | **Level vs integrated flows** (drum, sump) | Drum: Δ_pred = ∫(V̂ − L_0 − D) dt / N_0,1%; sump: Δ_pred = ∫(F + L_0 − V̂ − B) dt / N_S,1% (tray holdups taken constant). V̂ = V_boil (T1) or V_cw (T2/3); Δ_meas = LT_end − LT_start; r5 = Δ_meas − Δ_pred (in % level) | 1.0 % + 0.5 % per 600 s of window | A mini-trend over the window: measured level (solid) and "level predicted from the flows" (dashed, starting at the same point). The gap at the end is r5 |
| C6 | **Tray temperatures** (T2/3), in two parts | (a) Ordering: going down the column readings must rise; flag TI k if T̄_k < T̄_above − 0.5 K or T̄_k > T̄_below + 0.5 K. (b) Change since a reference: ΔT_k = T̄_k − T_k,ref, where the reference is the 300-s mean at drill start or when the learner presses "Set reference". Flag k if \|ΔT_k − ½(ΔT_above + ΔT_below)\| > max(1.0 K, 0.5 max(\|ΔT_above\|, \|ΔT_below\|)); the end TIs use their single neighbour | (as stated) | The plant-view temperature profile: dots at instrumented trays, the reference profile as a ghost line, and a bar chart of ΔT per TI with flagged TIs in red. A lying TI is a lone bar; a real process change is a smooth wave of bars |
| C7 | **Bubble-point consistency** (T2/3 binaries; T_bub uses the active tier's K model, so NRTL or DePriester in Tier 3); valid in transients too (the pressure term acts at once; a composition transient adds at most a few tenths of a kelvin through the analyser lag) | Top: r7a = (T̄_100 + ΔT_sub,lever) − T_bub(x_D, P̄_101). Bottom: r7b = T̄_121 − T_bub(x_B, P̄_101 + P̄DT_101) | ±1.0 K each | "Top: drum 80.1 °C + 0 K subcooling vs bubble point of the analysed distillate at the measured pressure 80.3 °C (−0.2 K)". A lying PT moves both rows by about (dT/dP)·b with the same sign (B-T near 1 atm: 0.33 K/kPa) |

Signal look (on every faceplate detail, all tiers): the 5-min standard deviation of the reading next to its typical healthy value σ_disp (§10.5), and the age of the last change of the displayed digits. "σ 0.00 (typical 1.23)" means frozen; "σ 0.06 (typical 1.23)" means too steady; "σ 9.4 (typical 1.23)" means erratic.

Trends make faults visible on a phone because:
- Each trend auto-scales its y-axis to the data, with a minimum visible range of 10 σ_disp of the tag. Healthy fuzz then fills about a fifth of the plot height, and a plugged or stuck line is visibly flat.
- Each pixel column draws the min–max envelope of its bins, so 1-s spikes survive decimation (ENGINE_API.md §5.4).

**Which checks fail for which fault.** This table is used by hints and debriefs. "Own C4" means the check of the faulty meter's own valve line.

| Fault | C1 | C3 / C5 (drum) | Own C4 | C5 (sump) | C6 | C7 | Signal look |
|---|---|---|---|---|---|---|---|
| FT-102 bias or drift | ok | fail | fail | ok | coherent (true reflux changed) | ok | normal |
| FT-102 plugged | ok | fail | fail | ok | coherent | ok | too steady |
| FV-102 stuck (F20) | ok | ok | fail | ok | ok | ok | normal; OP wandering |
| FT-103 bias, drift or plugged | ok | fail | fail | fail | coherent | ok | normal / too steady |
| FV-103 stuck | ok | ok | fail | ok | ok | ok | normal; OP wandering |
| FT-101 bias or drift | fail | ok (q = 1) | fail | fail | coherent | ok | normal |
| FT-104 or FT-105 fault | fail | fail (FT-104) / ok | fail | ok / fail | ok | ok | as mode |
| LT-101 bias | fail for one window after onset | fail for one window | ok | ok | ok | ok | step at onset; field gauge LG-101 disagrees |
| LT-101 or LT-102 drift | fail (∝ W) | fail (∝ W) | ok | fail (LT-102) | ok | ok | normal |
| LT stuck or plugged | fail after any flow change | fail after any flow change | ok | as drum | ok | ok | flat / too steady |
| PT-101 bias | ok | small | ok | ok | coherent shift | fail both rows, same sign | normal |
| TI bias, drift, spiking, stuck or coated | ok | ok | ok | ok | flagged at that TI (coated: during transients only) | fail if TI-100 or TI-121 | as mode |
| Real feed upset (F07) | ok | ok | ok | ok | coherent wave | ok once the analysers catch up | normal |
| Reboiler fouling or condensate backup (F13, F14), thermosyphon restriction (F17, F18) (M6) | ok | ok | FV-103 `fail` once the duty falls short with FC-103 at 100 % (the clean characteristic promises more) | ok | coherent (less boilup) | ok | normal; F18 adds a ≈ 10-s ripple to the bottom TIs, not to FT-103 (§8.3.4) |
| LT-102 drift with a thermosyphon (H5) | `check` at 10 %/h (r ≈ 1.15 band at any window: r1 is a rate) | – | ok | `check` at the 600-s window (r ≈ 1.1 band), borderline at 1800 s (2.0), `fail` at 3600 s (r ≈ 2.5 band) | ok | ok | normal; field gauge LG-102 disagrees |

---

## 15. Equation trace catalogue

The math overlay (ENGINE_API.md §8) shows, for the selected item, equations from this catalogue with the live values substituted. Equation ids are stable and reference the numbering in this document.

| Target | Equation ids (in display order) |
|---|---|
| Tray j | `eq.componentBalance` (4.1, for the light component or LK), `eq.equilibrium.T1` (3.1) or `eq.raoult` (3.2) / `eq.nrtl` (3.7–3.8) / `eq.depriester` (3.9), `eq.bubblePoint` (3.6.1 result), `eq.murphree` (4.2), `eq.vapourFlow.cmo` (4.5) or `eq.vapourFlow.energy` (4.6), `eq.bennett` (5.2), `eq.dryDP` (5.3/5.4), `eq.trayDP` (5.5), `eq.jetFlood` (5.6), `eq.entrainment` (5.7–5.8), `eq.downcomer` (5.10–5.11), `eq.weeping` (5.12–5.14) |
| Packed segment k | component balance, equilibrium, `eq.robbins` (6.1), `eq.kisterGill` (6.2), `eq.packHoldup` (6.3), `eq.hetp` (6.5), `eq.lewis` (4.3), `eq.maldistribution` (6.6) when active |
| Feed | `eq.flash` (3.14), `eq.qValue` (3.15) |
| Condenser / drum | `eq.condenserDuty` (7.3), `eq.condensation` (7.4), `eq.overheadPressure` (7.1), `eq.drumBalance` (7.6) |
| Reboiler | `eq.kettleDuty` (8.2) or the thermosyphon set `eq.ts.subcooling`, `eq.ts.exitQuality`, `eq.ts.drivingHead`, `eq.ts.friction`, `eq.ts.instabilityIndex` (8.3–8.4), and `eq.boilup` (4.7) |
| Streams D, B, products | composition, flow, `eq.overallBalance` (F z = D x_D + B x_B, live residual), enthalpy |
| Controller | `eq.pid` (10.1) with the last e, ΔOP, OP; `eq.valve` (10.2) with OP, flow and the expected flow |
| Instrument | `eq.instrument` (pipeline of §10.5 with the current values of v, v_m, b, I, v_meas and the quality); analysers add `eq.analyser` (sample time, publication time, age) |
| Cross-check | `eq.check.material` (C1), `eq.check.component` (C2), `eq.check.topVapour` (C3, C3a), `eq.check.energy` (C3b), `eq.check.valve` (C4), `eq.check.level` (C5), `eq.check.trayT` (C6), `eq.check.bubble` (C7), with the readings substituted |
| McCabe–Thiele elements | operating line equations, q-line, R_min construction (14.1); pseudo-binary: `eq.hengstebeck` (14.2) |
| FUG panel (M7) | `eq.fug.alpha` (geometric-mean α, 14.3), `eq.fug.fenske` (N_min), `eq.fug.split` (non-key d_i/b_i), `eq.fug.underwood` (θ and R_min), `eq.fug.gilliland` (X, Y, N), `eq.fug.kirkbride` (N_R/N_S, N_R), each with the live values; the rigorous comparison (N_act, N_R,act, R_act) as a closing line |

---

## 16. Simplifications (summary)

| Simplification | Where | Why it is acceptable | What it hides (shown in the overlay) |
|---|---|---|---|
| Vapour holdup neglected; vapour flows algebraic | §4.4–4.5 | Vapour time constants ≪ 1 s | Pressure waves between trays |
| Liquid at bubble point; T algebraic | §4.7 | Trays are boiling | Subcooled trays during start-up |
| Quasi-steady energy balance with lagged sensible storage | §4.5 | Energy dynamics faster than composition; storage term keeps flashing/heating effects | First-step error after a sudden pressure jump |
| Ideal heat of mixing (h^E = 0) | §3.3 | ≤ 2 % of latent heat for the shipped systems | Small energy effects in ethanol–water |
| Constant viscosity per preset | §2.3 | Viscosity enters via exponents ≤ 0.25 | Viscosity change with T |
| Perfectly mixed trays (no liquid gradient, no plug flow) | §4 | Standard stage model | Lewis plug-flow efficiency enhancement |
| Downcomer holdup not tracked | §5.7 | Downcomer liquid level computed algebraically | Downcomer residence time (≈ seconds) |
| Entrainment fit to Fair's chart; ψ ≤ 0.6 | §5.6 | Chart is ± factor 2; beyond 0.6 the full-tray overflow governs | Very high entrainment regime details |
| Thermosyphon instability via index + oscillator | §8.3.3 | First-principles density waves need fine meshes and ms steps | Exact oscillation waveform |
| Thermosyphon: steam chest as a first-order buffer (τ_st = 10 s, FT-103 reads Q_st); loop liquid inventory not coupled to the sump | §8.3.4 | Steam chest and condensate absorb a 5–20 s swing; energy mismatch ≤ 1.5 % | Steam-flow ripple during surging; sump-level swing from void changes |
| Steam side without a chest pressure: Q = min(Q_v, Q_max) with Q_v from the clean Q_max,0 at the header | §8.2, §10.3 | Same duties and the same saturation point as a chest-pressure model; clean-state valve positions stay simple (60 % at design) | FV-103 creeping open as fouling raises the chest pressure: in LowSYS it stays at its clean position, then runs to 100 % within minutes (F13, H4) |
| Packing: Robbins ΔP and Kister–Gill flood (random-packing correlations) also for structured packing; HETP from a catalogue value × wetting × loading; Onda wetting; maldistribution as two parallel columns; ideal distributors and redistributors with no ΔP | §6 | Right order and right trends (ΔP ∝ G² rising steeply near flood, HETP up at low load and near flood, maldistribution worst near S = 1 and in tall beds) for a teaching simulator | Vendor-specific capacity and HETP, liquid-load effects on structured packing ΔP, radial profiles, wall flow |
| DePriester K for hydrocarbons instead of an EOS | §3.4.2 | Textbook standard, fast | Composition dependence of K |
| FUG with one geometric-mean α per component, the Fenske non-key split and Molokanov's Gilliland fit | §14.3 | The textbook shortcut; it is shown next to the rigorous column, not used by it | α variation along the column (`debut` Tier 3: α_LK 2.22 at the top, 1.89 at the bottom) |
| Watson λ = 0 above a component's T_c | §3.3 | Only propane in the `deprop` bottoms (x ≈ 0.004) | Supercritical-component enthalpy (< 0.3 % of the reboiler balance) |
| Crude: no light ends, constant K_W, steam as inert vapour, 2-stage strippers | §9 | Teaching fidelity; captures cut points, gaps, steam stripping, PA heat balance | Offgas, water dew point details, kerosene flash point |
| Valves deliver F_max g(p)(1 + d): no pump curves, no line losses, inherent = installed characteristic | §10.3 | Gives a straight characteristic a learner can check; real loops behave the same in the small | Installed-characteristic distortion, pump run-out |
| Instrument noise as OU processes with textbook magnitudes; no process-condition dependence | §10.5 | Signatures (bias, frozen, too steady, erratic, slow) are what diagnosis needs | Flashing in impulse lines, temperature effects on transmitters |

---

## 17. References

1. McCabe, W. L.; Thiele, E. W. Graphical design of fractionating columns. *Ind. Eng. Chem.* 17 (1925) 605.
2. Fenske, M. R. Fractionation of straight-run Pennsylvania gasoline. *Ind. Eng. Chem.* 24 (1932) 482.
3. Underwood, A. J. V. Fractional distillation of multicomponent mixtures. *Chem. Eng. Prog.* 44 (1948) 603.
4. Gilliland, E. R. Multicomponent rectification. *Ind. Eng. Chem.* 32 (1940) 1220; Molokanov, Yu. K. et al. *Int. Chem. Eng.* 12 (1972) 209.
5. Kirkbride, C. G. Process design procedure for multicomponent fractionators. *Petrol. Refiner* 23 (1944) 87.
6. Murphree, E. V. Rectifying column calculations. *Ind. Eng. Chem.* 17 (1925) 747; Lewis, W. K. Rectification of binary mixtures — plate efficiency. *Ind. Eng. Chem.* 28 (1936) 399; Colburn, A. P. Effect of entrainment on plate efficiency. *Ind. Eng. Chem.* 28 (1936) 520; O'Connell, H. E. *Trans. AIChE* 42 (1946) 741.
7. Hengstebeck, R. J. A simplified method for solving multicomponent distillation problems. *Trans. AIChE* 42 (1946) 309.
8. Fair, J. R. How to predict sieve tray entrainment and flooding. *Petro/Chem Eng.* 33(10) (1961) 45; Lygeros, A. I.; Magoulas, K. G. Column flooding and entrainment. *Hydrocarbon Processing* 65(12) (1986) 43.
9. Bennett, D. L.; Agrawal, R.; Cook, P. J. New pressure drop correlation for sieve tray distillation columns. *AIChE J.* 29 (1983) 434.
10. Summers, D. R. et al. Tray stability at low vapor load. *Distillation & Absorption 2010*, Eindhoven, pp. 611–616.
11. Lockett, M. J. *Distillation Tray Fundamentals*. Cambridge University Press (1986); Billingham, J. F.; Banik, S.; Lockett, M. J. The effect of inlet weeping on distillation tray efficiency. AIChE Annual Meeting (1994), paper 134e.
12. Sinnott, R. K. *Coulson & Richardson's Chemical Engineering Vol. 6*, 4th ed., Butterworth-Heinemann (2005), §11.13 (plate hydraulics).
13. Bolles, W. L. Estimating valve tray performance. *Chem. Eng. Prog.* 72(9) (1976) 43.
14. Kister, H. Z. *Distillation Design*. McGraw-Hill (1992); *Distillation Operation* (1990); *Distillation Troubleshooting*. Wiley (2006).
15. Robbins, L. A. Improved pressure drop prediction with a new correlation. *Chem. Eng. Prog.* 87(5) (1991) 87; Kister, H. Z.; Gill, D. R. Predict flood point and pressure drop for modern random packings. *Chem. Eng. Prog.* 87(2) (1991) 32.
16. Billet, R.; Schultes, M. Prediction of mass transfer columns with dumped and arranged packings. *Trans IChemE* 77A (1999) 498; Onda, K.; Takeuchi, H.; Okumoto, Y. *J. Chem. Eng. Japan* 1 (1968) 56.
17. Hoek, P. J.; Wesselingh, J. A.; Zuiderweg, F. J. Small scale and large scale liquid maldistribution in packed columns. *Chem. Eng. Res. Des.* 64 (1986) 431.
18. Renon, H.; Prausnitz, J. M. Local compositions in thermodynamic excess functions for liquid mixtures. *AIChE J.* 14 (1968) 135.
19. Beneke, D.; Peters, M.; Glasser, D.; Hildebrandt, D. *Understanding Distillation Using Column Profile Maps*. Wiley (2013), Appendix B (NRTL and Antoine parameters).
20. Dean, J. A. *Lange's Handbook of Chemistry*, 15th ed. (Antoine constants).
21. Green, D. W.; Perry, R. H. *Perry's Chemical Engineers' Handbook*, 8th ed. (2008), Table 2-8 (DIPPR-101 vapour pressure).
22. Poling, B. E.; Prausnitz, J. M.; O'Connell, J. P. *The Properties of Gases and Liquids*, 5th ed. McGraw-Hill (2001).
23. Lee, B. I.; Kesler, M. G. A generalized thermodynamic correlation based on three-parameter corresponding states. *AIChE J.* 21 (1975) 510.
24. McWilliams, M. L. An equation to relate K-factors to pressure and temperature. *Chem. Eng.* 80(25) (1973) 138; DePriester, C. L. *Chem. Eng. Prog. Symp. Ser.* 49(7) (1953) 1; Seader, J. D.; Henley, E. J.; Roper, D. K. *Separation Process Principles*, 3rd ed. Wiley (2011).
25. Riazi, M. R.; Daubert, T. E. Simplify property predictions. *Hydrocarbon Processing* 59(3) (1980) 115; Riazi, M. R. *Characterization and Properties of Petroleum Fractions*. ASTM MNL50 (2005); Daubert, T. E. Petroleum fraction distillation interconversions. *Hydrocarbon Processing* 73(9) (1994) 75.
26. Watson, K. M.; Nelson, E. F. Improved methods for approximating critical and thermal properties of petroleum fractions. *Ind. Eng. Chem.* 25 (1933) 880.
27. Watkins, R. N. *Petroleum Refinery Distillation*, 2nd ed. Gulf (1979); Packie, J. W. Distillation equipment in the oil refining industry. *Trans. AIChE* 37 (1941) 51.
28. Horsley, L. H. *Azeotropic Data III*. ACS Advances in Chemistry 116 (1973) (azeotrope compositions and temperatures).
29. Smith, J. M.; Van Ness, H. C.; Abbott, M. M. *Introduction to Chemical Engineering Thermodynamics*, 7th ed. (Pitzer virial correlation).
