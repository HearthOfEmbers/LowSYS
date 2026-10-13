// VALIDATION U2 (contrast, every theme) and U4 (golden images of the column and McCabe-Thiele painters, per
// theme, on the B-T steady state). Regenerate with: flutter test --update-goldens test/m5_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_app/theme/themes/blueprint.dart';
import 'package:lowsys_app/theme/themes/control_room.dart';
import 'package:lowsys_app/theme/themes/paper.dart';
import 'package:lowsys_app/widgets/column_view.dart';

import 'shot_helpers.dart';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double _cr(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(loadFonts);

  group('U2 contrast', () {
    for (final t in [blueprintTheme, controlRoomTheme, paperTheme]) {
      test('${t.name}: ink 7:1, inkMuted 4.5:1, accents and chart lines 3:1', () {
        final p = t.palette;
        expect(_cr(p.ink, p.bg), greaterThanOrEqualTo(7), reason: 'ink/bg');
        expect(_cr(p.inkMuted, p.bg), greaterThanOrEqualTo(4.5), reason: 'inkMuted/bg');
        final isPhosphorLike = t.id == 'controlRoom';
        final named = <String, Color>{
          'accent': p.accent,
          'ok': p.ok,
          'warn': p.warn,
          'eqCurve': p.eqCurve,
          'opLine': p.opLine,
          'qLine': p.qLine,
          'stepLine': p.stepLine,
          if (!isPhosphorLike) 'alarm': p.alarm,
        };
        for (final e in named.entries) {
          expect(_cr(e.value, p.bg), greaterThanOrEqualTo(3), reason: '${e.key}/bg');
        }
        for (var i = 0; i < p.series.length; i++) {
          expect(_cr(p.series[i], p.bg), greaterThanOrEqualTo(3), reason: 'series $i/bg');
        }
      });
    }

    test('Paper numbers quoted by SCOPE.md 7.2: warn 3.43, series lowest 4.45 on bg, info 5.34 on bg', () {
      final p = paperTheme.palette;
      expect(_cr(p.warn, p.bg), closeTo(3.43, 0.05));
      expect(_cr(p.series[4], p.bg), closeTo(4.45, 0.05));
      expect(_cr(p.info, p.bg), closeTo(5.34, 0.05));
      expect(_cr(p.series[4], p.surface), closeTo(4.72, 0.05));
      // the highlighter is only ever a fill behind ink
      expect(_cr(p.ink, p.selection), greaterThanOrEqualTo(7));
    });
  });

  group('U4 goldens', () {
    for (final id in ['blueprint', 'controlRoom', 'paper']) {
      testWidgets('column and McCabe-Thiele painters, $id, B-T steady state', (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final sim = SimController();
        await tester.pumpWidget(LowsysApp(controller: sim));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        await frames(tester, 20);
        expect(sim.loaded, isTrue);
        await sim.setTheme(id);
        sim.diagramTab.value = 0;
        await frames(tester, 20);
        // the column painter and the McCabe-Thiele painter are both on the screen; one image per theme
        expect(find.byType(ColumnView), findsOneWidget);
        expect(find.byType(McCabeChart), findsOneWidget);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${id}_column_mccabe.png'));
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
