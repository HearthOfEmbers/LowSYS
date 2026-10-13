import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart';
import '../core/ids.dart';
import 'component.dart';
import 'thermo_model.dart';

/// Gas constant (J/mol/K).
const double gasR = 8.314462618;

/// Tier 2 thermo: Raoult's law K = P_sat(T)/P, Watson enthalpies, Rackett densities (PHYSICS.md 3.2, 3.3, 3.5, 3.6).
/// The hot-path methods (`*At`) take buffers with offsets and do not allocate.
class Tier2Raoult implements ThermoModel {
  final List<Component> comps;
  final double _mu;
  final Float64List mw, _tc, _pc, _om;
  final Float64List _k, _tmp1, _tmp2;

  /// S = sum K x and the bubble-point derivative sum K x dlnK/dT of the last [bubbleAt] (for tau_j, PHYSICS.md 4.5).
  double lastS = 1, lastDen = 1;

  Tier2Raoult(this.comps, {double viscosity = 0.00027})
      : _mu = viscosity,
        mw = Float64List.fromList([for (final c in comps) c.mw]),
        _tc = Float64List.fromList([for (final c in comps) c.tc]),
        _pc = Float64List.fromList([for (final c in comps) c.pc]),
        _om = Float64List.fromList([for (final c in comps) c.omega]),
        _k = Float64List(comps.length),
        _tmp1 = Float64List(comps.length),
        _tmp2 = Float64List(comps.length);

  factory Tier2Raoult.fromConfig(ColumnConfig c) {
    final db = ComponentDb.load();
    return Tier2Raoult([for (final id in c.components) db[id]],
        viscosity: c.liquidViscosity);
  }

  @override
  ThermoTier get tier => ThermoTier.t2;
  @override
  int get nc => comps.length;
  @override
  bool get hasTemperature => true;

  // ---------------------------------------------------------------- K values

  @override
  void kValues(double t, double p, Float64List x, Float64List kOut) {
    for (var i = 0; i < comps.length; i++) {
      kOut[i] = comps[i].vaporPressure(t) / p;
    }
  }

  @override
  void dLnKdT(double t, double p, Float64List x, Float64List out) {
    for (var i = 0; i < comps.length; i++) {
      out[i] = comps[i].dLnPsatDt(t);
    }
  }

  // ---------------------------------------------------------------- bubble and dew points

  /// Cold guess: mole-fraction average of the normal boiling points.
  double coldGuess(Float64List x, int xo) {
    var t = 0.0;
    for (var i = 0; i < comps.length; i++) {
      t += x[xo + i] * comps[i].tb;
    }
    return t;
  }

