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
    case Quantity.energyRate:
      return 10;
    case Quantity.temperature:
      return 0.5;
    case Quantity.temperatureDelta:
      return 1;
    case Quantity.volumeFlowLiquid:
      return 5;
    default:
      return 0.05;
  }
}

String _fmtValue(LeverSpec s, double si, UnitSystem u) {
  if (s.integer) return si.round().toString();
  final d = u.fromSI(s.quantity, si);
  switch (s.quantity) {
    case Quantity.molarFlow:
      return d.toStringAsFixed(1);
    case Quantity.percent:
      return d.toStringAsFixed(0);
    case Quantity.fraction:
      return d.toStringAsFixed(3);
    case Quantity.energyRate:
      return d.toStringAsFixed(1);
    case Quantity.temperature:
    case Quantity.temperatureDelta:
      return d.toStringAsFixed(1);
    case Quantity.volumeFlowLiquid:
      return d.toStringAsFixed(0);
    default:
      return d.toStringAsFixed(2);
  }
}

/// Levers tab: grouped lever tiles (SCOPE.md 3.2 ControlPanel).
class LeverPanel extends StatelessWidget {
  final ScrollController? controller;
  final EdgeInsets padding;
  final Widget? header;
  const LeverPanel({
    super.key,
    this.controller,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(12, 4, 12, 24),
  });

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([sim, sim.units, sim.scenarioTick]),
      builder: (context, _) {
        if (!sim.loaded) return const SizedBox();
        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: sim.leverValues,
          builder: (context, values, _) {
            final levers = sim.levers;
            final u = sim.units.value;
            final locked = sim.lockedLevers;
            LeverSpec? byId(String id) {
              for (final l in levers) {
                if (l.id == id) return l;
              }
              return null;
            }

            final snap = sim.snapshot.value;
            final t2 = snap != null && snap.tier != ThermoTier.t1;
            final ratioMode = (values['refluxMode'] ?? 0) >= 0.5;
            final full = (values['hydraulics'] ?? 0) >= 0.5;
            final children = <Widget>[if (header != null) header!];
            void group(String title, List<Widget> tiles) {
              if (tiles.isEmpty) return;
              children.add(_GroupHeader(title: title, t: t));
              children.addAll(tiles);
            }

            Widget tile(String id) => LeverTile(
              spec: byId(id)!,
              value: values[id] ?? byId(id)!.defaultValue,
              sim: sim,
              units: u,
              locked: locked.contains(id),
            );
            final feedZ = levers.firstWhere((l) => l.id.startsWith('feedZ.'));
            group('FEED', [
              tile('feedFlow'),
              tile(feedZ.id),
              if (t2) tile('feedT') else tile('feedQ'),
              if (t2) _FeedCondition(snap: snap, t: t),
              tile('feedStage'),
            ]);
            group('TOP', [
              _Segments(
                options: const ['Reflux flow', 'Reflux ratio'],
                selected: ratioMode ? 1 : 0,
                onSelect: (i) => sim.setLever('refluxMode', i.toDouble()),
                t: t,
              ),
              tile(ratioMode ? 'refluxRatio' : 'refluxFlow'),
              tile('drumLevelSp'),
              if (t2) tile('pTop'),
              if (t2) tile('refluxSubcooling'),
            ]);
            group('BOTTOM', [
              if (t2) tile('reboilerDuty') else tile('boilup'),
              tile('sumpLevelSp'),
            ]);
            if (t2) {
              group('UTILITIES', [
                _Labeled(
                  label: 'Condenser',
                  t: t,
                  child: _Segments(
                    options: const ['Total', 'Partial'],
                    selected: (values['condenserType'] ?? 0) >= 0.5 ? 1 : 0,
                    onSelect: locked.contains('condenserType')
                        ? null
                        : (i) => sim.setLever('condenserType', i.toDouble()),
                    t: t,
                  ),
                ),
                if ((values['condenserType'] ?? 0) >= 0.5) tile('cwOP'),
                tile('inertVent'),
                tile('cwInletT'),
                tile('cwMaxFlow'),
                tile('steamHeaderP'),
              ]);
              group('TRAY TEMPERATURE CONTROL', [
                _Labeled(
                  label: 'TC-101 (cascade to the reboiler duty)',
                  t: t,
                  child: _Segments(
                    options: const ['Off', 'On'],
                    selected: (values['tc101Enable'] ?? 0) >= 0.5 ? 1 : 0,
                    onSelect: locked.contains('tc101Enable')
                        ? null
                        : (i) => sim.setLever('tc101Enable', i.toDouble()),
                    t: t,
                  ),
                ),
                if ((values['tc101Enable'] ?? 0) >= 0.5) ...[
                  tile('tc101Tray'),
                  tile('tc101Sp'),
                ],
              ]);
            }
            group('COLUMN', [
              tile('nTrays'),
              tile('murphree'),
              if (byId('alpha') != null) tile('alpha'),
            ]);
            group('INTERNALS', [
              _Labeled(
                label: 'Hydraulics',
                t: t,
                child: _Segments(
                  options: const ['Ideal', 'Full'],
                  selected: full ? 1 : 0,
                  onSelect: locked.contains('hydraulics')
                      ? null
                      : (i) => sim.setLever('hydraulics', i.toDouble()),
                  t: t,
                ),
              ),
              if (full)
                _Labeled(
                  label: 'Tray type',
                  t: t,
                  child: _Segments(
                    options: const ['Sieve', 'Valve'],
                    selected: (values['trayType.0'] ?? 0) >= 0.5 ? 1 : 0,
                    onSelect: locked.contains('trayType.0')
                        ? null
                        : (i) => sim.setLever('trayType.0', i.toDouble()),
                    t: t,
                  ),
                ),
              if (full)
                _Labeled(
                  label: 'Antifoam',
                  t: t,
                  child: _Segments(
                    options: const ['Off', 'On'],
                    selected: (values['antifoam'] ?? 0) >= 0.5 ? 1 : 0,
                    onSelect: (i) => sim.setLever('antifoam', i.toDouble()),
                    t: t,
                  ),
                ),
            ]);
            group('INSTRUMENTS', [
              _Labeled(
                label: 'Measurement noise',
                t: t,
                child: _Segments(
                  options: const ['Off', 'On'],
                  selected: (values['noise'] ?? 0) >= 0.5 ? 1 : 0,
                  onSelect: locked.contains('noise')
                      ? null
                      : (i) => sim.setLever('noise', i.toDouble()),
                  t: t,
                ),
              ),
              _Labeled(
                label: 'View',
                t: t,
                child: _Segments(
                  options: const [
                    'Model (true values)',
                    'Plant (readings only)',
                  ],
                  selected: (values['view'] ?? 0) >= 0.5 ? 1 : 0,
                  onSelect: locked.contains('view')
                      ? null
                      : (i) => sim.setLever('view', i.toDouble()),
                  t: t,
                ),
              ),
              _Labeled(
                label: 'Loop on a bad signal',
                t: t,
                child: _Segments(
                  options: const ['Keeps running', 'Drops to MAN'],
                  selected: (values['badPvShed'] ?? 1) >= 0.5 ? 1 : 0,
                  onSelect: locked.contains('badPvShed')
                      ? null
                      : (i) => sim.setLever('badPvShed', i.toDouble()),
                  t: t,
                ),
              ),
            ]);
            return ListView(
              controller: controller,
              padding: padding,
              children: children,
            );
          },
        );
      },
    );
  }
}

