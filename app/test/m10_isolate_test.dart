// M10: the background-isolate runner gives the same trajectory as the local runner and mirrors trends.
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/controllers/isolate_sim_runner.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

void main() {
  test('isolate runner matches the local runner, mirrors trends, and rethrows range errors', () async {
    final iso = IsolateSimRunner();
    final loc = LocalSimRunner();
    final cfg = Presets.byId(Presets.bt);
    await iso.load(cfg);
    await loc.load(cfg);
    expect(iso.config.trayCount, cfg.trayCount);
    expect(iso.levers.isNotEmpty, true);
    const req = FrameRequest(trendTags: ['PV:FT-102']);
    FrameResult? a, b;
    for (var i = 0; i < 40; i++) {
      a = await iso.frame(req, advanceSeconds: 5, budget: const Duration(seconds: 5));
      b = await loc.frame(req, advanceSeconds: 5, budget: const Duration(seconds: 5));
    }
    expect(a!.snapshot.time, b!.snapshot.time);
    expect(a.snapshot.time, greaterThan(150));
    expect(a.snapshot.kpis.xD, b.snapshot.kpis.xD);
    expect(a.mccabe, isNotNull);
    // trends: the mirror has the bins the local buffer has, with the same values
    final i0 = iso.trends.indexOf('PV:FT-102');
    final l0 = loc.trends.indexOf('PV:FT-102');
    expect(i0, isNotNull);
    expect(iso.trends.count, loc.trends.count);
    expect(iso.trends.count, greaterThan(20));
    expect(iso.trends.mean(i0!, iso.trends.count - 1), loc.trends.mean(l0!, loc.trends.count - 1));
    await expectLater(iso.setLever('refluxFlow', -1e9), throwsA(isA<RangeError>()));
    await iso.dispose();
    await loc.dispose();
  });
}
