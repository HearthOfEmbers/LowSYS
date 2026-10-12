import '../config/column_config.dart';
import '../core/ids.dart';
import 'thermo_model.dart';
import 'tier1_constant_alpha.dart';

/// Builds thermo models from configurations (ENGINE_API.md 3.2).
abstract final class ThermoFactory {
  static ThermoModel build(ColumnConfig config, ThermoTier tier) {
    switch (tier) {
      case ThermoTier.t1:
        return Tier1ConstantAlpha.fromConfig(config);
      case ThermoTier.t2:
      case ThermoTier.t3:
        throw UnsupportedError(
            'Thermo ${tier.name} arrives with a later milestone (M4/M5)');
    }
  }
}
