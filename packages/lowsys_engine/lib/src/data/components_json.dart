/// Named component data, PHYSICS.md 2.1 and 2.2 (SI: Pa, K, J/mol, kg/m3). The 14 named components of the
/// component database (M4); crude pseudo-components arrive with M9.
const String componentsJson = r'''
{
  "benzene": {
    "name": "Benzene", "mw": 78.11, "tb": 353.24, "tc": 562.05, "pc": 4895000.0, "omega": 0.210,
    "dHvapTb": 30720.0, "cp0": 135.69, "dCp": 0.22, "rhoRef": 873.6, "tRef": 298.15, "sigmaRef": 0.0282,
    "vpKind": "antoineLog10MmHgC", "vpCoeffs": [6.90565, 1211.033, 220.790]
  },
  "toluene": {
    "name": "Toluene", "mw": 92.14, "tb": 383.78, "tc": 591.75, "pc": 4108000.0, "omega": 0.264,
    "dHvapTb": 33180.0, "cp0": 157.29, "dCp": 0.26, "rhoRef": 862.3, "tRef": 298.15, "sigmaRef": 0.0279,
    "vpKind": "antoineLog10MmHgC", "vpCoeffs": [6.95464, 1344.800, 219.482]
  },
  "methanol": {
    "name": "Methanol", "mw": 32.04, "tb": 337.69, "tc": 512.50, "pc": 8084000.0, "omega": 0.565,
    "dHvapTb": 35210.0, "cp0": 81.1, "dCp": 0.25, "rhoRef": 786.6, "tRef": 298.15, "sigmaRef": 0.0221,
    "vpKind": "antoineLog10MmHgC", "vpCoeffs": [8.07240, 1574.990, 238.870]
  },
  "ethanol": {
    "name": "Ethanol", "mw": 46.07, "tb": 351.44, "tc": 514.00, "pc": 6137000.0, "omega": 0.644,
    "dHvapTb": 38560.0, "cp0": 112.3, "dCp": 0.30, "rhoRef": 785.1, "tRef": 298.15, "sigmaRef": 0.0220,
    "vpKind": "antoineLog10MmHgC", "vpCoeffs": [8.11220, 1592.864, 226.184]
  },
  "water": {
    "name": "Water", "mw": 18.015, "tb": 373.15, "tc": 647.10, "pc": 22064000.0, "omega": 0.345,
    "dHvapTb": 40660.0, "cp0": 75.3, "dCp": 0.01, "rhoRef": 997.0, "tRef": 298.15, "sigmaRef": 0.0720,
    "zraOverride": 0.4945,
    "vpKind": "dippr101", "vpCoeffs": [73.649, -7258.2, -7.3037, 4.1653e-6, 2.0]
  },
  "acetone": {
    "name": "Acetone", "mw": 58.08, "tb": 329.22, "tc": 508.10, "pc": 4700000.0, "omega": 0.307,
    "dHvapTb": 29100.0, "cp0": 126.3, "dCp": 0.15, "rhoRef": 784.5, "tRef": 298.15, "sigmaRef": 0.0230,
    "vpKind": "antoineLog10MmHgC", "vpCoeffs": [7.23160, 1277.030, 237.230]
  },
  "chloroform": {
    "name": "Chloroform", "mw": 119.38, "tb": 334.33, "tc": 536.40, "pc": 5472000.0, "omega": 0.222,
    "dHvapTb": 29240.0, "cp0": 114.2, "dCp": 0.08, "rhoRef": 1479.0, "tRef": 298.15, "sigmaRef": 0.0267,
    "vpKind": "antoineLog10MmHgC", "vpCoeffs": [6.93710, 1171.200, 227.000]
  },
  "propane": {
    "name": "Propane", "mw": 44.10, "tb": 231.10, "tc": 369.83, "pc": 4248000.0, "omega": 0.152,
    "dHvapTb": 19040.0, "cp0": 117.8, "dCp": 0.60, "rhoRef": 493.0, "tRef": 298.15, "sigmaRef": 0.0070,
    "vpKind": "leeKesler", "vpCoeffs": []
  },
  "isobutane": {
    "name": "Isobutane", "mw": 58.12, "tb": 261.40, "tc": 407.80, "pc": 3640000.0, "omega": 0.184,
    "dHvapTb": 21300.0, "cp0": 140.0, "dCp": 0.35, "rhoRef": 551.0, "tRef": 298.15, "sigmaRef": 0.0096,
    "vpKind": "leeKesler", "vpCoeffs": []
  },
  "nbutane": {
    "name": "n-Butane", "mw": 58.12, "tb": 272.70, "tc": 425.12, "pc": 3796000.0, "omega": 0.200,
    "dHvapTb": 22440.0, "cp0": 140.9, "dCp": 0.35, "rhoRef": 573.0, "tRef": 298.15, "sigmaRef": 0.0119,
    "vpKind": "leeKesler", "vpCoeffs": []
  },
  "isopentane": {
    "name": "Isopentane", "mw": 72.15, "tb": 301.00, "tc": 460.40, "pc": 3380000.0, "omega": 0.227,
    "dHvapTb": 24690.0, "cp0": 164.8, "dCp": 0.30, "rhoRef": 616.0, "tRef": 298.15, "sigmaRef": 0.0144,
    "vpKind": "leeKesler", "vpCoeffs": []
  },
  "npentane": {
    "name": "n-Pentane", "mw": 72.15, "tb": 309.20, "tc": 469.70, "pc": 3370000.0, "omega": 0.252,
    "dHvapTb": 25790.0, "cp0": 167.2, "dCp": 0.30, "rhoRef": 621.0, "tRef": 298.15, "sigmaRef": 0.0155,
    "vpKind": "leeKesler", "vpCoeffs": []
  },
  "nhexane": {
    "name": "n-Hexane", "mw": 86.18, "tb": 341.90, "tc": 507.60, "pc": 3025000.0, "omega": 0.301,
    "dHvapTb": 28850.0, "cp0": 195.6, "dCp": 0.30, "rhoRef": 655.0, "tRef": 298.15, "sigmaRef": 0.0179,
    "vpKind": "leeKesler", "vpCoeffs": []
  },
  "nheptane": {
    "name": "n-Heptane", "mw": 100.20, "tb": 371.60, "tc": 540.20, "pc": 2740000.0, "omega": 0.350,
    "dHvapTb": 31770.0, "cp0": 224.7, "dCp": 0.30, "rhoRef": 680.0, "tRef": 298.15, "sigmaRef": 0.0197,
    "vpKind": "leeKesler", "vpCoeffs": []
  }
}
''';
