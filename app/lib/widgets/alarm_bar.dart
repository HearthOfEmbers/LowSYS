import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';

Color alarmColor(ThemePalette p, AlarmPriority pr) => switch (pr) {
  AlarmPriority.high => p.alarm,
  AlarmPriority.medium => p.warn,
  AlarmPriority.low => p.info,
};

String stateLabel(AlarmState s) => switch (s) {
  AlarmState.unack => 'UNACK',
  AlarmState.acked => 'ACK',
  AlarmState.rtnUnack => 'RTN',
};

/// One-line alarm banner (ISA-18.2 style): the newest unacknowledged alarm of the highest priority, with the
/// count and an Ack button. Tap for the list. Collapses to nothing when no alarm is active.
class AlarmBar extends StatelessWidget {
  const AlarmBar({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (context, s, _) {
        final alarms = s?.alarms ?? const <Alarm>[];
        if (alarms.isEmpty) return const SizedBox.shrink();
        Alarm? top;
        for (final a in alarms) {
          if (a.state == AlarmState.unack) {
            top = a;
            break;
          }
        }
        final unack = alarms.where((a) => a.state == AlarmState.unack).length;
        final shown = top ?? alarms.first;
        final color = top == null ? p.inkFaint : alarmColor(p, shown.priority);
        return InkWell(
          onTap: () => showAlarmList(context),
          child: Container(
            height: 30,
            padding: const EdgeInsets.only(left: 10),
            color: color.withValues(alpha: top == null ? 0.12 : 0.28),
            child: Row(
              children: [
                Icon(Icons.notifications_active, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    top == null
                        ? '${alarms.length} active, all acknowledged'
                        : '${shown.id}  ${shown.message}',
                    overflow: TextOverflow.ellipsis,
                    style: t.type.label.style(
                      13,
                      p.ink,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  unack > 0
                      ? '$unack new / ${alarms.length}'
                      : '${alarms.length}',
                  style: t.type.number.style(12.5, p.inkMuted),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: sim.acknowledgeAll,
                  child: Text(
                    'ACK',
                    style: t.type.display.style(
                      13,
                      p.accent,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Alarm list with per-alarm acknowledge and the journal.
Future<void> showAlarmList(BuildContext context) {
  final sim = AppScope.of(context).sim;
  final t = LowsysThemeScope.of(context);
  final p = t.palette;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: ValueListenableBuilder<SimSnapshot?>(
          valueListenable: sim.snapshot,
          builder: (context, s, _) {
            final alarms = s?.alarms ?? const <Alarm>[];
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Alarms',
                          style: t.type.display.style(20, p.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: sim.acknowledgeAll,
                        child: const Text('Acknowledge all'),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Flexible(
                    child: alarms.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'No active alarms.',
                              style: t.type.label.style(14, p.inkMuted),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final a in alarms)
                                ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 8,
                                    height: 30,
                                    color: alarmColor(p, a.priority),
                                  ),
                                  title: Text(
                                    '${a.id}  ${a.message}',
                                    style: t.type.label.style(
                                      14,
                                      a.state == AlarmState.rtnUnack
                                          ? p.inkFaint
                                          : p.ink,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${stateLabel(a.state)} · since ${formatTimeOfDay(a.raisedAt)}',
                                    style: t.type.label.style(12.5, p.inkMuted),
                                  ),
                                  trailing: a.state == AlarmState.acked
                                      ? null
                                      : TextButton(
                                          onPressed: () =>
                                              sim.acknowledge(a.id),
                                          child: const Text('Ack'),
                                        ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

String formatTimeOfDay(double t) {
  final s = t.floor();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}';
}
