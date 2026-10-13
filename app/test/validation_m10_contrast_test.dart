// M10 acceptance (validator, read-only check of app/lib/theme): VALIDATION.md §U2 contrast and §U3 colour vision, computed
// independently of m10_theme_test.dart. U2 is checked against the backgrounds the painters actually draw on: the McCabe-
// Thiele and T-x-y plots fill bgAlt at 55 % over the scaffold bg (mccabe_painter.dart:51, txy_painter.dart:73); only the
// crude Products charts draw the Brass parchment inset (crude_products_panel.dart:136). U3 uses two simulations: Machado
// et al. 2009 (as the coder) and Vienot, Brettel & Mollon 1999 (LMS projection), independent of each other.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/theme/lowsys_theme.dart';
import 'package:lowsys_app/theme/themes/brass.dart' show brassParchment;
import 'package:lowsys_app/theme/themes/registry.dart';

double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.x relative luminance of an opaque colour.
double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// [fg] (alpha honoured) composited over the opaque [bg].
Color _over(Color fg, Color bg) => Color.from(
    alpha: 1, red: bg.r + (fg.r - bg.r) * fg.a, green: bg.g + (fg.g - bg.g) * fg.a, blue: bg.b + (fg.b - bg.b) * fg.a);

double _lstar(double y) => y > 216 / 24389 ? 116 * math.pow(y, 1 / 3).toDouble() - 16 : 24389 / 27 * y;

/// L* under deuteranopia, Machado, Oliveira & Fernandes 2009, severity 1.
double _lMachado(Color c) {
  final r = _lin(c.r), g = _lin(c.g), b = _lin(c.b);
  final r2 = 0.367322 * r + 0.860646 * g - 0.227968 * b;
  final g2 = 0.280085 * r + 0.672501 * g + 0.047413 * b;
  final b2 = -0.011820 * r + 0.042940 * g + 0.968881 * b;
  return _lstar((0.2126 * r2 + 0.7152 * g2 + 0.0722 * b2).clamp(0.0, 1.0));
}

/// L* under deuteranopia, Vienot, Brettel & Mollon 1999 (M replaced from L and S, linear RGB).
double _lVienot(Color c) {
  final r = _lin(c.r), g = _lin(c.g), b = _lin(c.b);
  final l = 17.8824 * r + 43.5161 * g + 4.11935 * b;
  final s = 0.0299566 * r + 0.184309 * g + 1.46709 * b;
  final m = 0.494207 * l + 1.24827 * s;
  final r2 = 0.0809444479 * l - 0.130504409 * m + 0.116721066 * s;
  final g2 = -0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s;
  final b2 = -0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s;
  return _lstar((0.2126 * r2 + 0.7152 * g2 + 0.0722 * b2).clamp(0.0, 1.0));
}

String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

void main() {
  for (final t in kThemes) {
    final p = t.palette;
    // plot fill of the McCabe-Thiele and T-x-y painters over the scaffold
    final chartBg = _over(p.bgAlt.withValues(alpha: 0.55), p.bg);

    test('${t.id}: U2 text and state colours on bg (ink 7, inkMuted 4.5, accent / warn / ok / alarm 3)', () {
      final rows = <String>[];
      final fails = <String>[];
      void chk(String name, Color fg, Color bg, double min) {
        final r = _ratio(_over(fg, bg), bg);
        rows.add('$name ${r.toStringAsFixed(2)}');
        if (r < min) fails.add('$name ${_hex(fg)} on ${_hex(bg)} = ${r.toStringAsFixed(2)} < $min');
      }

      chk('ink', p.ink, p.bg, 7);
      chk('inkMuted', p.inkMuted, p.bg, 4.5);
      chk('accent', p.accent, p.bg, 3);
      chk('warn', p.warn, p.bg, 3);
      chk('ok', p.ok, p.bg, 3);
      chk('ok/surface', p.ok, p.surface, 3);
      if (t.id != 'phosphor') chk('alarm', p.alarm, p.bg, 3); // phosphor alarm is inverse video (exempt)
      for (var i = 0; i < p.series.length; i++) {
        chk('series$i', p.series[i], chartBg, 3);
      }
      // ignore: avoid_print
      print('U2 ${t.id}: ${rows.join(', ')}; inkFaint/bg (exempt, used for KPI units) '
          '${_ratio(_over(p.inkFaint, p.bg), p.bg).toStringAsFixed(2)}');
      expect(fails, isEmpty);
    });

    test('${t.id}: U2 chart line colours (eqCurve, opLine, opLineCmo, qLine, stepLine, pseudoEq, marker) >= 3:1 on the '
        'background the McCabe-Thiele / T-x-y painters draw on', () {
      final lines = {
        'eqCurve': p.eqCurve,
        'opLine': p.opLine,
        'opLineCmo': p.opLineCmo,
        'qLine': p.qLine,
        'stepLine': p.stepLine,
        'pseudoEq': p.pseudoEq,
        'marker': p.marker,
      };
      final rows = <String>[], fails = <String>[];
      lines.forEach((name, c) {
        final r = _ratio(_over(c, chartBg), chartBg);
        rows.add('$name ${r.toStringAsFixed(2)}');
        if (r < 3) fails.add('$name ${_hex(c)} on ${_hex(chartBg)} = ${r.toStringAsFixed(2)}');
      });
      if (t.id == 'brass') {
        // what SCOPE.md T-4 intends ("charts on a parchment inset"): the same tokens on parchment
        final onParch = [
          for (final e in lines.entries) '${e.key} ${_ratio(e.value, brassParchment).toStringAsFixed(2)}'
        ];
        // ignore: avoid_print
        print('U2 brass chart lines on parchment ${_hex(brassParchment)} (crude Products only): ${onParch.join(', ')}');
      }
      // ignore: avoid_print
      print('U2 ${t.id} chart lines on ${_hex(chartBg)}: ${rows.join(', ')}');
      expect(fails, isEmpty, reason: '${t.id}: chart lines below 3:1 on the plot fill: $fails');
    });

    test('${t.id}: U3 alarm vs ok lightness under deuteranopia >= 15 L* (two simulations)', () {
      final dm = (_lMachado(p.alarm) - _lMachado(p.ok)).abs();
      final dv = (_lVienot(p.alarm) - _lVienot(p.ok)).abs();
      // ignore: avoid_print
      print('U3 ${t.id}: ok ${_hex(p.ok)} alarm ${_hex(p.alarm)}: dL* Machado ${dm.toStringAsFixed(1)}, '
          'Vienot ${dv.toStringAsFixed(1)}; ok vs warn Machado ${(_lMachado(p.warn) - _lMachado(p.ok)).abs().toStringAsFixed(1)}');
      if (t.id == 'phosphor') return; // alarm = inverse video with a text label (U3 shape/label pairing)
      expect(dm, greaterThanOrEqualTo(15));
      expect(dv, greaterThanOrEqualTo(15));
    });
  }

  test('M10 ok colours are the values DEVIATIONS "M10 (coder)" item 5 states', () {
    final ok = {for (final t in kThemes) t.id: _hex(t.palette.ok)};
    expect(ok['blueprint'], '9DE8BA');
    expect(ok['controlRoom'], '217E38');
    expect(ok['paper'], '1E5020');
    expect(ok['brass'], '8DB255');
  });
}
