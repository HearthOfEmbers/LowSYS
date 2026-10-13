import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../l10n/strings.dart';
import '../theme/lowsys_theme.dart';
import 'drill_ui.dart';
import 'time_bar.dart';

/// Scenario list dialog (S3): pick a guided scenario, read the briefing (S4), start it.
Future<void> showScenarioList(BuildContext context, SimController sim) async {
  final t = LowsysThemeScope.of(context);
  final p = t.palette;
  final picked = await showDialog<ScenarioDef>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.scenariosTitle, style: t.type.display.style(20, p.ink)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in [...Scenarios.all, for (final id in Scenarios.allIds.where((x) => !Scenarios.ids.contains(x))) Scenarios.byId(id)])
                      ListTile(
                        title: Text(
                          '${d.id.split('_').first}  ${d.title}${d.isDrill ? '  ${S.drillTag}' : ''}',
                          style: t.type.display.style(16, p.accent),
                        ),
                        subtitle: Text(
                          '${d.topic}  ·  ${d.start == 'cold' ? S.coldStart : S.startsSteady}  ·  ${S.limit(formatClock(d.timeLimit))}',
                          style: t.type.label.style(13, p.inkMuted),
                        ),
                        trailing: Icon(Icons.chevron_right, color: p.inkMuted),
                        onTap: () => Navigator.pop(ctx, d),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(S.close),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await showScenarioBriefing(context, sim, picked);
}

/// Briefing dialog (S4) for [picked] with Start; shared by the scenario list and the Library.
Future<void> showScenarioBriefing(BuildContext context, SimController sim, ScenarioDef picked) async {
  final t = LowsysThemeScope.of(context);
  final p = t.palette;
  final attempts = picked.isDrill ? await sim.savedAttempts(picked.id) : const <Map<String, Object?>>[];
  if (!context.mounted) return;
  int? replaySeed;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text(picked.title, style: t.type.display.style(20, p.ink)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(picked.briefing, style: t.type.label.style(14.5, p.ink)),
              const SizedBox(height: 12),
              if (picked.isDrill)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${S.drillIntro} ${S.drillAttempts(picked.diagnosis?.attempts ?? 2)}',
                    style: t.type.label.style(13.5, p.warn),
                  ),
                ),
              Text(
                picked.isDrill ? S.whatToDo : S.goals,
                style: t.type.display.style(
                  13.5,
                  p.accent,
                  weight: FontWeight.w700,
                ),
              ),
              for (final o in picked.objectives)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${o.text}',
                    style: t.type.label.style(13.5, p.ink),
                  ),
                ),
              if (attempts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(S.savedAttempts,
                    style: t.type.label.style(13, p.inkMuted)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final a in attempts.reversed)
                    ChoiceChip(
                      key: ValueKey('drill-seed-${a['seed']}'),
                      label: Text('seed ${a['seed']}  ${a['score']} %', style: t.type.label.style(12.5, p.ink)),
                      selected: replaySeed == a['seed'],
                      onSelected: (v) => setS(() => replaySeed = v ? a['seed'] as int : null),
                    ),
                ]),
              ],
              const SizedBox(height: 8),
              Text(
                picked.isDrill
                    ? S.timeLimit(formatClock(picked.timeLimit))
                    : S.parTime(formatClock(picked.parTime), formatClock(picked.timeLimit)),
                style: t.type.label.style(12.5, p.inkMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(S.back),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(S.start),
        ),
      ],
    )),
  );
  if (go == true) await sim.startScenario(picked, seed: replaySeed);
}

/// Objective checklist, timer, answers, hints and Finish (S2a).
class ScenarioHud extends StatefulWidget {
  const ScenarioHud({super.key});
  @override
  State<ScenarioHud> createState() => _ScenarioHudState();
}

class _ScenarioHudState extends State<ScenarioHud> {
  bool?
  _open; // null: decide from the window height (collapsed on short windows)

