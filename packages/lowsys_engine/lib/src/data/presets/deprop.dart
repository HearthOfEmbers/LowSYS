/// Depropanizer preset (PHYSICS.md 2.3, M7): 28 valve trays in two sections (trays 1-10 at 0.55 m, trays 11-28 at 0.85 m), feed tray 11, E = 0.7, Tier 3 DePriester,
/// L0 66.1 kmol/h, Tier-1 V_B 96.9 kmol/h, Tier-2/3 duty 416.55 kW (D about 30.78 kmol/h). LK propane, HK isobutane.
const String depropPresetJson = r'''
{
  "presetId": "deprop",
  "displayName": "Depropanizer",
  "components": ["propane", "isobutane", "nbutane", "isopentane", "npentane", "nhexane"],
  "tier": "t3",
  "tier3Model": "dePriester",
  "keys": {"lk": "propane", "hk": "isobutane"},
  "tier1Alpha": [2.172, 1.0, 0.747, 0.378, 0.33, 0.157],
  "tier1Props": {"rhoL": 470, "rhoV": 36.0, "sigma": 0.005},
  "liquidViscosity": 0.0001,
  "sections": [{"kind": "trays", "trays": 10, "type": "valve",
    "geometry": {"diameter": 0.55, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}},
               {"kind": "trays", "trays": 18, "type": "valve",
    "geometry": {"diameter": 0.85, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 11, "flow": 27.77777777777778, "z": [0.3, 0.2, 0.25, 0.1, 0.1, 0.05], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 1724000.0,
                "reliefSet": 2586000.0, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 22030.0,
                "dvMax": 8.55, "reliefMax": 53.833333333333336, "dTbubDp": 2.6e-5, "pcKc": 120, "pcTi": 400},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 28630.0},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 18.36111111111111, "boilup": 26.916666666666668, "reboilerDuty": 416550.0}
}
''';
