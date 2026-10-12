// M4 fixtures: Tier 2 (Raoult + energy balances), pressure control,
// condenser/reboiler heat transfer, the `mw` preset. All M4 engine
// touch-points live here (ENGINE_API.md names).
library;

import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'fixtures_m3.dart';

export 'fixtures_m3.dart';

const double kw = 1000.0;

/// B-T Tier 2, ideal hydraulics (ΔP = 0), as VC-11 wants, with overrides.
ColumnConfig btT2(
    {Map<String, Object?> overrides = const {}, bool full = false}) {
  var cfg = Presets.byId(Presets.bt);
  if (overrides.isNotEmpty) cfg = cfg.applyOverrides(overrides);
  return cfg.copyWith(
      tier: ThermoTier.t2,
      hydraulics: full ? HydraulicsMode.full : HydraulicsMode.ideal);
}

/// Methanol–water preset (VC-27.1), Tier 2 Raoult.
ColumnConfig mwT2({Map<String, Object?> overrides = const {}}) {
  var cfg = Presets.byId('mw');
  if (overrides.isNotEmpty) cfg = cfg.applyOverrides(overrides);
  return cfg.copyWith(tier: ThermoTier.t2, hydraulics: HydraulicsMode.ideal);
}

/// VC-11 setup: duty SP 1301.477 kW, L0 100 kmol/h, PC-101 at 101 325 Pa,
/// E = 1; returns the steady profile.
Simulator vc11Sim(
    {double duty = 1301.477,
    double l0 = 100,
    Map<String, Object?> overrides = const {'murphree': 1.0}}) {
  final sim = newSim(btT2(overrides: overrides));
  sim.setLever('reboilerDuty', duty * kw);
  sim.setLever('refluxFlow', l0 * kmolh);
  sim.setLever('pTop', 101325);
  return sim;
}

/// Tier-2 thermo model of a config.
ThermoModel thermoOf(ColumnConfig cfg) =>
    ThermoFactory.build(cfg, ThermoTier.t2);

/// Bubble point helper on a binary model: returns (T, y_light).
(double, double) bubble(ThermoModel m, double p, double x,
    {double tGuess = 360}) {
  final xs = Float64List.fromList([x, 1 - x]);
  final y = Float64List(2), k = Float64List(2);
  final t = m.bubbleT(p, xs, tGuess, y, k, SolverHealth());
  return (t, y[0]);
}

/// Stage temperature in °C.
double tC(SimSnapshot s, int j) => s.stages.t[j] - 273.15;

/// Expectations on a Tier-2 snapshot that must always hold.
void expectTier2Sane(SimSnapshot s, {String where = ''}) {
  expectPhysical(s, where: where);
  for (var j = 0; j < s.stages.n; j++) {
    expect(s.stages.t[j].isFinite, isTrue, reason: 'T[$j] $where');
    expect(s.stages.t[j], inInclusiveRange(250, 650), reason: 'T[$j] $where');
  }
  expect(s.kpis.pTop.isFinite && s.kpis.pTop > 1000, isTrue,
      reason: 'P_top $where');
  expect(s.kpis.qr.isFinite && s.kpis.qr >= 0, isTrue, reason: 'Q_R $where');
  expect(s.kpis.qc.isFinite && s.kpis.qc >= 0, isTrue, reason: 'Q_C $where');
}

/// Energy closure of a steady snapshot (relative to Q_R), PHYSICS.md VC-5.4:
/// |F h_F + Q_R − Q_C − D h_D − B h_B| / Q_R using the engine's enthalpies.
double energyResidual(Simulator sim) {
  final s = sim.snapshot();
  return s.kpis.energyResidual.abs();
}
