import 'dart:math' as math;
import 'dart:typed_data';

import '../core/ids.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/component.dart' show WaterProps;
import '../thermo/tier2_raoult.dart';
import 'control_system.dart';
import 'trend_buffer.dart';

const double _kmolh = 1000 / 3600;

/// What the Tier-2 cross-checks may use besides the readings: lever values and design constants (PHYSICS.md 14.6).
class T2CheckContext {
  final Tier2Raoult thermo;

  /// Feed temperature lever (K; for a saturated feed its bubble point; no fault offsets).
  final double feedT;

  /// Reflux subcooling lever (K).
  final double refluxSubLever;

  /// Clean reboiler UA (W/K), CW capacity (kg/s) and the instrumented tray numbers (TI-1jj).
  final double uaRebClean, cwMax;
  final List<int> trayIds;
  final int nTrays;
  const T2CheckContext({
    required this.thermo,
    required this.feedT,
    required this.refluxSubLever,
    required this.uaRebClean,
    required this.cwMax,
    required this.trayIds,
    required this.nTrays,
  });
}

/// Cross-checks C1 to C7 of PHYSICS.md 14.6, computed from the 5-s trend bins of the readings only.
class CrossCheckEngine {
  /// Window (s): 300, 600, 1800 or 3600.
  double window = 600;
  List<CrossCheckResult> results = const [];

  /// C6 reference: 300-s means of the instrumented TIs (tag -> K) at drill start or "Set reference".
  Map<String, double>? tiReference;

  void setWindow(double w) {
    if (w != 300 && w != 600 && w != 1800 && w != 3600) {
      throw ArgumentError('Window must be 300, 600, 1800 or 3600 s');
    }
    window = w;
  }

  static CheckStatus statusOf(double r, double band) {
    final a = r.abs();
    if (a.isNaN) return CheckStatus.notAvailable;
    if (a <= band) return CheckStatus.ok;
    if (a <= 2 * band) return CheckStatus.check;
    return CheckStatus.fail;
  }

  /// True when an analyser sits at either end of its span (the result is clipped, so the check cannot use it).
  static bool _atEnd(ControlSystem cs, String tag, double v) {
    final s = cs.instrument(tag).spec;
    final eps = 1e-6 * (s.hi - s.lo);
    return v >= s.hi - eps || v <= s.lo + eps;
  }

  static CheckStatus worse(CheckStatus a, CheckStatus b) =>
      a.index >= b.index ? a : b;

  final Float64List _x = Float64List(2),
      _xb = Float64List(2),
      _y = Float64List(2),
      _k = Float64List(2);
  final SolverHealth _health = SolverHealth();

  /// The TI tags of the Tier-2 tray set including the sump (ordered top to bottom).
  static List<String> tiTags(T2CheckContext t2) => [
        for (final j in t2.trayIds) 'TI-${100 + j}',
        'TI-${100 + t2.nTrays + 1}',
      ];

  /// Stores the C6 reference from the newest 300 s of the trend (Tiers 2/3).
  bool setReference(TrendBuffer tb, T2CheckContext t2) {
    final m = <String, double>{};
    for (final tag in tiTags(t2)) {
      final i = tb.indexOf('PV:$tag');
      if (i == null) return false;
      final v = tb.windowMean(i, 0, math.min(60, math.max(tb.count, 1)));
      if (v.isNaN) return false;
      m[tag] = v;
    }
    tiReference = m;
    return true;
  }

