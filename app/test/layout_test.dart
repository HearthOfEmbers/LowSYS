
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';

import 'shot_helpers.dart';

void main() {
  setUpAll(loadFonts);

  final sizes = <String, Size>{
    'portrait_360x800': const Size(360, 800),
    'landscape_800x360': const Size(800, 360),
    'medium_768x1024': const Size(768, 1024),
    'desktop_1440x900': const Size(1440, 900),
  };

  for (final e in sizes.entries) {
    testWidgets('no overflow and reachable levers at ${e.key}', (tester) async {
      tester.view.physicalSize = e.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d, forceReport: true);
      final key = GlobalKey();
      final sim = SimController();
      await tester.pumpWidget(RepaintBoundary(key: key, child: LowsysApp(controller: sim)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await frames(tester, 20);
      expect(sim.loaded, isTrue);
      await snap(tester, key, '${e.key}_steady');

      // +10 % reflux at 100x, then look at the transient
      await sim.setLever('refluxFlow', 110 / 3.6);
      sim.setSpeed(100);
      await frames(tester, 240);
      expect(sim.snapshot.value!.time, greaterThan(100));
      sim.selectStage(7);
      await frames(tester, 3);
      await snap(tester, key, '${e.key}_transient_tray7');
      expect(tester.takeException(), isNull);

      // text must be at least 12 sp
      final texts = tester.widgetList<Text>(find.byType(Text));
      for (final t in texts) {
        final size = t.style?.fontSize;
        if (size != null) expect(size, greaterThanOrEqualTo(12), reason: 'text "${t.data}"');
      }
      // dispose the ticker/controller cleanly
      await tester.pumpWidget(const SizedBox());
    });
  }
}
