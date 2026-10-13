import 'dart:math' as math;
import 'dart:typed_data';

import '../config/column_config.dart' show KeyComponents;
import '../thermo/thermo_model.dart';
import 'sim_snapshot.dart';

/// User targets for the FUG panel (PHYSICS.md 14.3): key recoveries and either the live reflux ratio
/// ([rOverRmin] null) or R = [rOverRmin] R_min.
class FugTargets {
  final double rLK, rHK;
  final double? rOverRmin;
  const FugTargets(this.rLK, this.rHK, [this.rOverRmin]);
}

enum FugInvalidReason { notAdjacent, noSplit }

/// Result of one FUG evaluation (ENGINE_API.md 7.3). Stage counts include the reboiler; a total condenser is not a
/// stage. Fields after `reason` are NaN when [valid] is false.
class FugResult {
  final bool valid;
  final FugInvalidReason? reason;

  /// The inputs actually used (live or targets).
  final double rLK, rHK, r, q;

  /// Relative to the heavy key (geometric mean of the top and bottom values in Tiers 2/3).
  final Float64List alpha;
  final double nMin, theta, rMin, x, y, nGilliland;
  final bool belowRmin;
  final double nrOverNs, nR;

  /// Fenske split: flows (same unit as the feed flow passed in) and mole fractions.
  final Float64List d, b, xD, xB, dToB;

  /// The rigorous column: sum of the effective efficiencies plus the reboiler, the effective stages above the
  /// feed stage, and L0/D.
  final double nActual, nRActual, rActual;
  const FugResult({
    required this.valid,
    this.reason,
    required this.rLK,
    required this.rHK,
    required this.r,
    required this.q,
    required this.alpha,
    this.nMin = double.nan,
    this.theta = double.nan,
    this.rMin = double.nan,
    this.x = double.nan,
    this.y = double.nan,
    this.nGilliland = double.nan,
    this.belowRmin = false,
    this.nrOverNs = double.nan,
    this.nR = double.nan,
    required this.d,
    required this.b,
    required this.xD,
    required this.xB,
    required this.dToB,
    this.nActual = double.nan,
    this.nRActual = double.nan,
    this.rActual = double.nan,
  });

  FugResult withRigorous(double nAct, double nRAct, double rAct) => FugResult(
        valid: valid,
        reason: reason,
        rLK: rLK,
        rHK: rHK,
        r: r,
        q: q,
        alpha: alpha,
        nMin: nMin,
        theta: theta,
        rMin: rMin,
        x: x,
        y: y,
        nGilliland: nGilliland,
        belowRmin: belowRmin,
        nrOverNs: nrOverNs,
        nR: nR,
        d: d,
        b: b,
        xD: xD,
        xB: xB,
        dToB: dToB,
        nActual: nAct,
        nRActual: nRAct,
        rActual: rAct,
      );
}

/// FUG shortcut (PHYSICS.md 14.3): Fenske, Underwood, Gilliland (Molokanov) and Kirkbride, from the live column or
/// from user targets.
class FugCalculator {
  const FugCalculator();

