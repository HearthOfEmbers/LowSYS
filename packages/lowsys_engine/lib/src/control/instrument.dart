import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/quantity.dart';
import '../core/rng.dart';

enum Quality { good, uncertain, bad, oos }

enum InstrumentType {
  ftLiquid,
  ftSteam,
  ftWater,
  ltDrum,
  ltSump,
  pt,
  pdt,
  tiTray,
  tiLine,
  at
}

/// One row of the PHYSICS.md 10.5 table (SI spans; sigmas in % of span).
@immutable
class InstrumentSpec {
  final String tag;
  final InstrumentType type;

  /// Metric path of the true value, e.g. `stream.reflux.flow` (ENGINE_API.md 10).
  final String measures;
  final Quantity quantity;
  final double lo, hi;
  final double tauM, sigmaS, tauS, sigmaE;
  final double? analyserPhase;

  /// Display resolution (SI) used for the "digits age" of the signal look.
  final double resolution;
  const InstrumentSpec({
    required this.tag,
    required this.type,
    required this.measures,
    this.quantity = Quantity.dimensionless,
    required this.lo,
    required this.hi,
    required this.tauM,
    required this.sigmaS,
    required this.tauS,
    required this.sigmaE,
    this.analyserPhase,
    this.resolution = 0.1,
  });

  bool get isAnalyser => type == InstrumentType.at;
  bool get isFlow =>
      type == InstrumentType.ftLiquid ||
      type == InstrumentType.ftSteam ||
      type == InstrumentType.ftWater;

  /// Displayed noise of a healthy transmitter in % of span (PHYSICS.md 10.5).
  double get sigmaDisp =>
      math.sqrt(sigmaS * sigmaS * tauS / (tauS + tauM) + sigmaE * sigmaE);
}

/// Failure modes (PHYSICS.md 10.6).
enum InstrumentFaultKind {
  bias,
  drift,
  stuck,
  signalLossLow,
  signalLossHigh,
  signalLoss,
  plugged,
  spiking,
  coated
}

class InstrumentFault {
  final InstrumentFaultKind kind;
  final double sign;
  final double severityFinal, onset, ramp;
  InstrumentFault(
      this.kind, this.sign, this.severityFinal, this.onset, this.ramp);

  double severityAt(double t) {
    if (t < onset) return 0;
    if (ramp <= 0) return severityFinal;
    return severityFinal * ((t - onset) / ramp).clamp(0.0, 1.0);
  }
}

@immutable
class InstrumentReading {
  final String tag;
  final InstrumentType type;
  final Quantity quantity;

  /// v_meas (SI); for an analyser the shown result.
  final double value;
  final double lo, hi;

  /// I_q in mA; NaN for an analyser.
  final double milliamps;
  final Quality quality;

  /// 'IOP−', 'IOP+', 'OOR▲', 'OOR▼', 'STALE', 'OOS' or null.
  final String? qualityText;
  final double lastGoodValue;
  final double sigma5min, typicalSigma;
  final double digitsAge;
  final double? resultAge;
  final String? loopTag;
  const InstrumentReading({
    required this.tag,
    required this.type,
    required this.quantity,
    required this.value,
    required this.lo,
    required this.hi,
    required this.milliamps,
    required this.quality,
    required this.qualityText,
    required this.lastGoodValue,
    required this.sigma5min,
    required this.typicalSigma,
    required this.digitsAge,
    this.resultAge,
    this.loopTag,
  });
}

/// One transmitter with the full PHYSICS.md 10.5 pipeline and its own random streams.
class Instrument {
  InstrumentSpec spec;
  int seed;
  late Rng _rngS = Rng.stream(seed, 'inst:${spec.tag}:s');
  late Rng _rngE = Rng.stream(seed, 'inst:${spec.tag}:e');
  late Rng _rngSpike = Rng.stream(seed, 'inst:${spec.tag}:spike');
  OuNoise _ns;

  String? loopTag;

