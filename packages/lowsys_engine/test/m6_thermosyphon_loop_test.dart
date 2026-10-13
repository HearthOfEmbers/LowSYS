// VC-14.1 (coder run): the standalone thermosyphon loop at fixed inputs against the readiness-prototype table.
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

class _Row {
  final String label;
  final double qSp, level, op, w, xe, q, iS, amp, period;
  final double kOut, kIn, rfK;
  final double? wHalf, qHalf;
  const _Row(this.label, this.qSp, this.level, this.op, this.w, this.xe, this.q, this.iS, this.amp, this.period,
      {this.kOut = 3, this.kIn = 4, this.rfK = 0, this.wHalf, this.qHalf});
}

class _Stats {
  double sum = 0, mn = double.infinity, mx = -double.infinity;
  int n = 0;
  void add(double x) {
    sum += x;
    n++;
    mn = math.min(mn, x);
    mx = math.max(mx, x);
  }

  double get mean => sum / n;
  double get half => (mx - mn) / 2;
}

const _rows = [
  _Row('90 % / 100 %', 1300e3, 90, 100, 19.33, 0.136, 1300, 0.40, 0, 9.8),
  _Row('75 % / 100 %', 1300e3, 75, 100, 16.79, 0.169, 1300, 0.50, 0, 9.6),
  _Row('75 % / 16 %', 1300e3, 75, 16, 13.05, 0.231, 1300, 0.47, 0, 10.0),
  _Row('50 % / 100 %', 1300e3, 50, 100, 12.98, 0.241, 1300, 0.74, 0, 9.2),
  _Row('15 % / 100 %', 1300e3, 15, 100, 8.23, 0.406, 1277, 1.28, 0.141, 8.6, wHalf: 0.27, qHalf: 229),
  _Row('15 % / 16 %', 1300e3, 15, 16, 7.30, 0.446, 1236, 1.08, 0.082, 9.0, wHalf: 0.08, qHalf: 163),
  _Row('15 % / 8 %', 1300e3, 15, 8, 5.83, 0.493, 1087, 0.87, 0, 10.2),
  _Row('1600 kW 75 %', 1600e3, 75, 100, 15.58, 0.239, 1597, 0.72, 0, 8.2),
  _Row('1600 kW 30 %', 1600e3, 30, 100, 9.88, 0.375, 1443, 1.17, 0.116, 8.1, wHalf: 0.26, qHalf: 260),
  _Row('K_out 20', 1300e3, 75, 100, 6.94, 0.434, 1203, 1.42, 0.163, 11.5, kOut: 20, wHalf: 0.34, qHalf: 313),
  _Row('R_f 8.4e-6', 1300e3, 75, 100, 17.24, 0.138, 1141, 0.41, 0, 10.6, rfK: 8.40e-6),
  _Row('K_in 154', 1300e3, 50, 100, 8.02, 0.412, 1297, 0.67, 0, 9.7, kIn: 154),
  _Row('K_out 19', 1300e3, 50, 100, 5.95, 0.478, 1109, 1.56, 0.180, 11.5, kOut: 19, wHalf: 0.24, qHalf: 339),
];

ThermosyphonLoop _loop({double kOut = 3, double kIn = 4}) {
  final geo = ThermosyphonGeometry(kOut: kOut, kIn: kIn);
  final l = ThermosyphonLoop(geo);
  l.w = 12;
  return l;
}

