import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/ids.dart';

/// Tray geometry (PHYSICS.md 5.1). Defaults are the benzene-toluene preset.
@immutable
class TrayGeometry {
  final double diameter,
      traySpacing,
      downcomerFraction,
      weirHeight,
      apronClearance;
  final double holeFraction, holeDiameter, orificeCoeff;
  final double valveOpenFraction, valveClosedRatio, valveLiftDp, valveCoeff;
  final double downcomerAeration, systemFactor;

  const TrayGeometry({
    this.diameter = 1.2,
    this.traySpacing = 0.9,
    this.downcomerFraction = 0.12,
    this.weirHeight = 0.05,
    this.apronClearance = 0.038,
    this.holeFraction = 0.10,
    this.holeDiameter = 0.0127,
    this.orificeCoeff = 0.73,
    this.valveOpenFraction = 0.14,
    this.valveClosedRatio = 0.25,
    this.valveLiftDp = 190,
    this.valveCoeff = 0.65,
    this.downcomerAeration = 0.5,
    this.systemFactor = 1.0,
  });

  factory TrayGeometry.fromJson(Map<String, Object?> j) {
    const d = TrayGeometry();
    double g(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return TrayGeometry(
      diameter: g('diameter', d.diameter),
      traySpacing: g('traySpacing', d.traySpacing),
      downcomerFraction: g('downcomerFraction', d.downcomerFraction),
      weirHeight: g('weirHeight', d.weirHeight),
      apronClearance: g('apronClearance', d.apronClearance),
      holeFraction: g('holeFraction', d.holeFraction),
      holeDiameter: g('holeDiameter', d.holeDiameter),
      orificeCoeff: g('orificeCoeff', d.orificeCoeff),
      valveOpenFraction: g('valveOpenFraction', d.valveOpenFraction),
      valveClosedRatio: g('valveClosedRatio', d.valveClosedRatio),
      valveLiftDp: g('valveLiftDp', d.valveLiftDp),
      valveCoeff: g('valveCoeff', d.valveCoeff),
      downcomerAeration: g('downcomerAeration', d.downcomerAeration),
      systemFactor: g('systemFactor', d.systemFactor),
    );
  }

  Map<String, Object?> toJson() => {
        'diameter': diameter,
        'traySpacing': traySpacing,
        'downcomerFraction': downcomerFraction,
        'weirHeight': weirHeight,
        'apronClearance': apronClearance,
        'holeFraction': holeFraction,
        'holeDiameter': holeDiameter,
        'orificeCoeff': orificeCoeff,
        'valveOpenFraction': valveOpenFraction,
        'valveClosedRatio': valveClosedRatio,
        'valveLiftDp': valveLiftDp,
        'valveCoeff': valveCoeff,
        'downcomerAeration': downcomerAeration,
        'systemFactor': systemFactor,
      };

  /// Total tower cross-section A_T (m2).
  double get areaTotal => math.pi * diameter * diameter / 4;

  /// Downcomer area A_d (m2).
  double get areaDowncomer => downcomerFraction * areaTotal;

  /// Active (bubbling) area A_a = A_T - 2 A_d (m2).
  double get areaActive => areaTotal - 2 * areaDowncomer;

  /// Weir length L_w (m): solves (theta - sin theta)/(2 pi) = f_d, L_w = D sin(theta/2).
  double get weirLength {
    var th = 2.0;
    for (var i = 0; i < 50; i++) {
      final f = (th - math.sin(th)) / (2 * math.pi) - downcomerFraction;
      final df = (1 - math.cos(th)) / (2 * math.pi);
      final dth = f / df;
      th -= dth;
      if (dth.abs() < 1e-14) break;
    }
    return diameter * math.sin(th / 2);
  }

  /// Bennett weir constant C = 0.501 + 0.438 exp(-137.8 h_w) (PHYSICS.md 5.3).
  double get bennettC => 0.501 + 0.438 * math.exp(-137.8 * weirHeight);

  void validate(List<String> problems, String where) {
    if (diameter <= 0) problems.add('$where: diameter must be > 0');
    if (downcomerFraction <= 0 || downcomerFraction >= 0.4)
      problems.add('$where: downcomerFraction out of range');
    if (weirHeight <= 0) problems.add('$where: weirHeight must be > 0');
    if (traySpacing <= weirHeight)
      problems.add('$where: traySpacing must exceed weirHeight');
  }
}

sealed class SectionConfig {
  const SectionConfig();
  int get stageCount;
  Map<String, Object?> toJson();
  static SectionConfig fromJson(Map<String, Object?> j) {
    final kind = j['kind'] as String? ?? 'trays';
    if (kind == 'trays') return TraySection.fromJson(j);
    throw ConfigException(
        'Section kind "$kind" is not available in this build');
  }
}

class TraySection extends SectionConfig {
  final int trays;
  final TrayType type;
  final TrayGeometry geometry;
  const TraySection(
      {required this.trays,
      this.type = TrayType.sieve,
      this.geometry = const TrayGeometry()});

  factory TraySection.fromJson(Map<String, Object?> j) => TraySection(
        trays: (j['trays']! as num).toInt(),
        type:
            TrayType.values.firstWhere((e) => e.name == (j['type'] ?? 'sieve')),
        geometry: TrayGeometry.fromJson(
            (j['geometry'] as Map<String, Object?>?) ?? const {}),
      );

  @override
  int get stageCount => trays;

  TraySection copyWith({int? trays, TrayType? type, TrayGeometry? geometry}) =>
      TraySection(
          trays: trays ?? this.trays,
          type: type ?? this.type,
          geometry: geometry ?? this.geometry);

  @override
  Map<String, Object?> toJson() => {
        'kind': 'trays',
        'trays': trays,
        'type': type.name,
        'geometry': geometry.toJson()
      };
}
