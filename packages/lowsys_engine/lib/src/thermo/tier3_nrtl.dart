import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart';
import '../core/ids.dart';
import 'component.dart';
import 'tier2_raoult.dart';

/// NRTL binary parameters (PHYSICS.md 3.4.1; Beneke et al. 2013, App. B): tau_ij = a_ij + b_ij / T, T in K.
/// [first] is component 1 of the table row ("i" of i - j).
class NrtlPair {
  final ComponentId first, second;
  final double aij, aji, bij, bji, alpha;
  const NrtlPair(this.first, this.second, this.aij, this.aji, this.bij,
      this.bji, this.alpha);
}

const List<NrtlPair> nrtlPairs = [
  NrtlPair('methanol', 'water', -0.693, 2.732, 173.0, -617.3, 0.3),
  NrtlPair('ethanol', 'water', -0.801, 3.458, 246.2, -586.1, 0.3),
  NrtlPair('acetone', 'chloroform', 0.965, 0.538, -590.0, -106.4, 0.3),
];

/// Tier 3 for polar binaries: K_i = gamma_i P_sat,i / P with NRTL activity coefficients (PHYSICS.md 3.7, 3.8).
/// Enthalpies and physical properties are the Tier-2 ideal ones. In the bubble-point Newton gamma is held constant
/// in d ln K / dT.
class Tier3Nrtl extends Tier2Raoult {
  final Float64List _a, _b, _alpha;
  final Float64List _tau, _g, _s, _nn, _xn;
  final Float64List _lg;

  Tier3Nrtl._(super.comps, this._a, this._b, this._alpha, {super.viscosity})
      : _tau = Float64List(comps.length * comps.length),
        _g = Float64List(comps.length * comps.length),
        _s = Float64List(comps.length),
        _nn = Float64List(comps.length),
        _xn = Float64List(comps.length),
        _lg = Float64List(comps.length);

  /// Builds the model for [ids] (every pair must have parameters).
  factory Tier3Nrtl.fromIds(List<ComponentId> ids,
      {double viscosity = 0.00027}) {
    final db = ComponentDb.load();
    final n = ids.length;
    final a = Float64List(n * n),
        b = Float64List(n * n),
        al = Float64List(n * n);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        NrtlPair? pr;
        for (final c in nrtlPairs) {
          if ((c.first == ids[i] && c.second == ids[j]) ||
              (c.first == ids[j] && c.second == ids[i])) {
            pr = c;
          }
        }
        if (pr == null) {
          throw ConfigException(
              'No NRTL parameters for ${ids[i]} - ${ids[j]}');
        }
        final fwd = pr.first == ids[i];
        a[i * n + j] = fwd ? pr.aij : pr.aji;
        a[j * n + i] = fwd ? pr.aji : pr.aij;
        b[i * n + j] = fwd ? pr.bij : pr.bji;
        b[j * n + i] = fwd ? pr.bji : pr.bij;
        al[i * n + j] = al[j * n + i] = pr.alpha;
      }
    }
    return Tier3Nrtl._([for (final id in ids) db[id]], a, b, al,
        viscosity: viscosity);
  }

  factory Tier3Nrtl.fromConfig(ColumnConfig c) =>
      Tier3Nrtl.fromIds(c.components, viscosity: c.liquidViscosity);

  @override
  ThermoTier get tier => ThermoTier.t3;
  @override
  bool get xDependent => true;

  /// ln gamma_i of the liquid [x] (at [xo]) at [t] into [out] (at [oo]).
  void lnGamma(double t, Float64List x, int xo, Float64List out, int oo) {
    final n = comps.length;
    var sx = 0.0;
    for (var i = 0; i < n; i++) {
      sx += x[xo + i];
    }
    if (!(sx > 0)) sx = 1;
    for (var i = 0; i < n; i++) {
      _xn[i] = x[xo + i] / sx;
    }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) {
          _tau[i * n + j] = 0;
          _g[i * n + j] = 1;
        } else {
          final tau = _a[i * n + j] + _b[i * n + j] / t;
          _tau[i * n + j] = tau;
          _g[i * n + j] = math.exp(-_alpha[i * n + j] * tau);
        }
      }
    }
    // S_j = sum_k x_k G_kj ; N_j = sum_m x_m tau_mj G_mj
    for (var j = 0; j < n; j++) {
      var s = 0.0, nn = 0.0;
      for (var k = 0; k < n; k++) {
        s += _xn[k] * _g[k * n + j];
        nn += _xn[k] * _tau[k * n + j] * _g[k * n + j];
      }
      _s[j] = s;
      _nn[j] = nn;
    }
    for (var i = 0; i < n; i++) {
      var v = _nn[i] / _s[i];
      for (var j = 0; j < n; j++) {
        v += _xn[j] *
            _g[i * n + j] /
            _s[j] *
            (_tau[i * n + j] - _nn[j] / _s[j]);
      }
      out[oo + i] = v;
    }
  }

  @override
  void kAt(double t, double p, Float64List x, int xo, Float64List kOut,
      int ko) {
    final n = comps.length;
    lnGamma(t, x, xo, _lg, 0);
    for (var i = 0; i < n; i++) {
      kOut[ko + i] = math.exp(_lg[i]) * comps[i].vaporPressure(t) / p;
    }
  }

  /// Activity coefficients of the liquid [x] at [t] (allocates).
  Float64List gammas(double t, Float64List x) {
    final out = Float64List(comps.length);
    lnGamma(t, x, 0, out, 0);
    for (var i = 0; i < out.length; i++) {
      out[i] = math.exp(out[i]);
    }
    return out;
  }
}
