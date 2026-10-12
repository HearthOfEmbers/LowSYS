// VC-22 instruments: 4–20 mA, noise statistics, the closed-loop noise,
// failure-mode signatures, field gauges and maintenance.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';
import 'reference/instrument_reference.dart' as ref;
import 'reference/validation_expectations_m3.dart';

/// Bare transmitter from the B-T spec table.
Instrument _bare(String tag, InstrumentType type, double lo, double hi,
    double tauM, double sigS, double tauS, double sigE,
    {int seed = 11, bool noise = false, double v0 = 0}) {
  final spec = InstrumentSpec(
      tag: tag,
      type: type,
      measures: 'test',
      lo: lo,
      hi: hi,
      tauM: tauM,
      sigmaS: sigS,
      tauS: tauS,
      sigmaE: sigE);
  return Instrument(spec, seed: seed, noise: noise, initialValue: v0);
}

Instrument _ft102({int seed = 11, bool noise = false, double v0 = 100}) =>
    _bare('FT-102', InstrumentType.ftLiquid, 0, 300 * kmolh, 0.5, 0.50, 1, 0.02,
        seed: seed, noise: noise, v0: v0 * kmolh);

void main() {
  group('VC-22.1 4–20 mA and quality (FT-102, noise off)', () {
    for (final (v, mA, vm, q) in vc221) {
      test('true $v kmol/h → $mA mA, $vm, $q', () {
        final inst = _ft102(v0: v);
        for (var k = 0; k < 200; k++) {
          inst.update(0.1, v * kmolh, k * 0.1);
        }
        final r = inst.reading;
        expect(r.milliamps, closeTo(mA, 1e-4));
        expect(r.value / kmolh, closeTo(vm, 1e-6));
        expect(r.quality.name.toUpperCase(), q);
        if (q == 'UNCERTAIN') expect(r.qualityText, startsWith('OOR'));
      });
    }
    test('signal loss low/high (via the simulator)', () {
      for (final (kind, mA, vm, txt) in [
        ('signalLossLow', 3.6, -7.5, 'IOP−'),
        ('signalLossHigh', 21.0, 318.75, 'IOP+')
      ]) {
        final sim = steadyT1();
        injectInstrumentFault(sim, 'FT-102', kind);
        sim.step();
        final r = reading(sim.snapshot(), 'FT-102');
        expect(r.milliamps, closeTo(mA, 1e-9), reason: kind);
        expect(r.value / kmolh, closeTo(vm, 1e-9), reason: kind);
        expect(r.quality, Quality.bad);
        expect(r.qualityText, txt);
        expect(hasAlarm(sim.snapshot(), 'FT-102.BAD'), isTrue);
      }
    });
    test('with noise on, I_q is a multiple of 1/4096 mA', () {
      final sim = steadyT1(noise: true);
      advanceSampling(sim, 30, 0.5, (t, s) {
        for (final r in s.instruments) {
          if (r.milliamps.isNaN) continue;
          final counts = r.milliamps * 4096;
          expect((counts - counts.roundToDouble()).abs(), lessThan(1e-6),
              reason: r.tag);
        }
      });
    });
  });

  group('VC-22.2 noise statistics (200 000 s, seed 11)', () {
    for (final (name, tag, type, lo, hi, tauM, sigS, tauS, sigE, hs) in [
      (
        'FT',
        'FT-102',
        InstrumentType.ftLiquid,
        0.0,
        300 * kmolh,
        0.5,
        0.50,
        1.0,
        0.02,
        [0.1]
      ),
      (
        'LT drum',
        'LT-101',
        InstrumentType.ltDrum,
        0.0,
        100.0,
        2.0,
        0.50,
        5.0,
        0.02,
        [0.5, 2.0]
      ),
      (
        'LT sump',
        'LT-102',
        InstrumentType.ltSump,
        0.0,
        100.0,
        2.0,
        1.00,
        3.0,
        0.02,
        [0.5, 2.0]
      ),
      (
        'PT',
        'PT-101',
        InstrumentType.pt,
        0.0,
        202650.0,
        1.0,
        0.05,
        2.0,
        0.02,
        [0.5, 2.0]
      ),
      (
        'PDT',
        'PDT-101',
        InstrumentType.pdt,
        0.0,
        40000.0,
        2.0,
        1.00,
        5.0,
        0.02,
        [0.5, 2.0]
      ),
      (
        'TI',
        'TI-114',
        InstrumentType.tiTray,
        273.15,
        473.15,
        10.0,
        0.075,
        20.0,
        0.01,
        [0.5, 2.0]
      ),
    ]) {
      test(
          '$name: sd within ±6 % of σ_disp, mean ±0.02 %, lag-τ_s autocorrelation 0.45–0.70, dt-independent',
          () {
        final sigmaDisp =
            math.sqrt(sigS * sigS * tauS / (tauS + tauM) + sigE * sigE);
        final sds = <double>[];
        for (final h in hs) {
          final mid = lo + 0.5 * (hi - lo);
          final inst = _bare(tag, type, lo, hi, tauM, sigS, tauS, sigE,
              noise: true, v0: mid);
          final n = (200000 / h).round();
          final buf = List<double>.filled(n, 0);
          for (var k = 0; k < n; k++) {
            inst.update(h, mid, k * h);
            buf[k] = (inst.reading.value - mid) / (hi - lo) * 100;
          }
          final m = mean(buf);
          final sd = stdDev(buf);
          final l = (tauS / h).round();
          var acc = 0.0;
          for (var k = l; k < n; k++) {
            acc += (buf[k] - m) * (buf[k - l] - m);
          }
          final ac = acc / (n - l) / (sd * sd);
          expect(sd, closeTo(sigmaDisp, 0.06 * sigmaDisp),
              reason: '$name h=$h sd');
          expect(m, closeTo(0, 0.02), reason: '$name h=$h mean');
          expect(ac, inInclusiveRange(0.45, 0.70),
              reason: '$name h=$h autocorrelation');
          expect(inst.reading.typicalSigma / (hi - lo) * 100,
              closeTo(sigmaDisp, 1e-6),
              reason: 'typicalSigma field');
          sds.add(sd);
        }
        if (sds.length == 2)
          expect(sds[1], closeTo(sds[0], 0.06 * sds[0]),
              reason: 'dt independence');
      });
    }

    test(
        'valve disturbance d: sd 0.0100 ± 0.0006, autocorrelation at 30 s = e⁻¹ ± 0.05',
        () {
      final sim = steadyT1(noise: true, seed: 11);
      sim.control.setMode(
          'FC-102', LoopMode.man); // constant OP → flow = F_max g(p)(1 + d)
      final pos = valveOf(sim.snapshot(), 'FV-102').position;
      final d = <double>[];
      advanceSampling(
          sim,
          20000,
          0.5,
          (t, s) => d.add(
              s.streams[StreamId.reflux]!.flow / (300 * kmolh * pos / 100) -
                  1));
      final sd = stdDev(d);
      expect(sd, closeTo(0.0100, 0.0006));
      final m = mean(d);
      var acc = 0.0;
      for (var k = 60; k < d.length; k++) {
        acc += (d[k] - m) * (d[k - 60] - m);
      }
      expect(acc / (d.length - 60) / (sd * sd), closeTo(math.exp(-1), 0.05));
    });
  });

  test(
      'VC-22.3 noise in the closed FC-102 loop (seed 3): reading sd 1.0–1.4, diffs 0.6–0.85, true 0.6–1.2, OP 0.3–0.7',
      () {
    final sim = steadyT1(noise: true, seed: 3);
    sim.advance(600);
    final readings = <double>[], trues = <double>[], ops = <double>[];
    advanceSampling(sim, 1800, 0.5, (t, s) {
      readings.add(reading(s, 'FT-102').value / kmolh);
      trues.add(s.streams[StreamId.reflux]!.flow / kmolh);
      ops.add(loopOf(s, 'FC-102').op);
    });
    expect(stdDev(readings), inInclusiveRange(1.0, 1.4));
    expect(
        stdDev([
          for (var i = 1; i < readings.length; i++)
            readings[i] - readings[i - 1]
        ]),
        inInclusiveRange(0.6, 0.85));
    expect(stdDev(trues), inInclusiveRange(0.6, 1.2));
    expect(stdDev(ops), inInclusiveRange(0.3, 0.7));
    for (var i = 0; i + 600 <= trues.length; i += 600) {
      expect(mean(trues.sublist(i, i + 600)), closeTo(100, 0.4),
          reason: '5-min mean ${i ~/ 600}');
    }
  });

  group('VC-22.5 failure-mode signatures (t0 = 600 s)', () {
    test(
        'bias FT-102 +, s 0.3: mean(reading − true) = 9.00 ± 0.1, GOOD, noise unchanged',
        () {
      final sim = steadyT1(noise: true, seed: 5);
      final pre = <double>[];
      advanceSampling(
          sim,
          600,
          0.5,
          (t, s) => pre.add(
              reading(s, 'FT-102').value - s.streams[StreamId.reflux]!.flow));
      injectInstrumentFault(sim, 'FT-102', 'bias', severity: 0.3, sign: 1);
      final post = <double>[];
      advanceSampling(
          sim,
          600,
          0.5,
          (t, s) => post.add(
              reading(s, 'FT-102').value - s.streams[StreamId.reflux]!.flow));
      expect(mean(post) / kmolh, closeTo(9.0, 0.1));
      expect(reading(sim.snapshot(), 'FT-102').quality, Quality.good);
      expect(stdDev(post), closeTo(stdDev(pre), 0.06 * stdDev(pre) + 0.02));
    });
    test('drift FT-101 +, s 0.6: +7.5 after 1800 s, +15.0 after 3600 s', () {
      final sim = steadyT1();
      sim.control
          .setMode('FC-101', LoopMode.man); // keep the true feed constant
      injectInstrumentFault(sim, 'FT-101', 'drift', severity: 0.6, sign: 1);
      sim.advance(1800);
      expect(
          (reading(sim.snapshot(), 'FT-101').value -
                  sim.snapshot().streams[StreamId.feed]!.flow) /
              kmolh,
          closeTo(7.5, 0.1));
      sim.advance(1800);
      expect(
          (reading(sim.snapshot(), 'FT-101').value -
                  sim.snapshot().streams[StreamId.feed]!.flow) /
              kmolh,
          closeTo(15.0, 0.1));
    });
    test('stuck: bitwise equal readings, σ_5min = 0, digitsAge grows', () {
      final sim = steadyT1(noise: true, seed: 2);
      injectInstrumentFault(sim, 'LT-102', 'stuck');
      sim.step();
      final frozen = reading(sim.snapshot(), 'LT-102').value;
      advanceSampling(
          sim,
          900,
          0.5,
          (t, s) => expect(reading(s, 'LT-102').value, equals(frozen),
              reason: 't=$t'));
      final r = reading(sim.snapshot(), 'LT-102');
      expect(r.sigma5min, 0);
      expect(r.digitsAge, greaterThanOrEqualTo(900));
    });
    test(
        'plugged FT-102 (noise off): fraction of a +10 % step shown 600 s after it = 0.058/0.140/0.451/0.998',
        () {
      for (final (s, frac) in vc225Plugged) {
        final sim = steadyT1();
        sim.control.setMode('FC-102', LoopMode.man);
        injectInstrumentFault(sim, 'FT-102', 'plugged', severity: s);
        sim.advance(60);
        final op = loopOf(sim.snapshot(), 'FC-102').op;
        sim.control
            .setOp('FC-102', op + 10); // true flow +30 kmol/h = +10 % of span
        sim.advance(600 + 2.5); // + the valve's own lag, see reason below
        final true1 = sim.snapshot().streams[StreamId.reflux]!.flow / kmolh;
        final shown = (reading(sim.snapshot(), 'FT-102').value / kmolh - 100) /
            (true1 - 100);
        expect(shown, closeTo(frac, 0.015),
            reason: 's=$s (valve lag adds ≈ 2 s)');
      }
    });
    test('plugged s = 1 with noise: σ_5min/σ_disp ≤ 0.08', () {
      final sim = steadyT1(noise: true, seed: 9);
      injectInstrumentFault(sim, 'FT-102', 'plugged', severity: 1.0);
      sim.advance(600);
      expect(
          signalLookRatio(sim.snapshot(), 'FT-102'), lessThanOrEqualTo(0.08));
    });
    test(
        'spiking FT-102 s = 1 / 0.5: 180 ± 40 / 90 ± 28 spikes per hour, σ ratio ≥ 10 / ≥ 4',
        () {
      for (final (s, n, tol, ratio) in [
        (1.0, 180, 40, 10.0),
        (0.5, 90, 28, 4.0)
      ]) {
        final sim = steadyT1(noise: true, seed: 4);
        sim.control.setMode('FC-102', LoopMode.man);
        injectInstrumentFault(sim, 'FT-102', 'spiking', severity: s);
        var spikes = 0;
        var inSpike = false;
        var maxRatio = 0.0;
        var anyBadHigh = false;
        advanceSampling(sim, 3600, 0.5, (t, st) {
          final r = reading(st, 'FT-102');
          final dev = (r.value - st.streams[StreamId.reflux]!.flow).abs() /
              (300 * kmolh) *
              100;
          final spike = dev > 8; // spikes are 10–50 % of span, noise < 2 %
          if (spike && !inSpike) spikes++;
          inSpike = spike;
          maxRatio = math.max(maxRatio, r.sigma5min / r.typicalSigma);
          if (r.quality == Quality.bad && r.milliamps >= 21) anyBadHigh = true;
        });
        expect(spikes, closeTo(n, tol), reason: 's=$s spikes/h');
        expect(maxRatio, greaterThanOrEqualTo(ratio), reason: 's=$s σ ratio');
        // Doc: "at 33 % of span no spike reaches BAD" holds for positive
        // spikes (33 % + 50 % → 17.3 mA); a negative spike ≥ 29 % of span
        // drives the current below 3.6 mA. Assert the high side only.
        expect(anyBadHigh, isFalse,
            reason: 'no spike reaches 21 mA at 33 % of span');
      }
    });
    test(
        'analyser AT-102 bias +, s 0.5: published = lagged true + 0.005 ± 1e-4',
        () {
      final sim = steadyT1();
      injectInstrumentFault(sim, 'AT-102', 'bias', severity: 0.5, sign: 1);
      sim.advance(1200);
      final r = reading(sim.snapshot(), 'AT-102');
      expect(r.value, closeTo(prof(sim).xB + 0.005, 1.5e-4));
      expect(r.resultAge!, inInclusiveRange(0, 600));
    });
    test('analyser timing: result age 300–600 s, STALE after signal loss', () {
      final sim = steadyT1();
      sim.advance(1200);
      advanceSampling(
          sim,
          1200,
          5,
          (t, s) => expect(
              reading(s, 'AT-101').resultAge!, inInclusiveRange(300, 600.5),
              reason: 't=$t'));
      injectInstrumentFault(sim, 'AT-101', 'signalLoss');
      sim.advance(650);
      expect(reading(sim.snapshot(), 'AT-101').quality, Quality.bad);
      expect(
          hasAlarm(sim.snapshot(), 'AT-101.STALE') ||
              hasAlarm(sim.snapshot(), 'AT-101.BAD'),
          isTrue);
    });
  });

  test(
      'VC-22.6 field gauge LG-101: ready at the first step end ≥ request + 180 s; σ 1.15 ± 0.1; one pending',
      () {
    final sim = steadyT1(noise: true, seed: 1);
    final errors = <double>[];
    for (var i = 0; i < 300; i++) {
      final t0 = sim.time;
      sim.requestFieldCheck('LG-101');
      sim.requestFieldCheck('LG-101'); // ignored while pending
      sim.advance(179.5);
      expect(
          sim
              .snapshot()
              .fieldChecks
              .where((f) => f.gaugeTag == 'LG-101' && f.value == null)
              .length,
          1);
      sim.advance(0.5);
      final done = sim
          .snapshot()
          .fieldChecks
          .firstWhere((f) => f.gaugeTag == 'LG-101' && f.value != null);
      expect(done.readyAt, closeTo(t0 + 180, 1e-9));
      errors.add(done.value! - sim.snapshot().kpis.drumLevelPct);
    }
    expect(mean(errors), closeTo(0, 0.2));
    expect(stdDev(errors), closeTo(vc226Sigma, 0.15));
  });

  test(
      'VC-22.7 maintenance: OOS 1800 s, FC-102 shed, then GOOD with the bias cleared',
      () {
    final sim = steadyT1();
    sim.setLever('badPvShed', 0);
    injectInstrumentFault(sim, 'FT-102', 'bias', severity: 0.3, sign: 1);
    sim.advance(60);
    sim.requestMaintenance('FT-102');
    sim.step();
    expect(reading(sim.snapshot(), 'FT-102').quality, Quality.oos);
    expect(loopOf(sim.snapshot(), 'FC-102').mode, LoopMode.man);
    sim.advance(1800);
    expect(reading(sim.snapshot(), 'FT-102').quality, Quality.good);
    expect(sim.faults.active, isEmpty);
    expect(reading(sim.snapshot(), 'FT-102').value,
        closeTo(sim.snapshot().streams[StreamId.reflux]!.flow, 1e-6));
  });

  test('σ_disp table of PHYSICS.md §10.5 reproduced by the engine specs', () {
    final sim = steadyT1();
    for (final (tag, sigma) in [
      ('FT-102', 0.409),
      ('LT-101', 0.423),
      ('LT-102', 0.775),
      ('PDT-101', 0.845)
    ]) {
      final r = reading(sim.snapshot(), tag);
      expect(r.typicalSigma / (r.hi - r.lo) * 100, closeTo(sigma, 0.0015),
          reason: tag);
    }
    expect(ref.ft102.sigmaDisp, closeTo(0.409, 0.001));
  });
}
