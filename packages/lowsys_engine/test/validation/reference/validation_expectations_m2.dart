// VALIDATION.md numbers for the M2 cases (VC-12, VC-17), transcribed once.
library;

/// VC-12.1 geometry.
const vc121 = (aT: 1.1310, aA: 0.8595, aN: 0.9953, lW: 0.9171);

/// VC-12.2 Lygeros–Magoulas C_SB (TS mm, F_LV, C_SB m/s).
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

const vc123 = (
  xD: 0.96725,
  xB: 0.00839,
  d: 51.27,
  columnDpKpa: 14.68,
  trays: [
    Vc123Tray(1, 0.666, 0.0125, 0.0403, 1.687, 21.1, 0.286, 472, 645),
    Vc123Tray(
        15, 0.804, 0.0194, 0.0832, 1.804, 23.7, double.nan, double.nan, 798),
    Vc123Tray(20, 0.832, 0.0246, double.nan, double.nan, 23.1, double.nan,
        double.nan, 829),
  ],
  dcBackupTray15M: 0.131,
  dcBackupTray15Frac: 0.40,
);

/// VC-12.4 "must hold" assertions (the prototype numbers are informative).
class Vc124Case {
  final String name;
  final double loadFactor; // L0, VB and F multiplier (1.2 = +20 %)
  final bool entrainment;
  final double
      dpRatioMin; // column ΔP after 10 min ≥ ratio × base (0 = not tested)
  final double? xD4hMax, xD4hMin;
  final double? weepMin, weepMax;
  final double protoDp10, protoXd4h;
  const Vc124Case(this.name, this.loadFactor,
      {this.entrainment = true,
      this.dpRatioMin = 0,
      this.xD4hMax,
      this.xD4hMin,
      this.weepMin,
      this.weepMax,
      this.protoDp10 = double.nan,
      this.protoXd4h = double.nan});
}

const vc124Loads = [
  Vc124Case('Load +20 %', 1.2,
      dpRatioMin: 1.25, xD4hMax: 0.94, protoDp10: 19.62, protoXd4h: 0.9124),
  Vc124Case('Load +20 %, entrainment off', 1.2,
      entrainment: false, xD4hMin: 0.98, protoDp10: 19.03, protoXd4h: 0.9886),
  Vc124Case('Load +30 %', 1.3,
      dpRatioMin: 1.45, xD4hMax: 0.88, protoDp10: 22.79, protoXd4h: 0.8364),
  Vc124Case('Load +45 %', 1.45,
      dpRatioMin: 1.8, xD4hMax: 0.6, protoDp10: 28.90, protoXd4h: 0.497),
  Vc124Case('Turndown 50 %', 0.5,
      weepMin: 0.0, weepMax: 0.2, protoXd4h: 0.9783),
  Vc124Case('Turndown 35 %', 0.35, weepMin: 0.3, protoXd4h: 0.9647),
];

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
