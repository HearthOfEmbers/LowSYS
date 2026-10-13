/// Ethanol–water preset (PHYSICS.md 2.3, M5): 40 sieve trays with the B-T geometry, feed tray 30, F = 100 kmol/h, z = [0.1, 0.9],
/// saturated liquid. L0 = 100.0 kmol/h, Tier-1 V_B = 110.0 kmol/h, Tier-2/3 duty 1206.8 kW (D about 10.0 kmol/h).
const String ewPresetJson = r'''
{
  "presetId": "ew",
  "displayName": "Ethanol–water",
  "components": ["ethanol", "water"],
  "tier": "t3",
  "tier3Model": "nrtl",
  "tier1Alpha": [2.4, 1.0],
  "tier1Props": {"rhoL": 820, "rhoV": 1.30, "sigma": 0.035},
  "liquidViscosity": 0.0004,
  "sections": [{"kind": "trays", "trays": 40, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 30, "flow": 27.77777777777778, "z": [0.1, 0.9], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 28830,
                "dvMax": 2.7777777777777777, "reliefMax": 61.111111111111114},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 38980},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 27.77777777777778, "boilup": 30.555555555555557, "reboilerDuty": 1206800.0}
}
''';
