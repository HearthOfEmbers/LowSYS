import 'package:meta/meta.dart';

import '../config/column_config.dart';
import '../config/presets.dart';
import '../core/ids.dart';
import '../core/quantity.dart';
import '../faults/fault_spec.dart';
import '../snapshot/sim_snapshot.dart' show ScenarioKind;
import 'predicate.dart';
import 'scoring.dart';

/// How a numeric, choice or stage answer is checked (ENGINE_API.md 11.1).
@immutable
class AnswerSpec {
  /// `number`, `choice` or `stage`.
  final String type;
  final double? correctNumber;
  final int? correctIndex;
  final List<int> correctStages;
  final List<String> options;
  final double tolerance;
  final bool relative;
  final Quantity quantity;
  final int attempts;
  const AnswerSpec({
    required this.type,
    this.correctNumber,
    this.correctIndex,
    this.correctStages = const [],
    this.options = const [],
    this.tolerance = 0,
    this.relative = false,
    this.quantity = Quantity.dimensionless,
    this.attempts = 3,
  });

  factory AnswerSpec.fromJson(Map<String, Object?> j) => AnswerSpec(
        type: j['type']! as String,
        correctNumber:
            j['type'] == 'number' ? (j['correct']! as num).toDouble() : null,
        correctIndex:
            j['type'] == 'choice' ? (j['correct']! as num).toInt() : null,
        correctStages: j['type'] == 'stage'
            ? [
                for (final v in j['correct']! as List<Object?>)
                  (v! as num).toInt()
              ]
            : const [],
        options: [
          for (final v in (j['options'] as List<Object?>?) ?? const [])
            v! as String
        ],
        tolerance: (j['tolerance'] as num?)?.toDouble() ?? 0,
        relative: j['toleranceKind'] == 'rel',
        quantity: j['quantity'] == null
            ? Quantity.dimensionless
            : Quantity.values.firstWhere((q) => q.name == j['quantity']),
        attempts: (j['attempts'] as num?)?.toInt() ?? 3,
      );

  /// SI value of a number answer typed in display units must be passed already converted.
  bool isCorrect(Object answer) {
    switch (type) {
      case 'number':
        if (answer is! num) return false;
        final c = correctNumber!;
        final tol = relative ? tolerance * c.abs() : tolerance;
        return (answer.toDouble() - c).abs() <= tol + 1e-12;
      case 'choice':
        return answer is num && answer.toInt() == correctIndex;
      case 'stage':
        return answer is num && correctStages.contains(answer.toInt());
    }
    return false;
  }
}

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
  final double weight;

  /// Instead of `when`: achieved (and latched) by a correct answer.
  final AnswerSpec? answer;
  const ObjectiveDef(
      {required this.id,
      required this.text,
      this.when,
      this.holdFor = 0,
      this.latch = false,
      this.after,
      this.weight = 1,
      this.answer});
}

@immutable
class HintDef {
  final double? after;
  final Predicate? when;
  final String text;

  /// Fraction of the total score deducted when the hint is taken.
  final double cost;
  const HintDef({this.after, this.when, required this.text, this.cost = 0});
}

@immutable
class EventDef {
  final String? id;

  /// Fixed time, random window, or condition.
  final double? at;
  final List<double>? atRandom;
  final Predicate? when;
  final String action;
  final Map<String, Object?> data;
  final String? text;
  const EventDef(
      {this.id,
      this.at,
      this.atRandom,
      this.when,
      required this.action,
      required this.data,
      this.text});
}

/// One fault a drill may draw (ENGINE_API.md 11.2).
@immutable
class CandidateDef {
  final String id;
  final double weight;
  /// Null for a candidate without a fault (M8: an operating condition, e.g. H7 `near_flood`).
  final FaultType? faultType;
  final FaultLocation location;
  final Map<String, Object?> params;
  final double severityLo, severityHi, ramp;
  final String answerCategory, answerLocation;
  final String? answerMode;
  final List<({String tag, List<String> modes})> protect;
  final String debrief;
  const CandidateDef({
    required this.id,
    required this.weight,
    required this.faultType,
    required this.location,
    required this.params,
    required this.severityLo,
    required this.severityHi,
    required this.ramp,
    required this.answerCategory,
    required this.answerLocation,
    this.answerMode,
    this.protect = const [],
    this.debrief = '',
  });
}

