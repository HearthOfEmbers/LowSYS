import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';

/// Display names of the diagnosis vocabulary (ENGINE_API.md 11.2, with the M6 additions).
String diagnosisLabel(String id) {
  const names = {
    'cooling': S.coolingWater,
    'fouling': S.fouling,
    'inerts': S.nonCondensables,
    'foaming': S.foaming,
    'trayDamage': S.trayDamage,
    'instrument': S.instrument,
    'valve': S.valve,
    'feedUpset': S.feedUpset,
    'steam': S.steamSupply,
    'thermosyphon': S.thermosyphon,
    'maldistribution': S.maldistribution,
    'none': S.nothingIsWrong,
    'restriction': S.restriction,
    'condensate': S.condensateSteamTrap,
    'condenser': S.condenser,
    'reboiler': S.reboiler,
    'rectifying': S.rectifyingSection,
    'stripping': S.strippingSection,
    'feed': S.feed,
    'packedBed': S.packedBed,
    'packingDamage': S.packingDamageCrushed,
    'flooding': S.floodingOperatingLimit,
    'steamLoss': S.strippingSteamLoss,
    'pumparound': S.pumparound,
    'furnace': S.furnaceCOT,
    'column': S.wholeColumn,
    'steamSupply': S.steamSupply,
    'tsInletLine': S.reboilerInletLine,
    'tsOutletLine': S.reboilerOutletLine,
    'bias': S.bias,
    'drift': S.drift,
    'stuck': S.stuck,
    'signalLoss': S.signalLoss,
    'plugged': S.pluggedLine,
    'spiking': S.spiking,
    'coated': S.coated,
  };
  if (id.startsWith('instrument:')) return 'Instrument ${id.substring(11)}';
  if (id.startsWith('valve:')) return 'Valve ${id.substring(6)}';
  if (id.startsWith('bed:')) return bedLabel(int.tryParse(id.substring(4)) ?? 1);
  if (id.startsWith('steam:')) return steamLabel(id.substring(6));
  return names[id] ?? id;
}

/// Display name of a crude steam injection point (M9): bottom, ss1, ss2, ss3.
String steamLabel(String point) => switch (point) {
      'bottom' => S.bottomStrippingSteamFc,
      'ss1' => S.keroStripperSteamFc,
      'ss2' => S.dieselStripperSteamFc,
      'ss3' => S.agoStripperSteamFc,
      _ => 'Steam $point',
    };

/// Display name of packed bed [b] (1 = top): the PDT that watches it is PDT-(101 + b) (PHYSICS.md 10.5).
String bedLabel(int b) => b == 1 ? 'Upper bed (PDT-102)' : (b == 2 ? 'Lower bed (PDT-103)' : 'Bed $b (PDT-${101 + b})');

/// The locations offered by a drill: `instrument:*` and `valve:*` expand to every tag visible in the drill.
List<String> expandLocations(DiagnosisDef d, SimSnapshot? s) {
  final out = <String>[];
  for (final l in d.locations) {
    if (l == 'instrument:*') {
      for (final i in s?.instruments ?? const <InstrumentReading>[]) {
        out.add('instrument:${i.tag}');
      }
    } else if (l == 'bed:*') {
      for (final b in s?.beds ?? const <PackedBedSnapshot>[]) {
        out.add('bed:${b.bed}');
      }
    } else if (l == 'steam:*') {
      for (final q in const ['bottom', 'ss1', 'ss2', 'ss3']) {
        out.add('steam:$q');
      }
    } else if (l == 'valve:*') {
      for (final v in s?.valves ?? const <ValveSnapshot>[]) {
        out.add('valve:${v.id}');
      }
    } else {
      out.add(l);
    }
  }
  return out;
}

/// Diagnose dialog: a category, a location and, for an instrument fault in a drill that lists modes, the failure mode.
Future<void> showDiagnoseDialog(BuildContext context, SimController sim) async {
  final def = sim.scenarioDef;
  final dg = def?.diagnosis;
  if (def == null || dg == null) return;
  final t = LowsysThemeScope.of(context);
  final p = t.palette;
  final locations = expandLocations(dg, sim.snapshot.value);
  String? category, location, mode;
  final res = await showDialog<Diagnosis>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(S.diagnose, style: t.type.display.style(19, p.ink)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.whatKindOfFault, style: t.type.label.style(14, p.inkMuted)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final c in dg.categories)
                    ChoiceChip(
                      key: ValueKey('diag-cat-$c'),
                      label: Text(diagnosisLabel(c), style: t.type.label.style(13, p.ink)),
                      selected: category == c,
                      onSelected: (_) => setS(() => category = c),
                    ),
                ]),
                const SizedBox(height: 10),
                Text(S.whereIsIt, style: t.type.label.style(14, p.inkMuted)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final l in locations)
                    ChoiceChip(
                      key: ValueKey('diag-loc-$l'),
                      label: Text(diagnosisLabel(l), style: t.type.label.style(13, p.ink)),
                      selected: location == l,
                      onSelected: (_) => setS(() => location = l),
                    ),
                ]),
                if (dg.modes.isNotEmpty && category == 'instrument') ...[
                  const SizedBox(height: 10),
                  Text(S.howDidItFail, style: t.type.label.style(14, p.inkMuted)),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final m in dg.modes)
                      ChoiceChip(
                        label: Text(diagnosisLabel(m), style: t.type.label.style(13, p.ink)),
                        selected: mode == m,
                        onSelected: (_) => setS(() => mode = mode == m ? null : m),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
          FilledButton(
            key: const ValueKey('diag-submit'),
            onPressed: category == null || location == null
                ? null
                : () => Navigator.pop(ctx, Diagnosis(category: category!, location: location!, mode: mode)),
            child: const Text(S.submit),
          ),
        ],
      ),
    ),
  );
  if (res == null) return;
  final r = await sim.submitDiagnosis(res);
  if (!context.mounted) return;
  final msg = S.diagnosisResult(r.fullyCorrect, r.categoryOk, r.locationOk, r.attemptsLeft);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  if (r.fullyCorrect || r.attemptsLeft <= 0) await sim.finishScenario();
}
