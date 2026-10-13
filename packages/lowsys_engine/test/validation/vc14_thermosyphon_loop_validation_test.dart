// M6 validation, loop level (VALIDATION.md VC-14.1; M6.md E.3 rows 1-18, 21, 22). The engine's ThermosyphonLoop is run
// with the fixed VC-14.1 inputs and compared with the spec table and with the validator's independent reference
// (reference/thermosyphon_reference.dart, written from PHYSICS.md 8.3 only).
import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/thermosyphon_reference.dart';

class _Row {
  final String name;
  final double qSp, level, op, kIn, kOut, rf;
  final double w, xe, q, iS, period;
  final double? amp, wHalf, xeHalf, qHalf, qSteam;
  final bool osc, marginal;
  const _Row(this.name, this.qSp, this.level, this.op, this.w, this.xe, this.q, this.iS, this.period,
      {this.kIn = 4,
      this.kOut = 3,
      this.rf = 0,
      this.amp,
      this.wHalf,
      this.xeHalf,
      this.qHalf,
      this.qSteam,
      this.osc = false,
      this.marginal = false});
}

const _rows = [
  _Row('1300 kW 90 % 100 %', 1300e3, 90, 100, 19.33, 0.136, 1300e3, 0.40, 9.8),
  _Row('1300 kW 75 % 100 %', 1300e3, 75, 100, 16.79, 0.169, 1300e3, 0.50, 9.6),
  _Row('1300 kW 75 % 16 %', 1300e3, 75, 16, 13.05, 0.231, 1300e3, 0.47, 10.0),
  _Row('1300 kW 50 % 100 %', 1300e3, 50, 100, 12.98, 0.241, 1300e3, 0.74, 9.2),
  _Row('1300 kW 30 % 100 % (marginal)', 1300e3, 30, 100, 10.19, 0.325, 1300e3, 1.01, 8.8,
      osc: true, marginal: true),
  _Row('1300 kW 15 % 100 %', 1300e3, 15, 100, 8.23, 0.406, 1277e3, 1.28, 8.6,
      osc: true, amp: 0.141, wHalf: 0.27, xeHalf: 0.055, qHalf: 229e3, qSteam: 1270e3),
  _Row('1300 kW 15 % 16 %', 1300e3, 15, 16, 7.30, 0.446, 1236e3, 1.08, 9.0,
      osc: true, amp: 0.082, wHalf: 0.08, xeHalf: 0.020, qHalf: 163e3, qSteam: 1234e3),
  _Row('1300 kW 15 % 8 %', 1300e3, 15, 8, 5.83, 0.493, 1087e3, 0.87, 10.2),
  _Row('1600 kW 75 % 100 %', 1600e3, 75, 100, 15.58, 0.239, 1597e3, 0.72, 8.2),
  _Row('1600 kW 30 % 100 %', 1600e3, 30, 100, 9.88, 0.375, 1443e3, 1.17, 8.1,
      osc: true, amp: 0.116, wHalf: 0.26, xeHalf: 0.030, qHalf: 260e3, qSteam: 1436e3),
  _Row('1300 kW K_out 20, 75 %', 1300e3, 75, 100, 6.94, 0.434, 1203e3, 1.42, 11.5,
      kOut: 20, osc: true, amp: 0.163, wHalf: 0.34, xeHalf: 0.051, qHalf: 313e3, qSteam: 1192e3),
  _Row('1300 kW R_f 8.40e-6 K/W, 75 %', 1300e3, 75, 100, 17.24, 0.138, 1141e3, 0.41, 10.6, rf: 8.40e-6),
  _Row('1300 kW K_in 154 (F17 s 0.5), 50 %', 1300e3, 50, 100, 8.02, 0.412, 1297e3, 0.67, 9.7, kIn: 154),
  _Row('1300 kW K_out 19 (F18 s 0.4), 50 %', 1300e3, 50, 100, 5.95, 0.478, 1109e3, 1.56, 11.5,
      kOut: 19, osc: true, amp: 0.180, wHalf: 0.24, xeHalf: 0.047, qHalf: 339e3, qSteam: 1096e3),
];

const _d = 0.1;

/// Engine loop with the VC-14.1 start (W0 12, x 0, u 1e-3).
ThermosyphonLoop _eng({double kIn = 4, double kOut = 3}) =>
    ThermosyphonLoop(ThermosyphonGeometry(kIn: kIn, kOut: kOut))..w = 12;

