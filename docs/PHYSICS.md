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
      controller integrals / OPs, valve positions, measurement filters
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

Tier-1 α values for the non-ideal binaries are the geometric mean of the Tier-3 α at x = 0.1, 0.5 and 0.9 (1 atm); for `debut`/`deprop` they are the geometric mean of the DePriester α at the top and bottom temperatures of the FUG design case (VALIDATION.md VC-9). They are stored constants, not recomputed.

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

γ depends on T only through τ; inside the bubble-point Newton iteration dγ/dT is ignored (§3.6), which converges in 3–5 iterations anyway.

#### 3.4.2 DePriester K-values (light hydrocarbons)

McWilliams, Chem. Eng. 80(25) (1973) 138, fit of the DePriester (1953) charts; table as reproduced in Seader, Henley and Roper, *Separation Process Principles*. T_R in °R (T_R = 1.8 T), p in psia (p = P / 6894.757):

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

Validity: 365–700 °R and 14.7–870 psia. Outside, evaluate at the clamped T and p and set `thermoOutOfRange`. K depends on T and P only (no composition dependence), which is why DePriester charts are fast; the non-ideality they capture is the pressure effect on light hydrocarbons near their critical points.

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
Fallback: bisection on [T_lo, T_hi] = [150 K, 0.98 · min_i T_c,i  (or 900 K for crude)] after
          bracketing g(T_lo) < 0 < g(T_hi); 60 iterations; set solverHealth.bubbleFallbacks += 1
Output:  T, K_i, y*_i = K_i x_i / S   (normalised)
```

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

Overall-to-Murphree (Lewis, Ind. Eng. Chem. 28 (1936) 399), used for packed segments and in the math overlay, with stripping factor λ = m V / L (m = local slope of the equilibrium curve, dy*/dx):

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
      − C_j (T_j^n − T_j^(n−1)) / dt ] / (H_j − h_j)                                     (4.6)

C_j = M_j · Cp_L,j + m_metal,j · 500 J/(kg·K)            (sensible heat of liquid + tray metal)
m_metal,j = 75 kg/m² × A_T  (tray, shell share and supports)
```

- Evaluated bottom-up (j = N … 1) with all enthalpies and T at the start of the step, L_{j−1} and the other liquid flows from the previous step, and V_{j+1} just computed. One sweep, no iteration.
- H_j uses the vapour actually leaving (y_j at T_j). The two bypass terms come from the bypass split of §4.1: tray j receives (1 − f_j) L_{j−1} from above plus the liquid f_{j−1} L_{j−2} that fell through tray j−1.
- The storage term makes the column absorb heat when it warms (pressure rise, start-up) and flash when it cools (pressure drop). It is bounded: |C_j ΔT/dt| ≤ 0.5 · (numerator without the storage term) when that numerator is positive, to stop a large pressure step from reversing vapour flow in one step **[safeguard]**.
- V_j is clamped to ≥ 0.
- At steady state the storage term is zero and (4.6) is the exact steady energy balance, so energy closure at steady state is exact (VALIDATION.md VC-11).

Sump/reboiler (j = N+1):

```
V_{N+1} = s_sump · [ L_N (h_N − h_B) + f_N L_{N−1} (h_{N−1} − h_B) + Q_R,delivered − C_B ΔT_B/dt ] / (H_B − h_B)     (4.7)
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
| Tray spacing | TS | 0.60 m |
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
ΔP_j = ΔP_dry + ρ_L g h_cl + ΔP_σ                                                   (5.5)
P_1 = P_top        P_{j+1} = P_j + ΔP_j        P_{N+1} = P_N + ΔP_N
```

(ρ_L g h_cl is the hydrostatic head of the froth: the clear-liquid equivalent.) In ideal-hydraulics mode ΔP_j = 0.

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

**Dumping.** When the vapour can no longer hold liquid on the deck at all (Φ < 0.2, e.g. boilup lost), the tray drains through its holes:

```
k_d,j = ((0.2 − Φ_j) / 0.2) / τ_d          τ_d = 8 s           (only when Φ_j < 0.2)
L_j  += k_d,j · M_j          (implicit; part of the downflow with tray composition)              (5.15)
```

Valve trays reach low Φ only when the valves are closed (§5.4), which is why they turn down further (about 5:1 versus 2:1 for sieve trays with the defaults).

### 5.9 Downflow summary

```
L_j = smin( L_weir(M_j), L_max,j ) + k_d,j M_j          smin = plain min [impl may smooth]       (5.16)
```

### 5.10 Indicators reported per tray

φ_j (jet flood), ψ_j, downcomer flood fraction, M_j/M_max,j (froth fill), Φ_j and w_j (weeping), ΔP_j, h_cl, α_e, froth height h_f = h_cl/α_e, u_h, E_j^eff, and booleans `dcLimited`, `dumping`, `overflowing`. "Max flood %" in the KPI strip = 100 × max over trays of max(φ_j, dc flood fraction, M_j/M_max,j).

---

## 6. Packed sections

### 6.1 Discretisation

A packed bed of height H_bed with reference HETP_ref is split into n_seg = max(1, round(H_bed / HETP_ref)) segments of height H_k = H_bed / n_seg. Each segment is a stage in the chain (same component balance (4.1), same energy balance (4.6)) whose Murphree efficiency comes from the HETP (§6.4). A liquid feed or reflux enters the top segment of a bed through an ideal distributor unless the maldistribution fault is active (§6.6). Packed segments have no weeping, no downcomer and no entrainment terms.

