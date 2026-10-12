// VC-16 controllers: PID arithmetic (bare loop), flow loop, level loops,
// BAD-PV handling, valve faults and bypass.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';
import 'reference/validation_expectations_m3.dart';

/// A bare PID loop on a 0–100 span (VALIDATION.md VC-16 preamble).
ControlLoop _bare(
    {required double kc,
    required double ti,
    double td = 0,
    required Action action,
    bool spKick = true,
    double sp = 50,
    double op = 50,
    LoopMode mode = LoopMode.auto}) {
  final l = ControlLoop(
    tag: 'XC-1',
    pvTag: 'XT-1',
    mvRef: 'XV-1',
    params: PidParams(kc: kc, ti: ti, td: td, action: action, spKick: spKick),
    fastLayer: false,
    lo: 0,
    hi: 100,
  );
  l.mode = mode;
  l.sp = sp;
  l.op = op;
  return l;
}

void main() {
  group('VC-16.1 PID arithmetic (Kc 2, Ti 10, h 1, direct, OP0 50)', () {
    test('PV 50 → 51: OP 52.2 after 1, 54.0 after 10, 52.0 after PV back', () {
      final l = _bare(kc: 2, ti: 10, action: Action.direct);
      l.execute(50, 1);
      expect(l.execute(51, 1), closeTo(vc161.op1, 1e-12));
      for (var k = 2; k <= 10; k++) {
        l.execute(51, 1);
      }
      expect(l.op, closeTo(vc161.op10, 1e-12));
      expect(l.execute(50, 1), closeTo(vc161.opBack, 1e-12));
    });

    test('SP step 50 → 49 with spKick true: 52.2 / 54.0; re-based: 50.2 / 52.0',
        () {
      for (final (kick, op1, op10) in [
        (true, vc161.op1, vc161.op10),
        (false, vc161.rebasedOp1, vc161.rebasedOp10)
      ]) {
        final l = _bare(kc: 2, ti: 10, action: Action.direct, spKick: kick);
        l.execute(50, 1);
        l.setSp(49);
        expect(l.execute(50, 1), closeTo(op1, 1e-12),
            reason: 'spKick=$kick after 1');
        for (var k = 2; k <= 10; k++) {
          l.execute(50, 1);
        }
        expect(l.op, closeTo(op10, 1e-12), reason: 'spKick=$kick after 10');
      }
    });
  });

  group('VC-16.1b derivative sign (Kc 1, Ti ∞, Td 8 s)', () {
    for (final (action, exp) in [
      (Action.direct, vc161bDirect),
      (Action.reverse, vc161bReverse)
    ]) {
      test(action.name, () {
        final l = _bare(kc: 1, ti: double.infinity, td: 8, action: action);
        l.execute(50, 1);
        for (var k = 1; k <= 6; k++) {
          expect(l.execute(50 + k.toDouble(), 1), closeTo(exp[k - 1], 1e-9),
              reason: 'execution $k');
        }
      });
    }
  });

  test(
      'VC-16.2 anti-windup: 61, 99 at 39, 100 from 40; 88.9 then 88.8 after PV 49.5',
      () {
    final l = _bare(kc: 2, ti: 10, action: Action.direct);
    l.execute(50, 1);
    expect(l.execute(55, 1), closeTo(vc162.op1, 1e-12));
    for (var k = 2; k <= 39; k++) {
      l.execute(55, 1);
    }
    expect(l.op, closeTo(vc162.op39, 1e-12));
    for (var k = 40; k <= 100; k++) {
      l.execute(55, 1);
      expect(l.op, closeTo(100, 1e-12), reason: 'clamped at $k');
    }
    expect(l.execute(49.5, 1), closeTo(vc162.opAfterDrop1, 1e-9));
    expect(l.execute(49.5, 1), closeTo(vc162.opAfterDrop2, 1e-9));
  });

  group('VC-16.3 bumpless transfer', () {
    test(
        '(a) MAN 37.2 %, PV 62 → AUTO: SP = 62, |ΔOP| < 1e-9 for 100 executions',
        () {
      final l = _bare(
          kc: 2, ti: 10, action: Action.direct, op: 37.2, mode: LoopMode.man);
      l.execute(62, 1);
      l.setMode(LoopMode.auto);
      expect(l.sp, closeTo(62, 1e-12));
      expect(l.spTracked, isTrue);
      for (var k = 0; k < 100; k++) {
        final before = l.op;
        l.execute(62, 1);
        expect((l.op - before).abs(), lessThan(1e-9), reason: 'execution $k');
      }
      expect(l.op, closeTo(37.2, 1e-9));
    });
    test('(b) AUTO → MAN holds OP', () {
      final l = _bare(kc: 2, ti: 10, action: Action.direct);
      l.execute(50, 1);
      l.execute(53, 1);
      final op = l.op;
      l.setMode(LoopMode.man);
      l.execute(60, 1);
      expect(l.op, closeTo(op, 1e-12));
    });
  });

  group('VC-16.4 flow loop FC-102 (noise off)', () {
    test('true flow trajectory, PV at 3 s, OP, t63 3.0/3.5 s, no overshoot',
        () {
      final sim = steadyT1();
      final trace = sim.fastLayerTrace; // @visibleForTesting
      sim.setLever('refluxFlow', 110 * kmolh);
      final want = {
        for (var i = 0; i < vc164Times.length; i++)
          vc164Times[i]: vc164TrueFlow[i]
      };
      double? t63True, t63Meas, pv3, op1;
      var overshoot = 0.0;
      final t0 = sim.time;
      for (var step = 0; step < 40; step++) {
        sim.step();
        for (final p in trace.points) {
          final t = p.time - t0;
          final flow = p.flow('FV-102') / kmolh;
          final meas = p.reading('FT-102') / kmolh;
          for (final k in want.keys) {
            if ((k - t).abs() < 1e-9)
              expect(flow, closeTo(want[k]!, 0.01),
                  reason: 'true flow at $k s');
          }
          if ((t - 3).abs() < 1e-9) pv3 = meas;
          if ((t - 1).abs() < 1e-9) op1 = p.op('FC-102');
          t63True ??= flow - 100 >= 6.3 ? t : null;
          t63Meas ??= meas - 100 >= 6.3 ? t : null;
          overshoot = math.max(overshoot, flow - 110);
        }
      }
      expect(pv3!, closeTo(vc164.pv3s, 0.01));
      expect(op1!, closeTo(vc164.op1s, 0.01));
      expect(t63True!, closeTo(vc164.t63True, 0.1));
      expect(t63Meas!, closeTo(vc164.t63Meas, 0.1));
      expect(overshoot, lessThan(0.055));
      expect(loopOf(sim.snapshot(), 'FC-102').op, closeTo(vc164.opFinal, 0.01));
    });

    test(
        'main-step means at dt 0.5 and 2 s (StepDebug) and bit-identical sub-steps',
        () {
      final a = newSim(btConfig(), options: const SimOptions(dt: 0.5));
      final b = newSim(btConfig(), options: const SimOptions(dt: 2.0));
      runSteady(a);
      runSteady(b);
      a.setLever('refluxFlow', 110 * kmolh);
      b.setLever('refluxFlow', 110 * kmolh);
      for (var i = 0; i < vc164MeansDt05.length; i++) {
        a.step();
        expect(a.debug.refluxFlow / kmolh, closeTo(vc164MeansDt05[i], 0.01),
            reason: 'dt 0.5 step ${i + 1}');
      }
      for (var i = 0; i < vc164MeansDt2.length; i++) {
        b.step();
        expect(b.debug.refluxFlow / kmolh, closeTo(vc164MeansDt2[i], 0.01),
            reason: 'dt 2 step ${i + 1}');
      }
      for (var i = 0; i < 8; i++) {
        a.step();
      }
      expect(valveOf(a.snapshot(), 'FV-102').position,
          equals(valveOf(b.snapshot(), 'FV-102').position),
          reason: 'bit-identical valve position after 8 s');
      expect(reading(a.snapshot(), 'FT-102').value,
          equals(reading(b.snapshot(), 'FT-102').value));
    });

    test(
        'with the real flow loops every M1 steady state is unchanged (VC-4.1, 4.6)',
        () {
      final s1 = runSteady(newSim(btConfig()));
      expect(s1.xD, closeTo(0.981183, 1e-5));
      final sim = newSim(btConfig());
      sim.setLever('refluxFlow', 110 * kmolh);
      sim.setLever('boilup', 160 * kmolh);
      expect(runSteady(sim).xD, closeTo(0.984504, 1e-5));
      expect(
          reading(sim.snapshot(), 'FT-102').value / kmolh, closeTo(110, 1e-6),
          reason: 'integral action: PV = SP');
    });
  });

  group('VC-16.8 BAD PV handling', () {
    test(
        '(a) badPvShed = 1: LT-101 signal loss sheds LC-101 with OP held; AUTO refused',
        () {
      final sim = steadyT1();
      final op0 = loopOf(sim.snapshot(), 'LC-101').op;
      injectInstrumentFault(sim, 'LT-101', 'signalLossLow');
      sim.step();
      final s = sim.snapshot();
      final lc = loopOf(s, 'LC-101');
      expect(lc.mode, LoopMode.man);
      expect(lc.shed, isTrue);
      expect(lc.op, closeTo(op0, 1e-12));
      expect(hasAlarm(s, 'LT-101.BAD'), isTrue);
      expect(hasAlarm(s, 'LC-101.SHED'), isTrue);
      expect(
          () => sim.control.setMode('LC-101', LoopMode.auto), throwsStateError);
    });
    test(
        '(b) badPvShed = 0: LC-101 driven to 0 %, LC-102 (signalLossHigh) to 100 %',
        () {
      final sim = steadyT1();
      sim.setLever('badPvShed', 0);
      injectInstrumentFault(sim, 'LT-101', 'signalLossLow');
      injectInstrumentFault(sim, 'LT-102', 'signalLossHigh');
      sim.step();
      sim.step();
      final s = sim.snapshot();
      expect(loopOf(s, 'LC-101').mode, LoopMode.auto);
      expect(loopOf(s, 'LC-101').op, closeTo(0, 1e-9));
      expect(loopOf(s, 'LC-102').op, closeTo(100, 1e-9));
    });
    test('(c) ratio mode with FT-104 BAD: FC-102 SP holds its last GOOD value',
        () {
      final sim = steadyT1();
      sim.setLever('refluxMode', 1);
      sim.setLever('refluxRatio', 2.0);
      sim.advance(60);
      final sp0 = loopOf(sim.snapshot(), 'FC-102').sp;
      injectInstrumentFault(sim, 'FT-104', 'signalLossLow');
      sim.advance(60);
      expect(loopOf(sim.snapshot(), 'FC-102').sp, closeTo(sp0, 1e-9));
    });
  });

  group('VC-16.9 valve faults and bypass (FC-102, noise off)', () {
    test(
        '(a) FV-102 stuck, SP +10: flow unchanged, OP 2.1 % kick then 1 %/s, 100 % at 64.7 s, OPSAT 60 s later',
        () {
      final sim = steadyT1();
      final flow0 = sim.snapshot().streams[StreamId.reflux]!.flow;
      final op0 = loopOf(sim.snapshot(), 'FC-102').op;
      injectValveFault(sim, 'FV-102', 'stuck');
      sim.step();
      sim.setLever('refluxFlow', 110 * kmolh);
      double? tSat, tOpsat;
      final t0 = sim.time;
      advanceSampling(sim, 180, 0.5, (t, s) {
        expect(s.streams[StreamId.reflux]!.flow, closeTo(flow0, 1e-9),
            reason: 'flow at $t');
        tSat ??= loopOf(s, 'FC-102').op >= 100 - 1e-9 ? t : null;
        tOpsat ??= hasAlarm(s, 'FC-102.OPSAT') ? t : null;
      });
      expect(tSat!, closeTo(vc169.stuckSatTime, 0.5));
      expect(tOpsat!, closeTo(tSat! + 60, 1.0));
      expect(sim.time - t0, greaterThan(170));
      expect(op0, closeTo(100 / 3, 0.01));
    });
    test(
        '(b) failOpen: 63 % of the way to 300 kmol/h after 2.1 s; OP driven to 0',
        () {
      final sim = steadyT1();
      injectValveFault(sim, 'FV-102', 'failOpen');
      double? t63;
      advanceSampling(sim, 60, 0.5, (t, s) {
        final f = s.streams[StreamId.reflux]!.flow / kmolh;
        t63 ??= f - 100 >= 0.63 * 200 ? t : null;
      });
      expect(t63!, closeTo(vc169.failOpenT63, 0.5)); // 0.5-s step means
      expect(loopOf(sim.snapshot(), 'FC-102').op, closeTo(0, 1e-6));
    });
    test(
        '(c) bypass.FV-102 = 33.3: ramps at 2 %/s, flow 99.9, FC-102 forced to MAN, FT-102 reads it',
        () {
      final sim = steadyT1();
      injectValveFault(sim, 'FV-102', 'stuck');
      sim.setLever('bypass.FV-102', 33.3);
      sim.advance(5);
      expect(valveOf(sim.snapshot(), 'FV-102').bypass, closeTo(10, 1.5),
          reason: '2 %/s hand wheel');
      expect(loopOf(sim.snapshot(), 'FC-102').mode, LoopMode.man);
      sim.advance(120);
      expect(sim.snapshot().streams[StreamId.reflux]!.flow / kmolh,
          closeTo(99.9, 0.1));
      expect(
          reading(sim.snapshot(), 'FT-102').value / kmolh, closeTo(99.9, 0.1));
    });
  });

  test(
      'VC-16.5 level loops keep VC-7.3 within its bands with the real flow loops',
      () {
    final sim = steadyT1();
    sim.setLever('refluxFlow', 110 * kmolh);
    var maxDev = 0.0;
    advanceSampling(sim, 4 * 3600, 30,
        (t, s) => maxDev = math.max(maxDev, (s.kpis.drumLevelPct - 50).abs()));
    expect(maxDev, inInclusiveRange(2, 6));
    expect(runSteady(sim).drumLevel, closeTo(50, 0.01));
  });
}
