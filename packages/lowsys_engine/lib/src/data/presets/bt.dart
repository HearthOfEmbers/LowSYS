/// Benzene-toluene textbook preset (ENGINE_API.md 4, SCOPE.md 4.1). SI units.
/// Flow values (mol/s) are the exact conversions of 100 / 100 / 150 kmol/h (the spec JSON example lists them in kmol/s; see docs/DEVIATIONS.md).
const String btPresetJson = r'''
{
  "presetId": "bt",
  "displayName": "Benzene–toluene (textbook)",
  "components": ["benzene", "toluene"],
  "tier": "t1",
  "tier1Alpha": [2.5, 1.0],
  "tier1Props": {"rhoL": 800, "rhoV": 2.9, "sigma": 0.020},
  "liquidViscosity": 0.00027,
  "sections": [{"kind": "trays", "trays": 20, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 10, "flow": 27.77777777777778, "z": [0.5, 0.5], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 29900, "dvMax": 13.88888889, "reliefMax": 83.33333333},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 57500},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 27.77777777777778, "boilup": 41.666666666666664, "reboilerDuty": 1301477.0}
}
''';

/// "Custom alpha" preset: same column, the relative volatility is a lever (1.05..10).
const String btCustomAlphaPresetJson = r'''
{
  "presetId": "bt_custom_alpha",
  "displayName": "Custom α",
  "components": ["benzene", "toluene"],
  "tier": "t1",
  "tier1Alpha": [2.5, 1.0],
  "tier1Props": {"rhoL": 800, "rhoV": 2.9, "sigma": 0.020},
  "liquidViscosity": 0.00027,
  "sections": [{"kind": "trays", "trays": 20, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 10, "flow": 27.77777777777778, "z": [0.5, 0.5], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 29900, "dvMax": 13.88888889, "reliefMax": 83.33333333},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 57500},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 27.77777777777778, "boilup": 41.666666666666664, "reboilerDuty": 1301477.0}
}
''';