### 6.2 Packing data

Packing factors F_p (ft⁻¹) and areas from Kister, *Distillation Design*, McGraw-Hill (1992), chapter 8, and vendor bulletins as summarised there; HETP rules of thumb from Kister (random: HETP[ft] ≈ 1.5 × nominal size [in]; structured: HETP[in] ≈ 1200/a[ft²/ft³] + 4). Values are representative, not vendor-certified.

| id | Packing | a (m²/m³) | ε | F_p (ft⁻¹) | Material σ_c (mN/m) | HETP_ref (m) |
|---|---|---|---|---|---|---|
| pall25m | 25 mm metal Pall rings | 205 | 0.94 | 56 | 75 (steel) | 0.46 |
| pall50m | 50 mm metal Pall rings | 105 | 0.96 | 27 | 75 | 0.91 |
| raschig50c | 50 mm ceramic Raschig rings | 92 | 0.74 | 65 | 61 (ceramic) | 0.91 |
| struct250 | Structured, 250 m²/m³ (Mellapak 250Y class) | 250 | 0.98 | 20 | 75 | 0.45 |
| struct500 | Structured, 500 m²/m³ (Mellapak 500Y class) | 500 | 0.975 | 34 | 75 | 0.30 |

### 6.3 Holdup, pressure drop, flooding

Superficial velocities: u_L = L v_L / A_T, u_V = V MW_V/(1000 ρ_V A_T); mass fluxes L' = L MW_L/(1000 A_T), G' = V MW_V/(1000 A_T) (kg/m²/s).

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
HETP = HETP_ref · (a_w,ref / a_w) · g(φ_p)                                                     (6.5)
a_w/a = 1 − exp[ −1.45 (σ_c/σ)^0.75 Re_L^0.1 Fr_L^−0.05 We_L^0.2 ]       (Onda, Takeuchi and Okumoto, J. Chem. Eng. Japan 1 (1968) 56)
Re_L = L'/(a μ_L)    Fr_L = L'² a / (ρ_L² g)    We_L = L'² / (ρ_L σ a)
a_w,ref = a_w at the preset's design liquid load
g(φ) = 1                       φ ≤ 0.80
     = 1 + 8 (φ − 0.80)²         0.80 < φ ≤ 1.0
     = 1.32 + 3 (φ − 1.0)       φ > 1.0
```

The wetting term makes HETP rise at low liquid loads (poor wetting); g makes it rise above about 80 % of flood (entrainment, back-mixing). The g shape is empirical; packing HETP has no first-principles model at this fidelity.

Segment efficiency: the overall efficiency of segment k is E_O,k = min(1, H_k / HETP) × E_mal (§6.6), converted to Murphree with (4.3) using λ_k = K̃_LK,k V_k / L_k (K̃ of the light key, or of the more volatile component of a binary).

### 6.5 Packed-section indicators

φ_p per segment, ΔP per segment and per bed, h_L, HETP, a_w/a, E_O,k, and `flooding` when φ_p ≥ 1.

### 6.6 Maldistribution — parallel-column model

A plugged distributor sends more liquid to one side of the bed. LowSYS uses the parallel-column model (Hoek, Wesselingh and Zuiderweg, Chem. Eng. Res. Des. 64 (1986) 431): the bed behaves as two half-columns, A and B, with liquid fractions (1 + f)/2 and (1 − f)/2 and equal vapour. Each half is a Kremser cascade of n = n_seg stages with stripping factor S_A = S/(1 + f), S_B = S/(1 − f), where S = K̃_LK V / L is the bed average.

```
Kremser fraction stripped:  Φ_K(S, n) = (S^(n+1) − S) / (S^(n+1) − 1)        (S = 1: n/(n+1))
Mixed outlet:               Φ_mal = [ (1 + f) Φ_K(S_A, n) + (1 − f) Φ_K(S_B, n) ] / 2
Equivalent stages:          n_eff = ln[ (S − Φ_mal)/(1 − Φ_mal) ] / ln S − 1    (S = 1: Φ_mal/(1 − Φ_mal))
E_mal = n_eff / n                                                                              (6.6)
```

Recomputed every 10 steps per bed. The effect is physical rather than a fixed multiplier: it is largest when S ≈ 1 (near a pinch) and when the bed has many stages, which is the known behaviour. With f = 0.2 and S = 1, a 10-stage bed keeps 70 % of its stages and a 20-stage bed only 43 % (VALIDATION.md VC-13).

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

### 7.2 Condenser duty

Cooling water flow m_cw = (OP_cw/100) m_cw,max (kg/s), inlet temperature T_cw,in, c_p,w = 4180 J/(kg·K). Using the mean water temperature T_cw,in + Q/(2 m_cw c_p,w):

```
UA_eff = UA_clean / (1 + UA_clean R_f) · (1 − f_blanket)          f_blanket = min(0.95, 3 y_I)
Q_C    = UA_eff (T_0,sat − T_cw,in) / (1 + UA_eff / (2 m_cw c_p,w))      clipped to ≥ 0               (7.3)
```

T_0,sat is the condensing temperature (drum bubble point before subcooling). Inerts act twice, as in a real condenser: they lower the condensable partial pressure (lower condensing temperature, smaller ΔT) and they blanket the tubes.

Condensation rate from the drum energy balance (vapour enters at H_1, condensate leaves at h_0):

```
N_cond = [ V_1 (H_V(y_1, T_0,sat) − H_1) + Q_C ] / ( H_V(y_1, T_0,sat) − h_L(x_0, T_0) )          (7.4)
```

The first term is the (usually small) desuperheating of the incoming vapour.

Design values (stored in the preset): UA_clean is chosen so that at the design point the condenser uses 70 % of the CW valve. For B-T: Q_C ≈ 1.281 MW, T_0 ≈ 80.2 °C, T_cw,in = 30 °C, m_cw,max = 150 m³/h (41.5 kg/s; 70 % → 29.1 kg/s) → UA_clean = 28.5 kW/K. For a new preset, the value is found once, offline: run the Tier-2 preset to steady state with the pressure held at P_top (a "perfect condenser" debug option), read Q_C and T_0,sat, solve (7.3) for UA at OP_cw = 70 %, and store the result in the preset JSON.

Total condenser: D_V = 0. Partial condenser: vapour product through the pressure-control valve

```
D_V = (OP_DV/100) D_V,max √( max(P_top − P_down, 0) / (P_design − P_down) )                 (7.5)
```

P_down = 1.01325 bar (vapour header).

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

P_top^(n+1) comes from an implicit scalar solve each step (the condenser is fast: τ_P ≈ 2–10 s):

```
Unknown P. For a trial P:  T_0,sat(P) = bubble T of x_0 at P(1 − y_I);  Q_C(P) from (7.3);  N_cond(P) from (7.4);  D_V(P) from (7.5)
Residual:  r(P) = n_V(P) − n_V^n − dt [ V_1 − N_cond(P) − D_V(P) − N_vent − N_relief(P) ] · (1 − y_I)
           with n_V(P) = P V_ovh (1 − y_I) / (R T_0,sat(P))
