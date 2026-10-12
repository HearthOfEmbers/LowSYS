import 'dart:convert';
import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
      'banded solver (tridiagonal + one sub-diagonal) matches a dense Gaussian solve',
      () {
    const n = 12;
    final g = Float64List(n),
        a = Float64List(n),
        b = Float64List(n),
        c = Float64List(n),
        d = Float64List(n);
    for (var j = 0; j < n; j++) {
      g[j] = j >= 2 ? -0.1 - 0.01 * j : 0;
      a[j] = j >= 1 ? -0.3 + 0.01 * j : 0;
      c[j] = j < n - 1 ? -0.2 : 0;
      b[j] = 2.0 + 0.1 * j;
      d[j] = 1.0 + j * 0.5;
    }
    final out = Float64List(n);
    BandedSolver.solve(n, g, a, b, c, d, out, Float64List(n), Float64List(n));
    // dense reference
    final m = List.generate(n, (_) => List<double>.filled(n + 1, 0));
    for (var j = 0; j < n; j++) {
      if (j >= 2) m[j][j - 2] = g[j];
      if (j >= 1) m[j][j - 1] = a[j];
      m[j][j] = b[j];
      if (j < n - 1) m[j][j + 1] = c[j];
      m[j][n] = d[j];
    }
    for (var col = 0; col < n; col++) {
      for (var r = col + 1; r < n; r++) {
        final f = m[r][col] / m[col][col];
        for (var k = col; k <= n; k++) {
          m[r][k] -= f * m[col][k];
        }
      }
    }
    final x = List<double>.filled(n, 0);
    for (var r = n - 1; r >= 0; r--) {
      var s = m[r][n];
      for (var k = r + 1; k < n; k++) {
        s -= m[r][k] * x[k];
      }
      x[r] = s / m[r][r];
    }
    for (var j = 0; j < n; j++) {
      expect(out[j], closeTo(x[j], 1e-12));
    }
  });

  test('config JSON round trip and validation', () {
    final cfg = Presets.byId('bt');
    final again = ColumnConfig.fromJson(
        jsonDecode(jsonEncode(cfg.toJson())) as Map<String, Object?>);
    expect(jsonEncode(again.toJson()), jsonEncode(cfg.toJson()));
    expect(cfg.validate(), isEmpty);
    expect(cfg.withTrays(2).validate(), isNotEmpty);
    final o = cfg.applyOverrides(
        {'sections[0].trays': 60, 'feeds[0].stage': 30, 'murphree': 1.0});
    expect(o.trayCount, 60);
    expect(o.feeds.first.stage, 30);
    expect(o.murphree, 1.0);
    expect(() => Simulator(cfg.withTrays(70)), throwsA(isA<ConfigException>()));
  });

  test('VC-20 determinism: identical runs give identical saveState JSON', () {
    String run() {
      final sim = Simulator(Presets.byId('bt'), warmStart: false);
      for (var i = 0; i < 10000; i++) {
        if (i == 3000) sim.setLever('refluxFlow', kmolh(105));
        if (i == 6000) sim.setLever('feedZ.benzene', 0.45);
        sim.step();
      }
      return jsonEncode(sim.saveState());
    }

    expect(run(), run());
  });

  test('save and restore continue bit-identically', () {
    final a = Simulator(Presets.byId('bt'), warmStart: false)..advance(1000);
    final saved = jsonDecode(jsonEncode(a.saveState())) as Map<String, Object?>;
    final b = Simulator.restore(saved);
    a.advance(500);
    b.advance(500);
    expect(jsonEncode(b.saveState()), jsonEncode(a.saveState()));
  });

  test('unit conversions (SI and US field)', () {
    const si = UnitSystem.si, us = UnitSystem.usField;
    expect(si.fromSI(Quantity.temperature, 353.15), closeTo(80, 1e-9));
    expect(us.fromSI(Quantity.temperature, 373.15), closeTo(212, 1e-9));
    expect(si.fromSI(Quantity.molarFlow, 1 / 3.6), closeTo(1, 1e-12));
    expect(us.fromSI(Quantity.molarFlow, 453.59237 / 3600), closeTo(1, 1e-12));
    expect(us.fromSI(Quantity.pressure, 6894.757293), closeTo(1, 1e-12));
    for (final q in Quantity.values) {
      for (final u in [si, us]) {
        expect(u.toSI(q, u.fromSI(q, 12.5)), closeTo(12.5, 1e-9),
            reason: '$q ${u.name}');
      }
    }
    expect(Fmt.value(Quantity.fraction, 0.981183), '0.9812');
    expect(Fmt.value(Quantity.fraction, 0.995951), '0.995951');
    expect(Fmt.value(Quantity.fraction, 0.5), '0.5000');
    expect(Fmt.value(Quantity.molarFlow, 50 / 3.6), '50.0');
  });

  test('layout, streams and loops are reported in the snapshot', () {
    final s = btSim().snapshot();
    expect(s.layout.nTrays, 20);
    expect(s.layout.feedStages, [10]);
    expect(s.loops.map((l) => l.tag), ['LC-101', 'LC-102']);
    expect(s.streams[StreamId.feed]!.flow, closeTo(100 / 3.6, 1e-9));
    expect(s.kpis.refluxRatio, closeTo(2.0, 1e-6));
    expect(s.kpis.balanceResidual, lessThan(1e-8));
    expect(s.steady.isSteady, isTrue);
  });

  test('step speed (informational)', () {
    final sim = btSim();
    final sw = Stopwatch()..start();
    const n = 20000;
    for (var i = 0; i < n; i++) {
      sim.step();
    }
    final us = sw.elapsedMicroseconds / n;
    // ignore: avoid_print
    print(
        'Simulator.step(): ${us.toStringAsFixed(1)} us per step (JIT, 22 stages)');
    expect(us, lessThan(500));
  });
}
