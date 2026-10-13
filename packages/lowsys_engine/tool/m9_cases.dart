import 'package:lowsys_engine/lowsys_engine.dart';

String f(num v, [int d = 2]) => v.toStringAsFixed(d);

Simulator fresh() => Simulator(Presets.byId('crude'));

void steady(Simulator s) {
  final r = s.runToSteadyState(maxSimSeconds: 172800);
  if (!r.reached) print('  NOT STEADY residual ${r.residual}');
}

void show(String tag, Simulator s) {
  final sn = s.snapshot();
  final k = sn.kpis.crude!;
  print('== $tag  (t=${f(s.time / 3600, 2)} h)');
  print('  yields ${k.yieldVolPct.map((e) => f(e)).join(' / ')} OF ${f(k.overflashVolPct)}  Qc ${f(k.qc / 1e6, 3)} MW  flood ${f(sn.kpis.maxFloodPct, 1)}');
  print('  D86 95 kero ${f(k.d86p95[1] - 273.15, 1)} diesel ${f(k.d86p95[2] - 273.15, 1)} | D86 5 diesel ${f(k.d86p5[2] - 273.15, 1)} AGO95 ${f(k.d86p95[3] - 273.15, 1)} gaps ${f(k.gapKeroNaphtha, 1)} ${f(k.gapDieselKero, 1)} ${f(k.gapAgoDiesel, 1)} res5 ${f(k.residueTbp5 - 273.15, 1)}');
  print('  T1 ${f(k.topT - 273.15, 1)} FZ ${f(k.flashZoneT - 273.15, 1)} T30 ${f(k.bottomT - 273.15, 1)} COT ${f(k.cot - 273.15, 1)} PA ${f(k.qPa / 1e6, 2)} MW ret ${f(k.paReturnT - 273.15, 1)} dry ${k.drawDry} paLim ${k.paDutyLimited} reflux ${f(sn.streams[StreamId.reflux]!.flow * 3.6, 1)}');
}

void main(List<String> args) {
  final which = args.isEmpty ? 'all' : args[0];
  bool run(String n) => which == 'all' || which == n;
  final base = fresh();
  if (run('base')) show('default', base);
  if (run('dir')) {
    var s = fresh();
    s.setLever('drawRate.kero', 0.137 * 0.0368056);
    steady(s);
    show('kero +2 % (13.7)', s);
    s = fresh();
    s.setLever('drawRate.kero', 0.097 * 0.0368056);
    steady(s);
    show('kero 9.7', s);
    s = fresh();
    s.setLever('cot', 623.15);
    steady(s);
    show('COT 350', s);
    s = fresh();
    s.setLever('paDuty', 3e6);
    steady(s);
    show('PA 3 MW', s);
    s = fresh();
    s.setLever('steam.bottom', 1000 / 3600);
    steady(s);
    show('bottom steam 1000', s);
    s = fresh();
    s.setLever('steam.ss2', 1000 / 3600);
    steady(s);
    show('SS2 steam 1000', s);
    s = fresh();
    s.setLever('drawRate.kero', 0.107 * 0.0368056);
    s.setLever('drawRate.diesel', 0.177 * 0.0368056);
    steady(s);
    show('kero 10.7 diesel 17.7', s);
  }
  if (run('f27')) {
    var s = fresh();
    s.setLever('drawRate.kero', 0.16 * 0.0368056);
    steady(s);
    show('kero 16 %', s);
    s = fresh();
    s.setLever('paDuty', 8e6);
    steady(s);
    show('PA 8 MW', s);
  }
  if (run('faults')) {
    for (final c in [
      ('F24 bottom 1', FaultType.strippingSteamLoss, const FaultLocation.steam('bottom'), 1.0, 60.0, <String, Object?>{}),
      ('F24 bottom 0.5', FaultType.strippingSteamLoss, const FaultLocation.steam('bottom'), 0.5, 60.0, <String, Object?>{}),
      ('F24 ss2 1', FaultType.strippingSteamLoss, const FaultLocation.steam('ss2'), 1.0, 60.0, <String, Object?>{}),
      ('F25 1', FaultType.pumparoundTrip, const FaultLocation.equipment('pumparound'), 1.0, 0.0, <String, Object?>{}),
      ('F25 0.85', FaultType.pumparoundTrip, const FaultLocation.equipment('pumparound'), 0.85, 0.0, <String, Object?>{}),
      ('F25 0.5', FaultType.pumparoundTrip, const FaultLocation.equipment('pumparound'), 0.5, 0.0, <String, Object?>{}),
      ('F26 1', FaultType.cotUpset, const FaultLocation.equipment('furnace'), 1.0, 300.0, <String, Object?>{'dT': -15}),
      ('F26 0.6', FaultType.cotUpset, const FaultLocation.equipment('furnace'), 0.6, 300.0, <String, Object?>{'dT': -15}),
    ]) {
      final s = fresh();
      s.faults.inject(FaultSpec(type: c.$2, location: c.$3, severity: c.$4, onset: 0, ramp: c.$5, params: c.$6));
      steady(s);
      show(c.$1, s);
    }
  }
}