Secant iteration from P^n and 1.001 P^n; stop at |ΔP| < 0.1 Pa; max 12 iterations; fallback: keep P^n and flag.
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

UA_R,clean is stored in the preset, chosen so that the design duty uses 60 % of Q_max (B-T: Q = 1.30 MW at T_B = 110.4 °C and T_st = 148.1 °C → UA_R,clean = 57.5 kW/K); for a new preset it is found offline from a steady-state run, like the condenser UA (§7.2). Fouling raises R_f,R; condensate backup raises f_flooded (§11).

In Tier 1 the boilup lever V_B is used directly; heat-transfer limits do not apply.

### 8.3 Thermosyphon reboiler (M6)

A vertical thermosyphon draws sump liquid down an inlet line, heats it in tubes, and returns a two-phase mixture through a riser to the column above the liquid level. Nothing pumps it: the driving force is the density difference between the liquid leg and the two-phase leg.

#### 8.3.1 Geometry and properties (B-T defaults)

| Item | Symbol | Default |
|---|---|---|
| Tubes: number, inner diameter, length | N_t, D_i, L_t | 200, 0.0212 m, 3.0 m |
| Heat-transfer area | A | 47.6 m² |
| Overall clean U (steam → boiling organic) | U | 1000 W/(m²·K) |
| Liquid surface height above bottom tubesheet | z = z_0 + (level%/100) h_sump | z_0 = 1.2 m, h_sump = 2.4 m (75 % level → z = 3.0 m = top tubesheet) |
| Return nozzle height above bottom tubesheet | z_ret | 4.5 m (riser length L_r = z_ret − L_t = 1.5 m) |
| Inlet line diameter, length | D_in, L_in | 0.20 m, 6.0 m |
| Riser diameter | D_r | 0.30 m |
| Inlet loss coefficient (entry, bends) | K_in | 4 |
| Inlet valve loss coefficient | K_valve | K_valve = 1/(OP/100)² (1 at 100 % open, 400 at 5 %) |
| Outlet loss coefficient (bends, nozzle) | K_out | 3 |
| Exit-quality onset of mist-flow degradation | x_c | 0.30 |

Liquid properties are the sump liquid's (ρ_L, c_p,L, λ = H_V − h_L at the sump), ρ_V at P_{N+1}; dT_sat/dP = R T²/(λ P) (Clausius–Clapeyron). Flow areas: A_t = N_t π D_i²/4, A_in, A_r.

#### 8.3.2 Loop model (sub-stepped)

States: circulation W (kg/s), riser quality x_r, oscillator (u, v). Sub-step δ = 0.1 s (5 sub-steps per main step at dt = 0.5 s; 20 at 2.0 s). Within a main step, column conditions (sump T, composition, P, level) are frozen.

