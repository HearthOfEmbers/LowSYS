import 'dart:math' as math;
import 'dart:typed_data';

import '../core/ids.dart';
import 'fault_effects.dart';
import 'fault_spec.dart';

class _Fault {
  final FaultId id;
  final FaultSpec spec;
  bool cleared = false;
  _Fault(this.id, this.spec);
}

/// Holds the injected faults and turns them into effective parameters (PHYSICS.md 11, ENGINE_API.md 9).
class FaultManager {
  final List<_Fault> _faults = [];
  int _counter = 0;

  /// Antifoam injection (SCOPE.md 4.2): after 300 s dead time the foaming severity decays with tau = 600 s.
  bool _antifoam = false;
  double _antifoamSince = 0;

  final double systemFactor;
  final double phiDcBase;
  FaultManager({this.systemFactor = 1.0, this.phiDcBase = 0.5});

  FaultId inject(FaultSpec spec) {
    final id = 'F${++_counter}';
    _faults.add(_Fault(id, spec));
    return id;
  }

  void clear(FaultId id) {
    for (final f in _faults) {
      if (f.id == id) f.cleared = true;
    }
  }

  void clearAll() {
    for (final f in _faults) {
      f.cleared = true;
    }
  }

  bool get antifoam => _antifoam;
  void setAntifoam(bool on, double time) {
    if (on && !_antifoam) _antifoamSince = time;
    _antifoam = on;
  }

  /// Severity s(t) of [spec] at time [t] (PHYSICS.md 11.1).
  static double severityAt(FaultSpec spec, double t) {
    if (t < spec.onset) return 0;
    if (spec.ramp <= 0) return spec.severity;
    return spec.severity * ((t - spec.onset) / spec.ramp).clamp(0.0, 1.0);
  }

  double _foamFactor(double t) {
    if (!_antifoam) return 1.0;
    final dtOn = t - _antifoamSince - 300;
    return dtOn <= 0 ? 1.0 : math.exp(-dtOn / 600);
  }

  /// Active faults as snapshot info at time [t]; hidden faults are omitted.
  List<FaultInfo> activeAt(double t) => [
        for (final f in _faults)
          if (!f.cleared && !f.spec.hidden)
            FaultInfo(
              id: f.id,
              type: f.spec.type,
              location: f.spec.location,
              severity: severityAt(f.spec, t) * (f.spec.type == FaultType.foaming ? _foamFactor(t) : 1.0),
              finalSeverity: f.spec.severity,
              onset: f.spec.onset,
              ramp: f.spec.ramp,
              params: f.spec.params,
            ),
      ];

  /// Active (not cleared, not hidden) faults with their final severities.
  List<FaultInfo> get active => activeAt(double.infinity);

  bool get hasActive => _faults.any((f) => !f.cleared);

  /// Builds the effective parameters for time [t] (called at the start of every step).
  void apply(double t, EffectiveParams ep, Float64List baseZ) {
    ep.reset(systemFactor, phiDcBase);
    for (var i = 0; i < baseZ.length; i++) {
      ep.zEff[i] = baseZ[i];
    }
    for (final f in _faults) {
      if (f.cleared) continue;
      final s = severityAt(f.spec, t);
      if (s <= 0) continue;
      final loc = f.spec.location;
      switch (f.spec.type) {
        case FaultType.trayDamage:
          for (var j = 1; j < ep.n - 1; j++) {
            if (loc.coversStage(j)) ep.brokenS[j] = math.max(ep.brokenS[j], s);
          }
        case FaultType.trayFouling:
          final mode = (f.spec.params['mode'] as String?) ?? 'both';
          for (var j = 1; j < ep.n - 1; j++) {
            if (!loc.coversStage(j)) continue;
            if (mode == 'holes' || mode == 'both') ep.holeScale[j] *= 1 - 0.8 * s;
            if (mode == 'downcomer' || mode == 'both') ep.apronScale[j] *= 1 - 0.9 * s;
          }
        case FaultType.foaming:
          final se = s * _foamFactor(t);
          for (var j = 1; j < ep.n - 1; j++) {
            if (!loc.coversStage(j)) continue;
            final sf = 1 - 0.45 * se;
            ep.sfFroth[j] *= sf;
            ep.sfFlood[j] *= sf;
            ep.phiDc[j] = math.min(ep.phiDc[j], phiDcBase - 0.2 * se);
          }
        case FaultType.feedComposition:
          final dz = f.spec.params['dz'];
          for (var i = 0; i < ep.nc; i++) {
            double d = 0;
            if (dz is List) {
              d = i < dz.length ? (dz[i]! as num).toDouble() : 0;
            } else if (i == 0) {
              d = 0.15;
            }
            ep.zEff[i] += s * d;
          }
          var sum = 0.0;
          for (var i = 0; i < ep.nc; i++) {
            ep.zEff[i] = math.max(ep.zEff[i], 0);
            sum += ep.zEff[i];
          }
          if (sum > 0) {
            for (var i = 0; i < ep.nc; i++) {
              ep.zEff[i] /= sum;
            }
          }
        default:
          break;
      }
    }
  }

  Map<String, Object?> toJson() => {
        'counter': _counter,
        'antifoam': _antifoam,
        'antifoamSince': _antifoamSince,
        'faults': [
          for (final f in _faults) {'id': f.id, 'spec': f.spec.toJson(), 'cleared': f.cleared},
        ],
      };

  void loadJson(Map<String, Object?> j) {
    _faults.clear();
    _counter = (j['counter']! as num).toInt();
    _antifoam = j['antifoam']! as bool;
    _antifoamSince = (j['antifoamSince']! as num).toDouble();
    for (final e in (j['faults']! as List<Object?>)) {
      final m = e! as Map<String, Object?>;
      final f = _Fault(m['id']! as String, FaultSpec.fromJson(m['spec']! as Map<String, Object?>));
      f.cleared = m['cleared']! as bool;
      _faults.add(f);
    }
  }
}
