import '../core/ids.dart';

class PidParams {
  final double kc, ti, td;
  final Action action;
  final double pvLo, pvHi;
  const PidParams({
    required this.kc,
    required this.ti,
    this.td = 0,
    required this.action,
    this.pvLo = 0,
    this.pvHi = 100,
  });
}

enum ValveFault { none, stuck, failOpen, failClosed }

/// Control valve with a first-order actuator lag (PHYSICS.md 10.2/10.3).
class Valve {
  final String id;

  /// Flow at 100 % (mol/s)
  final double maxFlow;

  /// s
  final double lag;
  ValveFault fault = ValveFault.none;

  /// Actual flow (mol/s)
  double flow;
  Valve(this.id, this.maxFlow, this.lag, this.flow);

  /// Advance the actuator towards [opPct], implicit Euler.
  void update(double opPct, double dt) {
    final cmd = switch (fault) {
      ValveFault.none => opPct / 100 * maxFlow,
      ValveFault.stuck => flow,
      ValveFault.failOpen => maxFlow,
      ValveFault.failClosed => 0.0,
    };
    flow += (cmd - flow) * dt / (lag + dt);
  }
}

/// A PID loop on a percentage-span PV (PHYSICS.md 10.1, velocity form).
class ControlLoop {
  final LoopTag tag;
  final String pvRef;
  final String mvRef;
  LoopMode mode;

  /// Setpoint in PV units (% of span for levels).
  double sp;

  /// Output, % valve.
  double op;
  final PidParams params;
  final bool idealFlow;

  /// Transmitter time constant (s).
  final double tauMeas;

  /// Filtered (measured) PV, same units as [sp].
  double pv = 0;
  double _ePrev = 0;
  bool _pvInit = false;

  ControlLoop({
    required this.tag,
    required this.pvRef,
    required this.mvRef,
    this.mode = LoopMode.auto,
    required this.sp,
    required this.op,
    required this.params,
    this.idealFlow = false,
    this.tauMeas = 2.0,
  });

  double _norm(double v) =>
      (v - params.pvLo) / (params.pvHi - params.pvLo) * 100;

  void _initPv(double raw) {
    pv = raw;
    _pvInit = true;
    _ePrev = _err();
  }

  double _err() {
    final e = _norm(pv) - _norm(sp);
    return params.action == Action.direct ? e : -e;
  }

  /// One execution (called every main step).
  void execute(double dt, double rawPv) {
    if (!_pvInit) _initPv(rawPv);
    pv += (rawPv - pv) * dt / (tauMeas + dt);
    final e = _err();
    if (mode == LoopMode.auto) {
      final dOp = params.kc *
          ((e - _ePrev) + (params.ti.isFinite ? dt / params.ti * e : 0.0));
      op = (op + dOp).clamp(0.0, 100.0);
    }
    _ePrev = e;
  }

  /// MAN to AUTO is bumpless: SP tracks PV and the velocity form continues from the current OP.
  void toMode(LoopMode m) {
    if (m == mode) return;
    if (m == LoopMode.auto) sp = pv;
    mode = m;
    _ePrev = _err();
  }

  void setSp(double v) {
    sp = v;
    // A setpoint step must not kick the output through the proportional term.
    _ePrev = _err();
  }

  Map<String, Object?> toJson() => {
        'tag': tag,
        'mode': mode.name,
        'sp': sp,
        'op': op,
        'pv': pv,
        'ePrev': _ePrev,
        'pvInit': _pvInit
      };

  void loadJson(Map<String, Object?> j) {
    mode = LoopMode.values.firstWhere((e) => e.name == j['mode']);
    sp = (j['sp']! as num).toDouble();
    op = (j['op']! as num).toDouble();
    pv = (j['pv']! as num).toDouble();
    _ePrev = (j['ePrev']! as num).toDouble();
    _pvInit = j['pvInit']! as bool;
  }
}

/// Process values the loops read.
class MeasurementBus {
  double drumLevelPct = 0;
  double sumpLevelPct = 0;
  double read(String ref) => switch (ref) {
        'drum.levelPct' => drumLevelPct,
        'sump.levelPct' => sumpLevelPct,
        _ => throw ArgumentError('Unknown PV reference $ref'),
      };
}

/// M1 control system: the two level loops (drum to D, sump to B), each with a valve.
/// The flow loops are ideal and live in the stepper (PHYSICS.md 10.2).
class ControlSystem {
  final List<ControlLoop> loops;
  final Valve distillateValve;
  final Valve bottomsValve;

  ControlSystem._(this.loops, this.distillateValve, this.bottomsValve);

  factory ControlSystem.levels({
    required double kc,
    required double ti,
    required double drumSp,
    required double sumpSp,
    required double dMax,
    required double bMax,
    required double dInit,
    required double bInit,
  }) {
    final p = PidParams(kc: kc, ti: ti, action: Action.direct);
    final lc101 = ControlLoop(
      tag: 'LC-101',
      pvRef: 'drum.levelPct',
      mvRef: 'distillateValve',
      sp: drumSp,
      op: (dInit / dMax * 100).clamp(0.0, 100.0),
      params: p,
    );
    final lc102 = ControlLoop(
      tag: 'LC-102',
      pvRef: 'sump.levelPct',
      mvRef: 'bottomsValve',
      sp: sumpSp,
      op: (bInit / bMax * 100).clamp(0.0, 100.0),
      params: p,
    );
    return ControlSystem._(
      [lc101, lc102],
      Valve('distillateValve', dMax, 2.0, dInit),
      Valve('bottomsValve', bMax, 2.0, bInit),
    );
  }

  ControlLoop loop(LoopTag tag) => loops.firstWhere((l) => l.tag == tag,
      orElse: () => throw ArgumentError('No loop $tag'));

  void setMode(LoopTag tag, LoopMode mode) => loop(tag).toMode(mode);
  void setSp(LoopTag tag, double sp) => loop(tag).setSp(sp);
  void setOp(LoopTag tag, double op) => loop(tag).op = op.clamp(0.0, 100.0);

  /// PHYSICS.md 10.1, called by the stepper at the end of every step (step 12).
  void execute(double dt, MeasurementBus pvs) {
    for (final l in loops) {
      l.execute(dt, pvs.read(l.pvRef));
    }
    distillateValve.update(loops[0].op, dt);
    bottomsValve.update(loops[1].op, dt);
  }

  Map<String, Object?> toJson() => {
        'loops': [for (final l in loops) l.toJson()],
        'dMax': distillateValve.maxFlow,
        'bMax': bottomsValve.maxFlow,
        'dFlow': distillateValve.flow,
        'bFlow': bottomsValve.flow,
        'dFault': distillateValve.fault.name,
        'bFault': bottomsValve.fault.name,
      };

  void loadJson(Map<String, Object?> j) {
    final ls = j['loops']! as List<Object?>;
    for (var i = 0; i < loops.length; i++) {
      loops[i].loadJson(ls[i]! as Map<String, Object?>);
    }
    distillateValve.flow = (j['dFlow']! as num).toDouble();
    bottomsValve.flow = (j['bFlow']! as num).toDouble();
    distillateValve.fault =
        ValveFault.values.firstWhere((e) => e.name == j['dFault']);
    bottomsValve.fault =
        ValveFault.values.firstWhere((e) => e.name == j['bFault']);
  }
}
