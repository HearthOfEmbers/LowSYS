// VALIDATION.md numbers for the M4 cases (VC-10, VC-11, VC-27, VC-8.7/8.9,
// VC-16.6) and the PHYSICS.md §7.2 / §8.2 / §13.5 claims, transcribed once.
library;

/// VC-10.1 normal boiling points from the vapour-pressure models (°C).
const vc101 = [
  ('benzene', 80.100),
  ('toluene', 110.625),
  ('methanol', 64.504),
  ('ethanol', 78.298),
  ('acetone', 56.287),
  ('chloroform', 61.737),
  ('water', 100.018),
];

/// VC-10.2 water.
const vc102 = (
  psat25: 3170.4,
  psat150: 475089.0,
  tsatBarG: [(1.0, 120.48), (3.5, 148.10), (10.0, 184.21), (20.0, 214.99)]
);

/// VC-10.3 B-T bubble points at 1 atm: x, T °C, y, α.
const vc103 = [
  (0.0, 110.625, 0.00000, 2.3481),
  (0.1, 106.136, 0.20919, 2.3807),
  (0.2, 102.103, 0.37609, 2.4112),
  (0.3, 98.457, 0.51115, 2.4398),
  (0.4, 95.142, 0.62185, 2.4667),
  (0.5, 92.112, 0.71363, 2.4920),
  (0.6, 89.328, 0.79054, 2.5160),
  (0.7, 86.760, 0.85557, 2.5388),
  (0.8, 84.380, 0.91105, 2.5604),
  (0.9, 82.166, 0.95873, 2.5811),
  (1.0, 80.100, 1.00000, 2.6007),
];
const vc103Pressure = [
  (0.5e5, 69.824, 2.7053),
  (2.0e5, 117.011, 2.3040),
  (3.0e5, 133.814, 2.1993)
];

/// VC-10.7 property spot values.
const vc107 = (
  rhoBenzene80: 816.4,
  rhoToluene110: 779.9,
  rhoWater100: 958.4,
  zBenzeneSat: 0.9661,
  watsonBenzene298: 33.58,
);

/// VC-11 Tier-2 B-T steady state (E = 1, L0 100, D 50, 1 atm).
const vc11 = (
  qR: 1301.477,
  xD: 0.994946,
  xB: 0.005054,
  tD: 80.201,
  tB: 110.386,
  qC: 1281.2,
  v1: 150.000,
  vB: 141.118,
  l10: 193.183,
);

/// VC-11 profile: stage, x, T °C, V leaving, L leaving (NaN where absent).
const vc11Profile = [
  (1, 0.98697, 80.361, 150.000, 99.845),
  (5, 0.86543, 82.914, 148.560, 97.706),
  (9, 0.55287, 90.612, 144.557, 93.786),
  (10, 0.49166, 92.355, 143.786, 193.183),
  (11, 0.44108, 93.865, 143.183, 192.406),
  (15, 0.14427, 104.298, 140.454, 190.394),
  (20, 0.01003, 110.152, 141.036, 191.118),
  (21, 0.00505, 110.386, 141.118, double.nan),
];

/// VC-11 further references: (name, l0, feedTray, d, xD, xB, qR kW, qC kW).
const vc11Further = [
  ('L0 150', 150.0, 10, 50.0, 0.998569, 0.001431, 1727.7, 1707.1),
  ('feed tray 5', 100.0, 5, 50.0, 0.971465, 0.028535, 1305.3, double.nan),
  ('D 55', 100.0, 10, 55.0, 0.908433, 0.000804, 1362.4, double.nan),
];

/// VC-27.1 methanol–water preset (Raoult, E 0.7, feed 12, z 0.3, L0 60).
const vc271 = (
  d: 30.00,
  qR: 890.4,
  xD: 0.98873,
  xB: 0.00481,
  tD: 64.72,
  tB: 99.68,
  v1: 90.00,
  vB: 78.95,
  l1: 59.83,
  l19: 149.06,
  qC: 882.1,
  uaCond: 29.76,
  uaReb: 30.65,
  tier1Xd: 0.99046,
  tier1Xb: 0.00407,
);

/// VC-27.2 B-T pressure sweep at L0 100, D 50, E 0.7: P bar(a), Q_R, xD, xB, T_D, T_B, α feed tray.
/// Re-pinned 2026-10-12 (perfect condenser, P held exactly); tolerances
/// Q_R ± 0.3 %, x ± 2e-4, T ± 0.05 K, α ± 0.002.
const vc272 = [
  (0.50, 1349.6, 0.98766, 0.01234, 59.02, 86.94, 2.707),
  (0.70, 1328.6, 0.98374, 0.01627, 68.86, 97.35, 2.601),
  (1.01325, 1303.1, 0.97808, 0.02193, 80.54, 109.60, 2.491),
  (2.00, 1247.7, 0.96299, 0.03700, 104.75, 134.66, 2.302),
  (3.00, 1207.6, 0.95067, 0.04932, 121.19, 151.45, 2.197),
];

