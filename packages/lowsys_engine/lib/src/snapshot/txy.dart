import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../thermo/thermo_model.dart';
import '../thermo/tier2_raoult.dart';
import 'mccabe_thiele.dart' show Point2;
import 'sim_snapshot.dart';

/// An azeotrope of a binary at one pressure (PHYSICS.md 14.4b, VALIDATION.md VC-10.5).
@immutable
class Azeotrope {
  /// Light-component mole fraction (= y).
  final double x;

  /// K
  final double t;

  /// True when T_az is above both pure-component boiling points.
  final bool maximumBoiling;
  const Azeotrope(this.x, this.t, this.maximumBoiling);
  @override
  String toString() => 'Azeotrope(x $x, T $t, max $maximumBoiling)';
}

/// T-x-y data of a binary at one pressure: one bubble-point sweep gives the bubble curve T_bub(x), the dew curve
/// (y*, T) and the x-y equilibrium curve (PHYSICS.md 14.4b).
@immutable
class TxyData {
  final double p;

  /// Grid sorted by x; T in K.
  final Float64List x, tBubble, yStar;

  /// The same points as (y*, T), sorted by y.
  final Float64List yDew, tDew;
  final List<Azeotrope> azeotropes;

  /// Tier-1 view drawn with Raoult.
  final bool ideal;
  const TxyData._(this.p, this.x, this.tBubble, this.yStar, this.yDew,
      this.tDew, this.azeotropes, this.ideal);

  static final SolverHealth _health = SolverHealth();

  static double _bubble(Tier2Raoult m, double p, double x, double tg,
      Float64List xs, Float64List ys, Float64List ks) {
    xs[0] = x;
    xs[1] = 1 - x;
    return m.bubbleAt(p, xs, 0, tg, ys, 0, ks, 0, _health);
  }

  /// y*(x) - x at pressure [p] (the azeotrope function).
  static double _f(Tier2Raoult m, double p, double x, Float64List xs,
      Float64List ys, Float64List ks) {
    _bubble(m, p, x, 350, xs, ys, ks);
    return ys[0] - x;
  }

  /// VC-10.5 method: sign changes of y* - x on a 1e-4 grid, bisection to 1e-8. Allocates; not on the hot path.
  static List<Azeotrope> findAzeotropes(ThermoModel model, double p,
      {double step = 1e-4}) {
    final m = model as Tier2Raoult;
    if (m.nc != 2) return const [];
    final xs = Float64List(2), ys = Float64List(2), ks = Float64List(2);
    final out = <Azeotrope>[];
    final tLight = _bubble(m, p, 1.0, 350, xs, ys, ks);
    final tHeavy = _bubble(m, p, 0.0, 350, xs, ys, ks);
    var prevX = step;
    var prevF = _f(m, p, prevX, xs, ys, ks);
    final n = (1 / step).round();
    for (var i = 2; i < n; i++) {
      final x = i * step;
      final f = _f(m, p, x, xs, ys, ks);
      if (prevF * f < 0) {
        var lo = prevX, hi = x;
        var flo = prevF;
        for (var k = 0; k < 80 && hi - lo > 1e-8; k++) {
          final mid = 0.5 * (lo + hi);
          final fm = _f(m, p, mid, xs, ys, ks);
          if (flo * fm <= 0) {
            hi = mid;
          } else {
            lo = mid;
            flo = fm;
          }
        }
        final xa = 0.5 * (lo + hi);
        final ta = _bubble(m, p, xa, 350, xs, ys, ks);
        out.add(Azeotrope(xa, ta, ta > math.max(tLight, tHeavy)));
      }
      prevX = x;
      prevF = f;
    }
    return out;
  }

  /// One bubble-point sweep at pressure [p] on the 14.4b grid. [m] must have temperatures: in Tier 1 pass the
  /// Tier-2 model behind `displayBubbleT()` and set [ideal].
  static TxyData build(ThermoModel model, double p, {bool ideal = false}) {
    final m = model as Tier2Raoult;
    // the sweep scans on a 2e-3 grid (the VC-10.5 grid of 1e-4 costs 10 ms); the refinement is the same
    final azs = findAzeotropes(m, p, step: 2e-3);
    final xsSet = <double>{};
    for (var i = 0; i <= 200; i++) {
      xsSet.add(i * 0.005);
    }
    for (var i = 1; i <= 10; i++) {
      final v = 0.01 * math.pow(10, -2.0 * (10 - i) / 9);
      xsSet.add(v);
      xsSet.add(1 - v);
    }
    for (final a in azs) {
      for (var i = -10; i <= 10; i++) {
        final v = a.x + i * 0.002;
        if (v > 0 && v < 1) xsSet.add(v);
      }
    }
    final grid = xsSet.toList()..sort();
    final n = grid.length;
    final x = Float64List(n), tb = Float64List(n), ys = Float64List(n);
    final xs = Float64List(2), yv = Float64List(2), ks = Float64List(2);
    var tg = 350.0;
    for (var i = 0; i < n; i++) {
      x[i] = grid[i];
      tg = _bubble(m, p, x[i], tg, xs, yv, ks);
      tb[i] = tg;
      ys[i] = yv[0];
    }
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => ys[a].compareTo(ys[b]));
    final yd = Float64List(n), td = Float64List(n);
    for (var i = 0; i < n; i++) {
      yd[i] = ys[order[i]];
      td[i] = tb[order[i]];
    }
    return TxyData._(p, x, tb, ys, yd, td, azs, ideal);
  }
}

/// Stage overlay and curves of the T-x-y tab (ENGINE_API.md 7.3).
typedef TxyView = ({
  TxyData top,
  TxyData? bottom,
  List<Point2> stages,
  Point2 d,
  Point2 b,
});

/// Caches [TxyData] per (system, tier, pressure rounded to 100 Pa) and adds the column overlay.
class TxyBuilder {
  final Map<String, TxyData> _cache = {};

  TxyData data(Tier2Raoult m, double p, {required String tierKey, bool ideal = false}) {
    final key = '${m.comps.map((c) => c.id).join(',')}:$tierKey:${(p / 100).round()}';
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 24) _cache.clear();
    return _cache[key] = TxyData.build(m, p, ideal: ideal);
  }

  /// Curves at P_top and, when the column pressure drop exceeds 1 kPa, at P_{N+1}; plus the stage overlay (x_j, T_j),
  /// D and B. In Tier 1 [thermo] is the Tier-2 model behind `displayBubbleT()`, the data is flagged ideal and T_j is
  /// the display T*.
  TxyView build(SimSnapshot s, ThermoModel thermo) {
    final m = thermo as Tier2Raoult;
    final ideal = s.tier == ThermoTier.t1;
    final key = ideal ? 'ideal' : s.tier.name;
    final N = s.layout.nTrays;
    final nc = s.stages.nc;
    final pTop = s.kpis.pTop.isFinite ? s.kpis.pTop : 101325.0;
    final pBot = s.stages.p[N + 1].isFinite ? s.stages.p[N + 1] : pTop;
    final top = data(m, pTop, tierKey: key, ideal: ideal);
    final bottom = (pBot - pTop).abs() > 1000
        ? data(m, pBot, tierKey: key, ideal: ideal)
        : null;
    final stages = <Point2>[
      for (var j = 1; j <= N; j++) Point2(s.stages.x[j * nc], s.stages.t[j]),
    ];
    return (
      top: top,
      bottom: bottom,
      stages: stages,
      d: Point2(s.stages.x[0], s.stages.t[0]),
      b: Point2(s.stages.x[(N + 1) * nc], s.stages.t[N + 1]),
    );
  }
}
