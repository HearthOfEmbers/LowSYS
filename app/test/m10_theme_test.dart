// M10: VALIDATION U2 (contrast) and U3 (deuteranopia lightness of the alarm/ok pair) for every theme.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/theme/lowsys_theme.dart';
import 'package:lowsys_app/theme/themes/brass.dart' show brassParchment;
import 'package:lowsys_app/theme/themes/registry.dart';

double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// CIE L* of the colour as seen with deuteranopia (Machado et al. 2009, severity 1.0, linear RGB).
double deuteranopiaLstar(Color c) {
  final r = _lin(c.r), g = _lin(c.g), b = _lin(c.b);
  final r2 = 0.367322 * r + 0.860646 * g - 0.227968 * b;
  final g2 = 0.280085 * r + 0.672501 * g + 0.047413 * b;
  final b2 = -0.011820 * r + 0.042940 * g + 0.968881 * b;
  final y = (0.2126 * r2 + 0.7152 * g2 + 0.0722 * b2).clamp(0.0, 1.0);
  return y > 216 / 24389 ? 116 * math.pow(y, 1 / 3).toDouble() - 16 : 24389 / 27 * y;
}

void main() {
  for (final t in kThemes) {
    final p = t.palette;
    test('${t.id}: U2 contrast', () {
      expect(contrast(p.ink, p.bg), greaterThanOrEqualTo(7), reason: 'ink/bg');
      expect(contrast(p.inkMuted, p.bg), greaterThanOrEqualTo(4.5), reason: 'inkMuted/bg');
      for (final e in {'accent': p.accent, 'warn': p.warn, 'ok': p.ok, if (t.id != 'phosphor') 'alarm': p.alarm}.entries) {
        expect(contrast(e.value, p.bg), greaterThanOrEqualTo(3), reason: '${e.key}/bg');
      }
      for (var i = 0; i < p.series.length; i++) {
        expect(contrast(p.series[i], p.bg), greaterThanOrEqualTo(3), reason: 'series $i/bg');
      }
      if (t.id == 'brass') {
        expect(contrast(p.qLine, brassParchment), greaterThanOrEqualTo(3));
      }
    });
    test('${t.id}: U3 alarm and ok differ in lightness under deuteranopia', () {
      final d = (deuteranopiaLstar(p.alarm) - deuteranopiaLstar(p.ok)).abs();
      // phosphor shows alarms as inverse video with a text label (VALIDATION U3: shape/label pairing)
      if (t.id == 'phosphor') return;
      expect(d, greaterThanOrEqualTo(15), reason: '${t.id} L* difference $d');
    });
  }
}
