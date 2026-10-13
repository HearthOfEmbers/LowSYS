// M8 coder tests: VC-13.8 faults on the H7 column (steady states), and the +10 % / +25 % healthy rows.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm8_helpers.dart';

typedef _Row = ({
  String name,
  FaultType? type,
  int bed,
  double sev,
  double xD,
  double xB,
  double dpU,
  double dpL,
  double phiU,
  double phiL,
  double spanU,
  double spanL,
  double eMal
});

_Row _r(String name, FaultType? type, int bed, double sev, double xD, double xB, double dpU, double dpL, double phiU,
        double phiL, double spanU, double spanL, double eMal) =>
    (
      name: name,
      type: type,
      bed: bed,
      sev: sev,
      xD: xD,
      xB: xB,
      dpU: dpU,
      dpL: dpL,
      phiU: phiU,
      phiL: phiL,
      spanU: spanU,
      spanL: spanL,
      eMal: eMal
    );

void main() {
  final rows = <_Row>[
    _r('healthy', null, 0, 0, 0.99357, 0.01108, 1263.2, 1610.5, 0.6747, 0.7865, 11.46, 17.02, 1),
    _r('F21 upper s 0.5', FaultType.packingMaldistribution, 1, 0.5, 0.97875, 0.02803, 1266.5, 1567.4, 0.6754, 0.7832, 8.09, 17.76, 0.5725),
    _r('F21 upper s 0.8', FaultType.packingMaldistribution, 1, 0.8, 0.95247, 0.05678, 1272.5, 1537.2, 0.6771, 0.7781, 5.93, 16.60, 0.3277),
    _r('F21 lower s 0.5', FaultType.packingMaldistribution, 2, 0.5, 0.97418, 0.03646, 1275.6, 1603.2, 0.6814, 0.7797, 14.47, 12.97, 0.5627),
    _r('F21 lower s 0.8', FaultType.packingMaldistribution, 2, 0.8, 0.94334, 0.07558, 1290.3, 1591.5, 0.6869, 0.7725, 14.73, 9.55, 0.3353),
    _r('F23 upper s 0.3', FaultType.packingCrush, 1, 0.3, 0.99250, 0.01160, 1848.6, 1600.8, 0.7529, 0.7850, 11.41, 17.12, 1),
    _r('F23 upper s 0.5', FaultType.packingCrush, 1, 0.5, 0.99171, 0.01199, 2270.0, 1593.9, 0.7995, 0.7839, 11.37, 17.18, 1),
    _r('F23 lower s 0.3', FaultType.packingCrush, 2, 0.3, 0.99269, 0.01385, 1262.5, 2534.6, 0.6750, 0.8814, 11.89, 16.76, 1),
    _r('F23 lower s 0.5', FaultType.packingCrush, 2, 0.5, 0.99080, 0.01771, 1262.8, 3331.6, 0.6757, 0.9358, 12.58, 16.23, 1),
  ];

  for (final r in rows) {
    test('VC-13.8 ${r.name}', () {
      final sim = h7Sim();
      if (r.type != null) {
        sim.faults.inject(FaultSpec(type: r.type!, location: FaultLocation.bed(r.bed), severity: r.sev));
      }
      steady(sim);
      final s = sim.snapshot();
      expect(s.kpis.xD, closeTo(r.xD, 3e-5), reason: 'x_D');
      expect(s.kpis.xB, closeTo(r.xB, 3e-5), reason: 'x_B');
      expect(s.beds[0].dp, closeTo(r.dpU, 0.005 * r.dpU), reason: 'dP upper');
      expect(s.beds[1].dp, closeTo(r.dpL, 0.005 * r.dpL), reason: 'dP lower');
      expect(s.beds[0].maxFlood, closeTo(r.phiU, 0.002), reason: 'phi upper');
      expect(s.beds[1].maxFlood, closeTo(r.phiL, 0.002), reason: 'phi lower');
      expect((s.stages.t[1] - s.stages.t[9]).abs(), closeTo(r.spanU, 0.05), reason: 'TI span upper');
      expect((s.stages.t[10] - s.stages.t[18]).abs(), closeTo(r.spanL, 0.05), reason: 'TI span lower');
      final eMal = r.bed == 0 ? 1.0 : s.beds[r.bed - 1].eMal;
      expect(eMal, closeTo(r.eMal, 2e-4), reason: 'E_mal');
      if (r.type == FaultType.packingMaldistribution) {
        expect(s.beds[r.bed - 1].maldistribution, closeTo(0.6 * r.sev, 1e-9));
      }
    });
  }

  test('healthy at +10 % (the debrief\'s "about 110 %"): lower phi_p 0.8630, dP 2051.7 / 1563.9', () {
    final sim = steady(h7Sim());
    for (final (lev, k) in [('feedFlow', 1.1), ('refluxFlow', 1.1), ('reboilerDuty', 1.1)]) {
      sim.setLever(lev, sim.lever(lev) * k);
    }
    steady(sim);
    final s = sim.snapshot();
    expect(s.beds[1].maxFlood, closeTo(0.8630, 0.002));
    expect(s.beds[1].dp, closeTo(2051.7, 0.005 * 2051.7));
    expect(s.beds[0].dp, closeTo(1563.9, 0.005 * 1563.9));
    expect(s.kpis.xD, closeTo(0.99339, 3e-5));
    expect(s.kpis.xB, closeTo(0.01169, 3e-5));
  });

  test('healthy at +25 % (the H7 event): lower bed phi_p 0.9747, dP 1.83x, HETP 0.622 m, Q_C 1599 kW', () {
    final sim = steady(h7Sim());
    final dp0 = sim.snapshot().beds[1].dp;
    for (final (lev, k) in [('feedFlow', 1.25), ('refluxFlow', 1.25), ('reboilerDuty', 1.25)]) {
      sim.setLever(lev, sim.lever(lev) * k);
    }
    steady(sim);
    final s = sim.snapshot();
    expect(s.beds[1].maxFlood, closeTo(0.9747, 0.002));
    expect(s.beds[0].maxFlood, closeTo(0.8427, 0.002));
    expect(s.beds[1].dp, closeTo(2953.8, 0.005 * 2953.8));
    expect(s.beds[1].dp / dp0, closeTo(1.834, 0.01));
    expect(s.stages.hetp[18], closeTo(0.622, 0.002));
    expect(s.beds[1].nTheoretical, closeTo(7.55, 0.03));
    expect(s.kpis.xB, closeTo(0.01708, 3e-5));
    expect(s.kpis.xD, closeTo(0.98989, 3e-5));
    expect(s.kpis.d / kmolh, closeTo(62.05, 0.05));
    expect(s.kpis.qc / 1000, closeTo(1599, 3));
  });

  test('F21 leaves the other quantities of its bed alone (dP within 1 %), F23 changes x by less than 0.007', () {
    // the F21 rows already assert dP; here the shape of the evidence in the learner's terms (PDT flat, TI span down)
    final base = steady(h7Sim()).snapshot();
    final sim = h7Sim();
    sim.faults.inject(FaultSpec(
        type: FaultType.packingMaldistribution, location: const FaultLocation.bed(1), severity: 0.5, ramp: 900));
    steady(sim);
    final s = sim.snapshot();
    expect((s.beds[0].dp - base.beds[0].dp).abs() / base.beds[0].dp, lessThan(0.01));
    expect((s.stages.t[1] - s.stages.t[9]).abs(), lessThan((base.stages.t[1] - base.stages.t[9]).abs() - 2));
  });
}
