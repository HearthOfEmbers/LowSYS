// Independent ISA-18.2-style alarm with on/off delay and deadband
// (PHYSICS.md §10.8), used to recompute the VC-25.1 chatter numbers.
// No engine imports.
library;

class RefAlarm {
  final double limit, onDelay, offDelay, deadband;
  final bool high;
  bool active = false;
  double _overSince = double.nan, _underSince = double.nan;
  int raises = 0;
  RefAlarm(
      {required this.limit,
      this.onDelay = 5,
      this.offDelay = 10,
      this.deadband = 1,
      this.high = true});

  /// Feed the reading at time t; returns whether the alarm is active.
  bool update(double pv, double t) {
    final beyond = high ? pv > limit : pv < limit;
    final back = high ? pv < limit - deadband : pv > limit + deadband;
    if (!active) {
      if (beyond) {
        if (_overSince.isNaN) _overSince = t;
        if (t - _overSince >= onDelay) {
          active = true;
          raises++;
          _underSince = double.nan;
        }
      } else {
        _overSince = double.nan;
      }
    } else {
      if (back) {
        if (_underSince.isNaN) _underSince = t;
        if (t - _underSince >= offDelay) {
          active = false;
          _overSince = double.nan;
        }
      } else {
        _underSince = double.nan;
      }
    }
    return active;
  }
}
