// Standalone driver for the M3 reference numbers: PID (VC-16.1–16.3),
// the fast-layer flow loop (VC-16.4, 16.9), PRNG vectors (VC-20.3),
// instrument pipeline and noise (VC-22), cross-check margins (VC-23,
// ENGINE_API.md §11.5), alarm chatter (VC-25.1) and scoring (VC-26.3).
//   dart run packages/lowsys_engine/test/validation/reference/reference_main_m3.dart
// No engine imports. Exit code 1 if a comparison fails.
library;

import 'dart:io';
import 'dart:math' as math;

import 'alarm_reference.dart';
import 'cross_check_reference.dart';
import 'instrument_reference.dart';
import 'pid_reference.dart';
import 'prng_reference.dart';
import 'validation_expectations_m3.dart';

var _fail = 0, _pass = 0;
void check(String label, num got, num expected, num tol, {bool rel = false}) {
  final t = rel ? tol * expected.abs() : tol;
  final ok = (got - expected).abs() <= t;
  ok ? _pass++ : _fail++;
  stdout.writeln(
      '${ok ? 'PASS' : 'FAIL'}  $label: got ${got is int ? got : (got as double).toStringAsPrecision(7)} '
      'expected ${expected is int ? expected : (expected as double).toStringAsPrecision(7)} (tol ${rel ? '${100 * tol} %' : tol})');
}

void section(String s) => stdout.writeln('\n=== $s ===');

void main() {
  pid();
  flowLoop();
  prng();
  instruments();
  noiseStats();
  signatures();
  crossChecks();
  alarms();
  scoring();
  stdout.writeln('\n$_pass passed, $_fail failed');
  if (_fail > 0) exitCode = 1;
}

// ------------------------------------------------------------------ VC-16.1–3
void pid() {
  section('VC-16.1 PID arithmetic (Kc 2, Ti 10, h 1, direct)');
  var p = RefPid(kc: 2, ti: 10, action: RefAction.direct, sp: 50, op: 50);
  p.execute(50, 1); // establish e_{k-1} = 0 at PV = SP
  check('OP after 1 execution at PV 51', p.execute(51, 1), vc161.op1, 1e-12);
  for (var k = 2; k <= 10; k++) {
    p.execute(51, 1);
  }
  check('OP after 10', p.op, vc161.op10, 1e-12);
  check('OP after PV back to 50', p.execute(50, 1), vc161.opBack, 1e-12);

  // SP step with spKick true
  p = RefPid(
      kc: 2, ti: 10, action: RefAction.direct, sp: 50, op: 50, spKick: true);
  p.execute(50, 1);
  p.setSp(49);
  check('SP step, spKick: OP after 1', p.execute(50, 1), vc161.op1, 1e-12);
  for (var k = 2; k <= 10; k++) {
    p.execute(50, 1);
  }
  check('SP step, spKick: OP after 10', p.op, vc161.op10, 1e-12);
  p = RefPid(
      kc: 2, ti: 10, action: RefAction.direct, sp: 50, op: 50, spKick: false);
  p.execute(50, 1);
  p.setSp(49);
  check('SP step, re-based: OP after 1', p.execute(50, 1), vc161.rebasedOp1,
      1e-12);
  for (var k = 2; k <= 10; k++) {
    p.execute(50, 1);
  }
  check('SP step, re-based: OP after 10', p.op, vc161.rebasedOp10, 1e-12);

  section('VC-16.1b derivative sign (Kc 1, Ti ∞, Td 8, PV = 50 + k)');
  for (final (act, exp) in [
    (RefAction.direct, vc161bDirect),
    (RefAction.reverse, vc161bReverse)
  ]) {
    final d =
        RefPid(kc: 1, ti: double.infinity, td: 8, action: act, sp: 50, op: 50);
    d.execute(50, 1); // k = 0 initialises the filter at 50
    for (var k = 1; k <= 6; k++) {
      check('${act.name} execution $k', d.execute(50 + k.toDouble(), 1),
          exp[k - 1], 1e-9);
    }
  }

  section('VC-16.2 anti-windup');
  final a = RefPid(kc: 2, ti: 10, action: RefAction.direct, sp: 50, op: 50);
  a.execute(50, 1);
  check('OP after 1 at PV 55', a.execute(55, 1), vc162.op1, 1e-12);
  for (var k = 2; k <= 39; k++) {
    a.execute(55, 1);
  }
  check('OP after 39', a.op, vc162.op39, 1e-12);
  a.execute(55, 1);
  check('OP after 40', a.op, vc162.op40, 1e-12);
  for (var k = 41; k <= 100; k++) {
    a.execute(55, 1);
  }
  check('OP after 100 (clamped)', a.op, 100, 1e-12);
  check('OP first execution after PV 49.5', a.execute(49.5, 1),
      vc162.opAfterDrop1, 1e-9);
  check('OP second', a.execute(49.5, 1), vc162.opAfterDrop2, 1e-9);

  section('VC-16.3 bumpless transfer');
  final b = RefPid(
      kc: 2,
      ti: 10,
      action: RefAction.direct,
      sp: 50,
      op: 37.2,
      mode: RefMode.man);
  b.execute(62, 1);
  b.toAuto(62);
  check('SP tracked PV', b.sp, 62, 1e-12);
  var maxD = 0.0;
  for (var k = 0; k < 100; k++) {
    final before = b.op;
    b.execute(62, 1);
    maxD = math.max(maxD, (b.op - before).abs());
  }
  check('max |ΔOP| over 100 executions', maxD, 0, 1e-9);
}

