import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';
import '../theme/themes/registry.dart';
import 'scenario_ui.dart';

String formatClock(double t) {
  final s = t.floor();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}';
}

String speedLabel(double v) => v == 0 ? 'Pause' : '${v.toStringAsFixed(0)}×';

const Map<String, String> kPresetNames = {
  Presets.bt: 'Benzene–toluene (textbook)',
  Presets.mw: 'Methanol–water',
  Presets.btCustomAlpha: 'Custom α',
  Presets.ew: 'Ethanol–water',
  Presets.ac: 'Acetone–chloroform',
  Presets.c4: 'Isobutane–n-butane (C4 splitter)',
  Presets.debut: 'Debutanizer (6 components)',
  Presets.deprop: 'Depropanizer (6 components)',
};

/// Pause, clock, speed, steady indicator, run-to-steady and the preset menu (SCOPE.md 3.2).
class TimeBar extends StatelessWidget {
  /// Compact: drops the text of the steady chip next to the clock when space is tight.
  final bool dense;
  const TimeBar({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) {
        final paused = sim.paused;
        return SizedBox(
          height: dense ? 46 : 52,
          child: Row(
            children: [
              IconButton(
                tooltip: paused ? 'Resume (Space)' : 'Pause (Space)',
                style: dense
                    ? IconButton.styleFrom(
                        minimumSize: const Size(44, 48),
                        padding: EdgeInsets.zero,
                      )
                    : null,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: p.accent,
                  size: 28,
                ),
                onPressed: sim.togglePause,
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ValueListenableBuilder<SimSnapshot?>(
                    valueListenable: sim.snapshot,
                    builder: (_, s, __) => Text(
                      formatClock(s?.time ?? 0),
                      style: t.type.number.style(
                        dense ? 14 : 15,
                        p.ink,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _SpeedMenu(sim: sim),
              _TierBadge(sim: sim),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _SteadyChip(sim: sim, dense: dense),
                ),
              ),
              IconButton(
                tooltip: 'Run to steady state (S)',
                style: dense
                    ? IconButton.styleFrom(
                        minimumSize: const Size(44, 48),
                        padding: EdgeInsets.zero,
                      )
                    : null,
                icon: Icon(Icons.fast_forward_rounded, color: p.ink),
                onPressed: sim.runToSteady,
              ),
              _PresetMenu(sim: sim, dense: dense),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  final SimController sim;
  const _SpeedMenu({required this.sim});

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return PopupMenuButton<double>(
      tooltip: 'Simulation speed (+ / -)',
      initialValue: sim.speed,
      onSelected: sim.setSpeed,
      itemBuilder: (_) => [
        for (final v in kSpeeds)
          PopupMenuItem<double>(
            value: v,
            height: 44,
            child: Text(speedLabel(v), style: t.type.number.style(15, p.ink)),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        child: ValueListenableBuilder<double>(
          valueListenable: sim.achievedSpeed,
          builder: (_, ach, __) {
            final limited = sim.speedLimited && !sim.paused;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  limited
                      ? '≈${ach.toStringAsFixed(0)}×'
                      : speedLabel(sim.speed),
                  style: t.type.number.style(
                    15,
                    limited ? p.warn : p.accent,
                    weight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: p.inkMuted, size: 18),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// T1 / T2 / T3 badge: tap to switch the thermodynamic tier. The switch keeps the top vapour and the distillate
/// (PHYSICS.md 13.5), so the learner sees the vapour profile change and the products stay put. T3 is hidden for
/// systems whose Tier 3 is Tier 2 (`bt`, `crude`).
class _TierBadge extends StatelessWidget {
  final SimController sim;
  const _TierBadge({required this.sim});

  static const _tips = {
    ThermoTier.t1: 'Tier 1: constant relative volatility and molar overflow.',
    ThermoTier.t2: 'Tier 2: ideal VLE (Raoult) with energy balances.',
    ThermoTier.t3: 'Tier 3: non-ideal VLE (NRTL or DePriester K) with energy balances.',
  };

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (_, s, __) {
        final tier = s?.tier ?? ThermoTier.t1;
        final avail = [for (final x in ThermoTier.values) if (sim.runner.config.availableTiers.contains(x)) x];
        final next = avail.isEmpty ? tier : avail[(avail.indexOf(tier) + 1) % avail.length];
        final locked = sim.lockedLevers.contains('tier');
        final label = 'T${tier.index + 1}';
        return Tooltip(
          message: '${_tips[tier]} Tap for ${_tips[next]!.split(':').first}.',
          child: InkWell(
            onTap: locked || s == null || next == tier ? null : () => sim.setTier(next),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 44),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: tier != ThermoTier.t1 ? p.accent : p.inkMuted, width: 1.4),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  label,
                  key: const ValueKey('tier-badge'),
                  style: t.type.number.style(14, tier != ThermoTier.t1 ? p.accent : p.inkMuted, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SteadyChip extends StatelessWidget {
  final SimController sim;
  final bool dense;
  const _SteadyChip({required this.sim, required this.dense});

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<SimSnapshot?>(
      valueListenable: sim.snapshot,
      builder: (_, s, __) {
        final steady = s?.steady.isSteady ?? false;
        final c = steady ? p.ok : p.warn;
        return Tooltip(
          message: steady
              ? 'Steady state (residual below tolerance)'
              : 'Transient: the column is still moving',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: steady ? c : Colors.transparent,
                  border: Border.all(color: c, width: 1.6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                steady ? 'Steady' : 'Transient',
                style: t.type.label.style(12.5, c),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PresetMenu extends StatelessWidget {
  final SimController sim;
  final bool dense;
  const _PresetMenu({required this.sim, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return PopupMenuButton<String>(
      tooltip: 'Presets and options',
      icon: Icon(Icons.more_vert, color: p.ink),
      style: dense
          ? IconButton.styleFrom(
              minimumSize: const Size(44, 48),
              padding: EdgeInsets.zero,
            )
          : null,
      onSelected: (v) {
        if (v == 'reset') {
          sim.reset();
        } else if (v == 'rmin') {
          sim.toggleRmin();
        } else if (v == 'units') {
          sim.toggleUnits();
        } else if (v == 'shading') {
          sim.compositionShading.value = !sim.compositionShading.value;
        } else if (v.startsWith('theme:')) {
          sim.setTheme(v.substring(6));
        } else if (v == 'scenarios') {
          showScenarioList(context, sim);
        } else if (v.startsWith('save')) {
          sim.saveSandbox(int.parse(v.substring(4)));
        } else if (v.startsWith('load')) {
          sim.loadSandbox(int.parse(v.substring(4)));
        } else if (v == 'leave') {
          sim.leaveScenario();
          sim.reset();
        } else {
          sim.load(v);
        }
      },
      itemBuilder: (_) => [
        for (final e in kPresetNames.entries)
          CheckedPopupMenuItem<String>(
            value: e.key,
            checked: sim.presetId == e.key,
            child: Text(e.value, style: t.type.label.style(14, p.ink)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'scenarios',
          child: Text(
            'Guided scenarios…',
            style: t.type.label.style(14, p.ink),
          ),
        ),
        if (sim.scenarioDef != null)
          PopupMenuItem<String>(
            value: 'leave',
            child: Text(
              'Leave scenario (sandbox)',
              style: t.type.label.style(14, p.ink),
            ),
          ),
        PopupMenuItem<String>(
          value: 'units',
          child: Text(
            'Units: ${sim.units.value == UnitSystem.si ? 'SI → US field' : 'US field → SI'} (U)',
            style: t.type.label.style(14, p.ink),
          ),
        ),
        for (final th in kThemes)
          CheckedPopupMenuItem<String>(
            value: 'theme:${th.id}',
            checked: sim.themeId.value == th.id,
            child: Text('Theme: ${th.name}', style: t.type.label.style(14, p.ink)),
          ),
        if (sim.themeId.value == 'controlRoom')
          CheckedPopupMenuItem<String>(
            value: 'shading',
            checked: sim.compositionShading.value,
            child: Text('Composition shading', style: t.type.label.style(14, p.ink)),
          ),
        PopupMenuItem<String>(
          value: 'rmin',
          child: Text(
            sim.showRmin
                ? 'Hide R_min construction'
                : 'Show R_min construction',
            style: t.type.label.style(14, p.ink),
          ),
        ),
        if (sim.saveStore != null && sim.scenarioDef == null) ...[
          for (final n in [1, 2, 3])
            PopupMenuItem<String>(
              value: 'save$n',
              child: Text(
                'Save sandbox to slot $n',
                style: t.type.label.style(14, p.ink),
              ),
            ),
          for (final n in [1, 2, 3])
            PopupMenuItem<String>(
              value: 'load$n',
              child: Text(
                'Load sandbox slot $n',
                style: t.type.label.style(14, p.ink),
              ),
            ),
        ],
        PopupMenuItem<String>(
          value: 'reset',
          child: Text(
            'Reset to steady state',
            style: t.type.label.style(14, p.ink),
          ),
        ),
      ],
    );
  }
}
