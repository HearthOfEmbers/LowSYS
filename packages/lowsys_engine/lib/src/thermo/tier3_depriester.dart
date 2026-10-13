import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart';
import '../core/ids.dart';
import 'component.dart';
import 'tier2_raoult.dart';

/// McWilliams (1973) fit of the DePriester charts (PHYSICS.md 3.4.2):
/// ln K = a_T1/T_R^2 + a_T2/T_R + a_T6 + a_p1 ln p + a_p2/p^2 + a_p3/p, T_R in degR, p in psia.
/// Order: aT1, aT2, aT6, ap1, ap2, ap3.
const Map<ComponentId, List<double>> dePriesterCoeffs = {
  'propane': [-970688.5625, 0, 7.15059, -0.76984, 0, 6.90224],
  'isobutane': [-1166846, 0, 7.72668, -0.92213, 0, 0],
  'nbutane': [-1280557, 0, 7.94986, -0.96455, 0, 0],
  'isopentane': [-1481583, 0, 7.58071, -0.93159, 0, 0],
  'npentane': [-1524891, 0, 7.33129, -0.89143, 0, 0],
  'nhexane': [-1778901, 0, 6.96783, -0.84634, 0, 0],
  'nheptane': [-2013803, 0, 6.52914, -0.79543, 0, 0],
};

/// Tier 3 for light hydrocarbons: K from T and P only (PHYSICS.md 3.9). Enthalpies and properties are the Tier-2 ones.
class Tier3DePriester extends Tier2Raoult {
  final List<List<double>> _c;

  /// True once a K was evaluated outside 365-852 degR or 14.7-870 psia (`thermoOutOfRange`).
  bool outOfRange = false;

  Tier3DePriester._(super.comps, this._c, {super.viscosity});

  factory Tier3DePriester.fromIds(List<ComponentId> ids,
      {double viscosity = 0.00027}) {
    final db = ComponentDb.load();
    return Tier3DePriester._([
      for (final id in ids) db[id]
    ], [
      for (final id in ids)
        dePriesterCoeffs[id] ??
            (throw ConfigException('No DePriester coefficients for $id')),
    ], viscosity: viscosity);
  }

  factory Tier3DePriester.fromConfig(ColumnConfig c) =>
      Tier3DePriester.fromIds(c.components, viscosity: c.liquidViscosity);

  @override
  ThermoTier get tier => ThermoTier.t3;

  static const double _psi = 6894.757;

  @override
  void kAt(double t, double p, Float64List x, int xo, Float64List kOut,
      int ko) {
    // evaluated as is outside the validity range (365-852 degR, 14.7-870 psia): a clamped T would make K
    // independent of T and the bubble-point Newton would have g' = 0 (PHYSICS.md 3.4.2)
    final tr = 1.8 * t;
    if (tr < 365 || tr > 852) outOfRange = true;
    final pp = p / _psi;
    if (pp < 14.7 || pp > 870) outOfRange = true;
    for (var i = 0; i < comps.length; i++) {
      final c = _c[i];
      kOut[ko + i] = math.exp(c[0] / (tr * tr) +
          c[1] / tr +
          c[2] +
          c[3] * math.log(pp) +
          c[4] / (pp * pp) +
          c[5] / pp);
    }
  }

  @override
  void dLnKAt(double t, double p, Float64List x, int xo, Float64List out,
      int oo) {
    final tr = 1.8 * t;
    for (var i = 0; i < comps.length; i++) {
      final c = _c[i];
      out[oo + i] = 1.8 * (-2 * c[0] / (tr * tr * tr) - c[1] / (tr * tr));
    }
  }
}
