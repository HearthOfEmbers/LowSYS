import 'dart:typed_data';

import '../config/column_config.dart';
import '../core/ids.dart';
import 'component.dart';
import 'thermo_model.dart';

/// Tier 1 thermo: constant relative volatility, CMO (PHYSICS.md 3.1).
/// No temperature, enthalpy or pressure effects on VLE.
class Tier1ConstantAlpha implements ConstantAlphaThermo {
  @override
  final Float64List alpha;
  @override
  final double rhoL, rhoV, sigma;
  final double _mu;
  final Float64List mw;

  Tier1ConstantAlpha({
    required Float64List alpha,
    required this.rhoL,
    required this.rhoV,
    required this.sigma,
    required double viscosity,
    required this.mw,
  })  : alpha = Float64List.fromList(alpha),
        _mu = viscosity;

  factory Tier1ConstantAlpha.fromConfig(ColumnConfig c) {
    final db = ComponentDb.load();
    final props =
        c.tier1Props ?? (throw ConfigException('Tier 1 needs tier1Props'));
    final a =
        c.tier1Alpha ?? (throw ConfigException('Tier 1 needs tier1Alpha'));
    return Tier1ConstantAlpha(
      alpha: a,
      rhoL: props.rhoL,
      rhoV: props.rhoV,
      sigma: props.sigma,
      viscosity: c.liquidViscosity,
      mw: Float64List.fromList([for (final id in c.components) db[id].mw]),
    );
  }

  @override
  ThermoTier get tier => ThermoTier.t1;
  @override
  int get nc => alpha.length;
  @override
  bool get hasTemperature => false;

  /// Equilibrium vapour y*_i = alpha_i x_i / sum_k alpha_k x_k, PHYSICS.md (3.1).
  /// Reads [x] at [xOff] and writes [out] at [outOff].
  void equilibrium(Float64List x, int xOff, Float64List out, int outOff) {
    var s = 0.0;
    for (var i = 0; i < alpha.length; i++) {
      s += alpha[i] * x[xOff + i];
    }
    if (s <= 0) {
      for (var i = 0; i < alpha.length; i++) {
        out[outOff + i] = 1.0 / alpha.length;
      }
      return;
    }
    for (var i = 0; i < alpha.length; i++) {
      out[outOff + i] = alpha[i] * x[xOff + i] / s;
    }
  }

  /// Binary closed form y* = a x / (1 + (a - 1) x) for the light component.
  double yStarBinary(double x) =>
      alpha[0] / alpha[1] * x / (1 + (alpha[0] / alpha[1] - 1) * x);

  @override
  void kValues(double t, double p, Float64List x, Float64List kOut) {
    for (var i = 0; i < alpha.length; i++) {
      kOut[i] = alpha[i];
    }
  }

  @override
  void dLnKdT(double t, double p, Float64List x, Float64List out) {
    for (var i = 0; i < alpha.length; i++) {
      out[i] = 0;
    }
  }

  @override
  double bubbleT(double p, Float64List x, double tGuess, Float64List yOut,
          Float64List kOut, SolverHealth health) =>
      throw UnsupportedError('Tier 1 has no temperature');
  @override
  double dewT(double p, Float64List y, double tGuess, Float64List xOut,
          SolverHealth health) =>
      throw UnsupportedError('Tier 1 has no temperature');
  @override
  FlashResult flashTP(double t, double p, Float64List z) =>
      throw UnsupportedError('Tier 1 has no flash');
  @override
  double qOfFeed(double tFeed, double p, Float64List z) =>
      throw UnsupportedError('Tier 1: q is a lever');
  @override
  double hL(double t, Float64List x) =>
      throw UnsupportedError('Tier 1 has no enthalpy');
  @override
  double hV(double t, Float64List y) =>
      throw UnsupportedError('Tier 1 has no enthalpy');
  @override
  double cpL(double t, Float64List x) =>
      throw UnsupportedError('Tier 1 has no enthalpy');

  /// v_L = sum x_i MW_i / (1000 rhoL) (PHYSICS.md 3.1), m3/mol. [t] is ignored.
  @override
  double liquidMolarVolume(double t, Float64List x) {
    var m = 0.0;
    for (var i = 0; i < mw.length; i++) {
      m += x[i] * mw[i];
    }
    return m / (1000 * rhoL);
  }

  @override
  double vaporDensity(double t, double p, Float64List y) => rhoV;
  @override
  double surfaceTension(double t, Float64List x) => sigma;
  @override
  double liquidViscosity() => _mu;
}
