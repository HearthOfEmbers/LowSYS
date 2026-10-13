// M6 content: every new JSON validates (VC-26.1), F17/F18 need a thermosyphon, the new vocabulary is accepted.
import 'dart:convert';

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final id in ['G14_thermosyphon', 'H1_creeping_dp', 'H2_pressure', 'H3_lost_separation', 'H4_reboiler', 'H5_bottoms_swings']) {
    test('$id validates', () {
      expect(Scenarios.allIds, contains(id));
      expect(Scenarios.byId(id).validate(), isEmpty, reason: id);
    });
  }

  test('F17/F18 in a drill without a thermosyphon is rejected', () {
    final h5 = jsonDecode(Scenarios.jsonOf('H5_bottoms_swings')) as Map<String, Object?>;
    final copy = jsonDecode(jsonEncode(h5)) as Map<String, Object?>;
    ((copy['levers'] as Map)['set'] as Map).remove('reboilerType');
    expect(ScenarioDef.fromJson(copy).validate(), isNotEmpty);
  });

  test('a diagnosis answer outside the offered vocabulary is rejected', () {
    final h5 = jsonDecode(Scenarios.jsonOf('H5_bottoms_swings')) as Map<String, Object?>;
    final copy = jsonDecode(jsonEncode(h5)) as Map<String, Object?>;
    (((copy['candidates'] as List)[1] as Map)['answer'] as Map)['location'] = 'nowhere';
    expect(ScenarioDef.fromJson(copy).validate(), isNotEmpty);
  });

  test('injecting F17 into a kettle column throws', () {
    final sim = Simulator(Presets.byId('bt').copyWith(tier: ThermoTier.t2), warmStart: false);
    expect(
        () => sim.faults.inject(const FaultSpec(
            type: FaultType.tsInletRestriction,
            location: FaultLocation.equipment('reboiler'),
            severity: 0.5,
            ramp: 1800)),
        throwsA(isA<ConfigException>()));
  });
}
