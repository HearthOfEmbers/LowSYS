// §H H9/H10 detectability with noise ON, plant view, minimum severity,
// both signs, several seeds. Reports the detection margins (time to the
// first `fail`, max |r|/band, signal-look ratios) so the "winnable on a
// phone" claim is quantified, not just asserted.
//
// M3 scope: Tier-1-feasible rows (FT/LT/valve faults, C1/C3/C4/C5, signal
// look). Rows needing Tier 2 (C3a/C3b/C6/C7, TI/PT faults) are skipped until
// M4 and marked so.
library;

import 'dart:math' as math;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';

const seeds = [1, 2, 3];
const tier2Available = false; // flip when M4 lands

/// Drill-like run: B-T Tier 1, full hydraulics, steady, noise on, plant view.
Simulator drillRun(int seed,
    {required void Function(Simulator) inject,
    double onset = 600,
    double event = 2700,
    void Function(Simulator)? eventAction}) {
  final sim = newSim(btFull(), options: SimOptions(seed: seed));
  runSteady(sim);
  sim.setLever('noise', 1);
  sim.setLever('view', 1);
  sim.setLever('badPvShed', 0);
  sim.setCheckWindow(600);
  sim.advance(onset);
  inject(sim);
  return sim;
}

class Evidence {
  double? tFail;
  double maxRatio = 0;
  double minLook = double.infinity, maxLook = 0;
  int evals = 0, fails = 0;
}

/// Runs [seconds] from the injection, applying the feed event at 2700 s of
/// scenario time, collecting the margin of [checkId] and the look of [tag].
Evidence collect(Simulator sim, double seconds,
    {String? checkId,
    String? tag,
    double onset = 600,
    void Function(Simulator)? eventAction}) {
  final e = Evidence();
  var eventDone = false;
  advanceSampling(sim, seconds, 5, (t, s) {
    final scenarioT = t + onset;
    if (!eventDone && scenarioT >= 2700 && eventAction != null) {
      eventAction(sim);
      eventDone = true;
    }
    if (checkId != null) {
      final c = checkOf(s, checkId);
      if (c != null &&
          c.status != CheckStatus.notAvailable &&
          c.status != CheckStatus.transient) {
        e.evals++;
        final ratio = c.residual.abs() / c.band;
        e.maxRatio = math.max(e.maxRatio, ratio);
        if (c.status == CheckStatus.fail) {
          e.fails++;
          e.tFail ??= t;
        }
      }
    }
    if (tag != null) {
      final r = signalLookRatio(s, tag);
      if (r.isFinite) {
        e.minLook = math.min(e.minLook, r);
        e.maxLook = math.max(e.maxLook, r);
      }
    }
  });
  return e;
}

/// H9 feed event, ratio-preserving (DEVIATIONS "Spec decisions 2026-10-12"
/// #4, ENGINE_API §11.6): FC-101 +5, FC-102 +5 kmol/h and FC-103 +5 %
/// (+65 kW in Tier 2; the Tier-1 stand-in is +7.5 kmol/h of boilup). In
/// Tier 1 FC-103 is in AUTO, so the CAS-slave `delta` rule (ENGINE_API
/// §11.1) is not exercised here: rerun on the Tier-2 drill once M4 lands.
void feedEvent(Simulator sim) {
  sim.control.setSp('FC-101', sim.control.loop('FC-101').sp + 5 * kmolh);
  sim.control.setSp('FC-102', sim.control.loop('FC-102').sp + 5 * kmolh);
  sim.control.setSp('FC-103', sim.control.loop('FC-103').sp + 7.5 * kmolh);
}

void planningEvent(Simulator sim) {
  sim.control.setSp('FC-102', sim.control.loop('FC-102').sp + 5 * kmolh);
  sim.control.setSp('FC-103',
      sim.control.loop('FC-103').sp + 7.5 * kmolh); // T1 stand-in for +65 kW
}

