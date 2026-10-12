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
| Control | PID loops with AUTO/MAN/CAS, valves with characteristics and lag, instruments with lag/noise/faults, alarms. | M3 |
| Teaching layers | Math overlay (equation trace), guided scenarios, free sandbox, hidden-fault drills. | M2 (overlay), M3 (scenarios), M6 (drills) |
| Diagrams | Live McCabe–Thiele (binary and key-component pseudo-binary), T-x-y, profiles (T, x, L, V, flood, ΔP), trends, FUG panel, crude TBP/D86 and gap chart. | M1, M4, M5, M7, M9 |
| Units | SI and US field units, switchable at runtime. | M2 |
| Themes | Blueprint, Control Room (DCS), Phosphor CRT, Brass Steamworks, Textbook Paper. | M1, M4, M5, M7, M9 |

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
| S6 | Diagnose dialog | Choose fault category, location and (optional) severity; submit. Opens from S2b. |
| S7 | Settings | Theme picker with live thumbnails, units, graphics quality (High/Low), default speed, haptics, reset progress, about/licences. |
| S8 | Library (M10) | Concept cards (e.g. "Minimum reflux", "Weeping") that link to the scenario that demonstrates them. |

Navigation uses plain `Navigator` routes (no routing package): S0 → S1 → S2; S0 → S3 → S4 → S2(+S2a) → S5; S0 → S3(drills tab) → S4 → S2(+S2b) → S6 → S5. Back from S2 asks "Leave simulation? (state is auto-saved in sandbox)".

### 3.2 Simulator screen (S2) building blocks

| Block | Content |
|---|---|
| **TimeBar** | Sim clock (hh:mm:ss), speed selector (Pause, 1×, 2×, 5×, 10×, 30×, 100×, 300×, 1000×), actual speed achieved (shown amber when the frame budget limits it), "Steady?" indicator (green when the steady-state residual is below tolerance), "Run to steady state" button, tier badge (T1/T2/T3, tap to switch), units toggle. |
| **ColumnView** | Animated column painter (trays or packing, downcomers, liquid, froth, vapour, drum, sump, reboiler/thermosyphon, condenser, flows on pipes, side strippers for crude). Tap a tray or stream to open the math overlay; long-press for a quick-look tooltip. Pinch-zoom and pan on phone. |
| **DiagramPanel** | Tabs: McCabe–Thiele · Profiles · Trends · Products (FUG panel or crude TBP/D86) · Equipment (condenser, reboiler / thermosyphon detail). |
| **ControlPanel** | Tabs: Levers (grouped: Feed, Top, Bottom, Column, Advanced) · Faceplates (one per control loop) · Faults (sandbox only, M2+). |
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

Touch targets are at least 48 dp. Every slider has −/+ fine buttons and a numeric entry field (tap the value). Desktop keyboard shortcuts: Space pause/resume; `+`/`-` speed; `1`–`5` diagram tabs; `M` math overlay for the selected item; `T` cycle tier; `U` toggle units; `S` run to steady state.

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
| Hydraulic realism | ideal / full | full (M2+), ideal in M1 | – | all | "ideal": holdup dynamics only (no ΔP, entrainment, weeping, downcomer limits). Used by textbook scenarios and tests |
| Cooling-water inlet temperature | 5–45 | 30 | °C / °F | T2, T3 | |
| Cooling-water flow capacity | 50–500 | 150 | m³/h / US gpm | T2, T3 | 100 % of the CW valve |
| Steam header pressure | 1–20 | 3.5 | bar(g) / psig | T2, T3 | Sets steam condensing temperature (148 °C at 3.5 bar(g)) |
| Reboiler type | kettle / thermosyphon | kettle (thermosyphon in scenarios that use it) | – | T2, T3 | Switch requires pause |
| Thermosyphon inlet valve | 5–100 | 100 | % open | T2, T3 | Throttling stabilises a surging thermosyphon |
| Antifoam injection | off / on | off | – | all | Counters the foaming fault (with delay) |
| Overhead inert vent | 0–100 | 0 | % open | T2, T3 | Purges non-condensables |
| TC-101 tray-temperature control | enable / disable, tray choice, SP | disabled; tray 14 when enabled | – | T2, T3 | Cascades to the reboiler duty |
| Measurement noise | off / on | off (on in drills) | – | all | Seeded, deterministic |

