// Independent velocity-form PID (PHYSICS.md §10.2) with modes, setpoint
// re-basing, derivative on filtered PV and clamp anti-windup. No engine
// imports. Used to recompute VC-16.1, 16.1b, 16.2, 16.3.
library;

enum RefAction { direct, reverse }

enum RefMode { man, auto }

class RefPid {
  final double kc, ti, td;
  final RefAction action;
  final bool spKick;
  final double lo, hi, opLo, opHi;
  RefMode mode;
  double sp; // PV units
  double op; // %
  double _ePrev = 0;
  double _pvf1 = double.nan, _pvf2 = double.nan;
  double lastPvPct = double.nan;

  RefPid({
    required this.kc,
    required this.ti,
    this.td = 0,
    required this.action,
    this.spKick = true,
    this.lo = 0,
    this.hi = 100,
    this.opLo = 0,
    this.opHi = 100,
    this.mode = RefMode.auto,
    required this.sp,
    required this.op,
  });

  double get s => action == RefAction.direct ? 1 : -1;
  double pct(double v) => 100 * (v - lo) / (hi - lo);

  /// Operator/scenario setpoint change: re-bases e*_{k−1} when !spKick.
  void setSp(double newSp) {
    sp = newSp;
    if (!spKick && !lastPvPct.isNaN) _ePrev = s * (lastPvPct - pct(sp));
  }

  /// MAN → AUTO: setpoint tracking, e*_{k−1} = 0.
  void toAuto(double pv) {
    sp = pv;
    _ePrev = 0;
    mode = RefMode.auto;
  }

  void toMan() => mode = RefMode.man;

  /// One execution with interval h. Returns the new OP.
  double execute(double pv, double h) {
    final pvPct = pct(pv);
    final e = s * (pvPct - pct(sp));
    double dTerm = 0;
    if (td > 0) {
      final tf = td / 8;
      if (_pvf1.isNaN) {
        _pvf1 = pvPct;
        _pvf2 = pvPct;
      }
      final pvf = _pvf1 + (pvPct - _pvf1) * h / (tf + h);
      dTerm = s * (td / h) * (pvf - 2 * _pvf1 + _pvf2);
      _pvf2 = _pvf1;
      _pvf1 = pvf;
    }
    if (mode == RefMode.auto) {
      final iTerm = ti.isFinite ? (h / ti) * e : 0.0;
      final dOp = kc * ((e - _ePrev) + iTerm + dTerm);
      op = (op + dOp).clamp(opLo, opHi);
    }
    _ePrev = e;
    lastPvPct = pvPct;
    return op;
  }
}
