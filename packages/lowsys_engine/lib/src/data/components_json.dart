/// Named component data, PHYSICS.md 2.1 and 2.2 (SI: Pa, K, J/mol, kg/m3).
/// M1 ships benzene and toluene; the rest of the table arrives with M4/M5/M7.
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
  }
}
''';