void main() {
  for (final r in _rows) {
    test('VC-14.1 ${r.label}', () {
      final l = _loop(kOut: r.kOut, kIn: r.kIn);
      const dt = 0.1;
      final n = (3600 / dt).round(), nAvg = (300 / dt).round();
      final sw = _Stats(), sx = _Stats(), sq = _Stats(), si = _Stats(), sa = _Stats(), st = _Stats();
      var prevU = 0.0;
      var lastCross = double.nan;
      final crossings = <double>[];
      for (var i = 0; i < n; i++) {
        l.substep(dt, r.qSp, r.level, 2.4, r.op, rfK: r.rfK);
        if (i >= n - nAvg) {
          sw.add(l.w);
          sx.add(l.xe);
          sq.add(l.qDelivered);
          si.add(l.iS);
          sa.add(l.amplitude);
          st.add(l.tOsc);
          if (prevU < 0 && l.u >= 0) {
            if (!lastCross.isNaN) crossings.add(i * dt - lastCross);
            lastCross = i * dt;
          }
        }
        prevU = l.u;
      }
      expect(sw.mean, closeTo(r.w, 0.03 * r.w), reason: 'W');
      expect(sx.mean, closeTo(r.xe, 0.01), reason: 'x_e');
      expect(sq.mean / 1000, closeTo(r.q, 0.01 * r.q), reason: 'Q');
      expect(si.mean, closeTo(r.iS, 0.03), reason: 'I_s');
      if (r.amp == 0) {
        expect(sa.mean, lessThan(1e-4), reason: 'amplitude');
        expect(st.mean, closeTo(r.period, 0.15 * r.period), reason: 'T_osc');
      } else {
        expect(sa.mean, closeTo(r.amp, 0.3 * r.amp), reason: 'amplitude');
        final per = crossings.isEmpty ? st.mean : crossings.reduce((a, b) => a + b) / crossings.length;
        expect(per, closeTo(r.period, 0.15 * r.period), reason: 'period');
        expect(sw.half, closeTo(r.wHalf!, 0.3 * r.wHalf! + 0.02), reason: 'W half-range');
        expect(sq.half / 1000, closeTo(r.qHalf!, 0.3 * r.qHalf!), reason: 'Q half-range');
      }
    });
  }

  test('VC-14.1 spot values: dT_sub, Q_max,0, A_t', () {
    final l = _loop();
    l.substep(0.1, 1300e3, 75, 2.4, 100);
    expect(l.dTsub, closeTo(8.33, 0.05));
    expect(l.qMax0 / 1000, closeTo(1597, 5));
    l.substep(0.1, 1300e3, 50, 2.4, 100);
    expect(l.dTsub, closeTo(6.67, 0.05));
    expect(l.qMax0 / 1000, closeTo(1636, 5));
    expect(l.at, closeTo(0.0706, 0.0001));
  });

  test('VC-14.1 delta independence: 15 % / 100 % at 0.025 s', () {
    double meanW(double dt) {
      final l = _loop();
      final n = (3600 / dt).round(), nAvg = (300 / dt).round();
      var s = 0.0, c = 0, a = 0.0;
      for (var i = 0; i < n; i++) {
        l.substep(dt, 1300e3, 15, 2.4, 100);
        if (i >= n - nAvg) {
          s += l.w;
          a += l.amplitude;
          c++;
        }
      }
      return s / c + 1000 * a / c;
    }
    expect(meanW(0.025), closeTo(meanW(0.1), 0.05 * meanW(0.1)));
  });

  test('VC-14.1 no jitter: |dx_e| <= 0.01 between sub-steps at 15 % / 100 %', () {
    final l = _loop();
    var prev = double.nan, maxd = 0.0;
    for (var i = 0; i < 12000; i++) {
      l.substep(0.1, 1300e3, 15, 2.4, 100);
      if (i > 6000 && !prev.isNaN) maxd = math.max(maxd, (l.xe - prev).abs());
      prev = l.xe;
    }
    expect(maxd, lessThan(0.01));
  });

  test('VC-14.1 robustness: 400 random input sets never go non-finite or out of range', () {
    final rng = math.Random(7);
    for (var k = 0; k < 400; k++) {
      final geo = ThermosyphonGeometry(kOut: 3 + 40 * rng.nextDouble(), kIn: 4 + 300 * rng.nextDouble());
      final l = ThermosyphonLoop(geo)..w = 30 * rng.nextDouble();
      final level = 100 * rng.nextDouble(), op = 5 + 95 * rng.nextDouble();
      final qsp = 0.1e6 + 3e6 * rng.nextDouble();
      final rf = 4.2e-5 * rng.nextDouble(), ff = 0.8 * rng.nextDouble();
      for (var i = 0; i < 6000; i++) {
        l.substep(0.1, qsp, level, 2.4, op, rfK: rf, fFlooded: ff);
        if (i % 200 == 0 || i == 5999) {
          expect([l.w, l.xe, l.q, l.iS, l.u, l.v].every((x) => x.isFinite), isTrue, reason: 'finite #$k');
          expect(l.w, greaterThanOrEqualTo(0));
          expect(l.xe, inInclusiveRange(0, 1));
          expect(l.fsc, inInclusiveRange(0, 1));
          expect(l.amplitude, lessThanOrEqualTo(0.3 + 1e-9));
        }
      }
    }
  });
}
