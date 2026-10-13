import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'c6_card.dart';
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
          if (c.status == CheckStatus.notAvailable) {
            if (c.reason == 'collecting data') {
              final have = (sim.trends.count * 5).clamp(0, sim.checkWindow.round());
              return 'Collecting $have/${sim.checkWindow.round()} s';
            }
            return 'Not available: ${c.reason ?? ''}';
          }
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
            case 'C3a':
              String kw(String k) => tm[k]?.isNaN ?? true ? '—' : _kw(u, tm[k]!);
              return 'Condenser ${kw('dutyCw')} ≈ ${n('fromCondenser')} of vapour · reflux + distillate ${n('fromReflux')} · difference ${flow(c.residual)} $fu (band $band)';
            case 'C3b':
              String kw2(String k) => tm[k]?.isNaN ?? true ? '—' : _kw(u, tm[k]!);
              return 'Reboiler ${kw2('reboiler')} + feed ${kw2('feed')} = condenser ${kw2('condenser')} + products ${kw2('products')} · unaccounted ${_kw(u, c.residual)} (band ±${_kw(u, c.band)})';
            case 'C7':
              final top = c.id.endsWith('top');
              return '${top ? 'Top: reflux temperature + subcooling' : 'Bottom: sump temperature'} vs the bubble point of the analysed product at the measured pressure ${_tK(u, tm['bubble'] ?? double.nan)} · off by ${c.residual.toStringAsFixed(2)} K (band ±${c.band.toStringAsFixed(1)} K)';
            case 'C4':
              final v = c.id.split(':').last;
              if (v == 'FV-103' || v == 'PV-101') {
                final qty = v == 'FV-103' ? Quantity.energyRate : Quantity.volumeFlowLiquid;
                String m(double x) => '${Fmt.value(qty, x, u)} ${u.symbol(qty)}';
                return '$v: OP ${(tm['op'] ?? 0).toStringAsFixed(1)} % expects ${m(tm['expected'] ?? double.nan)}; meter says ${m(tm['measured'] ?? double.nan)} (off by ${m(c.residual)}, band ±${m(c.band)})';
              }
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
            case 'C3a':
              return 'C3a  Top vapour from the condenser duty';
            case 'C3b':
              return 'C3b  Column energy balance';
            case 'C7':
              return 'C7  Bubble point (${c.id.split(':').last})';
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
            ...() {
              final c6 = s.crossChecks.where((c) => c.id.startsWith('C6:')).toList();
              return [
                if (c6.isNotEmpty) TrayTemperatureCard(checks: c6),
              ];
            }(),
            for (final c in s.crossChecks.where((c) => !c.id.startsWith('C6:')))
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
                      if (c.reason == 'collecting data')
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            value: ((sim.trends.count * 5) / sim.checkWindow).clamp(0.0, 1.0),
                            color: p.accent,
                            backgroundColor: p.gridMajor,
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

String _kw(UnitSystem u, double w) =>
    w.isNaN ? '—' : '${Fmt.value(Quantity.energyRate, w, u)} ${u.symbol(Quantity.energyRate)}';

String _tK(UnitSystem u, double k) =>
    k.isNaN ? '—' : '${Fmt.value(Quantity.temperature, k, u)} ${u.symbol(Quantity.temperature)}';
