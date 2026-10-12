import 'dart:math' as math;
import 'dart:ui';

/// Layout of the column drawing inside a panel of [size] for [n] trays. Shared by the painters and
/// the tap hit-test so they cannot disagree.
class ColumnGeometry {
  final Size size;
  final int n;
  final int feedStage;

  late final double shellL = size.width * 0.20;
  late final double shellR = size.width * 0.60;
  late final double cx = (shellL + shellR) / 2;
  late final double shellW = shellR - shellL;

  /// Top of the tray region (first vapour space) and bottom of the last tray.
  late final double yT0 = size.height * 0.215;
  late final double yT1 = size.height * 0.675;

  /// Sump region.
  late final double sumpTop = yT1;
  late final double sumpBot = size.height * 0.83;
  late final double headTop = yT0 - size.height * 0.05;
  late final double headBot = sumpBot + size.height * 0.045;

  late final double spacing = (yT1 - yT0) / (n + 0.6);
  late final double dcW = shellW * 0.17;

  ColumnGeometry(this.size, this.n, this.feedStage);

  /// y of the deck of tray [j] (1..n).
  double deckY(int j) => yT0 + spacing * 0.6 + (j - 1) * spacing + spacing * 0.9;

  /// True when the downcomer of tray [j] is on the right.
  bool dcRight(int j) => j.isOdd;

  /// Horizontal extent of the deck of tray [j] (from wall to weir).
  (double, double) deckX(int j) => dcRight(j) ? (shellL, shellR - dcW) : (shellL + dcW, shellR);

  // overhead equipment
  late final Offset condCenter = Offset(size.width * 0.80, size.height * 0.075);
  late final double condR = math.min(size.width * 0.075, size.height * 0.032);
  late final Rect drum = Rect.fromCenter(
    center: Offset(size.width * 0.80, size.height * 0.148),
    width: size.width * 0.30,
    height: math.min(size.height * 0.058, size.width * 0.15),
  );

  // reboiler
  late final Offset reboilerCenter = Offset(size.width * 0.80, size.height * 0.765);
  late final double reboilerR = math.min(size.width * 0.085, size.height * 0.04);

  /// Stage under a tap at [p]: 0 drum, 1..n tray, n+1 sump, or null.
  int? hitTest(Offset p) {
    if (drum.inflate(6).contains(p)) return 0;
    if (p.dx < shellL - 14 || p.dx > shellR + 14) return null;
    if (p.dy >= sumpTop && p.dy <= headBot) return n + 1;
    if (p.dy < yT0 || p.dy > yT1) return null;
    // tray j owns the band (deck_{j-1}, deck_j]
    final j = ((p.dy - (yT0 + spacing * 0.6 + spacing * 0.9 - spacing)) / spacing).ceil().clamp(1, n);
    return j;
  }

  /// Band covered by tray j for the selection highlight.
  Rect band(int j) => Rect.fromLTRB(shellL - 4, deckY(j) - spacing, shellR + 4, deckY(j) + 2);
}
