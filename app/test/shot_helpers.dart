import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads real fonts from the OS so screenshots are legible (test environment has none by default).
Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }

  // KaTeX fonts of flutter_math_fork (package assets are not auto-loaded in tests)
  final cache = Platform.environment['PUB_CACHE'] ??
      (Platform.isWindows ? '${Platform.environment['LOCALAPPDATA']}/Pub/Cache' : '${Platform.environment['HOME']}/.pub-cache');
  final hosted = Directory('$cache/hosted/pub.dev');
  if (hosted.existsSync()) {
    for (final d in hosted.listSync().whereType<Directory>().where((d) => d.path.contains('flutter_math_fork'))) {
      final fonts = Directory('${d.path}/lib/katex_fonts/fonts');
      if (!fonts.existsSync()) continue;
      for (final f in fonts.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        final name = f.uri.pathSegments.last.replaceAll('.ttf', '');
        final family = name.split('-').first;
        final loader = FontLoader('packages/flutter_math_fork/$family')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        await loader.load();
      }
    }
  }
  final flutterRoot = _flutterRoot();
  if (flutterRoot != null) {
    await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  }
  await load('Architects Daughter', 'assets/fonts/ArchitectsDaughter-Regular.ttf');
  await load('Share Tech Mono', 'assets/fonts/ShareTechMono-Regular.ttf');
  await load('VT323', 'assets/fonts/VT323-Regular.ttf');
  await load('STIX Two Math', 'assets/fonts/STIXTwoMath-Regular.ttf');
  await load('Rajdhani', 'assets/fonts/Rajdhani-Medium.ttf');
  await load('JetBrains Mono', 'assets/fonts/JetBrainsMono-VF.ttf');
  await load('Source Sans 3', 'assets/fonts/SourceSans3-VF.ttf');
  await load('Cinzel', 'assets/fonts/Cinzel-VF.ttf');
  await load('IM Fell English', 'assets/fonts/IMFeENrm28P.ttf');
  await load('Courier Prime', 'assets/fonts/CourierPrime-Regular.ttf');
  // the italic is the only Source Serif face the Paper captions use
  await load('Source Serif 4', 'assets/fonts/SourceSerif4-Italic-VF.ttf');
}

final bool shots = Platform.environment['LOWSYS_SHOTS'] == '1';

Future<void> snap(WidgetTester tester, GlobalKey key, String name, {String dir = 'm1', double ratio = 2.0}) async {
  if (!shots) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: ratio);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('../docs/screenshots/$dir')..createSync(recursive: true);
    File('${folder.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The Flutter SDK running this test: FLUTTER_ROOT if set, else found by walking up from the
/// test runner binary (it lives under `<root>/bin/cache/artifacts/engine/`).
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (Directory('${dir.path}/bin/cache/artifacts').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}