void _engStep(ThermosyphonLoop l, double q, double level, double op, TsAcc? acc, double t, {double rf = 0}) {
  l.substep(_d, q, level, 2.4, op, rfK: rf);
  if (acc != null) {
    final uUsed = l.q > 0 ? l.qDelivered / l.q - 1 : 0.0;
    acc.add(t, l.w, l.xe, l.qDelivered, l.q, l.iS, l.amplitude, uUsed, l.tOsc);
  }
}

({TsStats eng, TsStats ref}) _runRow(_Row r, {double seconds = 3600, double window = 300}) {
  final l = _eng(kIn: r.kIn, kOut: r.kOut);
  final ref = TsRefLoop(geo: TsRefGeometry(kIn: r.kIn, kOut: r.kOut));
  final ea = TsAcc(), ra = TsAcc();
  final n = (seconds / _d).round(), n0 = ((seconds - window) / _d).round();
  for (var i = 1; i <= n; i++) {
    final t = i * _d;
    _engStep(l, r.qSp, r.level, r.op, i > n0 ? ea : null, t, rf: r.rf);
    ref.step(_d, r.qSp, r.level, r.op, rf: r.rf);
    if (i > n0) {
      ra.add(t, ref.w, ref.xe, ref.qDel, ref.q, ref.iS, ref.amp, ref.uUsed, ref.tOsc);
    }
  }
  return (eng: ea.stats(oscillating: r.osc), ref: ra.stats(oscillating: r.osc));
}

double _rel(double a, double b) => (a - b).abs() / math.max(b.abs(), 1e-12);

