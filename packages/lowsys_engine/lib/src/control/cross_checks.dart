import 'dart:math' as math;

import '../snapshot/sim_snapshot.dart';
import 'control_system.dart';
import 'trend_buffer.dart';

const double _kmolh = 1000 / 3600;

/// Cross-checks C1, C3, C4 and C5 of PHYSICS.md 14.6, computed from the 5-s trend bins of the readings only.
class CrossCheckEngine {
  /// Window (s): 300, 600, 1800 or 3600.
  double window = 600;
  List<CrossCheckResult> results = const [];

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

  /// Recomputes every check. [q] is the feed condition lever.
  void evaluate(TrendBuffer tb, ControlSystem cs, double q, bool steady) {
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
    final w = window;

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
        final band = math.max(2.0 * _kmolh, 0.02 * f);
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
    // ---- C3 (Tier 1)
    {
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
        final band = math.max(2.0 * _kmolh, 0.015 * vRefl);
        out.add(CrossCheckResult(id, title, r, band, statusOf(r, band), inputs,
            null, {'fromBoilup': vBoil, 'fromReflux': vRefl, 'difference': r}));
      }
    }
    // ---- C4, one per valve and meter
    for (final (valve, meter, loop) in const [
      ('FV-101', 'FT-101', 'FC-101'),
      ('FV-102', 'FT-102', 'FC-102'),
      ('FV-103', 'FT-103', 'FC-103'),
      ('LV-101', 'FT-104', 'LC-101'),
      ('LV-102', 'FT-105', 'LC-102'),
    ]) {
      final id = 'C4:$valve', title = 'check.c4';
      final inputs = [meter];
      if (!ready) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if (badInput(inputs) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else {
        final v = cs.valve(valve);
        final op = mean('OP:$loop');
        final fexp = v.expectedFlow(op);
        final fm = mean('PV:$meter');
        final r = fm - fexp;
        final band = 0.015 * v.fMax;
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
      if (!ready) {
        out.add(na(id, title, inputs, 'collecting data'));
      } else if (badInput(inputs) case final bad?) {
        out.add(na(id, title, inputs, 'BAD input $bad'));
      } else {
        final lt = drum ? 'PV:LT-101' : 'PV:LT-102';
        final n1 = drum ? cs.n01 : cs.ns1;
        final f = mean('PV:FT-101'),
            vb = mean('PV:FT-103'),
            l0 = mean('PV:FT-102');
        final vHat = vb + (1 - q) * f;
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
    results = out;
  }
}
