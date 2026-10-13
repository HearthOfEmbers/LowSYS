// M7 coder: full-hydraulics steady run at the ruled diameters (0.75 m debut / 0.55 m deprop); numbers are reported
// in DEVIATIONS "M7 app". Asserts only what holds: the run is finite and the pressure lever spans 3-25 bar.
import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final id in ['c4', 'debut', 'deprop']) {
    test('$id pTop lever 3-25 bar', () {
      final sim = Simulator(Presets.byId(id), options: const SimOptions(seed: 3), warmStart: false);
      final l = sim.levers.firstWhere((l) => l.id == 'pTop');
      expect(l.min, 300000);
      expect(l.max, 2.5e6);
    });
  }
  for (final id in ['debut', 'deprop']) {
    test('$id: full hydraulics run is finite; flood/weep reported', () {
      final cfg = Presets.byId(id).copyWith(hydraulics: HydraulicsMode.full);
      final sim = Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
      sim.runToSteadyState(maxSimSeconds: 100000);
      final s = sim.snapshot();
      final h = s.stages;
      var maxJet = 0.0, minJet = 9.0, maxWeep = 0.0;
      for (var i = 1; i <= s.layout.nTrays; i++) {
        maxJet = maxJet > h.jetFlood[i] ? maxJet : h.jetFlood[i];
        minJet = minJet < h.jetFlood[i] ? minJet : h.jetFlood[i];
        maxWeep = maxWeep > h.weepFrac[i] ? maxWeep : h.weepFrac[i];
        expect(h.dp[i].isFinite, isTrue);
      }
      // ignore: avoid_print
      print('$id jet ${minJet.toStringAsFixed(2)}..${maxJet.toStringAsFixed(2)} weep<=${maxWeep.toStringAsFixed(2)} dp1 ${h.dp[1].toStringAsFixed(0)}');
      expect(maxJet.isFinite, isTrue);
    });
  }
}
