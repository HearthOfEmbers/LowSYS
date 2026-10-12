// VC-24 plant view masking and VC-25 alarms.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';

void main() {
  group('VC-24 plant view (Tier 1, noise on, 1 h with a reflux step)', () {
    test(
        'model fields masked, KPIs from readings, no model alarms, truth still inside',
        () {
      final sim = steadyT1(noise: true, seed: 2, view: 1);
      sim.setLever('refluxFlow', 110 * kmolh);
      final thermo = ThermoFactory.build(sim.config, ThermoTier.t1);
      advanceSampling(sim, 3600, 300, (t, s) {
        expect(s.view, SimView.plant);
        final st = s.stages;
        for (final arr in [
          st.x,
          st.y,
          st.yStar,
          st.liquidDown,
          st.vaporUp,
          st.entrain,
          st.weep,
          st.dp,
          st.jetFlood,
          st.dcFlood,
          st.frothFill,
          st.stability,
          st.weepFrac,
          st.efficiency,
          st.t
        ]) {
          for (final v in arr) {
            expect(v.isNaN, isTrue, reason: 'masked array at $t');
          }
        }
        final lt1 = reading(s, 'LT-101').value,
            lt2 = reading(s, 'LT-102').value;
        expect(s.kpis.drumLevelPct, closeTo(lt1, 1e-9));
        expect(s.kpis.sumpLevelPct, closeTo(lt2, 1e-9));
        expect(s.kpis.d, closeTo(reading(s, 'FT-104').value, 1e-9));
        expect(s.kpis.b, closeTo(reading(s, 'FT-105').value, 1e-9));
        expect(s.kpis.boilup, closeTo(reading(s, 'FT-103').value, 1e-9));
        expect(s.kpis.xD, closeTo(1 - reading(s, 'AT-101').value, 1e-9));
        expect(
            s.kpis.maxFloodPct.isNaN && s.kpis.balanceResidual.isNaN, isTrue);
        expect(st.holdup[0] > 0 && st.holdup[st.n - 1] > 0, isTrue,
            reason: 'measured levels drawn');
        for (final v in s.valves) {
          expect(v.position.isNaN, isTrue, reason: '${v.id} position hidden');
        }
        expect(s.visibleFaults, isEmpty);
        expect(
            s.alarms.where(
                (a) => a.id.startsWith('model.') && a.id != 'model.relief'),
            isEmpty);
      });
      expect(
          mccabeAvailable(McCabeThieleBuilder().build(sim.snapshot(), thermo)),
          isFalse);
      final ex = sim.explain(ExplainStage(5));
      expect(ex.groups, isEmpty);
      expect(ex.notes.single.toLowerCase(), contains('not observable'));
      // truth is still read by predicates
      final ctx = TrueView(sim);
      final trueXd = ctx.read('kpi.xD');
      expect(trueXd.isNaN, isFalse);
      expect(trueXd, isNot(closeTo(sim.snapshot().kpis.xD, 1e-9)),
          reason: 'analyser lag separates truth and reading');
    });
  });

  group('VC-25 alarms', () {
    test(
        '25.1 chatter: LT-101 at the HI limit, noise on, 5 seeds: ≤ 4 raises/h; at 84.5 % ≤ 15/h',
        () {
      for (final (level, maxRaises) in [(85.0, 4), (84.5, 15)]) {
        for (var seed = 1; seed <= 5; seed++) {
          final sim = steadyT1(noise: true, seed: seed);
          sim.control.setMode('LC-101', LoopMode.man);
          sim.holdDrumLevelForTest(
              level); // @visibleForTesting: pins the true level
          var raises = 0;
          var wasActive = false;
          advanceSampling(sim, 3600, 0.5, (t, s) {
            final active = s.alarms.any(
                (a) => a.id == 'LT-101.HI' && a.state != AlarmState.rtnUnack);
            if (active && !wasActive) raises++;
            wasActive = active;
            if (!active && s.alarms.any((a) => a.id == 'LT-101.HI'))
              sim.acknowledgeAlarm('LT-101.HI');
          });
          expect(raises, lessThanOrEqualTo(maxRaises),
              reason: 'level $level seed $seed: $raises raises/h');
        }
      }
    });
    test(
        '25.2 states: raise → UNACK → ACKED → removed; clear before ack → RTN-UNACK → removed; journal',
        () {
      final sim = steadyT1();
      sim.setLever('drumLevelSp', 88);
      final tRaise =
          firstTime(sim, 3600, (s) => hasAlarm(s, 'LT-101.HI'), sample: 5);
      expect(tRaise, isNotNull);
      expect(sim.snapshot().alarms.firstWhere((a) => a.id == 'LT-101.HI').state,
          AlarmState.unack);
      sim.acknowledgeAlarm('LT-101.HI');
      expect(sim.snapshot().alarms.firstWhere((a) => a.id == 'LT-101.HI').state,
          AlarmState.acked);
      sim.setLever('drumLevelSp', 50);
      final tClear =
          firstTime(sim, 3600, (s) => !hasAlarm(s, 'LT-101.HI'), sample: 5);
      expect(tClear, isNotNull);
      // raise again, clear before ack
      sim.setLever('drumLevelSp', 88);
      firstTime(sim, 3600, (s) => hasAlarm(s, 'LT-101.HI'), sample: 5);
      sim.setLever('drumLevelSp', 50);
      final tRtn = firstTime(
          sim,
          3600,
          (s) => s.alarms.any(
              (a) => a.id == 'LT-101.HI' && a.state == AlarmState.rtnUnack),
          sample: 5);
      expect(tRtn, isNotNull);
      sim.acknowledgeAllAlarms();
      expect(hasAlarm(sim.snapshot(), 'LT-101.HI'), isFalse);
      final j = sim.control.alarms.journal;
      expect(j.where((e) => e.alarmId == 'LT-101.HI').length,
          greaterThanOrEqualTo(5));
      for (var i = 1; i < j.length; i++) {
        expect(j[i].time, greaterThanOrEqualTo(j[i - 1].time));
      }
    });
    test(
        '25.3 DEV after 30 s in AUTO only, cleared by MAN; OPSAT after 60 s; BAD immediate; ordering',
        () {
      final sim = steadyT1();
      sim.control.setSp('FC-102', 130 * kmolh); // 10 % of span deviation
      injectValveFault(sim, 'FV-102', 'stuck');
      final tDev =
          firstTime(sim, 120, (s) => hasAlarm(s, 'FC-102.DEV'), sample: 0.5);
      expect(tDev, isNotNull);
      expect(tDev!, inInclusiveRange(30, 36));
      final tSat =
          firstTime(sim, 600, (s) => hasAlarm(s, 'FC-102.OPSAT'), sample: 0.5);
      expect(tSat, isNotNull);
      sim.control.setMode('FC-102', LoopMode.man);
      sim.advance(15);
      expect(
          hasAlarm(sim.snapshot(), 'FC-102.DEV') &&
              sim
                      .snapshot()
                      .alarms
                      .firstWhere((a) => a.id == 'FC-102.DEV')
                      .state !=
                  AlarmState.rtnUnack,
          isFalse);
      injectInstrumentFault(sim, 'LT-102', 'signalLossLow');
      sim.step();
      expect(hasAlarm(sim.snapshot(), 'LT-102.BAD'), isTrue,
          reason: 'no on-delay');
      final list = sim.snapshot().alarms;
      for (var i = 1; i < list.length; i++) {
        expect(list[i].priority.index <= list[i - 1].priority.index, isTrue,
            reason: 'priority order');
        if (list[i].priority == list[i - 1].priority)
          expect(list[i].changedAt <= list[i - 1].changedAt, isTrue,
              reason: 'newest first');
      }
    });
    test(
        '25.4 readings, not truth: LT-101 bias −10 %: no HI at a true 87 %; safety accumulator uses truth',
        () {
      final sim = steadyT1();
      injectInstrumentFault(sim, 'LT-101', 'bias', severity: 1.0, sign: -1);
      sim.setLever('drumLevelSp', 77); // reading 77 → true 87
      sim.advance(3 * 3600);
      expect(sim.snapshot().kpis.drumLevelPct, closeTo(87, 1.0));
      expect(hasAlarm(sim.snapshot(), 'LT-101.HI'), isFalse);
      sim.setLever('drumLevelSp', 86); // true 96 > 95
      sim.advance(3 * 3600);
      expect(sim.safetyLevelViolationSeconds, greaterThan(60));
    });
  });
}
