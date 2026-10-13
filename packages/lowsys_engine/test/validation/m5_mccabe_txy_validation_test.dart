// M5 validation (validator, engine 9348b7c, re-run at fb33c07): McCabe–Thiele with azeotropes
// (VC-18.4, VC-28.4), T-x-y (VC-28.5) and the Tier-3 explain lines (VC-21),
// checked against the independent NRTL / DePriester of
// reference/tier3_reference.dart where a number is involved.
library;

import 'dart:typed_data';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/thermo_reference.dart' as ref;
import 'reference/tier3_reference.dart' as t3;
import 'reference/validation_expectations_m4.dart' show vc103;

const _atm = 101325.0;

Simulator _sim(String id,
    {ThermoTier? tier, double? e, Map<String, Object?> ov = const {}}) {
  var cfg = Presets.byId(id);
  if (tier != null) cfg = cfg.copyWith(tier: tier);
  if (e != null) cfg = cfg.copyWith(murphree: e);
  if (ov.isNotEmpty) cfg = cfg.applyOverrides(ov);
  return Simulator(cfg, options: const SimOptions(seed: 3), warmStart: false);
}

/// Independent R_min (PHYSICS.md 14.1): s_min = max over [x_q, x_D) of
/// (x_D − y*)/(x_D − x) on a 1e-4 grid, then golden section; q = 1.
(double, double) _rMinRef(double xD, double z) {
  double y(double x) => t3.bubbleTY(t3.ewNrtl.k, _atm, x).$2;
  double s(double x) => (xD - y(x)) / (xD - x);
  var best = s(z), xb = z;
  for (var x = z; x < xD - 1e-4; x += 1e-4) {
    final v = s(x);
    if (v > best) {
      best = v;
      xb = x;
    }
  }
  if (xb > z) {
    var a = xb - 1e-4, b = xb + 1e-4;
    for (var i = 0; i < 80; i++) {
      final c = b - 0.618033988749895 * (b - a), d = a + 0.618033988749895 * (b - a);
      if (s(c) > s(d)) {
        b = d;
      } else {
        a = c;
      }
    }
    xb = 0.5 * (a + b);
    best = s(xb);
  }
  return (best / (1 - best), xb);
}