@immutable
class DiagnosisDef {
  final List<String> categories, locations, modes;
  final int attempts;
  const DiagnosisDef(
      {this.categories = const [],
      this.locations = const [],
      this.modes = const [],
      this.attempts = 2});
}

/// A scenario or drill (ENGINE_API.md 11.1, 11.2).
class ScenarioDef {
  final String id, title, topic, briefing, debrief;
  final ScenarioKind kind;
  final int milestone;
  final PresetId preset;
  final Map<String, Object?> overrides;

  /// `steady` or `cold`.
  final String start;
  final bool noise, badPvShed;

  /// `model` or `plant`.
  final String view;
  final Map<LeverId, double> leverSet;
  final List<LeverId> leverLock, leverShow;
  final Map<LoopTag, Map<String, Object?>> loops;
  final double timeLimit, parTime;
  final List<ObjectiveDef> objectives;
  final List<HintDef> hints;
  final List<EventDef> events;
  final Map<String, Object?> scoring;
  final List<CandidateDef> candidates;
  final List<double> onsetWindow;
  final Predicate? offSpec;
  final double offSpecHold;
  final DiagnosisDef? diagnosis;

  /// The JSON this definition was parsed from (saved with the simulator state).
  final Map<String, Object?> source;

  ScenarioDef._({
    required this.source,
    required this.id,
    required this.kind,
    required this.title,
    required this.topic,
    required this.briefing,
    required this.debrief,
    required this.milestone,
    required this.preset,
    required this.overrides,
    required this.start,
    required this.noise,
    required this.view,
    required this.badPvShed,
    required this.leverSet,
    required this.leverLock,
    required this.leverShow,
    required this.loops,
    required this.timeLimit,
    required this.parTime,
    required this.objectives,
    required this.hints,
    required this.events,
    required this.scoring,
    required this.candidates,
    required this.onsetWindow,
    required this.offSpec,
    required this.offSpecHold,
    required this.diagnosis,
  });

  bool get isDrill => kind == ScenarioKind.drill;