  /// True for the Tier-2-only instruments while the column runs Tier 1 (PHYSICS.md 13.5).
  bool hidden = false;
  InstrumentFault? fault;

  // pipeline state
  double _vp = 0, _vm = 0;
  bool _init = false;

  // outputs
  double value = 0; // v_meas (SI)
  double milliamps = 12;
  Quality quality = Quality.good;
  String? qualityText;
  double lastGood = 0;

  // frozen outputs for F19 stuck
  bool _frozen = false;

  // spike state
  double _spikeLeft = 0, _spikeAmp = 0;

  // maintenance (OOS) state
  double oosUntil = -1;

  // analyser state
  double _vss = 0;
  double _nextSample = 0;
  double _nextPublish = double.infinity;
  double _pending = 0;
  double resultTime = 0;
  bool _analyserDead = false;

  // signal look: 5-s bins of the last 300 s
  final List<double> _binSum = List<double>.filled(60, 0);
  final List<double> _binSq = List<double>.filled(60, 0);
  final List<int> _binN = List<int>.filled(60, 0);
  int _binIdx = 0;
  double _binStart = 0;
  double _curSum = 0, _curSq = 0;
  int _curN = 0;
  double _lastShown = double.nan;
  double _lastChangeT = 0;

  /// Measurement noise switch (the simulator's `noise` lever).
  bool noise;

  /// Time of the last update (s).
  double _t = 0;

  Instrument(this.spec,
      {this.seed = 1, this.noise = false, double initialValue = 0})
      : _ns = OuNoise(spec.sigmaS / 100 * (spec.hi - spec.lo), spec.tauS) {
    reset(initialValue, 0);
  }

  double get span => spec.hi - spec.lo;

  /// Starts every state at the true value (PHYSICS.md 10.5 Initialisation, 13.1).
  void reset(double v, double t) {
    _vp = v;
    _vm = v;
    _init = true;
    _ns.value = 0;
    value = v;
    lastGood = v;
    milliamps = 4 + 16 * (v - spec.lo) / span;
    quality = Quality.good;
    qualityText = null;
    _frozen = false;
    _spikeLeft = 0;
    _vss = v;
    _pending = v;
    resultTime = t;
    _nextSample = (spec.analyserPhase ?? 0) +
        300 * ((t - (spec.analyserPhase ?? 0)) / 300).ceil();
    _nextPublish = double.infinity;
    _analyserDead = false;
    _lastShown = _display(v);
    _lastChangeT = t;
    _binStart = t;
    for (var i = 0; i < 60; i++) {
      _binSum[i] = 0;
      _binSq[i] = 0;
      _binN[i] = 0;
    }
    _curSum = 0;
    _curSq = 0;
    _curN = 0;
  }

  /// Replaces the span and noise data (FT-103 changes quantity on a tier switch, PHYSICS.md 13.5) and restarts
  /// every state at the true value [v] at time [t].
  void retarget(InstrumentSpec s, double v, double t) {
    spec = s;
    _ns = OuNoise(s.sigmaS / 100 * (s.hi - s.lo), s.tauS);
    typicalPct = null;
    reset(v, t);
  }

  void reseed(int newSeed) {
    seed = newSeed;
    _rngS = Rng.stream(seed, 'inst:${spec.tag}:s');
    _rngE = Rng.stream(seed, 'inst:${spec.tag}:e');
    _rngSpike = Rng.stream(seed, 'inst:${spec.tag}:spike');
  }

  /// Switching noise on starts every noise state at zero (PHYSICS.md 10.5).
  void resetNoise() {
    _ns.value = 0;
  }

  double _display(double v) => (v / spec.resolution).roundToDouble();

  /// Healthy 1-sigma of the reading in % of span when it differs from the transmitter alone (flows moved by a level
  /// loop, PHYSICS.md 10.5).
  double? typicalPct;

  double get typicalSigma => (typicalPct ?? spec.sigmaDisp) / 100 * span;

