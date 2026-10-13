import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../l10n/strings.dart';
import '../theme/lowsys_theme.dart';
import 'scenario_ui.dart';

/// Library screen S8: concept cards that link to the scenario demonstrating them.
Future<void> showLibrary(BuildContext context, SimController sim) async {
  final t = LowsysThemeScope.of(context);
  final p = t.palette;
  final open = await showDialog<LibraryCard>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(S.libraryTitle, style: t.type.display.style(20, p.ink))),
              const SizedBox(height: 4),
              Text(S.librarySubtitle, style: t.type.label.style(13, p.inkMuted)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  key: const ValueKey('library-list'),
                  shrinkWrap: true,
                  children: [
                    for (final c in S.libraryCards)
                      _CardTile(card: c, t: t, onOpen: () => Navigator.pop(ctx, c)),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.close)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (open == null || !context.mounted) return;
  await showScenarioBriefing(context, sim, Scenarios.byId(open.scenarioId));
}

class _CardTile extends StatelessWidget {
  final LibraryCard card;
  final LowsysTheme t;
  final VoidCallback onOpen;
  const _CardTile({required this.card, required this.t, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    final demo = Scenarios.byId(card.scenarioId);
    return Card(
      key: ValueKey('library-${card.id}'),
      color: p.surfaceAlt,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(card.title, style: t.type.display.style(16, p.accent)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.body, style: t.type.label.style(14, p.ink)),
          const SizedBox(height: 8),
          Text(S.libraryDemo(demo.title), style: t.type.label.style(12.5, p.inkMuted)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: ValueKey('library-open-${card.id}'),
              onPressed: onOpen,
              child: Text(S.libraryOpenScenario),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-run tutorial (and "Tutorial…" in the menu): a card over the simulator, one step at a time.
class OnboardingHost extends StatelessWidget {
  const OnboardingHost({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int?>(
      valueListenable: sim.onboardingStep,
      builder: (context, step, _) {
        if (step == null) return const SizedBox.shrink();
        final steps = S.tutorialSteps;
        final i = step.clamp(0, steps.length - 1);
        final last = i == steps.length - 1;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(
                container: true,
                liveRegion: true,
                label: '${S.tutorialTitle}, ${S.tutorialStep(i + 1, steps.length)}: ${steps[i].title}',
                child: Material(
                  key: const ValueKey('onboarding-card'),
                  color: p.surface,
                  shape: RoundedRectangleBorder(side: BorderSide(color: p.accent, width: 1.5)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.tutorialStep(i + 1, steps.length), style: t.type.label.style(12, p.inkMuted)),
                          const SizedBox(height: 2),
                          Text(steps[i].title, style: t.type.display.style(18, p.ink)),
                          const SizedBox(height: 6),
                          Text(steps[i].body, style: t.type.label.style(14, p.ink)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(key: const ValueKey('onboarding-skip'), onPressed: sim.finishOnboarding, child: Text(S.skip)),
                              if (i > 0) TextButton(onPressed: () => sim.onboardingStep.value = i - 1, child: Text(S.back)),
                              FilledButton(
                                key: const ValueKey('onboarding-next'),
                                onPressed: () => last ? sim.finishOnboarding() : sim.onboardingStep.value = i + 1,
                                child: Text(last ? S.done : S.next),
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
          ),
        );
      },
    );
  }
}