  factory ScenarioDef.fromJson(Map<String, Object?> j) {
    final lev = (j['levers'] as Map<String, Object?>?) ?? const {};
    final set = (lev['set'] as Map<String, Object?>?) ?? const {};
    Predicate? pred(Object? o) =>
        o == null ? null : Predicate.fromJson(o as Map<String, Object?>);
    final timeLimit = (j['timeLimit'] as num?)?.toDouble() ?? 3600;
    final kind = (j['kind'] as String?) == 'drill'
        ? ScenarioKind.drill
        : ScenarioKind.guided;
    final off = j['offSpec'] as Map<String, Object?>?;
    final diag = j['diagnosis'] as Map<String, Object?>?;
    return ScenarioDef._(
      source: j,
      id: j['id']! as String,
      kind: kind,
      title: j['title']! as String,
      topic: (j['topic'] as String?) ?? '',
      briefing: (j['briefing'] as String?) ?? '',
      debrief: (j['debrief'] as String?) ?? '',
      milestone: (j['milestone'] as num?)?.toInt() ?? 1,
      preset: j['preset']! as String,
      overrides: Map<String, Object?>.from(
          (j['overrides'] as Map<Object?, Object?>?) ?? const {}),
      start: (j['start'] as String?) ?? 'steady',
      noise: (j['noise'] as bool?) ?? false,
      view: (j['view'] as String?) ?? 'model',
      badPvShed: (j['badPvShed'] as bool?) ?? true,
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
      loops: {
        for (final e
            in ((j['loops'] as Map<Object?, Object?>?) ?? const {}).entries)
          e.key! as String:
              Map<String, Object?>.from(e.value! as Map<Object?, Object?>)
      },
      timeLimit: timeLimit,
      parTime: (j['parTime'] as num?)?.toDouble() ?? 0.25 * timeLimit,
      objectives: [
        for (final o in ((j['objectives'] as List<Object?>?) ?? const []))
          () {
            final m = o! as Map<String, Object?>;
            return ObjectiveDef(
              id: m['id']! as String,
              text: m['text']! as String,
              when: pred(m['when']),
              holdFor: (m['holdFor'] as num?)?.toDouble() ?? 0,
              latch: (m['latch'] as bool?) ?? (m['answer'] != null),
              after: m['after'] as String?,
              weight: (m['weight'] as num?)?.toDouble() ?? 1,
              answer: m['answer'] == null
                  ? null
                  : AnswerSpec.fromJson(m['answer']! as Map<String, Object?>),
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
                text: m['text']! as String,
                cost: (m['cost'] as num?)?.toDouble() ??
                    (kind == ScenarioKind.drill ? 0.03 : 0));
          }(),
      ],
      events: [
        for (final e in (j['events'] as List<Object?>?) ?? const [])
          () {
            final m = Map<String, Object?>.from(e! as Map<Object?, Object?>);
            final at = m.remove('at') as num?;
            final rnd = m.remove('atRandom') as List<Object?>?;
            final when = m.remove('when');
            final id = m.remove('id') as String?;
            final text = m.remove('text') as String?;
            return EventDef(
                id: id,
                at: at?.toDouble(),
                atRandom: rnd == null
                    ? null
                    : [for (final v in rnd) (v! as num).toDouble()],
                when: pred(when),
                action: m.remove('action')! as String,
                data: m,
                text: text);
          }(),
      ],
      scoring: Map<String, Object?>.from(
          (j['scoring'] as Map<Object?, Object?>?) ?? const {}),
      candidates: [
        for (final c in (j['candidates'] as List<Object?>?) ?? const [])
          _candidate(c! as Map<String, Object?>),
      ],
      onsetWindow: [
        for (final v in (j['onsetWindow'] as List<Object?>?) ?? const [])
          (v! as num).toDouble()
      ],
      offSpec: pred(off?['when']),
      offSpecHold: (off?['holdFor'] as num?)?.toDouble() ?? 0,
      diagnosis: diag == null
          ? null
          : DiagnosisDef(categories: [
              for (final v in diag['categories']! as List<Object?>) v! as String
            ], locations: [
              for (final v in diag['locations']! as List<Object?>) v! as String
            ], modes: [
              for (final v in (diag['modes'] as List<Object?>?) ?? const [])
                v! as String
            ], attempts: (diag['attempts'] as num?)?.toInt() ?? 2),
    );
  }

  static CandidateDef _candidate(Map<String, Object?> c) {
    final f = (c['fault'] as Map<String, Object?>?) ?? const <String, Object?>{};
    final noFault = c['fault'] == null;
    final sr = f['severityRange'] as List<Object?>?;
    final sv = (f['severity'] as num?)?.toDouble();
    final ans = c['answer']! as Map<String, Object?>;
    return CandidateDef(
      id: c['id']! as String,
      weight: (c['weight'] as num?)?.toDouble() ?? 1,
      faultType: noFault ? null : FaultType.values.firstWhere((e) => e.name == f['type']),
      location: f['location'] == null
          ? const FaultLocation.whole()
          : FaultLocation.fromJson(f['location']! as Map<String, Object?>),
      params: Map<String, Object?>.from(
          (f['params'] as Map<Object?, Object?>?) ?? const {}),
      severityLo: sr == null ? sv ?? 1 : (sr[0]! as num).toDouble(),
      severityHi: sr == null ? sv ?? 1 : (sr[1]! as num).toDouble(),
      ramp: (f['ramp'] as num?)?.toDouble() ?? 0,
      answerCategory: ans['category']! as String,
      answerLocation: ans['location']! as String,
      answerMode: ans['mode'] as String?,
      protect: [
        for (final p in (c['protect'] as List<Object?>?) ?? const [])
          (
            tag: (p! as Map<String, Object?>)['tag']! as String,
            modes: [
              for (final m in (p['modes']! as List<Object?>)) m! as String
            ],
          ),
      ],
      debrief: (c['debrief'] as String?) ?? '',
    );
  }