  /// Transmitter update (flow transmitters: h = 0.1 s; others: dt).
  void update(double h, double v, double t) {
    _t = t;
    if (!_init) reset(v, t);
    if (t < oosUntil) {
      quality = Quality.oos;
      qualityText = 'OOS';
      _record(value, t, h);
      return;
    }
    final f = fault;
    final s = f == null ? 0.0 : f.severityAt(t);
    final active = f != null && s > 0;
    final kind = active ? f.kind : null;
    if (kind == InstrumentFaultKind.stuck) {
      _frozen = true;
      _record(value, t, h);
      return;
    }
    _frozen = false;
    // 1 sensed signal
    var vs = v;
    if (noise) vs += _ns.step(h, _rngS);
    // 2 impulse line
    if (kind == InstrumentFaultKind.plugged) {
      final tauPlug = math.pow(10, 4 * s).toDouble() - 1;
      _vp += (vs - _vp) * h / (tauPlug + h);
    } else {
      _vp = vs;
    }
    // 3 damping
    final tauEff = kind == InstrumentFaultKind.coated
        ? spec.tauM * (1 + 9 * s)
        : spec.tauM;
    _vm += (_vp - _vm) * h / (tauEff + h);
    // 4 calibration
    var b = 0.0;
    if (kind == InstrumentFaultKind.bias) b = f!.sign * s * 0.10 * span;
    if (kind == InstrumentFaultKind.drift)
      b = f!.sign * s * 0.10 * span * (t - f.onset) / 3600;
    final vc = _vm + b;
    // 5 4-20 mA
    final sigE = spec.sigmaE * (kind == InstrumentFaultKind.spiking ? 5 : 1);
    var i = 4 + 16 * (vc - spec.lo) / span;
    if (noise) i += 0.16 * sigE * _rngE.normal();
    // 6 saturation
    i = i.clamp(3.8, 20.5).toDouble();
    // 7 spikes
    if (kind == InstrumentFaultKind.spiking) {
      if (_spikeLeft > 0) {
        _spikeLeft -= h;
      } else {
        final rate = s / 20;
        if (_rngSpike.uniform() < 1 - math.exp(-rate * h)) {
          final sign = _rngSpike.uniform() < 0.5 ? -1.0 : 1.0;
          _spikeAmp = sign * s * (10 + 40 * _rngSpike.uniform());
          _spikeLeft = 1.0;
        }
      }
      if (_spikeLeft > 0) i += 0.16 * _spikeAmp;
    } else {
      _spikeLeft = 0;
    }
    // 8 failure current
    if (kind == InstrumentFaultKind.signalLossLow) i = 3.6;
    if (kind == InstrumentFaultKind.signalLossHigh) i = 21.0;
    // 9 A/D (only with noise on, so a noise-free run is exact)
    final iq = noise
        ? (math.min(24.0, math.max(0.0, (4096 * i).roundToDouble() / 4096)))
        : i.clamp(0.0, 24.0).toDouble();
    milliamps = iq;
    // 10 value
    value = spec.lo + (iq - 4) / 16 * span;
    // 11 quality
    if (iq <= 3.6 + 1e-3) {
      quality = Quality.bad;
      qualityText = 'IOP−';
    } else if (iq >= 21.0 - 1e-3) {
      quality = Quality.bad;
      qualityText = 'IOP+';
    } else if (iq < 4.0) {
      quality = Quality.uncertain;
      qualityText = 'OOR▼';
    } else if (iq > 20.0) {
      quality = Quality.uncertain;
      qualityText = 'OOR▲';
    } else {
      quality = Quality.good;
      qualityText = null;
    }
    if (quality != Quality.bad) lastGood = value;
    _record(value, t, h);
  }

