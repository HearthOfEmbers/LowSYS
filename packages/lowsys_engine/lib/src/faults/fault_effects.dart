import 'dart:typed_data';

/// Flat, preallocated effective parameter set rebuilt every step by the fault manager. Faults never
/// mutate the configuration (ENGINE_API.md 9).
class EffectiveParams {
  final int n, nc;

  /// Multiplier on the open hole area (fouling), per tray.
  final Float64List holeScale;

  /// Multiplier on the downcomer apron clearance (fouling), per tray.
  final Float64List apronScale;

  /// Open fraction of the deck (broken tray), per tray.
  final Float64List brokenS;

  /// System (foaming) factors on froth density and on flood capacity, per tray.
  final Float64List sfFroth, sfFlood;

  /// Downcomer froth density (aeration), per tray.
  final Float64List phiDc;

  /// Effective feed composition after the feed-composition fault.
  final Float64List zEff;

  // ---- Tier 2 faults F08-F15 (PHYSICS.md 11)
  /// F08: feed temperature offset (K) and q offset (Tier 1).
  double feedDt = 0, feedDq = 0;

  /// F09: factor on the cooling-water capacity and offset of the CW inlet temperature (K).
  double cwFlowScale = 1, cwTempAdd = 0;

  /// F10: severity of the condenser fouling (R_f = 1.5 s / UA_clean). F13 likewise for the reboiler.
  double condFoulS = 0, rebFoulS = 0;

  /// F11: inert make-up per mol of feed. F12: factor on the reflux pump capacity. F14: flooded tube fraction.
  /// F15: factor on the absolute steam header pressure.
  double epsI = 0, refluxCapScale = 1, fFlooded = 0, headerScale = 1;

  EffectiveParams(this.n, this.nc)
      : holeScale = Float64List(n),
        apronScale = Float64List(n),
        brokenS = Float64List(n),
        sfFroth = Float64List(n),
        sfFlood = Float64List(n),
        phiDc = Float64List(n),
        zEff = Float64List(nc);

  void reset(double systemFactor, double phiDcBase) {
    feedDt = 0;
    feedDq = 0;
    cwFlowScale = 1;
    cwTempAdd = 0;
    condFoulS = 0;
    rebFoulS = 0;
    epsI = 0;
    refluxCapScale = 1;
    fFlooded = 0;
    headerScale = 1;
    for (var j = 0; j < n; j++) {
      holeScale[j] = 1;
      apronScale[j] = 1;
      brokenS[j] = 0;
      sfFroth[j] = systemFactor;
      sfFlood[j] = systemFactor;
      phiDc[j] = phiDcBase;
    }
  }
}