// ------------------------------------------------------------------ VC-16.4
RefFlowLoop _fc102({double delta = 0.1, bool noise = false, int seed = 1}) {
  final ft = Transmitter(ft102, 100, noise: noise, seed: seed);
  final pid = RefPid(
      kc: 0.6,
      ti: 2.0,
      action: RefAction.reverse,
      lo: 0,
      hi: 300,
      sp: 100,
      op: 100 / 3);
  final v = RefValve(300, 100 / 3);
  return RefFlowLoop(valve: v, ft: ft, pid: pid, delta: delta, flow: 100);
}

void flowLoop() {
  section('VC-16.4 flow loop FC-102 (Kc 0.6, Ti 2 s, δ 0.1 s), SP 100 → 110');
  final loop = _fc102();
  // settle at 100 (noise off: exact)
  for (var k = 0; k < 100; k++) {
    loop.subStep();
  }
  loop.pid.setSp(110);
  final want = {
    for (var i = 0; i < vc164Times.length; i++) vc164Times[i]: vc164TrueFlow[i]
  };
  double? t63True, t63Meas, tWithin1, opAt1;
  var overshoot = 0.0;
  var tt = 0.0;
  double? pv3;
  for (var k = 1; k <= 300; k++) {
    loop.subStep();
    tt = k * 0.1;
    final key = want.keys.where((x) => (x - tt).abs() < 1e-9);
    if (key.isNotEmpty)
      check('true flow at $tt s', loop.flow, want[key.first]!, 0.01);
    if ((tt - 3).abs() < 1e-9) pv3 = loop.ft.vMeas;
    if ((tt - 1).abs() < 1e-9) opAt1 = loop.pid.op;
    t63True ??= loop.flow - 100 >= 6.3 ? tt : null;
    t63Meas ??= loop.ft.vMeas - 100 >= 6.3 ? tt : null;
    tWithin1 ??= (loop.flow - 110).abs() <= 0.1 ? tt : null;
    overshoot = math.max(overshoot, loop.flow - 110);
  }
  check('measured PV at 3 s', pv3!, vc164.pv3s, 0.01);
  check('OP at 1 s (%)', opAt1!, vc164.op1s, 0.01);
  check('OP final (%)', loop.pid.op, vc164.opFinal, 0.01);
  check('t63 true flow (s)', t63True!, vc164.t63True, 0.1);
  check('t63 measured (s)', t63Meas!, vc164.t63Meas, 0.1);
  check('within 1 % of the step (s)', tWithin1!, vc164.within1pct, 0.2);
  check('overshoot (kmol/h) ≤ 0.005', overshoot, 0, 0.005);
  // main-step means at dt 0.5 and 2 s, bit-identical sub-steps
  final l05 = _fc102();
  final l2 = _fc102();
  for (var k = 0; k < 100; k++) {
    l05.subStep();
    l2.subStep();
  }
  l05.pid.setSp(110);
  l2.pid.setSp(110);
  for (var i = 0; i < vc164MeansDt05.length; i++) {
    check('mean flow dt 0.5 step ${i + 1}', l05.mainStep(0.5),
        vc164MeansDt05[i], 0.01);
  }
  for (var i = 0; i < vc164MeansDt2.length; i++) {
    check('mean flow dt 2 step ${i + 1}', l2.mainStep(2.0), vc164MeansDt2[i],
        0.01);
  }
  for (var i = 0; i < 8; i++) {
    l05.mainStep(0.5); // bring dt 0.5 to the same 8 s
  }
  check('dt 0.5 and dt 2 end at the same sub-step state (bit-identical)',
      l05.flow, l2.flow, 0);
  // Tier 2 duty loop: process gain 0.722
  {
    final ft =
        Transmitter(const InstSpec('FT-103', 0, 3000, 0.5, 0.5, 1, 0.02), 1300);
    final pid = RefPid(
        kc: 0.6,
        ti: 2.0,
        action: RefAction.reverse,
        lo: 0,
        hi: 3000,
        sp: 1300,
        op: 60);
    final v = RefValve(0.722 * 3000, 60);
    final d = RefFlowLoop(valve: v, ft: ft, pid: pid, flow: 1300);
    for (var k = 0; k < 200; k++) {
      d.subStep();
    }
    d.pid.setSp(1430);
    double? t63;
    for (var k = 1; k <= 300; k++) {
      d.subStep();
      t63 ??= d.flow - 1300 >= 0.63 * 130 ? k * 0.1 : null;
    }
    check('Tier 2 duty loop t63 (s)', t63!, 4.2, 0.2);
  }

  section('VC-16.9 valve faults');
  {
    final l = _fc102();
    for (var k = 0; k < 100; k++) {
      l.subStep();
    }
    l.valve.stuck = true;
    final op0 = l.pid.op;
    l.pid.setSp(110);
    l.subStep();
    check('(a) stuck: P kick at the first sub-step (% OP)', l.pid.op - op0,
        vc169.stuckKick, 0.05);
    double? tSat;
    var flow0 = l.flow;
    for (var k = 2; k <= 1000; k++) {
      l.subStep();
      tSat ??= l.pid.op >= 100 - 1e-9 ? k * 0.1 : null;
    }
    check('(a) stuck: true flow unchanged', l.flow, flow0, 1e-9);
    check('(a) stuck: OP reaches 100 % at (s)', tSat!, vc169.stuckSatTime, 0.5);
    // ramp rate: Kc·(h/Ti)·e per sub-step = 0.6 × 0.05 × 3.333 %span = 0.1 %/0.1 s = 1 %/s
    check('(a) stuck: integral ramp (%/s)',
        0.6 * (0.1 / 2.0) * (10 / 300 * 100) / 0.1, vc169.stuckRate, 1e-9);
    final f = _fc102();
    for (var k = 0; k < 100; k++) {
      f.subStep();
    }
    double? t63;
    for (var k = 1; k <= 200; k++) {
      f.valve.command = 100; // failOpen overrides the loop each sub-step
      f.subStep();
      f.valve.command = 100;
      t63 ??= f.flow - 100 >= 0.63 * 200 ? k * 0.1 : null;
    }
    check('(b) failOpen: t63 to 300 kmol/h (s)', t63!, vc169.failOpenT63, 0.1);
  }
}

