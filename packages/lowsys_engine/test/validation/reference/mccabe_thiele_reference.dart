// Independent McCabe–Thiele / FUG reference formulas for a binary with
// constant relative volatility. Pure Dart, no engine imports — used to
// re-derive the VALIDATION.md VC-1, VC-2 and VC-3.1 numbers.
//
// Everything here is textbook closed form (Seader, Henley & Roper ch. 7;
// McCabe, Smith & Harriott ch. 21). Nothing shares code with the engine.
library;

import 'dart:math' as math;

/// Equilibrium curve y* = αx / (1 + (α − 1)x).
double yEq(double x, double alpha) => alpha * x / (1 + (alpha - 1) * x);

/// Inverse equilibrium: x such that y*(x) = y.
double xEq(double y, double alpha) => y / (alpha - (alpha - 1) * y);

/// Intersection of the q-line through (z, z) with the equilibrium curve.
/// q-line: y = q/(q−1) x − z/(q−1)  (vertical x = z at q = 1).
({double x, double y}) qLinePinch(double alpha, double z, double q) {
  if ((q - 1).abs() < 1e-12) return (x: z, y: yEq(z, alpha));
  // q/(q-1) x - z/(q-1) = αx/(1+(α-1)x)
  // (q x - z)(1 + (α-1)x) = α x (q-1)
  // (α-1) q x² + (q - z(α-1) - α(q-1)) x - z = 0
  final a = (alpha - 1) * q;
  final b = q - z * (alpha - 1) - alpha * (q - 1);
  final c = -z;
  if (a.abs() < 1e-14) {
    final x = -c / b;
    return (x: x, y: yEq(x, alpha));
  }
  final disc = b * b - 4 * a * c;
  final r1 = (-b + math.sqrt(disc)) / (2 * a);
  final r2 = (-b - math.sqrt(disc)) / (2 * a);
  // pick the root in (0, 1)
  final x = (r1 > 0 && r1 < 1) ? r1 : r2;
  return (x: x, y: yEq(x, alpha));
}

/// Feed-pinch minimum reflux: the rectifying line from (xD, xD) through the
/// pinch point (x*, y*) has slope R/(R+1).
double rMinFeedPinch(double alpha, double z, double q, double xD) {
  final p = qLinePinch(alpha, z, q);
  final slope = (xD - p.y) / (xD - p.x);
  return slope / (1 - slope);
}

/// General minimum reflux (handles tangent pinches): s_min = max over
/// x in [x_q, xD) of (xD − y*(x))/(xD − x).
double rMinScan(double alpha, double z, double q, double xD, {int n = 20000}) {
  final xq = qLinePinch(alpha, z, q).x;
  var sMax = 0.0;
  for (var i = 0; i < n; i++) {
    final x = xq + (xD - xq) * i / n;
    final s = (xD - yEq(x, alpha)) / (xD - x);
    if (s > sMax) sMax = s;
  }
  return sMax / (1 - sMax);
}

/// Fenske minimum stages (including the reboiler as a stage).
double fenskeNmin(double alpha, double xD, double xB) =>
    math.log((xD / (1 - xD)) * ((1 - xB) / xB)) / math.log(alpha);

/// Fenske identity at total reflux for the symmetric case xB = 1 − xD:
/// (xD/(1−xD))² = α^N  →  xD = α^{N/2} / (1 + α^{N/2}).
double fenskeSymmetricXd(double alpha, int nStages) {
  final r = math.pow(alpha, nStages / 2).toDouble();
  return r / (1 + r);
}

/// Gilliland correlation. Returns X, Y and N.
({double x, double y, double n}) gilliland(double nMin, double r, double rMin,
    {bool eduljee = false}) {
  final x = (r - rMin) / (r + 1);
  final double y;
  if (eduljee) {
    y = 0.75 * (1 - math.pow(x, 0.5668));
  } else {
    // Molokanov et al. (1972)
    y = 1 -
        math.exp((1 + 54.4 * x) / (11 + 117.2 * x) * (x - 1) / math.sqrt(x));
  }
  final n = (nMin + y) / (1 - y);
  return (x: x, y: y, n: n);
}

class SteppingResult {
  final List<double> x; // x_j of stage j (index 0 = stage 1)
  final List<double> y; // y_j
  final int stages; // integer stage count (stages stepped until x <= xB)
  final double fractional; // (n−1) + (x_{n−1} − xB)/(x_{n−1} − x_n)
  final int feedStage; // first stage whose liquid x is below the intersection
  final double lOverV, lbarOverVbar, xIntersect, yIntersect;
  SteppingResult(this.x, this.y, this.stages, this.fractional, this.feedStage,
      this.lOverV, this.lbarOverVbar, this.xIntersect, this.yIntersect);
}

/// Step stages from (xD, xD) downward. Rectifying line y = L/V x + xD/(R+1);
/// stripping line through (xB, xB) and the operating-line intersection.
/// Switch to the stripping line once the liquid x drops below the
/// intersection x (the "optimal feed" rule). Basis F = 1.
SteppingResult stepStages(
    double alpha, double z, double q, double xD, double xB, double r,
    {int maxStages = 200}) {
  final d = (z - xB) / (xD - xB); // D/F
  final lv = r / (r + 1);
  final bIntercept = xD / (r + 1);
  // intersection of rectifying line with the q-line
  final double xi;
  if ((q - 1).abs() < 1e-12) {
    xi = z;
  } else {
    // lv x + bI = q/(q-1) x - z/(q-1)
    xi = (bIntercept + z / (q - 1)) / (q / (q - 1) - lv);
  }
  final yi = lv * xi + bIntercept;
  final lbarVbar = (yi - xB) / (xi - xB);
  final bInterceptS = xB - lbarVbar * xB; // = -B xB / Vbar
  // consistency: Vbar = V − (1−q)F, Lbar = L + qF
  final v = (r + 1) * d;
  final vbar = v - (1 - q);
  final lbar = r * d + q;
  final lbarVbarFlows = lbar / vbar;
  assert((lbarVbarFlows - lbarVbar).abs() < 1e-9,
      'stripping slope mismatch $lbarVbar vs $lbarVbarFlows');

  final xs = <double>[];
  final ys = <double>[];
  var y = xD;
  var stripping = false;
  var feed = -1;
  var n = 0;
  while (n < maxStages) {
    n++;
    final x = xEq(y, alpha);
    xs.add(x);
    ys.add(y);
    if (x <= xB) break;
    if (!stripping && x < xi) {
      stripping = true;
      feed = n;
    }
    y = stripping ? lbarVbar * x + bInterceptS : lv * x + bIntercept;
  }
  final xPrev = xs[n - 2];
  final xLast = xs[n - 1];
  final frac = (n - 1) + (xPrev - xB) / (xPrev - xLast);
  return SteppingResult(xs, ys, n, frac, feed, lv, lbarVbar, xi, yi);
}
