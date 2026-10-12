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

  EffectiveParams(this.n, this.nc)
      : holeScale = Float64List(n),
        apronScale = Float64List(n),
        brokenS = Float64List(n),
        sfFroth = Float64List(n),
        sfFlood = Float64List(n),
        phiDc = Float64List(n),
        zEff = Float64List(nc);

  void reset(double systemFactor, double phiDcBase) {
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