// ------------------------------------------------------------------ VC-20.3
void prng() {
  section('VC-20.3 PRNG vectors (xoshiro128**, FNV-1a-32 seeding)');
  check('FNV-1a-32("")', fnv1a32(''), vc203.fnvEmpty, 0);
  check('FNV-1a-32("a")', fnv1a32('a'), vc203.fnvA, 0);
  check('FNV-1a-32("FT-102")', fnv1a32('FT-102'), vc203.fnvFt102, 0);
  final g = Xoshiro128ss.stream(1, 'FT-102');
  for (var i = 0; i < 4; i++) {
    check('next32 #${i + 1}', g.next32(), vc203.next32[i], 0);
  }
  final g2 = Xoshiro128ss.stream(1, 'FT-102');
  check('uniform()', g2.uniform(), vc203.uniform, 1e-15);
  check('normal() #1', g2.normal(), vc203.normal1, 1e-15);
  check('normal() #2', g2.normal(), vc203.normal2, 1e-15);
  final d = Xoshiro128ss.stream(42, 'drill');
  check('drill uniform #1', d.uniform(), vc203.drillUniform1, 1e-15);
  check('drill uniform #2', d.uniform(), vc203.drillUniform2, 1e-15);
  // reference-algorithm cross-check, worked by hand from Vigna's C code with
  // state {1, 2, 3, 4}: result = rotl(2·5, 7)·9 = 11520; the update leaves
  // s1 = 0 so the next result is 0; then s1 = 1029 → rotl(5145, 7)·9 = 5927040.
  final c = Xoshiro128ss.raw(1, 2, 3, 4);
  check('canonical state {1,2,3,4} output #1', c.next32(), 11520, 0);
  check('canonical output #2', c.next32(), 0, 0);
  check('canonical output #3', c.next32(), 5927040, 0);
  // statistics
  final s = Xoshiro128ss.stream(7, 'stats');
  var sum = 0.0, sum2 = 0.0;
  const n = 1000000;
  for (var i = 0; i < n; i++) {
    final v = s.normal();
    sum += v;
    sum2 += v * v;
  }
  final mean = sum / n;
  final variance = sum2 / n - mean * mean;
  check('1e6 normals mean (±0.003)', mean, 0, 0.003);
  check('1e6 normals variance (1 ± 0.005)', variance, 1, 0.005);
}

