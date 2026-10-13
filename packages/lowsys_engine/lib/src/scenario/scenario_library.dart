import 'dart:convert';

import '../data/scenarios/drills.dart';
import '../data/scenarios/scenarios.dart';
import 'scenario_def.dart';

/// Shipped scenarios (SCOPE.md 6, ENGINE_API.md 11.8).
abstract final class Scenarios {
  static final Map<String, String> _guided = {
    'G1_meet_the_column': g1Json,
    'G2_min_reflux': g2Json,
    'G3_total_reflux': g3Json,
    'G4_q_line': g4Json,
    'G5_where_to_feed': g5Json,
    'G6_real_trays': g6Json,
    'G7_what_cmo_hides': g7Json,
    'G8_pressure_volatility': g8Json,
    'G9_azeotrope_wall': g9Json,
    'G10_other_azeotrope': g10Json,
    'G11_flooding': g11Json,
    'G12_turndown': g12Json,
  };

  /// Tier 2 drills: defined and testable (draws, scoring), playable from M4/M6.
  static final Map<String, String> _drills = {
    'H9_dont_trust_the_gauge': h9Json,
    'H10_valve_or_meter': h10Json,
  };

  /// Scenarios playable in this build.
  static List<String> get ids => _guided.keys.toList();

  /// Every definition, including the Tier 2 drills.
  static List<String> get allIds => [..._guided.keys, ..._drills.keys];

  static String jsonOf(String id) =>
      _guided[id] ?? _drills[id] ?? (throw ArgumentError('Unknown scenario $id'));

  static ScenarioDef byId(String id) =>
      ScenarioDef.fromJson(jsonDecode(jsonOf(id)) as Map<String, Object?>);

  static List<ScenarioDef> get all => [for (final id in ids) byId(id)];
}

/// M2 name of [Scenarios].
abstract final class ScenarioLibrary {
  static List<String> get ids => Scenarios.ids;
  static ScenarioDef byId(String id) => Scenarios.byId(id);
  static List<ScenarioDef> get all => Scenarios.all;
}