  /// Bubble point (PHYSICS.md 3.6.1) of the liquid [x] at [xo] at pressure [p]. Fills [yOut] (normalised, at [yo])
  /// and the K-values [kOut] (at [ko]) at the converged temperature. Returns T (K).
  double bubbleAt(double p, Float64List x, int xo, double tGuess,
      Float64List yOut, int yo, Float64List kOut, int ko, SolverHealth health) {
    final n = comps.length;
    var t = (tGuess.isFinite && tGuess > 150 && tGuess < 900)
        ? tGuess
        : coldGuess(x, xo);
    var ok = false;
    var s = 1.0, den = 1.0;
    for (var it = 0; it < 20; it++) {
      s = 0;
      den = 0;
      for (var i = 0; i < n; i++) {
        final c = comps[i];
        final ki = c.vaporPressure(t) / p;
        kOut[ko + i] = ki;
        final kx = ki * x[xo + i];
        s += kx;
        den += kx * c.dLnPsatDt(t);
      }
      if (!(s > 0)) break;
      final g = math.log(s);
      if (g.abs() < 1e-10) {
        ok = true;
        break;
      }
      var dT = -g * s / den;
      if (dT > 30) dT = 30;
      if (dT < -30) dT = -30;
      t += dT;
      if (dT.abs() < 1e-6) {
        s = 0;
        den = 0;
        for (var i = 0; i < n; i++) {
          final c = comps[i];
          final ki = c.vaporPressure(t) / p;
          kOut[ko + i] = ki;
          final kx = ki * x[xo + i];
          s += kx;
          den += kx * c.dLnPsatDt(t);
        }
        ok = true;
        break;
      }
    }
    if (!ok || !(t > 100) || t.isNaN) {
      health.bubbleFallbacks++;
      var lo = 150.0, hi = 900.0;
      for (final c in comps) {
        hi = math.min(hi, 0.98 * c.tc);
      }
      for (var it = 0; it < 80; it++) {
        final mid = 0.5 * (lo + hi);
        var sm = 0.0;
        for (var i = 0; i < n; i++) {
          sm += comps[i].vaporPressure(mid) / p * x[xo + i];
        }
        if (sm < 1) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      t = 0.5 * (lo + hi);
      s = 0;
      den = 0;
      for (var i = 0; i < n; i++) {
        final c = comps[i];
        final ki = c.vaporPressure(t) / p;
        kOut[ko + i] = ki;
        final kx = ki * x[xo + i];
        s += kx;
        den += kx * c.dLnPsatDt(t);
      }
    }
    lastS = s;
    lastDen = den;
    for (var i = 0; i < n; i++) {
      yOut[yo + i] = kOut[ko + i] * x[xo + i] / s;
    }
    return t;
  }

  @override
  double bubbleT(double p, Float64List x, double tGuess, Float64List yOut,
          Float64List kOut, SolverHealth health) =>
      bubbleAt(p, x, 0, tGuess, yOut, 0, kOut, 0, health);

  /// Dew point (PHYSICS.md 3.6.2) of the vapour [y]; fills [xOut] (normalised).
  @override
  double dewT(double p, Float64List y, double tGuess, Float64List xOut,
      SolverHealth health) {
    final n = comps.length;
    var t = (tGuess.isFinite && tGuess > 150 && tGuess < 900)
        ? tGuess
        : coldGuess(y, 0);
    var ok = false;
    for (var it = 0; it < 30; it++) {
      var s = 0.0, den = 0.0;
      for (var i = 0; i < n; i++) {
        final ki = comps[i].vaporPressure(t) / p;
        final r = y[i] / ki;
        s += r;
        den += r * comps[i].dLnPsatDt(t);
      }
      final g = math.log(s);
      if (g.abs() < 1e-10) {
        ok = true;
        break;
      }
      var dT = g * s / den;
      if (dT > 30) dT = 30;
      if (dT < -30) dT = -30;
      t += dT;
      if (dT.abs() < 1e-6) {
        ok = true;
        break;
      }
    }
    if (!ok) {
      health.bubbleFallbacks++;
      var lo = 150.0, hi = 900.0;
      for (final c in comps) {
        hi = math.min(hi, 0.98 * c.tc);
      }
      for (var it = 0; it < 80; it++) {
        final mid = 0.5 * (lo + hi);
        var sm = 0.0;
        for (var i = 0; i < n; i++) {
          sm += y[i] * p / comps[i].vaporPressure(mid);
        }
        if (sm > 1) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      t = 0.5 * (lo + hi);
    }
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      xOut[i] = y[i] / (comps[i].vaporPressure(t) / p);
      s += xOut[i];
    }
    for (var i = 0; i < n; i++) {
      xOut[i] /= s;
    }
    return t;
  }

  // ---------------------------------------------------------------- flash and feed condition

  /// Vapour fraction by Rachford-Rice (PHYSICS.md 3.14); fills [xOut], [yOut] if given.
  double flashBeta(double t, double p, Float64List z,
      [Float64List? xOut, Float64List? yOut]) {
    final n = comps.length;
    for (var i = 0; i < n; i++) {
      _k[i] = comps[i].vaporPressure(t) / p;
    }
    double f(double b) {
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        s += z[i] * (_k[i] - 1) / (1 + b * (_k[i] - 1));
      }
      return s;
    }

    double beta;
    if (f(0) < 0) {
      beta = 0;
    } else if (f(1) > 0) {
      beta = 1;
    } else {
      var lo = 0.0, hi = 1.0;
      beta = 0.5;
      for (var it = 0; it < 100; it++) {
        beta = 0.5 * (lo + hi);
        final v = f(beta);
        if (v > 0) {
          lo = beta;
        } else {
          hi = beta;
        }
        if (hi - lo < 1e-14) break;
      }
    }
    if (xOut != null || yOut != null) {
      for (var i = 0; i < n; i++) {
        final xi = z[i] / (1 + beta * (_k[i] - 1));
        xOut?[i] = xi;
        yOut?[i] = _k[i] * xi;
      }
    }
    return beta;
  }