// ------------------------------------------------------------------ VC-22.1
void instruments() {
  section('VC-22.1 4–20 mA and quality (FT-102, noise off)');
  for (final (v, mA, vm, q) in vc221) {
    final t = Transmitter(ft102, v);
    for (var k = 0; k < 2000; k++) {
      t.update(0.1, v, k * 0.1); // let the 0.5 s damping converge
    }
    check('true $v → mA', t.iq, mA, 1e-4);
    check('true $v → v_meas', t.vMeas, vm, 1e-6);
    check('true $v → quality $q', t.quality.name.toUpperCase() == q ? 1 : 0, 1,
        0);
  }
  for (final (mode, exp) in [
    (FailMode.signalLossLow, vc221LossLow),
    (FailMode.signalLossHigh, vc221LossHigh)
  ]) {
    final t = Transmitter(ft102, 100)
      ..mode = mode
      ..severity = 1
      ..onset = 0;
    t.update(0.1, 100, 1);
    check('${mode.name} mA', t.iq, exp.$1, 1e-9);
    check('${mode.name} v_meas', t.vMeas, exp.$2, 1e-9);
    check('${mode.name} BAD', t.quality == Quality.bad ? 1 : 0, 1, 0);
  }
  section('σ_disp of each instrument type (PHYSICS.md §10.5 table)');
  for (final (spec, exp) in [
    (ft102, 0.409),
    (ft201, 0.246),
    (lt101, 0.423),
    (lt102, 0.775),
    (pt101, 0.046),
    (pdt101, 0.845),
    (tiTray, 0.062),
    (tiLine, 0.022)
  ]) {
    check('σ_disp ${spec.tag}', spec.sigmaDisp, exp, 0.0015);
  }
  check('FT-102 σ_disp in kmol/h', ft102.sigmaDisp / 100 * 300, 1.23, 0.01);
  check('TI tray σ_disp in K', tiTray.sigmaDisp / 100 * 200, 0.124, 0.001);
}

// ------------------------------------------------------------------ VC-22.2
({double sd, double mean, double ac}) _stats(
    InstSpec spec, double h, double seconds, int seed,
    {double lag = double.nan}) {
  final mid = spec.lo + 0.5 * spec.span;
  final t = Transmitter(spec, mid, noise: true, seed: seed);
  final n = (seconds / h).round();
  final lagN = (lag.isNaN ? spec.tauS : lag) / h;
  final buf = List<double>.filled(n, 0);
  for (var k = 0; k < n; k++) {
    t.update(h, mid, k * h);
    buf[k] = (t.vMeas - mid) / spec.span * 100;
  }
  var s = 0.0, s2 = 0.0;
  for (final v in buf) {
    s += v;
    s2 += v * v;
  }
  final mean = s / n;
  final varc = s2 / n - mean * mean;
  var acc = 0.0;
  final l = lagN.round();
  for (var k = l; k < n; k++) {
    acc += (buf[k] - mean) * (buf[k - l] - mean);
  }
  return (sd: math.sqrt(varc), mean: mean, ac: acc / (n - l) / varc);
}

