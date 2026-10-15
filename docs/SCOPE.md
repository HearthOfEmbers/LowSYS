# LowSYS — Scope, Screens, Levers, Faults, Scenarios, Themes, Milestones

Status: specification v1.0 (2026-10-12). Owner: physics lead / scope owner.
Companion documents: [PHYSICS.md](PHYSICS.md) (model), [ENGINE_API.md](ENGINE_API.md) (architecture and Dart API), [VALIDATION.md](VALIDATION.md) (tests and reference numbers).

This document is the contract for *what* gets built and *in what order*. PHYSICS.md is the contract for *how the column behaves*. When the two disagree, PHYSICS.md wins for model behaviour and this document wins for scope and UI.

---

## 1. Product summary

LowSYS is a Flutter teaching app that simulates a distillation column dynamically. The learner pulls the levers a chemical engineering problem talks about (feed, reflux, boilup, pressure, trays) and watches three things respond in real time:

1. an animated column (liquid on trays, vapour, levels, flooding, weeping);
2. a live McCabe–Thiele diagram built from the actual tray compositions;
3. instruments: trends, profiles, faceplates, alarms.

Every number on screen can be tapped to show the equation that produced it, with the live numbers substituted.

Targets: Android first; Windows desktop is the development build; iOS and web later (M10). The engine is a pure-Dart package with no Flutter dependency.

### 1.1 Design principles

- **The math is real.** Every displayed quantity comes from a model in PHYSICS.md. There are no cosmetic animations driven by fake numbers.
- **Simplifications are visible.** Tier 1 (textbook), Tier 2 (ideal plus energy balances) and Tier 3 (non-ideal) can be switched at runtime on the same column state, so the learner sees what each simplification hides.
- **Dynamic, not snapshot.** Holdups, hydraulics, pressure and controllers evolve over simulated time. Flooding, weeping and thermosyphon surging build up over time; they do not switch on instantly.
- **Phone-first performance.** A 40-tray, 8-component column must run at 100× real time on a mid-range phone without dropping frames.
- **Deterministic.** The same configuration, seed and lever history give bit-identical results. This makes the engine testable.

### 1.2 Out of scope (v1)

- Column start-up from an empty, cold, dry column (filling, heating, establishing levels). "Cold start" in LowSYS means *initialising a solver from a crude guess*, not physical start-up.
- Three-phase (VLLE) trays, reactive distillation, vacuum crude (VDU), heat-integrated columns, multiple feeds for crude.
- Rigorous equations of state (Peng–Robinson etc.). Tier 3 for hydrocarbons uses DePriester K-values instead (PHYSICS.md §3.4).
- Multi-pass trays, bubble-cap trays, mechanical design.
- Networked or multi-user features.

---

## 2. Feature scope

| Area | In scope | Milestone |
|---|---|---|
| Thermo tiers | T1 constant α + CMO; T2 Raoult (Antoine / DIPPR-101 / Lee–Kesler) + enthalpy balances; T3 NRTL (polar binaries) or DePriester K (light hydrocarbons). Runtime switch. | M1 (T1), M4 (T2), M5/M7 (T3) |
| Systems | Binaries: benzene–toluene, methanol–water, ethanol–water (min-boiling azeotrope), acetone–chloroform (max-boiling azeotrope), isobutane–n-butane (close-boiling C4 splitter). Multicomponent: debutanizer, depropanizer (6 light hydrocarbons). Crude: 9 TBP pseudo-components + steam. | M1, M5, M7, M9 |
| Column internals | Sieve trays, valve trays, random packing, structured packing; mixed sections. | M1 (sieve, weir only), M2 (full tray hydraulics), M8 (packing) |
| Equipment | Total/partial condenser with cooling water; reflux drum; kettle reboiler; thermosyphon reboiler (natural circulation loop); side draws, side strippers, pumparound, stripping steam (crude). | M1, M4, M6, M9 |
| Dynamics | Liquid holdup dynamics on every stage, hydraulic lag, overhead pressure dynamics, controller dynamics, thermosyphon loop dynamics, time acceleration 0–1000×, run-to-steady-state. | M1–M6 |
| Control | PID loops with AUTO/MAN/CAS (real PI flow loops, sub-stepped), valves with characteristics, lag and bypass, instruments with lag, seeded noise, 4–20 mA scaling, quality flags and failure modes, analysers, field gauges, ISA-18.2 alarms, cross-check (Balance) panel, plant view. PHYSICS.md §10, §14.6. | M3 (Tier-2 instruments and checks: M4) |
| Teaching layers | Math overlay (equation trace), guided scenarios, free sandbox, hidden-fault drills. | M2 (overlay), M3 (scenarios), M6 (drills) |
| Diagrams | Live McCabe–Thiele (binary and key-component pseudo-binary), T-x-y, profiles (T, x, L, V, flood, ΔP), trends, FUG panel, crude TBP/D86 and gap chart. | M1, M4, M5, M7, M9 |
| Units | SI and US field units, switchable at runtime. | M2 |
| Themes | Blueprint, Control Room (DCS), Phosphor CRT, Brass Steamworks, Textbook Paper, SPD (Royal Crimson). | M1, M4, M5, M7, M9 |

---

## 3. Screens and navigation

### 3.1 Screen list

| ID | Screen | Purpose |
|---|---|---|
| S0 | Home | Mode hub: **Learn** (guided scenarios), **Sandbox**, **Diagnose** (hidden-fault drills), **Library** (M10), **Settings**. Shows "Continue" for the last session. |
| S1 | Sandbox setup | Pick a preset (grouped: Binary / Multicomponent / Crude), thermo tier, internals template, and start from a cached steady state ("warm") or from a guess ("cold"). An Advanced drawer edits sections, geometry and equipment. |
| S2 | Simulator | The core screen, shared by sandbox, scenarios and drills. Mode-specific HUDs are overlays (S2a–S2c). |
| S2a | Scenario HUD | Objective checklist, timer, Hint button, "Finish" button. |
| S2b | Drill HUD | Elapsed time, "Diagnose" button, alarm counter. No fault information. |
| S2c | Math overlay | Equation trace for the selected tray, stream or equipment item (sheet on phone, floating panel on desktop). |
| S3 | Scenario list | Guided scenarios grouped by topic, with completion state and best score. |
| S4 | Briefing | Scenario or drill text, goals, levers available, "Start". |
| S5 | Debrief | Score breakdown, what happened (event timeline), the key equations, "Retry" / "Next". |
| S6 | Diagnose dialog | Choose fault category, location and, for instrument faults when the drill asks, the failure mode; submit. Opens from S2b. |
| S7 | Settings | Theme picker with live thumbnails, units, graphics quality (High/Low), default speed, haptics, reset progress, about/licences. |
| S8 | Library (M10) | Concept cards (e.g. "Minimum reflux", "Weeping") that link to the scenario that demonstrates them. |

Navigation uses plain `Navigator` routes (no routing package): S0 → S1 → S2; S0 → S3 → S4 → S2(+S2a) → S5; S0 → S3(drills tab) → S4 → S2(+S2b) → S6 → S5. Back from S2 asks "Leave simulation? (state is auto-saved in sandbox)".

### 3.2 Simulator screen (S2) building blocks

| Block | Content |
|---|---|
| **TimeBar** | Sim clock (hh:mm:ss), speed selector (Pause, 1×, 2×, 5×, 10×, 30×, 100×, 300×, 1000×), actual speed achieved (shown amber when the frame budget limits it), "Steady?" indicator (green when the steady-state residual is below tolerance), "Run to steady state" button, tier badge (T1/T2/T3, tap to switch), units toggle. |
| **ColumnView** | Animated column painter (trays or packing, downcomers, liquid, froth, vapour, drum, sump, reboiler/thermosyphon, condenser, flows on pipes, side strippers for crude). Tap a tray or stream to open the math overlay; long-press for a quick-look tooltip. Pinch-zoom and pan on phone. |
| **DiagramPanel** | Tabs: McCabe–Thiele · T-x-y (binaries only, M5; PHYSICS.md §14.4b) · Profiles · Trends · Products (FUG panel or crude TBP/D86) · Equipment (condenser, reboiler / thermosyphon detail). Tabs that do not apply to the preset are hidden. |
| **ControlPanel** | Tabs: Levers (grouped: Feed, Top, Bottom, Column, Advanced) · Faceplates (one per control loop: PV/SP/OP, mode, quality badge, signal look, valve-curve mini plot, field check; M3) · Balance (cross-checks C1–C7 with window selector and the C6 temperature chart; M3) · Faults (sandbox only, M2+). |
| **KpiStrip** | xD, xB (or key-component specs, or crude product specs), D, B, R, Q_C, Q_R, column ΔP, max flood %, active alarms. Each value is tappable (math overlay). |
| **AlarmBanner** | Newest unacknowledged alarm; tap to open the alarm list; "Ack" button (M3). |

### 3.3 Layouts by form factor

Breakpoints use the logical width `w` and height `h` of the window (dp):

| Class | Condition | Layout |
|---|---|---|
| Compact portrait | `w < 600` and `h ≥ w` | TimeBar (48 dp) on top. Middle row: ColumnView (40 % width) beside DiagramPanel (60 %), about 55 % of the height. KpiStrip (one scrollable row). ControlPanel as a draggable bottom sheet (peek 30 %, full 85 %). Math overlay is a modal bottom sheet (70 % height). |
| Compact landscape | `h < 500` and `w > h` | One row: ColumnView (22 %) · DiagramPanel (48 %, TimeBar folded into its header) · ControlPanel (30 %, scrollable). KpiStrip as a thin bar under the DiagramPanel. The math overlay temporarily replaces the ControlPanel (right sheet). |
| Medium | `600 ≤ w < 1000` | Top: TimeBar. Row: ColumnView (30 %) · DiagramPanel (70 %). Bottom: ControlPanel, collapsible (40 % height). |
| Expanded (desktop) | `w ≥ 1000` | Three columns: ColumnView (25 %) · two stacked diagram panels (50 %) · ControlPanel (25 %). Bottom strip (20 % height): trends and alarm list. The math overlay is a floating, draggable panel. |

Touch targets are at least 48 dp. Every slider has −/+ fine buttons and a numeric entry field (tap the value). Desktop keyboard shortcuts: Space pause/resume; `+`/`-` speed; `1`–`6` diagram tabs (in the order shown, counting only visible tabs); `M` math overlay for the selected item; `T` cycle tier; `U` toggle units; `S` run to steady state.

---

## 4. Levers

"Lever" means any user-adjustable input. A lever is either a **direct parameter** (e.g. number of trays) or bound to a **control loop**: in AUTO the lever edits the loop setpoint, in MANUAL it edits the valve output (%). The lever UI shows which (badge "SP" or "OP").

Ranges are hard limits; defaults are for the benzene–toluene (B-T) preset unless stated. US field units are shown in the second unit column. "T1/T2/T3" lists the tiers in which the lever exists.

### 4.1 Simple levers

