import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../core/quantity.dart';

/// What a lever is and how far it may move (ENGINE_API.md 6.3). All values SI.
@immutable
class LeverSpec {
  final LeverId id;

  /// UI label (a key in later milestones; plain English in M1).
  final String label;
  final Quantity quantity;
  final double min, max, defaultValue;
  final Set<ThermoTier> tiers;

  /// When set: AUTO edits the loop SP, MAN edits the OP.
  final LoopTag? boundLoop;

  /// Condenser type, reboiler type, geometry.
  final bool requiresPause;

  /// 'feed' | 'top' | 'bottom' | 'column' | 'advanced' | 'crude'
  final String group;

  /// True for levers that only take integer values (feed tray, number of trays, mode switches).
  final bool integer;

  const LeverSpec({
    required this.id,
    required this.label,
    required this.quantity,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.tiers = const {ThermoTier.t1, ThermoTier.t2, ThermoTier.t3},
    this.boundLoop,
    this.requiresPause = false,
    required this.group,
    this.integer = false,
  });
}