  /// Recomputes every check. [q] is the feed condition lever (Tier 1); [t2] is non-null in Tiers 2/3.
  void evaluate(TrendBuffer tb, ControlSystem cs, double q, bool steady,
      {T2CheckContext? t2, int tier2StartBin = 0}) {
    final nb = (window / TrendBuffer.binSeconds).round();
    final out = <CrossCheckResult>[];
    CrossCheckResult na(
            String id, String title, List<String> inputs, String reason) =>
        CrossCheckResult(id, title, double.nan, double.nan,
            CheckStatus.notAvailable, inputs, reason, const {});

    int? ix(String name) => tb.indexOf(name);
    // returns the tag of the first BAD/OOS input, or null
    String? badInput(List<String> tags) {
      for (final tag in tags) {
        final i = ix('PV:$tag');
        if (i == null) return tag;
        for (var b = 0; b < nb; b++) {
          final qa = tb.qualityAt(i, tb.count - 1 - b);
          if (qa == Quality.bad.index || qa == Quality.oos.index) return tag;
        }
      }
      return null;
    }

    double mean(String series, [int offset = 0, int bins = -1]) {
      final i = ix(series)!;
      return tb.windowMean(i, offset, bins < 0 ? nb : bins);
    }

    double startMean(String series) => mean(series, nb - 12, 12);
    double endMean(String series) => mean(series, 0, 12);

    final ready = tb.count >= nb;
    // Tier-2 series only hold data since the switch (or the build)
    final binsSince = (tb.newestEnd / TrendBuffer.binSeconds).round() - tier2StartBin;
    final ready2 = ready && binsSince >= nb;
    final w = window;
    // The level terms of C1 and C3 are divided by W, so their noise grows as 1/W; the bands of PHYSICS 14.6 are
    // sized for W = 600 s and are widened for shorter windows (DEVIATIONS.md E36).
    final shortScale = math.max(1.0, 600 / w);
    final is2 = t2 != null;
    final sumpTi = is2 ? 'TI-${100 + t2.nTrays + 1}' : '';

    // ---- C1
    {
      const id = 'C1', title = 'check.c1';
      final inputs = ['FT-101', 'FT-104', 'FT-105', 'LT-101', 'LT-102'];
      if (!ready) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if (badInput(inputs) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else {
        final f = mean('PV:FT-101'),
            d = mean('PV:FT-104'),
            b = mean('PV:FT-105');
        final dn0 = (endMean('PV:LT-101') - startMean('PV:LT-101')) * cs.n01;
        final dn1 = (endMean('PV:LT-102') - startMean('PV:LT-102')) * cs.ns1;
        final r = f - d - b - (dn0 + dn1) / w;
        final band = shortScale * math.max(2.0 * _kmolh, 0.02 * f);
        out.add(CrossCheckResult(
            id, title, r, band, statusOf(r, band), inputs, null, {
          'in': f,
          'out': d + b,
          'accumulation': (dn0 + dn1) / w,
          'unaccounted': r
        }));
      }
    }
    // ---- C2 component balance (steady only, window of at least 1800 s)
    {
      const id = 'C2', title = 'check.c2';
      final inputs = [
        'FT-101',
        'FT-104',
        'FT-105',
        'AT-100',
        'AT-101',
        'AT-102'
      ];
      if (w < 1800) {
        out.add(na(id, title, inputs, 'needs a window of at least 1800 s'));
      } else if (!ready) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if (badInput(inputs) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else if (!steady) {
        out.add(CrossCheckResult(
            id,
            title,
            double.nan,
            double.nan,
            CheckStatus.transient,
            inputs,
            'column not at steady state', const {}));
      } else {
        final f = mean('PV:FT-101'),
            d = mean('PV:FT-104'),
            b = mean('PV:FT-105');
        final z = mean('PV:AT-100'),
            xd = 1 - mean('PV:AT-101'),
            xb = mean('PV:AT-102');
        final r = f * z - d * xd - b * xb;
        final band = 0.01 * f * z;
        final dfAnalyser =
            (xd - xb).abs() > 1e-9 ? (z - xb) / (xd - xb) : double.nan;
        out.add(CrossCheckResult(
            id, title, r, band, statusOf(r, band), inputs, null, {
          'in': f * z,
          'out': d * xd + b * xb,
          'dfMeters': f > 0 ? d / f : double.nan,
          'dfAnalysers': dfAnalyser
        }));
      }
    }

    // Tier-2 derived quantities used by C3a, C3b and C5 (NaN when unavailable)
    double qCw = double.nan, lamTop = double.nan, vCw = double.nan;
    String? t2Bad;
    if (is2 && ready2) {
      t2Bad = badInput(
          ['FT-201', 'TI-201', 'TI-202', 'PT-101', 'AT-101', 'TI-100']);
      if (t2Bad == null) {
        final th = t2.thermo;
        qCw = ControlSystem.rhoWater *
            mean('PV:FT-201') *
            4180.0 *
            (mean('PV:TI-202') - mean('PV:TI-201'));
        final xd = 1 - mean('PV:AT-101');
        _x[0] = xd;
        _x[1] = 1 - xd;
        final p = mean('PV:PT-101');
        final tCond = th.bubbleAt(p, _x, 0, mean('PV:TI-100') + 1, _y, 0, _k, 0, _health);
        lamTop = th.hVAt(tCond, _x, 0) - th.hLAt(mean('PV:TI-100'), _x, 0);
        vCw = lamTop > 0 ? qCw / lamTop : double.nan;
      }
    }

    // ---- C3 (Tier 1) or C3a / C3b (Tiers 2/3)
    if (!is2) {
      const id = 'C3', title = 'check.c3';
      final inputs = ['FT-101', 'FT-102', 'FT-103', 'FT-104', 'LT-101'];
      if (!ready) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if (badInput(inputs) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else {
        final f = mean('PV:FT-101'),
            vb = mean('PV:FT-103'),
            l0 = mean('PV:FT-102'),
            d = mean('PV:FT-104');
        final dn0 = (endMean('PV:LT-101') - startMean('PV:LT-101')) * cs.n01;
        final vBoil = vb + (1 - q) * f;
        final vRefl = l0 + d + dn0 / w;
        final r = vBoil - vRefl;
        final band = shortScale * math.max(2.0 * _kmolh, 0.015 * vRefl);
        out.add(CrossCheckResult(id, title, r, band, statusOf(r, band), inputs,
            null, {'fromBoilup': vBoil, 'fromReflux': vRefl, 'difference': r}));
      }
    } else {
      {
        const id = 'C3a', title = 'check.c3a';
        final inputs = [
          'FT-201', 'TI-201', 'TI-202', 'PT-101', 'AT-101', 'TI-100', //
          'FT-102', 'FT-104', 'LT-101'
        ];
        if (!ready2) {
          out.add(na(id, title, inputs, 'collecting data'));
        } else if ((badInput(['FT-102', 'FT-104', 'LT-101']) ?? t2Bad) case final bad?) {
          out.add(na(id, title, inputs, 'BAD input $bad'));
        } else {
          final l0 = mean('PV:FT-102'), d = mean('PV:FT-104');
          final dn0 = (endMean('PV:LT-101') - startMean('PV:LT-101')) * cs.n01;
          final vRefl = l0 + d + dn0 / w;
          final r = vCw - vRefl;
          final band = shortScale * math.max(2.0 * _kmolh, 0.02 * vRefl);
          out.add(CrossCheckResult(id, title, r, band, statusOf(r, band),
              inputs, null, {
            'dutyCw': qCw,
            'fromCondenser': vCw,
            'fromReflux': vRefl,
            'difference': r
          }));
        }
      }
      {
        const id = 'C3b', title = 'check.c3b';
        final inputs = [
          'FT-103', 'FT-101', 'FT-201', 'TI-201', 'TI-202', 'FT-104',
          'FT-105', 'AT-100', 'AT-101', 'AT-102', 'TI-100', sumpTi //
        ];
        if (!ready2) {
          out.add(na(id, title, inputs, 'collecting data'));
        } else if ((badInput(['FT-103', 'FT-101', 'FT-104', 'FT-105', 'AT-100', 'AT-102', sumpTi]) ?? t2Bad) case final bad?) {
          out.add(na(id, title, inputs, 'BAD input $bad'));
        } else {
          final th = t2.thermo;
          final qr = mean('PV:FT-103');
          final f = mean('PV:FT-101'),
              d = mean('PV:FT-104'),
              b = mean('PV:FT-105');
          final zl = mean('PV:AT-100');
          final xd = 1 - mean('PV:AT-101');
          final xbv = mean('PV:AT-102');
          final p = mean('PV:PT-101');
          _x[0] = zl;
          _x[1] = 1 - zl;
          final hF = th.feedEnthalpy(t2.feedT, p, _x);
          _xb[0] = xd;
          _xb[1] = 1 - xd;
          final hD = th.hLAt(mean('PV:TI-100'), _xb, 0);
          _xb[0] = xbv;
          _xb[1] = 1 - xbv;
          final hB = th.hLAt(mean('PV:$sumpTi'), _xb, 0);
          final r = qr + f * hF - qCw - d * hD - b * hB;
          final band = 0.02 * qr;
          out.add(CrossCheckResult(id, title, r, band, statusOf(r, band),
              inputs, null, {
            'reboiler': qr,
            'feed': f * hF,
            'condenser': qCw,
            'products': d * hD + b * hB,
            'unaccounted': r
          }));
        }
      }
    }

    // ---- C4, one per valve and meter
    for (final (valve, meter, loop) in const [
      ('FV-101', 'FT-101', 'FC-101'),
      ('FV-102', 'FT-102', 'FC-102'),
      ('FV-103', 'FT-103', 'FC-103'),
      ('LV-101', 'FT-104', 'LC-101'),
      ('LV-102', 'FT-105', 'LC-102'),
      ('PV-101', 'FT-201', 'PC-101'),
    ]) {
      if (valve == 'PV-101' && (!is2 || cs.partial)) continue;
      final id = 'C4:$valve', title = 'check.c4';
      final inputs = [meter];
      final isT2Valve = valve == 'FV-103' && is2 || valve == 'PV-101';
      final ok = isT2Valve ? ready2 : ready;
      if (!ok) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if (badInput(inputs) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else {
        final v = cs.valve(valve);
        final op = mean('OP:$loop');
        double fexp, fmax;
        if (valve == 'FV-103' && is2) {
          // Q_exp = Q_max,0 g(OP) with Q_max,0 = UA_R,clean (T_st(P_201) - T_121), all from readings
          final extra = badInput(['PT-201', sumpTi]);
          if (extra != null) {
            out.add(na(id, title, [meter, 'PT-201', sumpTi], 'BAD input $extra'));
            continue;
          }
          final tSt = WaterProps.saturationT(mean('PV:PT-201') + 101325.0);
          final qMax0 = math.max(0.0, t2.uaRebClean * (tSt - mean('PV:$sumpTi')));
          fexp = qMax0 * v.g(op);
          fmax = qMax0;
        } else if (valve == 'PV-101') {
          fmax = t2!.cwMax / ControlSystem.rhoWater;
          fexp = fmax * v.g(op);
        } else {
          fexp = v.expectedFlow(op);
          fmax = v.fMax;
        }
        final fm = mean('PV:$meter');
        final r = fm - fexp;
        final band = 0.015 * fmax;
        out.add(CrossCheckResult(id, title, r, band, statusOf(r, band), inputs,
            null, {'op': op, 'expected': fexp, 'measured': fm}));
      }
    }
    // ---- C5 drum and sump (% level)
    for (final drum in [true, false]) {
      final id = drum ? 'C5:drum' : 'C5:sump', title = 'check.c5';
      final inputs = drum
          ? ['LT-101', 'FT-101', 'FT-102', 'FT-103', 'FT-104']
          : ['LT-102', 'FT-101', 'FT-102', 'FT-103', 'FT-105'];
      final ok = is2 ? ready2 : ready;
      if (!ok) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if ((badInput(inputs) ?? (is2 ? t2Bad : null)) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else {
        final lt = drum ? 'PV:LT-101' : 'PV:LT-102';
        final n1 = drum ? cs.n01 : cs.ns1;
        final f = mean('PV:FT-101'),
            vb = mean('PV:FT-103'),
            l0 = mean('PV:FT-102');
        final vHat = is2 ? vCw : vb + (1 - q) * f;
        final net = drum
            ? vHat - l0 - mean('PV:FT-104')
            : f + l0 - vHat - mean('PV:FT-105');
        final pred = net * w / n1;
        final meas = endMean(lt) - startMean(lt);
        final r = meas - pred;
        final band = 1.0 + 0.5 * w / 600;
        out.add(CrossCheckResult(id, title, r, band, statusOf(r, band), inputs,
            null, {'measured': meas, 'predicted': pred}));
      }
    }

    // ---- C6 tray temperatures, C7 bubble-point consistency (Tiers 2/3)
    if (is2) {
      final tags = tiTags(t2);
      final n6 = tags.length;
      final inputs6 = tags;
      final bad6 = ready2 ? badInput(tags) : null;
      if (!ready2) {
        for (final tag in tags) {
          out.add(na('C6:$tag', 'check.c6', [tag], 'collecting data'));
        }
      } else if (bad6 != null) {
        for (final tag in tags) {
          out.add(na('C6:$tag', 'check.c6', inputs6, 'BAD input $bad6'));
        }
      } else {
        final tm = [for (final tag in tags) mean('PV:$tag')];
        final ref = tiReference;
        final dT = [
          for (var k = 0; k < n6; k++)
            ref != null && ref.containsKey(tags[k])
                ? tm[k] - ref[tags[k]]!
                : double.nan
        ];
        // pass 1: residuals of the two parts for every TI
        final rOrd = List<double>.filled(n6, 0), rChg = List<double>.filled(n6, 0);
        final bChg = List<double>.filled(n6, 1.0);
        for (var k = 0; k < n6; k++) {
          // (a) ordering: going down the column the readings must rise
          final above = k > 0 ? tm[k - 1] : double.nan;
          final below = k < n6 - 1 ? tm[k + 1] : double.nan;
          var ro = 0.0;
          if (!above.isNaN) ro = math.max(ro, above - tm[k]);
          if (!below.isNaN) ro = math.max(ro, tm[k] - below);
          rOrd[k] = ro;
          // (b) change since the reference against the neighbours
          if (ref != null && !dT[k].isNaN) {
            final da = k > 0 ? dT[k - 1] : double.nan;
            final db = k < n6 - 1 ? dT[k + 1] : double.nan;
            double expect;
            double nbMax;
            if (!da.isNaN && !db.isNaN) {
              expect = 0.5 * (da + db);
              nbMax = math.max(da.abs(), db.abs());
            } else {
              final one = da.isNaN ? db : da;
              expect = one.isNaN ? dT[k] : one;
              nbMax = one.isNaN ? 0.0 : one.abs();
            }
            rChg[k] = dT[k] - expect;
            // the end TIs have a single neighbour: factor 0.75 instead of 0.5 (DEVIATIONS.md E53)
            final factor = (!da.isNaN && !db.isNaN) ? 0.5 : 0.75;
            bChg[k] = math.max(1.0, factor * nbMax);
          }
        }
        // pass 2: a flagged TI is `fail` only if its residual is the largest among its flagged neighbours; a
        // neighbour of a lying TI sees the lie in its own comparison and is `check` (DEVIATIONS.md E53)
        bool flagged(int k) =>
            k >= 0 && k < n6 && (rChg[k].abs() > bChg[k] || rOrd[k] > 0.5);
        double size(int k) => math.max(rChg[k].abs() / bChg[k], rOrd[k] / 0.5);
        for (var k = 0; k < n6; k++) {
          CheckStatus st;
          if (!flagged(k)) {
            st = CheckStatus.ok;
          } else {
            final lead = (!flagged(k - 1) || rChg[k].abs() >= rChg[k - 1].abs()) &&
                (!flagged(k + 1) || rChg[k].abs() >= rChg[k + 1].abs());
            st = ((lead && size(k) >= 1.3) || rOrd[k] > 1.0)
                ? CheckStatus.fail
                : CheckStatus.check;
          }
          final useOrder = rOrd[k] / 0.5 > rChg[k].abs() / bChg[k];
          out.add(CrossCheckResult(
              'C6:${tags[k]}',
              'check.c6',
              useOrder ? rOrd[k] : rChg[k],
              useOrder ? 0.5 : bChg[k],
              st,
              [tags[k]],
              null,
              {
                'mean': tm[k],
                'dT': dT[k],
                'ordering': rOrd[k],
                'size': size(k),
              }));
        }
      }
      // C7
      for (final top in [true, false]) {
        final id = top ? 'C7:top' : 'C7:bottom', title = 'check.c7';
        final inputs = top
            ? ['TI-100', 'AT-101', 'PT-101']
            : [sumpTi, 'AT-102', 'PT-101', 'PDT-101'];
        if (!ready2) {
          out.add(na(id, title, inputs, 'collecting data'));
        } else if (badInput(inputs) case final bad?) {
          out.add(na(id, title, inputs, 'BAD input $bad'));
        } else if (_atEnd(cs, top ? 'AT-101' : 'AT-102', mean(top ? 'PV:AT-101' : 'PV:AT-102'))) {
          out.add(na(id, title, inputs,
              '${top ? 'AT-101' : 'AT-102'} is at the end of its range'));
        } else {
          final th = t2.thermo;
          final p = mean('PV:PT-101');
          double r, tb2;
          if (top) {
            final xd = 1 - mean('PV:AT-101');
            _x[0] = xd;
            _x[1] = 1 - xd;
            tb2 = th.bubbleAt(p, _x, 0, mean('PV:TI-100') + 1, _y, 0, _k, 0, _health);
            r = mean('PV:TI-100') + t2.refluxSubLever - tb2;
          } else {
            final xb = mean('PV:AT-102');
            _x[0] = xb;
            _x[1] = 1 - xb;
            tb2 = th.bubbleAt(p + mean('PV:PDT-101'), _x, 0, mean('PV:$sumpTi'), _y, 0, _k, 0, _health);
            r = mean('PV:$sumpTi') - tb2;
          }
          out.add(CrossCheckResult(id, title, r, 1.0, statusOf(r, 1.0), inputs,
              null, {'bubble': tb2, 'pressure': p}));
        }
      }
    }
    results = out;
  }
}
