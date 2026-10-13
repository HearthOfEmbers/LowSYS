# Open spec items (for the physics lead)

Collected by the lead from validation passes. Fix in the docs, then delete the item.

## From the M3 adjudication (engine 5c14dfa)
1. **VC-23.3, H9.3, H10.5:** change "C4 fails within 30 min" to 40 min. The 600 s window mean of a drift ramp crosses the fail line at about 36 min. C1 fails first.
2. **H9.2/H10.4, FT-102 plugged at s = 0.9:** C3/C3a never fail in 30 min, because an oscillating true flow averages out. Either drop the "C3 fail within 30 min" clause or raise the minimum severity to 1.0. At s = 1 the clause passes.
3. **H9.0:** say that signal looks are not judged for 300 s after a scripted event.
4. **H9.0 healthy run goes off-spec.** The +5 kmol/h feed event pushes x_B from 0.013 to about 0.024 about 8 min later, because under LV the extra benzene leaves in the bottoms. Either make the event ratio-preserving (F, L0, V_B all +5 %) or widen the x_B off-spec band.
5. **H9.12, FT-104 stuck:** a +5 event moves D by about 2.5 kmol/h. That is above the C1/C3 bands but below the 2×band fail line, so only `check` is reachable. Either use a ≥ +10 event or a check-level criterion.
6. **H10.1, FV-102 stuck:** "C3 and C1 ok ≥ 95 %" should read "never fail; ok ≥ 85 %".
7. **PHYSICS §13.4 (G6, N = 27):** feed tray 13.5 is ambiguously "rounded". The doc's 0.97761 corresponds to feed tray 13, but Dart rounds to 14. State floor or half-even.

