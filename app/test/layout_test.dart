import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';

/// Loads real fonts from the OS so screenshots are legible (test environment has none by default).
Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }

  await load('MaterialIcons', 'C:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await load('Architects Daughter', 'assets/fonts/ArchitectsDaughter-Regular.ttf');
  await load('Share Tech Mono', 'assets/fonts/ShareTechMono-Regular.ttf');
  await load('STIX Two Math', 'assets/fonts/STIXTwoMath-Regular.ttf');
}

final bool shots = Platform.environment['LOWSYS_SHOTS'] == '1';

Future<void> snap(WidgetTester tester, GlobalKey key, String name) async {
  if (!shots) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../docs/screenshots/m1')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

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
