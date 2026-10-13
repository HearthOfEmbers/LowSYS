import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/ids.dart';
import 'tray_geometry.dart';

Float64List _f64(Object? l) => Float64List.fromList(
    [for (final v in (l! as List<Object?>)) (v! as num).toDouble()]);

sealed class FeedThermal {
  const FeedThermal();
  Map<String, Object?> toJson();
  static FeedThermal fromJson(Map<String, Object?> j) {
    if (j.containsKey('q')) return FeedQ((j['q']! as num).toDouble());
    if (j.containsKey('t')) return FeedTemperature((j['t']! as num).toDouble());
    if (j.containsKey('beta'))
      return FeedVaporFraction((j['beta']! as num).toDouble());
    throw ConfigException('Feed thermal condition needs q, t or beta');
  }
}

/// Tier 1: liquid fraction of the feed.
class FeedQ extends FeedThermal {
  final double q;
  const FeedQ(this.q);
  @override
  Map<String, Object?> toJson() => {'q': q};
}

/// Tiers 2/3: feed temperature (K).
class FeedTemperature extends FeedThermal {
  final double t;
  const FeedTemperature(this.t);
  @override
  Map<String, Object?> toJson() => {'t': t};
}

class FeedVaporFraction extends FeedThermal {
  final double beta;
  const FeedVaporFraction(this.beta);
  @override
  Map<String, Object?> toJson() => {'beta': beta};
}

/// A feed. [stage] is the tray number counted from the top (1..N). [flow] is mol/s.
@immutable
class FeedConfig {
  final int stage;
  final double flow;
  final Float64List z;
  final FeedThermal thermal;
  const FeedConfig(
      {required this.stage,
      required this.flow,
      required this.z,
      required this.thermal});

  factory FeedConfig.fromJson(Map<String, Object?> j) => FeedConfig(
        stage: (j['stage']! as num).toInt(),
        flow: (j['flow']! as num).toDouble(),
        z: _f64(j['z']),
        thermal: FeedThermal.fromJson(j['thermal']! as Map<String, Object?>),
      );

  Map<String, Object?> toJson() => {
        'stage': stage,
        'flow': flow,
        'z': z.toList(),
        'thermal': thermal.toJson()
      };

  FeedConfig copyWith(
          {int? stage, double? flow, Float64List? z, FeedThermal? thermal}) =>
      FeedConfig(
          stage: stage ?? this.stage,
          flow: flow ?? this.flow,
          z: z ?? this.z,
          thermal: thermal ?? this.thermal);
}

@immutable
class CondenserConfig {
  final CondenserType type;

  /// m3
  final double drumVolume, overheadVolume;

  /// Pa
  final double pTopDesign, reliefSet;
  final double cwInletT, cwMaxFlow, uaClean, dvMax;

  /// CW valve OP (%) a partial condenser starts at (PHYSICS.md 7.2; below the total-condensation OP).
  final double cwOpPartial;

  /// Slope of the design distillate's bubble point at the design pressure (K/Pa; B-T 0.32 K/kPa): the process part
  /// of TI-100's typical sigma (PHYSICS.md 10.5).
  final double dTbubDp;

  /// PC-101 proportional gain for a total condenser (%OP per % span; the B-T value is 10). The light-hydrocarbon
  /// presets (M7) have a much smaller process gain in % span per % OP (a 3.45 MPa span and a small condenser).
  final double pcKc;

  /// Vapour-product header pressure (partial condenser), vent header pressure and capacities (PHYSICS.md 7.1, 7.2);
  /// null: P_design - 30 kPa, and 50 kPa below 3 bar design pressure else 1 atm.
  final double? pDown, pVent;

  /// Inert vent capacity at 50 kPa driving force (mol/s) and relief capacity (mol/s; 2 x the design V1).
  final double ventMax, reliefMax;
  const CondenserConfig({
    this.type = CondenserType.total,
    this.drumVolume = 3.0,
    this.overheadVolume = 3.0,
    this.pTopDesign = 101325,
    this.reliefSet = 350000,
    this.cwInletT = 303.15,
    this.cwMaxFlow = 41.54,
    this.uaClean = 29900,
    this.dvMax = 0,
    this.cwOpPartial = 30,
    this.dTbubDp = 3.2e-4,
    this.pcKc = 10,
    this.pDown,
    this.pVent,
    this.ventMax = 2.0,
    this.reliefMax = 83.3333333333,
  });

