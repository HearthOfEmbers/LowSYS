import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';
import 'time_bar.dart';

/// Scenario list dialog (S3, reduced): pick a guided scenario, read the briefing (S4), start it.
Future<void> showScenarioList(BuildContext context, SimController sim) async {
  final t = LowsysThemeScope.of(context);
  final p = t.palette;
  final picked = await showDialog<ScenarioDef>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Guided scenarios', style: t.type.display.style(20, p.ink)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final d in ScenarioLibrary.all)
                  ListTile(
                    title: Text('${d.id.split('_').first}  ${d.title}', style: t.type.display.style(16, p.accent)),
                    subtitle: Text(d.topic, style: t.type.label.style(13, p.inkMuted)),
                    trailing: Icon(Icons.chevron_right, color: p.inkMuted),
                    onTap: () => Navigator.pop(ctx, d),
                  ),
              ]),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))),
          ]),
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(picked.title, style: t.type.display.style(20, p.ink)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(picked.briefing, style: t.type.label.style(14.5, p.ink)),
            const SizedBox(height: 12),
            Text('GOALS', style: t.type.display.style(13.5, p.accent, weight: FontWeight.w700)),
            for (final o in picked.objectives) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${o.text}', style: t.type.label.style(13.5, p.ink))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
      ],
    ),
  );
  if (go == true) await sim.startScenario(picked);
}

/// Objective checklist, timer, hints and Finish (S2a).
class ScenarioHud extends StatelessWidget {
  const ScenarioHud({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int>(
      valueListenable: sim.scenarioTick,
      builder: (context, _, __) {
        final r = sim.scenario;
        final def = sim.scenarioDef;
        if (r == null || def == null || sim.scoreCard != null) return const SizedBox.shrink();
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
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(def.title, style: t.type.display.style(15, p.accent, weight: FontWeight.w700))),
                        Text(formatClock(r.elapsed), style: t.type.number.style(13, p.inkMuted)),
                      ]),
                      for (final o in r.objectives)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(o.achieved ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: o.achieved ? p.ok : p.inkMuted),
                            const SizedBox(width: 4),
                            Expanded(child: Text(o.text, style: t.type.label.style(12.5, o.achieved ? p.ok : p.ink))),
                          ]),
                        ),
                      Row(children: [
                        TextButton.icon(
                          onPressed: () => _hints(context, sim),
                          icon: Icon(Icons.lightbulb_outline, size: 18, color: p.warn),
                          label: Text('Hint${r.unlockedHints.isEmpty ? '' : ' (${r.unlockedHints.length})'}', style: t.type.label.style(13, p.warn)),
                        ),
                        const Spacer(),
                        TextButton(onPressed: sim.finishScenario, child: Text('Finish', style: t.type.label.style(13.5, p.accent, weight: FontWeight.w700))),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _hints(BuildContext context, SimController sim) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final h = sim.scenario?.unlockedHints ?? const <String>[];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hints', style: t.type.display.style(18, p.ink)),
        content: Text(h.isEmpty ? 'No hints yet. They unlock as you work.' : h.map((e) => '• $e').join('\n\n'), style: t.type.label.style(14, p.ink)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
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
    String pct(double v) => '${(100 * v).round()} %';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${sim.scenarioDef?.title ?? 'Scenario'} — ${c.total.round()} / 100', style: t.type.display.style(19, p.ink)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(c.completed ? 'All goals met.' : 'Not all goals met.', style: t.type.display.style(15, c.completed ? p.ok : p.warn)),
              const SizedBox(height: 8),
              for (final row in [('Goals (60 %)', c.objectives), ('Time (20 %)', c.time), ('Safety (10 %)', c.safety), ('Product quality (10 %)', c.quality)])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(child: Text(row.$1, style: t.type.label.style(14, p.ink))),
                    Text(pct(row.$2), style: t.type.number.style(14, p.accent)),
                  ]),
                ),
              const SizedBox(height: 10),
              Text(sim.debriefText ?? '', style: t.type.label.style(14, p.ink)),
            ]),
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
