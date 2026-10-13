import 'package:lowsys_engine/lowsys_engine.dart';

CrudeProductKpis k(Simulator s) => s.snapshot().kpis.crude!;
void main() {
  // G16: PA 3 MW
  var s = Simulator(Presets.byId('crude'));
  s.setLever('paDuty', 3e6);
  double? tMeet, tSteady;
  for (var t = 30; t <= 6 * 3600; t += 30) {
    s.advance(30);
    final q = k(s);
    if (tMeet == null && q.d86p95[1] <= 508.15 && q.gapDieselKero >= 0 && q.residueTbp5 >= 628.15) tMeet = t.toDouble();
    if (tSteady == null && s.isSteady) tSteady = t.toDouble();
  }
  print('G16 PA 3 MW: specs met at $tMeet s, monitor steady at $tSteady s');
  for (final c in [('steam_loss', FaultType.strippingSteamLoss, const FaultLocation.steam('bottom'), 0.85, 60.0), ('pa_trip', FaultType.pumparoundTrip, const FaultLocation.equipment('pumparound'), 0.85, 0.0), ('cot_low', FaultType.cotUpset, const FaultLocation.equipment('furnace'), 0.8, 300.0)]) {
    s = Simulator(Presets.byId('crude'));
    final b = k(s);
    s.faults.inject(FaultSpec(type: c.$2, location: c.$3, severity: c.$4, onset: 0, ramp: c.$5, params: c.$1 == 'cot_low' ? const {'dT': -15} : const {}));
    double? first;
    double hold = 0;
    double? offAt;
    for (var t = 10; t <= 3600; t += 10) {
      s.advance(10);
      final q = k(s);
      final off = (q.d86p95[1] - b.d86p95[1] > 8) || (q.d86p95[2] - b.d86p95[2] > 10) || (q.yieldVolPct[4] - b.yieldVolPct[4] > 1.0);
      if (off) { first ??= t.toDouble(); hold += 10; if (hold >= 300 && offAt == null) offAt = t.toDouble(); } else { hold = 0; first = null; }
    }
    print('H8 ${c.$1}: off-spec condition first true at $first, held 300 s by $offAt s from onset');
  }
}