  double get pDownEff => pDown ?? pTopDesign - 30000;
  double get pVentEff => pVent ?? (pTopDesign < 3e5 ? 50000.0 : 101325.0);

  factory CondenserConfig.fromJson(Map<String, Object?> j) {
    const d = CondenserConfig();
    double g(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return CondenserConfig(
      type: CondenserType.values
          .firstWhere((e) => e.name == (j['type'] ?? 'total')),
      drumVolume: g('drumVolume', d.drumVolume),
      overheadVolume: g('overheadVolume', d.overheadVolume),
      pTopDesign: g('pTopDesign', d.pTopDesign),
      reliefSet: g('reliefSet', d.reliefSet),
      cwInletT: g('cwInletT', d.cwInletT),
      cwMaxFlow: g('cwMaxFlow', d.cwMaxFlow),
      uaClean: g('uaClean', d.uaClean),
      dvMax: g('dvMax', d.dvMax),
      cwOpPartial: g('cwOpPartial', d.cwOpPartial),
      dTbubDp: g('dTbubDp', d.dTbubDp),
      pcKc: g('pcKc', d.pcKc),
      pDown: (j['pDown'] as num?)?.toDouble(),
      pVent: (j['pVent'] as num?)?.toDouble(),
      ventMax: g('ventMax', d.ventMax),
      reliefMax: g('reliefMax', d.reliefMax),
    );
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        'drumVolume': drumVolume,
        'overheadVolume': overheadVolume,
        'pTopDesign': pTopDesign,
        'reliefSet': reliefSet,
        'cwInletT': cwInletT,
        'cwMaxFlow': cwMaxFlow,
        'uaClean': uaClean,
        'dvMax': dvMax,
        'cwOpPartial': cwOpPartial,
        'dTbubDp': dTbubDp,
        if (pcKc != 10) 'pcKc': pcKc,
        if (pDown != null) 'pDown': pDown,
        if (pVent != null) 'pVent': pVent,
        'ventMax': ventMax,
        'reliefMax': reliefMax,
      };
}

/// Thermosyphon geometry and constants (PHYSICS.md 8.3.1; SI; B-T defaults). With a thermosyphon UA_R,clean = u * area
/// (FV-103 F_max, F13, C4); the kettle's `uaClean` is not used.
@immutable
class ThermosyphonGeometry {
  final int nTubes;
  final double tubeId, tubeLength;

  /// Outside heat-transfer area (m2) and clean overall U (W/m2/K), referred to it.
  final double area, u;

  /// Liquid height above the bottom tubesheet at 0 % sump level, return nozzle height (m).
  final double z0, zReturn;
  final double inletD, inletLength, riserD;

  /// Loss coefficients (inlet entry and bends, outlet) and the exit quality where mist-flow degradation starts.
  final double kIn, kOut, xCrit;

  /// Preset constants: liquid viscosity (Pa s) and the design liquid density (kg/m3) and dT_sat/dP (K/Pa) used by the
  /// C4 check of FV-103 (PHYSICS.md 14.6).
  final double muL, rhoLDesign, dTsatDpDesign;
  const ThermosyphonGeometry({
    this.nTubes = 200,
    this.tubeId = 0.0212,
    this.tubeLength = 3.0,
    this.area = 47.6,
    this.u = 1000,
    this.z0 = 1.2,
    this.zReturn = 4.5,
    this.inletD = 0.20,
    this.inletLength = 6.0,
    this.riserD = 0.30,
    this.kIn = 4,
    this.kOut = 3,
    this.xCrit = 0.30,
    this.muL = 0.27e-3,
    this.rhoLDesign = 780,
    this.dTsatDpDesign = 3.63e-4,
  });

  /// Clean UA (W/K) = U A.
  double get uaClean => u * area;