/// Feed condition read-out in Tiers 2/3: q and the vapour fraction from the feed enthalpy (PHYSICS.md 3.15).
class _FeedCondition extends StatelessWidget {
  final SimSnapshot snap;
  final LowsysTheme t;
  const _FeedCondition({required this.snap, required this.t});
  @override
  Widget build(BuildContext context) {
    final q = snap.streams[StreamId.feed]?.q ?? double.nan;
    final p = t.palette;
    final text = q.isNaN
        ? 'q: —'
        : q > 1.0005
            ? 'q = ${q.toStringAsFixed(2)}  subcooled liquid'
            : q > 0.9995
                ? 'q = 1.00  saturated liquid'
                : q >= 0
                    ? 'q = ${q.toStringAsFixed(2)}  part vapour (${(100 * (1 - q)).toStringAsFixed(0)} % vapour)'
                    : 'q = ${q.toStringAsFixed(2)}  superheated vapour';
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2),
      child: Text(text, key: const ValueKey('feed-q'), style: t.type.number.style(12.5, p.inkMuted)),
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
      child: Row(
        children: [
          Text(
            title,
            style: t.type.display.style(14, p.accent, weight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: p.gridMajor)),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  final LowsysTheme t;
  const _Labeled({required this.label, required this.child, required this.t});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.type.label.style(13.5, t.palette.ink)),
        const SizedBox(height: 3),
        child,
      ],
    ),
  );
}

