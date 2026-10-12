import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../thermo/component.dart';
import '../thermo/thermo_model.dart';
import 'sim_snapshot.dart';

@immutable
class Point2 {
  final double x, y;
  const Point2(this.x, this.y);
  @override
  String toString() => 'Point2($x, $y)';
  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

@immutable
class Segment2 {
  final Point2 a, b;
  const Segment2(this.a, this.b);
}

@immutable
class StageCorner {
  /// Liquid and vapour composition of the stage.
  final double x, y;
  final int stage;
  final bool isFeed;
  const StageCorner(this.x, this.y, this.stage, this.isFeed);
}

@immutable
class RangeX {
  final double lo, hi;
  const RangeX(this.lo, this.hi);
}

/// Minimum-reflux construction (PHYSICS.md 14.1).
@immutable
class RminConstruction {
  /// Line from (xD, xD) with slope [slope]; drawn from [from] to [to].
  final Point2 from, to;

  /// Where the line touches the equilibrium curve.
  final Point2 touch;
  final double slope, rMin;
  const RminConstruction(
      {required this.from,
      required this.to,
      required this.touch,
      required this.slope,
      required this.rMin});
}

@immutable
class McCabeThieleData {
  final bool pseudoBinary;
  final String lightLabel, heavyLabel;
  final List<Point2> equilibriumTop;
  final List<Point2>? equilibriumBottom;
  final List<Point2> localEquilibrium;
  final Segment2? qLine;
  final List<Point2> cmoRectifying, cmoStripping;
  final List<Point2> operatingLocus;
  final List<Point2> staircase;
  final List<StageCorner> corners;
  final List<Point2> pseudoEquilibrium;
  final double xF, xD, xB;
  final RminConstruction? rmin;
  final List<RangeX> pinchZones;
  final bool transient;

  /// Intersection of the two CMO operating lines.
  final Point2 operatingIntersection;

  const McCabeThieleData({
    required this.pseudoBinary,
    required this.lightLabel,
    required this.heavyLabel,
    required this.equilibriumTop,
    this.equilibriumBottom,
    required this.localEquilibrium,
    required this.qLine,
    required this.cmoRectifying,
    required this.cmoStripping,
    required this.operatingLocus,
    required this.staircase,
    required this.corners,
    required this.pseudoEquilibrium,
    required this.xF,
    required this.xD,
    required this.xB,
    required this.rmin,
    required this.pinchZones,
    required this.transient,
    required this.operatingIntersection,
  });
}

@immutable
class StageStep {
  final double x, y;
  const StageStep(this.x, this.y);
}

@immutable
class SteppingResult {
  /// (x, y) of every stage from the top (stage 1 is the first below the total condenser).
  final List<StageStep> stages;

  /// Whole stages needed (the last one reaches x <= xB).
  final int count;

  /// Fractional stage count (interpolating the last step).
  final double fractional;

  /// Optimal feed stage: the first stage whose x is below the operating-line intersection.
  final int feedStage;

  /// Intersection of the operating lines.
  final double xIntersection, yIntersection;

  /// False when stepping stagnated (reflux at or below the minimum).
  final bool converged;
  const SteppingResult({
    required this.stages,
    required this.count,
    required this.fractional,
    required this.feedStage,
    required this.xIntersection,
    required this.yIntersection,
    required this.converged,
  });
}

/// Closed-form textbook utilities for a binary with constant alpha (PHYSICS.md 14.1; VALIDATION.md VC-1/2/3).
abstract final class McCabeThieleMath {
  /// y = alpha x / (1 + (alpha - 1) x)
  static double yEq(double x, double alpha) =>
      alpha * x / (1 + (alpha - 1) * x);

  /// Inverse of [yEq].
  static double xEq(double y, double alpha) => y / (alpha - (alpha - 1) * y);

  /// q-line intersection with the equilibrium curve. q-line: through (z, z), slope q/(q - 1), vertical for q = 1.
  static ({double x, double y}) qLinePinch(double alpha, double z, double q) {
    if ((q - 1).abs() < 1e-12) return (x: z, y: yEq(z, alpha));
    final s = q / (q - 1);
    final c0 = z * (1 - s);
    final c1 = s;
    // c1 (alpha-1) x^2 + (c0 (alpha-1) + c1 - alpha) x + c0 = 0
    final qa = c1 * (alpha - 1);
    final qb = c0 * (alpha - 1) + c1 - alpha;
    final qc = c0;
    double x;
    if (qa.abs() < 1e-14) {
      x = -qc / qb;
    } else {
      final disc = math.sqrt(math.max(0.0, qb * qb - 4 * qa * qc));
      final r1 = (-qb + disc) / (2 * qa);
      final r2 = (-qb - disc) / (2 * qa);
      final ok1 = r1 >= -1e-12 && r1 <= 1 + 1e-12;
      final ok2 = r2 >= -1e-12 && r2 <= 1 + 1e-12;
      if (ok1 && !ok2) {
        x = r1;
      } else if (ok2 && !ok1) {
        x = r2;
      } else {
        // both (or neither) inside: take the one closest to z
        x = (r1 - z).abs() <= (r2 - z).abs() ? r1 : r2;
      }
    }
    return (x: x, y: yEq(x, alpha));
  }