| Lever | Symbol | Range | Default (B-T) | SI unit | US unit | Tiers | Binding / notes |
|---|---|---|---|---|---|---|---|
| Feed rate | F | 0–250 | 100 | kmol/h | lb-mol/h | all | FC-101 SP (AUTO) or valve % (MAN) |
| Feed composition | z | 0.01–0.99 (binary, light component); per-component editor (normalised) for multicomponent | 0.50 | mol frac | mol frac | all | Applied as a step, or as a ramp over a chosen time (0–3600 s) |
| Feed thermal condition | q | −0.5–1.5 | 1.0 | – | – | T1 | q = liquid fraction of feed (q > 1 subcooled, q < 0 superheated) |
| Feed temperature | T_F | 20 °C to dew point + 60 K | bubble point (92.1 °C at 1 atm) | °C | °F | T2, T3 | Readouts: computed q and vapour fraction. Alternative input mode: vapour fraction 0–1 |
| Feed tray | n_F | 1–N | 10 | – | – | all | Counted from the top |
| Reflux flow | L₀ | 0–300 | 100 | kmol/h | lb-mol/h | all | FC-102 SP |
| Reflux ratio | R | 0.1–20 | 2.0 | – | – | all | Ratio mode: L₀ SP = R × measured D |
| Reflux subcooling | ΔT_sub | 0–30 | 0 | K | °F (Δ) | T2, T3 | Subcooled reflux raises internal reflux |
| Boilup | V_B | 0–300 | 150 | kmol/h | lb-mol/h | T1 | FC-103 SP in T1 |
| Reboiler duty | Q_R | 0–3000 | 1300 | kW | MMBtu/h | T2, T3 | FC-103 SP in T2/T3 (steam flow × latent heat); may be limited by heat transfer |
| Column top pressure | P_top | 0.2–5.0 (B-T, alcohols); 3–25 (light HC); 1.0–2.5 (crude) | 1.013 | bar(a) | psia | T2, T3 | PC-101 SP. In T1 pressure is fixed and only displayed |
| Condenser type | – | total / partial | total | – | – | T2, T3 (partial) | Switch requires pause; partial adds a vapour product |
| Distillate | D | 0–200 | set by LC-101 | kmol/h | lb-mol/h | all | LC-101 OP when LC-101 is in MAN |
| Bottoms | B | 0–200 | set by LC-102 | kmol/h | lb-mol/h | all | LC-102 OP when LC-102 is in MAN |
| Drum level SP | – | 10–90 | 50 | % | % | all | LC-101 SP |
| Sump level SP | – | 10–90 | 50 | % | % | all | LC-102 SP. Sets thermosyphon driving head |
| Number of trays | N | 3–60 (binary), 10–50 (multicomponent); fixed for crude | 20 | – | – | all | Rebuilds the column; state is remapped (PHYSICS.md §13.4) |
| Murphree efficiency | E_MV | 0.05–1.00 | 0.70 | – | – | all | Global value; faults modify individual trays |
| Time acceleration | – | Pause, 1×…1000× | 1× | – | – | all | See TimeBar |

### 4.2 Advanced levers (Advanced group; most from M2 on)

| Lever | Range | Default | SI / US | Tiers | Notes |
|---|---|---|---|---|---|
| Tray type (per section) | sieve / valve | sieve | – | all | Valve trays turn down further before weeping |
| Internals (M8; B-T family only) | 20 sieve trays / structured packing 2 × 4.5 m / mixed (packed top, trays below) | trays (`bt`), packing (`bt_packed`) | – | all | Switch requires pause; rebuilds the stages (PHYSICS.md §13.4) |
| Hydraulic realism | ideal / full | full (M2+), ideal in M1 | – | all | "ideal": holdup dynamics only (no ΔP, entrainment, weeping, downcomer limits). Used by textbook scenarios and tests |
| Cooling-water inlet temperature | 5–45 | 30 | °C / °F | T2, T3 | |
| Cooling-water flow capacity | 50–500 | 150 | m³/h / US gpm | T2, T3 | 100 % of the CW valve |
| Steam header pressure | 1–20 | 3.5 | bar(g) / psig | T2, T3 | Sets steam condensing temperature (148 °C at 3.5 bar(g)) |
| Reboiler type | kettle / thermosyphon | kettle (thermosyphon in scenarios that use it) | – | T2, T3 | Switch requires pause |
| Thermosyphon inlet valve | 5–100 | 100 | % open | T2, T3 | Throttling damps a surging thermosyphon at the cost of circulation; at a very low sump level it is not enough on its own (PHYSICS.md §8.3.4) |
| Antifoam injection | off / on | off | – | all | Counters the foaming fault (with delay) |
| Overhead inert vent | 0–100 | 0 | % open | T2, T3 | Purges non-condensables |
| TC-101 tray-temperature control | enable / disable, tray choice, SP | disabled; tray 14 when enabled | – | T2, T3 | Cascades to the reboiler duty |
| Measurement noise | off / on | **on in the sandbox** (user decision 2026-10-12); off in guided scenarios; on in drills | – | all | Seeded, deterministic (PHYSICS.md §10.5, §12.9). "Run to steady state" suspends it for the run |
| Plant view | off / on | off (on in drills H9, H10) | – | all | Shows only what a real plant measures (PHYSICS.md §10.9) |
| Shed loops on bad PV | on / off | on | – | all | Modern DCS behaviour; off reproduces old systems (PHYSICS.md §10.2) |
| Valve bypass (per control valve) | closed / 0–100 % | closed | % | all | The F20 fix: isolates the control valve and sets the flow by hand |

### 4.3 Multicomponent presets (defaults)