/// The drills' off-spec predicate (H9/H10 JSON `offSpec`): true x_D more
/// than 0.01 below its start value or true x_B more than 0.01 above it,
/// held for 120 s (a single false evaluation resets the hold).
class OffSpec {
  final double xd0, xb0;
  double? _since, metAt;
  double minDxD = 0, maxDxB = 0;
  OffSpec(Simulator sim)
      : xd0 = TrueView(sim).read('kpi.xD'),
        xb0 = TrueView(sim).read('kpi.xB');
  void sample(Simulator sim, double t) {
    final v = TrueView(sim);
    final dxd = v.read('kpi.xD') - xd0, dxb = v.read('kpi.xB') - xb0;
    minDxD = math.min(minDxD, dxd);
    maxDxB = math.max(maxDxB, dxb);
    if (!(dxd < -0.01 || dxb > 0.01)) {
      _since = null;
      return;
    }
    _since ??= t;
    if (metAt == null && t - _since! >= 120) metAt = t;
  }
}

/// Tracks the first time at which a condition has held for [hold] s.
class Held {
  final double hold;
  double? _since, metAt;
  Held(this.hold);
  void sample(bool on, double t) {
    if (!on) {
      _since = null;
      return;
    }
    _since ??= t;
    if (metAt == null && t - _since! >= hold) metAt = t;
  }
}

bool checkAtLeastCheck(SimSnapshot s, String id) {
  final st = checkOf(s, id)?.status;
  return st == CheckStatus.check || st == CheckStatus.fail;
}