  /// Analyser update in the main layer (PHYSICS.md 10.5): sample-line lag, cyclic sampling, delayed result.
  /// [t] is the time at the END of the step.
  void updateAnalyser(double dt, double v, double t) {
    _t = t;
    if (!_init) reset(v, t);
    final f = fault;
    final s = f == null ? 0.0 : f.severityAt(t - dt);
    final active = f != null && s > 0;
    final kind = active ? f.kind : null;
    if (t - dt < oosUntil || t < oosUntil) {
      quality = Quality.oos;
      qualityText = 'OOS';
      return;
    }
    if (kind == InstrumentFaultKind.stuck) {
      return;
    }
    if (kind == InstrumentFaultKind.signalLoss) _analyserDead = true;
    final tauSs = 60.0 +
        (kind == InstrumentFaultKind.plugged
            ? math.pow(10, 4 * s).toDouble() - 1
            : 0.0);
    _vss += (v - _vss) * dt / (tauSs + dt);
    if (!_analyserDead && t + 1e-9 >= _nextPublish) {
      value = ((_pending.clamp(spec.lo, spec.hi)) * 1e4).roundToDouble() / 1e4;
      resultTime = _nextPublish - 300;
      _nextPublish = double.infinity;
      lastGood = value;
    }
    if (!_analyserDead && t + 1e-9 >= _nextSample) {
      var b = 0.0;
      if (kind == InstrumentFaultKind.bias) b = f!.sign * s * 0.10 * span;
      if (kind == InstrumentFaultKind.drift)
        b = f!.sign * s * 0.10 * span * (t - f.onset) / 3600;
      _pending = _vss + b + (noise ? 0.005 * span * _rngE.normal() : 0.0);
      _nextPublish = _nextSample + 300;
      _nextSample += 300;
    }
    final age = t - resultTime;
    if (_analyserDead) {
      quality = Quality.bad;
      qualityText = 'analyser fault';
    } else if (age > 600) {
      quality = Quality.uncertain;
      qualityText = 'STALE';
    } else {
      quality = Quality.good;
      qualityText = null;
    }
    _record(value, t, dt);
  }

  double resultAge(double t) => t - resultTime;

  void _record(double shown, double t, double h) {
    // signal look (5-s bins), digits age
    if (t - _binStart >= 5 - 1e-9) {
      _binSum[_binIdx] = _curSum;
      _binSq[_binIdx] = _curSq;
      _binN[_binIdx] = _curN;
      _binIdx = (_binIdx + 1) % 60;
      _curSum = 0;
      _curSq = 0;
      _curN = 0;
      _binStart = t;
    }
    _curSum += shown;
    _curSq += shown * shown;
    _curN++;
    final d = _display(shown);
    if (d != _lastShown) {
      _lastShown = d;
      _lastChangeT = t;
    }
  }

  /// Standard deviation of the readings over the last 300 s.
  double sigma5min() {
    var n = _curN, sum = _curSum, sq = _curSq;
    for (var i = 0; i < 60; i++) {
      if (i == _binIdx) continue; // the oldest bin: the window is the last 295-300 s, so a frozen signal reads 0 within 300 s
      n += _binN[i];
      sum += _binSum[i];
      sq += _binSq[i];
    }
    if (n < 2) return 0;
    final mean = sum / n;
    final v = sq / n - mean * mean;
    return v <= 1e-14 * mean * mean ? 0 : math.sqrt(v);
  }

  InstrumentReading get reading => readingAt(_t);

  InstrumentReading readingAt(double t) => InstrumentReading(
        tag: spec.tag,
        type: spec.type,
        quantity: spec.quantity,
        value: value,
        lo: spec.lo,
        hi: spec.hi,
        milliamps: spec.isAnalyser ? double.nan : milliamps,
        quality: quality,
        qualityText: qualityText,
        lastGoodValue: lastGood,
        sigma5min: sigma5min(),
        typicalSigma: typicalSigma,
        digitsAge: t - _lastChangeT,
        resultAge: spec.isAnalyser ? t - resultTime : null,
        loopTag: loopTag,
      );

  /// PV in % of span.
  double get pvPercent => 100 * (value - spec.lo) / span;

