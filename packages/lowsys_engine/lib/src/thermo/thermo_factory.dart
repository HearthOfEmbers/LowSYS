import '../config/column_config.dart';
import '../core/ids.dart';
import 'thermo_model.dart';
import 'tier1_constant_alpha.dart';
import 'tier2_raoult.dart';
import 'tier3_depriester.dart';
import 'tier3_nrtl.dart';

/// Builds thermo models from configurations (ENGINE_API.md 3.2).
abstract final class ThermoFactory {
  static ThermoModel build(ColumnConfig config, ThermoTier tier) {
    switch (tier) {
      case ThermoTier.t1:
        return Tier1ConstantAlpha.fromConfig(config);
      case ThermoTier.t2:
        return Tier2Raoult.fromConfig(config);
      case ThermoTier.t3:
        return buildTier3(config);
    }
  }

  /// The Tier-3 model of [config] (`sameAsTier2`: a plain Tier-2 model).
  static Tier2Raoult buildTier3(ColumnConfig config) {
    switch (config.tier3Model) {
      case Tier3Model.nrtl:
        return Tier3Nrtl.fromConfig(config);
      case Tier3Model.dePriester:
        return Tier3DePriester.fromConfig(config);
      case Tier3Model.sameAsTier2:
        return Tier2Raoult.fromConfig(config);
    }
  }
}