### 4.3 Multicomponent presets (defaults)

| Lever | Debutanizer | Depropanizer |
|---|---|---|
| Feed | 100 kmol/h; C3 0.05, iC4 0.15, nC4 0.25, iC5 0.20, nC5 0.20, nC6 0.15; saturated liquid | 100 kmol/h; C3 0.30, iC4 0.20, nC4 0.25, iC5 0.10, nC5 0.10, nC6 0.05; saturated liquid |
| Keys | LK n-butane, HK isopentane | LK propane, HK isobutane |
| P_top | 6.895 bar(a) (100 psia) | 17.24 bar(a) (250 psia) |
| Trays / feed tray | 22 / 12 | 20 / 8 |
| Reflux | 76.4 kmol/h (R = 1.70) | 66.1 kmol/h (R = 2.15) |
| Boilup (T1) | 121.3 kmol/h | 96.9 kmol/h |

### 4.4 Crude unit levers (M9)

| Lever | Range | Default | SI / US |
|---|---|---|---|
| Crude rate | 33–265 m³/h (5,000–40,000 bbl/d) | 132.5 m³/h (20,000 bbl/d) | m³/h / bbl/d |
| Furnace outlet temperature (COT) | 330–390 | 360 | °C / °F |
| Top pressure | 1.0–2.5 | 1.6 | bar(a) / psia |
| Top temperature SP (TC-201 → reflux) | 90–160 | 125 | °C / °F |
| Kerosene draw | 0–25 % of crude (vol) | 11.7 % | m³/h / bbl/d |
| Diesel draw | 0–30 % | 16.7 % | m³/h / bbl/d |
| AGO draw | 0–15 % | 5.3 % | m³/h / bbl/d |
| Pumparound duty | 0–15 | 6.0 | MW / MMBtu/h |
| Bottom stripping steam | 0–5000 | 2000 | kg/h / lb/h |
| Side-stripper steam (each) | 0–1000 | 300 | kg/h / lb/h |
| Overhead drum temperature (via CW) | 30–60 | 45 | °C / °F |

---

## 5. Fault catalog

Each fault has a physical model (PHYSICS.md §11 gives the equations), a severity parameter `s ∈ [0, 1]`, an onset time and a ramp time. Symptoms are the observable signatures a learner should use to diagnose it. "Fix" lists what an operator can do in the sim.

