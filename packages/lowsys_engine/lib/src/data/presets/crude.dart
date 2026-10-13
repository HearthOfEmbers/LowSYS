/// Crude unit preset (ENGINE_API.md 4.1 `crude`, PHYSICS.md 9). SI units. The feed flow is set by the `crudeRate` lever
/// (m3/s at 15.6 C) as crudeRate / sum(z v): 528.36 kmol/h at 132.5 m3/h; the value here is that conversion in mol/s.
const String crudePresetJson = r'''
{
  "presetId": "crude", "displayName": "Crude unit (20 000 bbl/d, light crude)", "tier": "t2", "hydraulics": "full", "murphree": 1.0,
  "components": ["PC1", "PC2", "PC3", "PC4", "PC5", "PC6", "PC7", "PC8", "PC9", "water"],
  "sections": [{"kind": "trays", "trays": 26, "type": "valve", "geometry": {"diameter": 3.2, "traySpacing": 0.75, "downcomerFraction": 0.12, "weirHeight": 0.05}},
               {"kind": "trays", "trays": 4,  "type": "valve", "geometry": {"diameter": 1.7, "traySpacing": 0.75, "downcomerFraction": 0.12, "weirHeight": 0.05}}],
  "feeds": [{"stage": 26, "flow": 146.767, "z": "assay", "thermal": {"t": 618.15}}],
  "condenser": {"type": "total", "pTopDesign": 160000, "drumVolume": 10.0},
  "control": {"loops": "default", "levelKc": 2.0, "levelTi": 1800},
  "sideDraws": [{"product": "kero", "drawStage": 8, "returnStage": 7, "stripper": 0},
                {"product": "diesel", "drawStage": 15, "returnStage": 14, "stripper": 1},
                {"product": "ago", "drawStage": 21, "returnStage": 20, "stripper": 2}],
  "strippers": [{"stages": 2, "diameter": 1.0, "bootVolume": 1.0, "steamPoint": "ss1"}, {"stages": 2, "diameter": 1.0, "bootVolume": 1.0, "steamPoint": "ss2"},
                {"stages": 2, "diameter": 1.0, "bootVolume": 1.0, "steamPoint": "ss3"}],
  "pumparounds": [{"drawStage": 16, "returnStage": 14, "circulation": 0.0333333, "tReturnMin": 393.15}],
  "steam": [{"point": "bottom", "temperature": 473.15}, {"point": "ss1", "temperature": 473.15},
            {"point": "ss2", "temperature": 473.15}, {"point": "ss3", "temperature": 473.15}],
  "crude": {"drumDp": 20000, "qcMax": 15000000, "furnaceTau": 60, "tbpTrim": 0.01, "steamFilterTau": 30, "steamFracMax": 0.98},
  "initialLevers": {"crudeRate": 0.0368056, "cot": 618.15, "pTop": 160000, "topTSp": 398.15, "drawRate.kero": 0.00430625,
                    "drawRate.diesel": 0.00614653, "drawRate.ago": 0.00195069, "paDuty": 5000000, "steam.bottom": 0.555556,
                    "steam.ss1": 0.0833333, "steam.ss2": 0.0833333, "steam.ss3": 0.0833333, "drumTSp": 318.15}
}
''';