```
Static head subcooling at the tube inlet:  ΔT_sub = (dT_sat/dP) ρ_L g z
Mean boiling temperature:                   T_b,mean = T_sump + ΔT_sub / 2
Effective heater flow:                      W_h = max(W (1 + u), 0.3 kg/s)

Heat (3 fixed-point iterations on x_e):
  D(x_e) = 1                                   x_e ≤ x_c
         = max(0.35, 1 − 0.65 (x_e − x_c)/0.35) x_e > x_c          (mist-flow loss of wall wetting)
  U_eff = D(x_e) (1 − f_flooded) / (1/U + R_f,R)          (same fouling and flooding factors as §8.2)
  Q_max = U_eff A (T_st − T_b,mean)
  Q     = min(Q_R,SP , Q_max)
  x_e   = max(0, (Q − W_h c_p,L ΔT_sub) / (W_h λ))                (exit quality)
Sensible fraction of tube length:           f_sc = min(1, W c_p,L ΔT_sub / Q)

Two-phase density with Zivi slip S = (ρ_L/ρ_V)^(1/3):
  α_void(x) = 1 / (1 + ((1 − x)/x)(ρ_V/ρ_L) S)      ρ_tp(x) = α_void ρ_V + (1 − α_void) ρ_L
  boiling-zone mean ρ̄_b = average of ρ_tp(x_e (k + ½)/8), k = 0..7     (8-point midpoint, linear x profile)

Riser transport (first-order lag, implicit):
  M_r = A_r L_r ρ_tp(x_r) ;   x_r ← (M_r x_r + δ W_h x_e) / (M_r + δ W_h)

Driving head:
  ΔP_drive = g [ ρ_L z − ρ_L L_t f_sc − ρ̄_b L_t (1 − f_sc) − ρ_tp(x_r) L_r ]

Friction (homogeneous two-phase multiplier φ² = 1 + ½ x_e (ρ_L/ρ_V − 1) averaged over the boiling zone):
  f_D = 0.316 Re^−0.25,  Re = max(2000, |W| D_i / (A_t μ_L))
  c_in   = (K_in + K_valve) / (2 ρ_L A_in²)
  c_tube = f_D L_t (f_sc + (1 − f_sc) φ²) / (D_i · 2 ρ_L A_t²)
  c_acc  = (v_h(x_e) − 1/ρ_L) / A_t²                   v_h(x) = x/ρ_V + (1 − x)/ρ_L
  c_out  = K_out v_h(x_r) / (2 A_r²)
Momentum (implicit in W, coefficient frozen):
  I = L_in/A_in + L_t/A_t + L_r/A_r
  W ← (W + (δ/I) ΔP_drive) / (1 + (δ/I)(c_in + c_tube + c_acc + c_out) |W|)                   (8.3)
```

#### 8.3.3 Instability index and oscillator

Why not first-principles: thermosyphon surging is mainly density-wave oscillation and flow-pattern intermittency. Resolving density waves needs dozens of axial cells and millisecond steps. In prototyping, a 14-cell implicit loop model (with flashing in the riser and hydrostatic subcooling) was stable everywhere in the operating map; the implicit transport on a coarse mesh damps the delay that drives the instability. LowSYS therefore keeps the loop hydraulics physical (8.3) and adds an explicit, physically indexed instability:

```
Filtered exit quality and loss ratios (a = δ/(τ_F + δ), τ_F = 30 s; W is the value after the momentum update):
  x̄_e   ← x̄_e   + a (x_e − x̄_e)
  r̄_out ← r̄_out + a (c_out W² / (0.5 ρ_L g z) − r̄_out)      (outlet two-phase loss vs half the static head)
  r̄_in  ← r̄_in  + a (c_in W² / (ρ_L g z) − r̄_in)          (inlet single-phase loss vs static head)

Instability index:
  I_s = max( x̄_e / 0.30 , r̄_out ) / (1 + 3 r̄_in)                                                (8.4)
```

Order inside one sub-step: subcooling and T_b,mean → W_h → heat/x_e iterations → f_sc → ρ̄_b → riser update → driving head → friction coefficients → momentum update (8.3) → filters and I_s (8.4) → oscillator (8.5).

The index encodes three practitioner rules (Kister, *Distillation Troubleshooting*, Wiley 2006, reboiler chapters): high vaporisation (above about 25–35 % for hydrocarbons) causes surging; a restrictive outlet line causes surging; adding inlet restriction stabilises the loop (at the cost of circulation). Low sump level acts through all three: lower head → lower circulation → higher x_e.

Oscillator (Stuart–Landau normal form of a Hopf bifurcation), relative modulation u of the heater flow:

```
period T_osc = 2 (M_heater + M_riser) / max(W, 0.3 kg/s)          (twice the transit time; typical of density waves)
   M_heater = A_t L_t (ρ_L f_sc + ρ̄_b (1 − f_sc))      M_riser = M_r
ω = 2π / T_osc          σ = (I_s − 1) / τ_s        τ_s = 20 s
κ = (max(σ, 0) + 1/τ_s) / A_sat²                     A_sat = 0.30
Sub-step update (exact rotation, then growth):
  [u, v] ← rotate([u, v], ω δ) · exp((σ − κ (u² + v²)) δ)
  if √(u² + v²) < 1×10⁻³ : rescale to 1×10⁻³ (deterministic noise floor so growth can start)        (8.5)
```

Below I_s = 1 any oscillation decays with time constant ≈ τ_s / (1 − I_s); above it the amplitude grows over tens of seconds to a limit √(u²+v²) ≈ A_sat √(σ/(σ + 1/τ_s)). Surging therefore *develops over time* and stops when the operator raises the level, throttles the inlet or cuts duty.

#### 8.3.4 Coupling to the column

