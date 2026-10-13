import 'dart:math' as math;
import 'dart:ui';


/// What a tap on the crude flowsheet hit.
sealed class CrudeHit {
  const CrudeHit();
}

class CrudeHitStage extends CrudeHit {
  final int stage; // 0 drum, 1..30, 31 sump
  const CrudeHitStage(this.stage);
}

class CrudeHitStripper extends CrudeHit {
  final int stripper;
  final bool bottom;
  const CrudeHitStripper(this.stripper, this.bottom);
}

class CrudeHitProduct extends CrudeHit {
  final int product; // 0 naphtha .. 4 residue
  const CrudeHitProduct(this.product);
}

class CrudeHitPumparound extends CrudeHit {
  const CrudeHitPumparound();
}

class CrudeHitOverflash extends CrudeHit {
  const CrudeHitOverflash();
}

class CrudeHitSteam extends CrudeHit {
  final int point; // 0 bottom, 1..3 strippers
  const CrudeHitSteam(this.point);
}

class CrudeHitFurnace extends CrudeHit {
  const CrudeHitFurnace();
}

/// Layout of the crude flowsheet (ENGINE_API.md 13.5) in a panel of [size]; shared by the painter and the tap test.
class CrudeGeometry {
  final Size size;
  CrudeGeometry(this.size);

  static const int nm = 30;
  static const List<int> drawStages = [8, 15, 21];
  static const List<int> returnStages = [7, 14, 20];
  static const int feedStage = 26, paDraw = 16, paReturn = 14;

  late final double shellL = size.width * 0.31, shellR = size.width * 0.55;
  late final double shellW = shellR - shellL;
  late final double yT0 = size.height * 0.20, yT1 = size.height * 0.80;
  late final double spacing = (yT1 - yT0) / nm;
  late final double sumpBot = size.height * 0.885;

  /// y of the middle of stage [j] (1..30).
  double stageY(int j) => yT0 + (j - 0.5) * spacing;

  late final Rect drum = Rect.fromLTWH(size.width * 0.60, size.height * 0.035, size.width * 0.20, size.height * 0.075);
  late final Offset condenser = Offset(size.width * 0.43, size.height * 0.075);
  late final double condR = math.min(size.width * 0.045, size.height * 0.03);

  late final double ssL = size.width * 0.68, ssR = size.width * 0.78;

  /// Stripper k: top stage rectangle and boot rectangle.
  Rect ssTop(int k) {
    final y = stageY(drawStages[k]) + spacing * 0.8;
    return Rect.fromLTRB(ssL, y, ssR, y + spacing * 2.2);
  }

  Rect ssBoot(int k) {
    final t = ssTop(k);
    return Rect.fromLTRB(ssL, t.bottom + spacing * 0.3, ssR, t.bottom + spacing * 2.8);
  }

  Rect get furnace => Rect.fromLTWH(size.width * 0.02, stageY(feedStage) - size.height * 0.035, size.width * 0.17, size.height * 0.07);
  late final double paX = size.width * 0.20;
  Offset get cooler => Offset(paX, (stageY(paDraw) + stageY(paReturn)) / 2);

  Offset steamPoint(int q) => q == 0
      ? Offset(shellL, stageY(30) + spacing * 0.2)
      : Offset((ssL + ssR) / 2, ssBoot(q - 1).bottom + 4);

  double productY(int p) => switch (p) {
        0 => drum.center.dy,
        4 => sumpBot - size.height * 0.02,
        _ => ssBoot(p - 1).center.dy,
      };

  CrudeHit? hit(Offset p) {
    if (drum.inflate(6).contains(p) || (p - condenser).distance < condR + 8) {
      return p.dx > size.width * 0.74 && p.dy > drum.top ? const CrudeHitProduct(0) : const CrudeHitStage(0);
    }
    for (var k = 0; k < 3; k++) {
      if (ssTop(k).inflate(4).contains(p)) return CrudeHitStripper(k, false);
      if (ssBoot(k).inflate(4).contains(p)) return CrudeHitStripper(k, true);
      if (p.dx > ssR && p.dx < size.width && (p.dy - productY(k + 1)).abs() < 14) return CrudeHitProduct(k + 1);
      if ((p - steamPoint(k + 1)).distance < 16) return CrudeHitSteam(k + 1);
    }
    if (furnace.inflate(6).contains(p) || (p.dx < shellL && p.dx > furnace.right && (p.dy - stageY(feedStage)).abs() < 8)) {
      return const CrudeHitFurnace();
    }
    if ((p.dx - paX).abs() < 14 && p.dy > stageY(paReturn) - 6 && p.dy < stageY(paDraw) + 6) return const CrudeHitPumparound();
    if (p.dx < shellL && p.dx > paX + 14 && ((p.dy - stageY(paDraw)).abs() < 8 || (p.dy - stageY(paReturn)).abs() < 8)) {
      return const CrudeHitPumparound();
    }
    if ((p - steamPoint(0)).distance < 16 && p.dx < shellL) return const CrudeHitSteam(0);
    if (p.dx > shellR && p.dx < ssL && p.dy > sumpBot - size.height * 0.04) return const CrudeHitProduct(4);
    if (p.dx >= shellL - 4 && p.dx <= shellR + 4) {
      if (p.dy > yT1 && p.dy <= sumpBot) return const CrudeHitStage(31);
      if (p.dy >= yT0 && p.dy <= yT1) {
        final j = ((p.dy - yT0) / spacing).floor() + 1;
        // the band between stages 25 and 26 is the overflash
        if ((p.dy - (yT0 + 25 * spacing)).abs() < spacing * 0.25 && p.dx > shellR - shellW * 0.25) return const CrudeHitOverflash();
        return CrudeHitStage(j.clamp(1, nm));
      }
    }
    return null;
  }
}