  factory ThermosyphonGeometry.fromJson(Map<String, Object?> j) {
    const d = ThermosyphonGeometry();
    double g(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return ThermosyphonGeometry(
      nTubes: (j['nTubes'] as num?)?.toInt() ?? d.nTubes,
      tubeId: g('tubeId', d.tubeId),
      tubeLength: g('tubeLength', d.tubeLength),
      area: g('area', d.area),
      u: g('u', d.u),
      z0: g('z0', d.z0),
      zReturn: g('zReturn', d.zReturn),
      inletD: g('inletD', d.inletD),
      inletLength: g('inletLength', d.inletLength),
      riserD: g('riserD', d.riserD),
      kIn: g('kIn', d.kIn),
      kOut: g('kOut', d.kOut),
      xCrit: g('xCrit', d.xCrit),
      muL: g('muL', d.muL),
      rhoLDesign: g('rhoLDesign', d.rhoLDesign),
      dTsatDpDesign: g('dTsatDpDesign', d.dTsatDpDesign),
    );
  }

  Map<String, Object?> toJson() => {
        'nTubes': nTubes,
        'tubeId': tubeId,
        'tubeLength': tubeLength,
        'area': area,
        'u': u,
        'z0': z0,
        'zReturn': zReturn,
        'inletD': inletD,
        'inletLength': inletLength,
        'riserD': riserD,
        'kIn': kIn,
        'kOut': kOut,
        'xCrit': xCrit,
        'muL': muL,
        'rhoLDesign': rhoLDesign,
        'dTsatDpDesign': dTsatDpDesign,
      };
}

@immutable
class ReboilerConfig {
  final ReboilerType type;

  /// Thermosyphon geometry (every preset has it; it is used when [type] is thermosyphon).
  final ThermosyphonGeometry thermosyphon;

  /// m, m2
  final double sumpHeight, sumpArea;
  final double steamHeaderPressure, uaClean;
  const ReboilerConfig({
    this.type = ReboilerType.kettle,
    this.sumpHeight = 2.4,
    this.sumpArea = 1.131,
    this.steamHeaderPressure = 451325,
    this.uaClean = 57500,
    this.thermosyphon = const ThermosyphonGeometry(),
  });

  factory ReboilerConfig.fromJson(Map<String, Object?> j) {
    const d = ReboilerConfig();
    double g(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return ReboilerConfig(
      type: ReboilerType.values
          .firstWhere((e) => e.name == (j['type'] ?? 'kettle')),
      sumpHeight: g('sumpHeight', d.sumpHeight),
      sumpArea: g('sumpArea', d.sumpArea),
      steamHeaderPressure: g('steamHeaderPressure', d.steamHeaderPressure),
      uaClean: g('uaClean', d.uaClean),
      thermosyphon: j['thermosyphon'] == null
          ? d.thermosyphon
          : ThermosyphonGeometry.fromJson(
              Map<String, Object?>.from(j['thermosyphon']! as Map<Object?, Object?>)),
    );
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        'sumpHeight': sumpHeight,
        'sumpArea': sumpArea,
        'steamHeaderPressure': steamHeaderPressure,
        'uaClean': uaClean,
        'thermosyphon': thermosyphon.toJson(),
      };

  /// Sump liquid volume at 100 % level (m3).
  double get sumpVolume => sumpHeight * sumpArea;
}

/// Loop tunings (PHYSICS.md 10.4). Level loops are PI, reverse of nothing: direct acting.
@immutable
class ControlConfig {
  /// %OP per % span
  final double levelKc;

  /// s
  final double levelTi;
  final double drumLevelSp, sumpLevelSp;

  /// Valve capacities (mol/s). Null: 2 x the design flow derived from the initial levers.
  final double? distillateMax, bottomsMax;

  /// Instrumented trays (TI-1jj, PHYSICS.md 10.5); null: the B-T heights [1, 4, 7, 10, 12, 14, 17, 20] / 20 scaled to N.
  final List<int>? temperatureTrays;

  /// Tray whose temperature TC-101 controls.
  final int tc101Tray;
  const ControlConfig({
    this.levelKc = 2.0,
    this.levelTi = 1800,
    this.drumLevelSp = 50,
    this.sumpLevelSp = 50,
    this.distillateMax,
    this.bottomsMax,
    this.temperatureTrays,
    this.tc101Tray = 14,
  });

  static const List<int> _btTrays = [1, 4, 7, 10, 12, 14, 17, 20];

  /// The instrumented trays for a column of [n] trays: each B-T entry keeps its fractional height, the result is
  /// de-duplicated and the TC-101 tray is always included (PHYSICS.md 10.5).
  List<int> trayList(int n) {
    final base = temperatureTrays ??
        [
          for (final t in _btTrays)
            n == 20 ? t : (t * n / 20).round().clamp(1, n),
        ];
    final out = <int>{for (final t in base) t.clamp(1, n)};
    out.add(tc101Tray.clamp(1, n));
    return out.toList()..sort();
  }