void noiseStats() {
  section('VC-22.2 noise statistics (200 000 s, seed 11)');
  for (final (name, spec, hs) in [
    ('FT', ft102, [0.1]),
    ('LT drum', lt101, [0.5, 2.0]),
    ('LT sump', lt102, [0.5, 2.0]),
    ('PT', pt101, [0.5, 2.0]),
    ('PDT', pdt101, [0.5, 2.0]),
    ('TI', tiTray, [0.5, 2.0]),
  ]) {
    final sds = <double>[];
    for (final h in hs) {
      final r = _stats(spec, h, 200000, 11);
      sds.add(r.sd);
      check(
          '$name h=$h sd within ±6 % of σ_disp ${spec.sigmaDisp.toStringAsFixed(4)}',
          r.sd,
          spec.sigmaDisp,
          0.06,
          rel: true);
      check('$name h=$h mean (±0.02 % span)', r.mean, 0, 0.02);
      check('$name h=$h lag-τ_s autocorrelation in 0.45–0.70', r.ac, 0.575,
          0.125);
    }
    if (sds.length == 2)
      check('$name dt independence (±6 %)', sds[1], sds[0], 0.06, rel: true);
  }
  // valve disturbance d
  {
    final ou = Ou(0.010, 30);
    final g = Xoshiro128ss.stream(11, 'valve:FV-102:d');
    const h = 0.1;
    const n = 2000000;
    final buf = List<double>.filled(n, 0);
    for (var k = 0; k < n; k++) {
      buf[k] = ou.step(h, g.normal());
    }
    var s2 = 0.0;
    for (final v in buf) {
      s2 += v * v;
    }
    final sd = math.sqrt(s2 / n);
    var acc = 0.0;
    const l = 300;
    for (var k = l; k < n; k++) {
      acc += buf[k] * buf[k - l];
    }
    check('valve d: sd 0.0100 ± 0.0006', sd, 0.0100, 0.0006);
    check('valve d: autocorrelation at 30 s = e⁻¹ ± 0.05',
        acc / (n - l) / (sd * sd), math.exp(-1), 0.05);
  }
  section(
      'VC-22.3 noise in the closed FC-102 loop (seed 3, 1800 s after 600 s warm-up)');
  {
    final loop = _fc102(noise: true, seed: 3);
    // valve supply disturbance d
    final ou = Ou(0.010, 30);
    final gd = Xoshiro128ss.stream(3, 'valve:FV-102:d');
    final readings = <double>[], trues = <double>[], ops = <double>[];
    var tt = 0.0;
    while (tt < 2400 - 1e-9) {
      // emulate the d multiplier by scaling fMax through the cap trick
      final d = ou.step(0.1, gd.normal());
      final pos = loop.valve.position +
          (loop.valve.command - loop.valve.position) * 0.1 / 2.1;
      loop.valve.position = pos;
      loop.flow = 300 * pos / 100 * (1 + d);
      tt += 0.1;
      loop.ft.update(0.1, loop.flow, tt);
      loop.valve.command = loop.pid.execute(loop.ft.vMeas, 0.1);
      if (tt > 600 && ((tt / 0.5) - (tt / 0.5).round()).abs() < 1e-6) {
        readings.add(loop.ft.vMeas);
        trues.add(loop.flow);
        ops.add(loop.pid.op);
      }
    }
    double sd(List<double> v) {
      final m = v.reduce((a, b) => a + b) / v.length;
      return math.sqrt(
          v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length);
    }

    final diffs = [
      for (var i = 1; i < readings.length; i++) readings[i] - readings[i - 1]
    ];
    check('reading sd 1.18 (1.0–1.4)', sd(readings), 1.2, 0.2);
    check('0.5-s difference sd 0.71 (0.6–0.85)', sd(diffs), 0.725, 0.125);
    check('true-flow sd 0.88 (0.6–1.2)', sd(trues), 0.9, 0.3);
    check('OP sd 0.47 % (0.3–0.7)', sd(ops), 0.5, 0.2);
    var worst = 0.0;
    for (var i = 0; i + 600 <= trues.length; i += 600) {
      final m = trues.sublist(i, i + 600).reduce((a, b) => a + b) / 600;
      worst = math.max(worst, (m - 100).abs());
    }
    check('every 5-min mean of true flow within ±0.4 of SP', worst, 0, 0.4);
  }
}