```
Q_R,delivered(t) = Q · (1 + u)          (averaged over the sub-steps of the main step)
```

The column's sump energy balance (4.7) uses Q_R,delivered, so the boilup, bottom-tray ΔP, sump level and bottom temperature all oscillate. The mean energy is conserved over a cycle. The loop's own vapour generation W x_e is a diagnostic (shown in the Equipment tab), not a second boilup.

Prototype map at the B-T defaults with Q_R,SP = 1300 kW (VALIDATION.md VC-14 gives the fixed-input unit test): sump level 75 % → W ≈ 16.8 kg/s, x_e ≈ 0.17, I_s ≈ 0.50 (stable); 50 % → I_s ≈ 0.74; 30 % → I_s ≈ 1.01 (marginal); 15 % → I_s ≈ 1.28 and a sustained oscillation with relative amplitude ≈ 0.14 (duty swinging about ±290 kW) and period ≈ 8.5 s. Throttling the inlet valve to 16 % open at 15 % level lowers I_s to ≈ 1.07 and the amplitude to ≈ 0.03; raising the level to 50 % removes it. An outlet restriction (K_out = 20) at 75 % level gives I_s ≈ 1.39.

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

## 10. Control system

### 10.1 PID (velocity form)

Each loop executes every main step (dt = 0.5 s). PV and SP are normalised to % of the transmitter span [lo, hi]; OP is % valve.

```
e_k = +(PV%_k − SP%_k)   for direct action (OP rises when PV rises above SP)
e_k = −(PV%_k − SP%_k)   for reverse action
ΔOP_k = Kc [ (e_k − e_{k−1}) + (dt/Ti) e_k − (Td/dt) s (PVf_k − 2 PVf_{k−1} + PVf_{k−2}) ]       (10.1)
OP_k = clamp(OP_{k−1} + ΔOP_k, 0, 100)
```

s = +1 for direct, −1 for reverse action; PVf is the PV filtered with τ = Td/8 (derivative on filtered PV, not on error). Clamping the increment is the anti-windup. Kc is dimensionless (%OP per %span); Ti and Td in seconds (Ti = ∞ disables integral).

Modes: **MAN** (user sets OP), **AUTO** (PID), **CAS** (SP from a master loop's OP mapped onto this loop's span). MAN→AUTO is bumpless: SP is set to the current PV (setpoint tracking) and the velocity form continues from the current OP.

### 10.2 Flow loops

Flow loops are fast relative to the process, so an ideal flow controller is used: in AUTO the flow follows SP (clamped to valve capacity) through a first-order lag τ_FC (3 s; 5 s for duty), updated implicitly. In MAN, flow = characteristic(OP) × F_max (linear characteristic) with actuator lag τ_v = 2 s. This removes the fastest, stiffest loops without changing what the learner sees.

### 10.3 Instruments and valves

```
PV_meas = filter(true value, τ_m) + bias + drift · (t − t_fault) + noise              (10.2)
```

τ_m: flows 1 s, levels 2 s, pressures 1 s, temperatures 10 s (thermowell), analysers 300 s dead time + 60 s lag (composition). Noise: Gaussian, σ = 0.2 % of span, from a seeded xorshift64* generator; off by default except in drills. Valve faults: stuck (position frozen), fail-open, fail-closed.

### 10.4 Default loops

| Tag | PV (span) | MV | Action | Default mode | Kc | Ti (s) | Td (s) | Tier |
|---|---|---|---|---|---|---|---|---|
| FC-101 | feed flow (0–250 kmol/h) | feed valve | ideal FC | AUTO | – | – | – | all |
| FC-102 | reflux flow (0–300 kmol/h) | reflux valve | ideal FC | AUTO (or ratio: SP = R × D) | – | – | – | all |
| FC-103 | boilup (T1, 0–300 kmol/h) / duty (T2/3, 0–3000 kW) | steam valve | ideal FC | AUTO | – | – | – | all |
| LC-101 | drum level (0–100 %) | distillate valve (D_max = 2 × design D) | direct | AUTO | 2.0 | 1800 | 0 | all |
| LC-102 | sump level (0–100 %) | bottoms valve (B_max = 2 × design B) | direct | AUTO | 2.0 | 1800 | 0 | all |
| PC-101 | top pressure (0–2 × P_design) | CW valve (total) / vapour product valve (partial) | direct | AUTO | 2.0 (total) / 1.0 (partial) | 60 / 30 | 0 | T2/3 |
| TC-101 | tray temperature (preset tray; span T_top−10 K to T_bottom+10 K) | FC-103 SP (cascade) | reverse | MAN (disabled) | 1.0 | 900 | 0 | T2/3 |

Crude (M9): TC-201 top temperature → FC reflux (direct, Kc 1.0, Ti 300 s); LC-201 drum → naphtha; LC-202 sump → residue; FC-201..203 side draws; FC-204 PA duty (ideal); TC-202 COT (ideal, τ = 60 s); FC-205..208 steam.

Level loops are tuned for averaging (they absorb flow upsets instead of passing them on), which is the normal practice for drum and sump levels. These are starting values; if a loop check in VALIDATION.md VC-16 fails, the implementer may retune within ±50 % and must record the change in the preset JSON.

### 10.5 Alarms

