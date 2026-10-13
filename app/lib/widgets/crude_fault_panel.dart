import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';

/// Faults tab of the crude unit (SCOPE.md 5): F24 stripping steam loss per injection point, F25 pumparound circulation
/// loss, F26 furnace outlet upset. F27 (draw tray dry) is an operating condition and is not injectable.
class CrudeFaultPanel extends StatefulWidget {
  final ScrollController? controller;
  final Widget? header;
  const CrudeFaultPanel({super.key, this.controller, this.header});
  @override
  State<CrudeFaultPanel> createState() => _CrudeFaultPanelState();
}

class _CrudeFaultPanelState extends State<CrudeFaultPanel> {
  String point = 'bottom';
  double sSteam = 0.85, sPa = 0.85, sCot = 0.8;

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (context, s, _) {
        if (s == null) return const SizedBox();
        Widget slider(String label, double v, double min, double max, void Function(double) on, String Function(double) fmt) => Row(
              children: [
                SizedBox(width: 78, child: Text(label, style: t.type.label.style(13, p.inkMuted))),
                Expanded(child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: 9, onChanged: (x) => setState(() => on(x)))),
                SizedBox(width: 56, child: Text(fmt(v), style: t.type.number.style(13.5, p.accent), textAlign: TextAlign.right)),
              ],
            );
        Widget card(Key key, String title, String sub, List<Widget> kids, String action, VoidCallback go) => Container(
              key: key,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.55), border: Border.all(color: p.gridMajor)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.type.display.style(14.5, p.accent, weight: FontWeight.w700)),
                  Text(sub, style: t.type.label.style(12.5, p.inkMuted)),
                  ...kids,
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: go, child: Text(action, style: t.type.label.style(13.5, p.warn, weight: FontWeight.w700))),
                  ),
                ],
              ),
            );
        const labels = {'bottom': 'Bottom (FC-321)', 'ss1': 'Kero (FC-322)', 'ss2': 'Diesel (FC-323)', 'ss3': 'AGO (FC-324)'};
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (widget.header != null) widget.header!,
            if (s.visibleFaults.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(S.noFaultIsActive, style: t.type.label.style(13.5, p.inkMuted))),
            for (final f in s.visibleFaults)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: p.warn)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(S.faultSeverityLine(f.description, f.severity, f.finalSeverity),
                          style: t.type.label.style(13, p.ink)),
                    ),
                    TextButton(onPressed: () => sim.clearFault(f.id), child: Text(S.clear, style: t.type.label.style(13.5, p.ok, weight: FontWeight.w700))),
                  ],
                ),
              ),
            card(
              const ValueKey('fault-f24'),
              S.strippingSteamLoss,
              S.f24TheSteamDelivered,
              [
                Wrap(spacing: 6, children: [
                  for (final e in labels.entries)
                    ChoiceChip(
                      label: Text(e.value, style: t.type.label.style(12.5, point == e.key ? p.bgAlt : p.ink)),
                      selected: point == e.key,
                      selectedColor: p.accent,
                      onSelected: (_) => setState(() => point = e.key),
                    ),
                ]),
                slider(S.loss, sSteam, 0.1, 1, (x) => sSteam = x, (v) => '${(100 * v).round()} %'),
              ],
              S.cutTheSteam,
              () => sim.injectFault(FaultSpec(type: FaultType.strippingSteamLoss, location: FaultLocation.steam(point), severity: sSteam, onset: s.time, ramp: 60)),
            ),
            card(
              const ValueKey('fault-f25'),
              S.pumparoundCirculationLoss,
              S.f25ThePumpDelivers,
              [slider(S.loss, sPa, 0.1, 1, (x) => sPa = x, (v) => '${(100 * v).round()} %')],
              S.slowThePump,
              () => sim.injectFault(FaultSpec(type: FaultType.pumparoundTrip, location: const FaultLocation.equipment('pumparound'), severity: sPa, onset: s.time)),
            ),
            card(
              const ValueKey('fault-f26'),
              S.furnaceOutletUpset,
              S.f26TheCrudeArrives,
              [slider(S.severity, sCot, 0.1, 1, (x) => sCot = x, (v) => '${(-15 * v).toStringAsFixed(1)} K')],
              S.upsetTheFurnace,
              () => sim.injectFault(FaultSpec(
                  type: FaultType.cotUpset, location: const FaultLocation.equipment('furnace'), severity: sCot, onset: s.time, ramp: 300, params: const {'dT': -15})),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(S.f27NotInjectable,
                  style: t.type.label.style(12.5, p.inkFaint)),
            ),
          ],
        );
      },
    );
  }
}