void main() {
  final res = <String, ({TsStats eng, TsStats ref})>{};
  setUpAll(() {
    for (final r in _rows) {
      res[r.name] = _runRow(r);
      print('${r.name}\n  engine    ${res[r.name]!.eng}\n  reference ${res[r.name]!.ref}');
    }
  });

  group('VC-14.1 table (3600 s, delta 0.1 s, last 300 s)', () {
    for (final r in _rows) {
      test(r.name, () {
        final e = res[r.name]!.eng;
        // means: W ± 3 %, x_e ± 0.01, I_s ± 0.03, Q ± 1 %, period ± 15 %
        expect(e.wMean, closeTo(r.w, 0.03 * r.w), reason: 'W');
        expect(e.xeMean, closeTo(r.xe, 0.01), reason: 'x_e');
        expect(e.iS, closeTo(r.iS, 0.03), reason: 'I_s');
        expect(e.qMean, closeTo(r.q, 0.01 * r.q), reason: 'Q delivered');
        expect(e.period, closeTo(r.period, 0.15 * r.period), reason: 'period');
        if (!r.osc) {
          expect(e.amp, lessThan(1e-4), reason: 'stable row amplitude');
        } else if (r.marginal) {
          expect(e.amp, inInclusiveRange(0.002, 0.05), reason: 'marginal row amplitude');
        } else {
          expect(e.amp, closeTo(r.amp!, 0.3 * r.amp!), reason: 'amplitude');
          expect(e.wHalf, closeTo(r.wHalf!, 0.3 * r.wHalf!), reason: 'W half-range');
          expect(e.xeHalf, closeTo(r.xeHalf!, 0.3 * r.xeHalf!), reason: 'x_e half-range');
          expect(e.qHalf, closeTo(r.qHalf!, 0.3 * r.qHalf!), reason: 'Q half-range');
          expect(e.qSteam, closeTo(r.qSteam!, 0.01 * r.qSteam!), reason: 'steam-side Q');
        }
      });
    }
  });

  test('engine = independent reference (PHYSICS.md 8.3 re-implemented) on every row', () {
    for (final r in _rows) {
      final e = res[r.name]!.eng, f = res[r.name]!.ref;
      final tol = r.osc ? 2e-3 : 1e-8;
      expect(_rel(e.wMean, f.wMean), lessThan(tol), reason: '${r.name}: W');
      expect(_rel(e.xeMean, f.xeMean), lessThan(tol), reason: '${r.name}: x_e');
      expect(_rel(e.qMean, f.qMean), lessThan(tol), reason: '${r.name}: Q');
      expect(_rel(e.iS, f.iS), lessThan(tol), reason: '${r.name}: I_s');
      if (r.osc) {
        expect(_rel(e.amp, f.amp), lessThan(r.marginal ? 0.05 : 1e-2), reason: '${r.name}: amplitude');
        expect(_rel(e.period, f.period), lessThan(1e-2), reason: '${r.name}: period');
      } else {
        expect(_rel(e.period, f.period), lessThan(1e-6), reason: '${r.name}: T_osc');
      }
    }
  });

  group('E.3 spot values and hand checks', () {
    final l = _eng();
    test('#13 subcooling 8.33 / 6.67 K and Q_max,0 1597 / 1636 kW at 75 / 50 % (hand: U A (T_st - T_sump - dT_sub/2))', () {
      for (final (lv, dts, q0) in [(75.0, 8.33, 1597e3), (50.0, 6.67, 1636e3)]) {
        final z = 1.2 + lv / 100 * 2.4;
        final hand = 3.63e-4 * 780 * 9.80665 * z;
        expect(l.subcooling(l.liquidHeight(lv, 2.4)), closeTo(hand, 1e-9));
        // 50 %: 6.664 K (the spec's "6.67" is a rounding slip; its Q_max,0 1636 kW uses 6.664)
        expect(hand, closeTo(dts, 0.007));
        final q0Hand = 1000 * 47.6 * (421.25 - (383.54 + hand / 2));
        expect(l.qMax0For(l.liquidHeight(lv, 2.4)), closeTo(q0Hand, 1e-6));
        expect(q0Hand, closeTo(q0, 1e3));
      }
    });
    test('#14 dT_sat/dP with the molar latent heat: R T^2 / (lambda M P) = 3.63e-4 K/Pa', () {
      final v = 8.314462618 * 383.54 * 383.54 / (361e3 * 0.09214 * 101325);
      expect(v, closeTo(3.63e-4, 0.005 * 3.63e-4));
    });
    test('#15 A_t 0.0706 m2; N_t pi D_i L_t 40.0 m2 (A = 47.6 m2 is the outside area)', () {
      expect(l.at, closeTo(0.0706, 5e-5));
      expect(200 * math.pi * 0.0212 * 3.0, closeTo(40.0, 0.05));
    });
    test('#16 limit amplitude A_sat sqrt((I_s - 1)/I_s) = 0.140 / 0.082 and matches the simulated rows', () {
      double lim(double i) => 0.30 * math.sqrt((i - 1) / i);
      expect(lim(1.28), closeTo(0.140, 0.001));
      expect(lim(1.08), closeTo(0.082, 0.001));
      for (final n in ['1300 kW 15 % 100 %', '1300 kW 15 % 16 %', '1300 kW K_out 19 (F18 s 0.4), 50 %']) {
        final e = res[n]!.eng;
        expect(e.amp, closeTo(lim(e.iS), 0.1 * lim(e.iS)), reason: n);
      }
    });
    test('#17 W_h where the old fixed-point map slope k Q_0 / (W_h lambda) reaches 1: 8.2 (75 %) / 8.7 kg/s (15 %)', () {
      const k = 0.65 / 0.35;
      expect(k * l.qMax0For(l.liquidHeight(75, 2.4)) / 361e3, closeTo(8.2, 0.05));
      expect(k * l.qMax0For(l.liquidHeight(15, 2.4)) / 361e3, closeTo(8.7, 0.05));
    });
    test('#18 cycle mean of u <= 0.005 in every oscillating row; steam side vs delivered inside the 2 % C3b band', () {
      for (final r in _rows.where((r) => r.osc && !r.marginal)) {
        final e = res[r.name]!.eng;
        expect(e.uMean.abs(), lessThanOrEqualTo(0.005), reason: r.name);
        expect(_rel(e.qMean, e.qSteam), lessThanOrEqualTo(0.02), reason: r.name);
      }
    });
    test('#18 as written: steam side vs delivered <= 0.5 %',
        skip: 'spec item (DEVIATIONS "M6 validation"): the spec table itself gives 0.55 % (15 %), 0.92 % (K_out 20) '
            'and 1.1 % (F18): Q_k and u_k correlate, so mean(Q(1+u)) - mean(Q) is not mean(u) mean(Q)', () {
      for (final r in _rows.where((r) => r.osc && !r.marginal)) {
        final e = res[r.name]!.eng;
        expect(_rel(e.qMean, e.qSteam), lessThanOrEqualTo(0.005), reason: r.name);
      }
    });
  });

  group('E.3 loop transients and the stability boundary', () {
    test('#3 the level where I_s = 1 (spec: about 29.5 %; 30 %: I_s 1.01)', () {
      double iSAt(double lv) {
        final l = _eng();
        for (var i = 0; i < 36000; i++) {
          l.substep(_d, 1300e3, lv, 2.4, 100);
        }
        return l.iS;
      }

      final i29 = iSAt(29), i30 = iSAt(30), i31 = iSAt(31), i32 = iSAt(32);
      print('#3 I_s at 29/30/31/32 %: ${[i29, i30, i31, i32].map((e) => e.toStringAsFixed(4)).join(' / ')}');
      expect(i29, greaterThan(i30));
      expect(i30, closeTo(1.01, 0.03));
      // the crossing lies between 30 and 32 %, not at 29.5 % (I_s falls with level and is 1.01 at 30 %)
      expect(i32, lessThan(1.0));
    });
    test('#21 level step 15 -> 50 %: amplitude < 0.01 after about 220 s', () {
      final l = _eng();
      for (var i = 0; i < 36000; i++) {
        l.substep(_d, 1300e3, 15, 2.4, 100);
      }
      var t = 0.0;
      while (l.amplitude >= 0.01 && t < 1200) {
        l.substep(_d, 1300e3, 50, 2.4, 100);
        t += _d;
      }
      print('#21 amplitude < 0.01 after ${t.toStringAsFixed(1)} s');
      expect(t, closeTo(220, 0.3 * 220));
    });
    test('#22 inlet throttled to 16 % at 15 % level: amplitude 0.141 -> 0.085 after 5 min (-40 %)', () {
      final l = _eng();
      for (var i = 0; i < 36000; i++) {
        l.substep(_d, 1300e3, 15, 2.4, 100);
      }
      final a0 = l.amplitude;
      for (var i = 0; i < 3000; i++) {
        l.substep(_d, 1300e3, 15, 2.4, 16);
      }
      print('#22 amplitude ${a0.toStringAsFixed(4)} -> ${l.amplitude.toStringAsFixed(4)}');
      expect(a0, closeTo(0.141, 0.3 * 0.141));
      expect(l.amplitude, closeTo(0.085, 0.3 * 0.085));
      expect(l.amplitude / a0, inInclusiveRange(0.5, 0.7));
    });
  });

  group('physical sense and direction (loop)', () {
    TsStats s(String n) => res[n]!.eng;
    test('higher level: more circulation, lower exit quality and lower I_s', () {
      final names = ['1300 kW 15 % 100 %', '1300 kW 30 % 100 % (marginal)', '1300 kW 50 % 100 %', '1300 kW 75 % 100 %',
          '1300 kW 90 % 100 %'];
      for (var i = 1; i < names.length; i++) {
        expect(s(names[i]).wMean, greaterThan(s(names[i - 1]).wMean), reason: names[i]);
        expect(s(names[i]).xeMean, lessThan(s(names[i - 1]).xeMean), reason: names[i]);
        expect(s(names[i]).iS, lessThan(s(names[i - 1]).iS), reason: names[i]);
      }
    });
    test('inlet restriction lowers W, raises x_e and lowers I_s (Kister: inlet restriction stabilises)', () {
      expect(s('1300 kW 75 % 16 %').wMean, lessThan(s('1300 kW 75 % 100 %').wMean));
      expect(s('1300 kW 75 % 16 %').xeMean, greaterThan(s('1300 kW 75 % 100 %').xeMean));
      expect(s('1300 kW 75 % 16 %').iS, lessThan(s('1300 kW 75 % 100 %').iS));
      expect(s('1300 kW 15 % 16 %').iS, lessThan(s('1300 kW 15 % 100 %').iS));
      expect(s('1300 kW 15 % 8 %').iS, lessThan(1.0));
      expect(s('1300 kW K_in 154 (F17 s 0.5), 50 %').wMean, lessThan(s('1300 kW 50 % 100 %').wMean));
    });
    test('outlet restriction raises I_s past 1; fouling cuts the duty; more duty raises x_e', () {
      expect(s('1300 kW K_out 20, 75 %').iS, greaterThan(1.0));
      expect(s('1300 kW K_out 19 (F18 s 0.4), 50 %').iS, greaterThan(s('1300 kW 50 % 100 %').iS));
      expect(s('1300 kW R_f 8.40e-6 K/W, 75 %').qMean, lessThan(1300e3 * 0.9));
      expect(s('1600 kW 75 % 100 %').xeMean, greaterThan(s('1300 kW 75 % 100 %').xeMean));
    });
    test('stable loop closes its energy balance: Q = W (c_p dT_sub + lambda x_e); x_e, f_sc in [0, 1]', () {
      for (final (lv, op) in [(75.0, 100.0), (50.0, 100.0), (90.0, 100.0), (75.0, 16.0)]) {
        final l = _eng();
        for (var i = 0; i < 36000; i++) {
          l.substep(_d, 1300e3, lv, 2.4, op);
        }
        final rhs = l.w * (1950 * l.dTsub + 361e3 * l.xe);
        expect(_rel(l.q, rhs), lessThan(1e-6), reason: '$lv % / $op %');
        expect(l.fsc, inInclusiveRange(0, 1));
        expect(l.drivingHead, greaterThan(0));
      }
    });
  });
}
