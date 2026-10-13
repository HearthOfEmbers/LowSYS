// M8 coder tests: bt_packed steady states (VC-13.5), the mixed template, structure rules (VC-13.9).
import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'm8_helpers.dart';

void main() {
  saveRestoreTests();
  group('VC-13.5 steady states', () {
    test('Tier 1 full: x_D, x_B, D, bed dP and phi_p, column dP, max flood', () {
      final sim = steady(packedSim());
      final s = sim.snapshot();
      expect(s.kpis.xD, closeTo(0.99383, 2e-5));
      expect(s.kpis.xB, closeTo(0.00617, 2e-5));
      expect(s.kpis.d / kmolh, closeTo(50.0, 0.01));
      expect(s.beds.length, 2);
      expect(s.beds[0].dp, closeTo(587.4, 0.005 * 587.4));
      expect(s.beds[1].dp, closeTo(818.6, 0.005 * 818.6));
      expect(s.beds[0].maxFlood, closeTo(0.4882, 0.002));
      expect(s.beds[1].maxFlood, closeTo(0.5938, 0.002));
      expect(s.beds[0].nTheoretical, closeTo(9, 1e-9));
      expect(s.beds[1].nTheoretical, closeTo(9, 1e-9));
      expect(s.kpis.columnDp, closeTo(1406.0, 0.005 * 1406));
      expect(s.kpis.maxFloodPct, closeTo(59.38, 0.2));
      // the design point: HETP = HETP_ref and E_O = 1 in every segment
      expect(s.stages.hetp[18], closeTo(0.5, 1e-6));
      expect(s.stages.efficiency[10], closeTo(1.0, 1e-6));
      expect(s.stages.hetp[5], closeTo(0.5, 1e-6));
      expect(s.stages.hetp[0].isNaN, isTrue, reason: 'NaN outside packed segments');
      expect(s.layout.kinds[1], StageKind.packed);
      expect(s.layout.kinds[19], StageKind.sump);
      expect(s.layout.sectionEnds, [9, 18]);
      expect(s.beds[0].firstStage, 1);
      expect(s.beds[1].lastStage, 18);
      expect(s.beds[1].packingId, 'struct250');
    });

    test('Tier 1 ideal hydraulics: same compositions, no dP and no flooding', () {
      final sim = steady(packedSim(hydraulics: 'ideal'));
      final s = sim.snapshot();
      expect(s.kpis.xD, closeTo(0.99383, 2e-5));
      expect(s.kpis.xB, closeTo(0.00617, 2e-5));
      expect(s.beds[0].dp, 0);
      expect(s.beds[1].dp, 0);
      expect(s.kpis.columnDp, 0);
      expect(s.kpis.maxFloodPct, 0);
      expect(s.stages.hetp[7], closeTo(0.5, 1e-9));
    });

    test('Tier 2 full: compositions, bed dP, temperatures, condenser duty', () {
      final sim = steady(packedSim(tier: 't2'));
      final s = sim.snapshot();
      expect(s.kpis.xD, closeTo(0.99339, 2e-5));
      expect(s.kpis.xB, closeTo(0.01063, 2e-5));
      expect(s.kpis.d / kmolh, closeTo(49.796, 0.01));
      expect(s.beds[0].dp, closeTo(579.5, 0.005 * 579.5));
      expect(s.beds[1].dp, closeTo(696.7, 0.005 * 696.7));
      expect(s.beds[0].maxFlood, closeTo(0.4699, 0.002));
      expect(s.beds[1].maxFlood, closeTo(0.5488, 0.002));
      expect(s.stages.t[19] - 273.15, closeTo(110.56, 0.02));
      for (final (j, t) in [(1, 80.44), (9, 91.80), (10, 93.37), (18, 110.06)]) {
        expect(s.stages.t[j] - 273.15, closeTo(t, 0.02), reason: 'T of stage $j');
      }
      expect(s.kpis.qc / 1000, closeTo(1279.9, 1.0));
      expect(s.kpis.columnDp, closeTo(1276.2, 0.005 * 1276));
    });

    test('Tier 2 ideal hydraulics', () {
      final s = steady(packedSim(tier: 't2', hydraulics: 'ideal')).snapshot();
      expect(s.kpis.xD, closeTo(0.99326, 2e-5));
      expect(s.kpis.xB, closeTo(0.01033, 2e-5));
      expect(s.kpis.d / kmolh, closeTo(49.817, 0.01));
      expect(s.stages.t[19] - 273.15, closeTo(110.14, 0.02));
    });

    test('mixed template (bed over 11 sieve trays, feed 10), Tier 1 ideal', () {
      final cfg = Presets.byId('bt').withInternals(2);
      expect(cfg.trayCount, 20);
      expect(cfg.beds.length, 1);
      final sim = steady(Simulator(cfg, warmStart: false));
      final s = sim.snapshot();
      expect(s.kpis.xD, closeTo(0.99133, 2e-5));
      expect(s.kpis.xB, closeTo(0.00867, 2e-5));
      expect(s.layout.kinds[9], StageKind.packed);
      expect(s.layout.kinds[10], StageKind.tray);
      // murphree acts on trays 10-20 only: the packed segments keep E = 1
      expect(s.stages.efficiency[5], closeTo(1.0, 1e-6));
      expect(s.stages.efficiency[12], closeTo(0.7, 1e-6));
    });

    test('bt with 20 trays at E 0.7 (solver check, VC-4.1)', () {
      final s = steady(Simulator(Presets.byId('bt'), warmStart: false)).snapshot();
      expect(s.kpis.xD, closeTo(0.981183, 2e-5));
    });
  });

  group('VC-13.9 structure', () {
    test('segmentation and the preset', () {
      final c = Presets.byId('bt_packed');
      expect(c.trayCount, 18);
      expect(c.beds.map((b) => (b.first, b.last)), [(1, 9), (10, 18)]);
      expect(c.feeds.first.stage, 10);
      expect(c.hydraulics, HydraulicsMode.full);
      expect(c.internals, 1);
      expect(c.control.trayList(18), [1, 3, 5, 7, 9, 10, 12, 14, 16, 18]);
      expect(c.internalsTemplates.map((t) => t.id), [0, 1, 2]);
      expect(Presets.byId('bt').internals, 0);
    });

    test('a feed on a mid-bed segment fails validate(); bed tops and trays pass', () {
      final c = Presets.byId('bt_packed');
      for (final stage in [2, 5, 9, 11, 18]) {
        final bad = c.copyWith(feeds: [c.feeds.first.copyWith(stage: stage)]);
        expect(bad.validate().any((p) => p.contains('packed bed')), isTrue, reason: 'stage $stage');
      }
      for (final stage in [1, 10]) {
        expect(c.copyWith(feeds: [c.feeds.first.copyWith(stage: stage)]).validate(), isEmpty);
      }
      expect(c.copyWith(sections: [const PackedSection(bedHeight: 20, packingId: 'struct250')]).validate(), isNotEmpty);
      expect(c.copyWith(sections: [const PackedSection(bedHeight: 4.5, packingId: 'nope')]).validate(), isNotEmpty);
      expect(c.feedableStages, [1, 10]);
      expect(Presets.byId('bt').feedableStages.length, 20);
    });

    test('lever availability', () {
      final p = packedSim();
      final ids = p.levers.map((l) => l.id).toSet();
      expect(ids.contains('murphree'), isFalse);
      expect(ids.contains('nTrays'), isFalse);
      expect(ids.contains('trayType.0'), isFalse);
      expect(ids.contains('internals'), isTrue);
      expect(p.levers.firstWhere((l) => l.id == 'feedStage').options, [1, 10]);
      expect(p.levers.firstWhere((l) => l.id == 'internals').requiresPause, isTrue);
      expect(() => p.setLever('feedStage', 5), throwsA(isA<RangeError>()));
      p.setLever('feedStage', 1);
      expect(p.lever('feedStage'), 1);
      final bt = Simulator(Presets.byId('bt'), warmStart: false);
      expect(bt.levers.any((l) => l.id == 'murphree'), isTrue);
      expect(bt.levers.any((l) => l.id == 'nTrays'), isTrue);
      expect(bt.levers.any((l) => l.id == 'internals'), isTrue);
      final mw = Simulator(Presets.byId('mw'), warmStart: false);
      expect(mw.levers.any((l) => l.id == 'internals'), isFalse);
      // overriding sections removes the templates and the lever
      final ov = Simulator(
          Presets.byId('bt').applyOverrides({'sections': [Presets.byId('bt').sections.first.toJson()]}),
          warmStart: false);
      expect(ov.levers.any((l) => l.id == 'internals'), isFalse);
      // the mixed template keeps murphree and trayType for its tray section
      final mixed = Simulator(Presets.byId('bt').withInternals(2), warmStart: false);
      expect(mixed.levers.any((l) => l.id == 'murphree'), isTrue);
      expect(mixed.levers.any((l) => l.id == 'trayType.1'), isTrue);
      expect(mixed.levers.any((l) => l.id == 'nTrays'), isFalse);
      expect(mixed.levers.firstWhere((l) => l.id == 'feedStage').options!.length, 12);
    });

    test('internals 0 -> 1 -> 2 -> 0 rebuilds without NaN and keeps TI state by tag', () {
      final sim = Simulator(Presets.byId('bt').applyOverrides({'tier': 't2', 'hydraulics': 'full'}), warmStart: false);
      sim.runToSteadyState(maxSimSeconds: 100000);
      sim.advance(60);
      var tags = sim.snapshot().instruments.map((i) => i.tag).toSet();
      expect(tags.contains('TI-114'), isTrue);
      expect(tags.contains('PDT-102'), isFalse);
      void check(int id, int n, int beds) {
        sim.setLever('internals', id.toDouble());
        expect(sim.lever('internals'), id);
        expect(sim.config.trayCount, n);
        sim.advance(120);
        final s = sim.snapshot();
        expect(s.beds.length, beds);
        for (final v in [...s.stages.x, ...s.stages.holdup, ...s.stages.t, s.kpis.xD, s.kpis.xB]) {
          expect(v.isNaN || v.isInfinite, isFalse);
        }
        expect(s.stages.holdup.every((h) => h >= 0), isTrue);
        expect(s.layout.nTrays, n);
        tags = s.instruments.map((i) => i.tag).toSet();
        expect(tags.contains('PDT-102'), beds >= 1);
        expect(tags.contains('PDT-103'), beds >= 2);
        expect(tags.contains('TI-${100 + n + 1}'), isTrue, reason: 'sump TI follows N');
      }

      check(1, 18, 2);
      expect(sim.config.feeds.first.stage, 10);
      check(2, 20, 1);
      check(0, 20, 0);
      expect(sim.snapshot().instruments.map((i) => i.tag).contains('TI-114'), isTrue);
    });

    test('PDT-102 and PDT-103 read the bed dP (0 in ideal hydraulics)', () {
      final ideal = packedSim(hydraulics: 'ideal')..advance(600);
      expect(ideal.snapshot().instruments.firstWhere((i) => i.tag == 'PDT-102').value, closeTo(0, 5));
      final full = steady(packedSim(tier: 't2'))..advance(120);
      final r = {for (final i in full.snapshot().instruments) i.tag: i};
      expect(r['PDT-102']!.value, closeTo(579.5, 20));
      expect(r['PDT-103']!.value, closeTo(696.7, 20));
      expect(r['PDT-102']!.hi, 10000);
      expect(r['PDT-101']!.value, closeTo(1276, 25));
    });

    test('plant, plantCalc and model masks', () {
      final sim = steady(packedSim(tier: 't2'));
      sim.setLever('view', 1);
      var s = sim.snapshot();
      expect(s.stages.hetp.every((v) => v.isNaN), isTrue);
      expect(s.stages.packFlood.every((v) => v.isNaN), isTrue);
      expect(s.beds[0].maxFlood.isNaN, isTrue);
      expect(s.beds[0].nTheoretical.isNaN, isTrue);
      expect(s.beds[0].eMal.isNaN, isTrue);
      expect(s.stages.packHoldup[3].isFinite, isTrue, reason: 'kept for the animation');
      expect(s.stages.wetFrac[3].isFinite, isTrue);
      expect(s.stages.efficiency.every((v) => v.isNaN), isTrue);
      sim.setLever('view', 2);
      s = sim.snapshot();
      expect(s.stages.hetp[3].isFinite, isTrue);
      expect(s.stages.packFlood[3].isFinite, isTrue);
      expect(s.beds[0].maxFlood.isFinite, isTrue);
      expect(s.beds[0].dp.isFinite, isTrue);
      expect(s.beds[0].eMal.isNaN, isTrue);
      expect(s.stages.efficiency.every((v) => v.isNaN), isTrue);
      // sandbox model view: E_mal and f are visible
      sim.setLever('view', 0);
      s = sim.snapshot();
      expect(s.beds[0].eMal, 1.0);
      expect(s.beds[0].maldistribution, 0.0);
    });

    test('F21 and F23 with a bed the column lacks raise a ConfigException', () {
      final sim = packedSim();
      expect(
          () => sim.faults.inject(
              FaultSpec(type: FaultType.packingCrush, location: const FaultLocation.bed(3), severity: 0.3)),
          throwsA(isA<ConfigException>()));
      expect(
          () => sim.faults.inject(
              FaultSpec(type: FaultType.packingMaldistribution, location: const FaultLocation.bed(0), severity: 0.3)),
          throwsA(isA<ConfigException>()));
      final tray = Simulator(Presets.byId('bt'), warmStart: false);
      expect(
          () => tray.faults.inject(
              FaultSpec(type: FaultType.packingCrush, location: const FaultLocation.bed(1), severity: 0.3)),
          throwsA(isA<ConfigException>()));
      sim.faults.inject(FaultSpec(type: FaultType.packingCrush, location: const FaultLocation.bed(2), severity: 0.3));
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Save and restore (the app persists sessions): a packed column with a bed fault resumes bit for bit.
void saveRestoreTests() {
  test('saveState / restore on bt_packed (Tier 2, F23 on bed 2): the restored run follows the original', () {
    final a = h7Sim();
    a.faults.inject(FaultSpec(type: FaultType.packingCrush, location: const FaultLocation.bed(2), severity: 0.3, onset: 100));
    a.advance(600);
    final saved = jsonDecode(jsonEncode(a.saveState())) as Map<String, Object?>;
    final b = Simulator.restore(saved);
    expect(b.config.beds.length, 2);
    expect(b.config.internals, -1, reason: 'the H7 sections override removed the templates');
    a.advance(300);
    b.advance(300);
    final sa = a.snapshot(), sb = b.snapshot();
    expect(sb.beds[1].dp, closeTo(sa.beds[1].dp, 1e-4 * sa.beds[1].dp), reason: "the holdup-factor lag restarts at its raw value");
    expect(sb.kpis.xD, closeTo(sa.kpis.xD, 1e-5));
    expect(sb.stages.hetp[18], closeTo(sa.stages.hetp[18], 1e-4));
  });
}
