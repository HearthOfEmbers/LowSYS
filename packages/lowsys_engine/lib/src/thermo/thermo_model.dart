import 'dart:typed_data';

import '../core/ids.dart';

/// Result of an isothermal flash (Tiers 2/3).
class FlashResult {
  final double beta;
  final Float64List x, y;
  const FlashResult(this.beta, this.x, this.y);
}

/// One thermo model per tier per system (ENGINE_API.md 3.2). Hot-path methods are
/// allocation-free: callers pass output buffers.
abstract class ThermoModel {
  ThermoTier get tier;
  int get nc;

  /// False for Tier 1 (M1-M3).
  bool get hasTemperature;

  /// K-values at (T, P, x). Tier 1 fills alpha_i (relative, not true K).
  void kValues(double t, double p, Float64List x, Float64List kOut);

  /// d ln K_i / dT (gamma treated as constant).
  void dLnKdT(double t, double p, Float64List x, Float64List out);

  /// Bubble point (Tiers 2/3). Tier 1 throws [UnsupportedError].
  double bubbleT(double p, Float64List x, double tGuess, Float64List yOut,
      Float64List kOut, SolverHealth health);
  double dewT(double p, Float64List y, double tGuess, Float64List xOut,
      SolverHealth health);
  FlashResult flashTP(double t, double p, Float64List z);
  double qOfFeed(double tFeed, double p, Float64List z);

  double hL(double t, Float64List x);
  double hV(double t, Float64List y);
  double cpL(double t, Float64List x);

  /// m3/mol
  double liquidMolarVolume(double t, Float64List x);

  /// kg/m3
  double vaporDensity(double t, double p, Float64List y);

  /// N/m
  double surfaceTension(double t, Float64List x);

  /// Pa s
  double liquidViscosity();
}

/// Tier 1 adds the relative volatilities and constant properties.
abstract class ConstantAlphaThermo implements ThermoModel {
  Float64List get alpha;
  double get rhoL;
  double get rhoV;
  double get sigma;
}