  factory ControlConfig.fromJson(Map<String, Object?> j) {
    const d = ControlConfig();
    double g(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return ControlConfig(
      levelKc: g('levelKc', d.levelKc),
      levelTi: g('levelTi', d.levelTi),
      drumLevelSp: g('drumLevelSp', d.drumLevelSp),
      sumpLevelSp: g('sumpLevelSp', d.sumpLevelSp),
      distillateMax: (j['distillateMax'] as num?)?.toDouble(),
      bottomsMax: (j['bottomsMax'] as num?)?.toDouble(),
      temperatureTrays: (j['temperatureTrays'] as List<Object?>?)
          ?.map((e) => (e! as num).toInt())
          .toList(),
      tc101Tray: (j['tc101Tray'] as num?)?.toInt() ?? 14,
    );
  }

  Map<String, Object?> toJson() => {
        'loops': 'default',
        'levelKc': levelKc,
        'levelTi': levelTi,
        'drumLevelSp': drumLevelSp,
        'sumpLevelSp': sumpLevelSp,
        if (distillateMax != null) 'distillateMax': distillateMax,
        if (bottomsMax != null) 'bottomsMax': bottomsMax,
        if (temperatureTrays != null) 'temperatureTrays': temperatureTrays,
        'tc101Tray': tc101Tray,
      };
}

@immutable
class Tier1Props {
  /// kg/m3, kg/m3, N/m
  final double rhoL, rhoV, sigma;
  const Tier1Props(
      {required this.rhoL, required this.rhoV, required this.sigma});
  factory Tier1Props.fromJson(Map<String, Object?> j) => Tier1Props(
        rhoL: (j['rhoL']! as num).toDouble(),
        rhoV: (j['rhoV']! as num).toDouble(),
        sigma: (j['sigma']! as num).toDouble(),
      );
  Map<String, Object?> toJson() => {'rhoL': rhoL, 'rhoV': rhoV, 'sigma': sigma};
}

/// Immutable, JSON-serialisable description of a column and its initial lever values
/// (ENGINE_API.md 4). All values SI (mol/s, K, Pa, m, kg/s, W).
@immutable
/// Light and heavy key component indices of a multicomponent column (ENGINE_API.md 4, M7). Components are listed
/// in order of decreasing volatility, so the light cut is every component up to [lk] and the heavy cut every
/// component from [hk] on.
@immutable
class KeyComponents {
  final int lk, hk;
  const KeyComponents(this.lk, this.hk);
  @override
  bool operator ==(Object other) => other is KeyComponents && other.lk == lk && other.hk == hk;
  @override
  int get hashCode => Object.hash(lk, hk);
}

class ColumnConfig {
  final PresetId presetId;
  final String displayName;
  final List<ComponentId> components;
  final ThermoTier tier;
  final Float64List? tier1Alpha;
  final Tier1Props? tier1Props;

  /// Pa s
  final double liquidViscosity;
  final List<SectionConfig> sections;
  final List<FeedConfig> feeds;
  final CondenserConfig condenser;
  final ReboilerConfig reboiler;
  final ControlConfig control;
  final HydraulicsMode hydraulics;
  final Map<LeverId, double> initialLevers;
  final double murphree;

  /// Tier-3 model (M5) and the "Tier 1 cannot represent this system" flag (`ac`, PHYSICS.md 2.3).
  final Tier3Model tier3Model;
  final bool tier1CannotRepresent;

  /// Multicomponent keys (`debut`, `deprop`); null for binaries.
  final KeyComponents? keys;

  /// Key indices used by the analysers and KPIs: the declared keys, or (0, 1) for a binary.
  KeyComponents get effectiveKeys => keys ?? const KeyComponents(0, 1);

  /// Tiers the learner may select (PHYSICS.md 13.5): `sameAsTier2` has no Tier 3, crude only Tier 2.
  Set<ThermoTier> get availableTiers {
    if (presetId == 'crude') return const {ThermoTier.t2};
    if (tier3Model == Tier3Model.sameAsTier2) {
      return const {ThermoTier.t1, ThermoTier.t2};
    }
    return const {ThermoTier.t1, ThermoTier.t2, ThermoTier.t3};
  }

  const ColumnConfig({
    required this.presetId,
    required this.displayName,
    required this.components,
    this.tier = ThermoTier.t1,
    this.tier1Alpha,
    this.tier1Props,
    this.liquidViscosity = 0.00027,
    required this.sections,
    required this.feeds,
    this.condenser = const CondenserConfig(),
    this.reboiler = const ReboilerConfig(),
    this.control = const ControlConfig(),
    this.hydraulics = HydraulicsMode.ideal,
    this.initialLevers = const {},
    this.murphree = 0.7,
    this.tier3Model = Tier3Model.sameAsTier2,
    this.tier1CannotRepresent = false,
    this.keys,
  });