// ------------------------------------------------------------------ VC-22.5
void signatures() {
  section('VC-22.5 failure-mode signatures');
  // bias
  {
    final t = Transmitter(ft102, 100, noise: true, seed: 5)
      ..mode = FailMode.bias
      ..severity = 0.3
      ..sign = 1
      ..onset = 600;
    var sum = 0.0;
    var n = 0;
    for (var k = 0; k < 12000; k++) {
      final tt = k * 0.1;
      t.update(0.1, 100, tt);
      if (tt >= 600) {
        sum += t.vMeas - 100;
        n++;
      }
    }
    check('bias FT-102 s 0.3: mean(reading − true) = 9.00 ± 0.1', sum / n, 9.0,
        0.1);
    check('bias: GOOD', t.quality == Quality.good ? 1 : 0, 1, 0);
  }
  // drift
  {
    final t = Transmitter(ft101, 100)
      ..mode = FailMode.drift
      ..severity = 0.6
      ..sign = 1
      ..onset = 600;
    double? at1800, at3600;
    for (var k = 0; k <= 42000; k++) {
      final tt = k * 0.1;
      t.update(0.1, 100, tt);
      if ((tt - 2400).abs() < 1e-6) at1800 = t.vMeas - 100;
      if ((tt - 4200).abs() < 1e-6) at3600 = t.vMeas - 100;
    }
    check('drift FT-101 s 0.6: +7.5 after 1800 s', at1800!, 7.5, 0.1);
    check('drift: +15.0 after 3600 s', at3600!, 15.0, 0.1);
  }
  // plugged
  for (final (s, frac) in vc225Plugged) {
    final t = Transmitter(ft102, 100)
      ..mode = FailMode.plugged
      ..severity = s
      ..onset = 600;
    double? shown;
    for (var k = 0; k <= 12600; k++) {
      final tt = k * 0.1;
      final v = tt >= 660 ? 130.0 : 100.0; // +10 % of span 60 s after onset
      t.update(0.1, v, tt);
      if ((tt - 1260).abs() < 1e-6)
        shown = (t.vMeas - 100) / 30; // 600 s after the step
    }
    check('plugged s=$s: fraction shown 600 s after the step', shown!, frac,
        0.01);
    final tauPlug = math.pow(10, 4 * s) - 1;
    check('plugged s=$s: 1 − exp(−600/τ_plug) analytic',
        1 - math.exp(-600 / tauPlug), frac, 0.002);
  }
  {
    final t = Transmitter(ft102, 100, noise: true, seed: 9)
      ..mode = FailMode.plugged
      ..severity = 1
      ..onset = 0;
    final buf = <double>[];
    for (var k = 0; k < 6000; k++) {
      t.update(0.1, 100, k * 0.1);
      if (k >= 3000 && k % 5 == 0) buf.add(t.vMeas);
    }
    final m = buf.reduce((a, b) => a + b) / buf.length;
    final sd = math.sqrt(
        buf.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / buf.length);
    check('plugged s=1, noise on: σ_5min/σ_disp ≤ 0.08 (proto 0.049)',
        sd / 1.227, 0.049, 0.031);
  }
  // spiking: Poisson counts
  {
    for (final (s, exp, tol) in [
      (1.0, vc225Spikes.s1, vc225Spikes.s1Tol),
      (0.5, vc225Spikes.s05, vc225Spikes.s05Tol)
    ]) {
      final lambda = s / 20 * 3600;
      check('spiking s=$s: expected spikes in 3600 s', lambda, exp, 1e-9);
      check('spiking s=$s: 3σ Poisson tolerance ≈ doc tolerance',
          3 * math.sqrt(lambda), tol, 2);
    }
    // amplitude 10–50 % of span on FT-102 at 33 % of span: max current 4 + 16·0.333 + 0.16·50 = 17.3 mA → never BAD
    check('spike at 33 % of span, +50 %: mA', 4 + 16 * 0.3333 + 0.16 * 50,
        17.33, 0.02);
    check('reading at 90 % + 20 % spike → 21.6 mA (BAD)',
        4 + 16 * 0.9 + 0.16 * 20, 21.6, 1e-9);
    // σ_5min/σ_disp for s = 1: spikes of mean 30 % span for 1 s at 180/h → variance ≈ 0.05 × 30² = 45 + 5× electronics
    final r =
        math.sqrt(0.05 * (30 * 30 + 400 / 3) + 0.1 * 0.1) / ft102.sigmaDisp;
    check('spiking s=1: σ ratio ≥ 10 (estimate; proto 17.8)', r >= 10 ? 1 : 0,
        1, 0);
  }
  // coated
  {
    for (final (s, exp) in [
      (0.0, vc225Coated.healthyT63),
      (1.0, vc225Coated.t63)
    ]) {
      final t = Transmitter(tiTray, 100)
        ..mode = FailMode.coated
        ..severity = s
        ..onset = 0;
      double? t63;
      for (var k = 1; k <= 1000; k++) {
        final tt = k * 0.5;
        t.update(0.5, 110, tt);
        t63 ??= t.vMeas - 100 >= 6.3 ? tt : null;
      }
      check('coated s=$s: t63 (s)', t63!, exp, s == 0 ? 0.5 : 1.0);
    }
    final coated = InstSpec('TI', 0, 200, 100, 0.075, 20, 0.01);
    check('coated σ_disp ratio 0.52 ± 0.05',
        coated.sigmaDisp / tiTray.sigmaDisp, vc225Coated.sigmaRatio, 0.05);
  }
  // analyser timeline
  {
    var vss = 0.02;
    final published = <double, double>{};
    var shown = 0.02;
    for (var k = 1; k <= 4000; k++) {
      final tt = k * 0.5;
      final v = tt >= 1000 ? 0.07 : 0.02;
      vss += (v - vss) * 0.5 / 60.5;
      // sample at 100 + 300 m, publish 300 s later
      final m = ((tt - 100) / 300).floor();
      if (m >= 0 && (tt - (100 + 300 * m)).abs() < 1e-9) {
        published[tt + 300] = (vss * 1e4).round() / 1e4;
      }
      if (published.containsKey(tt)) shown = published[tt]!;
      for (final (tq, exp) in vc225Analyser) {
        if ((tt - tq).abs() < 1e-9)
          check('analyser shown at $tq s', shown, exp, 1e-9);
      }
    }
    check('0.826 % of the step after one 0.5-s step through the 60-s lag',
        0.5 / 60.5 * 100, 0.826, 0.001);
  }
  // field gauge
  {
    final g = Xoshiro128ss.stream(1, 'field:LG-101');
    var s = 0.0, s2 = 0.0;
    const n = 100000;
    for (var i = 0; i < n; i++) {
      final e = g.normal() * 1.0;
      final r = ((50 + e) / 2).round() * 2.0 - 50;
      s += r;
      s2 += r * r;
    }
    final sd = math.sqrt(s2 / n - (s / n) * (s / n));
    check('LG-101 reading σ (N(0,1 %) + 2 % rounding) = 1.15 ± 0.1', sd,
        vc226Sigma, 0.1);
    check('analytic √(1 + 4/12)', math.sqrt(1 + 4 / 12), vc226Sigma, 0.01);
  }
}

