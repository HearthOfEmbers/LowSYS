import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'lever_panel.dart';

/// Faults tab (sandbox): inject F04-F07, see active faults and clear them (SCOPE.md 5, 3.2).
class FaultPanel extends StatefulWidget {
  final ScrollController? controller;
  final Widget? header;
  const FaultPanel({super.key, this.controller, this.header});
  @override
  State<FaultPanel> createState() => _FaultPanelState();
}

class _FaultPanelState extends State<FaultPanel> {
  int tray = 8;
  int fromTray = 12, toTray = 16;
  double sBroken = 1.0, sFoul = 0.6, sFoam = 0.5, sFeed = 1.0;
  String foulMode = 'holes';
  double foulRamp = 0;

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (context, s, _) {
        if (s == null) return const SizedBox();
        final n = s.layout.nTrays;
        final full = s.hydraulics == HydraulicsMode.full;
        tray = tray.clamp(1, n);
        fromTray = fromTray.clamp(1, n);
        toTray = toTray.clamp(fromTray, n);
        Widget slider(String label, double v, double min, double max, int? div, void Function(double) on, String Function(double) fmt) => Row(children: [
              SizedBox(width: 78, child: Text(label, style: t.type.label.style(13, p.inkMuted))),
              Expanded(child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: div, onChanged: (x) => setState(() => on(x)))),
              SizedBox(width: 44, child: Text(fmt(v), style: t.type.number.style(13.5, p.accent), textAlign: TextAlign.right)),
            ]);
        Widget card(String title, String sub, List<Widget> kids, String action, VoidCallback go) => Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.55), border: Border.all(color: p.gridMajor)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.type.display.style(14.5, p.accent, weight: FontWeight.w700)),
                Text(sub, style: t.type.label.style(12.5, p.inkMuted)),
                ...kids,
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: full ? go : null, child: Text(action, style: t.type.label.style(13.5, full ? p.warn : p.inkFaint, weight: FontWeight.w700))),
                ),
              ]),
            );
        final active = s.visibleFaults;
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (widget.header != null) widget.header!,
            if (!full)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: p.warn)),
                child: Text('Tray faults need full hydraulics. Switch Internals > Hydraulics to Full on the Levers tab.', style: t.type.label.style(13, p.warn)),
              ),
            if (active.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('ACTIVE', style: t.type.display.style(14, p.accent, weight: FontWeight.w700))),
              for (final f in active)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(border: Border.all(color: p.warn.withValues(alpha: 0.7))),
                  child: Row(children: [
                    Expanded(
                      child: Text('${f.description}\nseverity ${(100 * f.severity).toStringAsFixed(0)} % (final ${(100 * f.finalSeverity).toStringAsFixed(0)} %)', style: t.type.label.style(13, p.ink)),
                    ),
                    TextButton(onPressed: () => sim.clearFault(f.id), child: Text('Clear', style: t.type.label.style(13.5, p.ok, weight: FontWeight.w700))),
                  ]),
                ),
            ],
            card('Broken tray', 'F04: part of the deck is missing. Liquid and vapour bypass it.', [
              slider('Tray', tray.toDouble(), 1, n.toDouble(), n - 1, (x) => tray = x.round(), (v) => '${v.round()}'),
              slider('Opening', sBroken, 0.1, 1, 9, (x) => sBroken = x, (v) => '${(100 * v).round()}%'),
            ], 'Break tray', () => sim.injectFault(FaultSpec(type: FaultType.trayDamage, location: FaultLocation.stages(tray, tray), severity: sBroken, onset: s.time))),
            card('Fouled trays', 'F05: plugged holes or a blocked downcomer. Pressure drop creeps up first.', [
              slider('From', fromTray.toDouble(), 1, n.toDouble(), n - 1, (x) {
                fromTray = x.round();
                if (toTray < fromTray) toTray = fromTray;
              }, (v) => '${v.round()}'),
              slider('To', toTray.toDouble(), 1, n.toDouble(), n - 1, (x) {
                toTray = x.round();
                if (fromTray > toTray) fromTray = toTray;
              }, (v) => '${v.round()}'),
              slider('Plugging', sFoul, 0.1, 1, 9, (x) => sFoul = x, (v) => '${(100 * v).round()}%'),
              Wrap(spacing: 6, children: [
                for (final m in ['holes', 'downcomer', 'both'])
                  ChoiceChip(
                    label: Text(m, style: t.type.label.style(12.5, foulMode == m ? p.bgAlt : p.ink)),
                    selected: foulMode == m,
                    selectedColor: p.accent,
                    onSelected: (_) => setState(() => foulMode = m),
                  ),
                for (final r in [(0.0, 'step'), (3600.0, '1 h ramp')])
                  ChoiceChip(
                    label: Text(r.$2, style: t.type.label.style(12.5, foulRamp == r.$1 ? p.bgAlt : p.ink)),
                    selected: foulRamp == r.$1,
                    selectedColor: p.accent,
                    onSelected: (_) => setState(() => foulRamp = r.$1),
                  ),
              ]),
            ], 'Foul trays', () => sim.injectFault(FaultSpec(type: FaultType.trayFouling, location: FaultLocation.stages(fromTray, toTray), severity: sFoul, onset: s.time, ramp: foulRamp, params: {'mode': foulMode}))),
            card('Foaming', 'F06: the froth gets lighter and the flood capacity falls. Antifoam works after a delay.', [
              slider('Severity', sFoam, 0.1, 1, 9, (x) => sFoam = x, (v) => '${(100 * v).round()}%'),
            ], 'Start foaming', () => sim.injectFault(FaultSpec(type: FaultType.foaming, location: const FaultLocation.whole(), severity: sFoam, onset: s.time, ramp: 600))),
            card('Feed composition upset', 'F07: more of the light component in the feed (+15 points at full severity).', [
              slider('Size', sFeed, 0.1, 1, 9, (x) => sFeed = x, (v) => '${(100 * v).round()}%'),
            ], 'Upset the feed', () => sim.injectFault(FaultSpec(type: FaultType.feedComposition, location: const FaultLocation.feed(0), severity: sFeed, onset: s.time))),
          ],
        );
      },
    );
  }
}

/// Levers / Faults tab strip around the control panel. With [scrollTabs] the strip (and [handle]) scroll with
/// the content so a draggable sheet can be dragged by it.
class ControlTabs extends StatelessWidget {
  final ScrollController? controller;
  final Widget? handle;
  final bool scrollTabs;
  const ControlTabs({super.key, this.controller, this.handle, this.scrollTabs = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int>(
      valueListenable: sim.controlTab,
      builder: (context, tab, _) {
        Widget btn(String label, int i) => Expanded(
              child: InkWell(
                onTap: () => sim.controlTab.value = i,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == i ? p.accent : p.gridMajor, width: tab == i ? 2.5 : 1))),
                  child: Text(label, style: t.type.display.style(14, tab == i ? p.accent : p.inkMuted, weight: FontWeight.w700)),
                ),
              ),
            );
        final tabs = Row(children: [btn('LEVERS', 0), btn('FAULTS', 1)]);
        final header = scrollTabs ? Column(children: [if (handle != null) handle!, tabs]) : null;
        final content = tab == 0 ? LeverPanel(controller: controller, header: header) : FaultPanel(controller: controller, header: header);
        if (scrollTabs) return content;
        return Column(children: [tabs, Expanded(child: content)]);
      },
    );
  }
}
