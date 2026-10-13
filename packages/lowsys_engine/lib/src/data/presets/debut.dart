/// Debutanizer preset (PHYSICS.md 2.3, M7): 32 sieve trays with the B-T geometry, feed tray 16, E = 0.7, Tier 3 DePriester,
/// L0 76.4 kmol/h, Tier-1 V_B 121.3 kmol/h, Tier-2/3 duty 679.68 kW (D about 44.94 kmol/h). LK n-butane, HK isopentane.
const String debutPresetJson = r'''
{
  "presetId": "debut",
  "displayName": "Debutanizer",
  "components": ["propane", "isobutane", "nbutane", "isopentane", "npentane", "nhexane"],
  "tier": "t3",
  "tier3Model": "dePriester",
  "keys": {"lk": "nbutane", "hk": "isopentane"},
  "tier1Alpha": [5.18, 2.628, 2.041, 1.0, 0.843, 0.385],
  "tier1Props": {"rhoL": 560, "rhoV": 15.0, "sigma": 0.009},
  "liquidViscosity": 0.00013,
  "sections": [{"kind": "trays", "trays": 32, "type": "sieve",
    "geometry": {"diameter": 0.75, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 16, "flow": 27.77777777777778, "z": [0.05, 0.15, 0.25, 0.2, 0.2, 0.15], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 689500.0,
                "reliefSet": 1034250.0, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 38470.0,
                "dvMax": 12.48, "reliefMax": 67.38888888888889, "dTbubDp": 6.2e-5, "pcKc": 30},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 32020.0},
  "control": {"loops": "default", "temperatureTrays": [1, 6, 11, 16, 19, 22, 27, 32]},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 21.222222222222225, "boilup": 33.69444444444444, "reboilerDuty": 679680.0}
}
''';