  /// The configuration this scenario starts from: preset plus overrides.
  ColumnConfig buildConfig() => Presets.byId(preset).applyOverrides(overrides);

  static final RegExp _leverPattern = RegExp(
      r'^(feedFlow|feedZ\.\w+|feedQ|feedT|feedVaporFraction|feedStage|refluxFlow|refluxRatio|refluxMode|refluxSubcooling|boilup|reboilerDuty|pTop|condenserType|drumLevelSp|sumpLevelSp|distillateValve|bottomsValve|nTrays|murphree|trayType\.\w+|hydraulics|cwInletT|cwMaxFlow|steamHeaderP|reboilerType|tsInletValve|antifoam|inertVent|tc101Enable|tc101Tray|tc101Sp|tier|noise|crudeRate|cot|topTSp|drawRate\.\w+|paDuty|steam\.\w+|drumTSp|view|badPvShed|bypass\.[\w-]+|feedFlowOp|refluxOp|boilupOp|alpha|internals)$');
  static final RegExp _loopPattern = RegExp(r'^(FC|LC|PC|TC)-\d+$');
  static const Set<String> _instrumentKinds = {
    'bias',
    'drift',
    'stuck',
    'signalLossLow',
    'signalLossHigh',
    'signalLoss',
    'plugged',
    'spiking',
    'coated'
  };
  static const Set<String> _valveKinds = {'stuck', 'failOpen', 'failClosed'};
  static final RegExp _templatePattern =
      RegExp(r'\{([\w\[\].:\-]+?)(?::([0-9.]+|time))?\}');

  /// Diagnosis vocabulary (ENGINE_API.md 11.2, with the M6 additions).
  static const Set<String> diagnosisCategories = {
    'cooling', 'fouling', 'inerts', 'foaming', 'trayDamage', 'instrument', 'valve', 'feedUpset', 'steam',
    'thermosyphon', 'maldistribution', 'none', 'restriction', 'condensate', 'pump', 'packingDamage', 'flooding',
    'steamLoss', 'pumparound', 'furnace',
  };
  static const Set<String> diagnosisLocations = {
    'condenser', 'reboiler', 'rectifying', 'stripping', 'feed', 'instrument:*', 'valve:*', 'packedBed', 'column',
    'steamSupply', 'tsInletLine', 'tsOutletLine', 'refluxPump', 'bed:*', 'steam:*', 'pumparound', 'furnace',
  };

  /// True when [path] is a valid template variable of this scenario.
  bool _validTemplateVar(String v) {
    if (metricPathPattern.hasMatch(v)) return true;
    if (v.startsWith('fault.')) {
      return isDrill &&
          const {'tag', 'mode', 'severity', 'sign', 'magnitude', 'onset'}
              .contains(v.substring(6));
    }
    if (v.startsWith('result.')) {
      return isDrill &&
          const {
            'offSpecTime',
            'protectTime',
            'diagnosisTime',
            'firstFlaggedCheck'
          }.contains(v.substring(7));
    }
    return false;
  }

