import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';

/// Products tab (SCOPE.md 3.2, M7): the FUG shortcut panel and the GC analyser composition lists.
class ProductsPanel extends StatelessWidget {
  final bool compact;
  const ProductsPanel({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    return ListenableBuilder(
      listenable: Listenable.merge([sim.fug, sim.fugTargets, sim.snapshot]),
      builder: (context, _) => ListView(
        key: const ValueKey('products-panel'),
        padding: const EdgeInsets.all(8),
        children: const [
          FugPanel(),
          SizedBox(height: 10),
          GcLists(),
        ],
      ),
    );
  }
}

String componentName(String id) {
  try {
    return ComponentDb.load()[id].name;
  } on Object {
    return id;
  }
}

/// FUG live and target panel (PHYSICS.md 14.3).
class FugPanel extends StatelessWidget {
  const FugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final s = sim.snapshot.value;
    final r = sim.fug.value;
    final tg = sim.fugTargets.value;
    final keys = sim.config.effectiveKeys;
    final lk = componentName(sim.config.components[keys.lk]);
    final hk = componentName(sim.config.components[keys.hk]);
    Widget chip(String label, bool on, VoidCallback f, Key k) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            key: k,
            onTap: f,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: on ? p.accent.withValues(alpha: 0.18) : Colors.transparent,
                border: Border.all(color: on ? p.accent : p.gridMajor),
              ),
              child: Text(label, style: t.type.label.style(13, on ? p.accent : p.inkMuted)),
            ),
          ),
        );
    String f1(double v, [int d = 2]) => v.isFinite ? v.toStringAsFixed(d) : '-';
    Widget row(String label, String value, {String? note, Color? color, Key? k}) => Padding(
          key: k,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text(label, style: t.type.label.style(13.5, p.inkMuted))),
              Expanded(flex: 3, child: Text(value, style: t.type.number.style(14, color ?? p.ink))),
              Expanded(flex: 5, child: Text(note ?? '', style: t.type.label.style(12, p.inkFaint))),
            ],
          ),
        );
    final body = <Widget>[];
    if (r == null || !r.valid) {
      final why = switch (r?.reason) {
        FugInvalidReason.notAdjacent =>
          'The keys are not adjacent in volatility: Fenske and Underwood need the light key and heavy key next to each other.',
        FugInvalidReason.noSplit =>
          'These recoveries do not split the keys: the light key must go to D and the heavy key to B.',
        null => s?.view.isPlant == true
            ? 'Not available on a real plant view: the panel needs model compositions.'
            : 'Waiting for the first result.',
      };
      body.add(Text(why, key: const ValueKey('fug-invalid'), style: t.type.label.style(13.5, p.warn)));
    } else {
      final rNote = (tg?.rOverRmin == null) ? 'live L0 / D' : 'R = ${tg!.rOverRmin} R_min';
      body.addAll([
        row('alpha (LK/HK)', f1(r.alpha[keys.lk], 3), note: 'mean of top and bottom'),
        row('N_min (Fenske)', f1(r.nMin), note: 'stages incl. reboiler', k: const ValueKey('fug-nmin')),
        row('R_min (Underwood)', f1(r.rMin), k: const ValueKey('fug-rmin')),
        row('R used', f1(r.r), note: rNote),
        row('N (Gilliland)', f1(r.nGilliland), k: const ValueKey('fug-n')),
        row('N_R above feed (Kirkbride)', f1(r.nR), note: 'N_R/N_S ${f1(r.nrOverNs, 3)}'),
        if (r.belowRmin)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('R is below R_min: no finite column reaches these recoveries.',
                key: const ValueKey('fug-below-rmin'), style: t.type.label.style(13.5, p.warn)),
          ),
        const Divider(height: 14),
        row('Rigorous: N_act', f1(r.nActual), note: 'sum of E, plus reboiler', k: const ValueKey('fug-nact')),
        row('N_R,act above feed', f1(r.nRActual)),
        row('R_act', f1(r.rActual)),
      ]);
    }
    return Container(
      key: const ValueKey('fug-panel'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.gridMajor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FUG shortcut: $lk / $hk', style: t.type.display.style(16, p.accent)),
          const SizedBox(height: 6),
          Wrap(runSpacing: 6, children: [
            chip('Live column', tg == null, () => sim.setFugTargets(null), const ValueKey('fug-live')),
            chip('Targets 98 %', tg != null && tg.rOverRmin == null, () => sim.setFugTargets(const FugTargets(0.98, 0.98)),
                const ValueKey('fug-target')),
            chip('98 %, R = 1.3 R_min', tg?.rOverRmin != null, () => sim.setFugTargets(const FugTargets(0.98, 0.98, 1.3)),
                const ValueKey('fug-target-k')),
          ]),
          const SizedBox(height: 8),
          ...body,
        ],
      ),
    );
  }
}

/// The GC analysers AT-100 (feed), AT-101 (distillate) and AT-102 (bottoms) with the full composition (PHYSICS.md 10.5).
class GcLists extends StatelessWidget {
  const GcLists({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final s = sim.snapshot.value;
    final comps = sim.config.components;
    final keys = sim.config.effectiveKeys;
    final at = [
      for (final i in s?.instruments ?? const <InstrumentReading>[])
        if (i.tag.startsWith('AT-') && i.components != null) i
    ];
    const titles = {'AT-100': 'Feed', 'AT-101': 'Distillate', 'AT-102': 'Bottoms'};
    if (at.isEmpty) return const SizedBox.shrink();
    Widget col(InstrumentReading i) => Expanded(
          child: Container(
            key: ValueKey('gc-${i.tag}'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.gridMajor)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i.tag} ${titles[i.tag] ?? ''}', style: t.type.display.style(14, p.accent)),
                const SizedBox(height: 4),
                for (var j = 0; j < comps.length && j < i.components!.length; j++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${componentName(comps[j])}${j == keys.lk ? ' (LK)' : (j == keys.hk ? ' (HK)' : '')}',
                          overflow: TextOverflow.ellipsis,
                          style: t.type.label.style(12.5, j == keys.lk || j == keys.hk ? p.ink : p.inkMuted),
                        ),
                      ),
                      Text(i.components![j].isFinite ? i.components![j].toStringAsFixed(4) : '-',
                          style: t.type.number.style(13, p.ink)),
                    ]),
                  ),
                if (i.qualityText != null) Text(i.qualityText!, style: t.type.label.style(12, p.warn)),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GC analysers (mole fractions)', style: t.type.display.style(15, p.ink)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final i in at) ...[col(i), if (i != at.last) const SizedBox(width: 6)],
        ]),
      ],
    );
  }
}
