import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../data/components_json.dart';

enum VaporPressureKind { antoineLog10MmHgC, dippr101, leeKesler }

/// Pure-component constants (PHYSICS.md 2.1). SI units except [mw] (g/mol).
@immutable
class Component {
  final ComponentId id;
  final String name;

  /// g/mol (= kg/kmol)
  final double mw;

  /// K
  final double tb, tc;

  /// Pa
  final double pc;
  final double omega;

  /// J/mol
  final double dHvapTb;

  /// J/mol/K at 298.15 K; J/mol/K^2
  final double cp0, dCp;

  /// kg/m3 at tRef (K)
  final double rhoRef, tRef;
  final double? zraOverride;

  /// N/m at 298.15 K
  final double sigmaRef;
  final VaporPressureKind vpKind;
  final List<double> vpCoeffs;
  final List<double>? mcWilliams;
  final bool vaporOnly;

  const Component({
    required this.id,
    required this.name,
    required this.mw,
    required this.tb,
    required this.tc,
    required this.pc,
    required this.omega,
    required this.dHvapTb,
    required this.cp0,
    required this.dCp,
    required this.rhoRef,
    required this.tRef,
    this.zraOverride,
    required this.sigmaRef,
    required this.vpKind,
    required this.vpCoeffs,
    this.mcWilliams,
    this.vaporOnly = false,
  });

  static const double _t0 = 298.15;
  static const double _mmHg = 133.322368;

  /// Saturation pressure (Pa) at [t] (K), PHYSICS.md 2.2.
  double vaporPressure(double t) {
    switch (vpKind) {
      case VaporPressureKind.antoineLog10MmHgC:
        return math.pow(10.0, vpCoeffs[0] - vpCoeffs[1] / (t - 273.15 + vpCoeffs[2])) *
            _mmHg;
      case VaporPressureKind.dippr101:
        return math.exp(vpCoeffs[0] +
            vpCoeffs[1] / t +
            vpCoeffs[2] * math.log(t) +
            vpCoeffs[3] * math.pow(t, vpCoeffs[4]));
      case VaporPressureKind.leeKesler:
        final tr = t / tc;
        final f0 = 5.92714 - 6.09648 / tr - 1.28862 * math.log(tr) + 0.169347 * math.pow(tr, 6);
        final f1 = 15.2518 - 15.6875 / tr - 13.4721 * math.log(tr) + 0.43577 * math.pow(tr, 6);
        return pc * math.exp(f0 + omega * f1);
    }
  }

  /// d ln P_sat / dT (1/K), PHYSICS.md 3.6.1.
  double dLnPsatDt(double t) {
    switch (vpKind) {
      case VaporPressureKind.antoineLog10MmHgC:
        final d = t - 273.15 + vpCoeffs[2];
        return math.ln10 * vpCoeffs[1] / (d * d);
      case VaporPressureKind.dippr101:
        return -vpCoeffs[1] / (t * t) +
            vpCoeffs[2] / t +
            vpCoeffs[3] * vpCoeffs[4] * math.pow(t, vpCoeffs[4] - 1);
      case VaporPressureKind.leeKesler:
        final tr = t / tc;
        return (6.09648 / (tr * tr) -
                1.28862 / tr +
                1.016082 * math.pow(tr, 5) +
                omega *
                    (15.6875 / (tr * tr) -
                        13.4721 / tr +
                        2.61462 * math.pow(tr, 5))) /
            tc;
    }
  }

  /// Liquid enthalpy (J/mol) relative to the liquid at 298.15 K (PHYSICS.md 3.3).
  double hLiquid(double t) {
    final d = t - _t0;
    return cp0 * d + 0.5 * dCp * d * d;
  }

  /// Heat of vaporisation (J/mol) by Watson's correlation (3.4).
  double dHvap(double t) =>
      t >= tc ? 0.0 : dHvapTb * math.pow((tc - t) / (tc - tb), 0.38);