// ------------------------------------------------------------------ VC-23
void crossChecks() {
  section(
      'VC-23 / §11.5 static detection margins (|r|/band ≥ 2 means unambiguous)');
  for (final m in staticMargins()) {
    stdout.writeln(
        '  ${m.fault} → ${m.check}: r = ${m.residual.toStringAsFixed(2)}, band ${m.band.toStringAsFixed(2)}, ratio ${m.ratio.toStringAsFixed(1)}');
    check('${m.fault} ${m.check} ratio ≥ 2', m.ratio >= 2 ? 1 : 0, 1, 0);
  }
  section('Band vs residual noise at W = 600 s (bands should be 3–10× noise)');
  // C1: flow means (τ_c ≈ 1.5 s) are negligible; the level term dominates:
  // ΔN from two 60-s means of LT-101 (σ 0.423 %, τ_c ≈ 7 s) and LT-102 (0.775 %, τ_c ≈ 5 s)
  final lt1 = meanNoise(0.423, 7, 60) * math.sqrt(2);
  final lt2 = meanNoise(0.775, 5, 60) * math.sqrt(2);
  final c1Noise =
      math.sqrt(math.pow(lt1 * n01pct, 2) + math.pow(lt2 * ns1pct, 2)) /
          kmolhToMols /
          600;
  for (final w in [300.0, 600.0, 1800.0, 3600.0]) {
    final nz = c1Noise * 600 / w; // the level term scales as 1/W
    stdout.writeln(
        '  C1 at W=${w.toInt()} s: residual noise ≈ ${nz.toStringAsFixed(2)} kmol/h vs band 2.0 → '
        'band/noise ${(2.0 / nz).toStringAsFixed(1)}; P(check) ≈ ${(100 * 2 * (1 - _phi(2.0 / nz))).toStringAsFixed(1)} %, '
        'P(fail) ≈ ${(100 * 2 * (1 - _phi(4.0 / nz))).toStringAsFixed(2)} %');
  }
  // FINDING: the doc says bands are 3–10× the residual noise at the default
  // window; for C1 the level term gives ≈ 2.4× at W = 600 s and ≈ 1.2× at
  // W = 300 s, where VC-23.2's "check < 2 %, never fail" cannot hold.
  check('C1 band / noise ≥ 3 at W = 600 s (doc claim; measured ≈ 2.4)',
      2.0 / c1Noise, 6.5, 3.5);
  final c3Noise = math.sqrt(math.pow(lt1 * n01pct / kmolhToMols / 600, 2) +
      2 * math.pow(meanNoise(1.23, 1.5, 600), 2));
  stdout.writeln(
      '  C3 residual noise ≈ ${c3Noise.toStringAsFixed(2)} kmol/h vs band 2.25');
  check('C3 band / noise in 3–10', 2.25 / c3Noise, 6.5, 3.5);
  // C4: the valve disturbance d (σ 0.01, τ 30 s) on a 100 kmol/h flow, 600-s mean: 0.01×100×√(60/600) = 0.32 %
  final c4Noise = meanNoise(0.01, 30, 600);
  stdout.writeln(
      '  C4 noise from d ≈ ${(100 * c4Noise).toStringAsFixed(2)} % of flow (doc 0.32 %) → 0.32 kmol/h vs band 4.5');
  check('C4 10-min noise ≈ 0.32 % of the flow', 100 * c4Noise, 0.32, 0.02);
  // C5 drum over 600 s: ΔLT noise lt1 = 0.42 % plus the integrated flow noise (small)
  stdout.writeln(
      '  C5 drum noise ≈ ${lt1.toStringAsFixed(2)} % vs band 1.5 % (ratio ${(1.5 / lt1).toStringAsFixed(1)})');
  check('C5 band / noise in 3–10', 1.5 / lt1, 6.5, 3.5);
  // design constants
  check('N_0,1 % (drum 3 m³, x_D 0.98)',
      0.03 / (0.98 * 78.11e-3 + 0.02 * 92.14e-3) * 800, 307, 2);
  check('N_S,1 % (sump 2.714 m³, x_B 0.02)',
      0.02714 / (0.02 * 78.11e-3 + 0.98 * 92.14e-3) * 800, 236, 2);
}