  factory ColumnConfig.fromJson(Map<String, Object?> j) {
    final lev = (j['initialLevers'] as Map<String, Object?>?) ?? const {};
    return ColumnConfig(
      presetId: j['presetId']! as String,
      displayName: (j['displayName'] as String?) ?? j['presetId']! as String,
      components: [
        for (final c in (j['components']! as List<Object?>)) c! as String
      ],
      tier: ThermoTier.values.firstWhere((e) => e.name == (j['tier'] ?? 't1')),
      tier1Alpha: j['tier1Alpha'] == null ? null : _f64(j['tier1Alpha']),
      tier1Props: j['tier1Props'] == null
          ? null
          : Tier1Props.fromJson(j['tier1Props']! as Map<String, Object?>),
      liquidViscosity: (j['liquidViscosity'] as num?)?.toDouble() ?? 0.00027,
      sections: [
        for (final s in (j['sections']! as List<Object?>))
          SectionConfig.fromJson(s! as Map<String, Object?>)
      ],
      feeds: [
        for (final f in (j['feeds']! as List<Object?>))
          FeedConfig.fromJson(f! as Map<String, Object?>)
      ],
      condenser: CondenserConfig.fromJson(
          (j['condenser'] as Map<String, Object?>?) ?? const {}),
      reboiler: ReboilerConfig.fromJson(
          (j['reboiler'] as Map<String, Object?>?) ?? const {}),
      control: ControlConfig.fromJson(
          (j['control'] as Map<String, Object?>?) ?? const {}),
      hydraulics: HydraulicsMode.values
          .firstWhere((e) => e.name == (j['hydraulics'] ?? 'ideal')),
      initialLevers: {
        for (final e in lev.entries) e.key: (e.value! as num).toDouble()
      },
      murphree: (j['murphree'] as num?)?.toDouble() ?? 0.7,
      tier3Model: Tier3Model.values.firstWhere(
          (e) => e.name == (j['tier3Model'] ?? 'sameAsTier2')),
      tier1CannotRepresent: (j['tier1CannotRepresent'] as bool?) ?? false,
      keys: j['keys'] == null
          ? null
          : (() {
              final k = j['keys']! as Map<String, Object?>;
              final comps = [for (final c in (j['components']! as List<Object?>)) c! as String];
              return KeyComponents(comps.indexOf(k['lk']! as String), comps.indexOf(k['hk']! as String));
            })(),
    );
  }

  Map<String, Object?> toJson() => {
        'presetId': presetId,
        'displayName': displayName,
        'components': components,
        'tier': tier.name,
        if (tier1Alpha != null) 'tier1Alpha': tier1Alpha!.toList(),
        if (tier1Props != null) 'tier1Props': tier1Props!.toJson(),
        'liquidViscosity': liquidViscosity,
        'sections': [for (final s in sections) s.toJson()],
        'feeds': [for (final f in feeds) f.toJson()],
        'condenser': condenser.toJson(),
        'reboiler': reboiler.toJson(),
        'control': control.toJson(),
        'hydraulics': hydraulics.name,
        'murphree': murphree,
        'tier3Model': tier3Model.name,
        if (tier1CannotRepresent) 'tier1CannotRepresent': true,
        if (keys != null) 'keys': {'lk': components[keys!.lk], 'hk': components[keys!.hk]},
        'initialLevers': initialLevers,
      };

  /// Number of equilibrium trays/segments N (excluding drum and sump).
  int get trayCount => sections.fold(0, (a, s) => a + s.stageCount);

  /// The first (and in M1 only) tray section.
  TraySection get traySection => sections.whereType<TraySection>().first;

  int get nc => components.length;

