import 'package:meta/meta.dart';

import '../core/rng.dart';
import 'scenario_def.dart';

/// The learner's diagnosis in a drill.
@immutable
class Diagnosis {
  final String category, location;
  final String? mode;
  const Diagnosis({required this.category, required this.location, this.mode});
}

@immutable
class DrillResult {
  final bool fullyCorrect, categoryOk, locationOk, modeOk;
  final int attemptsLeft;
  const DrillResult(
      {required this.fullyCorrect,
      required this.categoryOk,
      required this.locationOk,
      required this.modeOk,
      required this.attemptsLeft});
}

@immutable
class AnswerResult {
  final String objectiveId;
  final bool correct;
  final int attemptsLeft;
  const AnswerResult(this.objectiveId, this.correct, this.attemptsLeft);
}

/// The reproducible drill draw (ENGINE_API.md 11.2): four uniforms from the stream `drill`, seeded with the
/// attempt seed, are always consumed in the same order.
@immutable
class DrillDraw {
  final CandidateDef candidate;
  final String candidateId;

  /// Severity s = lo + u1 (hi - lo).
  final double severity;

  /// Onset t0 (s of scenario time), a multiple of dt inside the onset window.
  final double onset;

  /// -1 if u3 < 0.5, else +1 (used when the fault sign is "random").
  final double sign;
  const DrillDraw._(
      this.candidate, this.candidateId, this.severity, this.onset, this.sign);

  static DrillDraw draw(ScenarioDef def, int seed, {double dt = 0.5}) {
    final rng = Rng.stream(seed, 'drill');
    final u0 = rng.uniform(),
        u1 = rng.uniform(),
        u2 = rng.uniform(),
        u3 = rng.uniform();
    var total = 0.0;
    for (final c in def.candidates) {
      total += c.weight;
    }
    var acc = 0.0;
    var pick = def.candidates.first;
    for (final c in def.candidates) {
      acc += c.weight;
      if (c.weight > 0 && u0 * total < acc) {
        pick = c;
        break;
      }
    }
    final sev = pick.severityLo + u1 * (pick.severityHi - pick.severityLo);
    final a = def.onsetWindow[0], b = def.onsetWindow[1];
    final onset = dt * ((a + u2 * (b - a)) / dt).floor();
    return DrillDraw._(pick, pick.id, sev, onset, u3 < 0.5 ? -1.0 : 1.0);
  }
}
