import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'dart:typed_data';

import '../core/ids.dart';
import '../thermo/component.dart';
import '../thermo/thermo_model.dart';
import '../thermo/tier2_raoult.dart';
import 'sim_snapshot.dart';
import 'txy.dart';

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

enum AzeotropeSide { distillate, bottoms }

/// "x_D (or x_B) is beyond the azeotrope (x = ...)": no reflux ratio reaches the specification (PHYSICS.md 14.1).
@immutable
class RminBlock {
  final AzeotropeSide side;
  final double xAzeotrope;
  const RminBlock(this.side, this.xAzeotrope);
}

/// Minimum-reflux construction (PHYSICS.md 14.1; M5 adds the azeotrope cases).
@immutable
class RminConstruction {
  /// Null when blocked.
  final double? sMin, rMin;

  /// Touching point (x, y*): the feed pinch (x_q) or a tangent pinch.
  final Point2? pinch;

  /// True when the pinch is not at x_q.
  final bool tangentPinch;

  /// From (x_D, x_D) with slope [sMin], to x = 0; null when blocked.
  final Segment2? line;

  /// Non-null: draw no line, show the banner.
  final RminBlock? blocked;
  const RminConstruction({
    this.sMin,
    this.rMin,
    this.pinch,
    this.tangentPinch = false,
    this.line,
    this.blocked,
  });

  /// Start and end of the line, the touching point and the slope (null when blocked).
  Point2? get from => line?.a;
  Point2? get to => line?.b;
  Point2? get touch => pinch;
  double? get slope => sMin;
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