| ID | Fault | Physical model (summary) | Observable symptoms | Fix in the sim | M |
|---|---|---|---|---|---|
| F01 | Jet / entrainment flooding (operating condition) | Vapour velocity exceeds the Fair flood limit; entrainment ψ rises steeply; liquid is carried up; trays fill to the tray spacing; liquid is carried into the overhead | ΔP rises sharply and becomes erratic; xD falls (heavy component overhead); drum level rises, sump level falls; T profile flattens in the flooded zone | Cut boilup and reflux; cut feed | M2 |
| F02 | Downcomer-backup flooding | Downcomer liquid head (tray ΔP + receiving-tray head + apron loss) exceeds tray spacing; downflow is capped; liquid accumulates upward from the restriction | ΔP jumps across the section *above* the restriction; liquid inventory grows there; sump level drops; separation collapses | Cut liquid and vapour load | M2 |
| F03 | Weeping / dumping (operating condition) | Tray stability factor Φ = √(h_dry/h_cl) below 0.75 makes inlet liquid bypass the tray; below 0.2 the tray dumps (drains) | Low ΔP; efficiency loss (xB and xD both worse at the same L/V); dumping trays show near-zero holdup | Raise boilup; switch to valve trays (design) | M2 |
| F04 | Broken or missing tray | Fraction `s` of the tray deck is open: liquid bypass fraction `s` straight to the tray below, vapour bypass fraction `s` uncontacted; ΔP of that tray falls | Lower ΔP across the damaged tray; flatter T and composition profile at that location; lower separation; staircase shows a "missing step" | None in operation (needs shutdown); reduce rates to limit damage | M2 |
| F05 | Fouled / plugged trays | Open hole area × (1 − 0.8 s); downcomer clearance × (1 − 0.6 s); slow ramp (days of plant time compressed to hours) | Gradual ΔP rise in the fouled section at constant rates; earlier flooding (downcomer backup) at a lower throughput; little separation change until flooding | Reduce throughput | M2 |
| F06 | Foaming | System (foam) factor SF = 1 − 0.45 s on flood capacity; froth density α_e × SF; downcomer aeration φ_dc lowered | Flooding symptoms at normal loads; erratic ΔP; quick recovery with antifoam (after 10–20 min delay) | Antifoam on; cut rates | M2 |
| F07 | Feed composition upset | Step or ramp of z | Profile moves up/down the column; temperatures shift (T2/3); product specs drift; drum/sump levels shift | Re-target reflux/boilup | M2 |
| F08 | Feed temperature / vaporisation upset | Preheater change: T_F or q steps | V and L change below the feed; stripping section loads change; ΔP shift below feed | Adjust duty | M4 |
| F09 | Loss of condenser cooling | CW flow capacity × (1 − s) (pump trip at s = 1) or CW inlet T + 15 s K | Pressure rises; PC output saturates at 100 %; all temperatures rise; separation degrades (α falls); drum level falls; relief valve lifts at 1.3 × design pressure | Cut reboiler duty | M4 |
| F10 | Condenser fouling | UA × 1/(1 + UA R_f), R_f grows linearly with time | Slow pressure creep; PC output creeping up; subcooling falls | Cut duty; clean (not in sim) | M4 |
| F11 | Non-condensables in overhead | Inert inventory accumulates (feed carries 1×10⁻⁴·s mol inert per mol); blankets condenser area: UA × (1 − blanket fraction) | Pressure rises slowly while CW valve is open; condensate subcooling *rises* (blanketed tubes subcool); venting restores | Open inert vent | M4 |
| F12 | Loss of reflux (pump trip) | Reflux flow → 0 (or capped by `1 − s`) | Top temperature spikes; xD collapses; drum level rises fast; top trays dry out (holdup → 0) | Restore pump (fault clears); cut duty | M4 |
| F13 | Reboiler fouling | UA_R × 1/(1 + UA_R R_f), R_f grows with time | Steam valve creeps open, then saturates; duty falls below SP; bottoms off-spec; ΔP falls (less vapour) | Raise steam pressure; cut feed | M4 |
| F14 | Reboiler condensate backup (failed steam trap) | Fraction 0.8 s of tube area flooded with condensate (no condensing) | Sudden duty limitation with the steam valve wide open; steam flow falls; unlike fouling, the onset is fast | Open trap bypass (fault clears with 5 min delay) | M4 |
| F15 | Steam header pressure loss | Header pressure × (1 − 0.6 s) → lower steam temperature | Duty limited; valve 100 %; T_B unchanged at first, then bottoms purity drops | Cut feed | M4 |
| F16 | Thermosyphon instability (operating condition) | Instability index I_s > 1 grows a limit-cycle oscillation of loop circulation (PHYSICS.md §8.3) | Boilup, bottom-tray ΔP, sump level and bottom T oscillate (period 5–20 s); duty falls if exit quality > 0.30 | Raise sump level; throttle inlet valve; cut duty | M6 |
| F17 | Thermosyphon inlet restriction | Inlet loss coefficient K_in + 300 s | Lower circulation; higher exit quality; duty may fall | Clear restriction | M6 |
| F18 | Thermosyphon outlet restriction | Outlet loss coefficient K_out + 40 s | Lower circulation; surging (raises I_s strongly) | Throttle inlet (stabilise); cut duty | M6 |
| F19 | Instrument bias / drift / stuck | Measured = true + bias (step), + drift·t, or frozen | Controller holds the wrong value; mass/energy balance mismatch; cross-checks disagree (e.g. level vs flows) | Switch loop to MAN; use redundant instrument | M3 |
| F20 | Control valve stuck / failed | Valve position frozen, or failed open/closed | Controller output moves but flow does not | Switch to bypass (manual flow) | M3 |
| F21 | Packing maldistribution (distributor plugged) | Parallel-column model with liquid split fraction f = 0.6 s (PHYSICS.md §6.6) | Fewer effective stages; T profile in the bed distorts; ΔP almost unchanged | None (needs shutdown); raise reflux | M8 |
| F22 | Packing flooding (operating condition) | Robbins ΔP reaches the Kister–Gill flood ΔP; holdup rises steeply; HETP rises | Steep ΔP rise across the bed; HETP and separation worsen; liquid carryover | Cut rates | M8 |
| F23 | Packing crushed / compacted | Packing factor F_p × (1 + 1.5 s), area unchanged, bed height lowered by 0.15 s | Higher ΔP at the same load; earlier flooding | Cut rates | M8 |
| F24 | Stripping steam loss (crude) | Steam flow × (1 − s) | Residue lighter (more diesel/AGO lost to residue); flash-zone and bottom T rise; light ends in side products (front end of kero/diesel falls) | Restore steam | M9 |
| F25 | Pumparound trip (crude) | PA flow → 0 | Heat removal shifts to the overhead; top T and overhead load rise; internal reflux above the PA rises, below it falls; products get heavier | Raise reflux; cut COT | M9 |
| F26 | Furnace outlet temperature upset (crude) | COT step | Overflash changes; residue yield and gas-oil yields shift | Re-target COT | M9 |
| F27 | Draw tray dry (crude; operating condition) | Side draw exceeds internal liquid; draw pan empties | Draw flow cannot meet SP (FC saturates); trays below the draw dry; next-heavier product front end gets lighter | Reduce the draw rate | M9 |