  /// Minimum reflux from the feed pinch: R_min / (R_min + 1) = (xD - y*) / (xD - x*).
  static double rMin(double alpha, double z, double q, double xD) {
    final p = qLinePinch(alpha, z, q);
    return (xD - p.y) / (p.y - p.x);
  }

  /// Fenske minimum number of stages (incl. the reboiler) at total reflux.
  static double fenskeNmin(double alpha, double xD, double xB) =>
      math.log((xD / (1 - xD)) * ((1 - xB) / xB)) / math.log(alpha);

  /// Gilliland correlation. Molokanov form by default, Eduljee with [eduljee].
  /// Returns X = (R - Rmin)/(R + 1), Y and the stage count N = (Nmin + Y)/(1 - Y).
  static ({double x, double y, double n}) gilliland(
      double nMin, double r, double rMin,
      {bool eduljee = false}) {
    final x = (r - rMin) / (r + 1);
    final y = eduljee
        ? 0.75 * (1 - math.pow(x, 0.5668))
        : 1 -
            math.exp(
                (1 + 54.4 * x) / (11 + 117.2 * x) * (x - 1) / math.sqrt(x));
    return (x: x, y: y, n: (nMin + y) / (1 - y));
  }

  /// Steps stages from the top for given alpha, z, q, product compositions and reflux ratio.
  static SteppingResult stepStages(
      double alpha, double z, double q, double xD, double xB, double r,
      {int maxStages = 1000}) {
    final a = r / (r + 1);
    final b = xD / (r + 1);
    double xi, yi;
    if ((q - 1).abs() < 1e-12) {
      xi = z;
    } else {
      final s = q / (q - 1);
      xi = (b + s * z - z) / (s - a);
    }
    yi = a * xi + b;
    final slopeS = (yi - xB) / (xi - xB);
    final stages = <StageStep>[];
    var y = xD;
    var feed = 0;
    var xPrev = xD;
    var converged = true;
    var fractional = 0.0;
    for (var n = 1; n <= maxStages; n++) {
      final x = xEq(y, alpha);
      stages.add(StageStep(x, y));
      if (x <= xB) {
        fractional = (n - 1) + (xPrev - xB) / (xPrev - x);
        break;
      }
      if ((xPrev - x).abs() < 1e-12 || n == maxStages) {
        converged = false;
        fractional = double.infinity;
        break;
      }
      if (feed == 0 && x < xi) feed = n;
      y = x >= xi ? a * x + b : xB + slopeS * (x - xB);
      xPrev = x;
    }
    return SteppingResult(
      stages: stages,
      count: converged ? stages.length : -1,
      fractional: fractional,
      feedStage: feed,
      xIntersection: xi,
      yIntersection: yi,
      converged: converged,
    );
  }

  /// Lewis (1936): overall efficiency from Murphree vapour efficiency and stripping factor lambda = m V / L.
  static double lewisEo(double emv, double lambda) {
    if ((lambda - 1).abs() < 1e-9) return emv;
    return math.log(1 + emv * (lambda - 1)) / math.log(lambda);
  }

  static double lewisEmv(double eo, double lambda) {
    if ((lambda - 1).abs() < 1e-9) return eo;
    return (math.pow(lambda, eo) - 1) / (lambda - 1);
  }
}

/// Builds [McCabeThieleData] from a snapshot (ENGINE_API.md 7.2, PHYSICS.md 14.1). Tier 1 binary only in M1.
class McCabeThieleBuilder {
  final Map<double, List<Point2>> _curveCache = {};

  List<Point2> _equilibrium(double alpha) {
    return _curveCache[alpha] ??= [
      for (var k = 0; k <= 100; k++)
        () {
          final x =
              0.5 * (1 - math.cos(math.pi * k / 100)); // refined near the ends
          return Point2(x, McCabeThieleMath.yEq(x, alpha));
        }(),
    ];
  }