| Lever | Debutanizer | Depropanizer |
|---|---|---|
| Feed | 100 kmol/h; C3 0.05, iC4 0.15, nC4 0.25, iC5 0.20, nC5 0.20, nC6 0.15; saturated liquid | 100 kmol/h; C3 0.30, iC4 0.20, nC4 0.25, iC5 0.10, nC5 0.10, nC6 0.05; saturated liquid |
| Keys | LK n-butane, HK isopentane | LK propane, HK isobutane |
| P_top | 6.895 bar(a) (100 psia) | 17.24 bar(a) (250 psia) |
| Trays / feed tray | 32 / 16 (E = 0.7; the FUG design's 22 / 12 at E = 1, M7 readiness pass) | 28 / 11 (E = 0.7; FUG design 20 / 8 at E = 1) |
| Default tier; duty (T2/T3) | T3 DePriester; 679.7 kW | T3 DePriester; 416.6 kW |
| Reflux | 76.4 kmol/h (R = 1.70) | 66.1 kmol/h (R = 2.15) |
| Boilup (T1) | 121.3 kmol/h | 96.9 kmol/h |
| Design recoveries at the defaults (T3) | n-butane 0.978 to D, isopentane 0.978 to B | propane 0.991 to D, isobutane 0.954 to B |

Utilities, Tier-2 equivalents and the reasons for these numbers: PHYSICS.md §2.3 (M7 rules); reference steady states: VALIDATION.md VC-9.6.

### 4.3b Methanol–water preset `mw` (M4)

Used by G7. From M5 it also runs in Tier 3 (NRTL; VALIDATION.md VC-8.13, VC-28.7).

| Setting | Value |
|---|---|
| Column | 20 sieve trays, B-T geometry (TS 0.9 m), feed tray 12, P_top 1 atm |
| Feed | F = 100 kmol/h, z_MeOH = 0.30, saturated liquid |
| Tier 1 | α = 3.5; L₀ = 60, V_B = 90 kmol/h |
| Tier 2 | L₀ = 60 kmol/h, duty 890.4 kW (D = 30 kmol/h) |
| Utilities | condenser UA_clean 29.76 kW/K, reboiler UA_R,clean 30.65 kW/K |

Reference steady states: VALIDATION.md VC-27.1.

### 4.4 Crude unit levers (M9)

| Lever | Range | Default | SI / US |
|---|---|---|---|
| Crude rate | 33–265 m³/h (5,000–40,000 bbl/d) | 132.5 m³/h (20,000 bbl/d) | m³/h / bbl/d |
| Furnace outlet temperature (COT) | 330–390 | 345 (M9 readiness; v1.0 360 gave 10.9 % overflash) | °C / °F |
| Top pressure | 1.0–2.5 | 1.6 | bar(a) / psia |
| Top temperature SP (TC-201 → reflux) | 90–160 | 125 | °C / °F |
| Kerosene draw | 0–25 % of crude (vol) | 11.7 % | m³/h / bbl/d |
| Diesel draw | 0–30 % | 16.7 % | m³/h / bbl/d |
| AGO draw | 0–15 % | 5.3 % | m³/h / bbl/d |
| Pumparound duty | 0–10 (v1.0 0–15; the kero tray runs dry above ≈ 7.5 MW, the cooler limits at ≈ 10.9 MW) | 5.0 (M9 readiness; v1.0 6.0) | MW / MMBtu/h |
| Bottom stripping steam | 0–5000 | 2000 | kg/h / lb/h |
| Side-stripper steam (each) | 0–1000 | 300 | kg/h / lb/h |
| Overhead drum temperature (via CW) | 30–60 | 45 | °C / °F |

M9 readiness notes:
- **Draw levers.** The three draw levers set **product** rates: the stripper bottoms, m³/h at 15.6 °C, on FC-311/312/313. The draw from the column follows the stripper level (PHYSICS.md §9.4), so the defaults equal the ideal yields of VALIDATION.md VC-15.3.
- **Not offered for crude.** The column is 30 theoretical stages; `murphree`, `nTrays` and `feedStage` are not offered.
- **Default steady state** (PHYSICS.md §9.8): naphtha 19.75 / kero 11.70 / diesel 16.70 / AGO 5.30 / residue 46.55 vol %; overflash 4.6 %; gaps K–N +0.9, D–K −9.0, A–D −9.7 K; Q_C 8.95 MW.

---

## 5. Fault catalog

Each fault has a physical model (PHYSICS.md §11 gives the equations), a severity parameter `s ∈ [0, 1]`, an onset time and a ramp time. Symptoms are the observable signatures a learner should use to diagnose it. "Fix" lists what an operator can do in the sim.

| ID | Fault | Physical model (summary) | Observable symptoms | Fix in the sim | M |
|---|---|---|---|---|---|
| F01 | Jet / entrainment flooding (operating condition) | Vapour velocity exceeds the Fair flood limit; entrainment ψ rises steeply towards 0.6, so liquid is sprayed up and recycled tray to tray and into the overhead. The froth fill stays near 0.35: trays do *not* fill to the spacing (that is F02 / full-tray overflow) | ΔP rises sharply and becomes erratic; xD falls (heavy component overhead); drum level rises, sump level falls; T profile flattens in the flooded zone | Cut boilup and reflux; cut feed | M2 |
| F02 | Downcomer-backup flooding | Downcomer liquid head (tray ΔP + receiving-tray head + apron loss) exceeds tray spacing; downflow is capped; liquid accumulates upward from the restriction | ΔP jumps across the section *above* the restriction; liquid inventory grows there; sump level drops; separation collapses | Cut liquid and vapour load | M2 |
| F03 | Weeping / dumping (operating condition) | Tray stability factor Φ = √(h_dry/h_cl) below 0.75 makes inlet liquid bypass the tray; below 0.2 the tray dumps: it drains through its holes like an orifice (PHYSICS.md (5.15), revised for M3) | Low ΔP; efficiency loss (xB and xD both worse at the same L/V); dumping trays hold almost no liquid (sieve ≈ 0.15 mm, valve ≈ 1.5 mm of clear liquid), drawn as liquid raining through an empty deck | Raise boilup; switch to valve trays (design) | M2 |
| F04 | Broken or missing tray | Fraction `s` of the tray deck is open: liquid bypass fraction `s` straight to the tray below, vapour bypass fraction `s` uncontacted; ΔP of that tray falls | Lower ΔP across the damaged tray; flatter T and composition profile at that location; lower separation; staircase shows a "missing step" | None in operation (needs shutdown); reduce rates to limit damage | M2 |
| F05 | Fouled / plugged trays | Mode holes / downcomer / both. Holes: open hole area × (1 − 0.8 s) (valve trays: A_min and A_max × (1 − 0.8 s)); downcomer: apron clearance h_ap × (1 − 0.9 s), so s = 1 is 90 % blocked; ramp 4 h of sim time (weeks of plant time compressed) | Gradual ΔP rise in the fouled section at constant rates; earlier flooding (downcomer backup) at a lower throughput; little separation change until flooding | Reduce throughput | M2 |
| F06 | Foaming | System (foam) factor SF = 1 − 0.45 s on flood capacity; froth density α_e × SF_froth (SF_froth = SF); downcomer aeration φ_dc = 0.5 − 0.2 s; ramp 600 s. Antifoam on: after a 300 s dead time s decays with τ = 600 s | Flooding at normal load (max flood % up, xD down, carryover into the drum) while the column ΔP barely changes; with the default headroom it floods only for s ≳ 0.8. Recovery starts 5 min after antifoam and is mostly complete within 20–40 min | Antifoam on; cut rates | M2 |
| F07 | Feed composition upset | z ← z + s Δz with Σ Δz = 0 (for a binary the other component gets −Δz), step or ramp; default Δz = +0.15 light, so B-T z = 0.50 → 0.65 (PHYSICS.md §11) | Profile moves up/down the column; temperatures shift (T2/3); product specs drift; drum/sump levels shift | Re-target reflux/boilup | M2 |
| F08 | Feed temperature / vaporisation upset | Preheater change, step: T_F += s ΔT (Tiers 2/3, default −40 K) or q += s Δq (Tier 1, default +0.3) | V and L change below the feed; stripping section loads change; ΔP shift below feed | Adjust duty | M4 |
| F09 | Loss of condenser cooling | Mode flow: CW flow capacity × (1 − s) (pump trip at s = 1, step); mode temperature: CW inlet T + 15 s K (ramp 1800 s) | Pressure rises; PC output saturates at 100 %; all temperatures rise; separation degrades (α falls); drum level falls; relief valve lifts at its set pressure (preset; B-T 3.5 bar(a)) | Cut reboiler duty | M4 |
| F10 | Condenser fouling | UA × 1/(1 + UA R_f) with R_f = s · 1.5/UA_clean (UA_eff = 0.4 UA_clean at s = 1); s ramps over 6 h | Slow pressure creep; PC output creeping up; subcooling falls | Cut duty; clean (not in sim) | M4 |
| F11 | Non-condensables in overhead | Inert inventory accumulates (feed carries 1×10⁻⁴·s mol inert per mol); blankets condenser area: UA × (1 − blanket fraction) | CW valve opens while PC-101 holds P, saturates (≈ 17 min at s = 1), then pressure rises slowly; condensate subcooling *rises* (blanketed tubes subcool); venting restores | Open inert vent | M4 |
| F12 | Loss of reflux (pump trip) | Reflux flow → 0 (or capped by `1 − s`) | Top temperature spikes; xD collapses; drum level rises fast; top trays dry out (holdup → 0) | Restore pump (fault clears); cut duty | M4 |
| F13 | Reboiler fouling | UA_R × 1/(1 + UA_R R_f) with R_f = s · 1.5/UA_R,clean; s ramps over 6 h | Steam valve holds its position while the exchanger has spare capacity, then saturates within minutes (a real valve creeps open as the chest pressure rises; not modelled, PHYSICS.md §8.2); duty falls below SP; bottoms off-spec; ΔP falls (less vapour) | Raise steam pressure; cut feed | M4 |
| F14 | Reboiler condensate backup (failed steam trap) | Fraction 0.8 s of tube area flooded with condensate (no condensing); ramp 60 s | Sudden duty limitation with the steam valve wide open; steam flow falls; unlike fouling, the onset is fast | Open trap bypass (s ramps back to 0 over 300 s) | M4 |
| F15 | Steam header pressure loss | Header pressure × (1 − 0.6 s) → lower steam temperature | Duty below SP with the steam valve at 100 % (`FC-103.OPSAT`); T_B unchanged at first, then bottoms purity drops | Cut feed | M4 |
| F16 | Thermosyphon instability (operating condition) | Instability index I_s > 1 grows a limit-cycle oscillation of loop circulation (PHYSICS.md §8.3) | Boilup, tray and column ΔP and bottom T oscillate (period 5–20 s); the sump level moves only slightly, and the steam flow (FT-103) shows the mean duty only (PHYSICS.md §8.3.4); duty falls if exit quality > 0.30 | Raise sump level (the reliable fix); throttle inlet valve (damps, costs circulation; at a very low level it costs duty too); cut duty | M6 |
| F17 | Thermosyphon inlet restriction | Inlet loss coefficient K_in + 300 s | Lower circulation; higher exit quality; inlet-line ΔP up; no surging (inlet friction stabilises); duty may fall at s ≥ 0.5 | Clear restriction | M6 |
| F18 | Thermosyphon outlet restriction | Outlet loss coefficient K_out + 40 s | Lower circulation; outlet-line ΔP up; surging (raises I_s strongly); duty falls | Throttle inlet (stabilise); cut duty | M6 |
| F19 | Instrument bias / drift / stuck | Additive in % of span: bias s·10 %, drift s·10 % per hour, or output frozen (no noise). PHYSICS.md §10.6 | Controller holds the wrong value; mass/energy balance mismatch; cross-checks disagree (e.g. level vs flows) | Switch loop to MAN; use redundant instrument | M3 |
| F20 | Control valve stuck / failed | Valve position frozen, or failed open/closed (actuator lag still applies). PHYSICS.md §10.3, §10.6 | Controller output moves but flow does not | Switch to bypass (manual flow) | M3 |
| F28 | Transmitter hard failure | Signal loss (NAMUR failure current 3.6 / 21.0 mA → BAD, reads −2.5 % / 106.25 % of span; a loop sheds to MAN or, without shedding, drives its valve to a limit), plugged impulse line (extra lag 10^(4s) − 1 s: the reading stops following the process and keeps only the small electronic noise, "too steady"), spiking (Poisson spikes of 10–50 % of span), coated thermowell (TI lag × (1 + 9 s)). PHYSICS.md §10.6 | Loop on that PV drives its valve to a limit or goes sluggish; reading disagrees with neighbours (adjacent tray TIs, mass balance, valve OP vs flow); plugged lines look "too steady" | Put loop in MAN; use redundant/inferred measurement; flag instrument for maintenance (clears) | M3 |
| F21 | Packing maldistribution (distributor plugged) | Parallel-column model with liquid split fraction f = 0.6 s (PHYSICS.md §6.6) | Fewer effective stages; T profile in the bed distorts; ΔP almost unchanged | None (needs shutdown); raise reflux | M8 |
| F22 | Packing flooding (operating condition) | Robbins ΔP reaches the Kister–Gill flood ΔP; holdup rises steeply; HETP rises | Steep ΔP rise across the bed; HETP and separation worsen; liquid carryover | Cut rates | M8 |
| F23 | Packing crushed / compacted | Packing factor F_p × (1 + 1.5 s), area unchanged, bed height H_bed × (1 − 0.15 s) (same segment count) | Higher ΔP at the same load; earlier flooding | Cut rates | M8 |
| F24 | Stripping steam loss (crude) | Steam delivered × (1 − s) at one injection point (bottom or a stripper); its FC saturates | Bottom steam: residue yield up (+0.9 vol % at s = 0.85, +3.4 at s = 1), stage-30 T **up** 8–15 K, flash-zone T up ≈ 1.7 K, Q_C down 18–28 %, diesel and AGO heavier; at s = 1 the AGO tray runs dry. Stripper steam: that product's front end gets lighter (SS2 at s = 1: diesel D86 5 % 229 → 189 °C) | Restore steam | M9 |
| F25 | Pumparound circulation loss (crude) | PA circulation × (1 − s) (trip at s = 1, step); the duty follows while the cooler can still reach it (s ≤ 0.5 is invisible except for the PA return T) | Heat removal shifts to the overhead: top T up 4.6–13 K until TC-301 raises the reflux (× 1.7–2.1), Q_C up 14–53 %, top flood up; the diesel runs heavy for the first ≈ 10 min, then *lighter* at steady state (more internal reflux) | Cut the crude rate or restore the pump | M9 |
| F26 | Furnace outlet temperature upset (crude) | True COT = TC-320 SP + s ΔT (default ΔT = −15 K), ramp 300 s; TI-320 keeps reading the SP | Flash-zone and stage-30 T both **down** 7.5–14 K, overflash to ≈ 0, Q_C down 6–9 %, AGO heavier; at s = 1 the AGO tray runs just dry | Re-target COT (raise the SP by \|s ΔT\|) | M9 |
| F27 | Draw tray dry (crude; operating condition) | A draw takes more than the internal liquid; the stripper level falls and its product FC saturates | The lowest draw dries first when the lift is short (AGO above a kero draw of ≈ 15.5 %, with F24 s = 1 or F26 s = 1). The kero tray dries when the PA takes too much heat (≥ ≈ 7.5 MW): the kero product falls and the diesel's front end gets lighter (D86 5 % 229 → 202 °C at 8 MW) | Reduce the draw rate or the PA duty | M9 |

The hidden-fault drill pool uses F04, F05, F06, F07, F09, F10, F11, F12, F13, F14, F15, F17, F18, F19, F20, F21, F23, F24, F25, F26, F28. The M8 pass added F12 (H6), F15 (H4), F23 (H7) and F26 (H8), which the drill table of §6.2 already used. H7 also uses the operating condition F22, through its planning event.

---

## 6. Scenarios

Scenarios are JSON data (ENGINE_API.md §11). Each has a briefing, objectives (structured predicates on KPIs), hints, timed events, scoring and a debrief.

### 6.1 Guided scenarios (16)

| ID | Title | System / tier | What the learner does | Objective (summary) | M |
|---|---|---|---|---|---|
| G1 | Meet the column | B-T, T1, ideal hydraulics, E = 1 | Watch the column reach steady state; tap trays; read the staircase | Reach steady state; identify the feed tray on the McCabe–Thiele diagram (tap it) | M3 |
| G2 | Minimum reflux | B-T, T1, ideal, 60 trays, E = 1, feed q = 1 | Lower R at fixed D until xD = 0.95 can no longer be held; find R_min | Report R_min within ±5 % of 1.10 (textbook); see the pinch at the q-line | M3 |
| G3 | Total reflux and Fenske | B-T, T1, ideal, 6 equilibrium stages (5 trays + reboiler) | Set F = D = B = 0; compare stages with Fenske | Read xD, xB; compute N_min = ln[S]/ln α; matches 6 within 0.05 | M3 |
| G4 | The q-line | B-T, T1 | Change q from 1.2 to 0 | Hold xD ≥ 0.95, xB ≤ 0.05 at each q with the least boilup; observe the q-line pivot around (z, z) | M3 |
| G5 | Where to feed | B-T, T1, E = 0.7 | Move the feed tray from 4 to 16 | Find the feed tray that maximises xD at fixed L, V (answer: tray 11) | M3 |
| G6 | Real trays (Murphree) | B-T, T1 | Lower E_MV from 1 to 0.5; add trays to recover | Restore xD ≥ 0.98 with E = 0.5 by adding trays; compare with the Lewis relation | M3 |
| G7 | What CMO hides | B-T then methanol–water, switch T1 ↔ T2 | Compare V and L profiles and operating curves in T1 vs T2 | Explain why V_B < V_top in T2 (answer chosen from options); see the curved operating locus | M4 |
| G8 | Pressure and volatility | B-T, T2, steam header 10 bar(g), CW 15 °C (VALIDATION.md VC-27.3) | Take P_top from 1 atm down to 0.7 bar, then up to 3 bar | Observe α fall (2.60 → 2.20 at x = 0.5) and, for the same purity, reflux and duty rise; hold the 1-atm specs at 2 bar | M4 |
| G9 | The azeotrope wall | Ethanol–water, T3, then T1, then T3 at 0.5 bar(a) | Raise R at fixed duty (cut D) and watch x_D stall; switch to Tier 1; go to 0.5 bar(a), turning the feed down to 60 % so the condenser keeps up | Discover the azeotrope at about 0.896 / 78.1 °C; see Tier 1 "beat" it falsely; at 0.5 bar(a) pass 0.8956 (x_D ≥ 0.897), because lower pressure moves the azeotrope (to 0.911) | M5 |
| G10 | The other azeotrope | Acetone–chloroform, T3 | Draw more distillate at fixed duty and see where the azeotrope ends up; read it off the T-x-y tab | Identify that the maximum-boiling azeotrope leaves in the bottoms (x_B 0.378 approaches it from above), and read x_az = 0.333 ± 0.02 off the T-x-y diagram | M5 |
| G11 | Flooding | B-T, T1, full hydraulics | Push throughput up 10 % per step | The default column runs at 63 % of flood and floods at about 160 % throughput. Find the onset (ΔP slope change, xD collapse); back off to 80–92 % flood (≈ 130–140 %) with xD ≥ 0.95 | M2 (stays Tier 1, decided 2026-10-13) |
| G12 | Turndown and weeping | B-T, sieve then valve trays | Cut throughput to 35 % | See weeping cost separation on sieve trays and not (yet) on valve trays | M2 |
| G13 | Debutanizer keys and FUG | Debutanizer, T3 at the sandbox defaults (32 trays, E = 0.7) | Compare the FUG panel to the rigorous column; raise reflux and duty together | Meet 98 % LK/HK recoveries (R ≈ 1.73); read N_min and R_min off the FUG panel; compare Gilliland's N with 32 × 0.7 + 1 (ENGINE_API.md §11.8) | M7 |
| G14 | Thermosyphon tuning | B-T, T2, thermosyphon | Restore stable boilup after a low sump level causes surging. Start: sump held at 15 % with the inlet valve pinched to 8 % (stable, duty-limited); at t = 0 the inlet is opened fully and the loop starts to surge | Stop the oscillation (amplitude < 2 % of boilup, I_s < 1) without losing more than 10 % duty (≥ 1170 kW of the 1300 kW SP); then explain why throttling helps. Throttling alone cannot do it at 15 % level (ENGINE_API.md §11.8) | M6 |
| G15 | Packing retrofit | B-T, **T1**, full hydraulics (M8 readiness: v1.0 said T2, but G15's tray numbers are VC-12.3's Tier-1 values, and in Tier 2 the B-T condenser cannot follow load changes, as for G11) | Compare 20 sieve trays to 9 m of structured packing (lever `internals`) | Report the ΔP ratio (≈ 10) and the capacity gain at equal flood % (≈ 6 %: the lower bed's liquid load is the limit). See why x_D rises (18 theoretical stages against ≈ 14) (ENGINE_API.md §11.8) | M8 |
| G16 | Crude cut points and gaps | Crude, T2 at the defaults (COT 345 °C, PA 5 MW: kero D86 95 % 238 °C, D–K gap −9 K) | Set draws, PA and stripping steam to meet kero D86 95 % ≤ 235 °C and a diesel–kero gap ≥ 0 K | Meet both specs with the residue TBP 5 % ≥ 355 °C (M9: replaces v1.0's undefined "residue D86-equivalent IBP ≥ 340 °C"; residues have no D86). See that draws move cut points while internal reflux and stripping steam open gaps (PA 3 MW alone: 231 °C and +6.5 K; ENGINE_API.md §11.8) | M9 |

Objective predicates, hints and reference numbers for G1–G16: ENGINE_API.md §11.8.

### 6.2 Hidden-fault drills (10)

In a drill the engine injects one fault (from the drill's candidate list, chosen by a seeded random draw) at a random onset time inside a window. Measurement noise is on. The learner may move levers and switch loops. The learner presses **Diagnose** and picks a category, a location and optionally a severity class.

| ID | Drill | System | Candidate faults (one is chosen) | Key evidence the learner should find |
|---|---|---|---|---|
| H1 | Creeping ΔP | B-T, T2, plant view with calculations | F05 fouling (stripping trays 12–18, or rectifying trays 2–8) vs F07 lighter feed | ΔP rise at constant rates in one section → fouling; profile shift without ΔP change → feed |
| H2 | Pressure won't hold | B-T, T2 | F09 CW loss (partial), F10 condenser fouling, F11 non-condensables | Subcooling trend separates inerts (rises) from fouling/CW loss (falls); CW temperature/flow readings |
| H3 | Lost separation | B-T, T2, plant view with calculations | F04 broken tray (rectifying), F06 foaming (s 0.8–1.0), F19 reflux flow meter bias | One tray's ΔP near zero (broken tray) vs flood % high at normal load with unchanged column ΔP (foam) vs balance mismatch (meter bias: L + D ≠ V₁ from heat balance) |
| H4 | Reboiler can't keep up | B-T, T2 | F13 fouling, F14 condensate backup, F15 steam header loss | Onset speed; steam flow vs valve position; header pressure reading |
| H5 | Bottoms level swings | B-T, T2, thermosyphon, plant view with calculations | F19 sump level transmitter drift (true level low → surge), F17 inlet restriction, F18 outlet restriction | Thermosyphon circulation and exit quality; inlet vs outlet line ΔP; compare level with mass balance and the LG-102 sight glass |
| H6 | Off-spec overhead | Debutanizer, T3, ideal hydraulics, plant view with calculations; planning raises feed, reflux and duty by 8 % at 45 min | F07 feed heavier in the keys (less C3/iC4, more nC4/iC5), F12 reflux pump capacity loss, F20 reflux valve FV-102 stuck | Feed analyser AT-100 (light cut) moves vs reflux flow below SP with FC-102 at 100 % from the onset vs FC-102 OP running away after the planning event while the flow stays flat (C4). Full JSON: ENGINE_API.md §11.10 |
| H7 | Packed bed underperforms | B-T packed (two 4.5 m struct250 beds in a 1.0 m shell), T2, plant view with calculations, CW at 15 °C; planning raises feed, reflux and duty by 25 % at 45 min | F21 maldistribution (upper or lower bed), F23 crushed packing (upper or lower bed), F22 near-flood operation (no fault: the planning event takes the healthy lower bed to 97 % of flood) | What changed **before** the rates rose? Bed ΔP (PDT-102/103) at constant load: crushed → up 45–110 %; maldistribution → flat while that bed's T profile flattens and the product drifts; flooding → nothing, then ΔP 1.8× for 1.25× load. Full JSON: ENGINE_API.md §11.11 |
| H8 | Crude product drift | Crude, T2, plantCalc, lab D86 every 30 min | F24 bottom stripping steam loss (s 0.7–1), F25 pumparound circulation loss (s 0.7–1), F26 COT low (s 0.6–1, TI-320 reads the SP). Full JSON: ENGINE_API.md §11.12 | Stage-30 T up (steam) vs down together with the flash zone (COT); Q_C and top T up (PA) vs Q_C down (steam, COT); FC-321 or FC-314 saturated |
| H9 | Don't trust the gauge | B-T, **T2** (T1 has no temperatures or pressure), full hydraulics, plant view, all loops in AUTO with the TC-101 cascade, no bad-PV shedding | One draw from 13: twelve instrument faults on FT-101/102/103/104, LT-101/102, PT-101, TI-107, TI-114 (F19 bias/drift/stuck, F28 signal loss/plugged/spiking/coated), or, about 1 in 8, a **real** feed change with every instrument healthy (decoy). Full JSON: ENGINE_API.md §11.6 | Decide *process problem vs instrument problem* and name the tag: cross-check neighbouring TIs, material and energy balance, valve OP vs measured flow, "too steady" trends. Bonus for putting the affected loop in MAN before product goes off-spec. |
| H10 | Bad valve or bad meter? | B-T, T2, plant view | F20 FV-102/FV-103 stuck vs F19/F28 (bias, drift, plugged) on FT-102/FT-103 vs a real upset (F07). Full JSON: ENGINE_API.md §11.7 | OP moving while flow is flat (valve) vs flow reading disagreeing with the heat/mass balance (meter) vs everything consistent (real upset) |

Scoring (exact formulas: ENGINE_API.md §11.4).

- **Guided:** objectives 60 %, time 20 % (full marks up to the scenario's par time), safety 10 % (no relief lift, no true level < 5 % or > 95 % for more than 60 s), product quality 10 % (share of time on spec).
- **Drills:** correct category 50 %, correct location 20 %, time to diagnosis 20 % (full within 10 min of the fault, zero after 60 min), safety 10 %. Wrong diagnoses cost 10 % each (two attempts).
- **Bonuses** (H9, H10): +10 % for putting the affected loop in MAN, or breaking the cascade, before the product goes off-spec. H9 also gives +5 % for naming the failure mode.
- Drill hints cost 3 % each. The total is capped at 100 %.

Drills must be winnable on a phone with noise on. Every instrument and valve candidate's evidence must clear the signal-to-noise rules of ENGINE_API.md §11.5, which VALIDATION.md §H tests with noise on; process candidates are checked by the key-evidence rows of VALIDATION.md §H.

**Views in drills (M6).** A drill must not show the learner the truth that its candidates hide. H9 and H10 use plant view. H1, H3, H5 and H6 (M7) contain instrument or feed candidates, so they use *plant view with engineering calculations*: readings everywhere, plus the computed tray hydraulics (ΔP per tray, flood %) and thermosyphon figures (circulation, exit quality, I_s) that an online rating model gives a plant engineer (PHYSICS.md §10.9). H2 and H4 use model view, with fault parameters (UA, fouling resistance, inert inventory, loss coefficients) hidden. Full drill definitions for H1–H5: ENGINE_API.md §11.9; H6: §11.10.

---

## 7. Themes

Themes are pure data (`LowsysTheme`, ENGINE_API.md §13.4) plus a small set of painter style switches. Every theme provides every token. No theme has its own widgets or layout.

### 7.1 Token set (all themes)

Colour tokens: `bg`, `bgAlt`, `surface`, `surfaceAlt`, `ink`, `inkMuted`, `inkFaint`, `grid`, `gridMajor`, `accent`, `accent2`, `steel` (vessel outline), `liquidLight`, `liquidHeavy` (composition gradient ends), `froth`, `vapor`, `hot`, `cold`, `ok`, `warn`, `alarm`, `info`, `selection`, `eqCurve`, `opLine`, `opLineCmo`, `qLine`, `stepLine`, `diagonal`, `pseudoEq`, `marker`, and six series colours `series1`…`series6` (trends, profiles with several components, pinned variables). The series colours were added for the M3 Trends tab; if M3 already shipped its own colours, it moves them into these tokens. A theme without colour freedom (Phosphor) varies dash pattern and intensity instead. From M7 the set includes `seriesDash1`…`seriesDash6`: a dash pattern in logical px, or solid. Blueprint, Control Room and Paper set all six to solid. The component profile chart draws component i with series ((i mod 6) + 1); a seventh or later component also gets point markers. Every theme fills every token; a missing token is a build-time error, not a fallback.

Typography tokens: `display`, `label`, `number` (tabular figures), `math` (font family, weight, letter spacing).

Style switches (enums): `vesselStyle` {outline, flat, bevel, vector}, `liquidStyle` {hatch, gradient, glyph, amber}, `vaporStyle` {circles, glowDots, glyphs, puffs, dots}, `gaugeStyle` {numeric, bargraph, dial}, `lineStyle` {pen, glow, vector, ink}, plus effect flags: `blueprintGrid`, `paperGrain`, `scanlines`, `bloom`, `vignette`, `rivets`, `needlePhysics`, `figureCaptions`, `alarmBlink`.

### 7.2 The six themes

**ok colours (M10, ruled 2026-10-13).** The `ok` colours of Blueprint, Control Room and Paper were changed so that they pass VALIDATION.md U3 (colour-blind safety). Their L* differences under deuteranopia were 12.1, 6.8 and 3.8 and are now 16.7, 17.3 and 20.0, and every U2 ratio still passes. Brass passes unchanged. Phosphor is exempt because its alarm is inverse video with a text label. Blueprint's fifth series colour stays `#7CE0A3`. The values below are the ones in `app/lib/theme/themes/`.

**T-1 Blueprint — "Drafting Table"** (ships in M1)
- Palette (tokens the v1.0 list missed, added for completeness: surfaceAlt `#164F8A`, info `#9BE7FF`, selection `#FFD166`, marker `#FFFFFF`, series `#FFD166` `#9BE7FF` `#FF9F6E` `#EAF4FF` `#7CE0A3` `#C3A6FF`; if M1 shipped other values for these, keep them): bg `#0E3A66`, bgAlt `#0B2F54`, surface `#12457A`, ink `#EAF4FF`, inkMuted `#A9C8E8`, inkFaint `#6F95BD`, grid `#2F6B9E`, gridMajor `#4C87BA`, accent `#FFD166` (yellow pencil), accent2 `#FF9F6E`, steel `#EAF4FF`, liquidLight `#9BE7FF`, liquidHeavy `#3FA7D6`, froth `#CFF3FF`, vapor `#FFFFFF` at 55 %, hot `#FF9F6E`, cold `#9BE7FF`, ok `#9DE8BA` (M10, was `#7CE0A3`; U3), warn `#FFD166`, alarm `#FF6B6B`, eqCurve `#EAF4FF`, opLine `#FFD166`, opLineCmo `#FFD166` dashed, qLine `#FF9F6E`, stepLine `#9BE7FF`, diagonal `#6F95BD`, pseudoEq `#A9C8E8` dotted.
- Typography: labels "Architects Daughter"; numbers "Share Tech Mono"; math "STIX Two Math".
- Column: line-art cross-section; trays as double lines; weirs and downcomers drawn; liquid as 45° hatching whose density follows holdup and whose colour lerps light→heavy with composition; vapour as small outlined circles rising at a speed proportional to the hole velocity. Dimension lines show tray spacing and diameter; leader callouts label feed, draws and instruments.
- Charts: hand-ruled grid with major/minor lines; dashed CMO operating lines; arrowheads on staircase segments; a "title block" in the lower-right corner of the McCabe–Thiele panel (system, tier, sim time, P).
- Signature effects: cached blueprint grid and paper grain (one tiled image); pencil-yellow highlight on the selected tray. Cost: static layers in a `RepaintBoundary`.

**T-2 Control Room — "DCS Night Shift"** (M4)
- Palette: bg `#0B0F14`, bgAlt `#0F151C`, surface `#121A22`, surfaceAlt `#18222C`, ink `#CFE3F1`, inkMuted `#7F93A3`, inkFaint `#3C4A57`, grid `#1C2733`, gridMajor `#263442`, accent `#31C4F3`, accent2 `#9B7BFF`, steel `#8A99A6`, liquidLight `#2BD9FE`, liquidHeavy `#1E6FD9`, froth `#7FE9FF`, vapor `#B4F1FF`, hot `#FF8A3D`, cold `#31C4F3`, ok `#217E38` (M10, was `#34C759`; U3), warn `#FFCC00`, alarm `#FF3B30`, eqCurve `#CFE3F1`, opLine `#31C4F3`, opLineCmo `#31C4F3` dashed, qLine `#FF8A3D`, stepLine `#2BD9FE`, diagonal `#3C4A57`, pseudoEq `#7F93A3`.
- Typography: "Rajdhani" (labels), "JetBrains Mono" (numbers).
- Remaining tokens: info `#5AC8FA`, selection `#31C4F3` (drawn at 30 % alpha for fills), marker `#FFFFFF`; series `#31C4F3` `#E6E6E6` `#9B7BFF` `#FF8A3D` `#7FD4A8` `#F2C14E`. Red and pure yellow are reserved for alarms and are never series colours.
- **ISA-101 rules** (the theme's point: colour means something is wrong):
  - Vessels, pipes and normal values are grey (steel, inkMuted). Live values are ink, never coloured, and do not glow.
  - Accent cyan is used only for what the operator can change (SP and OP handles, the selected item) and for trend PVs.
  - Liquid is drawn in grey-blue tones (liquidHeavy at 40 % saturation); composition shading is a Settings option, off by default.
  - Tag bubbles (FIC-101 …) sit next to instruments. Levels are vertical bar graphs with an SP marker and HI/LO ticks.
- **Alarms** (PHYSICS.md §10.8), colour plus shape plus text:
  - High: alarm red ◆; Medium: warn yellow ▲; Low: info blue ■.
  - UNACK: the symbol and the value box blink at 1 Hz (alternating fill and outline). ACKED: steady fill. RTN-UNACK: outline only, blinking.
  - The banner uses the same symbol; the alarm list shows priority symbol, tag, message, time and state.
- **Signal quality** on values, faceplates and trends:
  - BAD: violet accent2 `#9B7BFF` "BAD" badge with IOP−/IOP+, digits in inkMuted; the trend segment is dashed inkMuted.
  - UNCERTAIN: dashed warn outline plus "OOR▲/▼".
  - OOS: inkFaint digits plus "OOS".
  - Stale analyser result: inkMuted plus "STALE" and its age.
- **Faults.** Faults are never shown in drills or plant view. In the sandbox, an injected fault puts an info-blue ⚑ on the affected item (tray, valve, tag) with the Faults tab entry.
- **Faceplates:** tag, mode badge (AUTO plain; MAN in a warn outline; CAS in accent; "MAN (shed)" in an alarm outline), PV digits, a PV bar with SP marker (accent) and HI/LO ticks, an OP bar (inkMuted), and the signal look and valve curve of M3.
- **Charts:**
  - Dark trend grid (grid / gridMajor). PV in its series colour, 1.5 px, with a soft glow (one blurred stroke under a sharp stroke). SP dashed ink; OP on a right-hand axis in inkMuted.
  - Min/max envelope at 25 % alpha of the series colour; alarm limits dotted warn.
  - McCabe–Thiele: eqCurve ink, operating lines accent (CMO reference dashed), staircase liquidLight, q-line hot.
- **Signature effects:** alarm blink at 1 Hz until acknowledged; "ACK" button. Glow uses `MaskFilter.blur(BlurStyle.normal, 3)` on at most 8 strokes per frame (Low quality: no glow).
- **Contrast** (VALIDATION.md U2) is checked with these values: info and selection on bg exceed 7:1; the series colours on the chart background exceed 3:1.

**T-3 Phosphor — "Green Screen CRT"** (M7)
- Palette: single hue. bg `#031A09`, bgAlt `#02140A`, surface `#06240F`, ink `#33FF66`, inkMuted `#1F9940`, inkFaint `#0E5223`, grid `#0B3D1A`, gridMajor `#12602A`, accent `#9CFFB5`, accent2 `#FFB000` (amber, used only for the selection cursor), steel `#33FF66`, liquidLight `#66FF99`, liquidHeavy `#1A8F3A`, froth `#9CFFB5`, vapor `#33FF66` at 40 %, hot/cold = ink at 100 %/60 %, ok `#33FF66`, warn `#FFB000`, alarm = inverse video (green block, black text) blinking, eqCurve `#33FF66`, opLine `#9CFFB5`, qLine `#9CFFB5` dotted, stepLine `#66FF99`, diagonal `#0E5223`, pseudoEq `#1F9940`.
- Remaining tokens (M7 readiness pass): surfaceAlt `#0A2E14`, info `#9CFFB5`, selection `#FFB000` (the amber cursor), marker `#9CFFB5`, opLineCmo `#9CFFB5` dashed.
- Series (colour plus dash, since the hue is fixed):
  - `series1` `#33FF66` solid; `series2` `#9CFFB5` dashed [6, 3]; `series3` `#1F9940` solid;
  - `series4` `#33FF66` dotted [1.5, 3]; `series5` `#9CFFB5` dash-dot [6, 3, 1.5, 3]; `series6` `#1F9940` dashed [6, 3].
  - Amber stays reserved for the cursor and warn.
- Alarm priorities are told apart by the Control Room symbols (◆ ▲ ■) and text, not by colour.
- Contrast on bg `#031A09` (VALIDATION.md U2): ink 13.5:1, inkMuted 4.9:1, accent and info 15.0:1, liquidLight and stepLine 14.1:1, amber 9.9:1. The weakest series (`#1F9940`) is 4.9:1, so every chart line clears 3:1.
- Typography: "VT323" for everything; numbers padded to fixed width.
- Column: vector-display drawing; liquid as a fill of `≈` glyph rows; vapour as `°` glyphs drifting up.
- Charts: vector lines with persistence — the previous 4 staircase states drawn with alpha 0.5, 0.3, 0.15, 0.07, so changes leave fading trails.
- Signature effects: scanline overlay (cached 2-px stripe `ImageShader`), slight bloom (Low quality: off), vignette (cached radial gradient). No screen curvature (cost).

**T-4 Brass — "Steamworks Refinery"** (M9)
- Palette: bg `#1B120B` (walnut), bgAlt `#140D08`, surface `#2B1D12`, surfaceAlt `#3A2818`, ink `#F3E2C7` (parchment), inkMuted `#C8B08A`, inkFaint `#7A6448`, grid `#4A3622`, gridMajor `#6B4F30`, accent `#C89B3C` (brass), accent2 `#B87333` (copper), steel `#C89B3C`, liquidLight `#E8B04B` (amber), liquidHeavy `#7A3E12` (tea), froth `#F6D58E`, vapor `#EDE6DA` (steam), hot `#E2572B`, cold `#6FA8A0` (verdigris), ok `#8DB255`, warn `#E8B04B`, alarm `#D7263D`, eqCurve `#3B2A1A` on parchment inset, opLine `#7A3E12`, qLine `#9A5B24`, stepLine `#2F4F4F`, diagonal `#A08C70`, pseudoEq `#7A6448`.
- Typography: "Cinzel" (titles), "IM Fell English" (labels), "Courier Prime" (numbers).
- Column: riveted brass shell with a vertical bevel gradient; porthole sight glasses for drum and sump levels; steam puffs from vents; dial gauges (pressure, key temperatures) with needles.
- Charts: drawn on a parchment inset with sepia ink and a thin brass frame.
- Signature effects: needles follow a damped spring (ζ = 0.6, 0.4 s natural period) so they overshoot slightly; rivets are a cached pattern; gear spinner while running to steady state.

**T-5 Paper — "Textbook"** (M5)
- Palette: bg `#FBF8F1`, bgAlt `#F3EEE3`, surface `#FFFFFF`, ink `#1F2328`, inkMuted `#57606A`, inkFaint `#A8A29A`, grid `#E3DED3`, gridMajor `#CFC8BA`, accent `#2B6CB0`, accent2 `#C0392B` (red pen), steel `#1F2328`, liquidLight `#9CC9F5`, liquidHeavy `#2B6CB0`, froth `#D6E8FA`, vapor `#9AA0A6`, hot `#C0392B`, cold `#2B6CB0`, ok `#1E5020` (M10, was `#2E7D32`; U3), warn `#B7791F`, alarm `#C0392B`, eqCurve `#1F2328`, opLine `#2B6CB0`, opLineCmo `#2B6CB0` dashed, qLine `#B7791F`, stepLine `#C0392B`, diagonal `#A8A29A`, pseudoEq `#57606A` dotted.
- Typography: "Source Serif 4" (text), "Source Sans 3" (UI), "STIX Two Math" (math and axis labels).
- Column: clean schematic like a textbook figure — thin black outline, light blue liquid, grey vapour.
- Charts: classic McCabe–Thiele as printed in textbooks: black equilibrium curve, blue operating lines, red staircase, stage numbers in small italics beside each step.
- Remaining tokens (M5 readiness): surfaceAlt `#F1ECE1`, info `#1F6F8B`, selection `#F6D365` (highlighter; used **only as a fill** at 60 % alpha behind ink, never as a line or text colour), marker `#1F2328`; series `#2B6CB0` `#1F2328` `#00796B` `#6A3D9A` `#B35C00` `#C2185B`. Red (alarm, stepLine) and the ok/warn colours are not series colours. Contrast (VALIDATION.md U2) on bg / surface: series lowest 4.45 / 4.72 (`#B35C00`), info 5.34 / 5.67.
- Style switches: vesselStyle outline, liquidStyle gradient (flat fill lerped liquidLight → liquidHeavy with composition, no texture), vaporStyle dots (vapor, small, no glow), gaugeStyle numeric, lineStyle ink (1.25 px solid strokes, no glow). Effects: paperGrain on (the cached grain tile at 4 % alpha), figureCaptions on, alarmBlink on; blueprintGrid, scanlines, bloom, vignette, rivets and needlePhysics off.
- Signature effects:
  - Figure captions under each diagram, in Source Serif 4 italic, inkMuted: "Figure n — <diagram>, <system>, Tier <k>[ (<model>)], P = <P_top in display units>, t = hh:mm:ss". n is the tab's position (McCabe–Thiele 1, T-x-y 2, Profiles 3, Trends 4, Products 5, Equipment 6). Example: "Figure 2 — T-x-y, ethanol–water, Tier 3 (NRTL), P = 1.013 bar, t = 01:32:10". A "transient" caption (PHYSICS.md §14.1) is appended in accent2.
  - Margin note for the selected tray: a 160-dp box in the diagram's right margin (below the caption on compact layouts), Source Serif 4 italic 12 sp, ink on surface with a hairline inkFaint border, joined to the stage marker by a thin inkMuted leader. Content: "Tray j: T, x, y, y*, L, V" in display units, 4 significant figures.
  - "Export figure": a button in the diagram panel header (Paper only; other themes hide it). It renders that panel's chart and caption, without the app chrome, through `RepaintBoundary.toImage(pixelRatio: 3)` (longest side capped at 4096 px), on an opaque surface background, and writes a PNG named `lowsys_<preset>_<tab>_<hhmmss>.png`. Windows: the Downloads folder (`getDownloadsDirectory()`, falling back to the Documents folder). Android: the app's external files folder `…/Android/data/<package>/files/figures/` (`getExternalStorageDirectory()`; no storage permission needed). A snackbar shows the full path. This adds `path_provider` (flutter.dev) to the app dependencies (§9). A share sheet is not in M5.

**T-6 SPD — "Royal Crimson"** (added after M10)
- Palette: bg `#3A0F17` (oxblood), bgAlt `#2A0A10`, surface `#531824`, surfaceAlt `#6A2331`, ink `#F7EBD2` (ivory), inkMuted `#DDC49C`, inkFaint `#9E7A6A`, grid `#6B2C39`, gridMajor `#8F4A55`, accent `#E7B94C` (gold), accent2 `#D4A05A`, steel `#D9B35A`, liquidLight `#F0C45A`, liquidHeavy `#B3394A`, froth `#F8E3A8`, vapor `#F1E6D2`, hot `#FF8A4D`, cold `#7FC6D6`, ok `#9BE8BE` (pale mint), warn `#FFA03A`, alarm `#FF2E7E` (hot magenta-pink, set apart from the red ground by hue and lightness), info `#7FC6D6`, selection `#E7B94C`, eqCurve `#F7EBD2`, opLine and opLineCmo `#E7B94C`, qLine `#FF8A4D`, stepLine `#7FC6D6`, diagonal `#B08C78`, pseudoEq `#C9AA8C`, marker `#F7EBD2`; series `#E7B94C` `#5CC8C0` `#F7EBD2` `#F28BA8` `#8FB4F0` `#F08A3E` with dashes solid, 7-3, 2-3, 8-3-2-3, 4-2, 1.5-2.5.
- Typography: "Cinzel" (titles), "Source Serif 4" (labels), "JetBrains Mono" (numbers), "STIX Two Math" (math).
- Style switches: vesselStyle flat, liquidStyle gradient, vaporStyle glowDots, gaugeStyle bargraph, lineStyle glow (at most 4 glow strokes). Effects: vignette and alarmBlink on.
- Contrast: see the test output of `validation_m10_contrast_test.dart`; no exemption.

### 7.2b T-x-y drawing (all themes, M5)

The T-x-y tab (PHYSICS.md §14.4b) uses only existing tokens:
- Bubble curve (saturated liquid, T vs x): `cold`, solid, labelled "liquid" (Paper: "bubble-point curve"). Dew curve (saturated vapour, T vs y): `hot`, solid, labelled "vapour" (Paper: "dew-point curve"). Phosphor varies intensity (100 % / 60 %) as for hot/cold.
- Curves at P_{N+1} (shown when the column ΔP > 1 kPa): the same tokens at 50 % alpha, dashed.
- Azeotrope: a filled diamond in `marker` with a leader label "azeotrope x = 0.8956, 78.14 °C" (display units; maximum-boiling ones say "maximum-boiling azeotrope").
- Column overlay: each stage as a hollow circle in `stepLine` at (x_j, T_j); the drum and sump points as filled circles in `accent` labelled D and B; the selected stage's circle is filled with `selection`, and a horizontal tie-line in `accent` joins (x_j, T_j) to (y_j, T_j).
- Tier 1 (curves from the Tier-2 model, PHYSICS.md §14.4b): the caption or a banner says "ideal (Raoult) — constant α has no temperatures". Stage points use the display T* (PHYSICS.md §1.3).
- The x-y sub-view (toggle in the tab header) uses the McCabe–Thiele tokens: eqCurve, diagonal, azeotrope marker.
- Axes: x or y of the light component, 0–1; T in display units with 5 K (or 10 °F) major ticks.

### 7.3 Performance rules for all themes

- Static layers (grids, textures, vessel outline, rivets) are painted once into a `RepaintBoundary` and invalidated only on resize or theme change.
- Animated layers repaint from a `ValueListenable<SimSnapshot>`; no widget rebuild per frame.
- At most 400 vapour particles on screen (High) / 120 (Low), pooled; positions advance on the UI clock.
- Blur/glow/bloom and scanline shaders are disabled on Low quality and when the measured frame time exceeds 14 ms for 2 s.
- No `saveLayer` per tray; one `saveLayer` per panel at most.

### 7.4 Drawing hydraulic states (all themes)

The two kinds of flooding look different in the model, and must look different on screen (PHYSICS.md §5.6):
- **Jet flood** (`jetFlood` ≥ 1, or high ψ): spray and carryover. Dense entrainment particles leave the froth and land on the tray above; at tray 1 liquid streams up the vapour line into the condenser. The froth itself stays at its normal height, since the fill is about 0.35 at jet flood.
- **Downcomer flood and full-tray overflow** (`dcFlood` ≥ 1 or `frothFill` ≥ 1): froth stacks up to the tray above, and the downcomer is shown backed up to the next deck.
- **Weeping:** drips under the deck, scaled with the weeping fraction.
- **Dumping** (flag bit 2): an almost empty deck with liquid raining through the holes.
- **Dry tray** (flag bit 8): an empty deck with no froth.

---

## 8. Milestones

Every milestone is shippable on its own: it builds for Windows desktop and Android, passes its VALIDATION.md tests, and adds user-visible value. "VC-x" refers to VALIDATION.md cases.

### M1 — Vertical slice: textbook binary column (Tier 1)

**Engine** (`packages/lowsys_engine`)
- Component data for benzene and toluene (MW, Tier-1 constant properties); unit helpers (SI only).
- `ColumnConfig` for a single tray section: N trays (3–60), feed tray, sieve-tray geometry (only what the weir model needs: diameter, A_d/A_T, weir height), reflux drum volume, sump geometry.
- Tier 1 thermo: constant α (B-T α = 2.5; "custom α" preset 1.05–10), CMO.
- Dynamic stage model (PHYSICS.md §4 and §12): component holdups per stage; Bennett weir hydraulics with the scalar implicit holdup solve (ideal hydraulics: no ΔP, entrainment, weeping, downcomer limits); implicit tridiagonal component balances with the Murphree two-pass scheme; total condenser + reflux drum; partial reboiler + sump.
- Internal PI level loops (drum → D, sump → B) at fixed defaults (Kc = 2 %/%, Ti = 1800 s), AUTO only, not user-switchable.
- Levers: F, z, q, feed tray, reflux flow or ratio, boilup V_B, E_MV, N (rebuild while paused).
- Fixed step dt = 0.5 s; `advance`, `runToSteadyState`; snapshots; McCabe–Thiele data builder (equilibrium curve, diagonal, q-line, CMO operating lines from external flows, actual operating locus, live staircase, Murphree pseudo-equilibrium points, x_F/x_D/x_B markers).
- Steady-state residual for the "Steady?" indicator.

**App** (`app/`)
- One Simulator screen (S2) with TimeBar (pause, 1×–1000×, run to steady state), ColumnView, DiagramPanel with the McCabe–Thiele tab only, ControlPanel with the Levers tab only, KpiStrip (xD, xB, D, B, R, drum %, sump %).
- Tray inspector: tap a tray to see x, y, y*, L, V, holdup, E_MV in a small panel (numbers only; the full math overlay is M2).
- Responsive layouts for compact portrait, compact landscape and expanded desktop.
- Blueprint theme only; SI units only; presets "Benzene–toluene (textbook)" and "Custom α".

**Acceptance criteria**
1. VC-1 (textbook numbers from the McCabe–Thiele utilities), VC-3 (total reflux), VC-4 (dynamic steady state matches the independent solution: xD = 0.981183 ± 1×10⁻⁵, xB = 0.018817 ± 1×10⁻⁵ for the default case), VC-5 (component conservation), VC-6 (dt robustness), VC-7 (dynamic responses), VC-18 (McCabe–Thiele data invariants), VC-20 (determinism) pass in CI (`dart test` in the engine package).
2. From the default preset, "Run to steady state" finishes in under 10 s wall time on the Windows dev machine and shows the "Steady" indicator.
3. At 100× on a mid-range Android device (or the emulator profile "Pixel 6", release build) the UI holds ≥ 55 fps for 60 s with the McCabe–Thiele tab open.
4. Changing reflux by +10 % visibly moves the staircase within 5 s of wall time at 100× and settles to the new steady state.
5. Layout check on emulator: portrait 360×800 dp, landscape 800×360 dp, desktop 1440×900: no overflow errors, all levers reachable, all text ≥ 12 sp.

### M2 — Tray hydraulics, first faults, math overlay, units

- Engine: full sieve and valve tray hydraulics (PHYSICS.md §5): dry ΔP, tray ΔP and pressure profile, Bennett froth, jet flooding (Fair / Lygeros–Magoulas), entrainment flows, weeping bypass and dumping, downcomer backup limit, flood overflow; hydraulic indicators per tray; "ideal/full" switch.
- Faults F01–F07 with the fault manager (onset, ramp, clear).
- Explain API v1 (Tier 1 MESH, equilibrium, Murphree, hydraulics) and the math overlay UI.
- Unit system SI / US field everywhere.
- App: Profiles tab (ΔP, flood %, weep fraction, holdup, x per tray); column painter shows froth height, entrainment spray, weeping drips, flooding overlay; Faults tab in sandbox.
- Acceptance: VC-8 (qualitative Tier-1 checks), VC-12 (hydraulic checks and fault symptoms), VC-17 (units), VC-21 (explain consistency) pass; math overlay opens for every tray and stream in under 100 ms.

### M3 — Regulatory control, trends, alarms, scenario engine

- Engine (PHYSICS.md §10, §12.9, §14.6):
  - PID library: velocity form, corrected derivative sign, setpoint re-basing, anti-windup, bumpless transfer, IMAN cascade initialisation, BAD-PV shedding.
  - Real PI flow loops FC-101/102/103 in a 0.1 s fast layer, replacing the ideal flow controller; LC-101/102 switchable AUTO/MAN.
  - Valves: characteristic, actuator lag, supply disturbance, bypass.
  - Instruments: the full pipeline with seeded noise (xoshiro128**), 4–20 mA, quality, analysers and field gauges.
  - Faults F19, F20 and F28.
  - ISA-18.2 alarms with acknowledgement.
  - Cross-checks C1, C3, C4, C5; plant view; the noise-aware steady indicator.
  - The scenario runner extended from M2 (per-step update, answer objectives, drill-ready schema, exact scoring, debrief templates).
  - Sandbox save/load (JSON).
- App:
  - Faceplates tab (signal look, valve curve, field check, maintenance); Balance tab; Trends tab (rolling 2 h sim-time buffer, 5-s bins with min/max envelopes, auto-scaling with a minimum range of 10 σ).
  - Alarm banner and list with Ack; plant-view toggle; noise on by default in the sandbox.
  - Scenario list / briefing / debrief screens. Guided scenarios G1–G6 and G11–G12 (Tier 1 versions; objectives and reference numbers in ENGINE_API.md §11.8).
- Acceptance: VC-7.2 (amended), VC-16, VC-20.3–20.6, VC-22 (Tier 1 instruments), VC-23 (C1, C3, C4, C5), VC-24, VC-25 and VC-26 pass. All eight scenarios can be completed by following their hints (VC-26.4), and scenario JSON files validate against the schema test. With noise on, B-T Tier 1 at 100× still holds ≥ 55 fps on the reference phone.

### M4 — Tier 2: ideal thermodynamics, energy balances, pressure

- Engine:
  - Component database (PHYSICS.md §2.1); vapour pressure models (Antoine, DIPPR-101, Lee–Kesler); Raoult K; bubble/dew/flash; enthalpy model.
  - Quasi-steady energy balance (vapour profile) with the **implicit** pressure-driven storage term (PHYSICS.md (4.6), a v1.1 change).
  - Overhead vapour inventory tracked per component, and pressure dynamics. The pressure solve runs *before* the hydraulic step (§12.4 step 6, also v1.1).
  - Condenser UA + cooling water at the 50 % CW design (§7.2: UA_clean 29.9 kW/K for B-T); PC-101 (Kc 10, Ti 120 s).
  - Kettle reboiler with steam-side heat-transfer limit; partial condenser (vapour header P_design − 30 kPa); inert vent to a 0.5 bar(a) vent system; relief capacity.
  - Reflux subcooling, feed temperature input.
  - Runtime tier switching with the top-vapour rule (§13.5); TC-101 option.
  - Faults F08–F15; preset `mw` (Tiers 1/2).
- McCabe–Thiele upgrades: non-CMO actual operating locus, q from feed enthalpy, local-equilibrium band (top-to-bottom pressure), temperature profile chart.
- App: Control Room theme (§7.2, completed in v1.1); scenarios G7, G8. G11 stays Tier 1 (decided 2026-10-13): flooding lives in the hydraulics, which both tiers share, and in Tier 2 the B-T condenser cannot follow the load (×1.3 needs ≈ 1.67 MW against 1.39 MW at 100 % CW, VC-27.3), so P would rise and the lesson would become a condenser limit, with none of ENGINE_API.md §11.8's [P] numbers valid.
- Energy panel (Equipment tab), three cards:
  - Condenser: Q_C, UA_eff vs UA_clean, T_cw in/out, CW OP, condensing T, reflux subcooling, inert fraction y_I.
  - Reboiler: Q_R delivered vs Q_max, UA_eff, steam header pressure and T_st, steam valve OP, "duty limited" flag.
  - Column energy balance: F h_F + Q_R in, Q_C + D h_D + D_V H_V,0 + B h_B out (D_V H_V,0: the partial condenser's vapour product, 0 for a total condenser), and the residual (`Kpis.energyResidual`).

  In plant view the cards show readings only (FT-201, TI-201/202, PT-201, FT-103) and the C3a/C3b checks.
- Acceptance: VC-10 (thermo spot values), VC-11 (Tier-2 MESH reference, duty 1301.477 kW), VC-8 Tier-2 directions (8.7 with 10 bar(g) steam), VC-5.2 (1×10⁻¹⁰) and VC-5.4 pass; energy closure ≤ 1×10⁻⁶ relative at steady state (prototype 5×10⁻⁹); VC-16.6 (pressure loop, flash stability), VC-18.3 and VC-27 (mw preset, pressure sweep, utility limits) pass; switching T1 ↔ T2 at steady state meets VC-8.9: no NaN, top vapour and D continuous, the stripping-section vapour steps by the physical −4 … −6 %. v1.0's "no step > 5 % in any flow" is not physical. Identical steady states at dt = 0.5, 2 and 30 s.

### M5 — Tier 3 (NRTL, DePriester) and azeotropic binaries

Readiness pass completed 2026-10-12 (excerpt: docs/milestones/M5.md).

- Engine:
  - NRTL activity model (`Tier3Nrtl`, PHYSICS.md §3.4.1) and DePriester K (`Tier3DePriester`, §3.4.2; used by `c4` in M5, by `debut`/`deprop` from M7).
  - Presets `ew`, `ac`, `c4`, and Tier 3 for `mw` (PHYSICS.md §2.3, including the M5 preset rules).
  - Azeotrope finder and T-x-y data (PHYSICS.md §14.4b; ENGINE_API.md §7.3).
  - McCabe–Thiele azeotrope rules: q-line root search, R_min "beyond the azeotrope" banners (§14.1).
  - Tier switching among T1/T2/T3 (§13.5); explain lines `eq.nrtl` and `eq.depriester` (§15).
  - Tier-2 instruments, cross-checks C6/C7 and faults F08–F15 work unchanged in Tier 3; C7 uses the active tier's bubble point.
- App:
  - Paper theme (§7.2, completed in the readiness pass).
  - T-x-y tab with x-y sub-view (§3.2, §7.2b).
  - Tier badge T1/T2/T3. T3 is hidden for presets whose Tier 3 equals Tier 2 (`bt`, `crude`).
  - Tier 1 on `ac` shows the banner "Tier 1 cannot represent this system" (PHYSICS.md §2.3).
  - Scenarios G9 and G10 (ENGINE_API.md §11.8); G8 gets its condenser-limit debrief line.
- Acceptance:
  - VC-10.4–10.6, VC-10.8 (every preset system, including `c4` with DePriester) and VC-10.9 (DePriester K).
  - VC-8.10, 8.11 and 8.13; VC-18.4; VC-28.1–28.8. The Tier 3 ethanol–water column never exceeds the azeotrope in the distillate (VC-8.10, VC-28.6).
  - VC-5.2 (1×10⁻¹⁰) and VC-5.4 (1×10⁻⁶) on `ew` and `ac` in Tier 3.
  - VC-21 for the NRTL and DePriester lines.
  - U1 with the T-x-y tab; U2 and U4 for Paper.
  - G9 and G10 are completed by their hints (VC-28.8).
  - Identical steady states at dt 0.5, 2 and 30 s (VC-28.1).

### M6 — Thermosyphon reboiler and hidden-fault drills

Readiness pass completed 2026-10-13 (excerpt: docs/milestones/M6.md). It changed §8.3 (exact x_e solve, oscillator floor only while unstable, FT-103 on the steam side), re-derived VC-14 and added the H1–H5 definitions, G14 and the "plant view with calculations".

- Engine: thermosyphon loop model with instability index and oscillator (PHYSICS.md §8.3); faults F16–F18; hidden-fault framework (seeded candidate, severity, onset and sign draw, diagnosis submission, protect/off-spec clocks, drill scoring; ENGINE_API.md §11.2–11.4). Measurement noise already exists from M3.
- App: Equipment tab for the reboiler (loop schematic, circulation, exit quality, I_s gauge); Drill HUD and Diagnose dialog; drills H1–H5, H9, H10; scenario G14.
- Acceptance: VC-14 (thermosyphon map) passes; each drill's injected fault produces its listed key evidence (automated symptom tests per drill in VALIDATION.md §H); H9 and H10 pass their noise-on detectability tests (VALIDATION.md §H, H9.0–H10.7), and candidates that cannot are disabled (weight 0) and recorded.

### M7 — Multicomponent light hydrocarbons

- Engine: hydrocarbon components C3–nC7 (PHYSICS.md §2.1), Tier 1 multicomponent constant α, Tier 2 Raoult with Lee–Kesler, Tier 3 DePriester (McWilliams; the K model ships in M5 with `c4`); debutanizer and depropanizer presets; key components; FUG shortcut module (Fenske, Underwood, Gilliland/Molokanov, Kirkbride) computed live; Hengstebeck pseudo-binary McCabe–Thiele.
- App: Phosphor theme; Products tab with the FUG panel; component profile chart; scenario G13; drill H6.
- Acceptance:
  - VC-9.1–9.8: FUG numbers, DePriester spot values, bubble and dew points, the rigorous-vs-shortcut check, preset steady states with tier switches, the live FUG panel and the G13 references.
  - VC-21 for `eq.fug.*` and `eq.hengstebeck`; VC-26.1 on G13 and H6.
  - The VALIDATION.md §H rows for H6 (noise off, plus the noise-on rule-1 check for `fv102_stuck`).
  - U2 for Phosphor.
  - 40 trays × 7 components in Tier 3 runs at ≥ 100× on the reference phone (VC-19). v1.0 said 8 components, but the database has seven light hydrocarbons.

Readiness pass completed 2026-10-13 (excerpt: docs/milestones/M7.md). Spec changes:
- The sandbox presets get E = 0.7 tray counts (32 / 16 and 28 / 11) and default to Tier 3, with utilities sized from the Tier-3 steady state (PHYSICS.md §2.3).
- The DePriester validity range is corrected to 852 °R, with no clamping (§3.4.2).
- The FUG and Hengstebeck rules are made exact (§14.2–14.3), and multicomponent analysers read key cuts (§10.5, `kpi.xDHeavy` / `kpi.xBLight`).
- VC-9.5 dew points are corrected; VC-9.6–9.8, the G13 objectives and the full H6 drill (ENGINE_API.md §11.8, §11.10) are new.
- Phosphor's missing tokens are filled in, and `seriesDash` tokens are added.

### M8 — Packed sections

- Engine: packing database, packed-section segmentation by HETP, holdup, Robbins ΔP, Kister–Gill flood, HETP modifiers (wetting, loading), parallel-column maldistribution, faults F21–F23; mixed tray/packed columns.
- App: packed-bed rendering (texture, wetting, liquid rivulets), scenario G15, drill H7.
- Acceptance:
  - VC-13 passes (VC-13.1–13.9).
  - VC-21 for the packing lines (`eq.robbins`, `eq.kisterGill`, `eq.packHoldup`, `eq.hetp`, `eq.lewis`, `eq.maldistribution`).
  - VC-26.1 on G15 and H7, including the M8 vocabulary and the null-fault candidate.
  - The VALIDATION.md §H rows for H7, with noise off.

Readiness pass completed 2026-10-13 (excerpt: docs/milestones/M8.md). Spec changes:
- New preset `bt_packed`: two 4.5 m struct250 beds in the B-T shell (9 + 9 segments, feed on stage 10). The new lever `internals` switches the B-T family between trays, packing and a mixed template (PHYSICS.md §2.3, §6.1, §13.4).
- struct250 HETP_ref 0.45 → 0.50 m, by the stated rule. The packing table is flagged as quoted from memory.
- Exact rules for the per-segment flows and properties, ΔP in the pressure profile, wetting as max(1, ·) with L'_des, λ as the equilibrium slope (v1.0 used K), and maldistribution with n = n_th and a geometric-mean S (§6.3–6.6).
- Per-bed PDTs and bed TIs (§10.5), and the plant-view rules for packing (§10.9).
- G15 moves to Tier 1: its tray numbers are VC-12.3's, and in Tier 2 the B-T condenser cannot follow load changes.
- The full H7 drill (ENGINE_API.md §11.11): 1.0 m beds, CW at 15 °C, a +25 % planning event that *is* the F22 candidate, and a null-fault candidate.
- VC-13.4–13.9 are new or rewritten, and the §H H7 rows are rewritten.

### M9 — Crude fractionation

- Engine: assay → pseudo-components (PHYSICS.md §9), crude thermo with steam, crude column topology (main column, three 2-stage side strippers, pumparound, bottom and stripper steam), product property calculations (TBP, D86 via Daubert, 5–95 gaps), crude control scheme, faults F24–F27.
- App: Brass theme; crude flowsheet in ColumnView; Products tab with TBP/D86 curves and gap bars; scenario G16; drill H8.
- Acceptance: VC-15.1–15.7 (pseudo-components and the M9 enthalpy rule, D86 conversion, ideal and lumped cuts, the default steady state, F24–F27, G16, structure and robustness), VC-19 for crude, VC-21 for the crude equation lines, VC-26.1 on G16 and H8, and the §H H8 rows.

M9 readiness pass (2026-10-13; prototype `tools/prototypes/m9`, excerpt `docs/milestones/M9.md`):
- **Enthalpy.** Crude enthalpies take the T_b reference and an anchored vapour enthalpy with the Fallon–Watson Cp_V (PHYSICS.md §9.1). §3.3's path gave a falling vapour enthalpy near T_c, and negative (4.6) denominators on crude stages.
- **Steam fraction.** The bubble point uses a filtered, capped steam fraction (§9.3); the lagged v1.0 value has a loop gain of ≈ 12 on stage 30.
- **Product draws.** The draw levers set product rates, and the stripper level sets the draw (§9.4).
- **Pumparound.** Fixed circulation of 120 m³/h, with a cooler limit at a 120 °C return (§9.5).
- **TBP trim.** Product TBP 0/100 % are read at 1/99 % (§9.6); without it a 0.007 % trace gave a diesel D86 0 % of −154 °C.
- **Overhead.** Ideal top pressure and drum temperature, with Q_C,max 15 MW only flagged (§9.7).
- **Column.** Theoretical stages (E = 1), and a 1.7 m stripping section (§9.2).
- **Defaults.** COT 345 °C (was 360) and PA 5 MW (was 6; range 0–10).
- **Tags.** Crude tags are renumbered to the 300 series (PHYSICS.md §10.7).
- **Faults.** F24–F27 are defined with numbers (PHYSICS.md §11); F26 is a high-reading COT.
- **Content.** The G16 residue criterion becomes TBP 5 % ≥ 355 °C. H8 gets its full JSON (ENGINE_API.md §11.12).
- **Validation.** VC-15.4 becomes a [P] reference table, and VC-15.5–15.7 are new.

### M10 — Content completion, polish, platforms

- All scenarios and drills reviewed against VALIDATION.md; Library screen; onboarding tutorial.
- Performance pass: run the engine in a background isolate on native platforms (web stays on the UI isolate with a smaller budget).
- iOS and web builds; accessibility (semantics labels for every lever and KPI, colour-blind-safe check of every theme's alarm/ok pair, text scaling to 130 %); all user strings in one localisation file.
- Acceptance: full VALIDATION.md suite green on Windows, Android, iOS simulator and Chrome; no theme fails the contrast check (VALIDATION.md §U).

---

## 9. Decisions made on the user's behalf (defaults, not questions)

| Topic | Decision | Why |
|---|---|---|
| Fourth/fifth binary | Acetone–chloroform (maximum-boiling azeotrope) and isobutane–n-butane (close boilers, α ≈ 1.35) | Contrasts with ethanol–water; shows why C4 splitters need many trays |
| Tier 3 for hydrocarbons | DePriester K-values (McWilliams fit), not an equation of state | Cheap, textbook-standard, captures pressure non-ideality |
| Crude tiers | Tier 2 only (Tier 1 locked, Tier 3 = Tier 2) | CMO is meaningless with pumparounds and steam; pseudo-components are ideal by construction |
| Thermosyphon instability | Physically computed steady loop + instability index driving a limit-cycle oscillator | First-principles density-wave oscillations need fine meshes and millisecond steps (see PHYSICS.md §8.3) |
| Default control configuration | LV: reflux on flow control, boilup/duty on flow control, drum level → D, sump level → B, pressure → cooling water; tray temperature control off | The textbook configuration; levers map directly onto L and V |
| Default Murphree efficiency | 0.70 in sandbox, 1.00 in textbook scenarios | Realistic by default, ideal where textbooks are |
| Time step | Fixed 0.5 s (deterministic); fast-forward uses 2.0 s | Stable and accurate per the prototype study in PHYSICS.md §12 |
| State management | Plain `ChangeNotifier`s + `InheritedNotifier`, no third-party package | Fewest concepts for the implementer; hot path uses `ValueListenable` |
| Fonts | Bundled OFL fonts (offline) | Works on phones without network |
| Tier-2 storage term | Implicit in the overhead pressure (PHYSICS.md (4.6)) | The v1.0 lagged form ran away in the M4 prototype at every dt |
| Tier switch | Keep the top vapour and D, not the boilup | Keeping the boilup collapsed x_D 0.981 → 0.883 on a B-T switch (PHYSICS.md §13.5) |
| Condenser design | 50 % CW at the design point | At 70 % the CW valve had 3 % authority and the pressure floated on every duty change (PHYSICS.md §7.2) |
| Default tray spacing (B-T and its variants) | 0.90 m (was 0.60 m): the default runs at 63 % of jet flood | Raising reflux and boilup then improves xD as the textbook says; flooding needs about +60 % load. Spacing changes nothing in ideal hydraulics or in weeping (PHYSICS.md §5.1) |
| Flow control | Real PI flow loops (Kc 0.6, Ti 2 s) on measured flow, sub-stepped at 0.1 s; closed-loop 63 % in 3 s | Instrument and valve faults need a controller that acts on a reading and owns an OP; the sub-step keeps it identical at every dt (PHYSICS.md §10.4) |
| VC-7.2 | Tray lag timed from the delivered reflux, not the lever | That is what the case was written to test; holds for any flow-loop speed (VALIDATION.md VC-7.2) |
| Random numbers | xoshiro128** with per-process streams (32-bit operations only) | Bit-identical on native and web; adding a fault never changes another instrument's noise (PHYSICS.md §12.9) |
| Noise in the sandbox | On by default; off in guided scenarios | The user asked for noise on; textbook scenarios read cleaner without it, and their objectives use true values anyway |
| What a drill shows | Plant view (only measured values) in H9 and H10 | Otherwise the model's true profiles would expose a lying instrument at a glance |
| Bad-PV behaviour | Loops shed to MAN on a BAD PV (sandbox, H10); H9 turns shedding off | Modern DCS default; H9 needs the old behaviour so that a signal loss threatens the process |
| G9 vacuum step (M5) | The learner turns the feed down to 60 % at 0.5 bar(a); the default condenser is kept | At 0.5 bar(a) the condensing ΔT falls from 48 to 32 K, and the default condenser carries only about 68 % of the design load. A condenser big enough for full rate (UA ≈ 60 kW/K, the earlier plan) would run at about 12 % CW at 1 atm, where PC-101 has about 15 times the B-T loop gain (VALIDATION.md VC-28.8). Turning the feed down is also what an operator would do |
| Azeotropic presets' efficiency (M5) | `ew` and `ac` ship with E = 0.7 like every sandbox preset; VC-28 and G9/G10 set E = 1 | Keeps the "0.70 in sandbox" rule; the reference steady states are textbook (E = 1) cases |
| Tier 1 T-x-y (M5) | Drawn from the Tier-2 (Raoult) model and labelled "ideal" | Constant α has no temperatures; matches M4's display-only bubble point |
| Figure export (M5) | PNG to Downloads (Windows) or the app's external files folder (Android) via `path_provider`; no share sheet | One small first-party dependency; sharing waits for M10 |
| Multicomponent sandbox columns (M7) | `debut` 32 trays and `deprop` 28 trays at E = 0.7, defaulting to Tier 3. These are the FUG designs divided by the sandbox efficiency | With the E = 1 counts at E = 0.7, the sandbox ran 4 % below its design recoveries. With these counts the FUG panel's N matches N × E + 1 (PHYSICS.md §2.3) |
| Multicomponent analysers (M7) | AT-100/101/102 read key cuts: feed light cut, HK and heavier in D, LK and lighter in B | These are the specs a real debutanizer is run to (C5+ in LPG, C4− in gasoline), and they reduce to the binary tags |

## 10. Open items for the user (not blocking)

These have defaults; the user may override them later.

1. Crude assay: LowSYS ships a synthetic ~32 °API light crude (PHYSICS.md §9.1). If the user has a specific assay they care about, it can be added as a second preset.
2. Resolved: the user wants measurement noise on, and instrument failure as its own troubleshooting drill (F28, H9, H10; delivered with the M6 drill framework). Noise is now on by default in the sandbox as well.
3. H9 includes a decoy draw (weight 2 of 17): a real feed change with every instrument healthy. This makes "process or instrument?" a real question; without it, "instrument" is always right. Set the decoy's weight to 0 to restore "the process itself is always healthy".
4. H9 runs in Tier 2 instead of "T1 or T2", because Tier 1 has no temperatures or pressure for the TI and PT faults. A Tier-1 variant would be limited to flow and level faults.
