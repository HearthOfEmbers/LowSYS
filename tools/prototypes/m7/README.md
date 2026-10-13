# M7 light-hydrocarbon prototype (physics lead, readiness pass 2026-10-13)
`hc.dart` holds PHYSICS.md §2.1/§2.2/§3.3/§3.4.2 thermo, an independent steady-state column solver (bubble-point method with Murphree; reproduces VC-4.1) and the §14.3 FUG; the scripts print VC-9.1–9.8 and the §H H6 values (`vc9`, `dew_check`, `col`, `design`, `refs`, `extra`, `final`).
Run from this folder with `dart run refs.dart` (pure Dart, no packages); it is a reference for re-derivation, not engine code.
