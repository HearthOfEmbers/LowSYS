// Independent FUG shortcut (validator), written from PHYSICS.md §14.3 / VALIDATION.md VC-9 only:
// Fenske N_min from the key recoveries, non-keys from Fenske at N_min, Underwood theta in (alpha_HK, alpha_LK)
// (here by Brent-free regula falsi, not bisection), R_min from the Fenske x_D, Gilliland via Molokanov, Kirkbride
// with x_B,LK and x_D,HK from the Fenske split. Plain lists, no engine types.
import 'dart:math' as math;

class FugRef {
  final double nMin, theta, rMin, r, n, nrOverNs, nR, dTotal, bTotal;
  final List<double> d, b;
  const FugRef(this.nMin, this.theta, this.rMin, this.r, this.n, this.nrOverNs, this.nR, this.dTotal, this.bTotal,
      this.d, this.b);
}

/// [alpha] relative to any reference; [z] feed mole fractions; [f] feed flow; [r] reflux ratio or null to use
/// [k] R_min.
FugRef fugRef(List<double> alpha, List<double> z, int lk, int hk, double rLK, double rHK,
    {double q = 1, double f = 100, double? r, double k = 1.3}) {
  final nc = z.length;
  final a = [for (final v in alpha) v / alpha[hk]];
  final dLK = rLK * f * z[lk], bLK = f * z[lk] - dLK;
  final bHK = rHK * f * z[hk], dHK = f * z[hk] - bHK;
  final nMin = math.log((dLK / bLK) * (bHK / dHK)) / math.log(a[lk]);
  final d = <double>[], b = <double>[];
  for (var i = 0; i < nc; i++) {
    final ratio = math.pow(a[i], nMin) * dHK / bHK;
    final fi = f * z[i];
    d.add(fi * ratio / (1 + ratio));
    b.add(fi / (1 + ratio));
  }
  final dt = d.reduce((x, y) => x + y), bt = b.reduce((x, y) => x + y);
  double phi(double th) {
    var s = 0.0;
    for (var i = 0; i < nc; i++) {
      s += a[i] * z[i] / (a[i] - th);
    }
    return s - (1 - q);
  }

  // regula falsi (Illinois) on (1 + eps, a_LK - eps): phi -> -inf at 1+, +inf at a_LK-
  var lo = 1 + 1e-12, hi = a[lk] - 1e-12, flo = phi(lo), fhi = phi(hi);
  var th = lo;
  var side = 0;
  for (var it = 0; it < 500; it++) {
    th = (lo * fhi - hi * flo) / (fhi - flo);
    final ft = phi(th);
    if (ft.abs() < 1e-15 || (hi - lo) < 1e-15) break;
    if (ft * fhi > 0) {
      hi = th;
      fhi = ft;
      if (side == 1) flo /= 2;
      side = 1;
    } else {
      lo = th;
      flo = ft;
      if (side == -1) fhi /= 2;
      side = -1;
    }
  }
  var sum = 0.0;
  for (var i = 0; i < nc; i++) {
    sum += a[i] * (d[i] / dt) / (a[i] - th);
  }
  final rMin = sum - 1;
  final rr = r ?? k * rMin;
  final x = (rr - rMin) / (rr + 1);
  final y = 1 - math.exp((1 + 54.4 * x) / (11 + 117.2 * x) * (x - 1) / math.sqrt(x));
  final n = (nMin + y) / (1 - y);
  final xBLK = b[lk] / bt, xDHK = d[hk] / dt;
  final kb = math.pow(z[hk] / z[lk] * (xBLK / xDHK) * (xBLK / xDHK) * bt / dt, 0.206).toDouble();
  return FugRef(nMin, th, rMin, rr, n, kb, n * kb / (1 + kb), dt, bt, d, b);
}
