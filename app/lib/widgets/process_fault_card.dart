import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';

/// F08 to F15 (SCOPE.md 5, PHYSICS.md 11): the Tier 2 feed, utility and equipment faults. Sandbox only; drills hide them.
class ProcessFaultCard extends StatefulWidget {
  const ProcessFaultCard({super.key});
  @override
  State<ProcessFaultCard> createState() => _ProcessFaultCardState();
}

class _Def {
  final FaultType type;
  final String id, title, equipment, blurb;
  final double defaultSeverity, defaultRamp;
  const _Def(this.type, this.id, this.title, this.equipment, this.blurb, this.defaultSeverity, this.defaultRamp);
}

const List<_Def> _defs = [
  _Def(FaultType.feedThermal, 'F08', 'Feed temperature upset', 'feed',
      'The preheater changes: the feed temperature drops by 40 K at full severity.', 1.0, 0),
  _Def(FaultType.coolingLoss, 'F09', 'Loss of condenser cooling', 'condenser',
      'Flow mode: the cooling-water capacity falls to (1 - s). Temperature mode: the water inlet rises by 15 s K.', 0.7, 0),
  _Def(FaultType.condenserFouling, 'F10', 'Condenser fouling', 'condenser',
      'The condenser UA falls to 40 % at full severity, slowly.', 0.85, 6 * 3600),
  _Def(FaultType.nonCondensables, 'F11', 'Non-condensables', 'condenser',
      'Inert gas builds up in the overhead, blankets the tubes and raises the pressure. The inert vent clears it.', 1.0, 0),
  _Def(FaultType.refluxPumpTrip, 'F12', 'Reflux pump trip', 'reflux',
      'The reflux pump delivers at most (1 - s) of its capacity.', 0.5, 0),
  _Def(FaultType.reboilerFouling, 'F13', 'Reboiler fouling', 'reboiler',
      'The reboiler UA falls to 40 % at full severity, slowly.', 1.0, 6 * 3600),
  _Def(FaultType.condensateBackup, 'F14', 'Condensate backup', 'reboiler',
      'A failed steam trap floods part of the tubes. Open the trap bypass to clear it.', 0.75, 60),
  _Def(FaultType.steamHeaderLoss, 'F15', 'Steam header pressure loss', 'reboiler',
      'The steam header pressure falls by 60 % s, so the steam temperature falls.', 0.85, 120),
];

class _ProcessFaultCardState extends State<ProcessFaultCard> {
  int sel = 1;
  double? sev;
  double? ramp;
  String mode = 'flow';

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final d = _defs[sel];
    final severity = sev ?? d.defaultSeverity;
    final rampS = ramp ?? (d.type == FaultType.coolingLoss && mode == 'temperature' ? 1800.0 : d.defaultRamp);
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (context, s, _) {
        if (s == null) return const SizedBox();
        final trap = s.visibleFaults.any((f) => f.type == FaultType.condensateBackup);
        return Container(
          key: const ValueKey('process-faults'),
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.55),
            border: Border.all(color: p.gridMajor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Feed and utility faults (Tier 2)', style: t.type.display.style(14.5, p.accent, weight: FontWeight.w700)),
              Text('F08 to F15. Their symptoms are on the Energy and Balance tabs.', style: t.type.label.style(12.5, p.inkMuted)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < _defs.length; i++)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(_defs[i].id, style: t.type.label.style(12.5, sel == i ? p.bgAlt : p.ink)),
                      selected: sel == i,
                      selectedColor: p.accent,
                      onSelected: (_) => setState(() {
                        sel = i;
                        sev = null;
                        ramp = null;
                      }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${d.id}  ${d.title}', style: t.type.label.style(14, p.ink, weight: FontWeight.w700)),
              ),
              Text(d.blurb, style: t.type.label.style(12.5, p.inkMuted)),
              if (d.type == FaultType.coolingLoss)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in ['flow', 'temperature'])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(m, style: t.type.label.style(12.5, mode == m ? p.bgAlt : p.ink)),
                        selected: mode == m,
                        selectedColor: p.accent,
                        onSelected: (_) => setState(() {
                          mode = m;
                          ramp = null;
                        }),
                      ),
                  ],
                ),
              Row(
                children: [
                  SizedBox(width: 70, child: Text('Severity', style: t.type.label.style(13, p.inkMuted))),
                  Expanded(
                    child: Slider(
                      value: severity.clamp(0.1, 1.0),
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      onChanged: (x) => setState(() => sev = x),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${(100 * severity).round()}%', style: t.type.number.style(13.5, p.accent), textAlign: TextAlign.right),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in <(double, String)>[(0.0, 'step'), (60.0, '1 min'), (1800.0, '30 min'), (6 * 3600.0, '6 h')])
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('ramp ${r.$2}', style: t.type.label.style(12.5, rampS == r.$1 ? p.bgAlt : p.ink)),
                      selected: rampS == r.$1,
                      selectedColor: p.accent,
                      onSelected: (_) => setState(() => ramp = r.$1),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  children: [
                    if (trap)
                      TextButton(
                        onPressed: sim.openTrapBypass,
                        child: Text('Open trap bypass', style: t.type.label.style(13.5, p.ok, weight: FontWeight.w700)),
                      ),
                    TextButton(
                      key: const ValueKey('inject-process-fault'),
                      onPressed: () => sim.injectFault(FaultSpec(
                        type: d.type,
                        location: FaultLocation.equipment(d.equipment),
                        severity: severity,
                        onset: s.time,
                        ramp: rampS,
                        params: d.type == FaultType.coolingLoss ? {'mode': mode} : const {},
                      )),
                      child: Text('Inject ${d.id}', style: t.type.label.style(13.5, p.warn, weight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