  /// Maintenance (sandbox): OOS for 1800 s, then the faults clear and states restart (PHYSICS.md 10.5).
  void startMaintenance(double t) {
    oosUntil = t + 1800;
  }

  /// Called when maintenance ends.
  void finishMaintenance(double trueValue, double t) {
    fault = null;
    oosUntil = -1;
    reset(trueValue, t);
  }

  Map<String, Object?> toJson() => {
        'vp': _vp,
        'vm': _vm,
        'init': _init,
        'ns': _ns.value,
        'value': value,
        'ma': milliamps,
        'q': quality.index,
        'qt': qualityText,
        'lastGood': lastGood,
        'frozen': _frozen,
        'spikeLeft': _spikeLeft,
        'spikeAmp': _spikeAmp,
        'oosUntil': oosUntil,
        'vss': _vss,
        'nextSample': _nextSample,
        'nextPublish': _nextPublish.isFinite ? _nextPublish : null,
        'pending': _pending,
        'resultTime': resultTime,
        'dead': _analyserDead,
        'binSum': _binSum,
        'binSq': _binSq,
        'binN': _binN,
        'binIdx': _binIdx,
        'binStart': _binStart,
        'curSum': _curSum,
        'curSq': _curSq,
        'curN': _curN,
        'lastShown': _lastShown.isNaN ? null : _lastShown,
        'lastChangeT': _lastChangeT,
        'rngS': _rngS.toJson(),
        'rngE': _rngE.toJson(),
        'rngSpike': _rngSpike.toJson(),
        'fault': fault == null
            ? null
            : {
                'kind': fault!.kind.name,
                'sign': fault!.sign,
                's': fault!.severityFinal,
                'onset': fault!.onset,
                'ramp': fault!.ramp
              },
      };

  void loadJson(Map<String, Object?> j) {
    double d(String k) => (j[k]! as num).toDouble();
    _vp = d('vp');
    _vm = d('vm');
    _init = j['init']! as bool;
    _ns.value = d('ns');
    value = d('value');
    milliamps = d('ma');
    quality = Quality.values[(j['q']! as num).toInt()];
    qualityText = j['qt'] as String?;
    lastGood = d('lastGood');
    _frozen = j['frozen']! as bool;
    _spikeLeft = d('spikeLeft');
    _spikeAmp = d('spikeAmp');
    oosUntil = d('oosUntil');
    _vss = d('vss');
    _nextSample = d('nextSample');
    _nextPublish = (j['nextPublish'] as num?)?.toDouble() ?? double.infinity;
    _pending = d('pending');
    resultTime = d('resultTime');
    _analyserDead = j['dead']! as bool;
    final bs = j['binSum']! as List<Object?>,
        bq = j['binSq']! as List<Object?>,
        bn = j['binN']! as List<Object?>;
    for (var i = 0; i < 60; i++) {
      _binSum[i] = (bs[i]! as num).toDouble();
      _binSq[i] = (bq[i]! as num).toDouble();
      _binN[i] = (bn[i]! as num).toInt();
    }
    _binIdx = (j['binIdx']! as num).toInt();
    _binStart = d('binStart');
    _curSum = d('curSum');
    _curSq = d('curSq');
    _curN = (j['curN']! as num).toInt();
    _lastShown = (j['lastShown'] as num?)?.toDouble() ?? double.nan;
    _lastChangeT = d('lastChangeT');
    _rngS.loadJson(j['rngS']! as Map<String, Object?>);
    _rngE.loadJson(j['rngE']! as Map<String, Object?>);
    _rngSpike.loadJson(j['rngSpike']! as Map<String, Object?>);
    final f = j['fault'] as Map<String, Object?>?;
    fault = f == null
        ? null
        : InstrumentFault(
            InstrumentFaultKind.values.firstWhere((e) => e.name == f['kind']),
            (f['sign']! as num).toDouble(),
            (f['s']! as num).toDouble(),
            (f['onset']! as num).toDouble(),
            (f['ramp']! as num).toDouble());
  }
}