Each loop has PV HI/LO limits (defaults: levels 85 %/15 %, pressure 1.15/0.85 × SP, flows 110 %/10 % of span); plus model alarms: max flood % > 90, weeping fraction > 0.3, downcomer limited, duty limited, drum or sump < 5 % or > 95 %, relief lifting, thermosyphon I_s > 1, water condensing (crude), draw tray dry (crude), solver fallback. Alarms latch until acknowledged (M3).

---

## 11. Fault models

A fault has a type, a location, a final severity s_f ∈ (0, 1], an onset time t₀ and a ramp time τ_r. Its current severity is

```
s(t) = s_f · clamp( (t − t₀) / τ_r , 0 , 1 )          (τ_r = 0: step)                         (11.1)
```

Faults act only by changing physical parameters or adding physical flows. No fault applies a cosmetic multiplier to a displayed number.

| ID | Location | Parameter changes (applied every step from s(t)) | Default τ_r |
|---|---|---|---|
| F04 Broken / missing tray | tray j | Opening fraction s of the deck: liquid bypass s_broken,j = s added to the bypass fraction f_j (5.14) (the arriving liquid falls through with its inlet composition, like weeping); vapour bypass b_V,j = s in (4.2); hole area A_h,eff = A_h (1 − s) + s · A_a (the opening is a large hole, so ΔP_dry falls); active area A_a,eff = A_a · max(1 − s, 0.02), used for h_cl, the weir relation and M_max | 0 (sudden damage) |
| F05 Fouled / plugged trays | trays j₁…j₂; mode holes / downcomer / both | holes: A_h,eff = A_h (1 − 0.8 s) (valve trays: A_min and A_max × (1 − 0.8 s)); downcomer: h_ap,eff = h_ap (1 − 0.9 s) | 4 h of sim time (represents weeks) |
| F06 Foaming | section or whole column | SF = SF_froth = 1 − 0.45 s; φ_dc = 0.5 − 0.2 s. Antifoam on: after 300 s dead time s decays with τ = 600 s | 600 s |
| F07 Feed composition upset | feed | z ← normalise(z + s Δz), Δz from the fault spec (default: light component +0.15) | 0 or ramp |
| F08 Feed thermal upset | feed | T_F += s ΔT (Tier 2/3, default −40 K) or q += s Δq (Tier 1, default +0.3) | 0 |
| F09 Loss of cooling | condenser | mode flow: m_cw,max × (1 − s); mode temperature: T_cw,in + 15 s K | 0 (pump trip) / 1800 s |
| F10 Condenser fouling | condenser | R_f = s · 1.5/UA_clean (at s = 1, UA_eff = 0.4 UA_clean) | 6 h |
| F11 Non-condensables | overhead | ε_I = 1×10⁻⁴ s (mol inert per mol feed), §7.1 | 0 |
| F12 Reflux pump trip | reflux | L_0 ≤ (1 − s) L_0,max | 0 |
| F13 Reboiler fouling | reboiler | R_f,R = s · 1.5/UA_R,clean | 6 h |
| F14 Condensate backup (failed trap) | reboiler | f_flooded = 0.8 s. "Open trap bypass" action: s → 0 over 300 s | 60 s |
| F15 Steam header pressure loss | steam | P_hdr × (1 − 0.6 s) → lower T_st | 120 s |
| F17 Thermosyphon inlet restriction | loop | K_in += 300 s | 1800 s |
| F18 Thermosyphon outlet restriction | loop | K_out += 40 s | 1800 s |
| F19 Instrument fault | instrument tag | bias: +s · b_span (b_span = ±10 % of span); drift: +s · 10 % of span per hour; stuck: output frozen at its value at t₀ | 0 |
| F20 Valve fault | valve tag | stuck at current position / fail open (100 %) / fail closed (0 %) | 0 |
| F21 Packing maldistribution | packed bed | f = 0.6 s in (6.6) | 0 or 1800 s |
| F23 Packing crushed | packed bed | F_p × (1 + 1.5 s); H_bed × (1 − 0.15 s) (fewer metres of packing, same segment count) | 0 |
| F24 Stripping steam loss | steam injection point | steam × (1 − s) | 60 s |
| F25 Pumparound trip | pumparound | P_PA × (1 − s) (and Q_PA with it) | 0 |
| F26 COT upset | furnace | COT += s ΔT (default −15 K) | 300 s |

F01, F02, F03, F16, F22 and F27 are operating conditions that emerge from the models in §5, §6, §8 and §9. Scenarios provoke them by changing loads. Drill symptom expectations for every injectable fault are tabulated in VALIDATION.md §H.

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
| Flow controllers | 3 s | Ideal FC, implicit lag |
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

L_j(M) is the downflow function of §5.9 for trays (weir capped by L_max, plus the dump drain k_d M; dL/dM = dL_weir/dM when the weir is below the cap, 0 when capped, plus k_d) or (6.4) for packed segments. L_j is monotone non-decreasing in M, so R is monotone and the Newton iteration converges.

Drum and sump totals follow from their flows, each pump limited so that the holdup stays ≥ 0:

```
M̂_0     = M_0^n + dt (N_cond + e_1 − L_0 − D_L)                (Tier 1: N_cond = V_1)
M̂_{N+1} = M_{N+1}^n + dt (L_N + f_N L_{N−1} − V_{N+1} − B)
```

