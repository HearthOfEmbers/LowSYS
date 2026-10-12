import '../core/ids.dart';

/// PID settings (PHYSICS.md 10.2, 10.7).
class PidParams {
  /// %OP per % span; seconds (ti = infinity disables the integral term).
  final double kc, ti, td;
  final Action action;

  /// true: a setpoint change acts through the proportional term too (flow loops).
  final bool spKick;
  final double opLo, opHi;
  const PidParams({
    required this.kc,
    required this.ti,
    this.td = 0,
    required this.action,
    this.spKick = true,
    this.opLo = 0,
    this.opHi = 100,
  });
}

/// A PID loop in velocity form (PHYSICS.md 10.2). PV and SP are SI; the algorithm works in % of span.
class ControlLoop {
  final LoopTag tag;

  /// Instrument tag of the PV, valve id (or `FC-103.sp` for a cascade master) of the MV.
  final String pvTag;
  final String mvRef;
  final String? masterTag;
  final PidParams params;
  final bool fastLayer;

  /// PV span (SI), set from the instrument.
  double lo, hi;

  /// SP limits (SI), the bound lever's range.
  double spLo, spHi;

  LoopMode mode;

  /// The mode an IMAN master resumes.
  LoopMode requestedMode;
  bool shed = false;
  bool spTracked = false;

  /// Setpoint (SI) and output (%).
  double sp, op;

  // history for the velocity form
  double _eStar = 0;
  double _pvf1 = 0, _pvf2 = 0;
  double _pvPct1 = 0;
  bool _hist = false;
  double lastError = 0, lastDeltaOp = 0;

  ControlLoop({
    required this.tag,
    required this.pvTag,
    required this.mvRef,
    this.masterTag,
    required this.params,
    required this.fastLayer,
    required this.lo,
    required this.hi,
    double? spLo,
    double? spHi,
    this.mode = LoopMode.auto,
    this.sp = 0,
    this.op = 0,
  })  : spLo = spLo ?? lo,
        spHi = spHi ?? hi,
        requestedMode = mode;

  double get _s => params.action == Action.direct ? 1.0 : -1.0;

  double pct(double v) => 100 * (v - lo) / (hi - lo);

  /// Starts the loop history at the current PV (e = 0, PVf = PV).
  void initHistory(double pvSi) {
    final p = pct(pvSi);
    _pvf1 = p;
    _pvf2 = p;
    _pvPct1 = p;
    _eStar = 0;
    _hist = true;
  }

  double _lastPvSi = 0;

  /// One execution on the PV reading [pvSi] with interval [h]. The OP changes only in AUTO and CAS. Returns the OP.
  double execute(double pvSi, double h) {
    _lastPvSi = pvSi;
    if (!_hist) initHistory(pvSi);
    final pv = pct(pvSi);
    final spP = pct(sp);
    final s = _s;
    final e = s * (pv - spP);
    double pvf = pv;
    final td = params.td;
    if (td > 0) {
      final tauF = td / 8;
      pvf = _pvf1 + (pv - _pvf1) * h / (tauF + h);
    }
    final integral = params.ti.isFinite ? h / params.ti * e : 0.0;
    final deriv = td > 0 ? s * (td / h) * (pvf - 2 * _pvf1 + _pvf2) : 0.0;
    final dOp = params.kc * ((e - _eStar) + integral + deriv);
    if (mode == LoopMode.auto || mode == LoopMode.cas) {
      op = (op + dOp).clamp(params.opLo, params.opHi).toDouble();
      lastDeltaOp = dOp;
    } else {
      lastDeltaOp = 0;
    }
    _eStar = e;
    lastError = e;
    _pvf2 = _pvf1;
    _pvf1 = pvf;
    _pvPct1 = pv;
    return op;
  }

  /// Bumpless mode change (PHYSICS.md 10.2): MAN to AUTO tracks the PV into the SP.
  void setMode(LoopMode m) {
    if (m == mode) return;
    if (m == LoopMode.auto) {
      trackPv(_lastPvSi);
      shed = false;
    }
    mode = m;
    requestedMode = m;
  }

  /// An operator setpoint change: clamped to the SP limits; with `spKick` false the previous error is
  /// re-based so the output does not jump (PHYSICS.md 10.2). Cascade updates use [setSpCascade].
  void setSp(double v) {
    sp = v.clamp(spLo, spHi).toDouble();
    spTracked = false;
    if (!params.spKick && _hist) _eStar = _s * (_pvPct1 - pct(sp));
  }

  /// Setpoint from a master loop or the ratio station: no re-basing.
  void setSpCascade(double v) {
    sp = v.clamp(spLo, spHi).toDouble();
  }

  void setOp(double v) {
    op = v.clamp(params.opLo, params.opHi).toDouble();
  }

  /// MAN to AUTO: setpoint tracking (SP := PV) and e* := 0, so the output does not move.
  void trackPv(double pvSi) {
    sp = pvSi.clamp(spLo, spHi).toDouble();
    _eStar = 0;
    spTracked = true;
  }

  Map<String, Object?> toJson() => {
        'tag': tag,
        'mode': mode.name,
        'req': requestedMode.name,
        'shed': shed,
        'tracked': spTracked,
        'sp': sp,
        'op': op,
        'eStar': _eStar,
        'pvf1': _pvf1,
        'pvf2': _pvf2,
        'pvPct1': _pvPct1,
        'hist': _hist,
        'lastPv': _lastPvSi,
        'lastError': lastError,
        'lastDeltaOp': lastDeltaOp,
        'lo': lo,
        'hi': hi,
      };

  void loadJson(Map<String, Object?> j) {
    double d(String k) => (j[k]! as num).toDouble();
    mode = LoopMode.values.firstWhere((e) => e.name == j['mode']);
    requestedMode = LoopMode.values.firstWhere((e) => e.name == j['req']);
    shed = j['shed']! as bool;
    spTracked = j['tracked']! as bool;
    sp = d('sp');
    op = d('op');
    _eStar = d('eStar');
    _pvf1 = d('pvf1');
    _pvf2 = d('pvf2');
    _pvPct1 = d('pvPct1');
    _hist = j['hist']! as bool;
    _lastPvSi = d('lastPv');
    lastError = d('lastError');
    lastDeltaOp = d('lastDeltaOp');
    lo = d('lo');
    hi = d('hi');
  }
}