The hidden-fault drill pool uses F04, F05, F06, F07, F09, F10, F11, F13, F14, F17, F18, F19, F20, F21, F24, F25.

---

## 6. Scenarios

Scenarios are JSON data (ENGINE_API.md §11). Each has a briefing, objectives (structured predicates on KPIs), hints, timed events, scoring and a debrief.

### 6.1 Guided scenarios (14)

| ID | Title | System / tier | What the learner does | Objective (summary) | M |
|---|---|---|---|---|---|
| G1 | Meet the column | B-T, T1, ideal hydraulics, E = 1 | Watch the column reach steady state; tap trays; read the staircase | Reach steady state; identify the feed tray on the McCabe–Thiele diagram (tap it) | M3 |
| G2 | Minimum reflux | B-T, T1, ideal, 60 trays, E = 1, feed q = 1 | Lower R at fixed D until xD = 0.95 can no longer be held; find R_min | Report R_min within ±5 % of 1.10 (textbook); see the pinch at the q-line | M3 |
| G3 | Total reflux and Fenske | B-T, T1, ideal, 6 equilibrium stages (5 trays + reboiler) | Set F = D = B = 0; compare stages with Fenske | Read xD, xB; compute N_min = ln[S]/ln α; matches 6 within 0.05 | M3 |
| G4 | The q-line | B-T, T1 | Change q from 1.2 to 0 | Hold xD ≥ 0.95, xB ≤ 0.05 at each q with the least boilup; observe the q-line pivot around (z, z) | M3 |
| G5 | Where to feed | B-T, T1, E = 0.7 | Move the feed tray from 4 to 16 | Find the feed tray that maximises xD at fixed L, V (answer: tray 11) | M3 |
| G6 | Real trays (Murphree) | B-T, T1 | Lower E_MV from 1 to 0.5; add trays to recover | Restore xD ≥ 0.98 with E = 0.5 by adding trays; compare with the Lewis relation | M3 |
| G7 | What CMO hides | B-T then methanol–water, switch T1 ↔ T2 | Compare V and L profiles and operating curves in T1 vs T2 | Explain why V_B < V_top in T2 (answer chosen from options); see the curved operating locus | M4 |
| G8 | Pressure and volatility | B-T, T2 | Raise P_top from 0.5 to 3 bar | Observe α fall (2.71 → 2.20) and duty rise for the same purity; hold specs at 2 bar | M4 |
| G9 | The azeotrope wall | Ethanol–water, T3 then T1 | Try to exceed x = 0.90 in the distillate | Discover the azeotrope at about 0.896 / 78.1 °C; see Tier 1 "beat" it falsely; lower pressure moves the azeotrope | M5 |
| G10 | The other azeotrope | Acetone–chloroform, T3 | Find where the azeotrope ends up | Identify that the maximum-boiling azeotrope (x ≈ 0.33) leaves in the bottoms | M5 |
| G11 | Flooding | B-T, T2, full hydraulics | Push throughput up 10 % per step | Find the onset of flooding (ΔP slope change, xD collapse); back off to 85 % flood | M2 (T1), upgraded in M4 |
| G12 | Turndown and weeping | B-T, sieve then valve trays | Cut throughput to 35 % | See weeping cost separation on sieve trays and not (yet) on valve trays | M2 |
| G13 | Debutanizer keys and FUG | Debutanizer, T3 | Compare the FUG panel to the rigorous column | Meet 98 % LK/HK recoveries; compare N and R_min with Fenske/Underwood/Gilliland | M7 |
| G14 | Thermosyphon tuning | B-T, T2, thermosyphon | Restore stable boilup after a low sump level causes surging | Stop the oscillation (amplitude < 2 % of boilup) without losing more than 10 % duty | M6 |
| G15 | Packing retrofit | B-T, T2 | Compare 20 sieve trays to 9 m of structured packing | Report ΔP ratio and capacity gain (flood % at the same load) | M8 |
| G16 | Crude cut points and gaps | Crude, T2 | Set draws and PA to meet kero D86 95 % ≤ 235 °C and a diesel–kero gap ≥ 0 °C | Meet both specs with residue D86-equivalent IBP ≥ 340 °C | M9 |

