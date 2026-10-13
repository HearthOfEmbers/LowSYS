// VALIDATION.md numbers for the M3 cases (VC-16, VC-20.3, VC-22, VC-23,
// VC-25) and the PHYSICS.md §10 claims, transcribed once.
library;

/// VC-16.1: Kc 2, Ti 10, h 1, direct, OP0 50; PV 50→51.
const vc161 =
    (op1: 52.2, op10: 54.0, opBack: 52.0, rebasedOp1: 50.2, rebasedOp10: 52.0);

/// VC-16.1b: Kc 1, Ti ∞, Td 8 (τ_f 1), PV = 50 + k.
const vc161bDirect = [55.0, 58.0, 60.0, 61.5, 62.75, 63.875];
const vc161bReverse = [45.0, 42.0, 40.0, 38.5, 37.25, 36.125];

/// VC-16.2 anti-windup.
const vc162 = (
  op1: 61.0,
  op39: 99.0,
  op40: 100.0,
  opAfterDrop1: 88.9,
  opAfterDrop2: 88.8
);

/// VC-16.4 flow loop, SP 100 → 110 kmol/h.
const vc164Times = [0.5, 1.0, 2.0, 3.0, 5.0, 10.0, 20.0];
const vc164TrueFlow = [
  101.186,
  102.566,
  104.820,
  106.432,
  108.323,
  109.748,
  109.994
];
const vc164 = (
  pv3s: 105.615,
  op1s: 35.986,
  opFinal: 36.667,
  t63True: 3.0,
  t63Meas: 3.5,
  within1pct: 12.5
);
const vc164MeansDt05 = [
  100.596,
  102.026,
  103.308,
  104.418,
  105.359,
  106.149,
  106.808,
  107.357
];
const vc164MeansDt2 = [102.587, 106.418, 108.315, 109.210];

/// VC-16.9.
const vc169 =
    (stuckKick: 2.1, stuckRate: 1.0, stuckSatTime: 64.7, failOpenT63: 2.1);

/// VC-20.3 PRNG vectors.
const vc203 = (
  fnvEmpty: 2166136261,
  fnvA: 3826002220,
  fnvFt102: 1498766031,
  next32: [3793846675, 4233283444, 1026389867, 4162901922],
  uniform: 0.883323766184137,
  normal1: -0.6076328127833632,
  normal2: -0.42066679512424215,
  drillUniform1: 0.041090393331688735,
  drillUniform2: 0.8835882459215075,
);

/// VC-22.1 FT-102 4–20 mA table: (true kmol/h, mA, v_meas, quality).
const vc221 = [
  (100.0, 9.33333, 100.000, 'GOOD'),
  (300.0, 20.0, 300.000, 'GOOD'),
  (305.0, 20.2667, 305.000, 'UNCERTAIN'),
  (320.0, 20.5, 309.375, 'UNCERTAIN'),
  (-20.0, 3.8, -3.750, 'UNCERTAIN'),
];
const vc221LossLow = (3.6, -7.5);
const vc221LossHigh = (21.0, 318.75);

/// VC-22.2 σ_disp per type and the prototype measured values.
const vc222 = [
  ('FT', 0.409, 0.404, double.nan),
  ('LT drum', 0.423, 0.418, 0.408),
  ('LT sump', 0.775, 0.761, 0.748),
  ('PT', 0.046, 0.0445, 0.0446),
  ('PDT', 0.845, 0.835, 0.815),
  ('TI', 0.062, 0.0624, 0.0610),
];

/// VC-22.5 plugged fractions (s → fraction of a step shown 600 s after it).
const vc225Plugged = [(1.0, 0.058), (0.9, 0.140), (0.75, 0.451), (0.5, 0.998)];
const vc225Spikes = (s1: 180, s1Tol: 40, s05: 90, s05Tol: 28);
const vc225Coated = (t63: 100.5, healthyT63: 10.5, sigmaRatio: 0.52);
const vc225Analyser = [
  (1299.5, 0.0200),
  (1300.0, 0.0204),
  (1600.0, 0.0697),
  (1900.0, 0.0700)
];

/// VC-22.6 field gauge: σ of N(0, 1 %) + 2 % graduation rounding.
const vc226Sigma = 1.15;

/// VC-25.1 chatter.
const vc251 = (
  maxRaisesAtLimit: 4,
  protoAtLimit: '1–2',
  unfilteredAbout: 200,
  maxRaisesInsideDeadband: 15
);

/// VC-26.3 scores.
const vc263 = (guided: 64, drill: 96, drillNever: 20);

/// VC-26.4 G6 (B-T Tier 1, E 0.5, L0 100, V_B 150): (N, feed tray, xD).
/// The feed tray is the one a rebuild from 20 / 10 gives under PHYSICS.md
/// §13.4 (floor(φ N' + 1e-9), φ = 0.5; spec decision 2026-10-12 #7).
const vc264G6 = [(28, 14, 0.98056), (27, 13, 0.97761)];