void main() {
  group('VC-18.4 / VC-28.4 R_min construction', () {
    test('VC-1 configuration (B-T Tier 1, α 2.5, z 0.5, q 1, x_D 0.95): builder R_min 1.1000', () {
      final m = _sim('bt');
      final mt = McCabeThieleBuilder()
          .build(m.snapshot(), m.thermo, showRmin: true, xDTarget: 0.95);
      expect(mt.rmin!.rMin!, closeTo(1.1000, 1e-4));
      expect(mt.rmin!.tangentPinch, isFalse);
      expect(mt.rmin!.blocked, isNull);
    });

    test('ew, z 0.10, q 1: x_D 0.85 tangent pinch 0.753 / 1.873, feed pinch alone 1.165; x_D 0.80 feed pinch 1.021; engine = independent search',
        () {
      final m = _sim('ew', e: 1.0);
      final s = m.snapshot();
      final b = McCabeThieleBuilder();
      final (r85, x85) = _rMinRef(0.85, 0.10);
      expect(r85, closeTo(1.873, 0.005));
      expect(x85, closeTo(0.753, 0.003));
      final d85 = b.build(s, m.thermo, showRmin: true, xDTarget: 0.85).rmin!;
      expect(d85.rMin!, closeTo(r85, 1e-3));
      expect(d85.pinch!.x, closeTo(x85, 2e-3));
      expect(d85.tangentPinch, isTrue);
      // the line touches the curve at the pinch: y* = x_D − s_min (x_D − x)
      final yp = t3.bubbleTY(t3.ewNrtl.k, _atm, d85.pinch!.x).$2;
      expect(d85.pinch!.y, closeTo(yp, 1e-6));
      expect(d85.line, isNotNull);
      // feed pinch alone
      final yq = t3.bubbleTY(t3.ewNrtl.k, _atm, 0.10).$2;
      final sF = (0.85 - yq) / (0.85 - 0.10);
      expect(sF / (1 - sF), closeTo(1.165, 0.005));
      final (r80, x80) = _rMinRef(0.80, 0.10);
      expect(r80, closeTo(1.021, 0.005));
      expect(x80, closeTo(0.10, 1e-9));
      final d80 = b.build(s, m.thermo, showRmin: true, xDTarget: 0.80).rmin!;
      expect(d80.rMin!, closeTo(r80, 1e-3));
      expect(d80.tangentPinch, isFalse);
      // the tangent pinch takes over between x_D 0.80 and 0.82
      final d82 = b.build(s, m.thermo, showRmin: true, xDTarget: 0.82).rmin!;
      expect(d82.tangentPinch, isTrue);
      expect(d82.rMin!, closeTo(_rMinRef(0.82, 0.10).$1, 1e-3));
    });

    test('ew x_D 0.90 blocked at the azeotrope found at P_top; ac x_B 0.30 blocked on the stripping side', () {
      final m = _sim('ew', e: 1.0);
      final d = McCabeThieleBuilder()
          .build(m.snapshot(), m.thermo, showRmin: true, xDTarget: 0.90)
          .rmin!;
      expect(d.rMin, isNull);
      expect(d.sMin, isNull);
      expect(d.line, isNull);
      expect(d.blocked!.side, AzeotropeSide.distillate);
      expect(d.blocked!.xAzeotrope,
          closeTo(TxyData.findAzeotropes(m.thermo, m.snapshot().kpis.pTop).single.x, 1e-6));
      final a = _sim('ac', e: 1.0);
      final da = McCabeThieleBuilder()
          .build(a.snapshot(), a.thermo, showRmin: true, xBTarget: 0.30)
          .rmin!;
      expect(da.blocked!.side, AzeotropeSide.bottoms);
      expect(da.blocked!.xAzeotrope, closeTo(0.3335, 2e-3));
    });
  });

  group('VC-28.4 q-line root search', () {
    test('ew, q 0.5, z 0.5: the crossing at x 0.385 ± 0.001, the only one on [0, 1]; |y_line − y*| < 1e-8',
        () {
      final th = Tier3Nrtl.fromIds(['ethanol', 'water']);
      final z = Float64List.fromList([0.5, 0.5]);
      // a feed temperature at which (3.15) gives q = 0.5 at 1 atm
      final tF = ref.bisect((t) => th.qOfFeed(t, _atm, z) - 0.5, 352, 368);
      final m = _sim('ew', e: 1.0, ov: {
        'feeds[0].z': [0.5, 0.5],
        'feeds[0].thermal': {'t': tF}
      });
      final s = m.snapshot();
      final q = s.streams[StreamId.feed]!.q;
      expect(q, closeTo(0.5, 1e-6), reason: 'feed q at the feed tray');
      final mt = McCabeThieleBuilder().build(s, m.thermo);
      final e = mt.qLine!.b;
      expect(e.x, closeTo(0.385, 0.001));
      final yLine = 0.5 + q / (q - 1) * (e.x - 0.5);
      final yStar = t3.bubbleTY(t3.ewNrtl.k, _atm, e.x).$2;
      expect((yLine - yStar).abs(), lessThan(1e-8));
      expect(e.y, closeTo(yStar, 1e-8));
      // the only crossing on [0, 1]
      var sign = 0, changes = 0;
      for (var x = 0.0005; x < 1; x += 0.001) {
        final f = 0.5 + q / (q - 1) * (x - 0.5) - t3.bubbleTY(t3.ewNrtl.k, _atm, x).$2;
        final sg = f > 0 ? 1 : -1;
        if (sign != 0 && sg != sign) changes++;
        sign = sg;
      }
      expect(changes, 1);
    });

    test('ew, z 0.95 (above the azeotrope), saturated liquid: the q-line meets the curve at x 0.95 with y* < x',
        () {
      final m = _sim('ew', e: 1.0, ov: {'feeds[0].z': [0.95, 0.05]});
      final yStar = t3.bubbleTY(t3.ewNrtl.k, _atm, 0.95).$2;
      expect(yStar, lessThan(0.95));
      for (final t in [0.0, 1.0, 60.0]) {
        if (t > 0) m.advance(t - m.time);
        final s = m.snapshot();
        final q = s.streams[StreamId.feed]!.q;
        final mt = McCabeThieleBuilder().build(s, m.thermo);
        final e = mt.qLine!.b;
        expect(e.x, closeTo(0.95, 1e-3),
            reason: 't $t s: q ${q.toStringAsFixed(9)}, end (${e.x}, ${e.y})');
        expect(e.y, lessThan(0.95), reason: 't $t s, q $q: end (${e.x}, ${e.y})');
      }
    });
  });

  group('VC-28.5 T-x-y', () {
    test('mw, ew, ac at 1 atm: one sweep makes both curves (T_dew(y*) = T_bub to 1e-6 K); markers = findAzeotropes; independent bubble points',
        () {
      for (final (id, r) in [('mw', t3.mwNrtl), ('ew', t3.ewNrtl), ('ac', t3.acNrtl)]) {
        final m = _sim(id, tier: ThermoTier.t3);
        final th = m.thermo;
        final d = TxyData.build(th, _atm);
        expect(d.x.length, d.tBubble.length);
        expect(d.yDew.length, d.x.length);
        // the dew curve is the bubble sweep's (y*, T) sorted by y
        final pairs = [for (var i = 0; i < d.x.length; i++) (d.yStar[i], d.tBubble[i])]
          ..sort((a, b) => a.$1.compareTo(b.$1));
        for (var i = 0; i < pairs.length; i++) {
          expect(d.yDew[i], pairs[i].$1);
          expect(d.tDew[i], pairs[i].$2);
        }
        final xo = Float64List(2), h = SolverHealth();
        for (var i = 1; i < d.x.length - 1; i += 7) {
          final td = th.dewT(_atm, Float64List.fromList([d.yStar[i], 1 - d.yStar[i]]),
              d.tBubble[i] + 0.5, xo, h);
          expect(td, closeTo(d.tBubble[i], 1e-6), reason: '$id x ${d.x[i]}');
          final (tr, yr) = t3.bubbleTY(r.k, _atm, d.x[i]);
          expect(d.tBubble[i], closeTo(tr, 1e-6), reason: '$id x ${d.x[i]}');
          expect(d.yStar[i], closeTo(yr, 1e-9), reason: '$id x ${d.x[i]}');
        }
        final az = TxyData.findAzeotropes(th, _atm);
        expect(d.azeotropes.length, az.length, reason: id);
        for (var k = 0; k < az.length; k++) {
          expect(d.azeotropes[k].x, closeTo(az[k].x, 1e-6));
          expect(d.azeotropes[k].t, closeTo(az[k].t, 1e-5));
        }
        // refinement near the azeotrope and the ends (PHYSICS.md 14.4b)
        for (final a in az) {
          final near = [for (final x in d.x) if ((x - a.x).abs() <= 0.02) x];
          // 21 extra points (some may coincide with the 0.005 grid)
          expect(near.length, greaterThanOrEqualTo(21), reason: '$id refined');
        }
        expect(d.x.where((x) => x > 0 && x < 0.01).length, greaterThanOrEqualTo(10));
        expect(d.x.where((x) => x > 0.99 && x < 1).length, greaterThanOrEqualTo(10));
      }
    });

    test('spot values: VC-10.6 rows on the grid; B-T Tier 2 equals VC-10.3', () {
      final mw = TxyData.build(_sim('mw', tier: ThermoTier.t3).thermo, _atm);
      final ew = TxyData.build(_sim('ew').thermo, _atm);
      int at(TxyData d, double x) => d.x.indexWhere((v) => (v - x).abs() < 1e-12);
      for (final (d, x, tC, y) in [
        (mw, 0.10, 87.77, 0.4223),
        (mw, 0.50, 73.11, 0.7893),
        (ew, 0.10, 86.26, 0.4464),
        (ew, 0.50, 79.73, 0.6580),
        (ew, 0.80, 78.26, 0.8190),
      ]) {
        final i = at(d, x);
        expect(i, greaterThanOrEqualTo(0), reason: 'x $x on the grid');
        expect(d.tBubble[i] - 273.15, closeTo(tC, 0.01));
        expect(d.yStar[i], closeTo(y, 1e-4));
      }
      final bt = TxyData.build(
          ThermoFactory.build(Presets.byId('bt'), ThermoTier.t2), _atm);
      for (final (x, tC, y, _) in vc103) {
        final i = at(bt, x);
        expect(bt.tBubble[i] - 273.15, closeTo(tC, 0.002), reason: 'x $x');
        expect(bt.yStar[i], closeTo(y, 1e-5), reason: 'x $x');
      }
      expect(bt.azeotropes, isEmpty);
    });

    test('ew at 0.5 atm: azeotrope 0.9105 / 61.62 °C', () {
      final a = TxyData.build(_sim('ew').thermo, 0.5 * _atm).azeotropes.single;
      expect(a.x, closeTo(0.9105, 0.002));
      expect(a.t - 273.15, closeTo(61.62, 0.05));
    });

    // ENGINE_API.md 7.3 caches per "p rounded to 100 Pa"; PHYSICS.md 14.4b and
    // VC-28.5 say "recomputed only when P changes by more than 100 Pa". At
    // 101 325 Pa a +30 Pa change crosses the 101 350 Pa rounding boundary and
    // rebuilds (OPEN_ITEMS.md, M5 validation). Asserted here: what both agree
    // on (same 100-Pa bucket → reused; > 150 Pa → rebuilt).
    test('TxyBuilder caches per 100 Pa: a −20 Pa change reuses the curves, a 300-Pa change rebuilds them',
        () {
      final m = _sim('ew', e: 1.0);
      m.runToSteadyState();
      final b = TxyBuilder();
      final s0 = m.snapshot();
      final v0 = b.build(s0, m.thermo);
      m.setLever('pTop', s0.kpis.pTop - 20);
      m.advance(1800);
      final s1 = m.snapshot();
      expect((s1.kpis.pTop - s0.kpis.pTop).abs(), lessThan(100));
      expect(identical(b.build(s1, m.thermo).top, v0.top), isTrue);
      m.setLever('pTop', s0.kpis.pTop + 300);
      m.advance(1800);
      final s2 = m.snapshot();
      expect((s2.kpis.pTop - s0.kpis.pTop).abs(), greaterThan(150));
      final v2 = b.build(s2, m.thermo);
      expect(identical(v2.top, v0.top), isFalse);
      expect(v2.top.p, closeTo(s2.kpis.pTop, 100));
    });

    test('one TxyData.build takes < 2 ms (median of 21 warm builds, desktop)', () {
      final th = _sim('ew').thermo;
      for (var i = 0; i < 5; i++) {
        TxyData.build(th, _atm + i);
      }
      final ts = <int>[];
      for (var i = 0; i < 21; i++) {
        final sw = Stopwatch()..start();
        TxyData.build(th, _atm + 10 * i);
        ts.add(sw.elapsedMicroseconds);
      }
      ts.sort();
      expect(ts[10] / 1000, lessThan(2.0), reason: 'median ${ts[10]} µs');
    });

    test('Tier 1 on ew: ideal, Raoult curves (78.298 / 100.018 °C), no marker, every stage point on the bubble curve (1e-6 K)',
        () {
      final m = _sim('ew', tier: ThermoTier.t1, e: 1.0);
      m.advance(1200);
      final s = m.snapshot();
      final raoult = m.tier2Thermo;
      final v = TxyBuilder().build(s, raoult);
      expect(v.top.ideal, isTrue);
      expect(v.top.azeotropes, isEmpty);
      expect(v.top.tBubble.first - 273.15, closeTo(100.018, 0.005));
      expect(v.top.tBubble.last - 273.15, closeTo(78.298, 0.005));
      final y = Float64List(2), k = Float64List(2);
      for (var j = 0; j < v.stages.length; j++) {
        final p = v.stages[j];
        final tb = raoult.bubbleT(s.stages.p[j], Float64List.fromList([p.x, 1 - p.x]),
            p.y, y, k, SolverHealth());
        expect(p.y, closeTo(tb, 1e-6), reason: 'stage $j');
      }
    });

    test('c4 Tier 3 at 7 bar: no azeotrope; end points where K_i = 1 (± 0.01 K)', () {
      final m = _sim('c4', tier: ThermoTier.t3);
      final d = TxyData.build(m.thermo, 7e5);
      expect(d.azeotropes, isEmpty);
      expect(d.tBubble.first, closeTo(t3.tKEqualsOne('nbutane', 7e5), 0.01));
      expect(d.tBubble.last, closeTo(t3.tKEqualsOne('isobutane', 7e5), 0.01));
      expect(1.8 * d.tBubble.first, inInclusiveRange(365, 852));
    });
  });

  group('VC-21 Tier-3 explain lines on every tray', () {
    // PHYSICS.md 15, tray row
    const catalogue = {
      'eq.componentBalance', 'eq.equilibrium.T1', 'eq.raoult', 'eq.nrtl',
      'eq.depriester', 'eq.bubblePoint', 'eq.murphree', 'eq.vapourFlow.cmo',
      'eq.vapourFlow.energy', 'eq.bennett', 'eq.dryDP', 'eq.trayDP',
      'eq.jetFlood', 'eq.entrainment', 'eq.downcomer', 'eq.weeping'
    };
    for (final (id, line) in [('ew', 'eq.nrtl'), ('ac', 'eq.nrtl'), ('c4', 'eq.depriester')]) {
      test('$id: $line equals y* on every tray (1e-12), with TeX; every tray id is in the §15 catalogue', () {
        final m = _sim(id, tier: ThermoTier.t3);
        m.advance(600);
        final s = m.snapshot();
        final nc = s.stages.nc;
        for (var j = 1; j <= s.layout.nTrays; j++) {
          final r = m.explain(ExplainStage(j));
          expect(r.time, s.time);
          final lines = [for (final g in r.groups) ...g.lines];
          final l = lines.firstWhere((l) => l.id == line, orElse: () => fail('$line missing on tray $j'));
          expect((l.value - s.stages.yStar[j * nc]).abs(),
              lessThanOrEqualTo(1e-12 * s.stages.yStar[j * nc].abs() + 1e-300),
              reason: 'tray $j');
          expect(l.texSymbolic, isNotEmpty);
          expect(l.texSubstituted, isNotEmpty);
          expect(lines.any((l) => l.id == 'eq.equilibrium.T2' || l.id == 'eq.raoult'), isFalse);
          for (final l in lines) {
            expect(l.value.isFinite, isTrue, reason: '${l.id} tray $j');
            expect(catalogue, contains(l.id), reason: 'tray $j');
          }
        }
      });
    }
    test('ew Tier 3 tray: the §15 tray row lists eq.bubblePoint (3.6.1 result); the line equals T_j', () {
      final m = _sim('ew');
      m.advance(600);
      final s = m.snapshot();
      final lines = [for (final g in m.explain(const ExplainStage(10)).groups) ...g.lines];
      final ids = [for (final l in lines) l.id];
      final l = lines.where((l) => l.id == 'eq.bubblePoint');
      expect(l, isNotEmpty, reason: 'tray 10 lines: $ids');
      expect(l.first.value, closeTo(s.stages.t[10], 1e-9 * s.stages.t[10]));
    });
  });
}
