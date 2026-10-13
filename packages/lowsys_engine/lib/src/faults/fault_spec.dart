import 'package:meta/meta.dart';

import '../core/ids.dart';

enum FaultType {
  trayDamage,
  trayFouling,
  foaming,
  feedComposition,
  feedThermal,
  coolingLoss,
  condenserFouling,
  nonCondensables,
  refluxPumpTrip,
  reboilerFouling,
  condensateBackup,
  steamHeaderLoss,
  tsInletRestriction,
  tsOutletRestriction,
  instrument,
  transmitter,
  valve,
  packingMaldistribution,
  packingCrush,
  strippingSteamLoss,
  pumparoundTrip,
  cotUpset,
}

/// Where a fault acts: a stage range, a feed, or a tagged item (ENGINE_API.md 9).
@immutable
class FaultLocation {
  final int? stageFrom, stageTo;
  final int? feedIndex;

  /// Packed bed, 1-based from the top (F21, F23; M8).
  final int? bed;
  final String? tagName;

  /// Equipment id for the Tier-2 faults: `feed`, `condenser`, `reflux`, `reboiler`, `overhead`, `steam`.
  final String? equipmentId;
  const FaultLocation._(
      {this.stageFrom,
      this.stageTo,
      this.feedIndex,
      this.bed,
      this.tagName,
      this.equipmentId});

  /// Stages [from]..[to] counted from the top (trays 1..N).
  const FaultLocation.stages(int from, int to)
      : this._(stageFrom: from, stageTo: to);
  const FaultLocation.feed(int index) : this._(feedIndex: index);
  const FaultLocation.bed(int bed) : this._(bed: bed);
  const FaultLocation.tag(String tag) : this._(tagName: tag);
  const FaultLocation.equipment(String id) : this._(equipmentId: id);
  const FaultLocation.whole() : this._(stageFrom: 1, stageTo: 1000);

  bool coversStage(int j) =>
      stageFrom != null && j >= stageFrom! && j <= stageTo!;

  Map<String, Object?> toJson() => {
        if (stageFrom != null) 'from': stageFrom,
        if (stageTo != null) 'to': stageTo,
        if (feedIndex != null) 'feed': feedIndex,
        if (bed != null) 'bed': bed,
        if (tagName != null) 'tag': tagName,
        if (equipmentId != null) 'equipment': equipmentId,
      };

  factory FaultLocation.fromJson(Map<String, Object?> j) => FaultLocation._(
        stageFrom: (j['from'] as num?)?.toInt(),
        stageTo: (j['to'] as num?)?.toInt(),
        feedIndex: (j['feed'] as num?)?.toInt(),
        bed: (j['bed'] as num?)?.toInt(),
        tagName: j['tag'] as String?,
        equipmentId: j['equipment'] as String?,
      );

  @override
  String toString() => stageFrom != null
      ? (stageFrom == stageTo
          ? 'tray $stageFrom'
          : (stageTo! >= 1000 ? 'all trays' : 'trays $stageFrom-$stageTo'))
      : (feedIndex != null ? 'feed' : (bed != null ? 'bed $bed' : (tagName ?? equipmentId ?? '')));
}

/// A fault to inject (ENGINE_API.md 9). Severity s_f in (0, 1]; current severity follows PHYSICS.md (11.1).
@immutable
class FaultSpec {
  final FaultType type;
  final FaultLocation location;
  final double severity;

  /// Sim time (s) at which the fault starts.
  final double onset;

  /// Ramp (s); 0 = step.
  final double ramp;
  final Map<String, Object?> params;

  /// Drills: not reported in snapshots.
  final bool hidden;
  const FaultSpec({
    required this.type,
    required this.location,
    required this.severity,
    this.onset = 0,
    this.ramp = 0,
    this.params = const {},
    this.hidden = false,
  });

  Map<String, Object?> toJson() => {
        'type': type.name,
        'location': location.toJson(),
        'severity': severity,
        'onset': onset,
        'ramp': ramp,
        'params': params,
        'hidden': hidden,
      };

  factory FaultSpec.fromJson(Map<String, Object?> j) => FaultSpec(
        type: FaultType.values.firstWhere((e) => e.name == j['type']),
        location:
            FaultLocation.fromJson(j['location']! as Map<String, Object?>),
        severity: (j['severity']! as num).toDouble(),
        onset: (j['onset']! as num).toDouble(),
        ramp: (j['ramp']! as num).toDouble(),
        params:
            Map<String, Object?>.from(j['params']! as Map<Object?, Object?>),
        hidden: (j['hidden'] as bool?) ?? false,
      );
}

/// A fault as reported in snapshots (sandbox only).
@immutable
class FaultInfo {
  final FaultId id;
  final FaultType type;
  final FaultLocation location;

  /// Current severity s(t) and final severity.
  final double severity, finalSeverity;
  final double onset, ramp;
  final Map<String, Object?> params;
  const FaultInfo({
    required this.id,
    required this.type,
    required this.location,
    required this.severity,
    required this.finalSeverity,
    required this.onset,
    required this.ramp,
    this.params = const {},
  });

  String get description => '${faultLabel(type)} at $location';
}

/// SCOPE.md 5 names.
String faultLabel(FaultType t) {
  switch (t) {
    case FaultType.trayDamage:
      return 'Broken tray (F04)';
    case FaultType.trayFouling:
      return 'Fouled trays (F05)';
    case FaultType.foaming:
      return 'Foaming (F06)';
    case FaultType.feedComposition:
      return 'Feed composition upset (F07)';
    case FaultType.feedThermal:
      return 'Feed thermal upset (F08)';
    case FaultType.coolingLoss:
      return 'Loss of condenser cooling (F09)';
    case FaultType.condenserFouling:
      return 'Condenser fouling (F10)';
    case FaultType.nonCondensables:
      return 'Non-condensables in the overhead (F11)';
    case FaultType.refluxPumpTrip:
      return 'Reflux pump trip (F12)';
    case FaultType.reboilerFouling:
      return 'Reboiler fouling (F13)';
    case FaultType.condensateBackup:
      return 'Reboiler condensate backup (F14)';
    case FaultType.steamHeaderLoss:
      return 'Steam header pressure loss (F15)';
    case FaultType.tsInletRestriction:
      return 'Thermosyphon inlet restriction (F17)';
    case FaultType.tsOutletRestriction:
      return 'Thermosyphon outlet restriction (F18)';
    case FaultType.packingMaldistribution:
      return 'Packing maldistribution (F21)';
    case FaultType.packingCrush:
      return 'Packing crushed (F23)';
    default:
      return t.name;
  }
}
