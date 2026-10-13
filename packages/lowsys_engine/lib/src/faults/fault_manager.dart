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

  /// Component ids in column order, for `dz` maps (set by the simulator).
  List<String> componentIds = const [];

  final double systemFactor;
  final double phiDcBase;
  FaultManager({this.systemFactor = 1.0, this.phiDcBase = 0.5});

  /// Called when faults are injected, cleared or the antifoam changes (the simulator clears its steady flag).
  void Function()? onChange;

  /// Validation hook for control faults (installed by the simulator).
  void Function(FaultSpec spec)? validator;

  FaultId inject(FaultSpec spec) {
    final t0 = spec.type;
    if (t0 == FaultType.instrument ||
        t0 == FaultType.transmitter ||
        t0 == FaultType.valve) {
      validator?.call(spec);
      if (t0 != FaultType.valve) {
        // at most one F19/F28 fault per tag: the new one replaces the old
        for (final f in _faults) {
          if (!f.cleared &&
              f.spec.location.tagName == spec.location.tagName &&
              (f.spec.type == FaultType.instrument ||
                  f.spec.type == FaultType.transmitter)) {
            f.cleared = true;
          }
        }
      }
    }
    final id = 'F${++_counter}';
    _faults.add(_Fault(id, spec));
    onChange?.call();
    return id;
  }

  void clear(FaultId id) {
    for (final f in _faults) {
      if (f.id == id) f.cleared = true;
    }
    onChange?.call();
  }

  void clearAll() {
    for (final f in _faults) {
      f.cleared = true;
    }
  }

  /// Trap bypass (F14): once opened the condensate-backup severity falls to zero over 300 s.
  double? _trapBypassSince;
  bool get trapBypassOpen => _trapBypassSince != null;
  void setTrapBypass(bool on, double time) {
    if (on && _trapBypassSince == null) _trapBypassSince = time;
    if (!on) _trapBypassSince = null;
    onChange?.call();
  }

  double _trapFactor(double t) {
    final s0 = _trapBypassSince;
    if (s0 == null) return 1.0;
    return (1 - (t - s0) / 300).clamp(0.0, 1.0);
  }

  bool get antifoam => _antifoam;
  void setAntifoam(bool on, double time) {
    if (on && !_antifoam) _antifoamSince = time;
    _antifoam = on;
    onChange?.call();
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
              severity: severityAt(f.spec, t) *
                  (f.spec.type == FaultType.foaming ? _foamFactor(t) : 1.0),
              finalSeverity: f.spec.severity,
              onset: f.spec.onset,
              ramp: f.spec.ramp,
              params: f.spec.params,
            ),
      ];

  /// Active (not cleared, not hidden) faults with their final severities.
  List<FaultInfo> get active => activeAt(double.infinity);

  /// Active instrument, transmitter and valve faults (F19, F28, F20).
  Iterable<FaultSpec> get controlSpecs sync* {
    for (final f in _faults) {
      if (f.cleared) continue;
      final t = f.spec.type;
      if (t == FaultType.instrument ||
          t == FaultType.transmitter ||
          t == FaultType.valve) {
        yield f.spec;
      }
    }
  }

  /// Clears every instrument/transmitter fault on [tag] (end of maintenance).
  void clearTag(String tag) {
    for (final f in _faults) {
      if (f.spec.location.tagName == tag &&
          (f.spec.type == FaultType.instrument ||
              f.spec.type == FaultType.transmitter)) {
        f.cleared = true;
      }
    }
    onChange?.call();
  }

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
            if (mode == 'holes' || mode == 'both')
              ep.holeScale[j] *= 1 - 0.8 * s;
            if (mode == 'downcomer' || mode == 'both')
              ep.apronScale[j] *= 1 - 0.9 * s;
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
          final sg = f.spec.params['sign'];
          final sign = sg is num ? sg.toDouble() : 1.0;
          final nc = ep.nc;
          final listed = List<bool>.filled(nc, false);
          final d = List<double>.filled(nc, 0);
          if (dz is List) {
            for (var i = 0; i < nc && i < dz.length; i++) {
              d[i] = (dz[i]! as num).toDouble();
              listed[i] = true;
            }
          } else if (dz is Map) {
            for (final e in dz.entries) {
              final k = componentIds.indexOf(e.key as String);
              if (k >= 0 && k < nc) {
                d[k] = (e.value! as num).toDouble();
                listed[k] = true;
              }
            }
          } else {
            d[0] = 0.15;
            listed[0] = true;
          }
          // sum-zero convention (PHYSICS.md 11): unlisted components absorb -sum(listed) in proportion to z
          var sumListed = 0.0, zRest = 0.0;
          for (var i = 0; i < nc; i++) {
            if (listed[i]) {
              sumListed += d[i];
            } else {
              zRest += ep.zEff[i];
            }
          }
          for (var i = 0; i < nc; i++) {
            if (!listed[i]) {
              d[i] = zRest > 0
                  ? -sumListed * ep.zEff[i] / zRest
                  : -sumListed /
                      (nc - listed.where((e) => !e).length.clamp(1, nc));
            }
          }
          var clamped = false;
          for (var i = 0; i < nc; i++) {
            ep.zEff[i] += sign * s * d[i];
            if (ep.zEff[i] < 0) {
              ep.zEff[i] = 0;
              clamped = true;
            }
          }
          if (clamped) {
            var sum = 0.0;
            for (var i = 0; i < nc; i++) {
              sum += ep.zEff[i];
            }
            if (sum > 0) {
              for (var i = 0; i < nc; i++) {
                ep.zEff[i] /= sum;
              }
            }
          }
        case FaultType.feedThermal:
          final dT = (f.spec.params['dT'] as num?)?.toDouble() ?? -40.0;
          final dq = (f.spec.params['dq'] as num?)?.toDouble() ?? 0.3;
          ep.feedDt += s * dT;
          ep.feedDq += s * dq;
        case FaultType.coolingLoss:
          if ((f.spec.params['mode'] ?? 'flow') == 'temperature') {
            ep.cwTempAdd += 15 * s;
          } else {
            ep.cwFlowScale *= 1 - s;
          }
        case FaultType.condenserFouling:
          ep.condFoulS = math.max(ep.condFoulS, s);
        case FaultType.nonCondensables:
          ep.epsI += 1e-4 * s;
        case FaultType.refluxPumpTrip:
          ep.refluxCapScale *= 1 - s;
        case FaultType.reboilerFouling:
          ep.rebFoulS = math.max(ep.rebFoulS, s);
        case FaultType.condensateBackup:
          ep.fFlooded = math.max(ep.fFlooded, 0.8 * s * _trapFactor(t));
        case FaultType.steamHeaderLoss:
          ep.headerScale *= 1 - 0.6 * s;
        default:
          break;
      }
    }
  }

  Map<String, Object?> toJson() => {
        'counter': _counter,
        'antifoam': _antifoam,
        'antifoamSince': _antifoamSince,
        'trapBypassSince': _trapBypassSince,
        'faults': [
          for (final f in _faults)
            {'id': f.id, 'spec': f.spec.toJson(), 'cleared': f.cleared},
        ],
      };

  void loadJson(Map<String, Object?> j) {
    _faults.clear();
    _counter = (j['counter']! as num).toInt();
    _antifoam = j['antifoam']! as bool;
    _antifoamSince = (j['antifoamSince']! as num).toDouble();
    _trapBypassSince = (j['trapBypassSince'] as num?)?.toDouble();
    for (final e in (j['faults']! as List<Object?>)) {
      final m = e! as Map<String, Object?>;
      final f = _Fault(m['id']! as String,
          FaultSpec.fromJson(m['spec']! as Map<String, Object?>));
      f.cleared = m['cleared']! as bool;
      _faults.add(f);
    }
  }
}
