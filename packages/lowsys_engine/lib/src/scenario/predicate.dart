import '../core/ids.dart';
import '../sim/simulator.dart';

/// Resolves metric paths (ENGINE_API.md 11.1). Values are `num`, `bool` or `String`; `null` for an unknown path.
/// [MetricContext.live] reads the true model state of a running [Simulator] without building a snapshot; tests
/// use [FakeMetricContext].
abstract class MetricContext {
  const MetricContext();

  /// A context over the live simulator. [scenarioTime] is the value of the `time` metric.
  factory MetricContext.live(Simulator sim,
          {Map<String, Object?> answers = const {},
          double scenarioTime = 0,
          Map<String, Object?> start = const {}}) =>
      LiveMetricContext(sim)
        ..answers = answers
        ..scenarioTime = scenarioTime
        ..start = start;

  /// Current value of [path].
  dynamic read(String path);

  /// Value of [path] at the start of the scenario (for `from: "start"` comparisons).
  dynamic readStart(String path);
}

/// Mutable live context, reused by the scenario runner so that a step allocates nothing.
class LiveMetricContext extends MetricContext {
  final Simulator sim;
  Map<String, Object?> answers = const {};
  Map<String, Object?> start = const {};
  double scenarioTime = 0;
  LiveMetricContext(this.sim);

  @override
  dynamic read(String path) {
    if (path == 'time') return scenarioTime;
    if (path.startsWith('answer.')) return answers[path.substring(7)];
    return sim.liveMetric(path);
  }

  @override
  dynamic readStart(String path) => start[path];
}

/// A context over fixed values, for predicate tests.
class FakeMetricContext extends MetricContext {
  final Map<String, Object?> values, startValues;
  FakeMetricContext(this.values, {Map<String, Object?> start = const {}})
      : startValues = start;
  @override
  dynamic read(String path) => values[path];
  @override
  dynamic readStart(String path) => startValues[path];
}

/// Metric paths that a scenario may use (ENGINE_API.md 11.1).
final RegExp metricPathPattern = RegExp(
    r'^(time|steady|alarm\.count|alarm\[[\w.:-]+\]\.active|safety\.(reliefLifted|levelViolationSeconds)|kpi\.(xD|xB|d|b|refluxRatio|boilup|qc|qr|columnDp|maxFloodPct|maxWeepFraction|drumLevelPct|sumpLevelPct|pTop|recoveryLK|recoveryHK|balanceResidual)|answer\.\w+|lever\.[\w.]+|stage\[\d+\]\.(t|p|x|holdup|weepFrac|jetFlood)|loop\[[\w-]+\]\.(pv|sp|op|mode)|instrument\[[\w-]+\]\.(value|quality)|valve\[[\w-]+\]\.(op|position)|check\[[\w:.-]+\]\.(residual|status)|condenser\.(drumLevelPct|qc)|reboiler\.(qr|steamValveOp))$');

/// Structured predicate: all / any / not / leaf comparisons (no expression language).
sealed class Predicate {
  const Predicate();
  bool evaluate(MetricContext c);

  /// Same as [evaluate] (M2 name).
  bool eval(MetricContext c) => evaluate(c);
  void collectMetrics(List<String> out);

  /// Metric paths compared with `from: "start"`.
  void collectStartMetrics(List<String> out);

  static Predicate fromJson(Map<String, Object?> j) {
    if (j.containsKey('all')) {
      return _All([
        for (final e in j['all']! as List<Object?>)
          fromJson(e! as Map<String, Object?>)
      ]);
    }
    if (j.containsKey('any')) {
      return _Any([
        for (final e in j['any']! as List<Object?>)
          fromJson(e! as Map<String, Object?>)
      ]);
    }
    if (j.containsKey('not')) {
      return _Not(fromJson(j['not']! as Map<String, Object?>));
    }
    return _Leaf(j['metric']! as String, j['op']! as String, j['value'],
        (j['lo'] as num?)?.toDouble(), (j['hi'] as num?)?.toDouble(),
        fromStart: j['from'] == 'start');
  }
}

class _All extends Predicate {
  final List<Predicate> items;
  _All(this.items);
  @override
  bool evaluate(MetricContext c) {
    for (final p in items) {
      if (!p.evaluate(c)) return false;
    }
    return true;
  }

  @override
  void collectMetrics(List<String> out) {
    for (final p in items) {
      p.collectMetrics(out);
    }
  }

  @override
  void collectStartMetrics(List<String> out) {
    for (final p in items) {
      p.collectStartMetrics(out);
    }
  }
}

class _Any extends Predicate {
  final List<Predicate> items;
  _Any(this.items);
  @override
  bool evaluate(MetricContext c) {
    for (final p in items) {
      if (p.evaluate(c)) return true;
    }
    return false;
  }

  @override
  void collectMetrics(List<String> out) {
    for (final p in items) {
      p.collectMetrics(out);
    }
  }

  @override
  void collectStartMetrics(List<String> out) {
    for (final p in items) {
      p.collectStartMetrics(out);
    }
  }
}

class _Not extends Predicate {
  final Predicate p;
  _Not(this.p);
  @override
  bool evaluate(MetricContext c) => !p.evaluate(c);
  @override
  void collectMetrics(List<String> out) => p.collectMetrics(out);
  @override
  void collectStartMetrics(List<String> out) => p.collectStartMetrics(out);
}

class _Leaf extends Predicate {
  final String metric, op;
  final Object? value;
  final double? lo, hi;
  final bool fromStart;
  _Leaf(this.metric, this.op, this.value, this.lo, this.hi,
      {this.fromStart = false});

  @override
  bool evaluate(MetricContext c) {
    var v = c.read(metric);
    if (v == null) return false;
    if (v is bool) {
      final w = value is bool ? value! as bool : (value as num) != 0;
      return op == '!=' ? v != w : v == w;
    }
    if (v is String) return op == '!=' ? v != value : v == value;
    var x = (v as num).toDouble();
    if (fromStart) {
      final s = c.readStart(metric);
      if (s is! num) return false;
      x -= s.toDouble();
    }
    if (x.isNaN) return op == '!=';
    if (op == 'between') return x >= lo! && x <= hi!;
    final y = (value! as num).toDouble();
    switch (op) {
      case '<':
        return x < y;
      case '<=':
        return x <= y;
      case '==':
        return (x - y).abs() < 1e-9;
      case '>=':
        return x >= y;
      case '>':
        return x > y;
      case '!=':
        return (x - y).abs() >= 1e-9;
    }
    throw ConfigException('Unknown operator "$op"');
  }

  @override
  void collectMetrics(List<String> out) => out.add(metric);
  @override
  void collectStartMetrics(List<String> out) {
    if (fromStart) out.add(metric);
  }
}
