import 'dart:math' as math;

import '../core/rng.dart';

enum ValveFault { none, stuck, failOpen, failClosed }

enum ValveCharacteristic { linear, equalPercentage }

/// Control valve (PHYSICS.md 10.3): actuator lag, characteristic, supply disturbance, bypass, F20 faults.
class Valve {
  final String id;

  /// True for the Tier-2-only valves while the column runs Tier 1.
  bool hidden = false;

  /// Flow at 100 % (mol/s); for the steam valve of Tiers 2/3 the duty request scale (W).
  double fMax;
  final double tau;
  final ValveCharacteristic characteristic;

  /// Actual position p, command c (both %), and the bypass: target lever value (-1 closed, 0..100) and
  /// the actual hand-wheel opening.
  double position, command;
  double bypassTarget = -1;
  double bypassPos = 0;
  ValveFault fault = ValveFault.none;

  /// Supply disturbance d (Ornstein-Uhlenbeck, sigma 0.010, tau 30 s); 0 with noise off.
  final OuNoise _d = OuNoise(0.010, 30);
  Rng _rng;

  /// Flow cap (mol/s): infinity, or what the hydraulic stage could deliver last step (PHYSICS.md 10.3).
  double cap = double.infinity;

  /// Last valve flow F_k.
  double flow = 0;

  Valve(this.id, this.fMax, int seed,
      {this.tau = 2.0,
      this.characteristic = ValveCharacteristic.linear,
      double op = 0})
      : position = op,
        command = op,
        _rng = Rng.stream(seed, 'valve:$id:d');

  double get disturbance => _d.value;
  bool get bypassActive => bypassTarget >= 0 || bypassPos > 1e-9;

  double g(double p) {
    final x = p.clamp(0.0, 100.0) / 100;
    if (characteristic == ValveCharacteristic.linear) return x;
    const r = 50.0;
    return (math.pow(r, x) - 1) / (r - 1);
  }

  /// Sub-step update from the loop OP [op]; returns the flow F_k.
  double step(double h, double op, bool noise) {
    if (noise) {
      _d.step(h, _rng);
    }
    final d = noise ? _d.value : 0.0;
    switch (fault) {
      case ValveFault.none:
        command = op;
      case ValveFault.stuck:
        break;
      case ValveFault.failOpen:
        command = 100;
      case ValveFault.failClosed:
        command = 0;
    }
    if (fault != ValveFault.stuck) {
      position += (command - position) * h / (tau + h);
      if (position.abs() < 1e-9 && command == 0) position = 0;
    }
    // bypass hand wheel: at most 2 %/s
    final tgt = bypassTarget >= 0 ? bypassTarget : 0.0;
    final dMax = 2.0 * h;
    bypassPos += (tgt - bypassPos).clamp(-dMax, dMax);
    final eff = bypassActive ? bypassPos : position;
    final f = fMax * g(eff) * (1 + d);
    flow = f.clamp(0.0, cap).toDouble();
    if (flow < 1e-12) flow = 0; // a closed valve passes exactly nothing
    return flow;
  }

  /// Initialise so that the valve passes [f] with the loop OP [op] (PHYSICS.md 10.4 initialisation).
  void init(double op) {
    position = op;
    command = op;
    bypassTarget = -1;
    bypassPos = 0;
    fault = ValveFault.none;
    cap = double.infinity;
  }

  /// Flow the characteristic expects for OP [op] (the C4 straight line).
  double expectedFlow(double op) => fMax * g(op);

  void reseed(int seed) {
    _rng = Rng.stream(seed, 'valve:$id:d');
  }

  void resetNoise() {
    _d.value = 0;
  }

  Map<String, Object?> toJson() => {
        'p': position,
        'c': command,
        'bt': bypassTarget,
        'bp': bypassPos,
        'fault': fault.name,
        'd': _d.value,
        'cap': cap.isFinite ? cap : null,
        'flow': flow,
        'fMax': fMax,
        'rng': _rng.toJson(),
      };

  void loadJson(Map<String, Object?> j) {
    position = (j['p']! as num).toDouble();
    command = (j['c']! as num).toDouble();
    bypassTarget = (j['bt']! as num).toDouble();
    bypassPos = (j['bp']! as num).toDouble();
    fault = ValveFault.values.firstWhere((e) => e.name == j['fault']);
    _d.value = (j['d']! as num).toDouble();
    cap = (j['cap'] as num?)?.toDouble() ?? double.infinity;
    flow = (j['flow']! as num).toDouble();
    fMax = (j['fMax']! as num).toDouble();
    _rng.loadJson(j['rng']! as Map<String, Object?>);
  }
}
