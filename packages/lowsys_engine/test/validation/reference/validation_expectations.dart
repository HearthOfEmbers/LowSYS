// The numbers written in docs/VALIDATION.md (v1.0, 2026-10-12) for the
// M1-relevant cases, transcribed here so the reference calculator and the
// engine test suite share one copy. Flow units: kmol/h as in the document.
// No engine imports.
library;

import 'cmo_steady_reference.dart';

/// B-T default column (VALIDATION.md §0, PHYSICS.md §5.1).
const btDefault = CmoColumn(
  alpha: 2.5,
  nTrays: 20,
  feedTray: 10,
  f: 100,
  z: 0.5,
  q: 1.0,
  l0: 100,
  vB: 150,
  e: 0.7,
);

extension CmoColumnCopy on CmoColumn {
  CmoColumn copyWith({
    double? alpha,
    int? nTrays,
    int? feedTray,
    double? f,
    double? z,
    double? q,
    double? l0,
    double? vB,
    double? e,
  }) =>
      CmoColumn(
        alpha: alpha ?? this.alpha,
        nTrays: nTrays ?? this.nTrays,
        feedTray: feedTray ?? this.feedTray,
        f: f ?? this.f,
        z: z ?? this.z,
        q: q ?? this.q,
        l0: l0 ?? this.l0,
        vB: vB ?? this.vB,
        e: e ?? this.e,
      );
}

class Vc1Expect {
  final double pinchX = 0.50000, pinchY = 0.71429;
  final double rMin = 1.1000, nMin = 6.4269, r = 1.65;
  final double gillilandX = 0.20755, molokanovY = 0.45404;
  final double nMolokanov = 12.603, nEduljee = 12.319;
  final double lOverV = 0.62264, lbarOverVbar = 1.37736;
  final int stages = 12, feedStage = 6;
  final double fractionalStages = 11.675;
  final List<double> stageX = const [
    0.88372, 0.79931, 0.70424, 0.61093, 0.53093, 0.46991, //
    0.40345, 0.31676, 0.22276, 0.13924, 0.07717, 0.03691
  ];
  final List<double> stageY = const [
    0.95000, 0.90873, 0.85617, 0.79698, 0.73888, 0.68907, //
    0.62836, 0.53683, 0.41742, 0.28795, 0.17291, 0.08742
  ];
  const Vc1Expect();
}

const vc1 = Vc1Expect();

class Vc2Row {
  final double q, pinchX, pinchY, rMin, nMolokanov, fractional;
  final int stages, feedStage;
  const Vc2Row(this.q, this.pinchX, this.pinchY, this.rMin, this.nMolokanov,
      this.stages, this.fractional, this.feedStage);
}

const vc2 = [
  Vc2Row(1.2, 0.54112, 0.74671, 0.9888, 12.785, 12, 11.798, 6),
  Vc2Row(1.0, 0.50000, 0.71429, 1.1000, 12.603, 12, 11.675, 6),
  Vc2Row(0.5, 0.38743, 0.61257, 1.4987, 12.140, 11, 10.946, 6),
  Vc2Row(0.0, 0.28571, 0.50000, 2.1000, 11.736, 10, 9.950, 6),
];

class Vc31Row {
  final int n;
  final double xD;
  const Vc31Row(this.n, this.xD);
}

const vc31 = [
  Vc31Row(6, 0.939850),
  Vc31Row(10, 0.989864),
  Vc31Row(20, 0.999895)
];

class Vc4Case {
  final String id;
  final CmoColumn column;
  final double xD, xB, d;
  const Vc4Case(this.id, this.column, this.xD, this.xB, this.d);
}

const vc4 = [
  Vc4Case('4.1 default', btDefault, 0.981183, 0.018817, 50),
  Vc4Case(
      '4.2 E=1',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 150,
          e: 1.0),
      0.995951,
      0.004049,
      50),
  Vc4Case(
      '4.3 E=0.5',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 150,
          e: 0.5),
      0.953307,
      0.046693,
      50),
  Vc4Case(
      '4.4 feed 5',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 5,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 150,
          e: 0.7),
      0.948400,
      0.051600,
      50),
  Vc4Case(
      '4.5 feed 15',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 15,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 150,
          e: 0.7),
      0.967099,
      0.032901,
      50),
  Vc4Case(
      '4.6 L110 V160',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 110,
          vB: 160,
          e: 0.7),
      0.984504,
      0.015496,
      50),
  Vc4Case(
      '4.7 L150 V200',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 150,
          vB: 200,
          e: 0.7),
      0.991024,
      0.008976,
      50),
  Vc4Case(
      '4.8 q0.5 V100',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 0.5,
          l0: 100,
          vB: 100,
          e: 0.7),
      0.966910,
      0.033090,
      50),
  Vc4Case(
      '4.9 V155',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 155,
          e: 0.7),
      0.907066,
      0.002475,
      55),
  Vc4Case(
      '4.10 z0.6',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.6,
          q: 1,
          l0: 100,
          vB: 150,
          e: 0.7),
      0.992453,
      0.207547,
      50),
  Vc4Case(
      '4.11 L110 V150',
      CmoColumn(
          alpha: 2.5,
          nTrays: 20,
          feedTray: 10,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 110,
          vB: 150,
          e: 0.7),
      0.993373,
      0.171085,
      40),
  Vc4Case(
      '4.12 E1 N15 f8',
      CmoColumn(
          alpha: 2.5,
          nTrays: 15,
          feedTray: 8,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 100,
          vB: 150,
          e: 1.0),
      0.986620,
      0.013380,
      50),
  Vc4Case(
      '4.13 E1 N11 f6',
      CmoColumn(
          alpha: 2.5,
          nTrays: 11,
          feedTray: 6,
          f: 100,
          z: 0.5,
          q: 1,
          l0: 82.5,
          vB: 132.5,
          e: 1.0),
      0.953272,
      0.046728,
      50),
];

const vc414FeedTrays = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
const vc414Xd = [
  0.93211, 0.94840, 0.96031, 0.96893, 0.97495, 0.97891, 0.98118, //
  0.98203, 0.98147, 0.97927, 0.97479, 0.96710, 0.95520
];

/// VC-7.1 reflux step trajectory (prototype values; wide tolerances).
class Vc71Row {
  final double t, xD, xB, d;
  const Vc71Row(this.t, this.xD, this.xB, this.d);
}

const vc71 = [
  Vc71Row(60, 0.9815, 0.0195, 48.96),
  Vc71Row(300, 0.9843, 0.0385, 45.45),
  Vc71Row(600, 0.9875, 0.0718, 42.42),
  Vc71Row(1800, 0.9925, 0.1447, 38.47),
  Vc71Row(3600, 0.9933, 0.1680, 39.20),
  Vc71Row(7200, 0.99337, 0.17105, 39.99),
];