  McCabeThieleData build(SimSnapshot s, ThermoModel thermo,
      {bool showRmin = false}) {
    if (thermo is! ConstantAlphaThermo) {
      throw UnsupportedError(
          'Only Tier 1 McCabe-Thiele data is available in M1');
    }
    if (thermo.nc != 2)
      throw UnsupportedError(
          'Pseudo-binary (multicomponent) diagrams arrive with M7');
    final alpha = thermo.alpha[0] / thermo.alpha[1];
    final st = s.stages;
    final N = s.layout.nTrays;
    final nc = st.nc;
    final feedStage = s.layout.feedStages.first;
    final xF = s.streams[StreamId.feed]!.composition[0];
    final xD = st.x[0];
    final xB = st.x[(N + 1) * nc];

    final l0 = s.streams[StreamId.reflux]!.flow;
    final d = s.streams[StreamId.distillate]!.flow;
    final b = s.streams[StreamId.bottoms]!.flow;
    final vBar = s.streams[StreamId.boilup]!.flow;
    final v1 = l0 + d;
    final lBar = vBar + b;
    double sR, bR, sS, bS;
    if (v1 > 1e-12) {
      sR = l0 / v1;
      bR = d * xD / v1;
    } else {
      sR = 1;
      bR = 0;
    }
    if (vBar > 1e-12) {
      sS = lBar / vBar;
      bS = -b * xB / vBar;
    } else {
      sS = 1;
      bS = 0;
    }
    double xi, yi;
    if ((sR - sS).abs() > 1e-12) {
      xi = (bS - bR) / (sR - sS);
      yi = sR * xi + bR;
    } else {
      xi = xF;
      yi = xF;
    }
    final rect = [Point2(xD, xD), Point2(xi, yi)];
    final strip = [Point2(xi, yi), Point2(xB, sS * xB + bS)];

    // q-line
    final q = s.feedQ;
    final pinch = McCabeThieleMath.qLinePinch(alpha, xF, q);
    final qLine = Segment2(Point2(xF, xF), Point2(pinch.x, pinch.y));

    // local equilibrium, operating locus, staircase, corners
    final local = <Point2>[];
    final corners = <StageCorner>[];
    for (var j = 1; j <= N + 1; j++) {
      local.add(Point2(st.x[j * nc], st.yStar[j * nc]));
      corners.add(StageCorner(st.x[j * nc], st.y[j * nc], j, j == feedStage));
    }
    final locus = <Point2>[
      for (var j = 0; j <= N; j++) Point2(st.x[j * nc], st.y[(j + 1) * nc])
    ];
    final stair = <Point2>[Point2(st.x[0], st.x[0])];
    for (var j = 0; j <= N; j++) {
      stair.add(Point2(st.x[j * nc], st.y[(j + 1) * nc]));
      stair.add(Point2(st.x[(j + 1) * nc], st.y[(j + 1) * nc]));
    }
    final xN = st.x[(N + 1) * nc];
    stair.add(Point2(xN, xN));

    // Murphree pseudo-equilibrium (Tier 1): y_op + E (y* - y_op)
    final e = s.murphree;
    final pe = <Point2>[];
    for (final p in _equilibrium(alpha)) {
      final yop = p.x >= xi ? sR * p.x + bR : sS * p.x + bS;
      pe.add(Point2(p.x, yop + e * (p.y - yop)));
    }

    // pinch zones: runs of >= 3 stages that advance x by < 0.002
    final zones = <RangeX>[];
    var run = 0;
    for (var j = 1; j <= N + 1; j++) {
      final dx = st.x[(j - 1) * nc] - st.x[j * nc];
      if (dx.abs() < 0.002) {
        run++;
        if (run >= 3) {
          final lo = st.x[j * nc];
          final hi = st.x[(j - run) * nc];
          if (zones.isNotEmpty &&
              (zones.last.lo - lo).abs() < 1.0 &&
              zones.last.lo <= hi + 1e-12 &&
              zones.last.hi >= lo - 1e-12) {
            zones[zones.length - 1] = RangeX(
                math.min(zones.last.lo, lo), math.max(zones.last.hi, hi));
          } else {
            zones.add(RangeX(lo, hi));
          }
        }
      } else {
        run = 0;
      }
    }

    RminConstruction? rmin;
    if (showRmin && xD > pinch.x) {
      var sMin = -1.0;
      var tx = pinch.x;
      const m = 2000;
      for (var k = 0; k < m; k++) {
        final x = pinch.x + (xD - pinch.x) * k / m;
        final sl = (xD - McCabeThieleMath.yEq(x, alpha)) / (xD - x);
        if (sl > sMin) {
          sMin = sl;
          tx = x;
        }
      }
      if (sMin > 0 && sMin < 1) {
        rmin = RminConstruction(
          from: Point2(xD, xD),
          to: Point2(0, xD * (1 - sMin)),
          touch: Point2(tx, McCabeThieleMath.yEq(tx, alpha)),
          slope: sMin,
          rMin: sMin / (1 - sMin),
        );
      }
    }

    final db = ComponentDb.load();
    return McCabeThieleData(
      pseudoBinary: false,
      lightLabel: db[s.components[0]].name,
      heavyLabel: db[s.components[1]].name,
      equilibriumTop: _equilibrium(alpha),
      localEquilibrium: local,
      qLine: qLine,
      cmoRectifying: rect,
      cmoStripping: strip,
      operatingLocus: locus,
      staircase: stair,
      corners: corners,
      pseudoEquilibrium: pe,
      xF: xF,
      xD: xD,
      xB: xB,
      rmin: rmin,
      pinchZones: zones,
      transient: !s.steady.isSteady,
      operatingIntersection: Point2(xi, yi),
    );
  }
}
