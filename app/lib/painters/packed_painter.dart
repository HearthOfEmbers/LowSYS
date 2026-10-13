import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../theme/lowsys_theme.dart';
import 'column_geometry.dart';

/// A packed bed in the stage chain, as the painters need it (ENGINE_API.md 13.5).
class BedSpec {
  final int first, last;
  final String packingId;
  const BedSpec(this.first, this.last, this.packingId);

  /// Beds of a snapshot, top to bottom.
  static List<BedSpec> of(SimSnapshot s) => [for (final b in s.beds) BedSpec(b.firstStage, b.lastStage, b.packingId)];

  /// Stable key of a bed list (the static layer repaints when it changes).
  static String key(List<BedSpec> beds) => beds.map((b) => '${b.first}-${b.last}:${b.packingId}').join(',');

  static List<BedSpec> parse(String key) {
    if (key.isEmpty) return const [];
    return [
      for (final part in key.split(','))
        BedSpec(int.parse(part.split(':')[0].split('-')[0]), int.parse(part.split(':')[0].split('-')[1]), part.split(':')[1])
    ];
  }

  bool get structured => PackingData.byId(packingId).structured;
}

double _hash(double v) {
  final x = math.sin(v * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

/// Top and bottom y of the band of stage [j] (a segment owns the band above its deck line, as a tray does).
({double top, double bottom}) segmentBand(ColumnGeometry g, int j) => (top: g.deckY(j) - g.spacing, bottom: g.deckY(j));

/// Static art of the packed beds (packing texture, distributors above each bed, support grids below), drawn once into
/// the vessel layer. Random packings are ring glyphs, structured packings corrugated sheets (corrugation angle
/// alternating from sheet to sheet).
void paintPackedBedsStatic(Canvas canvas, ColumnGeometry g, LowsysTheme theme, List<BedSpec> beds) {
  final p = theme.palette;
  for (final bed in beds) {
    final top = segmentBand(g, bed.first).top, bottom = segmentBand(g, bed.last).bottom;
    final rect = Rect.fromLTRB(g.shellL + 1.5, top + 3, g.shellR - 1.5, bottom - 1);
    final pk = PackingData.byId(bed.packingId);
    canvas.save();
    canvas.clipRect(rect);
    final line = Paint()
      ..color = p.steel.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    if (pk.structured) {
      // corrugated sheets: vertical sheets, each a zigzag; neighbouring sheets zig the other way
      final pitch = pk.a > 400 ? 5.0 : 9.0;
      final per = pitch * 2.6;
      var k = 0;
      for (var x = rect.left + pitch / 2; x < rect.right; x += pitch, k++) {
        final path = Path()..moveTo(x, rect.top);
        var y = rect.top;
        var dir = k.isEven ? 1.0 : -1.0;
        while (y < rect.bottom) {
          y += per / 2;
          path.lineTo(x + dir * pitch * 0.38, math.min(y, rect.bottom));
          dir = -dir;
        }
        canvas.drawPath(path, line);
      }
    } else {
      final cell = pk.a > 150 ? 7.0 : 11.0;
      final cols = (rect.width / cell).floor(), rows = (rect.height / cell).floor();
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final u1 = _hash(r * 7.3 + c * 3.1 + bed.first), u2 = _hash(r * 2.9 + c * 5.7 + 1.0 + bed.first);
          final o = Offset(rect.left + (c + 0.3 + 0.4 * u1) * cell, rect.top + (r + 0.3 + 0.4 * u2) * cell);
          final ang = u1 * math.pi;
          canvas.save();
          canvas.translate(o.dx, o.dy);
          canvas.rotate(ang);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: cell * 0.85, height: cell * (0.35 + 0.3 * u2)), line);
          canvas.restore();
        }
      }
    }
    canvas.restore();
    // distributor trough above the bed: a line with spray holes (it also redistributes the liquid of the bed above)
    final dy = top + 1.5;
    final trough = Paint()
      ..color = p.steel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(g.shellL, dy), Offset(g.shellR, dy), trough);
    for (var x = g.shellL + 8; x < g.shellR - 4; x += 10) {
      canvas.drawLine(Offset(x, dy), Offset(x, dy + 2.6), trough);
    }
    // support grid below the bed
    final sup = Paint()
      ..color = p.steel.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(g.shellL, bottom), Offset(g.shellR, bottom), sup);
    canvas.drawLine(Offset(g.shellL, bottom + 2.4), Offset(g.shellR, bottom + 2.4), Paint()
      ..color = p.steel.withValues(alpha: 0.5)
      ..strokeWidth = 0.8);
  }
}

