// VALIDATION.md numbers for the M2 cases (VC-8.15/8.16, VC-12, VC-17),
// transcribed once. v1.1 (2026-10-12): default tray spacing 0.90 m.
library;

/// Default tray spacing of the v1.1 B-T preset (m); v1.0 used 0.6.
const double trayPitchV11 = 0.9;
const double trayPitchV10 = 0.6;

/// VC-12.1 geometry (independent of TS).
const vc121 = (aT: 1.1310, aA: 0.8595, aN: 0.9953, lW: 0.9171);

/// VC-12.2 Lygeros–Magoulas C_SB (TS mm, F_LV, C_SB m/s) — at fixed TS.
const vc122Csb = [
  (600.0, 0.04, 0.10279),
  (600.0, 0.0803, 0.09590),
  (610.0, 0.1, 0.09395)
];

/// Bennett at K_s = 0.06, h_w = 0.05.
const vc122Bennett = (alphaE: 0.37909, c: 0.50145);

/// Entrainment fit (F_LV, φ, ψ).
const vc122Psi = [
  (0.1, 0.9, 0.03416),
  (0.1, 1.0, 0.07232),
  (0.01, 0.5, 0.01150),
  (0.01, 0.95, 0.33605)
];

/// Weep map (Φ, w).
const vc122Weep = [(0.75, 0.0), (0.60, 0.273), (0.20, 1.0)];

/// VC-12.3 design-point steady state (full hydraulics) [P].
class Vc123Tray {
  final int tray;
  final double phi, psi, fLv, stability, hClMm, alphaE, dpDry, dp;
  const Vc123Tray(this.tray, this.phi, this.psi, this.fLv, this.stability,
      this.hClMm, this.alphaE, this.dpDry, this.dp);
}

class Vc123 {
  final double ts, xD, xB, d, columnDpKpa, maxFloodPct;
  final List<Vc123Tray> trays;
  final double dcBackupTray15M, dcBackupTray15Frac, dcLimitM;
  const Vc123({
    required this.ts,
    required this.xD,
    required this.xB,
    required this.d,
    required this.columnDpKpa,
    required this.maxFloodPct,
    required this.trays,
    required this.dcBackupTray15M,
    required this.dcBackupTray15Frac,
    required this.dcLimitM,
  });
}

/// v1.1 default (TS 0.9 m).
const vc123 = Vc123(
  ts: 0.9,
  xD: 0.97826,
  xB: 0.01459,
  d: 50.37,
  columnDpKpa: 14.49,
  maxFloodPct: 62.9,
  trays: [
    Vc123Tray(1, 0.503, 0.0037, 0.0403, 1.681, 21.2, 0.287, 470, 642),
    Vc123Tray(
        15, 0.599, 0.0042, 0.0832, 1.772, 23.8, double.nan, double.nan, 781),
    Vc123Tray(20, 0.629, 0.0053, double.nan, double.nan, 23.2, double.nan,
        double.nan, 827),
  ],
  dcBackupTray15M: 0.128,
  dcBackupTray15Frac: 0.27,
  dcLimitM: 0.475,
);

/// v1.0 (TS 0.6 m), kept as a second check of the same harness.
const vc123v10 = Vc123(
  ts: 0.6,
  xD: 0.96725,
  xB: 0.00839,
  d: 51.27,
  columnDpKpa: 14.68,
  maxFloodPct: 83.2,
  trays: [
    Vc123Tray(1, 0.666, 0.0125, 0.0403, 1.687, 21.1, 0.286, 472, 645),
    Vc123Tray(
        15, 0.804, 0.0194, 0.0832, 1.804, 23.7, double.nan, double.nan, 798),
    Vc123Tray(20, 0.832, 0.0246, double.nan, double.nan, 23.1, double.nan,
        double.nan, 829),
  ],
  dcBackupTray15M: 0.131,
  dcBackupTray15Frac: 0.40,
  dcLimitM: 0.325,
);

/// VC-8.15 / 8.16 full-hydraulics direction checks [P] (TS 0.9).
const vc815 = (
  xD0: 0.97826,
  xD10: 0.98001,
  xB0: 0.01459,
  xB10: 0.00997,
  flood0: 62.9,
  flood10: 67.1
);
const vc815Further = [
  (20.0, 0.9796, 71.0),
  (30.0, 0.9767, 75.0),
  (40.0, 0.9709, 80.0)
];
const vc816 = [
  (0.0, 0.9810),
  (10.0, 0.9843),
  (20.0, 0.9866),
  (30.0, 0.9883),
  (40.0, 0.9896)
];

