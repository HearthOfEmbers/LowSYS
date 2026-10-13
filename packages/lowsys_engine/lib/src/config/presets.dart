import 'dart:convert';

import '../core/ids.dart';
import '../data/presets/bt.dart';
import '../data/presets/mw.dart';
import 'column_config.dart';

/// Shipped column presets (ENGINE_API.md 4.1). M1: `bt` and `bt_custom_alpha`.
abstract final class Presets {
  static const String bt = 'bt';
  static const String btCustomAlpha = 'bt_custom_alpha';
  static const String mw = 'mw';

  static const List<PresetId> ids = [bt, btCustomAlpha, mw];

  static final Map<PresetId, String> _json = {
    bt: btPresetJson,
    btCustomAlpha: btCustomAlphaPresetJson,
    mw: mwPresetJson,
  };

  /// Parses and validates the preset. Each call returns a fresh (immutable) config.
  static ColumnConfig byId(PresetId id) {
    final src = _json[id];
    if (src == null) throw ConfigException('Unknown preset "$id"');
    final cfg = ColumnConfig.fromJson(jsonDecode(src) as Map<String, Object?>);
    final problems = cfg.validate();
    if (problems.isNotEmpty)
      throw ConfigException('Preset $id invalid: ${problems.join('; ')}');
    return cfg;
  }

  /// Raw JSON of a preset.
  static String jsonOf(PresetId id) =>
      _json[id] ?? (throw ConfigException('Unknown preset "$id"'));
}
