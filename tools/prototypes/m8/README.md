# M8 packed-section prototype (physics lead, readiness pass 2026-10-13)

`pk.dart` holds the PHYSICS.md §6 correlations (Robbins, Kister–Gill, flood bisection, holdup, Onda wetting, HETP, Lewis, Kremser maldistribution), the B-T Tier-2 thermo (Antoine Raoult, §3.3 enthalpies, §3.5 properties) and an independent steady-state column solver. Its stages are sieve trays (fixed Murphree E) or packed segments, whose E and ΔP are coupled by fixed-point iteration. It reproduces VC-4.1 (0.981183) and every v1.0 VC-13 number.

Scripts:
- `vc13.dart`: the VC-13.1–13.3 and 13.7 unit values.
- `g15.dart`: `bt_packed` Tier 1, G15, the mixed template and the VC-13.4 steps.
- `h7.dart`: `bt_packed` Tier 2 and the H7 column with F21/F23; `dart run h7.dart design` gives the diameter scan.
- `h7b.dart`: H7 extras.

Run from this folder with `dart run <script>.dart` (pure Dart, no packages). It is a reference for re-derivation, not engine code. It has no carry-over above flood, so rows past φ_p = 1 are bounds.