### 6.2 Hidden-fault drills (8)

In a drill the engine injects one fault (from the drill's candidate list, chosen by a seeded random draw) at a random onset time inside a window. Measurement noise is on. The learner may move levers and switch loops. The learner presses **Diagnose** and picks a category, a location and optionally a severity class.

| ID | Drill | System | Candidate faults (one is chosen) | Key evidence the learner should find |
|---|---|---|---|---|
| H1 | Creeping ΔP | B-T, T2 | F05 fouling (stripping trays 12–18) vs F07 lighter feed | ΔP rise at constant rates in one section → fouling; profile shift without ΔP change → feed |
| H2 | Pressure won't hold | B-T, T2 | F09 CW loss (partial), F10 condenser fouling, F11 non-condensables | Subcooling trend separates inerts (rises) from fouling/CW loss (falls); CW temperature/flow readings |
| H3 | Lost separation | B-T, T2 | F04 broken tray (rectifying), F06 foaming, F19 reflux flow meter bias | ΔP down (broken tray) vs up (foam) vs balance mismatch (meter bias: L + D ≠ V₁ from heat balance) |
| H4 | Reboiler can't keep up | B-T, T2 | F13 fouling, F14 condensate backup, F15 steam header loss | Onset speed; steam flow vs valve position; header pressure reading |
| H5 | Bottoms level swings | B-T, T2, thermosyphon | F19 sump level transmitter drift (true level low → surge), F17 inlet restriction, F18 outlet restriction | Thermosyphon circulation and exit quality; compare level with mass balance |
| H6 | Off-spec overhead | Debutanizer, T3 | F07 feed upset (more nC4/iC5), F12 partial reflux loss, F20 reflux valve stuck | Feed analyser trend vs reflux flow vs valve OP–flow mismatch |
| H7 | Packed bed underperforms | B-T packed, T2 | F21 maldistribution, F22 near-flood operation, F23 crushed packing | ΔP at constant load (crushed: up; maldistribution: flat) and bed T profile |
| H8 | Crude product drift | Crude, T2 | F24 stripping steam loss, F25 pumparound trip, F26 COT upset | Bottom T and residue yield; overhead duty and top T; flash-zone T |

Scoring (both kinds): objectives 60 %, time 20 %, safety 10 % (no relief lift, no level < 5 % or > 95 % for more than 60 s), product quality 10 % (integrated off-spec). Drills: correct category 50 %, correct location 20 %, time to diagnosis 20 %, safety 10 %. Wrong diagnoses cost 10 % each (two attempts).

---

## 7. Themes

Themes are pure data (`LowsysTheme`, ENGINE_API.md §13.4) plus a small set of painter style switches. Every theme provides every token. No theme has its own widgets or layout.

### 7.1 Token set (all themes)

Colour tokens: `bg`, `bgAlt`, `surface`, `surfaceAlt`, `ink`, `inkMuted`, `inkFaint`, `grid`, `gridMajor`, `accent`, `accent2`, `steel` (vessel outline), `liquidLight`, `liquidHeavy` (composition gradient ends), `froth`, `vapor`, `hot`, `cold`, `ok`, `warn`, `alarm`, `info`, `selection`, `eqCurve`, `opLine`, `opLineCmo`, `qLine`, `stepLine`, `diagonal`, `pseudoEq`, `marker`.

Typography tokens: `display`, `label`, `number` (tabular figures), `math` (font family, weight, letter spacing).

Style switches (enums): `vesselStyle` {outline, flat, bevel, vector}, `liquidStyle` {hatch, gradient, glyph, amber}, `vaporStyle` {circles, glowDots, glyphs, puffs, dots}, `gaugeStyle` {numeric, bargraph, dial}, `lineStyle` {pen, glow, vector, ink}, plus effect flags: `blueprintGrid`, `paperGrain`, `scanlines`, `bloom`, `vignette`, `rivets`, `needlePhysics`, `figureCaptions`, `alarmBlink`.

### 7.2 The five themes

**T-1 Blueprint — "Drafting Table"** (ships in M1)
- Palette: bg `#0E3A66`, bgAlt `#0B2F54`, surface `#12457A`, ink `#EAF4FF`, inkMuted `#A9C8E8`, inkFaint `#6F95BD`, grid `#2F6B9E`, gridMajor `#4C87BA`, accent `#FFD166` (yellow pencil), accent2 `#FF9F6E`, steel `#EAF4FF`, liquidLight `#9BE7FF`, liquidHeavy `#3FA7D6`, froth `#CFF3FF`, vapor `#FFFFFF` at 55 %, hot `#FF9F6E`, cold `#9BE7FF`, ok `#7CE0A3`, warn `#FFD166`, alarm `#FF6B6B`, eqCurve `#EAF4FF`, opLine `#FFD166`, opLineCmo `#FFD166` dashed, qLine `#FF9F6E`, stepLine `#9BE7FF`, diagonal `#6F95BD`, pseudoEq `#A9C8E8` dotted.
- Typography: labels "Architects Daughter"; numbers "Share Tech Mono"; math "STIX Two Math".
- Column: line-art cross-section; trays as double lines; weirs and downcomers drawn; liquid as 45° hatching whose density follows holdup and whose colour lerps light→heavy with composition; vapour as small outlined circles rising at a speed proportional to the hole velocity. Dimension lines show tray spacing and diameter; leader callouts label feed, draws and instruments.
- Charts: hand-ruled grid with major/minor lines; dashed CMO operating lines; arrowheads on staircase segments; a "title block" in the lower-right corner of the McCabe–Thiele panel (system, tier, sim time, P).
- Signature effects: cached blueprint grid and paper grain (one tiled image); pencil-yellow highlight on the selected tray. Cost: static layers in a `RepaintBoundary`.

**T-2 Control Room — "DCS Night Shift"** (M4)
- Palette: bg `#0B0F14`, bgAlt `#0F151C`, surface `#121A22`, surfaceAlt `#18222C`, ink `#CFE3F1`, inkMuted `#7F93A3`, inkFaint `#3C4A57`, grid `#1C2733`, gridMajor `#263442`, accent `#31C4F3`, accent2 `#9B7BFF`, steel `#8A99A6`, liquidLight `#2BD9FE`, liquidHeavy `#1E6FD9`, froth `#7FE9FF`, vapor `#B4F1FF`, hot `#FF8A3D`, cold `#31C4F3`, ok `#34C759`, warn `#FFCC00`, alarm `#FF3B30`, eqCurve `#CFE3F1`, opLine `#31C4F3`, opLineCmo `#31C4F3` dashed, qLine `#FF8A3D`, stepLine `#2BD9FE`, diagonal `#3C4A57`, pseudoEq `#7F93A3`.
- Typography: "Rajdhani" (labels), "JetBrains Mono" (numbers).
- Column: P&ID / ISA-101 high-performance-HMI style — grey vessel and lines in normal state; colour only for abnormal values and live process variables. Tag bubbles (FIC-101 etc.) next to instruments; levels as vertical bar graphs with SP markers; values glow cyan.
- Charts: dark trend grid; the main series has a soft glow (one blurred stroke under a sharp stroke); faceplates show PV/SP/OP bar graphs with mode badges.
- Signature effects: alarm blink at 1 Hz until acknowledged; "ACK" button; glow uses `MaskFilter.blur(BlurStyle.normal, 3)` on at most 8 strokes per frame (Low quality: no glow).

**T-3 Phosphor — "Green Screen CRT"** (M7)
- Palette: single hue. bg `#031A09`, bgAlt `#02140A`, surface `#06240F`, ink `#33FF66`, inkMuted `#1F9940`, inkFaint `#0E5223`, grid `#0B3D1A`, gridMajor `#12602A`, accent `#9CFFB5`, accent2 `#FFB000` (amber, used only for the selection cursor), steel `#33FF66`, liquidLight `#66FF99`, liquidHeavy `#1A8F3A`, froth `#9CFFB5`, vapor `#33FF66` at 40 %, hot/cold = ink at 100 %/60 %, ok `#33FF66`, warn `#FFB000`, alarm = inverse video (green block, black text) blinking, eqCurve `#33FF66`, opLine `#9CFFB5`, qLine `#9CFFB5` dotted, stepLine `#66FF99`, diagonal `#0E5223`, pseudoEq `#1F9940`.
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
- Palette: bg `#FBF8F1`, bgAlt `#F3EEE3`, surface `#FFFFFF`, ink `#1F2328`, inkMuted `#57606A`, inkFaint `#A8A29A`, grid `#E3DED3`, gridMajor `#CFC8BA`, accent `#2B6CB0`, accent2 `#C0392B` (red pen), steel `#1F2328`, liquidLight `#9CC9F5`, liquidHeavy `#2B6CB0`, froth `#D6E8FA`, vapor `#9AA0A6`, hot `#C0392B`, cold `#2B6CB0`, ok `#2E7D32`, warn `#B7791F`, alarm `#C0392B`, eqCurve `#1F2328`, opLine `#2B6CB0`, opLineCmo `#2B6CB0` dashed, qLine `#B7791F`, stepLine `#C0392B`, diagonal `#A8A29A`, pseudoEq `#57606A` dotted.
- Typography: "Source Serif 4" (text), "Source Sans 3" (UI), "STIX Two Math" (math and axis labels).
- Column: clean schematic like a textbook figure — thin black outline, light blue liquid, grey vapour.
- Charts: classic McCabe–Thiele as printed in textbooks: black equilibrium curve, blue operating lines, red staircase, stage numbers in small italics beside each step.
- Signature effects: figure captions under each diagram ("Figure 1 — Live McCabe–Thiele, benzene–toluene, Tier 2, t = 01:32:10"); margin notes for the selected tray; "Export figure" (PNG) button.

### 7.3 Performance rules for all themes

- Static layers (grids, textures, vessel outline, rivets) are painted once into a `RepaintBoundary` and invalidated only on resize or theme change.
- Animated layers repaint from a `ValueListenable<SimSnapshot>`; no widget rebuild per frame.
- At most 400 vapour particles on screen (High) / 120 (Low), pooled; positions advance on the UI clock.
- Blur/glow/bloom and scanline shaders are disabled on Low quality and when the measured frame time exceeds 14 ms for 2 s.
- No `saveLayer` per tray; one `saveLayer` per panel at most.

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

- Engine: PID library (velocity form, anti-windup, bumpless transfer), loops FC-101/102/103, LC-101/102 (switchable AUTO/MAN), valve and instrument models, faults F19–F20, alarms; scenario runner (JSON) with structured objectives, hints, events and scoring; sandbox save/load (JSON).
- App: Faceplates tab, Trends tab (rolling 2 h sim-time buffer, 1 point per 5 s), alarm banner and list, scenario list / briefing / debrief screens. Guided scenarios G1–G6 and G11–G12 (Tier 1 versions).
- Acceptance: VC-16 (controller tests) pass; all eight scenarios can be completed by following their hints; scenario JSON files validate against the schema test.

### M4 — Tier 2: ideal thermodynamics, energy balances, pressure

- Engine: component database (PHYSICS.md §3.1), vapour pressure models (Antoine, DIPPR-101, Lee–Kesler), Raoult K, bubble/dew/flash, enthalpy model, quasi-steady energy balance (vapour profile), overhead vapour inventory and pressure dynamics, condenser UA + cooling water, PC-101, kettle reboiler with steam-side heat-transfer limit, partial condenser, reflux subcooling, feed temperature input, runtime tier switching, TC-101 option; faults F08–F15.
- McCabe–Thiele upgrades: non-CMO actual operating locus, q from feed enthalpy, local-equilibrium band (top-to-bottom pressure), temperature profile chart.
- App: Control Room theme; energy panel (Q_C, Q_R, CW, steam); scenarios G7, G8; G11 upgraded to Tier 2.
- Acceptance: VC-10 (thermo spot values), VC-11 (Tier-2 MESH reference), VC-8 Tier-2 directions pass; energy closure ≤ 1×10⁻⁶ relative at steady state; switching T1 ↔ T2 at steady state causes no NaN and no step larger than 5 % in any flow.

### M5 — Tier 3 (NRTL) and azeotropic binaries

- Engine: NRTL activity model, presets methanol–water, ethanol–water, acetone–chloroform, isobutane–n-butane (DePriester K, PHYSICS.md §3.4), azeotrope finder, T-x-y data.
- App: Paper theme; T-x-y / x-y tab; scenarios G9, G10.
- Acceptance: VC-10 azeotrope and VLE checks pass; Tier 3 ethanol–water column cannot exceed the azeotrope composition in the distillate (VC-8).

### M6 — Thermosyphon reboiler and hidden-fault drills

- Engine: thermosyphon loop model with instability index and oscillator (PHYSICS.md §8.3); faults F16–F18; hidden-fault framework (seeded random fault draw and onset, diagnosis submission, scoring); measurement noise.
- App: Equipment tab for the reboiler (loop schematic, circulation, exit quality, I_s gauge); Drill HUD and Diagnose dialog; drills H1–H5; scenario G14.
- Acceptance: VC-14 (thermosyphon map) passes; each drill's injected fault produces its listed key evidence (automated symptom tests per drill in VALIDATION.md §H).

### M7 — Multicomponent light hydrocarbons

- Engine: hydrocarbon components C3–nC7 (PHYSICS.md §3.1), Tier 1 multicomponent constant α, Tier 2 Raoult with Lee–Kesler, Tier 3 DePriester (McWilliams); debutanizer and depropanizer presets; key components; FUG shortcut module (Fenske, Underwood, Gilliland/Molokanov, Kirkbride) computed live; Hengstebeck pseudo-binary McCabe–Thiele.
- App: Phosphor theme; Products tab with the FUG panel; component profile chart; scenario G13; drill H6.
- Acceptance: VC-9 (FUG numbers and rigorous-vs-shortcut check) passes; 40 trays × 8 components Tier 3 runs at ≥ 100× on the reference phone (VC-19).

### M8 — Packed sections

- Engine: packing database, packed-section segmentation by HETP, holdup, Robbins ΔP, Kister–Gill flood, HETP modifiers (wetting, loading), parallel-column maldistribution, faults F21–F23; mixed tray/packed columns.
- App: packed-bed rendering (texture, wetting, liquid rivulets), scenario G15, drill H7.
- Acceptance: VC-13 passes.

### M9 — Crude fractionation

- Engine: assay → pseudo-components (PHYSICS.md §9), crude thermo with steam, crude column topology (main column, three 2-stage side strippers, pumparound, bottom and stripper steam), product property calculations (TBP, D86 via Daubert, 5–95 gaps), crude control scheme, faults F24–F27.
- App: Brass theme; crude flowsheet in ColumnView; Products tab with TBP/D86 curves and gap bars; scenario G16; drill H8.
- Acceptance: VC-15 (pseudo-component properties, D86 conversion, crude plausibility) passes.

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

## 10. Open items for the user (not blocking)

These have defaults; the user may override them later.

1. Crude assay: LowSYS ships a synthetic ~32 °API light crude (PHYSICS.md §9.1). If the user has a specific assay they care about, it can be added as a second preset.
2. Hidden-fault drills use measurement noise by default. If the user finds noise frustrating on a phone, it can default to off.
