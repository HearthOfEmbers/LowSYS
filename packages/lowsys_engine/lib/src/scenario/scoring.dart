import 'package:meta/meta.dart';

/// Weights of a guided scenario (ENGINE_API.md 11.4).
@immutable
class ScoringWeights {
  final double objectives, time, safety, quality;
  const ScoringWeights(
      {this.objectives = 0.6,
      this.time = 0.2,
      this.safety = 0.1,
      this.quality = 0.1});
}

/// Weights and constants of a drill.
@immutable
class DrillScoringWeights {
  final double category, location, time, safety;
  final double timeFull, timeZero, wrongPenalty;
  final double protectBonus, modeBonus;
  const DrillScoringWeights({
    this.category = 0.5,
    this.location = 0.2,
    this.time = 0.2,
    this.safety = 0.1,
    this.timeFull = 600,
    this.timeZero = 3600,
    this.wrongPenalty = 0.1,
    this.protectBonus = 0,
    this.modeBonus = 0,
  });
}

/// One diagnosis attempt of a drill.
@immutable
class DrillAttempt {
  final double time;
  final bool categoryOk, locationOk, modeOk;
  const DrillAttempt(
      {required this.time,
      required this.categoryOk,
      required this.locationOk,
      this.modeOk = false});
  bool get fullyCorrect => categoryOk && locationOk;
}

/// The terms of a score and the rounded result (0-100).
@immutable
class ScoreResult {
  /// Guided: O, T, S, Q. Drill: C, L, T, S (and B, P below).
  final double objectives, time, safety, quality;
  final double category, location, bonus, penalty, hints;
  final double raw;
  const ScoreResult({
    this.objectives = 0,
    this.time = 0,
    this.safety = 0,
    this.quality = 0,
    this.category = 0,
    this.location = 0,
    this.bonus = 0,
    this.penalty = 0,
    this.hints = 0,
    required this.raw,
  });

  int get score => (100 * raw.clamp(0.0, 1.0)).round();
}

/// The exact scoring arithmetic of ENGINE_API.md 11.4.
abstract final class Scoring {
  static double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

  static double _safety(double w, bool relief, double levelViolation) =>
      w * (1 - 0.5 * (relief ? 1 : 0) - 0.5 * (levelViolation > 60 ? 1 : 0));

  static ScoreResult guided({
    required ScoringWeights weights,
    required List<double> objectiveWeights,
    required List<bool> achieved,
    required double tEnd,
    required double parTime,
    required double timeLimit,
    required bool reliefLifted,
    required double levelViolationSeconds,
    required double qualityFraction,
    required double hintCost,
  }) {
    var w = 0.0, wa = 0.0;
    for (var i = 0; i < objectiveWeights.length; i++) {
      w += objectiveWeights[i];
      if (achieved[i]) wa += objectiveWeights[i];
    }
    final frac = w > 0 ? wa / w : 1.0;
    final o = weights.objectives * frac;
    final span = timeLimit - parTime;
    final tf = span > 0 ? _clamp01(1 - (tEnd - parTime) / span) : 1.0;
    final t = weights.time * frac * tf;
    final s = _safety(weights.safety, reliefLifted, levelViolationSeconds);
    final q = weights.quality * _clamp01(qualityFraction);
    return ScoreResult(
        objectives: o,
        time: t,
        safety: s,
        quality: q,
        hints: hintCost,
        raw: o + t + s + q - hintCost);
  }

  static ScoreResult drill({
    required DrillScoringWeights weights,
    required double t0,
    required List<DrillAttempt> attempts,
    required double? protectMetAt,
    required double? offSpecAt,
    required bool reliefLifted,
    required double levelViolationSeconds,
    required double hintCost,
    required bool hasProtect,
  }) {
    DrillAttempt? f;
    for (final a in attempts) {
      if (a.fullyCorrect) {
        f = a;
        break;
      }
    }
    f ??= attempts.isEmpty ? null : attempts.last;
    final wrong = attempts.where((a) => !a.fullyCorrect).length;
    final p = weights.wrongPenalty * wrong;
    final c = f != null && f.categoryOk ? weights.category : 0.0;
    final l = f != null && f.locationOk ? weights.location : 0.0;
    var t = 0.0;
    if (f != null && f.fullyCorrect) {
      final dt = (f.time - t0).clamp(0.0, double.infinity);
      final span = weights.timeZero - weights.timeFull;
      t = weights.time * _clamp01(1 - (dt - weights.timeFull) / span);
    }
    final s = _safety(weights.safety, reliefLifted, levelViolationSeconds);
    var b = 0.0;
    if (hasProtect && protectMetAt != null) {
      final end = [
        if (offSpecAt != null) offSpecAt,
        if (f != null) f.time,
      ].fold<double>(double.infinity, (m, v) => v < m ? v : m);
      if (protectMetAt >= t0 && protectMetAt < end) b += weights.protectBonus;
    }
    if (f != null && f.fullyCorrect && f.modeOk) b += weights.modeBonus;
    return ScoreResult(
        category: c,
        location: l,
        time: t,
        safety: s,
        bonus: b,
        penalty: p,
        hints: hintCost,
        raw: c + l + t + s + b - p - hintCost);
  }
}
