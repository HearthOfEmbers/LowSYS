import '../core/ids.dart';
import '../snapshot/sim_snapshot.dart';

/// Resolves metric paths (ENGINE_API.md 11.1) against a snapshot and the scenario state.
class MetricContext {
  final SimSnapshot snapshot;
  final double scenarioTime;
  final Map<String, Object?> answers;
  final double levelViolationSeconds;
  const MetricContext(this.snapshot, this.scenarioTime, this.answers,
      this.levelViolationSeconds);

  /// Returns a num or bool, or null if the path is unknown.
  Object? read(String path) {
    final s = snapshot;
    if (path == 'time') return scenarioTime;
    if (path == 'steady') return s.steady.isSteady;
    if (path == 'alarm.count') return s.alarms.length;
    if (path == 'safety.reliefLifted') return false;
    if (path == 'safety.levelViolationSeconds') return levelViolationSeconds;
    if (path.startsWith('kpi.')) return _kpi(path.substring(4));
    if (path.startsWith('answer.')) return answers[path.substring(7)];
    if (path.startsWith('lever.')) return s.levers[path.substring(6)];
    final st = RegExp(r'^stage\[(\d+)\]\.(\w+)$').firstMatch(path);
    if (st != null) return _stage(int.parse(st.group(1)!), st.group(2)!);
    final lp = RegExp(r'^loop\[([\w-]+)\]\.(pv|sp|op|mode)$').firstMatch(path);
    if (lp != null) {
      for (final l in s.loops) {
        if (l.tag == lp.group(1)) {
          switch (lp.group(2)) {
            case 'pv':
              return l.pv;
            case 'sp':
              return l.sp;
            case 'op':
              return l.op;
            default:
              return l.mode.name;
          }
        }
      }
    }
    return null;
  }

  double? _kpi(String f) {
    final k = snapshot.kpis;
    switch (f) {
      case 'xD':
        return k.xD;
      case 'xB':
        return k.xB;
      case 'd':
        return k.d;
      case 'b':
        return k.b;
      case 'refluxRatio':
        return k.refluxRatio;
      case 'boilup':
        return k.boilup;
      case 'columnDp':
        return k.columnDp;
      case 'maxFloodPct':
        return k.maxFloodPct;
      case 'maxWeepFraction':
        return k.maxWeepFraction;
      case 'drumLevelPct':
        return k.drumLevelPct;
      case 'sumpLevelPct':
        return k.sumpLevelPct;
      case 'pTop':
        return k.pTop;
    }
    return null;
  }

  double? _stage(int j, String f) {
    final st = snapshot.stages;
    if (j < 0 || j >= st.n) return null;
    switch (f) {
      case 'x':
        return st.x[j * st.nc];
      case 'y':
        return st.y[j * st.nc];
      case 'dp':
        return st.dp[j];
      case 'jetFlood':
        return st.jetFlood[j];
      case 'dcFlood':
        return st.dcFlood[j];
      case 'weepFrac':
        return st.weepFrac[j];
      case 'holdup':
        return st.holdup[j];
    }
    return null;
  }
}

/// Structured predicate: all / any / not / leaf comparisons (no expression language).
sealed class Predicate {
  const Predicate();
  bool eval(MetricContext c);
  void collectMetrics(List<String> out);

  static Predicate fromJson(Map<String, Object?> j) {
    if (j.containsKey('all'))
      return _All([
        for (final e in j['all']! as List<Object?>)
          fromJson(e! as Map<String, Object?>)
      ]);
    if (j.containsKey('any'))
      return _Any([
        for (final e in j['any']! as List<Object?>)
          fromJson(e! as Map<String, Object?>)
      ]);
    if (j.containsKey('not'))
      return _Not(fromJson(j['not']! as Map<String, Object?>));
    return _Leaf(j['metric']! as String, j['op']! as String, j['value'],
        (j['lo'] as num?)?.toDouble(), (j['hi'] as num?)?.toDouble());
  }
}

class _All extends Predicate {
  final List<Predicate> items;
  _All(this.items);
  @override
  bool eval(MetricContext c) => items.every((p) => p.eval(c));
  @override
  void collectMetrics(List<String> out) {
    for (final p in items) {
      p.collectMetrics(out);
    }
  }
}

class _Any extends Predicate {
  final List<Predicate> items;
  _Any(this.items);
  @override
  bool eval(MetricContext c) => items.any((p) => p.eval(c));
  @override
  void collectMetrics(List<String> out) {
    for (final p in items) {
      p.collectMetrics(out);
    }
  }
}

class _Not extends Predicate {
  final Predicate p;
  _Not(this.p);
  @override
  bool eval(MetricContext c) => !p.eval(c);
  @override
  void collectMetrics(List<String> out) => p.collectMetrics(out);
}

class _Leaf extends Predicate {
  final String metric, op;
  final Object? value;
  final double? lo, hi;
  _Leaf(this.metric, this.op, this.value, this.lo, this.hi);

  @override
  bool eval(MetricContext c) {
    final v = c.read(metric);
    if (v == null) return false;
    if (v is bool) {
      final w = value is bool ? value! as bool : (value as num) != 0;
      return op == '!=' ? v != w : v == w;
    }
    if (v is String) return op == '!=' ? v != value : v == value;
    final x = (v as num).toDouble();
    if (x.isNaN) return false;
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
}