  @override
  FlashResult flashTP(double t, double p, Float64List z) {
    final x = Float64List(nc), y = Float64List(nc);
    final b = flashBeta(t, p, z, x, y);
    return FlashResult(b, x, y);
  }

  /// Feed enthalpy (J/mol) at [t], [p] for the overall composition [z]: (1 - beta) h_L(x) + beta H_V(y).
  double feedEnthalpy(double t, double p, Float64List z) {
    final b = flashBeta(t, p, z, _tmp1, _tmp2);
    return (1 - b) * hLAt(t, _tmp1, 0) + b * hVAt(t, _tmp2, 0);
  }

  @override
  double qOfFeed(double tFeed, double p, Float64List z) {
    final health = SolverHealth();
    final y = Float64List(nc), k = Float64List(nc), xd = Float64List(nc);
    final tb = bubbleT(p, z, tFeed, y, k, health);
    final hLsat = hLAt(tb, z, 0);
    final td = dewT(p, z, tb + 5, xd, health);
    final hVsat = hVAt(td, z, 0);
    final hF = feedEnthalpy(tFeed, p, z);
    final d = hVsat - hLsat;
    return d.abs() < 1e-9 ? 1.0 : (hVsat - hF) / d;
  }

  // ---------------------------------------------------------------- enthalpy

  static const double _t0 = 298.15;

  double hLAt(double t, Float64List x, int xo) {
    var h = 0.0;
    for (var i = 0; i < comps.length; i++) {
      h += x[xo + i] * comps[i].hLiquid(t);
    }
    return h;
  }

  double hVAt(double t, Float64List y, int yo) {
    var h = 0.0;
    for (var i = 0; i < comps.length; i++) {
      final c = comps[i];
      h += y[yo + i] * (c.hLiquid(t) + c.dHvap(t));
    }
    return h;
  }

  @override
  double hL(double t, Float64List x) => hLAt(t, x, 0);
  @override
  double hV(double t, Float64List y) => hVAt(t, y, 0);

  @override
  double cpL(double t, Float64List x) {
    var c = 0.0;
    for (var i = 0; i < comps.length; i++) {
      c += x[i] * (comps[i].cp0 + comps[i].dCp * (t - _t0));
    }
    return c;
  }

  /// Liquid heat capacity (J/mol/K) of the liquid [x] at [xo].
  double cpLAt(double t, Float64List x, int xo) {
    var c = 0.0;
    for (var i = 0; i < comps.length; i++) {
      c += x[xo + i] * (comps[i].cp0 + comps[i].dCp * (t - _t0));
    }
    return c;
  }

  // ---------------------------------------------------------------- physical properties

  double liquidMolarVolumeAt(double t, Float64List x, int xo) {
    var v = 0.0;
    for (var i = 0; i < comps.length; i++) {
      final c = comps[i];
      v += x[xo + i] * c.mw / (1000 * c.liquidDensity(t));
    }
    return v;
  }

  @override
  double liquidMolarVolume(double t, Float64List x) =>
      liquidMolarVolumeAt(t, x, 0);

  @override
  double vaporDensity(double t, double p, Float64List y) {
    var tcm = 0.0, pcm = 0.0, om = 0.0, mwv = 0.0, sy = 0.0;
    for (var i = 0; i < comps.length; i++) {
      sy += y[i];
    }
    if (sy <= 0) sy = 1;
    for (var i = 0; i < comps.length; i++) {
      final yi = y[i] / sy;
      tcm += yi * _tc[i];
      pcm += yi * _pc[i];
      om += yi * _om[i];
      mwv += yi * mw[i];
    }
    final tr = t / tcm, pr = p / pcm;
    final b0 = 0.083 - 0.422 / math.pow(tr, 1.6);
    final b1 = 0.139 - 0.172 / math.pow(tr, 4.2);
    final z = (1 + (b0 + om * b1) * pr / tr).clamp(0.30, 1.05);
    return p * mwv / (1000 * z * gasR * t);
  }

  @override
  double surfaceTension(double t, Float64List x) {
    var s = 0.0;
    for (var i = 0; i < comps.length; i++) {
      s += x[i] * math.pow(comps[i].surfaceTensionOf(t), 0.25);
    }
    return math.pow(s, 4).toDouble();
  }

  @override
  double liquidViscosity() => _mu;
}