  /// The design procedure of VALIDATION.md VC-9.1/9.2 on explicit inputs. [alpha] is relative to the heavy key,
  /// [z] the feed composition, [f] the feed flow, [r] the reflux ratio, or [rOverRmin] to use R = k R_min
  /// (VC-9 uses k = 1.3).
  static FugResult core({
    required Float64List alpha,
    required Float64List z,
    required int lk,
    required int hk,
    required double rLK,
    required double rHK,
    required double q,
    required double f,
    double? r,
    double? rOverRmin,
  }) {
    final nc = alpha.length;
    FugResult invalid(FugInvalidReason why) => FugResult(
        valid: false,
        reason: why,
        rLK: rLK,
        rHK: rHK,
        r: r ?? double.nan,
        q: q,
        alpha: alpha,
        d: Float64List(nc),
        b: Float64List(nc),
        xD: Float64List(nc),
        xB: Float64List(nc),
        dToB: Float64List(nc));
    final aLK = alpha[lk];
    final aHK = alpha[hk];
    if (!(aLK > aHK)) return invalid(FugInvalidReason.notAdjacent);
    for (var i = 0; i < nc; i++) {
      if (i != lk && i != hk && alpha[i] > aHK && alpha[i] < aLK) {
        return invalid(FugInvalidReason.notAdjacent);
      }
    }
    final fLK = f * z[lk], fHK = f * z[hk];
    if (!(rLK > 0.5 && rLK < 1 - 1e-9 && rHK > 0.5 && rHK < 1 - 1e-9) || !(fLK > 0) || !(fHK > 0)) {
      return invalid(FugInvalidReason.noSplit);
    }
    final dLK = rLK * fLK, bLK = fLK - dLK;
    final bHK = rHK * fHK, dHK = fHK - bHK;
    final sep = (dLK / bLK) * (bHK / dHK);
    if (!(sep > 1)) return invalid(FugInvalidReason.noSplit);
    // Fenske
    final nMin = math.log(sep) / math.log(aLK / aHK);
    final dToB = Float64List(nc), d = Float64List(nc), b = Float64List(nc);
    final hkRatio = dHK / bHK;
    var dSum = 0.0, bSum = 0.0;
    for (var i = 0; i < nc; i++) {
      final fi = f * z[i];
      final rho = math.pow(alpha[i] / aHK, nMin) * hkRatio;
      dToB[i] = rho.toDouble();
      d[i] = rho.isFinite ? fi * rho / (1 + rho) : fi;
      b[i] = fi - d[i];
      dSum += d[i];
      bSum += b[i];
    }
    final xD = Float64List(nc), xB = Float64List(nc);
    for (var i = 0; i < nc; i++) {
      xD[i] = d[i] / dSum;
      xB[i] = b[i] / bSum;
    }
    // Underwood: root in (alpha_HK, alpha_LK)
    double g(double th) {
      var s = 0.0;
      for (var i = 0; i < nc; i++) {
        s += alpha[i] * z[i] / (alpha[i] - th);
      }
      return s - (1 - q);
    }

    var lo = aHK, hi = aLK;
    for (var it = 0; it < 80; it++) {
      final mid = 0.5 * (lo + hi);
      if (g(mid) < 0) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final theta = 0.5 * (lo + hi);
    var s = 0.0;
    for (var i = 0; i < nc; i++) {
      s += alpha[i] * xD[i] / (alpha[i] - theta);
    }
    final rMin = s - 1;
    final rUsed = rOverRmin != null ? rOverRmin * rMin : (r ?? double.nan);
    var belowRmin = false;
    var xg = double.nan, yg = double.nan, nG = double.nan;
    if (rUsed.isNaN) {
      // no R: only N_min, theta and R_min
    } else if (rUsed <= rMin) {
      belowRmin = true;
      nG = double.infinity;
    } else {
      xg = (rUsed - rMin) / (rUsed + 1);
      yg = 1 - math.exp((1 + 54.4 * xg) / (11 + 117.2 * xg) * (xg - 1) / math.sqrt(xg));
      nG = (nMin + yg) / (1 - yg);
    }
    // Kirkbride
    final ratio = math.pow((z[hk] / z[lk]) * math.pow(xB[lk] / xD[hk], 2) * (bSum / dSum), 0.206).toDouble();
    final nR = nG.isFinite ? nG * ratio / (1 + ratio) : double.nan;
    return FugResult(
      valid: true,
      rLK: rLK,
      rHK: rHK,
      r: rUsed,
      q: q,
      alpha: alpha,
      nMin: nMin,
      theta: theta,
      rMin: rMin,
      x: xg,
      y: yg,
      nGilliland: nG,
      belowRmin: belowRmin,
      nrOverNs: ratio,
      nR: nR,
      d: d,
      b: b,
      xD: xD,
      xB: xB,
      dToB: dToB,
    );
  }

  /// Relative volatilities (to the heavy key) of the snapshot's column: the preset constants in Tier 1, the
  /// geometric mean of the K ratios at stage 1 and stage N + 1 in Tiers 2/3 (PHYSICS.md 14.3). Also returns the
  /// top and bottom vectors for the adjacency test and the explain lines.
  static ({Float64List mean, Float64List top, Float64List bottom}) alphas(
      SimSnapshot s, ThermoModel thermo, int hk) {
    final nc = s.stages.nc;
    final top = Float64List(nc), bot = Float64List(nc), mean = Float64List(nc);
    if (thermo is ConstantAlphaThermo) {
      final a = thermo.alpha;
      for (var i = 0; i < nc; i++) {
        top[i] = bot[i] = mean[i] = a[i] / a[hk];
      }
      return (mean: mean, top: top, bottom: bot);
    }
    final n = s.layout.nTrays;
    final k = Float64List(nc);
    void at(int j, Float64List out) {
      final x = Float64List.fromList(s.stages.x.sublist(j * nc, (j + 1) * nc));
      thermo.kValues(s.stages.t[j], s.stages.p[j], x, k);
      for (var i = 0; i < nc; i++) {
        out[i] = k[i] / k[hk];
      }
    }

    at(1, top);
    at(n + 1, bot);
    for (var i = 0; i < nc; i++) {
      mean[i] = math.sqrt(top[i] * bot[i]);
    }
    return (mean: mean, top: top, bottom: bot);
  }

  /// FUG for the running column. Null in plant and plantCalc views (the panel needs model compositions) and in
  /// Tier-1-less situations without a thermo model.
  FugResult? compute(SimSnapshot s, KeyComponents keys, {FugTargets? targets, required ThermoModel thermo}) {
    if (s.view.isPlant) return null;
    final nc = s.stages.nc;
    if (nc < 3) return null;
    final n = s.layout.nTrays;
    final feed = s.streams[StreamId.feed]!;
    final dS = s.streams[StreamId.distillate]!;
    final bS = s.streams[StreamId.bottoms]!;
    final l0 = s.streams[StreamId.reflux]!.flow;
    final f = feed.flow;
    final z = feed.composition;
    final al = alphas(s, thermo, keys.hk);
    var q = s.feedQ;
    if (thermo is! ConstantAlphaThermo && feed.q.isFinite) q = feed.q;
    final xDv = Float64List.fromList(s.stages.x.sublist(0, nc));
    final xBv = Float64List.fromList(s.stages.x.sublist((n + 1) * nc, (n + 2) * nc));
    final fLK = f * z[keys.lk], fHK = f * z[keys.hk];
    final rLive = l0 / dS.flow;
    final rLKLive = fLK > 0 ? dS.flow * xDv[keys.lk] / fLK : double.nan;
    final rHKLive = fHK > 0 ? bS.flow * xBv[keys.hk] / fHK : double.nan;
    final rLK = targets?.rLK ?? rLKLive;
    final rHK = targets?.rHK ?? rHKLive;
    final kR = targets?.rOverRmin;
    final rr = kR == null ? (rLive.isFinite ? rLive : double.nan) : null;
    // adjacency is tested on the top and bottom volatilities separately (PHYSICS.md 14.3)
    var adjacent = true;
    for (final a in [al.top, al.bottom]) {
      if (!(a[keys.lk] > 1)) adjacent = false;
      for (var i = 0; i < nc; i++) {
        if (i != keys.lk && i != keys.hk && a[i] > 1 && a[i] < a[keys.lk]) adjacent = false;
      }
    }
    var res = core(
      alpha: al.mean,
      z: z,
      lk: keys.lk,
      hk: keys.hk,
      rLK: rLK.isNaN ? 0 : rLK,
      rHK: rHK.isNaN ? 0 : rHK,
      q: q,
      f: f,
      r: rr,
      rOverRmin: kR,
    );
    if (!adjacent) {
      res = FugResult(
          valid: false,
          reason: FugInvalidReason.notAdjacent,
          rLK: rLK,
          rHK: rHK,
          r: rr ?? double.nan,
          q: q,
          alpha: al.mean,
          d: res.d,
          b: res.b,
          xD: res.xD,
          xB: res.xB,
          dToB: res.dToB);
    }
    var nAct = 1.0, nRAct = 0.0;
    final nf = s.layout.feedStages.first;
    for (var j = 1; j <= n; j++) {
      final e = s.stages.efficiency[j];
      final ej = e.isFinite ? e : s.murphree;
      nAct += ej;
      if (j < nf) nRAct += ej;
    }
    return res.withRigorous(nAct, nRAct, rLive);
  }
}