/// VC-27.3 utility limits (kW), re-pinned with 27.2: P, reboiler max at 3.5 bar(g), at 10 bar(g), condenser max CW 30 °C, CW 15 °C.
const vc273 = [
  (0.50, 3516.0, 5593.0, 799.0, 1212.0),
  (0.70, 2918.0, 4995.0, 1070.0, 1483.0),
  (1.01325, 2214.0, 4290.0, 1391.0, 1804.0),
  (2.00, 772.0, 2849.0, 2058.0, 2471.0),
  (3.00, double.nan, 1884.0, 2510.0, 2923.0),
];

/// VC-16.6c flash stability (VALIDATION.md, re-pinned 2026-10-12): CW OP
/// from the design 50 % to 100 % at the VC-11 state gives 0.906 ± 0.005
/// bar(a): with UA 29.9 kW/K the condenser needs T_sat ≈ 76.5 °C for
/// ≈ 1281 kW. The v1.0 0.966 bar(a) belonged to the UA 28.5 kW/K design.
const vc166c = (pBar: 0.906, tol: 0.005);

/// Condenser design (PHYSICS.md §7.2): UA 29.9 kW/K at 50 % CW, outlet 44.7 °C.
const condenserDesign = (
  qC: 1281.2,
  tCond: 80.201,
  tCwIn: 30.0,
  mCwMax: 41.54,
  opPct: 50.0,
  ua: 29.9,
  tOut: 44.7
);

/// Reboiler design (§8.2): UA_R 57.5 kW/K, 60 % of Q_max with 3.5 bar(g) steam.
const reboilerDesign = (ua: 57.5, tSt: 148.10, qDesign: 1300.0, fraction: 0.60);

/// VC-16.6 PC-101 (Kc 10, Ti 120 s): open-loop CW OP 50→40 % gives +5.8 kPa with t63 150–230 s;
/// ±10 kPa SP steps settle within ±1 kPa in < 600 s (proto 297/438 s), no overshoot.
const pc101 = (
  kc: 10.0,
  ti: 120.0,
  openLoopGainKpaPer10Pct: 5.8,
  openLoopT63: 190.0,
  settleMax: 600.0,
  settlePlus: 297.0,
  settleMinus: 438.0
);

/// VC-8.9 tier switch: V1 kept → V_B 150 → ≈ 141.9; keeping V_B instead would raise V1 by +4.3 %.
const vc89 = (
  vBAfterSwitch: 141.9,
  v1GrowthIfVbKept: 0.043,
  xDNewSteady: 0.97838,
  dNewSteady: 49.96
);

/// F15 (§11): s = 0.5 → 3.16 bar(a), 135.4 °C, Q_max 1437 kW; limit at s ≈ 0.58; s = 0.7 → 2.62 bar(a), 129.0 °C, ≈ 1070; s = 1 → 1.81, 117.1, 384.
/// The Q_max figures use T_B = 110.4 °C, i.e. the VC-11 design point (E = 1,
/// the point §8.2 sizes UA_R at), not the E = 0.7 default (T_B 109.6 °C).
const f15 = [
  (0.5, 3.16, 135.4, 1437.0),
  (0.7, 2.62, 129.0, 1070.0),
  (1.0, 1.81, 117.1, 384.0)
];
const f15LimitS = 0.58;

/// F11 at s = 1 (PHYSICS.md §11 and VALIDATION.md H2, restated 2026-10-12
/// as a transient): ≈ 10 mol inert/h into the 104-mol overhead at 1 atm;
/// PC-101 opens the CW valve, which saturates within 30 min (engine ≈ 17
/// min); then P rises. At 1 h: P ≈ 139 kPa, y_I ≈ 0.072, f_blanket ≈ 0.22,
/// extra subcooling ≈ 4.3 K; H2 asks for ≥ 3 K within 1 h.
const f11 = (
  inertPerHour: 10.0,
  overheadMol: 104.0,
  tSatMax: 1800.0,
  pTop1h: 139000.0,
  yI1h: 0.072,
  fBlanket1h: 0.22,
  subcool1h: 4.3,
  subcoolMinH2: 3.0
);