class _Segments extends StatelessWidget {
  final List<String> options;
  final int selected;
  final void Function(int)? onSelect;
  final LowsysTheme t;
  const _Segments({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.t,
  });
  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: InkWell(
              onTap: onSelect == null ? null : () => onSelect!(i),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected
                      ? p.accent.withValues(alpha: 0.18)
                      : Colors.transparent,
                  border: Border.all(
                    color: i == selected ? p.accent : p.gridMajor,
                  ),
                ),
                child: Text(
                  options[i],
                  style: t.type.label.style(
                    13,
                    i == selected
                        ? p.accent
                        : (onSelect == null ? p.inkFaint : p.inkMuted),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Slider with fine -/+ buttons and tap-to-type numeric entry (SCOPE.md 3.3).
class LeverTile extends StatelessWidget {
  final LeverSpec spec;
  final double value;
  final SimController sim;
  final UnitSystem units;
  final bool locked;
  const LeverTile({
    super.key,
    required this.spec,
    required this.value,
    required this.sim,
    required this.units,
    this.locked = false,
  });

  double get _dMin =>
      spec.integer ? spec.min : units.fromSI(spec.quantity, spec.min);
  double get _dMax =>
      spec.integer ? spec.max : units.fromSI(spec.quantity, spec.max);
  double _toDisplay(double si) =>
      spec.integer ? si : units.fromSI(spec.quantity, si);
  double _toSI(double d) => spec.integer ? d : units.toSI(spec.quantity, d);

  void _set(double display) {
    if (locked) return;
    final c = display.clamp(_dMin, _dMax).toDouble();
    sim.setLever(spec.id, spec.integer ? c.roundToDouble() : _toSI(c));
  }

  Future<void> _edit(BuildContext context) async {
    if (locked) return;
    final t = LowsysThemeScope.of(context);
    final ctl = TextEditingController(text: _fmtValue(spec, value, units));
    final unit = spec.integer ? '' : units.symbol(spec.quantity);
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(spec.label, style: t.type.display.style(18, t.palette.ink)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: t.type.number.style(18, t.palette.accent),
          decoration: InputDecoration(
            suffixText: unit,
            helperText:
                'Range ${_dMin.toStringAsFixed(spec.integer ? 0 : 2)} to ${_dMax.toStringAsFixed(spec.integer ? 0 : 2)}',
          ),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (res != null) _set(res);
  }

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final unit = spec.integer ? '' : units.symbol(spec.quantity);
    final step = _fineStep(spec);
    final d = _toDisplay(value);
    final isLoop = spec.boundLoop != null && !spec.id.contains('Valve');
    final divisions = spec.integer ? (spec.max - spec.min).round() : null;
    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: p.inkMuted,
                    ),
                  ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: spec.label,
                          style: t.type.label.style(13.5, p.ink),
                        ),
                        if (unit.isNotEmpty)
                          TextSpan(
                            text: '  $unit',
                            style: t.type.label.style(12, p.inkMuted),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLoop)
                  Container(
                    margin: const EdgeInsets.only(right: 4, left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: p.inkFaint),
                    ),
                    child: Text(
                      'SP',
                      style: t.type.number.style(12, p.inkMuted),
                    ),
                  ),
                InkWell(
                  onTap: () => _edit(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Text(
                      _fmtValue(spec, value, units),
                      style: t.type.number.style(
                        16,
                        p.accent,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                _FineButton(
                  icon: Icons.remove,
                  onTap: locked ? null : () => _set(d - step),
                  t: t,
                ),
                Expanded(
                  child: Slider(
                    value: d.clamp(_dMin, _dMax).toDouble(),
                    min: _dMin,
                    max: _dMax,
                    divisions: divisions,
                    onChanged: locked ? null : _set,
                  ),
                ),
                _FineButton(
                  icon: Icons.add,
                  onTap: locked ? null : () => _set(d + step),
                  t: t,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FineButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
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
