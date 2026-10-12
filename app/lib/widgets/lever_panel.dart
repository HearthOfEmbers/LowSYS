import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';

/// Step (display units) for the +/- fine buttons.
double _fineStep(LeverSpec s) {
  if (s.integer) return 1;
  switch (s.quantity) {
    case Quantity.molarFlow:
      return 1;
    case Quantity.percent:
      return 1;
    case Quantity.fraction:
      return 0.01;
    default:
      return s.id == 'refluxRatio' ? 0.05 : (s.id == 'alpha' ? 0.05 : 0.05);
  }
}

String _fmtValue(LeverSpec s, double si) {
  if (s.integer) return si.round().toString();
  final d = UnitSystem.si.fromSI(s.quantity, si);
  switch (s.quantity) {
    case Quantity.molarFlow:
      return d.toStringAsFixed(1);
    case Quantity.percent:
      return d.toStringAsFixed(0);
    case Quantity.fraction:
      return d.toStringAsFixed(3);
    default:
      return d.toStringAsFixed(2);
  }
}

/// Levers tab: grouped lever tiles (SCOPE.md 3.2 ControlPanel).
class LeverPanel extends StatelessWidget {
  final ScrollController? controller;
  final EdgeInsets padding;
  final Widget? header;
  const LeverPanel({super.key, this.controller, this.header, this.padding = const EdgeInsets.fromLTRB(12, 4, 12, 24)});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) {
        if (!sim.loaded) return const SizedBox();
        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: sim.leverValues,
          builder: (context, values, _) {
            final levers = sim.levers;
            LeverSpec? byId(String id) {
              for (final l in levers) {
                if (l.id == id) return l;
              }
              return null;
            }

            final ratioMode = (values['refluxMode'] ?? 0) >= 0.5;
            final children = <Widget>[if (header != null) header!];
            void group(String title, List<Widget> tiles) {
              if (tiles.isEmpty) return;
              children.add(_GroupHeader(title: title, t: t));
              children.addAll(tiles);
            }

            Widget tile(String id) => LeverTile(spec: byId(id)!, value: values[id] ?? byId(id)!.defaultValue, sim: sim);
            final feedZ = levers.firstWhere((l) => l.id.startsWith('feedZ.'));
            group('FEED', [tile('feedFlow'), tile(feedZ.id), tile('feedQ'), tile('feedStage')]);
            group('TOP', [
              _ModeToggle(ratioMode: ratioMode, sim: sim, t: t),
              tile(ratioMode ? 'refluxRatio' : 'refluxFlow'),
              tile('drumLevelSp'),
            ]);
            group('BOTTOM', [tile('boilup'), tile('sumpLevelSp')]);
            group('COLUMN', [
              tile('nTrays'),
              tile('murphree'),
              if (byId('alpha') != null) tile('alpha'),
            ]);
            return ListView(controller: controller, padding: padding, children: children);
          },
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final LowsysTheme t;
  const _GroupHeader({required this.title, required this.t});
  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(children: [
        Text(title, style: t.type.display.style(14, p.accent, weight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: p.gridMajor)),
      ]),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool ratioMode;
  final SimController sim;
  final LowsysTheme t;
  const _ModeToggle({required this.ratioMode, required this.sim, required this.t});
  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    Widget seg(String text, bool on, VoidCallback tap) => Expanded(
          child: InkWell(
            onTap: tap,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? p.accent.withValues(alpha: 0.18) : Colors.transparent,
                border: Border.all(color: on ? p.accent : p.gridMajor),
              ),
              child: Text(text, style: t.type.label.style(13, on ? p.accent : p.inkMuted)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        seg('Reflux flow', !ratioMode, () => sim.setLever('refluxMode', 0)),
        seg('Reflux ratio', ratioMode, () => sim.setLever('refluxMode', 1)),
      ]),
    );
  }
}

/// Slider with fine -/+ buttons and tap-to-type numeric entry (SCOPE.md 3.3).
class LeverTile extends StatelessWidget {
  final LeverSpec spec;
  final double value;
  final SimController sim;
  const LeverTile({super.key, required this.spec, required this.value, required this.sim});

  double get _dMin => spec.integer ? spec.min : UnitSystem.si.fromSI(spec.quantity, spec.min);
  double get _dMax => spec.integer ? spec.max : UnitSystem.si.fromSI(spec.quantity, spec.max);
  double _toDisplay(double si) => spec.integer ? si : UnitSystem.si.fromSI(spec.quantity, si);
  double _toSI(double d) => spec.integer ? d : UnitSystem.si.toSI(spec.quantity, d);

  void _set(double display) {
    final c = display.clamp(_dMin, _dMax).toDouble();
    sim.setLever(spec.id, spec.integer ? c.roundToDouble() : _toSI(c));
  }

  Future<void> _edit(BuildContext context) async {
    final t = LowsysThemeScope.of(context);
    final ctl = TextEditingController(text: _fmtValue(spec, value));
    final unit = spec.integer ? '' : UnitSystem.si.symbol(spec.quantity);
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(spec.label, style: t.type.display.style(18, t.palette.ink)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: t.type.number.style(18, t.palette.accent),
          decoration: InputDecoration(
            suffixText: unit,
            helperText: 'Range ${_dMin.toStringAsFixed(spec.integer ? 0 : 2)} to ${_dMax.toStringAsFixed(spec.integer ? 0 : 2)}',
          ),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text)), child: const Text('Set')),
        ],
      ),
    );
    if (res != null) _set(res);
  }

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final unit = spec.integer ? '' : UnitSystem.si.symbol(spec.quantity);
    final step = _fineStep(spec);
    final d = _toDisplay(value);
    final isLoop = spec.boundLoop != null && !spec.id.contains('Valve');
    final divisions = spec.integer ? (spec.max - spec.min).round() : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: spec.label, style: t.type.label.style(13.5, p.ink)),
                    if (unit.isNotEmpty) TextSpan(text: '  $unit', style: t.type.label.style(12, p.inkMuted)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLoop)
                Container(
                  margin: const EdgeInsets.only(right: 4, left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(border: Border.all(color: p.inkFaint)),
                  child: Text('SP', style: t.type.number.style(12, p.inkMuted)),
                ),
              InkWell(
                onTap: () => _edit(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(_fmtValue(spec, value), style: t.type.number.style(16, p.accent, weight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _FineButton(icon: Icons.remove, onTap: () => _set(d - step), t: t),
              Expanded(
                child: Slider(
                  value: d.clamp(_dMin, _dMax).toDouble(),
                  min: _dMin,
                  max: _dMax,
                  divisions: divisions,
                  onChanged: _set,
                ),
              ),
              _FineButton(icon: Icons.add, onTap: () => _set(d + step), t: t),
            ],
          ),
        ],
      ),
    );
  }
}

class _FineButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final LowsysTheme t;
  const _FineButton({required this.icon, required this.onTap, required this.t});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
        icon: Icon(icon, size: 20, color: t.palette.inkMuted),
        onPressed: onTap,
      ),
    );
  }
}