  double hVapour(double t) => hLiquid(t) + dHvap(t);

  /// Rackett-ratio liquid density (kg/m3), PHYSICS.md 3.5.1.
  double liquidDensity(double t) {
    final zra = zraOverride ?? (0.29056 - 0.08775 * omega);
    return rhoRef *
        math.pow(
            zra,
            math.pow(1 - tRef / tc, 2 / 7) -
                math.pow(math.max(1 - t / tc, 0.0), 2 / 7));
  }

  /// Pure-component surface tension (N/m), PHYSICS.md 3.5.3.
  double surfaceTensionOf(double t) {
    if (t >= tc) return 0;
    return sigmaRef * math.pow((tc - t) / (tc - _t0), 1.22);
  }

  factory Component.fromJson(ComponentId id, Map<String, Object?> j) {
    double d(String k) => (j[k]! as num).toDouble();
    final kind =
        VaporPressureKind.values.firstWhere((e) => e.name == j['vpKind']);
    return Component(
      id: id,
      name: j['name']! as String,
      mw: d('mw'),
      tb: d('tb'),
      tc: d('tc'),
      pc: d('pc'),
      omega: d('omega'),
      dHvapTb: d('dHvapTb'),
      cp0: d('cp0'),
      dCp: d('dCp'),
      rhoRef: d('rhoRef'),
      tRef: d('tRef'),
      zraOverride: (j['zraOverride'] as num?)?.toDouble(),
      sigmaRef: d('sigmaRef'),
      vpKind: kind,
      vpCoeffs: [
        for (final v in (j['vpCoeffs']! as List<Object?>))
          (v! as num).toDouble()
      ],
      mcWilliams: (j['mcWilliams'] as List<Object?>?)
          ?.map((e) => (e! as num).toDouble())
          .toList(),
      vaporOnly: (j['vaporOnly'] as bool?) ?? false,
    );
  }
}

/// Component database, parsed once from [componentsJson].
class ComponentDb {
  final Map<ComponentId, Component> _byId;
  ComponentDb._(this._byId);

  static ComponentDb? _cached;

  static ComponentDb load() {
    return _cached ??= () {
      final raw = jsonDecode(componentsJson) as Map<String, Object?>;
      return ComponentDb._({
        for (final e in raw.entries)
          e.key: Component.fromJson(e.key, e.value! as Map<String, Object?>),
      });
    }();
  }

  Component operator [](ComponentId id) {
    final c = _byId[id];
    if (c == null) throw ConfigException('Unknown component "$id"');
    return c;
  }

  bool contains(ComponentId id) => _byId.containsKey(id);
  Iterable<ComponentId> get ids => _byId.keys;
}

/// Saturated water for the steam header (PHYSICS.md 2.2, DIPPR-101 inverse).
abstract final class WaterProps {
  static Component get _w => ComponentDb.load()['water'];

  /// Saturation pressure (Pa) at [t] (K).
  static double saturationP(double t) => _w.vaporPressure(t);

  /// Saturation temperature (K) at [p] (Pa): Newton on ln P with a bisection fallback.
  static double saturationT(double p) {
    final w = _w;
    final lnp = math.log(p);
    var t = 373.15 + 28 * math.log(p / 101325).clamp(-2.0, 3.0);
    t = t.clamp(280.0, 640.0);
    for (var i = 0; i < 30; i++) {
      final g = math.log(w.vaporPressure(t)) - lnp;
      final dg = w.dLnPsatDt(t);
      var dt = -g / dg;
      if (dt > 30) dt = 30;
      if (dt < -30) dt = -30;
      t += dt;
      if (dt.abs() < 1e-9) return t;
    }
    var lo = 273.16, hi = 646.0;
    for (var i = 0; i < 100; i++) {
      final mid = 0.5 * (lo + hi);
      if (w.vaporPressure(mid) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// Latent heat (J/mol) of water at [t] (K), Watson.
  static double latentHeat(double t) => _w.dHvap(t);
}
