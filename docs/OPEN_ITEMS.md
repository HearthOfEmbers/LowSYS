# Open spec items (for the physics lead)

Collected by the lead from validation passes. Fix in the docs, then delete the item.

## For coder

- **M4 doc fix, no requirement change (2026-10-12).** PHYSICS.md §13.5: the "Why the top vapour" paragraph had been inserted inside the switch table, which left the T2 ↔ T3 row orphaned below it. The rows are now together and the paragraph follows the table. The T1 ↔ T2 rules are unchanged.
- **M5: PC-101 at low CW flow (VALIDATION.md VC-28.8).** A G9 learner who turns the feed down at 1 atm parks the CW valve near 9 % open. There the condenser gain dQ/dm_cw is about 10 times the B-T design value. If PC-101 oscillates on that path, report it here with the trend. Do not retune PC-101 globally: the fix (gain scheduling or a G9-only tuning override) needs a physics decision.
- **M5: G9/G10 time limits** (ENGINE_API.md §11.8: 172 800 s / 86 400 s) are estimates. The prototype holds P and does not give settling times, so VC-28.8 records the actual times to steady state. Raise an item here if a hint path takes longer than half the limit.

## For the physics lead

- **VC-28.1 x_B.** The [P] value is 0.012590 / T_B 96.496 °C. A re-run of the independent Newton MESH solve during the M5 pass gave 0.012564 / 96.502 °C, which is inside the 2×10⁻⁴ tolerance. The likely cause is a difference in feed temperature or ΔP handling between the two prototypes. Reconcile it once the engine's number exists.
- **Prototype provenance.** The M5 [I] numbers (VC-10.9, VC-28.3 Tier 3, VC-28.7, §11.8 G9/G10) come from a binary MESH Newton solver with a numerical Jacobian, with P held and the same ideal enthalpies as Tier 2. It is not in the repo. If it should be kept for re-derivation, add it under `tools/` (owner decision, not the coder's).