  /// Problems with metric paths, references and parameters (empty = valid).
  List<String> validate() {
    final p = <String>[];
    final paths = <String>[];
    for (final o in objectives) {
      o.when?.collectMetrics(paths);
      if (o.after != null && !objectives.any((x) => x.id == o.after)) {
        p.add('objective ${o.id}: unknown "after" ${o.after}');
      }
      if (o.when == null && o.answer == null) {
        p.add('objective ${o.id}: needs "when" or "answer"');
      }
    }
    for (final h in hints) {
      h.when?.collectMetrics(paths);
    }
    for (final e in events) {
      e.when?.collectMetrics(paths);
    }
    offSpec?.collectMetrics(paths);
    for (final m in paths) {
      if (!metricPathPattern.hasMatch(m)) p.add('unknown metric path "$m"');
      final lm = RegExp(r'^lever\.(.+)$').firstMatch(m);
      if (lm != null && !_leverPattern.hasMatch(lm.group(1)!)) {
        p.add('unknown lever "${lm.group(1)}" in metric $m');
      }
      final lp = RegExp(r'^loop\[([\w-]+)\]').firstMatch(m);
      if (lp != null && !_loopPattern.hasMatch(lp.group(1)!)) {
        p.add('unknown loop "${lp.group(1)}" in metric $m');
      }
    }
    for (final k in leverSet.keys.followedBy(leverLock).followedBy(leverShow)) {
      if (!_leverPattern.hasMatch(k)) p.add('unknown lever "$k"');
    }
    for (final t in loops.keys) {
      if (!_loopPattern.hasMatch(t)) p.add('unknown loop "$t"');
    }
    for (final e in events) {
      switch (e.action) {
        case 'setLever':
          final l = e.data['lever'];
          if (l is! String || !_leverPattern.hasMatch(l))
            p.add('event: unknown lever "$l"');
          if (e.data['value'] == null && e.data['delta'] == null)
            p.add('event setLever needs value or delta');
        case 'loadPreset':
          if (!Presets.ids.contains('${e.data['preset']}'))
            p.add('event: unknown preset "${e.data['preset']}"');
        case 'setLoopMode':
          if (!_loopPattern.hasMatch('${e.data['tag']}'))
            p.add('event: unknown loop "${e.data['tag']}"');
        case 'setSp':
          if (!_loopPattern.hasMatch('${e.data['tag']}'))
            p.add('event: unknown loop "${e.data['tag']}"');
          if (e.data['value'] == null && e.data['delta'] == null)
            p.add('event setSp needs value or delta');
        case 'injectFault':
          final f = e.data['fault'];
          if (f is! Map) {
            p.add('event injectFault needs a fault');
          } else {
            p.addAll(_checkFault(Map<String, Object?>.from(f)));
          }
        case 'clearFault':
          final r = e.data['faultRef'];
          if (!events.any((x) => x.id == r))
            p.add('event clearFault: unknown faultRef "$r"');
        case 'message':
          if (e.text == null) p.add('event message needs text');
        default:
          p.add('unknown event action "${e.action}"');
      }
    }
    if (isDrill) {
      if (candidates.isEmpty ||
          candidates.fold<double>(0, (s, c) => s + c.weight) <= 0) {
        p.add('drill needs candidates with a positive total weight');
      }
      if (onsetWindow.length != 2) {
        p.add('drill needs onsetWindow [lo, hi]');
      } else if (onsetWindow[1] + 3600 > timeLimit) {
        p.add('onsetWindow[1] + 3600 exceeds timeLimit');
      }
      for (final c in candidates) {
        final kind = c.params['kind'];
        if (c.faultType == null) continue;
        if (c.faultType == FaultType.instrument ||
            c.faultType == FaultType.transmitter) {
          if (kind is! String || !_instrumentKinds.contains(kind))
            p.add('candidate ${c.id}: bad instrument fault kind "$kind"');
        } else if (c.faultType == FaultType.valve) {
          if (kind is! String || !_valveKinds.contains(kind))
            p.add('candidate ${c.id}: bad valve fault kind "$kind"');
        }
        if (c.weight < 0) p.add('candidate ${c.id}: negative weight');
      }
      final dg = diagnosis;
      if (dg == null) {
        p.add('drill needs a diagnosis block');
      } else {
        for (final c in dg.categories) {
          if (!diagnosisCategories.contains(c)) p.add('unknown diagnosis category "$c"');
        }
        for (final l in dg.locations) {
          if (!diagnosisLocations.contains(l) && !diagnosisLocations.contains('${l.split(':').first}:*')) p.add('unknown diagnosis location "$l"');
        }
        for (final c in candidates) {
          if (!dg.categories.contains(c.answerCategory)) {
            p.add('candidate ${c.id}: answer category "${c.answerCategory}" is not offered');
          }
          final ok = dg.locations.any((l) =>
              l == c.answerLocation ||
              (l.endsWith(':*') && c.answerLocation.startsWith(l.substring(0, l.length - 1))));
          if (!ok) p.add('candidate ${c.id}: answer location "${c.answerLocation}" is not offered');
        }
      }
    }
    if (!const {'model', 'plant', 'plantCalc'}.contains(view)) p.add('unknown view "$view"');
    // F17 and F18 act on the thermosyphon loop only (ENGINE_API.md 9)
    const tsFaults = {'tsInletRestriction', 'tsOutletRestriction'};
    final usesTs = candidates.any((c) => tsFaults.contains(c.faultType?.name)) ||
        events.any((e) =>
            e.action == 'injectFault' &&
            e.data['fault'] is Map &&
            tsFaults.contains((e.data['fault'] as Map)['type']));
    if (usesTs) {
      final lev = (leverSet['reboilerType'] ?? 0) >= 0.5;
      if (!lev) p.add('F17/F18 need a thermosyphon reboiler (levers.set reboilerType 1)');
    }
    // templates (M8: a drill with a no-fault candidate must not use {fault.*} in its drill-level or that candidate's debrief)
    final hasNoFault = candidates.any((c) => c.faultType == null);
    for (final text in [debrief, ...candidates.map((c) => c.debrief)]) {
      if (hasNoFault && (text == debrief || candidates.any((c) => c.faultType == null && c.debrief == text))) {
        if (text.contains('{fault.')) p.add('a debrief that applies to a no-fault candidate uses {fault.*}');
      }
      for (final m in _templatePattern.allMatches(text)) {
        final v = m.group(1)!;
        if (!_validTemplateVar(v)) p.add('unknown template variable "{$v}"');
      }
    }
    try {
      buildConfig();
    } on Object catch (e) {
      p.add('config: $e');
    }
    return p;
  }

