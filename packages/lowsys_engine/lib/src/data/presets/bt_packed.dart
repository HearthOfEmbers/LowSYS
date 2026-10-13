/// Benzene-toluene with structured packing (PHYSICS.md 2.3 M8 rules): the `bt` shell, drum, sump, utilities and feed with the 20 sieve
/// trays replaced by two 4.5 m beds of struct250 (9 + 9 segments), feed on stage 10 (the top of the lower bed). Full hydraulics.
const String btPackedPresetJson = r'''
{
  "presetId": "bt_packed",
  "displayName": "Benzene–toluene, packed (2 × 4.5 m structured)",
  "components": ["benzene", "toluene"],
  "tier": "t1",
  "tier1Alpha": [2.5, 1.0],
  "tier1Props": {"rhoL": 800, "rhoV": 2.9, "sigma": 0.020},
  "liquidViscosity": 0.00027,
  "sections": [{"kind": "packed", "bedHeight": 4.5, "packingId": "struct250", "diameter": 1.2, "designLiquidFlux": 1.9}, {"kind": "packed", "bedHeight": 4.5, "packingId": "struct250", "diameter": 1.2, "designLiquidFlux": 4.0}],
  "feeds": [{"stage": 10, "flow": 27.77777777777778, "z": [0.5, 0.5], "thermal": {"q": 1.0}}],
  "condenser": {"type": "total", "drumVolume": 3.0, "overheadVolume": 3.0, "pTopDesign": 101325,
                "reliefSet": 350000, "cwInletT": 303.15, "cwMaxFlow": 41.54, "uaClean": 29900, "dvMax": 13.88888889, "reliefMax": 83.33333333},
  "reboiler": {"type": "kettle", "sumpHeight": 2.4, "sumpArea": 1.131, "steamHeaderPressure": 451325, "uaClean": 57500},
  "control": {"loops": "default", "temperatureTrays": [1, 3, 5, 7, 9, 10, 12, 14, 16, 18]},
  "hydraulics": "full",
  "murphree": 0.7,
  "internals": 1,
  "internalsTemplates": [
    {"id": 0, "label": "20 sieve trays", "feedStage": 10, "temperatureTrays": [1, 4, 7, 10, 12, 14, 17, 20],
     "sections": [{"kind": "trays", "trays": 20, "type": "sieve", "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05, "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73, "downcomerAeration": 0.5, "systemFactor": 1.0}}]},
    {"id": 1, "label": "Structured packing, 2 x 4.5 m", "feedStage": 10, "temperatureTrays": [1, 3, 5, 7, 9, 10, 12, 14, 16, 18],
     "sections": [{"kind": "packed", "bedHeight": 4.5, "packingId": "struct250", "diameter": 1.2, "designLiquidFlux": 1.9}, {"kind": "packed", "bedHeight": 4.5, "packingId": "struct250", "diameter": 1.2, "designLiquidFlux": 4.0}]},
    {"id": 2, "label": "Mixed: packed top, trays below", "feedStage": 10, "temperatureTrays": [1, 3, 5, 7, 9, 10, 12, 14, 17, 20],
     "sections": [{"kind": "packed", "bedHeight": 4.5, "packingId": "struct250", "diameter": 1.2, "designLiquidFlux": 1.9}, {"kind": "trays", "trays": 11, "type": "sieve", "geometry": {"diameter": 1.2, "traySpacing": 0.9, "downcomerFraction": 0.12, "weirHeight": 0.05, "apronClearance": 0.038, "holeFraction": 0.10, "holeDiameter": 0.0127, "orificeCoeff": 0.73, "downcomerAeration": 0.5, "systemFactor": 1.0}}]}
  ],
  "initialLevers": {"feedFlow": 27.77777777777778, "refluxFlow": 27.77777777777778, "boilup": 41.666666666666664, "reboilerDuty": 1300000.0}
}
''';
