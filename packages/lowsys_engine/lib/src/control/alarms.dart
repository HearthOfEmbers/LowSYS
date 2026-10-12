import '../snapshot/sim_snapshot.dart';

/// One alarm definition (PHYSICS.md 10.8). [condition] receives whether the alarm is currently active so it
/// can apply its deadband (raise above the limit, clear below limit - deadband).
class AlarmDef {
  final String id;
  final AlarmPriority priority;
  final double onDelay, offDelay;
  final String message;
  final bool Function(bool active) condition;

  /// SHED alarms clear only when acknowledged and the condition is false.
  final bool needsAckToClear;
  AlarmDef(this.id, this.priority, this.onDelay, this.offDelay, this.message,
      this.condition,
      {this.needsAckToClear = false});
}

class JournalEntry {
  final double time;
  final String text;

  /// Alarm id for raise, clear and acknowledge entries.
  final String? alarmId;
  const JournalEntry(this.time, this.text, [this.alarmId]);
}

class _AlarmRt {
  AlarmState? state; // null = NORMAL
  double onTimer = 0, offTimer = 0;
  double raisedAt = 0, changedAt = 0;
  bool active = false; // condition level after delays
}

/// ISA-18.2 alarm states with on/off delays (PHYSICS.md 10.8): NORMAL, UNACK, ACKED, RTN-UNACK.
class AlarmManager {
  final List<AlarmDef> defs = [];
  final Map<String, _AlarmRt> _rt = {};
  final List<JournalEntry> journal = [];
  static const int maxJournal = 2000;

  void add(AlarmDef d) {
    defs.add(d);
    _rt[d.id] = _AlarmRt();
  }

  /// Operator actions and mode changes go into the same journal.
  void log(double t, String s) => _log(t, s);

  void _log(double t, String s, [String? id]) {
    journal.add(JournalEntry(t, s, id));
    if (journal.length > maxJournal) journal.removeAt(0);
  }

  /// Evaluate all alarms for an interval [dt] ending at [t].
  void update(double dt, double t) {
    for (final d in defs) {
      final r = _rt[d.id]!;
      final cond = d.condition(r.active);
      if (cond) {
        r.offTimer = 0;
        r.onTimer += dt;
        if (!r.active && r.onTimer >= d.onDelay) {
          r.active = true;
          if (r.state == AlarmState.rtnUnack || r.state == null) {
            r.state = AlarmState.unack;
            r.raisedAt = t;
            r.changedAt = t;
            _log(t, 'RAISED ${d.id}', d.id);
          }
        }
      } else {
        r.onTimer = 0;
        if (r.active) {
          r.offTimer += dt;
          if (r.offTimer >= d.offDelay &&
              !(d.needsAckToClear && r.state == AlarmState.unack)) {
            r.active = false;
            r.offTimer = 0;
            if (r.state == AlarmState.unack) {
              r.state = AlarmState.rtnUnack;
              r.changedAt = t;
              _log(t, 'CLEARED (unacknowledged) ${d.id}', d.id);
            } else if (r.state == AlarmState.acked) {
              r.state = null;
              r.changedAt = t;
              _log(t, 'CLEARED ${d.id}', d.id);
            }
          }
        }
      }
    }
  }

  void acknowledge(String id, double t) {
    final r = _rt[id];
    if (r == null || r.state == null) return;
    if (r.state == AlarmState.unack) {
      r.state = AlarmState.acked;
      r.changedAt = t;
      _log(t, 'ACK $id', id);
    } else if (r.state == AlarmState.rtnUnack) {
      r.state = null;
      r.changedAt = t;
      _log(t, 'ACK (returned) $id', id);
    }
  }

  void acknowledgeAll(double t) {
    for (final d in defs) {
      acknowledge(d.id, t);
    }
  }

  /// Active alarms not NORMAL, sorted by priority then newest first (PHYSICS.md 10.8).
  List<Alarm> active() {
    final out = <Alarm>[];
    for (final d in defs) {
      final r = _rt[d.id]!;
      final st = r.state;
      if (st == null) continue;
      out.add(Alarm(
          d.id, d.message, d.priority, st != AlarmState.unack, r.raisedAt,
          state: st, changedAt: r.changedAt));
    }
    out.sort((a, b) {
      final p = b.priority.index.compareTo(a.priority.index);
      if (p != 0) return p;
      return b.raisedAt.compareTo(a.raisedAt);
    });
    return out;
  }

  bool isActive(String id) => _rt[id]?.state != null;

  /// Number of alarms that are not NORMAL.
  int get activeCount {
    var n = 0;
    for (final r in _rt.values) {
      if (r.state != null) n++;
    }
    return n;
  }

  void reset() {
    for (final r in _rt.values) {
      r.state = null;
      r.onTimer = 0;
      r.offTimer = 0;
      r.active = false;
    }
  }

  Map<String, Object?> toJson() => {
        'rt': {
          for (final e in _rt.entries)
            e.key: {
              's': e.value.state?.index,
              'on': e.value.onTimer,
              'off': e.value.offTimer,
              'raised': e.value.raisedAt,
              'changed': e.value.changedAt,
              'active': e.value.active,
            }
        },
        'journal': [
          for (final j in journal) [j.time, j.text, j.alarmId]
        ],
      };

  void loadJson(Map<String, Object?> j) {
    final rt = j['rt']! as Map<String, Object?>;
    for (final e in rt.entries) {
      final r = _rt[e.key];
      if (r == null) continue;
      final m = e.value! as Map<String, Object?>;
      r.state =
          m['s'] == null ? null : AlarmState.values[(m['s']! as num).toInt()];
      r.onTimer = (m['on']! as num).toDouble();
      r.offTimer = (m['off']! as num).toDouble();
      r.raisedAt = (m['raised']! as num).toDouble();
      r.changedAt = (m['changed']! as num).toDouble();
      r.active = m['active']! as bool;
    }
    journal.clear();
    for (final e in (j['journal']! as List<Object?>)) {
      final l = e! as List<Object?>;
      journal.add(JournalEntry((l[0]! as num).toDouble(), l[1]! as String,
          l.length > 2 ? l[2] as String? : null));
    }
  }
}
