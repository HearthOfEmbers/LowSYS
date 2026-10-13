import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'balance_panel.dart';
import 'energy_panel.dart';
import 'lever_panel.dart';
import 'loops_panel.dart';
import 'process_fault_card.dart';
import 'trends_panel.dart';

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
  int bed = 1;
  double sMal = 0.5, sCrush = 0.3;
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
        final hasTrays = s.layout.kinds.contains(StageKind.tray);
        const trayCards = {'Broken tray', 'Fouled trays', 'Foaming'};
        bed = bed.clamp(1, math.max(1, s.beds.length));
        tray = tray.clamp(1, n);
        fromTray = fromTray.clamp(1, n);
        toTray = toTray.clamp(fromTray, n);
        Widget slider(
          String label,
          double v,
          double min,
          double max,
          int? div,
          void Function(double) on,
          String Function(double) fmt,
        ) => Row(
          children: [
            SizedBox(
              width: 78,
              child: Text(label, style: t.type.label.style(13, p.inkMuted)),
            ),
            Expanded(
              child: Slider(
                value: v.clamp(min, max),
                min: min,
                max: max,
                divisions: div,
                onChanged: (x) => setState(() => on(x)),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                fmt(v),
                style: t.type.number.style(13.5, p.accent),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
        Widget card(
          String title,
          String sub,
          List<Widget> kids,
          String action,
          VoidCallback go,
        ) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.55),
            border: Border.all(color: p.gridMajor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: t.type.display.style(
                  14.5,
                  p.accent,
                  weight: FontWeight.w700,
                ),
              ),
              Text(sub, style: t.type.label.style(12.5, p.inkMuted)),
              ...kids,
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: full && (hasTrays || !trayCards.contains(title)) ? go : null,
                  child: Text(
                    action,
                    style: t.type.label.style(
                      13.5,
                      full && (hasTrays || !trayCards.contains(title)) ? p.warn : p.inkFaint,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
                child: Text(
                  'Tray faults need full hydraulics. Switch Internals > Hydraulics to Full on the Levers tab.',
                  style: t.type.label.style(13, p.warn),
                ),
              ),
            if (active.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'ACTIVE',
                  style: t.type.display.style(
                    14,
                    p.accent,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              for (final f in active)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.warn.withValues(alpha: 0.7)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${f.description}\nseverity ${(100 * f.severity).toStringAsFixed(0)} % (final ${(100 * f.finalSeverity).toStringAsFixed(0)} %)',
                          style: t.type.label.style(13, p.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: () => sim.clearFault(f.id),
                        child: Text(
                          'Clear',
                          style: t.type.label.style(
                            13.5,
                            p.ok,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (s.beds.isNotEmpty)
              card(
                'Packing maldistribution',
                'F21: a plugged distributor sends more liquid to one side of the bed (f = 0.6 s). The pressure drop hardly moves; the separation and the bed temperature profile do.',
                [
                  slider('Bed', bed.toDouble(), 1, s.beds.length.toDouble(), s.beds.length > 1 ? s.beds.length - 1 : null,
                      (x) => bed = x.round(), (v) => '${v.round()}'),
                  slider('Severity', sMal, 0.1, 1, 9, (x) => sMal = x, (v) => '${(100 * v).round()}%'),
                ],
                'Plug the distributor',
                () => sim.injectFault(FaultSpec(
                  type: FaultType.packingMaldistribution,
                  location: FaultLocation.bed(bed),
                  severity: sMal,
                  onset: s.time,
                  ramp: 900,
                )),
              ),
            if (s.beds.isNotEmpty)
              card(
                'Crushed packing',
                'F23: the packing factor rises by 150 % of s and the bed gets 15 % of s shorter. Higher dP at the same load, earlier flooding.',
                [
                  slider('Bed', bed.toDouble(), 1, s.beds.length.toDouble(), s.beds.length > 1 ? s.beds.length - 1 : null,
                      (x) => bed = x.round(), (v) => '${v.round()}'),
                  slider('Severity', sCrush, 0.1, 1, 9, (x) => sCrush = x, (v) => '${(100 * v).round()}%'),
                ],
                'Crush the packing',
                () => sim.injectFault(FaultSpec(
                  type: FaultType.packingCrush,
                  location: FaultLocation.bed(bed),
                  severity: sCrush,
                  onset: s.time,
                )),
              ),
            card(
              'Broken tray',
              'F04: part of the deck is missing. Liquid and vapour bypass it.',
              [
                slider(
                  'Tray',
                  tray.toDouble(),
                  1,
                  n.toDouble(),
                  n - 1,
                  (x) => tray = x.round(),
                  (v) => '${v.round()}',
                ),
                slider(
                  'Opening',
                  sBroken,
                  0.1,
                  1,
                  9,
                  (x) => sBroken = x,
                  (v) => '${(100 * v).round()}%',
                ),
              ],
              'Break tray',
              () => sim.injectFault(
                FaultSpec(
                  type: FaultType.trayDamage,
                  location: FaultLocation.stages(tray, tray),
                  severity: sBroken,
                  onset: s.time,
                ),
              ),
            ),
            card(
              'Fouled trays',
              'F05: plugged holes or a blocked downcomer. Pressure drop creeps up first.',
              [
                slider('From', fromTray.toDouble(), 1, n.toDouble(), n - 1, (
                  x,
                ) {
                  fromTray = x.round();
                  if (toTray < fromTray) toTray = fromTray;
                }, (v) => '${v.round()}'),
                slider('To', toTray.toDouble(), 1, n.toDouble(), n - 1, (x) {
                  toTray = x.round();
                  if (fromTray > toTray) fromTray = toTray;
                }, (v) => '${v.round()}'),
                slider(
                  'Plugging',
                  sFoul,
                  0.1,
                  1,
                  9,
                  (x) => sFoul = x,
                  (v) => '${(100 * v).round()}%',
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in ['holes', 'downcomer', 'both'])
                      ChoiceChip(
                        label: Text(
                          m,
                          style: t.type.label.style(
                            12.5,
                            foulMode == m ? p.bgAlt : p.ink,
                          ),
                        ),
                        selected: foulMode == m,
                        selectedColor: p.accent,
                        onSelected: (_) => setState(() => foulMode = m),
                      ),
                    for (final r in [(0.0, 'step'), (3600.0, '1 h ramp')])
                      ChoiceChip(
                        label: Text(
                          r.$2,
                          style: t.type.label.style(
                            12.5,
                            foulRamp == r.$1 ? p.bgAlt : p.ink,
                          ),
                        ),
                        selected: foulRamp == r.$1,
                        selectedColor: p.accent,
                        onSelected: (_) => setState(() => foulRamp = r.$1),
                      ),
                  ],
                ),
              ],
              'Foul trays',
              () => sim.injectFault(
                FaultSpec(
                  type: FaultType.trayFouling,
                  location: FaultLocation.stages(fromTray, toTray),
                  severity: sFoul,
                  onset: s.time,
                  ramp: foulRamp,
                  params: {'mode': foulMode},
                ),
              ),
            ),
            card(
              'Foaming',
              'F06: the froth gets lighter and the flood capacity falls. Antifoam works after a delay.',
              [
                slider(
                  'Severity',
                  sFoam,
                  0.1,
                  1,
                  9,
                  (x) => sFoam = x,
                  (v) => '${(100 * v).round()}%',
                ),
              ],
              'Start foaming',
              () => sim.injectFault(
                FaultSpec(
                  type: FaultType.foaming,
                  location: const FaultLocation.whole(),
                  severity: sFoam,
                  onset: s.time,
                  ramp: 600,
                ),
              ),
            ),
            card(
              'Feed composition upset',
              'F07: more of the light component in the feed (+15 points at full severity).',
              [
                slider(
                  'Size',
                  sFeed,
                  0.1,
                  1,
                  9,
                  (x) => sFeed = x,
                  (v) => '${(100 * v).round()}%',
                ),
              ],
              'Upset the feed',
              () => sim.injectFault(
                FaultSpec(
                  type: FaultType.feedComposition,
                  location: const FaultLocation.feed(0),
                  severity: sFeed,
                  onset: s.time,
                ),
              ),
            ),
            if (s.tier != ThermoTier.t1) const ProcessFaultCard(),
            const InstrumentFaultCard(),
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
  const ControlTabs({
    super.key,
    this.controller,
    this.handle,
    this.scrollTabs = false,
  });

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<int>(
      valueListenable: sim.controlTab,
      builder: (context, tab, _) {
        Widget btn(String label, IconData icon, int i) => _TabSlot(
          child: InkWell(
            onTap: () => sim.controlTab.value = i,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tab == i ? p.accent : p.gridMajor,
                    width: tab == i ? 2.5 : 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17, color: tab == i ? p.accent : p.inkMuted),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: t.type.display.style(12, tab == i ? p.accent : p.inkMuted, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final tabs = LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 6 * 72;
            final row = Row(
              children: [
                btn('LEVERS', Icons.tune, 0),
                btn('LOOPS', Icons.settings_input_component, 1),
                btn('BALANCE', Icons.balance, 2),
                btn('TRENDS', Icons.show_chart, 3),
                btn('FAULTS', Icons.warning_amber, 4),
                btn('ENERGY', Icons.local_fire_department, 5),
              ],
            );
            // six tabs of 12 sp text need 72 dp each; narrower panels scroll the strip
            return wide
                ? row
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 6 * 72.0, child: row),
                  );
          },
        );
        final header = scrollTabs
            ? Column(children: [if (handle != null) handle!, tabs])
            : null;
        final content = switch (tab) {
          0 => LeverPanel(controller: controller, header: header),
          1 => LoopsPanel(controller: controller, header: header),
          2 => BalancePanel(controller: controller, header: header),
          3 => TrendsPanel(controller: controller, header: header),
          5 => EnergyPanel(controller: controller, header: header),
          _ => FaultPanel(controller: controller, header: header),
        };
        if (scrollTabs) return content;
        return Column(
          children: [
            tabs,
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

/// Instrument and valve faults (F19, F28, F20) and maintenance (PHYSICS.md 10.5, 10.6).
class InstrumentFaultCard extends StatefulWidget {
  const InstrumentFaultCard({super.key});
  @override
  State<InstrumentFaultCard> createState() => _InstrumentFaultCardState();
}

class _InstrumentFaultCardState extends State<InstrumentFaultCard> {
  String tag = 'FT-102';
  String kind = 'bias';
  double severity = 0.4;
  bool negative = false;
  String valveKind = 'stuck';
  String valveId = 'FV-102';

  static const _f19 = {'bias', 'drift', 'stuck'};

  List<String> _kinds(InstrumentReading r) {
    final at = r.type == InstrumentType.at;
    final ft =
        r.type == InstrumentType.ftLiquid ||
        r.type == InstrumentType.ftSteam ||
        r.type == InstrumentType.ftWater;
    final lt =
        r.type == InstrumentType.ltDrum || r.type == InstrumentType.ltSump;
    return [
      'bias',
      'drift',
      'stuck',
      if (!at) 'signalLossLow',
      if (!at) 'signalLossHigh',
      if (at) 'signalLoss',
      if (ft ||
          lt ||
          at ||
          r.type == InstrumentType.pdt ||
          r.type == InstrumentType.pt)
        'plugged',
      if (!at) 'spiking',
      if (r.type == InstrumentType.tiTray || r.type == InstrumentType.tiLine)
        'coated',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final s = sim.snapshot.value;
    if (s == null) return const SizedBox.shrink();
    final r = s.instruments.firstWhere(
      (x) => x.tag == tag,
      orElse: () => s.instruments.first,
    );
    final kinds = _kinds(r);
    if (!kinds.contains(kind)) kind = kinds.first;
    final signed = kind == 'bias' || kind == 'drift';
    Widget chips(List<String> items, String cur, void Function(String) on) =>
        Wrap(
          spacing: 5,
          runSpacing: 0,
          children: [
            for (final k in items)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  k,
                  style: t.type.label.style(12, cur == k ? p.bgAlt : p.ink),
                ),
                selected: cur == k,
                selectedColor: p.accent,
                onSelected: (_) => setState(() => on(k)),
              ),
          ],
        );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.55),
        border: Border.all(color: p.gridMajor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Instrument fault',
            style: t.type.display.style(
              14.5,
              p.accent,
              weight: FontWeight.w700,
            ),
          ),
          Text(
            'F19 and F28: a transmitter lies, freezes, plugs or fails. Use the Balance tab and the signal look to find it.',
            style: t.type.label.style(12.5, p.inkMuted),
          ),
          const SizedBox(height: 4),
          chips([for (final i in s.instruments) i.tag], tag, (k) => tag = k),
          const SizedBox(height: 4),
          chips(kinds, kind, (k) => kind = k),
          Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  'Severity',
                  style: t.type.label.style(13, p.inkMuted),
                ),
              ),
              Expanded(
                child: Slider(
                  value: severity,
                  min: 0.1,
                  max: 1,
                  divisions: 9,
                  onChanged: (v) => setState(() => severity = v),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(100 * severity).round()}%',
                  style: t.type.number.style(13.5, p.accent),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (signed)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Reads', style: t.type.label.style(13, p.inkMuted)),
                const SizedBox(width: 8),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('high'),
                  selected: !negative,
                  onSelected: (_) => setState(() => negative = false),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('low'),
                  selected: negative,
                  onSelected: (_) => setState(() => negative = true),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => sim.injectFault(
                FaultSpec(
                  type: _f19.contains(kind)
                      ? FaultType.instrument
                      : FaultType.transmitter,
                  location: FaultLocation.tag(tag),
                  severity: severity,
                  onset: s.time,
                  params: {'kind': kind, if (signed) 'sign': negative ? -1 : 1},
                ),
              ),
              child: Text(
                'Inject on $tag',
                style: t.type.label.style(
                  13.5,
                  p.warn,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const Divider(),
          Text(
            'Valve fault (F20)',
            style: t.type.display.style(
              14.5,
              p.accent,
              weight: FontWeight.w700,
            ),
          ),
          Text(
            'A stuck valve moves nothing while its OP wanders. Open the bypass to work around it.',
            style: t.type.label.style(12.5, p.inkMuted),
          ),
          chips([for (final v in s.valves) v.id], valveId, (k) => valveId = k),
          chips(
            const ['stuck', 'failOpen', 'failClosed'],
            valveKind,
            (k) => valveKind = k,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => sim.injectFault(
                FaultSpec(
                  type: FaultType.valve,
                  location: FaultLocation.tag(valveId),
                  severity: 1,
                  onset: s.time,
                  params: {'kind': valveKind},
                ),
              ),
              child: Text(
                'Inject on $valveId',
                style: t.type.label.style(
                  13.5,
                  p.warn,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab of the control strip: fills its share of the row.
class _TabSlot extends StatelessWidget {
  final Widget child;
  const _TabSlot({required this.child});
  @override
  Widget build(BuildContext context) => Expanded(child: child);
}