void main() {
  final report =
      StringBuffer('H9/H10 detection margins (Tier 1, noise on, plant view)\n');
  tearDownAll(() => print(report));

  /// H9.0 / H10.0: healthy 2-h drill with the drill's scripted event at
  /// 2700 s of drill time. No check `fail`, no BAD alarm, the off-spec
  /// predicate never met, and every signal look in 0.5–2 except in the
  /// 300 s after the event (spec decision 2026-10-12 #3: the 5-min σ then
  /// contains the step). FT-104/FT-105 use the level-loop typical σ of
  /// PHYSICS.md §10.5, so every tag is held to 0.5–2.
  void healthy(String id, void Function(Simulator) event,
      {bool assertOffSpec = true}) {
    for (final seed in seeds) {
      final sim = drillRun(seed, inject: (_) {});
      final off = OffSpec(sim);
      double? tEvent;
      var lookWorst = 1.0;
      String? lookTag;
      advanceSampling(sim, 6600, 5, (t, s) {
        // drill time = t + 600; the callback's snapshot predates the event
        if (tEvent == null && t + 600 >= 2700) {
          event(sim);
          tEvent = t;
        }
        for (final c in s.crossChecks) {
          expect(c.status, isNot(CheckStatus.fail),
              reason: '$id seed $seed ${c.id} at $t');
        }
        expect(s.alarms.where((a) => a.id.endsWith('.BAD')), isEmpty,
            reason: '$id seed $seed BAD at $t');
        off.sample(sim, t);
        final afterEvent = tEvent != null && t - tEvent! <= 300;
        if (afterEvent) return;
        for (final r in s.instruments) {
          if (r.type == InstrumentType.at || r.sigma5min.isNaN) continue;
          final look = r.sigma5min / r.typicalSigma;
          if ((look - 1).abs() > (lookWorst - 1).abs()) {
            lookWorst = look;
            lookTag = '${r.tag} at $t';
          }
          expect(look, inInclusiveRange(0.5, 2.0),
              reason: '$id seed $seed ${r.tag} look at $t');
        }
      });
      report.writeln(
          '$id seed $seed: off-spec met at ${off.metAt} (min ΔxD ${off.minDxD.toStringAsFixed(4)}, max ΔxB ${off.maxDxB.toStringAsFixed(4)}), '
          'worst look ${lookWorst.toStringAsFixed(2)} ($lookTag)');
      if (assertOffSpec) {
        expect(off.metAt, isNull,
            reason: '$id seed $seed: healthy run met the off-spec predicate '
                '(min ΔxD ${off.minDxD}, max ΔxB ${off.maxDxB})');
      }
    }
  }

  test(
      'H9.0 healthy run, ratio-preserving feed event: no fail, no BAD, never off-spec, signal looks 0.5–2',
      () => healthy('H9.0', feedEvent));

  // FINDING (spec, OPEN_ITEMS 2026-10-12): the planning event (reflux +5
  // kmol/h, duty +5 %) is not D-neutral under LV control: D = V1 − L0 rises
  // by ≈ 2.5 kmol/h, so x_D falls by ≈ 0.034 and the healthy run meets the
  // off-spec predicate ≈ 22 min after the event (all three seeds). A
  // D-neutral event (reflux +7.5 with the duty +65 kW) keeps both products
  // on spec. Off-spec is reported, not asserted, until the lead decides.
  test(
      'H10.0 healthy run, planning event: no fail, no BAD, signal looks 0.5–2 (off-spec reported)',
      () => healthy('H10.0', planningEvent, assertOffSpec: false));

  group('H9 (Tier 1 rows)', () {
    test(
        'H9.1 FT-102 bias s 0.4 ±: C3 and C4:FV-102 fail within 10 min; C1 ok; off-spec within 2 h',
        () {
      for (final seed in seeds) {
        for (final sign in [1, -1]) {
          final sim = drillRun(seed,
              inject: (s) => injectInstrumentFault(s, 'FT-102', 'bias',
                  severity: 0.4, sign: sign));
          final off = OffSpec(sim);
          final e3 = Evidence(), e4 = Evidence(), e1 = Evidence();
          var eventDone = false;
          advanceSampling(sim, 6600, 5, (t, s) {
            if (!eventDone && t + 600 >= 2700) {
              feedEvent(sim);
              eventDone = true;
            }
            for (final (id, ev) in [
              ('C3', e3),
              ('C4:FV-102', e4),
              ('C1', e1)
            ]) {
              final c = checkOf(s, id)!;
              ev.evals++;
              ev.maxRatio = math.max(ev.maxRatio, c.residual.abs() / c.band);
              if (c.status == CheckStatus.fail) {
                ev.fails++;
                ev.tFail ??= t;
              }
            }
            if (off.metAt == null) off.sample(sim, t);
          });
          final tOff = off.metAt;
          report.writeln(
              'H9.1 seed $seed sign $sign: C3 fail at ${e3.tFail} s (max ${e3.maxRatio.toStringAsFixed(1)} band), '
              'C4 at ${e4.tFail} (max ${e4.maxRatio.toStringAsFixed(1)}), C1 max ${e1.maxRatio.toStringAsFixed(2)}, off-spec at $tOff');
          expect(e3.tFail, isNotNull, reason: 'seed $seed sign $sign C3');
          expect(e3.tFail!, lessThanOrEqualTo(600));
          expect(e4.tFail, isNotNull);
          expect(e4.tFail!, lessThanOrEqualTo(600));
          expect(e1.fails, 0, reason: 'C1 must stay ok');
          expect(tOff, isNotNull, reason: 'off-spec must be reachable');
        }
      }
    });

    // Minimum severity raised 0.9 → 1.0 (spec decision 2026-10-12 #2): at
    // 0.9 the oscillating true reflux averaged out in the window and C3
    // never failed. PENDING RERUN on the Tier-2 drill (C3/C3a) once M4 and
    // the [1.0, 1.0] scenario JSON land.
    test(
        'H9.2 FT-102 plugged s 1.0: signal look ≤ 0.2 within 15 min; C3 fail within 30 min',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectInstrumentFault(s, 'FT-102', 'plugged',
                severity: 1.0, ramp: 300));
        double? tLook;
        final e = Evidence();
        advanceSampling(sim, 1800, 5, (t, s) {
          final look = signalLookRatio(s, 'FT-102');
          tLook ??= look <= 0.2 ? t : null;
          e.minLook = math.min(e.minLook, look);
          final c = checkOf(s, 'C3')!;
          e.maxRatio = math.max(e.maxRatio, c.residual.abs() / c.band);
          if (c.status == CheckStatus.fail) e.tFail ??= t;
        });
        report.writeln(
            'H9.2 seed $seed: look ≤ 0.2 at $tLook s (min ${e.minLook.toStringAsFixed(3)}), C3 fail at ${e.tFail} (max ${e.maxRatio.toStringAsFixed(1)})');
        expect(tLook, isNotNull);
        expect(tLook!, lessThanOrEqualTo(900));
        expect(e.tFail, isNotNull, reason: 'seed $seed C3 fail');
        expect(e.tFail!, lessThanOrEqualTo(1800));
      }
    });

    test(
        'H9.3 FT-101 drift s 0.6 ±: C1 fail within 20 min (+10 min); C4:FV-101 within 40 min',
        () {
      for (final seed in seeds) {
        for (final sign in [1, -1]) {
          final sim = drillRun(seed,
              inject: (s) => injectInstrumentFault(s, 'FT-101', 'drift',
                  severity: 0.6, sign: sign));
          double? t1, t4;
          advanceSampling(sim, 2400, 5, (t, s) {
            t1 ??= checkFails(s, 'C1') ? t : null;
            t4 ??= checkFails(s, 'C4:FV-101') ? t : null;
          });
          report.writeln(
              'H9.3 seed $seed sign $sign: C1 fail at $t1 s, C4:FV-101 at $t4 s');
          expect(t1, isNotNull);
          expect(t1!, lessThanOrEqualTo(1800));
          // Spec decision 2026-10-12 #1: C4 sees the 600-s window mean of
          // the ramp and crosses the fail line at ≈ 36 min, so 40 min,
          // counted from t₀ (the drift rule's t₀ + 10 min would allow 50).
          expect(t4, isNotNull, reason: 'C4:FV-101 within 40 min');
          expect(t4!, lessThanOrEqualTo(2400));
        }
      }
    });

    test(
        'H9.5 LT-101 bias s 0.8 ±: C5:drum fail within 10 min; LG-101 vs LT-101 ≥ 5 % after 15 min',
        () {
      for (final seed in seeds) {
        for (final sign in [1, -1]) {
          final sim = drillRun(seed,
              inject: (s) => injectInstrumentFault(s, 'LT-101', 'bias',
                  severity: 0.8, sign: sign));
          final e = collect(sim, 600, checkId: 'C5:drum');
          sim.advance(300);
          sim.requestFieldCheck('LG-101');
          sim.advance(181);
          final lg = sim
              .snapshot()
              .fieldChecks
              .firstWhere((f) => f.gaugeTag == 'LG-101' && f.value != null)
              .value!;
          final diff = (reading(sim.snapshot(), 'LT-101').value - lg).abs();
          report.writeln(
              'H9.5 seed $seed sign $sign: C5 fail at ${e.tFail} s (max ${e.maxRatio.toStringAsFixed(1)}), LG−LT ${diff.toStringAsFixed(1)} %');
          expect(e.tFail, isNotNull);
          expect(e.tFail!, lessThanOrEqualTo(600));
          expect(diff, greaterThanOrEqualTo(5));
        }
      }
    });

    test(
        'H9.6 LT-102 signal loss low: BAD at once; with no action true sump > 95 % within 30 min',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectInstrumentFault(s, 'LT-102', 'signalLossLow'));
        sim.step();
        expect(hasAlarm(sim.snapshot(), 'LT-102.BAD'), isTrue);
        final tHigh = firstTime(
            sim, 1800, (s) => TrueView(sim).read('sump.levelPct') > 95,
            sample: 30);
        report.writeln('H9.6 seed $seed: true sump > 95 % at $tHigh s');
        expect(tHigh, isNotNull);
      }
    });

    test(
        'H9.7 LT-102 stuck: σ = 0 within 5 min; C5:sump fail within 20 min after the feed event',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectInstrumentFault(s, 'LT-102', 'stuck'));
        final tSigma = firstTime(
            sim, 300, (s) => reading(s, 'LT-102').sigma5min == 0,
            sample: 5);
        expect(tSigma, isNotNull);
        sim.advance(2100 - 300); // to the feed event at 2700 s drill time
        // ratio-preserving event (decision #4): the sump now gains only
        // F + L0 − V = +2.5 kmol/h (was +5). PENDING RERUN on the Tier-2
        // drill (CAS-slave delta rule) once M4 lands.
        feedEvent(sim);
        final e = collect(sim, 1200, checkId: 'C5:sump');
        report.writeln(
            'H9.7 seed $seed: σ=0 at $tSigma s, C5:sump fail ${e.tFail} s after the event (max ${e.maxRatio.toStringAsFixed(1)})');
        expect(e.tFail, isNotNull, reason: 'seed $seed C5:sump fail');
      }
    });

    // VALIDATION.md H9.12 (2026-10-12, supersedes spec decision #5's 20 min):
    // C1 or C3 at `check` or worse, held ≥ 60 s, within 30 min after the
    // feed event; σ = 0 stays the key evidence. The event moves the true D
    // by ≈ 2.5 kmol/h (above the C1/C3 bands, below the 2 × band fail line);
    // LC-101 (Ti 1800 s) needs ≈ 15 min for that, the 600-s window lags it,
    // and the frozen reading keeps the noise of the instant it froze. Engine
    // c4e1f17 seeds 1–3: 1225 / 555 / 1235 s (Tier-1 stand-in). The 20-min
    // result is reported for information.
    test(
        'H9.12 FT-104 stuck: σ = 0 within 5 min; C1 or C3 at check or worse, held ≥ 60 s, within 30 min after the feed event (20-min result reported)',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectInstrumentFault(s, 'FT-104', 'stuck'));
        final tSigma = firstTime(
            sim, 300, (s) => reading(s, 'FT-104').sigma5min == 0,
            sample: 5);
        expect(tSigma, isNotNull);
        sim.advance(2100 - 300); // to the feed event at 2700 s drill time
        feedEvent(sim);
        final held = Held(60);
        double? tFail;
        advanceSampling(sim, 1800, 5, (t, s) {
          held.sample(
              checkAtLeastCheck(s, 'C1') || checkAtLeastCheck(s, 'C3'), t);
          tFail ??= checkFails(s, 'C1') || checkFails(s, 'C3') ? t : null;
        });
        report.writeln(
            'H9.12 seed $seed: σ=0 at $tSigma s, C1/C3 ≥ check held 60 s at ${held.metAt} s '
            '(≤ 20 min, information: ${held.metAt != null && held.metAt! <= 1200}), fail at $tFail s after the event');
        expect(held.metAt, isNotNull,
            reason: 'seed $seed: C1 or C3 ≥ check for 60 s within 30 min');
      }
    });

    test(
        'H9.13 F07 ±0.08 benzene: AT-100 shows it within 15 min; no check fails in 2 h',
        () {
      for (final seed in seeds) {
        for (final sign in [1, -1]) {
          final sim = drillRun(seed,
              inject: (s) => s.faults.inject(FaultSpec(
                    type: FaultType.feedComposition,
                    location: FaultLocation.feed(0),
                    severity: 1.0,
                    onset: s.time,
                    ramp: 900,
                    params: {
                      'dz': {'benzene': 0.08},
                      'sign': sign
                    },
                    hidden: true,
                  )));
          final at0 = reading(sim.snapshot(), 'AT-100').value;
          double? tAt;
          var fails = 0;
          var eventDone = false;
          advanceSampling(sim, 6600, 5, (t, s) {
            if (!eventDone && t + 600 >= 2700) {
              feedEvent(sim);
              eventDone = true;
            }
            tAt ??= (reading(s, 'AT-100').value - at0).abs() >= 0.02 ? t : null;
            for (final c in s.crossChecks) {
              if (c.id != 'C2' && c.status == CheckStatus.fail) fails++;
            }
          });
          report.writeln(
              'H9.13 seed $seed sign $sign: AT-100 moved at $tAt s, check fails $fails');
          expect(tAt, isNotNull);
          expect(tAt!, lessThanOrEqualTo(900));
          expect(fails, 0);
        }
      }
    });

    test('H9.4/8/9/10/11 need Tier 2 (C3b, C6, C7, TI/PT)', () {},
        skip: !tier2Available ? 'Tier 2 arrives in M4' : null);
  });

  group('H10 (Tier 1 rows; FC-103 is the boilup loop, C3 stands in for C3b)',
      () {
    // Spec decision 2026-10-12 #6: C3/C3a and C1 never `fail`, and `ok` on
    // ≥ 85 % of evaluations (was 95 %; the planning event's transient puts
    // C3 in `check` for a few minutes). VC-23.3's FV-102 row keeps 95 %.
    // Runs the whole 2-h drill so that "never" means the drill.
    test(
        'H10.1 FV-102 stuck: C4:FV-102 fail within 20 min or 5 min after planning; C3/C1 never fail, ok ≥ 85 %; look normal',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectValveFault(s, 'FV-102', 'stuck'));
        final e4 = Evidence();
        var n = 0, ok = 0, c3Fails = 0, c1Fails = 0;
        var minLook = double.infinity, maxLook = 0.0;
        double? tEvent;
        advanceSampling(sim, 6600, 5, (t, s) {
          if (tEvent == null && t + 600 >= 2700) {
            planningEvent(sim);
            tEvent = t;
          }
          final c4 = checkOf(s, 'C4:FV-102')!;
          e4.maxRatio = math.max(e4.maxRatio, c4.residual.abs() / c4.band);
          if (c4.status == CheckStatus.fail) e4.tFail ??= t;
          n++;
          if (checkOk(s, 'C3') && checkOk(s, 'C1')) ok++;
          if (checkFails(s, 'C3')) c3Fails++;
          if (checkFails(s, 'C1')) c1Fails++;
          final look = signalLookRatio(s, 'FT-102');
          // the FT-102 look is judged outside the 300 s after the event
          // (decision #3): the FC-102 set point step lands in the 5-min σ
          if (tEvent == null || t - tEvent! > 300) {
            minLook = math.min(minLook, look);
            maxLook = math.max(maxLook, look);
          }
        });
        report.writeln(
            'H10.1 seed $seed: C4 fail at ${e4.tFail} s (event at $tEvent, max ${e4.maxRatio.toStringAsFixed(1)}), C3&C1 ok ${(100 * ok / n).toStringAsFixed(1)} %, fails C3 $c3Fails C1 $c1Fails, FT-102 look ${minLook.toStringAsFixed(2)}–${maxLook.toStringAsFixed(2)}');
        expect(e4.tFail, isNotNull);
        expect(e4.tFail! <= 1200 || e4.tFail! <= tEvent! + 300, isTrue);
        expect(c3Fails, 0, reason: 'seed $seed C3 never fails');
        expect(c1Fails, 0, reason: 'seed $seed C1 never fails');
        expect(ok / n, greaterThanOrEqualTo(0.85));
        expect(minLook, greaterThanOrEqualTo(0.5));
        expect(maxLook, lessThanOrEqualTo(2.0));
      }
    });

    test('H10.2 FV-103 stuck: C4:FV-103 fail; C3 ok ≥ 95 %; FT-103 look normal',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectValveFault(s, 'FV-103', 'stuck'));
        var okC3 = 0, n = 0;
        double? t4, tEvent;
        var eventDone = false;
        advanceSampling(sim, 3000, 5, (t, s) {
          if (!eventDone && t + 600 >= 2700) {
            planningEvent(sim);
            eventDone = true;
            tEvent = t;
          }
          t4 ??= checkFails(s, 'C4:FV-103') ? t : null;
          n++;
          if (checkOk(s, 'C3')) okC3++;
        });
        report.writeln(
            'H10.2 seed $seed: C4:FV-103 fail at $t4 s (event $tEvent), C3 ok ${(100 * okC3 / n).toStringAsFixed(1)} %');
        expect(t4, isNotNull);
        expect(t4! <= 1200 || t4! <= tEvent! + 300, isTrue);
        expect(okC3 / n, greaterThanOrEqualTo(0.95));
      }
    });

    // s = 1.0 as H9.2 (decision #2). PENDING RERUN on the Tier-2 drill.
    test(
        'H10.4 FT-102 plugged s 1.0: look ≤ 0.2 within 15 min; C3 fail within 30 min (separates it from H10.1)',
        () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectInstrumentFault(s, 'FT-102', 'plugged',
                severity: 1.0, ramp: 300));
        double? tLook;
        final e = Evidence();
        advanceSampling(sim, 1800, 5, (t, s) {
          final look = signalLookRatio(s, 'FT-102');
          tLook ??= look <= 0.2 ? t : null;
          e.minLook = math.min(e.minLook, look);
          final c = checkOf(s, 'C3')!;
          e.maxRatio = math.max(e.maxRatio, c.residual.abs() / c.band);
          if (c.status == CheckStatus.fail) e.tFail ??= t;
        });
        report.writeln(
            'H10.4 seed $seed: look ≤ 0.2 at $tLook s (min ${e.minLook.toStringAsFixed(3)}), C3 fail at ${e.tFail} s (max ${e.maxRatio.toStringAsFixed(1)})');
        expect(tLook, isNotNull);
        expect(tLook!, lessThanOrEqualTo(900));
        expect(e.tFail, isNotNull, reason: 'seed $seed C3 fail');
        expect(e.tFail!, lessThanOrEqualTo(1800));
      }
    });

    test(
        'H10.5 FT-103 drift s 0.6 ±: C3 (T1 stand-in for C3b) fail within 25 min; C4:FV-103 within 40 min',
        () {
      for (final seed in seeds) {
        for (final sign in [1, -1]) {
          final sim = drillRun(seed,
              inject: (s) => injectInstrumentFault(s, 'FT-103', 'drift',
                  severity: 0.6, sign: sign));
          double? t3, t4;
          var max3 = 0.0;
          advanceSampling(sim, 2400, 5, (t, s) {
            final c = checkOf(s, 'C3')!;
            max3 = math.max(max3, c.residual.abs() / c.band);
            t3 ??= c.status == CheckStatus.fail ? t : null;
            t4 ??= checkFails(s, 'C4:FV-103') ? t : null;
          });
          report.writeln(
              'H10.5 seed $seed sign $sign: C3 fail at $t3 s (max ${max3.toStringAsFixed(1)}), C4:FV-103 at $t4 s');
          expect(t3, isNotNull);
          expect(t3!, lessThanOrEqualTo(1500));
          // Spec decision 2026-10-12 #1: C4 crosses the fail line at ≈ 36
          // min (600-s window mean of the ramp), so 40 min from t₀.
          expect(t4, isNotNull, reason: 'C4:FV-103 within 40 min');
          expect(t4!, lessThanOrEqualTo(2400));
        }
      }
    });

    test('H10.6 FT-103 plugged s 0.9: look ≤ 0.2 within 15 min', () {
      for (final seed in seeds) {
        final sim = drillRun(seed,
            inject: (s) => injectInstrumentFault(s, 'FT-103', 'plugged',
                severity: 0.9, ramp: 300));
        final tLook = firstTime(
            sim, 900, (s) => signalLookRatio(s, 'FT-103') <= 0.2,
            sample: 5);
        report.writeln('H10.6 seed $seed: look ≤ 0.2 at $tLook s');
        expect(tLook, isNotNull);
      }
    });

    test('H10.7 F07 ±0.10: AT-100 within 15 min; no C4 or C3 fail in 2 h', () {
      for (final seed in seeds) {
        for (final sign in [1, -1]) {
          final sim = drillRun(seed,
              inject: (s) => s.faults.inject(FaultSpec(
                    type: FaultType.feedComposition,
                    location: FaultLocation.feed(0),
                    severity: 1.0,
                    onset: s.time,
                    ramp: 600,
                    params: {
                      'dz': {'benzene': 0.10},
                      'sign': sign
                    },
                    hidden: true,
                  )));
          final at0 = reading(sim.snapshot(), 'AT-100').value;
          double? tAt;
          var fails = 0;
          var eventDone = false;
          advanceSampling(sim, 6600, 5, (t, s) {
            if (!eventDone && t + 600 >= 2700) {
              planningEvent(sim);
              eventDone = true;
            }
            tAt ??= (reading(s, 'AT-100').value - at0).abs() >= 0.02 ? t : null;
            for (final c in s.crossChecks) {
              if ((c.id.startsWith('C4') || c.id == 'C3') &&
                  c.status == CheckStatus.fail) fails++;
            }
          });
          report.writeln(
              'H10.7 seed $seed sign $sign: AT-100 moved at $tAt s, C3/C4 fails $fails');
          expect(tAt, isNotNull);
          expect(tAt!, lessThanOrEqualTo(900));
          expect(fails, 0);
        }
      }
    });
  });
}