These M̂_j are the denominators of the component step.

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
 2. Inputs: flows from valve positions / ideal FC states (from the end of the previous step); lever changes.
 3. Thermo (from end of previous step, cached): T_j, K̃_ij, y_j, h_j, H_j, ρ, σ, v_L.
 4. Hydraulic coefficients at state n: Bennett α_e, ΔP_j, P_j profile, φ_j, ψ filter update, e_j,
    bypass fractions f_j, L_max,j, k_d, M_max; packing φ_p, ΔP, holdup factor, HETP, E.
 5. Reboiler: kettle Q (8.2) or thermosyphon sub-steps (8.3) → Q_R,delivered.
 6. Vapour profile bottom-up: (4.4) Tier 1 or (4.6)/(4.7) Tiers 2/3; sump-starvation factor.
 7. Side strippers (crude): hydraulic + component step for each stripper chain.
 8. Main hydraulic step (§12.2) → M̂_j, L_j; drum and sump M̂.
 9. Component step (§12.3), two Murphree passes → m_ij^(n+1).
10. Overhead pressure solve (§7.4) → P_top, n_V, n_I, N_cond, Q_C (Tier 2/3).
11. Thermo update at n+1: bubble points (§3.6.1) at P_j, enthalpies, densities, K̃ for the next step, y via (4.2).
12. Controllers: instruments → PV; PID (10.1); ideal FC lags; valve lags → flows for the next step. Alarms.
13. Diagnostics: KPIs, steady-state monitor (every 60 s of sim time), trend buffer (every 5 s), solver health.
14. t ← t + dt.
```

Tier 1 skips 5 (V_B lever instead), 10 and 11 (no T, fixed P), and uses K̃ from (4.4). In ideal-hydraulics mode step 4 computes only α_e and C.

### 12.5 Time step

- Main step dt = 0.5 s at all speeds up to the frame budget. Fixed, so a run is reproducible regardless of the speed it was watched at.
- Fast-forward ("Run to steady state", and speeds ≥ 300× when the user enables "coarse fast-forward" in Settings) uses dt = 2.0 s. Prototype: identical steady states; transients differ by under 1 % in composition.
- Thermosyphon sub-step 0.1 s; pressure solve once per main step.
- Tests use dt = 0.5 s unless stated.

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
- If it still fails: pause the simulation, set `solverHealth.fatal = true` with the stage and quantity that failed, and show "The model could not continue from this state — rewind 60 s?" (the engine keeps a ring buffer of states at 60 s intervals, last 10 min).
- Every fallback is counted in `solverHealth` and shown in a developer overlay (Settings → Developer).

### 12.8 Determinism

The engine uses only IEEE-754 double arithmetic, fixed iteration orders, and its own seeded PRNG (xorshift64*). With the same build on the same platform a run is bit-identical. Across platforms `exp`/`log`/`pow` may differ in the last bit; results then agree to 1×10⁻⁹ relative after 1 h of sim time (VALIDATION.md VC-20).

---

## 13. Initialisation, convergence and structural changes

### 13.1 Cold initialisation (from a configuration only)

1. Every stage gets the feed composition z (crude: also every stripper stage).
2. Flows by CMO from the levers: L_j = L_0 above the feed, L_0 + qF below; V_j from V_B (Tier 1) or V_B = Q_R,SP / (H − h)_sump estimate (Tiers 2/3).
3. Pressure: P_top = SP; P_j from the tray ΔP at these flows (Tier 2/3); n_V from the ideal-gas law.
4. Temperatures: bubble point of z at each P_j.
5. Holdups: trays from Bennett at the estimated L_j and V_j; packed segments from (6.3); drum and sump at 50 % level.
6. Controllers: OPs set to the values that give the estimated flows (bias); integrals zero; filters at their inputs (ψ_j = ψ_eq, L̄_j = L_j).
7. Thermosyphon: run the loop model alone for 600 s with the column frozen.

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

### 13.4 Changing the number of trays, feed tray, internals

- Feed tray change: no rebuild; the feed moves to the new stage at the next step.
- Number of trays N → N': rebuild the stage arrays. For each new tray at fractional height s' = (j' − ½)/N', interpolate liquid composition and h_cl linearly from the old profile at s = s'; drum, sump, controllers, pressure inventory unchanged; the feed tray keeps its fractional position (rounded). Then continue. Allowed while running; the UI pauses for the rebuild frame.
- Tray type or section geometry changes: allowed only while paused; holdups re-initialised from Bennett at current flows.

### 13.5 Switching thermodynamic tier at runtime

The state X is the same in every tier. On a switch:

| From → To | Actions |
|---|---|
| T1 → T2/T3 | Compute bubble points and enthalpies from the current x and P_top (= preset P). Set FC-103 SP (duty) = current V_B × (H − h)_sump so the boilup is continuous. Initialise n_V from P_top. PC-101 SP = P_top. |
| T2/T3 → T1 | Set the boilup lever V_B = current V_{N+1}. Vapour flows become CMO at the next step; the learner sees the vapour profile flatten (the teaching point). |
| T2 ↔ T3 | Only the K model changes; temperatures re-converge in the next bubble-point solve. |

Switching never resets compositions or holdups.

---

## 14. Diagrams and derived diagnostics

### 14.1 McCabe–Thiele (binary)

All series are produced by the engine (`McCabeThieleData`, ENGINE_API.md §7) from a snapshot, so the UI only draws. Axes: x and y of the light component, 0–1.

| Series | Definition | Notes |
|---|---|---|
| Diagonal | y = x | |
| Equilibrium curve | Tier 1: y = αx/(1 + (α − 1)x). Tiers 2/3: bubble-point y*(x) on 101 points (refined near the ends) at P_top, plus a second curve at P_{N+1}; the band between them is shaded | The band shows that a real column does not have one equilibrium curve |
| Local equilibrium points | (x_j, y*_j) for every stage at its own T_j, P_j (hollow circles) | |
| q-line | Through (z, z) with slope q/(q − 1) (vertical at q = 1), from (z, z) to its intersection with the equilibrium curve at the feed-tray pressure. Tiers 2/3 use q from (3.15) | |
| CMO reference operating lines (dashed) | Rectifying: y = (L_0/V_1) x + D x_D / V_1 with the *external* flows (reflux L_0, V_1 = L_0 + D, x_D = drum liquid). Stripping: y = (L̄/V̄) x − B x_B / V̄ with V̄ = V_{N+1}, L̄ = V̄ + B. Drawn from x_D to their intersection and from there to x_B | What a textbook would draw from the product flows |
| Actual operating locus (solid, dots) | Passing-stream points (x_j, y_{j+1}) for j = 0 … N | Tier 1 at steady state: lies exactly on the CMO lines. Tiers 2/3: a curve; the gap to the dashed lines is "what CMO hides" |
| Live staircase | (x_0, x_0) → (x_0, y_1) → (x_1, y_1) → (x_1, y_2) → (x_2, y_2) → … → (x_{N+1}, y_{N+1}) → (x_{N+1}, x_{N+1}). Corner (x_j, y_j) is labelled with the stage number; the feed stage is highlighted | Built from live compositions, so it moves during transients |
| Murphree pseudo-equilibrium | Tier 1: y_pe(x) = y_op(x) + E (y*(x) − y_op(x)) with y_op the CMO lines, on 101 points (dotted). Tiers 2/3: a line through the corners (x_j, y_j) | Corners sit on it at steady state |
| Murphree gap markers | For the selected tray: vertical bars showing (y_j − y_{j+1}) and (y*_j − y_{j+1}); their ratio is E_j | Visual definition of Murphree efficiency |
| Markers | x_F = z, x_D, x_B on the diagonal | |
| Minimum-reflux construction (toggle) | s_min = max over x ∈ [x_q, x_D) of (x_D − y*(x))/(x_D − x) on the equilibrium curve (x_q = q-line intersection); R_min = s_min/(1 − s_min); draw the line from (x_D, x_D) with slope s_min | Handles tangent pinches (ethanol–water) as well as feed pinches |
| Pinch shading | Shade where ≥ 3 consecutive steps advance x by < 0.002 | |
| Transient flag | When the steady-state monitor is false: caption "transient — operating lines are not yet consistent" | |

### 14.2 Multicomponent: key-component pseudo-binary (Hengstebeck)

Hengstebeck, Trans. AIChE 42 (1946) 309. With light key LK and heavy key HK:

```
x'_j = x_LK,j / (x_LK,j + x_HK,j)      y'_j = y_LK,j / (y_LK,j + y_HK,j)
y*'_j = K_LK,j x_LK,j / (K_LK,j x_LK,j + K_HK,j x_HK,j)
```

Plot: diagonal; "equilibrium locus" through (x'_j, y*'_j) sorted by x' (it is a stage-by-stage locus, not a closed-form curve); actual operating locus (x'_j, y'_{j+1}); staircase as in §14.1 with primed values; markers x'_F, x'_D, x'_B; a q-line through (z'_F, z'_F) drawn dashed with the caption "approximate for multicomponent". A banner explains that non-key components distort the pseudo-binary. Next to it: composition profile (all components versus stage), K-value / α profile, T profile.

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

### 14.4 Crude diagrams

TBP curves (feed and each product), D86 curves (naphtha to AGO), 5–95 gap/overlap bars between adjacent products (green = gap, red = overlap), temperature profile with draw and return stages marked, internal reflux (liquid traffic) profile, overflash and product yields (vol % of crude) versus the ideal TBP-cut yields.

### 14.5 Profiles (all systems)

Per stage: T, P, x (all components), L, V, L/V, holdup, ΔP, φ (jet), downcomer flood fraction, weeping fraction, E_eff, HETP (packing). Tier 2/3 vs Tier 1 comparison overlay (ghost line) is available when the learner has just switched tier.

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
| Controller | `eq.pid` (10.1) with the last e, ΔOP, OP |
| McCabe–Thiele elements | operating line equations, q-line, R_min construction (14.1), Fenske/Underwood/Gilliland (14.3) |

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
| DePriester K for hydrocarbons instead of an EOS | §3.4.2 | Textbook standard, fast | Composition dependence of K |
| Crude: no light ends, constant K_W, steam as inert vapour, 2-stage strippers | §9 | Teaching fidelity; captures cut points, gaps, steam stripping, PA heat balance | Offgas, water dew point details, kerosene flash point |
| Ideal flow controllers | §10.2 | Flow loops are seconds; learners care about the process | Flow-loop tuning |

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
