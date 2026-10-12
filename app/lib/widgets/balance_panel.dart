import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'loops_panel.dart' show checkColor;

/// Balance tab: the cross-checks of PHYSICS.md 14.6, computed from the readings only (so they work in plant
/// view). Each row opens the math overlay.
class BalancePanel extends StatelessWidget {
  final ScrollController? controller;
  final Widget? header;
  const BalancePanel({super.key, this.controller, this.header});

  static const windows = [300.0, 600.0, 1800.0, 3600.0];

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([sim.snapshot, sim.units]),
      builder: (context, _) {
        final s = sim.snapshot.value;
        if (s == null) return const SizedBox();
        final u = sim.units.value;
        String flow(double v) => Fmt.value(Quantity.molarFlow, v, u);
        final fu = u.symbol(Quantity.molarFlow);
        String rowText(CrossCheckResult c) {
          if (c.status == CheckStatus.notAvailable)
            return 'Not available: ${c.reason ?? ''}';
          if (c.status == CheckStatus.transient)
            return 'Waiting for steady state (${c.reason ?? ''})';
          final tm = c.terms;
          String n(String k) => tm[k]?.isNaN ?? true ? '—' : flow(tm[k]!);
          final band = '±${flow(c.band)} $fu';
          switch (c.id.split(':').first) {
            case 'C1':
              return 'In ${n('in')} · out D+B ${n('out')} · accumulating ${n('accumulation')} · unaccounted ${flow(c.residual)} $fu (band $band)';
            case 'C2':
              return 'Light component in ${n('in')}, out ${n('out')} · D/F meters ${(tm['dfMeters'] ?? double.nan).toStringAsFixed(3)}, analysers ${(tm['dfAnalysers'] ?? double.nan).toStringAsFixed(3)} · off by ${flow(c.residual)} $fu (band $band)';
            case 'C3':
              return 'Vapour to the top: from boilup ${n('fromBoilup')} · from reflux + distillate ${n('fromReflux')} · difference ${flow(c.residual)} $fu (band $band)';
            case 'C4':
              final v = c.id.split(':').last;
              return '$v: OP ${(tm['op'] ?? 0).toStringAsFixed(1)} % expects ${n('expected')}; meter says ${n('measured')} (${flow(c.residual)}, band $band)';
            case 'C5':
              return 'Level moved ${(tm['measured'] ?? 0).toStringAsFixed(2)} % · flows predict ${(tm['predicted'] ?? 0).toStringAsFixed(2)} % · gap ${c.residual.toStringAsFixed(2)} (band ±${c.band.toStringAsFixed(1)} %)';
          }
          return '';
        }

        String title(CrossCheckResult c) {
          switch (c.id.split(':').first) {
            case 'C1':
              return 'C1  Material balance';
            case 'C2':
              return 'C2  Component balance';
            case 'C3':
              return 'C3  Top vapour';
            case 'C4':
              return 'C4  Valve curve ${c.id.split(':').last}';
            case 'C5':
              return 'C5  Level vs flows (${c.id.split(':').last})';
          }
          return c.id;
        }

        final w = (s.crossChecks.isEmpty ? 600.0 : sim.checkWindow);
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (header != null) header!,
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, 
                children: [
                  Text('Window', style: t.type.label.style(13, p.inkMuted)),
                  const SizedBox(width: 8),
                  for (final x in windows)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          x >= 3600 ? '1 h' : '${(x / 60).round()} min',
                          style: t.type.label.style(
                            12.5,
                            w == x ? p.bgAlt : p.ink,
                          ),
                        ),
                        selected: w == x,
                        selectedColor: p.accent,
                        onSelected: (_) => sim.setCheckWindow(x),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              'Every check uses meters and analysers only. A fault larger than about twice the band is unambiguous.',
              style: t.type.label.style(12, p.inkMuted),
            ),
            for (final c in s.crossChecks)
              InkWell(
                onTap: () => sim.openMath(ExplainCheck(c.id)),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: 0.5),
                    border: Border(
                      left: BorderSide(
                        color: checkColor(p, c.status),
                        width: 4,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title(c),
                              style: t.type.display.style(
                                14,
                                p.ink,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (c.status == CheckStatus.ok ||
                              c.status == CheckStatus.check ||
                              c.status == CheckStatus.fail)
                            Text(
                              '${c.status.name.toUpperCase()}  ${(c.residual.abs() / c.band).toStringAsFixed(1)}×',
                              style: t.type.number.style(
                                13,
                                checkColor(p, c.status),
                                weight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        rowText(c),
                        style: t.type.label.style(
                          12.5,
                          c.status == CheckStatus.notAvailable
                              ? p.inkFaint
                              : p.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
