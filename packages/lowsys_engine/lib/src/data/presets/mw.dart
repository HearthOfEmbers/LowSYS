/// Methanol-water preset (SCOPE.md 4.3b, PHYSICS.md 2.3): 20 sieve trays with the B-T geometry, feed tray 12,
/// F = 100 kmol/h, z_MeOH = 0.30, saturated liquid. Tier 1 alpha 3.5 with L0 = 60 and V_B = 90 kmol/h; Tier 2
/// L0 = 60 kmol/h and duty 890.4 kW. Utilities: condenser UA_clean 29.76 kW/K, reboiler UA_R,clean 30.65 kW/K.
const String mwPresetJson = r'''
{
  "presetId": "mw",
  "displayName": "Methanol–water",
  "components": ["methanol", "water"],
  "tier": "t1",
  "tier1Alpha": [3.5, 1.0],
  "tier1Props": {"rhoL": 850, "rhoV": 1.0, "sigma": 0.040},
  "liquidViscosity": 0.00035,
  "sections": [{"kind": "trays", "trays": 20, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 12, "flow": 27.77777777777778, "z": [0.3, 0.7], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 29760,
                "dvMax": 8.33333333, "reliefMax": 50.0},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 30650},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 16.666666666666668, "boilup": 25.0, "reboilerDuty": 890400.0}
}
''';
