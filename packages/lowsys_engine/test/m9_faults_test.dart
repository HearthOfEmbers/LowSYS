// M9: VC-15.5 faults F24-F27 and the VALIDATION.md section H H8 rows (noise off, middle of each range).
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm9_helpers.dart';

void main() {
  final base = kpiOf(crudeSim());
  final baseQc = base.qc;

  group('VC-15.5 steady states', () {
    test('F24 bottom steam s = 1', () {
      final s = crudeSim();
      injectF24(s, 'bottom', 1.0);
      s.advance(300);
      expect(c(kpiOf(s).bottomT) - c(base.bottomT), greaterThan(12), reason: '>= +12 K within 5 min');
      steadyC(s);
      final k = kpiOf(s);
      expect(k.yieldVolPct[4], closeTo(49.92, 0.5));
      expect(k.bottomT - base.bottomT, closeTo(14.9, 2));
      expect(k.flashZoneT - base.flashZoneT, closeTo(1.75, 2));
      expect(100 * (k.qc / baseQc - 1), closeTo(-28, 4));
      expect(k.overflashVolPct, closeTo(0, 0.6));
      expect(k.yieldVolPct[3], closeTo(3.20, 0.5));
      expect(k.drawDry[2], isTrue);
      expect(s.control.loop('FC-321').op, closeTo(100, 0.5));
      expect(s.snapshot().alarms.any((a) => a.id == 'model.drawDry'), isTrue);
    });
    test('F24 bottom steam s = 0.5 and ss2 s = 1', () {
      var s = crudeSim();
      injectF24(s, 'bottom', 0.5);
      steadyC(s);
      var k = kpiOf(s);
      expect(k.yieldVolPct[4] - base.yieldVolPct[4], closeTo(0.52, 0.2));
      expect(k.bottomT - base.bottomT, closeTo(5.8, 1.5));
      expect(100 * (k.qc / baseQc - 1), closeTo(-12.6, 3));
      expect(k.drawDry, [false, false, false]);
      s = crudeSim();
      injectF24(s, 'ss2', 1.0);
      steadyC(s);
      k = kpiOf(s);
      expect(c(k.d86p5[2]), closeTo(188.5, 6));
      expect(k.gapDieselKero, closeTo(-55.5, 8));
    });
    test('F25 s = 1 (trip): timeline and new steady state', () {
      final s = crudeSim();
      injectF25(s, 1.0);
      var peak = 0.0;
      double? qc5;
      var d95Start = base.d86p95[2];
      var d95Up = true;
      for (var t = 30; t <= 2400; t += 30) {
        s.advance(30);
        peak = peak > instr(s, 'TI-341') - 398.15 ? peak : instr(s, 'TI-341') - 398.15;
        if (t == 300) qc5 = kpiOf(s).qc;
        if (t >= 120 && t <= 600 && kpiOf(s).d86p95[2] < d95Start) d95Up = false;
      }
      expect(peak, greaterThan(6));
      expect(qc5! / 1e6, closeTo(13.70, 13.70 * 0.04));
      expect(d95Up, isTrue);
      expect(s.snapshot().kpis.crude!.topT, closeTo(398.15, 1.0)); // back within 1 K by 40 min
      steadyC(s);
      final k = kpiOf(s);
      expect(k.qc / 1e6, closeTo(13.70, 13.70 * 0.04));
      expect(s.snapshot().streams[StreamId.reflux]!.flow * 3.6, closeTo(678, 678 * 0.04));
      expect(c(k.d86p95[2]), closeTo(324.3, 4));
      expect(s.snapshot().kpis.maxFloodPct, closeTo(88.6, 5));
    });
    test('F25 s = 0.5 and 0.85', () {
      var s = crudeSim();
      injectF25(s, 0.5);
      steadyC(s);
      var k = kpiOf(s);
      expect(k.qPa / 1e6, closeTo(5.0, 0.05));
      expect(k.paDutyLimited, isFalse);
      expect(c(k.paReturnT), closeTo(140.0, 3));
      s = crudeSim();
      injectF25(s, 0.85);
      steadyC(s);
      k = kpiOf(s);
      expect(k.qPa / 1e6, closeTo(1.77, 0.15));
      expect(c(k.paReturnT), closeTo(120.0, 0.5));
      expect(k.paDutyLimited, isTrue);
      expect(s.control.loop('FC-314').op, closeTo(100, 0.5));
      expect(100 * (k.qc / baseQc - 1), closeTo(34, 4));
      expect(s.snapshot().streams[StreamId.reflux]!.flow / (316.1 / 3.6), closeTo(1.73, 0.1));
    });
    test('F26 s = 1 and 0.6; TI-320 keeps reading the SP', () {
      var s = crudeSim();
      injectF26(s, 1.0);
      steadyC(s);
      var k = kpiOf(s);
      expect(k.flashZoneT - base.flashZoneT, closeTo(-14.0, 1.5));
      expect(k.bottomT - base.bottomT, closeTo(-13.3, 1.5));
      expect(100 * (k.qc / baseQc - 1), closeTo(-9.2, 2));
      expect(k.overflashVolPct, lessThan(0.2));
      expect(k.yieldVolPct[3], closeTo(5.15, 0.15));
      expect(c(k.d86p95[3]), closeTo(459, 15));
      expect(k.yieldVolPct[4], closeTo(46.55, 0.3));
      expect(instr(s, 'TI-320'), closeTo(618.15, 0.3));
      expect(k.cot, closeTo(603.15, 0.3));
      s = crudeSim();
      injectF26(s, 0.6);
      steadyC(s);
      k = kpiOf(s);
      expect(k.flashZoneT - base.flashZoneT, closeTo(-8.0, 1.5));
      expect(k.bottomT - base.bottomT, closeTo(-7.5, 1.5));
      expect(100 * (k.qc / baseQc - 1), closeTo(-5.9, 2));
      expect(k.overflashVolPct, closeTo(1.44, 0.5));
    });
    test('F27 through the levers', () {
      var s = crudeSim(levers: {'drawRate.kero': 0.16 * crudeRate0});
      steadyC(s);
      var k = kpiOf(s);
      expect(k.yieldVolPct[3], closeTo(4.60, 0.3));
      expect(k.yieldVolPct[4], closeTo(43.02, 0.3));
      expect(k.overflashVolPct, closeTo(0, 0.5));
      expect(k.drawDry[2], isTrue);
      s = crudeSim(levers: {'paDuty': 8e6});
      steadyC(s);
      k = kpiOf(s);
      expect(k.yieldVolPct[1], closeTo(7.97, 1.0));
      expect(k.drawDry[0], isTrue);
      expect(c(k.d86p5[2]), closeTo(201.6, 6));
      expect(k.yieldVolPct[4], closeTo(49.58, 1.0));
    });
  });

  group('H8 rows (noise off, middle of each range)', () {
    test('steam_loss: F24 bottom s = 0.85', () {
      final s = crudeSim();
      final t349 = instr(s, 'TI-349'), t350 = instr(s, 'TI-350');
      injectF24(s, 'bottom', 0.85);
      s.advance(300);
      expect(instr(s, 'TI-350') - t350, greaterThanOrEqualTo(6));
      final d349 = instr(s, 'TI-349') - t349;
      expect(d349, inInclusiveRange(0.5, 3));
      expect(100 * (1 - kpiOf(s).qc / baseQc), greaterThanOrEqualTo(15));
      expect(s.control.loop('FC-321').op, closeTo(100, 0.5));
      expect(instr(s, 'FT-321'), lessThan(0.555556 * 0.5));
      s.advance(1500);
      final k = kpiOf(s);
      expect(k.yieldVolPct[4] - base.yieldVolPct[4], greaterThanOrEqualTo(0.5));
      expect(k.overflashVolPct, lessThan(1));
    });
    test('pa_trip: F25 s = 0.85', () {
      final s = crudeSim();
      final fi0 = instr(s, 'FI-314');
      injectF25(s, 0.85);
      var peak = 0.0;
      for (var t = 10; t <= 300; t += 10) {
        s.advance(10);
        peak = peak > instr(s, 'TI-341') - 398.15 ? peak : instr(s, 'TI-341') - 398.15;
      }
      expect(peak, greaterThanOrEqualTo(4));
      expect(100 * (kpiOf(s).qc / baseQc - 1), greaterThanOrEqualTo(20));
      expect(instr(s, 'FI-314') / fi0, closeTo(0.15, 0.03));
      expect(s.control.loop('FC-314').op, closeTo(100, 1));
      expect(kpiOf(s).paDutyLimited, isTrue);
      expect(c(kpiOf(s).d86p95[2]) - c(base.d86p95[2]), greaterThanOrEqualTo(8));
      s.advance(2400 - 300);
      expect((instr(s, 'TI-341') - 398.15).abs(), lessThan(1));
    });
    test('cot_low: F26 s = 0.8', () {
      final s = crudeSim();
      final t349 = instr(s, 'TI-349'), t350 = instr(s, 'TI-350'), t320 = instr(s, 'TI-320');
      injectF26(s, 0.8);
      s.advance(600);
      expect(instr(s, 'TI-320'), closeTo(t320, 0.05));
      expect(instr(s, 'TI-349') - t349, lessThanOrEqualTo(-8));
      expect(instr(s, 'TI-350') - t350, lessThanOrEqualTo(-7));
      final dq = 100 * (kpiOf(s).qc / baseQc - 1);
      expect(dq, inInclusiveRange(-12, -4));
      s.advance(1200);
      expect(kpiOf(s).overflashVolPct, lessThan(1.5));
    });
    test('separation: bottoms of the ranges, noise on, 1-min means', () {
      double mean(Simulator s, String tag, double secs) {
        var sum = 0.0;
        var n = 0;
        for (var t = 0.0; t < secs; t += 5) {
          s.advance(5);
          sum += instr(s, tag);
          n++;
        }
        return sum / n;
      }

      final results = <String, (double, double)>{};
      for (final name in ['f24', 'f25', 'f26']) {
        final s = crudeSim(noise: true, seed: 3);
        s.advance(1200);
        final t350 = mean(s, 'TI-350', 60);
        final q0 = kpiOf(s).qc;
        // plant view Q_C is hidden: the true one stands in for the CW-side calculation
        switch (name) {
          case 'f24':
            injectF24(s, 'bottom', 0.7);
          case 'f25':
            injectF25(s, 0.7);
          default:
            injectF26(s, 0.6);
        }
        s.advance(240);
        final dT = mean(s, 'TI-350', 60) - t350;
        results[name] = (dT, 100 * (kpiOf(s).qc / q0 - 1));
      }
      expect(results['f24']!.$1, greaterThanOrEqualTo(5));
      expect(results['f25']!.$1.abs(), lessThanOrEqualTo(2));
      expect(results['f26']!.$1, lessThanOrEqualTo(-6));
      expect(results['f24']!.$2, lessThanOrEqualTo(-12));
      expect(results['f25']!.$2, greaterThanOrEqualTo(12));
      expect(results['f26']!.$2, inInclusiveRange(-10, -3));
    });
  });
}
