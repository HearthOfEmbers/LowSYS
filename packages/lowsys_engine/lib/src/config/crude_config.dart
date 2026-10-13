// Crude unit configuration (ENGINE_API.md 4.1 `crude`, PHYSICS.md 9.2-9.7).
import 'package:meta/meta.dart';

import '../thermo/crude_thermo.dart';

double _n(Map<String, Object?> j, String k, double d) => (j[k] as num?)?.toDouble() ?? d;

/// A side draw: the product leaves the bottom of a two-stage stripper (PHYSICS.md 9.4).
@immutable
class SideDrawConfig {
  /// 'kero' | 'diesel' | 'ago'
  final String product;

  /// Main-column stages (1-based) the draw leaves and the stripper vapour returns to.
  final int drawStage, returnStage;

  /// Index of the stripper in [ColumnConfig.strippers].
  final int stripper;
  const SideDrawConfig({required this.product, required this.drawStage, required this.returnStage, required this.stripper});

  /// 'FC-311' ... 'FC-313' and 'LC-311' ... 'LC-313'.
  String get productLoop => 'FC-${311 + stripper}';
  String get levelLoop => 'LC-${311 + stripper}';

  factory SideDrawConfig.fromJson(Map<String, Object?> j) => SideDrawConfig(
        product: j['product']! as String,
        drawStage: (j['drawStage']! as num).toInt(),
        returnStage: (j['returnStage']! as num).toInt(),
        stripper: (j['stripper']! as num).toInt(),
      );

  Map<String, Object?> toJson() =>
      {'product': product, 'drawStage': drawStage, 'returnStage': returnStage, 'stripper': stripper};
}

/// A side stripper (PHYSICS.md 9.4).
@immutable
class StripperConfig {
  /// Must be 2.
  final int stages;

  /// Top-stage weir-tray diameter (m).
  final double diameter;

  /// Volume at 100 % level of the bottom stage (m3).
  final double bootVolume;

  /// Level SP (fraction) and time constant (s): S_d = P + V_s1 + (M_SP - M)/levelTau.
  final double levelSp, levelTau;

  /// 'ss1' | 'ss2' | 'ss3'
  final String steamPoint;
  const StripperConfig(
      {this.stages = 2,
      this.diameter = 1.0,
      this.bootVolume = 1.0,
      this.levelSp = 0.5,
      this.levelTau = 60,
      required this.steamPoint});

  factory StripperConfig.fromJson(Map<String, Object?> j) => StripperConfig(
        stages: (j['stages'] as num?)?.toInt() ?? 2,
        diameter: _n(j, 'diameter', 1.0),
        bootVolume: _n(j, 'bootVolume', 1.0),
        levelSp: _n(j, 'levelSp', 0.5),
        levelTau: _n(j, 'levelTau', 60),
        steamPoint: j['steamPoint']! as String,
      );

  Map<String, Object?> toJson() => {
        'stages': stages,
        'diameter': diameter,
        'bootVolume': bootVolume,
        'levelSp': levelSp,
        'levelTau': levelTau,
        'steamPoint': steamPoint,
      };
}

/// The pumparound (PHYSICS.md 9.5).
@immutable
class PumparoundConfig {
  final int drawStage, returnStage;

  /// m3/s at 15.6 C (120 m3/h = 0.0333333).
  final double circulation;

  /// K, the cooler limit of (9.3).
  final double tReturnMin;
  const PumparoundConfig(
      {required this.drawStage, required this.returnStage, this.circulation = 0.0333333, this.tReturnMin = 393.15});

  factory PumparoundConfig.fromJson(Map<String, Object?> j) => PumparoundConfig(
        drawStage: (j['drawStage']! as num).toInt(),
        returnStage: (j['returnStage']! as num).toInt(),
        circulation: _n(j, 'circulation', 0.0333333),
        tReturnMin: _n(j, 'tReturnMin', 393.15),
      );

  Map<String, Object?> toJson() =>
      {'drawStage': drawStage, 'returnStage': returnStage, 'circulation': circulation, 'tReturnMin': tReturnMin};
}

/// A steam injection point (PHYSICS.md 9.3).
@immutable
class SteamConfig {
  /// 'bottom' (into stage 30) | 'ss1' | 'ss2' | 'ss3' (below the stripper's bottom stage).
  final String point;

  /// K
  final double temperature;
  const SteamConfig({required this.point, this.temperature = 473.15});

  /// 'FC-321' ... 'FC-324'.
  String get loop => switch (point) { 'bottom' => 'FC-321', 'ss1' => 'FC-322', 'ss2' => 'FC-323', _ => 'FC-324' };

  /// Lever id `steam.<point>`.
  String get lever => 'steam.$point';

  factory SteamConfig.fromJson(Map<String, Object?> j) =>
      SteamConfig(point: j['point']! as String, temperature: _n(j, 'temperature', 473.15));

  Map<String, Object?> toJson() => {'point': point, 'temperature': temperature};
}

/// `ColumnConfig.crude` (null for every other preset).
@immutable
class CrudeUnitConfig {
  final Assay assay;

  /// Pa: the drum sits at P_top - drumDp (PHYSICS.md 9.7).
  final double drumDp;

  /// W: `model.condenserLimited` above it.
  final double qcMax;

  /// s: TC-320 first order.
  final double furnaceTau;

  /// 0.01: TBP 0/100 % are read at 1 % / 99 % (PHYSICS.md 9.6).
  final double tbpTrim;

  /// s, and the cap of the steam fraction (PHYSICS.md 9.3).
  final double steamFilterTau, steamFracMax;

  /// m3: the reflux drum and the sump (level range 0-100 %).
  final double drumVolume, sumpVolume;
  const CrudeUnitConfig({
    this.assay = Assay.light,
    this.drumDp = 20000,
    this.qcMax = 15e6,
    this.furnaceTau = 60,
    this.tbpTrim = 0.01,
    this.steamFilterTau = 30,
    this.steamFracMax = 0.98,
    this.drumVolume = 10,
    this.sumpVolume = 20,
  });

  factory CrudeUnitConfig.fromJson(Map<String, Object?> j) => CrudeUnitConfig(
        drumDp: _n(j, 'drumDp', 20000),
        qcMax: _n(j, 'qcMax', 15e6),
        furnaceTau: _n(j, 'furnaceTau', 60),
        tbpTrim: _n(j, 'tbpTrim', 0.01),
        steamFilterTau: _n(j, 'steamFilterTau', 30),
        steamFracMax: _n(j, 'steamFracMax', 0.98),
        drumVolume: _n(j, 'drumVolume', 10),
        sumpVolume: _n(j, 'sumpVolume', 20),
      );

  Map<String, Object?> toJson() => {
        'drumDp': drumDp,
        'qcMax': qcMax,
        'furnaceTau': furnaceTau,
        'tbpTrim': tbpTrim,
        'steamFilterTau': steamFilterTau,
        'steamFracMax': steamFracMax,
        'drumVolume': drumVolume,
        'sumpVolume': sumpVolume,
      };
}
