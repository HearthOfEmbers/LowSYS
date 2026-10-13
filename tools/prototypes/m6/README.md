# M6 thermosyphon loop prototype (physics lead, readiness pass 2026-10-13)
`ts.dart` implements PHYSICS.md §8.3 as a standalone loop; `vc14.dart`, `sweep.dart`, `h5.dart` and `g14*.dart` produced VC-14, the H5 rows and G14 (§11.8); `an.dart`, `stress.dart`, `jit.dart` are robustness checks.
Run from this folder with `dart run vc14.dart` (pure Dart, no packages); it is a reference for re-derivation, not engine code.
