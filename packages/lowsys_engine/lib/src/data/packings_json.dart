import '../core/ids.dart';

/// One packing of PHYSICS.md 6.2 (representative values quoted from memory of Kister's tables; OPEN_ITEMS.md).
class PackingData {
  final String id, label;

  /// Specific area a (m2/m3), void fraction, packing factor F_p (1/ft), critical surface tension sigma_c (N/m),
  /// catalogue HETP at the design load (m), solid mass per m3 of bed (kg/m3, the metal heat capacity of (4.6)).
  final double a, eps, fp, sigmaC, hetpRef, rhoBed;

  /// True for structured packings (corrugated sheets), false for random packings (rings).
  final bool structured;
  const PackingData(this.id, this.label, this.a, this.eps, this.fp, this.sigmaC, this.hetpRef, this.rhoBed,
      {this.structured = false});

  static const List<PackingData> all = [
    PackingData('pall25m', '25 mm metal Pall rings', 205, 0.94, 56, 0.075, 0.46, 7900 * 0.06),
    PackingData('pall50m', '50 mm metal Pall rings', 105, 0.96, 27, 0.075, 0.91, 7900 * 0.04),
    PackingData('raschig50c', '50 mm ceramic Raschig rings', 92, 0.74, 65, 0.061, 0.91, 2300 * 0.26),
    PackingData('struct250', 'Structured 250 m2/m3 (250Y class)', 250, 0.98, 20, 0.075, 0.50, 7900 * 0.02,
        structured: true),
    PackingData('struct500', 'Structured 500 m2/m3 (500Y class)', 500, 0.975, 34, 0.075, 0.30, 7900 * 0.025,
        structured: true),
  ];

  static PackingData? tryById(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static PackingData byId(String id) =>
      tryById(id) ?? (throw ConfigException('Unknown packing "$id"'));
}
