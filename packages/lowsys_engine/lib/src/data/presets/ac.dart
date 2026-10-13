/// Acetone–chloroform preset (PHYSICS.md 2.3, M5): 30 sieve trays with the B-T geometry, feed tray 15, F = 100 kmol/h, z = [0.6, 0.4],
/// saturated liquid. L0 = 150.0 kmol/h, Tier-1 V_B = 188.0 kmol/h, Tier-2/3 duty 1515.9 kW (D about 38.0 kmol/h).
const String acPresetJson = r'''
{
  "presetId": "ac",
  "displayName": "Acetone–chloroform",
  "components": ["acetone", "chloroform"],
  "tier": "t3",
  "tier3Model": "nrtl",
  "tier1CannotRepresent": true,
  "tier1Alpha": [1.19, 1.0],
  "tier1Props": {"rhoL": 1150, "rhoV": 3.50, "sigma": 0.020},
  "liquidViscosity": 0.0003,
  "sections": [{"kind": "trays", "trays": 30, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 15, "flow": 27.77777777777778, "z": [0.6, 0.4], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 83700,
                "dvMax": 10.555555555555555, "reliefMax": 104.44444444444444},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 30240},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 41.66666666666667, "boilup": 52.22222222222222, "reboilerDuty": 1515900.0}
}
''';