  List<String> validate() {
    final p = <String>[];
    if (components.length < 2) p.add('At least two components are required');
    if (sections.isEmpty) p.add('At least one section is required');
    final n = trayCount;
    if (n < 3 || n > 60) p.add('Number of trays must be 3..60 (got $n)');
    if (tier == ThermoTier.t1) {
      final a = tier1Alpha;
      if (a == null || a.length != components.length) {
        p.add('Tier 1 needs tier1Alpha with one value per component');
      } else if (a.any((v) => !(v > 0))) {
        p.add('tier1Alpha values must be > 0');
      }
      if (tier1Props == null) p.add('Tier 1 needs tier1Props');
    }
    if (feeds.isEmpty) p.add('At least one feed is required');
    for (final f in feeds) {
      if (f.stage < 1 || f.stage > n)
        p.add('Feed stage ${f.stage} outside 1..$n');
      if (f.z.length != components.length) {
        p.add('Feed composition length mismatch');
      } else {
        final s = f.z.fold(0.0, (a, b) => a + b);
        if ((s - 1).abs() > 1e-6) p.add('Feed composition sums to $s, not 1');
      }
      if (f.flow < 0) p.add('Feed flow must be >= 0');
    }
    if (murphree <= 0 || murphree > 1) p.add('murphree must be in (0, 1]');
    for (final s in sections) {
      if (s is TraySection) s.geometry.validate(p, 'section');
    }
    if (tier == ThermoTier.t1 && condenser.type == CondenserType.partial) {
      p.add('A partial condenser needs Tier 2 or 3');
    }
    if (condenser.drumVolume <= 0) p.add('drumVolume must be > 0');
    if (reboiler.sumpVolume <= 0) p.add('sump volume must be > 0');
    return p;
  }

  ColumnConfig copyWith({
    PresetId? presetId,
    String? displayName,
    List<ComponentId>? components,
    ThermoTier? tier,
    Float64List? tier1Alpha,
    Tier1Props? tier1Props,
    double? liquidViscosity,
    List<SectionConfig>? sections,
    List<FeedConfig>? feeds,
    CondenserConfig? condenser,
    ReboilerConfig? reboiler,
    ControlConfig? control,
    HydraulicsMode? hydraulics,
    Map<LeverId, double>? initialLevers,
    double? murphree,
    Tier3Model? tier3Model,
    bool? tier1CannotRepresent,
    KeyComponents? keys,
  }) =>
      ColumnConfig(
        presetId: presetId ?? this.presetId,
        displayName: displayName ?? this.displayName,
        components: components ?? this.components,
        tier: tier ?? this.tier,
        tier1Alpha: tier1Alpha ?? this.tier1Alpha,
        tier1Props: tier1Props ?? this.tier1Props,
        liquidViscosity: liquidViscosity ?? this.liquidViscosity,
        sections: sections ?? this.sections,
        feeds: feeds ?? this.feeds,
        condenser: condenser ?? this.condenser,
        reboiler: reboiler ?? this.reboiler,
        control: control ?? this.control,
        hydraulics: hydraulics ?? this.hydraulics,
        initialLevers: initialLevers ?? this.initialLevers,
        murphree: murphree ?? this.murphree,
        tier3Model: tier3Model ?? this.tier3Model,
        tier1CannotRepresent: tier1CannotRepresent ?? this.tier1CannotRepresent,
        keys: keys ?? this.keys,
      );

  /// Convenience for tests and the app: same column with [trays] trays and the feed on [feedStage].
  ColumnConfig withTrays(int trays, {int? feedStage}) {
    final s = traySection.copyWith(trays: trays);
    final fs = feedStage ?? feeds.first.stage.clamp(1, trays);
    return copyWith(
        sections: [s],
        feeds: [feeds.first.copyWith(stage: fs), ...feeds.skip(1)]);
  }

  /// Applies dotted/indexed overrides like those in scenario JSON (ENGINE_API.md 11.1),
  /// e.g. `{'sections[0].trays': 60, 'feeds[0].stage': 30, 'murphree': 1.0}`.
  ColumnConfig applyOverrides(Map<String, Object?> overrides) {
    final json = _deepCopy(toJson()) as Map<String, Object?>;
    for (final e in overrides.entries) {
      final parts = e.key.split('.');
      Object? node = json;
      for (var i = 0; i < parts.length; i++) {
        final m = RegExp(r'^(\w+)(?:\[(\d+)\])?$').firstMatch(parts[i]);
        if (m == null) throw ConfigException('Bad override path "${e.key}"');
        final key = m.group(1)!;
        final idx = m.group(2) == null ? null : int.parse(m.group(2)!);
        final last = i == parts.length - 1;
        final map = node as Map<String, Object?>;
        if (last && idx == null) {
          map[key] = e.value;
        } else if (idx == null) {
          node = map[key];
        } else {
          final list = map[key]! as List<Object?>;
          if (last) {
            list[idx] = e.value;
          } else {
            node = list[idx];
          }
        }
      }
    }
    return ColumnConfig.fromJson(json);
  }

  static Object? _deepCopy(Object? o) {
    if (o is Map)
      return {for (final e in o.entries) e.key as String: _deepCopy(e.value)};
    if (o is List) return [for (final v in o) _deepCopy(v)];
    return o;
  }
}
