// M10: golden images of the crude flowsheet (Windows host). Tolerant: text anti-aliasing and the raster path differ a
// little between GPUs and Flutter builds, so up to 1.5 % of the pixels may differ before the test fails.
// Regenerate with: flutter test --update-goldens test/m10_crude_golden_test.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lowsys_app/app.dart';
import 'package:lowsys_app/controllers/save_store.dart';
import 'package:lowsys_app/controllers/sim_controller.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import 'shot_helpers.dart';

/// A [LocalFileComparator] that accepts a golden when at most [tolerance] of its pixels differ.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(Uri testFile, this.tolerance) : super(testFile);
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    goldenFileComparator = _TolerantComparator(Uri.parse('test/m10_crude_golden_test.dart'), 0.015);
  });

  for (final id in ['blueprint', 'brass']) {
    testWidgets('crude flowsheet golden, $id', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final sim = SimController()..saveStore = MemorySaveStore();
      await tester.pumpWidget(LowsysApp(controller: sim));
      await tester.pump(const Duration(milliseconds: 500));
      await frames(tester, 10);
      await tester.runAsync(() => sim.load(Presets.crude));
      await tester.runAsync(() => sim.setTheme(id));
      await frames(tester, 30);
      expect(tester.takeException(), isNull);
      final flowsheet = find.byKey(const ValueKey('crude-flowsheet'));
      expect(flowsheet, findsOneWidget);
      await expectLater(flowsheet, matchesGoldenFile('goldens/crude_flowsheet_$id.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