// ------------------------------------------------------------------ VC-25.1
void alarms() {
  section('VC-25.1 alarm chatter: LT-101 at exactly 85.0 %, noise on, 1 h');
  for (final (deadband, onD, offD, label) in [
    (1.0, 5.0, 10.0, 'spec'),
    (0.0, 0.0, 0.0, 'unfiltered')
  ]) {
    final raises = <int>[];
    for (var seed = 1; seed <= 5; seed++) {
      final t = Transmitter(lt101, 85.0, noise: true, seed: seed);
      final a =
          RefAlarm(limit: 85, onDelay: onD, offDelay: offD, deadband: deadband);
      for (var k = 0; k < 7200; k++) {
        final tt = k * 0.5;
        t.update(0.5, 85.0, tt);
        a.update(t.vMeas, tt);
      }
      raises.add(a.raises);
    }
    stdout.writeln('  $label: raises per hour by seed = $raises');
    if (label == 'spec') {
      check('spec filtering: max raises/h ≤ 4', raises.reduce(math.max), 2, 2);
    } else {
      check('unfiltered: about 200/h (±60)', raises.reduce((a, b) => a + b) / 5,
          200, 60);
    }
  }
  final inside = <int>[];
  for (var seed = 1; seed <= 5; seed++) {
    final t = Transmitter(lt101, 84.5, noise: true, seed: seed);
    final a = RefAlarm(limit: 85);
    for (var k = 0; k < 7200; k++) {
      t.update(0.5, 84.5, k * 0.5);
      a.update(t.vMeas, k * 0.5);
    }
    inside.add(a.raises);
  }
  stdout.writeln('  at 84.5 % (inside the deadband): $inside');
  check('inside deadband: ≤ 15/h', inside.reduce(math.max), 7, 8);
}

// ------------------------------------------------------------------ VC-26.3
void scoring() {
  section('VC-26.3 scoring arithmetic');
  final o = 0.6 * (2 / 3);
  final t =
      0.2 * (2 / 3) * ((1 - (30000 - 10800) / (43200 - 10800)).clamp(0, 1));
  const s = 0.1;
  const q = 0.1 * 0.9;
  check('guided score', (100 * (o + t + s + q)).round(), vc263.guided, 0);
  final drill = 0.5 +
      0.2 +
      0.2 * (1 - (2700 - 1200 - 600) / (3600 - 600)) +
      0.1 +
      0.1 +
      0.05 -
      0.1 -
      0.03;
  check('drill score', (100 * drill).round(), vc263.drill, 0);
  check('drill never diagnosed', (100 * (0.1 + 0.1)).round(), vc263.drillNever,
      0);
}

/// Standard normal CDF (Abramowitz–Stegun 7.1.26).
double _phi(double z) {
  final t = 1 / (1 + 0.3275911 * z.abs());
  final y = 1 -
      (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                      0.284496736) *
                  t +
              0.254829592) *
          t *
          math.exp(-z * z / 2);
  return z >= 0 ? 0.5 * (1 + y) : 0.5 * (1 - y);
}
