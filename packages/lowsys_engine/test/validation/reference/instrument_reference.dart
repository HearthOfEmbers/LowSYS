// Independent transmitter pipeline (PHYSICS.md §10.5), OU noise, 4–20 mA
// conversion and the F19/F28 failure modes; also the §10.3 valve and the
// §10.4 flow loop as a closed loop at the 0.1 s sub-step. No engine imports.
library;

import 'dart:math' as math;

import 'pid_reference.dart';
import 'prng_reference.dart';

/// Exact Ornstein–Uhlenbeck discretisation: statistics independent of h.
class Ou {
  final double sigma, tau;
  double n = 0;
  Ou(this.sigma, this.tau);
  double step(double h, double xi) {
    final a = math.exp(-h / tau);
    n = a * n + sigma * math.sqrt(1 - a * a) * xi;
    return n;
  }
}

class InstSpec {
  final String tag;
  final double lo, hi, tauM, sigmaS, tauS, sigmaE;
  const InstSpec(this.tag, this.lo, this.hi, this.tauM, this.sigmaS, this.tauS,
      this.sigmaE);
  double get span => hi - lo;

  /// σ_disp of a healthy transmitter, % of span.
  double get sigmaDisp =>
      math.sqrt(sigmaS * sigmaS * tauS / (tauS + tauM) + sigmaE * sigmaE);
}

// B-T instrument table (PHYSICS.md §10.5). Spans in kmol/h, %, kPa, °C.
const ft102 = InstSpec('FT-102', 0, 300, 0.5, 0.50, 1, 0.02);
const ft101 = InstSpec('FT-101', 0, 250, 0.5, 0.50, 1, 0.02);
const ft104 = InstSpec('FT-104', 0, 100, 0.5, 0.50, 1, 0.02);
const ft201 = InstSpec('FT-201', 0, 150, 0.5, 0.30, 1, 0.02);
const lt101 = InstSpec('LT-101', 0, 100, 2, 0.50, 5, 0.02);
const lt102 = InstSpec('LT-102', 0, 100, 2, 1.00, 3, 0.02);
const pt101 = InstSpec('PT-101', 0, 202.65, 1, 0.05, 2, 0.02);
const pdt101 = InstSpec('PDT-101', 0, 40, 2, 1.00, 5, 0.02);
const tiTray = InstSpec('TI-114', 0, 200, 10, 0.075, 20, 0.01);
const tiLine = InstSpec('TI-100', 0, 200, 10, 0.025, 20, 0.01);

enum Quality { good, uncertain, bad }

enum FailMode {
  none,
  bias,
  drift,
  stuck,
  signalLossLow,
  signalLossHigh,
  plugged,
  spiking,
  coated
}

class Transmitter {
  final InstSpec spec;
  final bool noise;
  final Ou _ns;
  final Xoshiro128ss _rs, _re;
  double vp, vm;
  double vMeas, iq;
  Quality quality = Quality.good;
  String? qualityText;
  // fault
  FailMode mode = FailMode.none;
  double severity = 0, sign = 1, onset = double.infinity;
  double _stuckV = 0, _stuckI = 0;
  Quality _stuckQ = Quality.good;

  Transmitter(this.spec, double v0, {this.noise = false, int seed = 1})
      : _ns = Ou(spec.sigmaS, spec.tauS),
        _rs = Xoshiro128ss.stream(seed, 'inst:${spec.tag}:s'),
        _re = Xoshiro128ss.stream(seed, 'inst:${spec.tag}:e'),
        vp = v0,
        vm = v0,
        vMeas = v0,
        iq = 4 + 16 * (v0 - spec.lo) / (spec.hi - spec.lo);

  double _bias(double t) {
    final s = severity;
    switch (mode) {
      case FailMode.bias:
        return sign * s * 0.10 * spec.span;
      case FailMode.drift:
        return sign * s * 0.10 * spec.span * (t - onset) / 3600;
      default:
        return 0;
    }
  }

  void update(double h, double v, double t, {double spikePct = 0}) {
    final active = t >= onset && mode != FailMode.none;
    if (active && mode == FailMode.stuck) {
      vMeas = _stuckV;
      iq = _stuckI;
      quality = _stuckQ;
      return;
    }
    final ns = noise ? _ns.step(h, _rs.normal()) * spec.span / 100 : 0.0;
    final vs = v + ns;
    if (active && mode == FailMode.plugged) {
      final tauPlug = math.pow(10, 4 * severity) - 1;
      vp += (vs - vp) * h / (tauPlug + h);
    } else {
      vp = vs;
    }
    final tauM = active && mode == FailMode.coated
        ? spec.tauM * (1 + 9 * severity)
        : spec.tauM;
    vm += (vp - vm) * h / (tauM + h);
    final vc = vm + (active ? _bias(t) : 0);
    final sigE =
        active && mode == FailMode.spiking ? spec.sigmaE * 5 : spec.sigmaE;
    final ne = noise ? sigE * _re.normal() : 0.0;
    var i = 4 + 16 * (vc - spec.lo) / spec.span + 0.16 * ne;
    i = i.clamp(3.8, 20.5);
    i += 0.16 * spikePct;
    if (active && mode == FailMode.signalLossLow) i = 3.6;
    if (active && mode == FailMode.signalLossHigh) i = 21.0;
    iq = noise ? (4096 * i).roundToDouble() / 4096 : i;
    iq = iq.clamp(0, 24);
    vMeas = spec.lo + (iq - 4) / 16 * spec.span;
    if (iq <= 3.6 || iq >= 21.0) {
      quality = Quality.bad;
      qualityText = iq <= 3.6 ? 'IOP−' : 'IOP+';
    } else if (iq < 4.0 || iq > 20.0) {
      quality = Quality.uncertain;
      qualityText = iq < 4.0 ? 'OOR▼' : 'OOR▲';
    } else {
      quality = Quality.good;
      qualityText = null;
    }
    // remember for a stuck fault that starts next update
    _stuckV = vMeas;
    _stuckI = iq;
    _stuckQ = quality;
  }
}

/// §10.3 valve: implicit first-order position lag, linear characteristic.
class RefValve {
  final double fMax, tau;
  double position, command;
  bool stuck = false;
  double cap = double.infinity;
  RefValve(this.fMax, this.position, {this.tau = 2.0}) : command = position;
  double step(double h) {
    if (!stuck) position += (command - position) * h / (tau + h);
    return math.min(fMax * position / 100, cap);
  }
}

/// Closed flow loop FC-102-like: valve → transmitter → PI, at sub-step δ.
class RefFlowLoop {
  final RefValve valve;
  final Transmitter ft;
  final RefPid pid;
  final double delta;
  double flow;
  double t = 0;
  RefFlowLoop(
      {required this.valve,
      required this.ft,
      required this.pid,
      this.delta = 0.1,
      required this.flow});

  /// One sub-step: position update, flow, transmitter, PID → next command.
  void subStep() {
    flow = valve.step(delta);
    t += delta;
    ft.update(delta, flow, t);
    final op = pid.execute(ft.vMeas, delta);
    valve.command = op;
  }

  /// One main step of dt: n sub-steps; returns the mean flow.
  double mainStep(double dt) {
    final n = (dt / delta).round();
    var sum = 0.0;
    for (var k = 0; k < n; k++) {
      subStep();
      sum += flow;
    }
    return sum / n;
  }
}
