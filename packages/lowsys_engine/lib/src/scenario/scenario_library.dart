import 'dart:convert';

import '../data/scenarios/scenarios.dart';
import 'scenario_def.dart';

/// Shipped scenarios (SCOPE.md 6). M2: G11 and G12.
abstract final class ScenarioLibrary {
  static final Map<String, String> _json = {
    'G11_flooding': g11Json,
    'G12_turndown': g12Json,
  };

  static List<String> get ids => _json.keys.toList();

  static ScenarioDef byId(String id) {
    final src = _json[id] ?? (throw ArgumentError('Unknown scenario $id'));
    return ScenarioDef.fromJson(jsonDecode(src) as Map<String, Object?>);
  }

  static List<ScenarioDef> get all => [for (final id in ids) byId(id)];
}
