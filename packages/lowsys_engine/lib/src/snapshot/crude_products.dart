// Crude product properties (PHYSICS.md 9.6): product TBP from the pseudo-components with the 1 % tail trim,
// ASTM D86 by Daubert (1994), the 5-95 gaps, and the ideal cuts of VALIDATION.md VC-15.3.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../thermo/crude_thermo.dart';

/// Products in the order of the snapshot arrays.
enum CrudeProduct { naphtha, kero, diesel, ago, residue }

/// Points of a TBP curve that Daubert's inversion uses (vol %).
const List<double> d86TbpPoints = [0, 10, 30, 50, 70, 90, 100];

/// Points of a D86 curve returned by [CrudeProducts.d86] (vol %).
const List<double> d86Points = [0, 5, 10, 30, 50, 70, 90, 95, 100];

@immutable
class GapBar {
  final CrudeProduct light, heavy;

  /// K: D86 95 % of the light product, D86 5 % of the heavy one; positive gap = clear space.
  final double d86p95Light, d86p5Heavy;
  double get gap => d86p5Heavy - d86p95Light;
  bool get isGap => gap >= 0;
  const GapBar(this.light, this.heavy, this.d86p95Light, this.d86p5Heavy);
}

/// M9 Products-tab data (ENGINE_API.md 7.3), built on demand.
class CrudeProductData {
  /// Six curves (feed and the five products): (vol %, K) at 0..100 % in 2 % steps.
  final List<List<({double vol, double t})>> tbp;

  /// Four curves (naphtha..AGO): (vol %, K) at [d86Points].
  final List<List<({double vol, double t})>> d86;
  final List<GapBar> gaps;

  /// VC-15.3 yields (vol % of crude) at the TBP cut points implied by the current cumulative yields.
  final Float64List idealYieldVolPct;

  /// K: the cut points (3 side-cut boundaries plus the naphtha end point) implied by the cumulative yields.
  final Float64List idealCutT;
  /// Lab sample time (s) in the plant views (D86 and gaps are the last lab result); NaN in the model view.
  final double labSampleTime;
  const CrudeProductData(this.tbp, this.d86, this.gaps, this.idealYieldVolPct, this.idealCutT, {this.labSampleTime = double.nan});
}

/// Product property calculations on liquid compositions (mole fractions of the pseudo-components).
class CrudeProducts {
  final CrudeThermo th;

  /// Vol % trimmed from each tail (1.0): the TBP 0 % and 100 % points are read at 1 % and 99 % (9.6 step 2).
  final double trimPct;
  CrudeProducts(this.th, {this.trimPct = 1.0});

  /// Product TBP (K) at product vol % [p] for composition [x] (nHc entries at [off]).
  double tbp(Float64List x, int off, double p) {
    final n = th.nHc;
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += x[off + i] * th.vStd[i];
    }
    if (!(s > 0)) return th.tLo[0];
    var cum = 0.0;
    for (var i = 0; i < n; i++) {
      final share = 100 * x[off + i] * th.vStd[i] / s;
      if (share <= 0) continue;
      if (cum + share >= p || i == n - 1) {
        final f = ((p - cum) / share).clamp(0.0, 1.0);
        return th.tLo[i] + f * (th.tHi[i] - th.tLo[i]);
      }
      cum += share;
    }
    return th.tHi[n - 1];
  }

  /// TBP at a point of the 0..100 axis with the trim applied to the ends.
  double tbpTrimmed(Float64List x, int off, double p) =>
      tbp(x, off, p <= trimPct ? trimPct : (p >= 100 - trimPct ? 100 - trimPct : p));

  /// Daubert (1994) TBP to D86. [tbp7] holds the TBP (K) at [d86TbpPoints]; the result (K) is at [d86Points].
  static List<double> d86(List<double> tbp7) {
    final f = [for (final c in tbp7) 1.8 * (c - 273.15) + 32];
    double inv(double dt, double a, double b) => math.pow(math.max(0.0, dt) / a, 1 / b).toDouble();
    final d50 = math.pow(f[3] / 0.8718, 1 / 1.0258).toDouble();
    final d30 = d50 - inv(f[3] - f[2], 3.0305, 0.8008);
    final d10 = d30 - inv(f[2] - f[1], 4.9004, 0.7164);
    final d0 = d10 - inv(f[1] - f[0], 7.4012, 0.6024);
    final d70 = d50 + inv(f[4] - f[3], 2.5282, 0.8200);
    final d90 = d70 + inv(f[5] - f[4], 3.0419, 0.7550);
    final d100 = d90 + inv(f[6] - f[5], 0.1180, 1.6606);
    final r = [d0, (d0 + d10) / 2, d10, d30, d50, d70, d90, (d90 + d100) / 2, d100];
    return [for (final v in r) (v - 32) / 1.8 + 273.15];
  }

  /// D86 curve (K, at [d86Points]) of a product with composition [x].
  List<double> productD86(Float64List x, int off) =>
      d86([for (final p in d86TbpPoints) tbpTrimmed(x, off, p)]);

  /// D86 5 / 50 / 95 % (K) of a product.
  (double, double, double) d86Key(Float64List x, int off) {
    final d = productD86(x, off);
    return (d[1], d[4], d[7]);
  }

  /// Gap (K) between a heavy and a light product: D86 5 % heavy - D86 95 % light.
  static double gap(double d86p5Heavy, double d86p95Light) => d86p5Heavy - d86p95Light;

  /// Perfect cut of the assay between TBP temperatures [tLoK] and [tHiK] (K): TBP at product vol %, untrimmed.
  List<double> idealCutTbp(double tLoK, double tHiK) {
    final a = th.assay;
    final vlo = a.volAt(tLoK - 273.15), vhi = a.volAt(tHiK - 273.15);
    return [for (final p in d86TbpPoints) a.tbpAt(vlo + p / 100 * (vhi - vlo)) + 273.15];
  }

  /// D86 (K, at [d86Points]) of the ideal cut.
  List<double> idealCut(double tLoK, double tHiK) => d86(idealCutTbp(tLoK, tHiK));

  /// Product TBP curve (K) at 0..100 % in 2 % steps.
  List<({double vol, double t})> tbpCurve(Float64List x, int off) =>
      [for (var p = 0; p <= 100; p += 2) (vol: p.toDouble(), t: tbpTrimmed(x, off, p.toDouble()))];
}

