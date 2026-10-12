import 'package:meta/meta.dart';

import '../core/ids.dart';
import '../core/quantity.dart';
import '../snapshot/sim_snapshot.dart';

/// What the math overlay explains (ENGINE_API.md 8.1).
sealed class ExplainTarget {
  const ExplainTarget();
}

/// A tray (1..N), the drum (0) or the sump (N + 1).
class ExplainStage extends ExplainTarget {
  final int stage;
  final ComponentId? focusComponent;
  const ExplainStage(this.stage, {this.focusComponent});
}

class ExplainStream extends ExplainTarget {
  final StreamId stream;
  const ExplainStream(this.stream);
}

class ExplainCondenser extends ExplainTarget {
  const ExplainCondenser();
}

class ExplainReboiler extends ExplainTarget {
  const ExplainReboiler();
}

class ExplainFeed extends ExplainTarget {
  final int feedIndex;
  const ExplainFeed([this.feedIndex = 0]);
}

class ExplainLoop extends ExplainTarget {
  final LoopTag tag;
  const ExplainLoop(this.tag);
}

/// A transmitter or analyser (PHYSICS.md 10.5): the pipeline with the current values.
class ExplainInstrument extends ExplainTarget {
  final String tag;
  const ExplainInstrument(this.tag);
}

/// A control valve (PHYSICS.md 10.3).
class ExplainValve extends ExplainTarget {
  final String valveId;
  const ExplainValve(this.valveId);
}

/// A cross-check (PHYSICS.md 14.6), e.g. `C1`, `C4:FV-102`.
class ExplainCheck extends ExplainTarget {
  final String checkId;
  const ExplainCheck(this.checkId);
}

enum McCabeElement { opLine, qLine, rmin, equilibrium }

class ExplainMcCabe extends ExplainTarget {
  final McCabeElement element;
  const ExplainMcCabe(this.element);
}

@immutable
class EquationLine {
  /// PHYSICS.md 15 id, e.g. `eq.bennett`.
  final String id;

  /// e.g. `PHYSICS.md (5.2)`.
  final String physicsRef;
  final String texSymbolic;
  final String texSubstituted;

  /// SI value; equals the corresponding snapshot value of the same state (VALIDATION.md VC-21).
  final double value;
  final Quantity quantity;
  final String? note;
  const EquationLine({
    required this.id,
    required this.physicsRef,
    required this.texSymbolic,
    required this.texSubstituted,
    required this.value,
    this.quantity = Quantity.dimensionless,
    this.note,
  });
}

@immutable
class EquationGroup {
  final String title;
  final List<EquationLine> lines;
  const EquationGroup(this.title, this.lines);
}

@immutable
class ExplainResult {
  final String title;
  final List<EquationGroup> groups;

  /// Simplification notes (PHYSICS.md 16) relevant here.
  final List<String> notes;

  /// Sim time of the state explained.
  final double time;
  const ExplainResult(
      {required this.title,
      required this.groups,
      required this.notes,
      required this.time});
}