/// VC-12.4 load rows (v1.1). "Load +x %": F fixed, L0 and V_B each + x·150.
class Vc124Load {
  final String name;
  final double fraction; // + x of 150 kmol/h on L0 and V_B (0.2 = +20 %)
  final bool entrainment;
  final double dpRatioMin;
  final double? xD4hMax, xD4hExact, xD4hTol;
  final bool xBBelowBase, floodAlarm, noFloodAlarm, maxFlood100;
  final double protoDp10, protoDp4h, protoXd4h, protoFlood4h;
  const Vc124Load(this.name, this.fraction,
      {this.entrainment = true,
      this.dpRatioMin = 0,
      this.xD4hMax,
      this.xD4hExact,
      this.xD4hTol,
      this.xBBelowBase = false,
      this.floodAlarm = false,
      this.noFloodAlarm = false,
      this.maxFlood100 = false,
      this.protoDp10 = double.nan,
      this.protoDp4h = double.nan,
      this.protoXd4h = double.nan,
      this.protoFlood4h = double.nan});
}

const vc124Loads = [
  Vc124Load('Load +20 %', 0.2,
      dpRatioMin: 1.25,
      xBBelowBase: true,
      noFloodAlarm: true,
      protoDp10: 18.93,
      protoDp4h: 19.29,
      protoXd4h: 0.9768,
      protoFlood4h: 75),
  Vc124Load('Load +20 %, entrainment off', 0.2,
      entrainment: false,
      xD4hExact: 0.9886,
      xD4hTol: 0.001,
      protoDp10: 18.69,
      protoXd4h: 0.9886),
  Vc124Load('Load +30 %', 0.3,
      dpRatioMin: 1.45,
      protoDp10: 21.56,
      protoDp4h: 22.25,
      protoXd4h: 0.9668,
      protoFlood4h: 82),
  Vc124Load('Load +45 %', 0.45,
      dpRatioMin: 1.8,
      xD4hMax: 0.95,
      floodAlarm: true,
      protoDp10: 26.22,
      protoDp4h: 27.29,
      protoXd4h: 0.9356),
  Vc124Load('Load +60 % (flood onset)', 0.6,
      xD4hMax: 0.90,
      maxFlood100: true,
      protoDp10: 32.09,
      protoDp4h: 33.07,
      protoXd4h: 0.8703,
      protoFlood4h: 101),
  Vc124Load('Load +75 %', 0.75,
      dpRatioMin: 2.5,
      xD4hMax: 0.80,
      protoDp10: 38.99,
      protoDp4h: 39.67,
      protoXd4h: 0.7323),
];

/// VC-12.4 turndown rows (F, L0, V_B × factor).
const vc124Turndown = [
  (
    0.5,
    0.09,
    0.9788,
    0.0192,
    0.9804,
    0.0174
  ), // factor, w, xD, xB, xD no-weep, xB no-weep
  (0.35, 0.51, 0.9653, 0.0313, 0.9788, 0.0155),
];

/// VC-12.4 foaming rows: severity, SF, φ_dc, max φ at 10 min, xD 4 h, ΔP 4 h.
const vc124Foam = [
  (0.33, 0.85, 0.433, 0.74, 0.9746, 14.18),
  (0.67, 0.70, 0.367, 0.90, 0.9564, 14.01),
  (1.0, 0.55, 0.30, 1.16, 0.8171, 14.25),
];

/// VC-12.4 fouling rows (holes, trays 12–16): severity, ΔP 10 min (kPa), ratio.
const vc124FoulHoles = [
  (0.3, 16.58, 1.14),
  (0.6, 22.20, 1.53),
  (0.8, 57.5, 3.97)
];
const vc124FoulDc = (dp10: 27.97, ratio: 1.93, dc: 5, sump: 20.0);

/// VC-17 unit conversions.
const vc17 = (
  tK: 373.15,
  tC: 100.0,
  tF: 212.0,
  pPa: 101325.0,
  pBar: 1.01325,
  pPsia: 14.6959,
  molFlowSi: 1.0,
  kmolh: 3.6,
  lbmolh: 7.93664,
  wSi: 1e6,
  kw: 1000.0,
  mmbtuh: 3.41214,
  crudeM3h: 132.5,
  bblD: 20001.6,
  bbl20000InM3h: 132.489,
  lenM: 0.0254,
  mm: 25.4,
  inch: 1.0,
  rho: 800.0,
  lbft3: 49.942,
  dT: 10.0,
  dF: 18.0,
);