/// Live layer of the packed beds (ENGINE_API.md 13.5): wetted-fraction shading with dry patches below 0.7, liquid
/// rivulets (count with the segment liquid load, width with the holdup), vapour rising through the voids at a speed
/// with the vapour rate, HETP ticks on the bed edge (model view only) and the flooding overlay. The F21 side bias is
/// drawn only from `PackedBedSnapshot.maldistribution`, which is NaN in drills and plant views.
void paintPackedLive(
  Canvas canvas,
  ColumnGeometry g,
  SimSnapshot s,
  LowsysTheme theme,
  double flowPhase,
  double bubblePhase,
  double time,
  Color Function(int stage) compColor,
) {
  if (s.beds.isEmpty) return;
  final p = theme.palette;
  final st = s.stages;
  final plant = s.view.isPlant;
  final liquid = <double>[
    for (final b in s.beds)
      for (var j = b.firstStage; j <= b.lastStage; j++) st.liquidDown[j]
  ].where((v) => v.isFinite && v > 0).toList()
    ..sort();
  final lNom = liquid.isEmpty ? 1.0 : liquid[liquid.length ~/ 2];
  final vNom = math.max(
      1e-9, (s.kpis.boilup.isFinite ? s.kpis.boilup : (st.vaporUp[st.n - 1].isFinite ? st.vaporUp[st.n - 1] : 1.0)));
  final bubble = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.9
    ..color = p.vapor;
  for (final bed in s.beds) {
    final bias = bed.maldistribution.isFinite ? bed.maldistribution : 0.0;
    var minHetp = double.infinity;
    for (var j = bed.firstStage; j <= bed.lastStage; j++) {
      if (st.hetp[j].isFinite) minHetp = math.min(minHetp, st.hetp[j]);
    }
    for (var j = bed.firstStage; j <= bed.lastStage; j++) {
      final band = segmentBand(g, j);
      final r = Rect.fromLTRB(g.shellL + 1.5, band.top + (j == bed.firstStage ? 3 : 0), g.shellR - 1.5, band.bottom - (j == bed.lastStage ? 1 : 0));
      final col = compColor(j);
      final wet = st.wetFrac[j].isFinite ? st.wetFrac[j].clamp(0.0, 1.0) : 1.0;
      final hL = st.packHoldup[j].isFinite ? st.packHoldup[j] : 0.04;
      final flux = st.liquidDown[j].isFinite ? st.liquidDown[j] / lNom : 1.0;
      // wetted columns: the fraction a_w/a of the strips carries a liquid film, the rest is dry packing
      const strips = 14;
      final sw = r.width / strips;
      final filmAlpha = (0.10 + 3.0 * hL).clamp(0.10, 0.42);
      for (var k = 0; k < strips; k++) {
        final wetted = _hash(j * 3.7 + k * 1.9) < (wet >= 0.7 ? 1.0 - (1.0 - wet) * 0.6 : wet * 0.85);
        if (!wetted) continue;
        canvas.drawRect(Rect.fromLTWH(r.left + k * sw, r.top, sw, r.height), Paint()..color = col.withValues(alpha: filmAlpha));
      }
      // rivulets
      final n = (3 + 13 * flux.clamp(0.1, 1.6)).round();
      final width = (0.8 + 22.0 * hL).clamp(0.8, 4.0);
      final rv = Paint()
        ..color = col.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < n; k++) {
        var u = _hash(j * 5.3 + k * 2.17 + 0.5);
        // F21: rivulets crowd to one side in proportion to f
        if (bias > 0) u = math.pow(u, 1.0 + 3.0 * bias).toDouble();
        final x0 = r.left + 3 + u * (r.width - 6);
        final sway = 3.0 * (_hash(j * 1.7 + k * 4.1) - 0.5);
        final path = Path()..moveTo(x0, r.top);
        const steps = 6;
        for (var q = 1; q <= steps; q++) {
          final y = r.top + r.height * q / steps;
          path.lineTo(x0 + sway * math.sin(q * 1.3 + k + time * 0.4), y);
        }
        // dashes slide down with the flow phase
        final seg = r.height / 5;
        final off = (flowPhase * 10) % (seg * 1.6);
        for (final m in path.computeMetrics()) {
          var d = -off;
          while (d < m.length) {
            final a = math.max(0.0, d), b = math.min(m.length, d + seg);
            if (b > a) canvas.drawPath(m.extractPath(a, b), rv);
            d += seg * 1.6;
          }
        }
      }
      // vapour through the voids
      final vJ = plant ? vNom : st.vaporUp[j + 1];
      final count = (4 * (vJ.isFinite ? (vJ / vNom).clamp(0.0, 1.6) : 1.0)).round();
      final pts = <Offset>[];
      for (var i = 0; i < count; i++) {
        final u1 = _hash(j * 7.31 + i * 1.77), u2 = _hash(j * 3.17 + i * 5.13 + 9), u3 = _hash(j * 1.91 + i * 2.71 + 4);
        final ph = (u3 + bubblePhase * (0.7 + 0.6 * u2)) % 1.0;
        pts.add(Offset(r.left + 4 + u1 * (r.width - 8) + math.sin(ph * 12.5 + u2 * 6) * 1.4, r.bottom - ph * r.height));
      }
      if (pts.isNotEmpty) canvas.drawPoints(PointMode.points, pts, bubble..strokeWidth = 2.2..strokeCap = StrokeCap.round);
      bubble.strokeWidth = 0.9;
      // HETP tick on the bed edge: longer where the segment needs more height per stage (model view)
      if (st.hetp[j].isFinite && minHetp.isFinite && minHetp > 0) {
        final len = (4 + 14 * (st.hetp[j] / minHetp - 1)).clamp(4.0, 18.0);
        canvas.drawLine(Offset(g.shellL - 4, band.bottom - 0.5), Offset(g.shellL - 4 - len, band.bottom - 0.5), Paint()
          ..color = p.inkMuted
          ..strokeWidth = 1.0);
      }
      // flooding overlay: liquid pools from the top of the segment and spreads upward
      final phi = st.packFlood[j];
      if (phi.isFinite && phi >= 1.0) {
        final up = phi >= 1.1 ? g.spacing * 0.5 : 0.0;
        final pool = Rect.fromLTRB(r.left, r.top - up, r.right, r.bottom);
        canvas.drawRect(pool, Paint()..color = p.alarm.withValues(alpha: 0.22));
        final hp = Paint()
          ..color = p.alarm.withValues(alpha: 0.8)
          ..strokeWidth = 0.9;
        canvas.save();
        canvas.clipRect(pool);
        for (var x = -pool.height; x < pool.width; x += 5) {
          canvas.drawLine(Offset(pool.left + x, pool.bottom), Offset(pool.left + x + pool.height, pool.top), hp);
        }
        canvas.restore();
        canvas.drawLine(pool.topLeft, pool.topRight, Paint()
          ..color = p.alarm
          ..strokeWidth = 1.6);
      }
    }
  }
}