  List<String> _checkFault(Map<String, Object?> f) {
    final p = <String>[];
    final names = FaultType.values.map((e) => e.name).toSet();
    if (!names.contains(f['type'])) p.add('unknown fault type "${f['type']}"');
    final params = (f['params'] as Map?) ?? const {};
    final kind = params['kind'];
    if (f['type'] == 'valve' && !_valveKinds.contains(kind))
      p.add('bad valve fault kind "$kind"');
    if ((f['type'] == 'instrument' || f['type'] == 'transmitter') &&
        !_instrumentKinds.contains(kind)) {
      p.add('bad instrument fault kind "$kind"');
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

  /// Scoring weights of a guided scenario.
  ScoringWeights get guidedWeights {
    double w(String k, double d) => (scoring[k] as num?)?.toDouble() ?? d;
    return ScoringWeights(
        objectives: w('objectives', 0.6),
        time: w('time', 0.2),
        safety: w('safety', 0.1),
        quality: w('quality', 0.1));
  }

  /// Scoring constants of a drill.
  DrillScoringWeights get drillWeights {
    double w(String k, double d) => (scoring[k] as num?)?.toDouble() ?? d;
    final b = (scoring['bonus'] as Map?) ?? const {};
    return DrillScoringWeights(
        category: w('category', 0.5),
        location: w('location', 0.2),
        time: w('time', 0.2),
        safety: w('safety', 0.1),
        timeFull: w('timeFull', 600),
        timeZero: w('timeZero', 3600),
        wrongPenalty: w('wrongPenalty', 0.1),
        protectBonus: (b['protectBeforeOffSpec'] as num?)?.toDouble() ?? 0,
        modeBonus: (b['mode'] as num?)?.toDouble() ?? 0);
  }
}
