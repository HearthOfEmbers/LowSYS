/// C4 splitter preset (PHYSICS.md 2.3, M5): 60 sieve trays with the B-T geometry, feed tray 30, F = 100 kmol/h, z = [0.4, 0.6],
/// saturated liquid. L0 = 280.0 kmol/h, Tier-1 V_B = 320.0 kmol/h, Tier-2/3 duty 1542.6 kW (D about 40.0 kmol/h).
const String c4PresetJson = r'''
{
  "presetId": "c4",
  "displayName": "C4 splitter",
  "components": ["isobutane", "nbutane"],
  "tier": "t2",
  "tier3Model": "dePriester",
  "tier1Alpha": [1.35, 1.0],
  "tier1Props": {"rhoL": 530, "rhoV": 15.0, "sigma": 0.008},
  "liquidViscosity": 0.00012,
  "sections": [{"kind": "trays", "trays": 60, "type": "sieve",
    "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05,
                 "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73,
                 "downcomerAeration": 0.5, "systemFactor": 1.0}}],
  "feeds": [{"stage": 30, "flow": 27.77777777777778, "z": [0.4, 0.6], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 700000,
                "reliefSet": 1050000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 122800,
                "dvMax": 11.11111111111111, "reliefMax": 177.77777777777777},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 30150},
  "control": {"loops": "default"},
  "hydraulics": "ideal",
  "murphree": 0.7,
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 77.77777777777779, "boilup": 88.88888888888889, "reboilerDuty": 1542600.0}
}
''';