  /// False in plant view: the diagram needs compositions that a real plant does not have (PHYSICS.md 10.9).
  final bool available;

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
    this.available = true,
  });

  /// The empty diagram of plant view.
  factory McCabeThieleData.unavailable() => const McCabeThieleData(
        pseudoBinary: false,
        lightLabel: '',
        heavyLabel: '',
        equilibriumTop: [],
        localEquilibrium: [],
        qLine: null,
        cmoRectifying: [],
        cmoStripping: [],
        operatingLocus: [],
        staircase: [],
        corners: [],
        pseudoEquilibrium: [],
        xF: double.nan,
        xD: double.nan,
        xB: double.nan,
        rmin: null,
        pinchZones: [],
        transient: false,
        operatingIntersection: Point2(double.nan, double.nan),
        available: false,
      );
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
    if ((q - 1).abs() < 1e-6) return (x: z, y: yEq(z, alpha));
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
    if ((q - 1).abs() < 1e-6) {
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

  final Float64List _xs = Float64List(2), _ys = Float64List(2), _ks = Float64List(2);
  final SolverHealth _health = SolverHealth();
  double _tg = 350;

  /// Tier 2 bubble-point y*(x) of the light component of a binary at pressure [p].
  double _yBub(Tier2Raoult th, double x, double p) {
    _xs[0] = x;
    _xs[1] = 1 - x;
    _tg = th.bubbleAt(p, _xs, 0, _tg, _ys, 0, _ks, 0, _health);
    return _ys[0];
  }

  List<Point2> _curveT2(Tier2Raoult th, double p) {
    final key = 't2:${th.comps.map((c) => c.id).join(',')}:${(p / 100).round()}';
    final hit = _curveCacheT2[key];
    if (hit != null) return hit;
    _tg = 350;
    final out = [
      for (var k = 0; k <= 100; k++)
        () {
          final x = 0.5 * (1 - math.cos(math.pi * k / 100));
          return Point2(x, _yBub(th, x, p));
        }(),
    ];
    if (_curveCacheT2.length > 24) _curveCacheT2.clear();
    return _curveCacheT2[key] = out;
  }

  final Map<String, List<Point2>> _curveCacheT2 = {};

  /// q-line pinch for the non-ideal curve (PHYSICS.md 14.1): walk from (z, z) away from the diagonal in steps of
  /// 1e-3 in x, take the first sign change of y_line - y* and refine it by bisection to 1e-8.
  Point2 _qPinchT2(Tier2Raoult th, double p, double z, double q) {
    if ((q - 1).abs() < 1e-6) return Point2(z, _yBub(th, z, p));
    final ys = _yBub(th, z, p);
    if ((ys - z).abs() < 1e-9) return Point2(z, z);
    final slope = q / (q - 1);
    // walk towards the side of the diagonal where the curve lies at x = z: the line is on that side where
    // sign(y_line - x) = sign((z - x)(1 - slope)) equals s = sign(y*(z) - z)
    final s = ys > z ? 1.0 : -1.0;
    final dirX = -s * (1 - slope).sign;
    if (slope.abs() <= 1) {
      double f(double x) => z + slope * (x - z) - _yBub(th, x, p);
      final r = _walkRoot(f, z, dirX, 1e-3);
      if (r != null) return Point2(r, _yBub(th, r, p));
      final xe = dirX > 0 ? 1.0 : 0.0;
      return Point2(xe, (z + slope * (xe - z)).clamp(0.0, 1.0).toDouble());
    }
    // steep line: step in y (the frame ends at y = 0 or 1)
    double xOf(double y) => z + (y - z) / slope;
    double g(double y) => y - _yBub(th, xOf(y).clamp(0.0, 1.0).toDouble(), p);
    final dirY = slope.sign * dirX;
    final r = _walkRoot(g, z, dirY, 1e-3);
    if (r != null) {
      final x = xOf(r).clamp(0.0, 1.0).toDouble();
      return Point2(x, _yBub(th, x, p));
    }
    final ye = dirY > 0 ? 1.0 : 0.0;
    return Point2(xOf(ye).clamp(0.0, 1.0).toDouble(), ye);
  }

  /// First sign change of [f] walking from [t0] in direction [dir] in steps of [h] inside [0, 1]; bisection to 1e-8.
  static double? _walkRoot(double Function(double) f, double t0, double dir, double h) {
    var xa = t0;
    var fa = f(xa);
    for (var k = 1; k <= 1000; k++) {
      final xb = t0 + dir * h * k;
      if (xb < 0 || xb > 1) break;
      final fb = f(xb);
      if (fa == 0) return xa;
      if (fa * fb < 0) {
        var lo = math.min(xa, xb), hi = math.max(xa, xb);
        var flo = f(lo);
        for (var i = 0; i < 60 && hi - lo > 1e-8; i++) {
          final m = 0.5 * (lo + hi);
          final fm = f(m);
          if (flo * fm <= 0) {
            hi = m;
          } else {
            lo = m;
            flo = fm;
          }
        }
        return 0.5 * (lo + hi);
      }
      xa = xb;
      fa = fb;
    }
    return null;
  }

  /// R_min construction (PHYSICS.md 14.1). Rectifying side: if the equilibrium curve meets the diagonal in (x_q, x_D)
  /// the distillate is beyond an azeotrope (R_min infinite); otherwise s_min is the maximum of (x_D - y*)/(x_D - x)
  /// over [x_q, x_D), refined by golden-section search (tangent pinches). Stripping side: a maximum-boiling azeotrope
  /// between x_B and x_q blocks the bottoms.
  RminConstruction? _rmin(
      Tier2Raoult? th,
      double Function(double, double) yEqAt,
      double pTop,
      double pFeed,
      double xD,
      double xB,
      double xq,
      double yq) {
    List<Azeotrope> azs = const [];
    if (th != null) {
      final key = 'az:${th.comps.map((c) => c.id).join(',')}:${th.tier.name}:${(pTop / 100).round()}';
      azs = _azCache[key] ??= TxyData.findAzeotropes(th, pTop);
    }
    // stripping side (maximum-boiling azeotrope below the feed)
    for (final a in azs) {
      if (a.maximumBoiling && xB < a.x && a.x < xq) {
        return RminConstruction(blocked: RminBlock(AzeotropeSide.bottoms, a.x));
      }
    }
    if (!(xD > xq)) return null;
    // distillate side: the curve must stay above the diagonal on (x_q, x_D)
    const m = 2000;
    for (var k = 1; k < m; k++) {
      final x = xq + (xD - xq) * k / m;
      if (yEqAt(x, pTop) <= x) {
        double? xa;
        for (final a in azs) {
          if (!a.maximumBoiling && a.x > xq - 1e-9 && a.x <= xD + 1e-9) xa = a.x;
        }
        xa ??= x;
        return RminConstruction(blocked: RminBlock(AzeotropeSide.distillate, xa));
      }
    }
    double slopeAt(double x) => (xD - yEqAt(x, pTop)) / (xD - x);
    var best = xq;
    var sMin = slopeAt(xq);
    for (var k = 1; k < m; k++) {
      final x = xq + (xD - xq) * k / m;
      final sl = slopeAt(x);
      if (sl > sMin) {
        sMin = sl;
        best = x;
      }
    }
    // golden-section refinement of the best interior point to 1e-6 in x
    if (best > xq) {
      var lo = math.max(xq, best - (xD - xq) / m);
      var hi = math.min(xD - 1e-9, best + (xD - xq) / m);
      const gr = 0.6180339887498949;
      var c = hi - gr * (hi - lo), d = lo + gr * (hi - lo);
      var fc = slopeAt(c), fd = slopeAt(d);
      for (var i = 0; i < 60 && hi - lo > 1e-9; i++) {
        if (fc > fd) {
          hi = d;
          d = c;
          fd = fc;
          c = hi - gr * (hi - lo);
          fc = slopeAt(c);
        } else {
          lo = c;
          c = d;
          fc = fd;
          d = lo + gr * (hi - lo);
          fd = slopeAt(d);
        }
      }
      final xr = 0.5 * (lo + hi);
      final sr = slopeAt(xr);
      if (sr > sMin) {
        sMin = sr;
        best = xr;
      }
    }
    if (!(sMin > 0 && sMin < 1)) return null;
    final tangent = (best - xq).abs() > 1e-3;
    return RminConstruction(
      sMin: sMin,
      rMin: sMin / (1 - sMin),
      pinch: Point2(best, yEqAt(best, pTop)),
      tangentPinch: tangent,
      line: Segment2(Point2(xD, xD), Point2(0, xD * (1 - sMin))),
    );
  }

  final Map<String, List<Azeotrope>> _azCache = {};

  /// [xDTarget] / [xBTarget] replace the live product compositions in the R_min construction only (what the
  /// construction asks "if the specification were ..."; VALIDATION.md VC-28.4).
  McCabeThieleData build(SimSnapshot s, ThermoModel thermo,
      {bool showRmin = false, double? xDTarget, double? xBTarget}) {
    if (s.view.isPlant) return McCabeThieleData.unavailable();
    final isT2 = thermo is Tier2Raoult;
    if (!isT2 && thermo is! ConstantAlphaThermo) {
      throw UnsupportedError('McCabe-Thiele data needs a Tier 1 or Tier 2 model');
    }
    if (thermo.nc != 2)
      throw UnsupportedError(
          'Pseudo-binary (multicomponent) diagrams arrive with M7');
    final th2 = isT2 ? thermo : null;
    final alpha = isT2
        ? double.nan
        : (thermo as ConstantAlphaThermo).alpha[0] /
            (thermo).alpha[1];
    final pTop = s.kpis.pTop.isFinite ? s.kpis.pTop : 101325.0;
    final pBot = s.stages.p[s.layout.nTrays + 1].isFinite
        ? s.stages.p[s.layout.nTrays + 1]
        : pTop;
    final pFeed = s.stages.p[s.layout.feedStages.first].isFinite
        ? s.stages.p[s.layout.feedStages.first]
        : pTop;
    double yEqAt(double x, double p) =>
        isT2 ? _yBub(th2!, x, p) : McCabeThieleMath.yEq(x, alpha);
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
    var q = s.feedQ;
    if (isT2) {
      final qs = s.streams[StreamId.feed]!.q;
      if (qs.isFinite) q = qs;
    }
    final ({double x, double y}) pinch;
    if (isT2) {
      final pp = _qPinchT2(th2!, pFeed, xF, q);
      pinch = (x: pp.x, y: pp.y);
    } else {
      pinch = McCabeThieleMath.qLinePinch(alpha, xF, q);
    }
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
    final eqTop = isT2 ? _curveT2(th2!, pTop) : _equilibrium(alpha);
    final eqBot = isT2 ? _curveT2(th2!, pBot) : null;
    for (final p in eqTop) {
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
    if (showRmin) {
      rmin = _rmin(isT2 ? th2 : null, yEqAt, pTop, pFeed, xDTarget ?? xD,
          xBTarget ?? xB, pinch.x, pinch.y);
    }

    final db = ComponentDb.load();
    return McCabeThieleData(
      pseudoBinary: false,
      lightLabel: db[s.components[0]].name,
      heavyLabel: db[s.components[1]].name,
      equilibriumTop: eqTop,
      equilibriumBottom: eqBot,
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
