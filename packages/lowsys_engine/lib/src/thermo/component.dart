import 'dart:convert';

import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../data/components_json.dart';

enum VaporPressureKind { antoineLog10MmHgC, dippr101, leeKesler }

/// Pure-component constants (PHYSICS.md 2.1). SI units except [mw] (g/mol).
@immutable
class Component {
  final ComponentId id;
  final String name;

  /// g/mol (= kg/kmol)
  final double mw;

  /// K
  final double tb, tc;

  /// Pa
  final double pc;
  final double omega;

  /// J/mol
  final double dHvapTb;

  /// J/mol/K at 298.15 K; J/mol/K^2
  final double cp0, dCp;

  /// kg/m3 at tRef (K)
  final double rhoRef, tRef;
  final double? zraOverride;

  /// N/m at 298.15 K
  final double sigmaRef;
  final VaporPressureKind vpKind;
  final List<double> vpCoeffs;
  final List<double>? mcWilliams;
  final bool vaporOnly;

  const Component({
    required this.id,
    required this.name,
    required this.mw,
    required this.tb,
    required this.tc,
    required this.pc,
    required this.omega,
    required this.dHvapTb,
    required this.cp0,
    required this.dCp,
    required this.rhoRef,
    required this.tRef,
    this.zraOverride,
    required this.sigmaRef,
    required this.vpKind,
    required this.vpCoeffs,
    this.mcWilliams,
    this.vaporOnly = false,
  });

  factory Component.fromJson(ComponentId id, Map<String, Object?> j) {
    double d(String k) => (j[k]! as num).toDouble();
    final kind =
        VaporPressureKind.values.firstWhere((e) => e.name == j['vpKind']);
    return Component(
      id: id,
      name: j['name']! as String,
      mw: d('mw'),
      tb: d('tb'),
      tc: d('tc'),
      pc: d('pc'),
      omega: d('omega'),
      dHvapTb: d('dHvapTb'),
      cp0: d('cp0'),
      dCp: d('dCp'),
      rhoRef: d('rhoRef'),
      tRef: d('tRef'),
      zraOverride: (j['zraOverride'] as num?)?.toDouble(),
      sigmaRef: d('sigmaRef'),
      vpKind: kind,
      vpCoeffs: [
        for (final v in (j['vpCoeffs']! as List<Object?>))
          (v! as num).toDouble()
      ],
      mcWilliams: (j['mcWilliams'] as List<Object?>?)
          ?.map((e) => (e! as num).toDouble())
          .toList(),
      vaporOnly: (j['vaporOnly'] as bool?) ?? false,
    );
  }
}

/// Component database, parsed once from [componentsJson].
class ComponentDb {
  final Map<ComponentId, Component> _byId;
  ComponentDb._(this._byId);

  static ComponentDb? _cached;

  static ComponentDb load() {
    return _cached ??= () {
      final raw = jsonDecode(componentsJson) as Map<String, Object?>;
      return ComponentDb._({
        for (final e in raw.entries)
          e.key: Component.fromJson(e.key, e.value! as Map<String, Object?>),
      });
    }();
  }

  Component operator [](ComponentId id) {
    final c = _byId[id];
    if (c == null) throw ConfigException('Unknown component "$id"');
    return c;
  }

  bool contains(ComponentId id) => _byId.containsKey(id);
  Iterable<ComponentId> get ids => _byId.keys;
}
