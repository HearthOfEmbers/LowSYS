import 'package:meta/meta.dart';

import '../config/column_config.dart';
import '../config/presets.dart';
import '../core/ids.dart';
import '../faults/fault_spec.dart';
import 'predicate.dart';

@immutable
class ObjectiveDef {
  final String id, text;
  final Predicate? when;

  /// Seconds the predicate must hold continuously.
  final double holdFor;

  /// Once achieved it stays achieved.
  final bool latch;

  /// Id of an objective that must be achieved first.
  final String? after;
  const ObjectiveDef(
      {required this.id,
      required this.text,
      this.when,
      this.holdFor = 0,
      this.latch = false,
      this.after});
}

@immutable
class HintDef {
  final double? after;
  final Predicate? when;
  final String text;
  const HintDef({this.after, this.when, required this.text});
}

@immutable
class EventDef {
  final double at;
  final String action;
  final Map<String, Object?> data;
  const EventDef(this.at, this.action, this.data);
}

/// A guided scenario (ENGINE_API.md 11.1).
class ScenarioDef {
  final String id, kind, title, topic, briefing, debrief;
  final int milestone;
  final PresetId preset;
  final Map<String, Object?> overrides;
  final Map<LeverId, double> leverSet;
  final List<LeverId> leverLock, leverShow;
  final double timeLimit;
  final List<ObjectiveDef> objectives;
  final List<HintDef> hints;
  final List<EventDef> events;
  final Map<String, Object?> scoring;

  ScenarioDef._({
    required this.id,
    required this.kind,
    required this.title,
    required this.topic,
    required this.briefing,
    required this.debrief,
    required this.milestone,
    required this.preset,
    required this.overrides,
    required this.leverSet,
    required this.leverLock,
    required this.leverShow,
    required this.timeLimit,
    required this.objectives,
    required this.hints,
    required this.events,
    required this.scoring,
  });

  factory ScenarioDef.fromJson(Map<String, Object?> j) {
    final lev = (j['levers'] as Map<String, Object?>?) ?? const {};
    final set = (lev['set'] as Map<String, Object?>?) ?? const {};
    Predicate? pred(Object? o) =>
        o == null ? null : Predicate.fromJson(o as Map<String, Object?>);
    return ScenarioDef._(
      id: j['id']! as String,
      kind: (j['kind'] as String?) ?? 'guided',
      title: j['title']! as String,
      topic: (j['topic'] as String?) ?? '',
      briefing: (j['briefing'] as String?) ?? '',
      debrief: (j['debrief'] as String?) ?? '',
      milestone: (j['milestone'] as num?)?.toInt() ?? 1,
      preset: j['preset']! as String,
      overrides: Map<String, Object?>.from(
          (j['overrides'] as Map<Object?, Object?>?) ?? const {}),
      leverSet: {
        for (final e in set.entries) e.key: (e.value! as num).toDouble()
      },
      leverLock: [
        for (final e in (lev['lock'] as List<Object?>?) ?? const [])
          e! as String
      ],
      leverShow: [
        for (final e in (lev['show'] as List<Object?>?) ?? const [])
          e! as String
      ],
      timeLimit: (j['timeLimit'] as num?)?.toDouble() ?? 3600,
      objectives: [
        for (final o in (j['objectives']! as List<Object?>))
          () {
            final m = o! as Map<String, Object?>;
            return ObjectiveDef(
              id: m['id']! as String,
              text: m['text']! as String,
              when: pred(m['when']),
              holdFor: (m['holdFor'] as num?)?.toDouble() ?? 0,
              latch: (m['latch'] as bool?) ?? false,
              after: m['after'] as String?,
            );
          }(),
      ],
      hints: [
        for (final h in (j['hints'] as List<Object?>?) ?? const [])
          () {
            final m = h! as Map<String, Object?>;
            return HintDef(
                after: (m['after'] as num?)?.toDouble(),
                when: pred(m['when']),
                text: m['text']! as String);
          }(),
      ],
      events: [
        for (final e in (j['events'] as List<Object?>?) ?? const [])
          () {
            final m = Map<String, Object?>.from(e! as Map<Object?, Object?>);
            return EventDef((m.remove('at')! as num).toDouble(),
                m.remove('action')! as String, m);
          }(),
      ],
      scoring: Map<String, Object?>.from(
          (j['scoring'] as Map<Object?, Object?>?) ?? const {}),
    );
  }

  /// The configuration this scenario starts from: preset plus overrides.
  ColumnConfig buildConfig() => Presets.byId(preset).applyOverrides(overrides);

  /// Problems with metric paths and references (empty = valid).
  List<String> validate() {
    final p = <String>[];
    final paths = <String>[];
    for (final o in objectives) {
      o.when?.collectMetrics(paths);
      if (o.after != null && !objectives.any((x) => x.id == o.after))
        p.add('objective ${o.id}: unknown "after" ${o.after}');
    }
    for (final h in hints) {
      h.when?.collectMetrics(paths);
    }
    final ok = RegExp(
        r'^(time|steady|alarm\.count|safety\.(reliefLifted|levelViolationSeconds)|kpi\.\w+|answer\.\w+|lever\.[\w.]+|stage\[\d+\]\.\w+|loop\[[\w-]+\]\.(pv|sp|op|mode))$');
    for (final m in paths) {
      if (!ok.hasMatch(m)) p.add('unknown metric path "$m"');
    }
    try {
      buildConfig();
    } on Object catch (e) {
      p.add('config: $e');
    }
    return p;
  }

  /// Fault spec of an `injectFault` event.
  static FaultSpec faultOf(Map<String, Object?> data, double time) {
    final f =
        Map<String, Object?>.from(data['fault']! as Map<Object?, Object?>);
    return FaultSpec(
      type: FaultType.values.firstWhere((e) => e.name == f['type']),
      location: f['location'] == null
          ? const FaultLocation.whole()
          : FaultLocation.fromJson(f['location']! as Map<String, Object?>),
      severity: (f['severity']! as num).toDouble(),
      onset: time,
      ramp: (f['ramp'] as num?)?.toDouble() ?? 0,
      params: Map<String, Object?>.from(
          (f['params'] as Map<Object?, Object?>?) ?? const {}),
    );
  }
}