/// Crude KPIs (ENGINE_API.md 7.1, M9): true model values; masked or replaced by lab results in the plant views.
@immutable
class CrudeProductKpis {
  /// Products in the order of [CrudeProduct]; vol % of crude at 15.6 C (sum 100 within 1e-4 at steady state).
  final Float64List yieldVolPct;

  /// m3/s at 15.6 C.
  final Float64List productFlow;

  /// K; naphtha..AGO (4 entries). In the plant views the last lab result (NaN before the first).
  final Float64List d86p5, d86p50, d86p95;

  /// K (D86 5 % heavy - 95 % light).
  final double gapKeroNaphtha, gapDieselKero, gapAgoDiesel;

  /// K
  final double residueTbp5;

  /// Stage 25 to 26 liquid, vol % of the crude (PHYSICS.md 9.2).
  final double overflashVolPct;

  /// K: stage 1, stage 26, stage 30, true COT.
  final double topT, flashZoneT, bottomT, cot;

  /// W, W, W, W, K, m3/s
  final double qc, qcMax, qPa, qPaMax, paReturnT, paCirculation;

  /// K, stage 1 (PHYSICS.md 9.3).
  final double waterDewMargin;

  /// Per side product (kero, diesel, ago): FC-31x cut by its stripper level (PHYSICS.md 9.4).
  final List<bool> drawDry;
  final bool condenserLimited, paDutyLimited;

  /// Sim time (s) the lab sample was taken, in the plant views; NaN in the model view.
  final double labSampleTime;
  const CrudeProductKpis({
    required this.yieldVolPct,
    required this.productFlow,
    required this.d86p5,
    required this.d86p50,
    required this.d86p95,
    required this.gapKeroNaphtha,
    required this.gapDieselKero,
    required this.gapAgoDiesel,
    required this.residueTbp5,
    required this.overflashVolPct,
    required this.topT,
    required this.flashZoneT,
    required this.bottomT,
    required this.cot,
    required this.qc,
    required this.qcMax,
    required this.qPa,
    required this.qPaMax,
    required this.paReturnT,
    required this.paCirculation,
    required this.waterDewMargin,
    required this.drawDry,
    required this.condenserLimited,
    required this.paDutyLimited,
    this.labSampleTime = double.nan,
  });
}

/// One side stripper (ENGINE_API.md 7.1): stage temperatures, liquid and vapour flows (mol/s), boot level and the
/// draw, product, vapour-return and steam flows (mol/s).
@immutable
class StripperSnapshot {
  final Float64List t, l, v;
  final double levelPct, draw, product, vaporReturn, steam;
  const StripperSnapshot(
      {required this.t,
      required this.l,
      required this.v,
      required this.levelPct,
      required this.draw,
      required this.product,
      required this.vaporReturn,
      required this.steam});
}
