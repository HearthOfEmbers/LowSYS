# M9 crude prototype (physics lead, readiness pass 2026-10-13)

`crude.dart` holds PHYSICS.md §9.1 and §9.6:
- the assay and pseudo-components (Riazi–Daubert, Lee–Kesler ω and latent heat, Watson–Nelson Cp);
- the M9 enthalpy rule (T_b reference, Fallon–Watson vapour Cp; water as vapour only);
- the bubble point at the hydrocarbon partial pressure, and the feed flash;
- the product TBP with the 1 % tail trim, and Daubert's TBP → D86.

`column.dart` is an independent steady-state solver for the crude column of §9.2–9.7:
- 30 theoretical stages, three 2-stage strippers with product-rate draws, one pumparound with the cooler limit, bottom and stripper steam, TC-301 on the reflux, and the valve-tray ΔP and jet flood of §5.
- Its main solver is an engine-like dynamic relaxation: weir holdups, (4.6) bottom-up, an implicit component step, and the ỹ_w filter. `polish()` runs a Wang–Henke bubble-point iteration (simultaneous mass + energy flow solve) from the result as a cross-check. The two agree to 1×10⁻⁴ K.
- A cold start takes about 5 s on a desktop.

Scripts (each prints what the docs quote):
- `vc15.dart`: VC-15.1–15.3, the enthalpy comparison behind the M9 rule, and the lumped ideal cuts.
- `base.dart [bp] [nohyd]`: the default steady state with the stage profile (PHYSICS.md §9.8, VC-15.4); `bp` adds the cross-check.
- `cases.dart steady|transient|f27`: the VC-15.4 direction checks; F24–F26 as steady states and as transients from the default; the F27 lever cases.
- `h8.dart`: the H8 candidates at the middle of their ranges (VALIDATION.md §H).
- `g16.dart`: G16 lever combinations (VC-15.6).
- `scan.dart cot|steam|ptop|pa|top|kero|ss|grid|cot345`: lever scans.
- `trim.dart`: the product D86 against the TBP tail trim (0 / 0.1 / 0.5 / 1 %).
- `misc.dart`: the drum bubble point, feed rates, H − h ranges, the stage-30 loop gain, and the PA limit.

Run from this folder with `dart run <script>.dart` (pure Dart, no packages). It is a reference for re-derivation, not engine code.
- It has no entrainment or weeping.
- Its tray holdups use a fixed froth density.
- Its side operations are coupled implicitly.
- So its transients are indicative only; its steady states are exact for the model.