  @override
  Widget build(BuildContext context) {
    final open = _open ?? MediaQuery.sizeOf(context).height >= 500;
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int>(
      valueListenable: sim.scenarioTick,
      builder: (context, _, __) {
        final r = sim.scenario;
        final def = sim.scenarioDef;
        if (r == null || def == null || sim.scoreCard != null)
          return const SizedBox.shrink();
        final nHints = r.hints.where((h) => h.unlocked && !h.taken).length;
        return SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 54, left: 6),
              child: Material(
                color: p.surface.withValues(alpha: 0.96),
                shape: Border.all(color: p.accent),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _open = !open),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  def.title,
                                  style: t.type.display.style(
                                    15,
                                    p.accent,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                open
                                    ? formatClock(r.elapsed)
                                    : '${formatClock(r.elapsed)}  ${r.objectives.where((o) => o.met).length}/${r.objectives.length}',
                                style: t.type.number.style(13, p.inkMuted),
                              ),
                              Text(
                                '  / ${formatClock(r.timeLimit)}',
                                key: const ValueKey('drill-timer'),
                                style: t.type.number.style(
                                  13,
                                  r.timeLimit - r.elapsed < 300 ? p.alarm : p.inkMuted,
                                ),
                              ),
                              Icon(
                                open ? Icons.expand_less : Icons.expand_more,
                                size: 20,
                                color: p.inkMuted,
                              ),
                            ],
                          ),
                        ),
                        if (open && def.isDrill)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Find the hidden fault. Attempts left: ${r.diagnosisAttemptsLeft}',
                              key: const ValueKey('drill-attempts'),
                              style: t.type.label.style(13, p.ink),
                            ),
                          ),
                        if (open && def.isDrill) _fieldChecks(sim, t),
                        if (open)
                          for (var i = 0; i < r.objectives.length; i++)
                            _objective(context, sim, def, r.objectives[i], t),
                        if (open && r.messages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              r.messages.last.text,
                              style: t.type.label.style(12.5, p.warn),
                            ),
                          ),
                        if (open)
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _hints(context, sim, r),
                                icon: Icon(
                                  Icons.lightbulb_outline,
                                  size: 18,
                                  color: p.warn,
                                ),
                                label: Text(
                                  'Hint${nHints == 0 ? '' : ' ($nHints new)'}',
                                  style: t.type.label.style(13, p.warn),
                                ),
                              ),
                              const Spacer(),
                              if (def.isDrill)
                                TextButton(
                                  key: const ValueKey('drill-diagnose'),
                                  onPressed: () => showDiagnoseDialog(context, sim),
                                  child: Text(
                                    'Diagnose',
                                    style: t.type.label.style(13.5, p.alarm, weight: FontWeight.w700),
                                  ),
                                ),
                              TextButton(
                                onPressed: sim.finishScenario,
                                child: Text(
                                  def.isDrill ? 'Give up' : 'Finish',
                                  style: t.type.label.style(
                                    13.5,
                                    p.accent,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Field checks of the LG sight glasses (the walk takes simulated time; the result compares with the transmitter).
  Widget _fieldChecks(SimController sim, LowsysTheme t) {
    final p = t.palette;
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (context, s, _) {
        final lines = <Widget>[];
        for (final g in const ['LG-101', 'LG-102']) {
          final fc = s?.fieldChecks.where((x) => x.gaugeTag == g).firstOrNull;
          final String status;
          if (fc == null) {
            status = '';
          } else if (fc.value == null) {
            status = 'walking, ${(fc.readyAt - (s?.time ?? 0)).clamp(0, 180).round()} s';
          } else {
            status = '${fc.value!.toStringAsFixed(0)} %';
          }
          lines.add(Row(children: [
            TextButton(
              key: ValueKey('drill-fc-$g'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: () => sim.fieldCheck(g),
              child: Text('Check $g', style: t.type.label.style(12.5, p.accent, weight: FontWeight.w700)),
            ),
            Text(status, key: ValueKey('drill-fc-result-$g'), style: t.type.number.style(12.5, p.inkMuted)),
          ]));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
      },
    );
  }

  Widget _objective(
    BuildContext context,
    SimController sim,
    ScenarioDef def,
    ObjectiveState o,
    LowsysTheme t,
  ) {
    final p = t.palette;
    final od = def.objectives.firstWhere((x) => x.id == o.id);
    final answer = od.answer;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            o.met ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: o.met ? p.ok : p.inkMuted,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.text,
                  style: t.type.label.style(12.5, o.met ? p.ok : p.ink),
                ),
                if (!o.met && o.holdFor > 0 && o.holdProgress > 0)
                  LinearProgressIndicator(
                    value: (o.holdProgress / o.holdFor).clamp(0.0, 1.0),
                    minHeight: 3,
                    color: p.accent,
                    backgroundColor: p.gridMajor,
                  ),
                if (!o.met && answer != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: () => _answer(context, sim, od, answer),
                      child: Text(
                        'Answer…',
                        style: t.type.label.style(
                          12.5,
                          p.accent,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _answer(
    BuildContext context,
    SimController sim,
    ObjectiveDef od,
    AnswerSpec spec,
  ) async {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final u = sim.units.value;
    final ctl = TextEditingController();
    int? choice;
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(od.text, style: t.type.label.style(15, p.ink)),
          content: switch (spec.type) {
            'number' => TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'Your answer',
                suffixText: u.symbol(spec.quantity),
              ),
            ),
            'choice' => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < spec.options.length; i++)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      choice == i
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: p.accent,
                    ),
                    title: Text(
                      spec.options[i],
                      style: t.type.label.style(14, p.ink),
                    ),
                    onTap: () => setS(() => choice = i),
                  ),
              ],
            ),
            _ => ValueListenableBuilder<int?>(
              valueListenable: sim.selectedStage,
              builder: (_, st, __) => Text(
                st == null
                    ? 'Tap a tray on the column or a corner of the staircase, then come back here.'
                    : 'Selected: ${st == 0
                          ? 'drum'
                          : st > (sim.snapshot.value?.layout.nTrays ?? 0)
                          ? 'sump'
                          : 'tray $st'}',
                style: t.type.label.style(14, p.ink),
              ),
            ),
          },
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                switch (spec.type) {
                  case 'number':
                    final v = double.tryParse(ctl.text.replaceAll(',', '.'));
                    if (v != null) Navigator.pop(ctx, u.toSI(spec.quantity, v));
                  case 'choice':
                    if (choice != null) Navigator.pop(ctx, choice!);
                  default:
                    final st = sim.selectedStage.value;
                    if (st != null) Navigator.pop(ctx, st);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final r = await sim.submitAnswer(od.id, result);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          r.correct
              ? 'Correct.'
              : (r.attemptsLeft > 0
                    ? 'Not quite. ${r.attemptsLeft} attempts left.'
                    : 'Not correct, and no attempts are left.'),
        ),
      ),
    );
  }

  void _hints(BuildContext context, SimController sim, ScenarioSnapshot r) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final cur = sim.scenario ?? r;
          return AlertDialog(
            title: Text('Hints', style: t.type.display.style(18, p.ink)),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (!cur.hints.any((h) => h.unlocked))
                    Text(
                      'No hints yet. They unlock as you work.',
                      style: t.type.label.style(14, p.ink),
                    ),
                  for (final h in cur.hints.where((h) => h.unlocked))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: h.taken
                          ? Text(
                              '• ${h.text}',
                              style: t.type.label.style(14, p.ink),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Hint ${h.index + 1} is ready.',
                                    style: t.type.label.style(14, p.inkMuted),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await sim.takeHint(h.index);
                                    setS(() {});
                                  },
                                  child: Text(
                                    h.cost > 0
                                        ? 'Show (costs ${(100 * h.cost).toStringAsFixed(0)} points)'
                                        : 'Show',
                                    style: t.type.label.style(
                                      13.5,
                                      p.warn,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Debrief dialog (S5) with the score breakdown; shown once the scenario is finished.
class DebriefHost extends StatefulWidget {
  const DebriefHost({super.key});
  @override
  State<DebriefHost> createState() => _DebriefHostState();
}

class _DebriefHostState extends State<DebriefHost> {
  ScoreCard? _shown;

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    return ValueListenableBuilder<int>(
      valueListenable: sim.scenarioTick,
      builder: (context, _, __) {
        final card = sim.scoreCard;
        if (card != null && !identical(card, _shown)) {
          _shown = card;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _show(context, sim, card);
          });
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _show(BuildContext context, SimController sim, ScoreCard c) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final drill = sim.scenarioDef?.isDrill ?? false;
    final w = sim.scenarioDef?.guidedWeights;
    String pts(double v) => '${(100 * v).toStringAsFixed(0)} pts';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${sim.scenarioDef?.title ?? 'Scenario'} — ${c.score} / 100',
          style: t.type.display.style(19, p.ink),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.completed ? (drill ? 'Diagnosed.' : 'All goals met.') : (drill ? 'Not diagnosed.' : 'Not all goals met.'),
                  style: t.type.display.style(15, c.completed ? p.ok : p.warn),
                ),
                const SizedBox(height: 8),
                for (final row in [
                  (
                    (drill ? 'Category' : 'Goals') + '${w == null ? '' : ' (of ${(100 * w.objectives).round()})'}',
                    c.objectives,
                  ),
                  (
                    'Time${w == null ? '' : ' (of ${(100 * w.time).round()})'}',
                    c.time,
                  ),
                  (
                    'Safety${w == null ? '' : ' (of ${(100 * w.safety).round()})'}',
                    c.safety,
                  ),
                  (
                    (drill ? 'Location' : 'Product quality') + '${w == null ? '' : ' (of ${(100 * w.quality).round()})'}',
                    c.quality,
                  ),
                  if (c.hintCost > 0) ('Hints', -c.hintCost),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.$1,
                            style: t.type.label.style(14, p.ink),
                          ),
                        ),
                        Text(
                          pts(row.$2),
                          style: t.type.number.style(14, p.accent),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(c.debriefText, style: t.type.label.style(14, p.ink)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final d = sim.scenarioDef;
              if (d != null) sim.startScenario(d);
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              sim.leaveScenario();
            },
            child: const Text('Back to sandbox'),
          ),
        ],
      ),
    );
  }
}
