import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../layout/sim_layout.dart';
import '../painters/effects/blueprint_grid.dart';
import '../theme/lowsys_theme.dart';

/// Simulator screen S2: backdrop, layout, frame loop, keyboard shortcuts, run-to-steady overlay.
class SimScreen extends StatefulWidget {
  const SimScreen({super.key});
  @override
  State<SimScreen> createState() => _SimScreenState();
}

class _SimScreenState extends State<SimScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final sim = AppScope.of(context).sim;
      sim.load(sim.presetId).then((_) {
        if (mounted) _ticker.start();
      });
    }
  }

  void _onTick(Duration elapsed) {
    final scope = AppScope.of(context);
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final s = scope.sim.snapshot.value;
    final factor = s == null ? 1.0 : s.kpis.boilup / (150 / 3.6);
    scope.anim.tick(dt, factor, paused: scope.sim.paused && !scope.sim.runningToSteady);
    scope.sim.onTick(elapsed);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final sim = AppScope.of(context).sim;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      sim.togglePause();
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd) {
      sim.stepSpeed(1);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      sim.stepSpeed(-1);
    } else if (k == LogicalKeyboardKey.keyS) {
      sim.runToSteady();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: CustomPaint(painter: BlueprintBackdropPainter(t), isComplex: true, willChange: false)),
            SafeArea(
              child: ListenableBuilder(
                listenable: sim,
                builder: (context, _) => sim.loaded ? const SimLayout() : Center(child: Text('Setting up the drawing board…', style: t.type.display.style(18, p.inkMuted))),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: sim.notice,
              builder: (context, msg, _) => msg == null
                  ? const SizedBox.shrink()
                  : SafeArea(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 56, left: 12, right: 12),
                          child: Material(
                            color: p.surfaceAlt,
                            shape: RoundedRectangleBorder(side: BorderSide(color: p.warn)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Flexible(child: Text(msg, style: t.type.label.style(13, p.warn))),
                                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => sim.notice.value = null),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            ValueListenableBuilder<double?>(
              valueListenable: sim.steadyProgress,
              builder: (context, prog, _) => prog == null
                  ? const SizedBox.shrink()
                  : ColoredBox(
                      color: const Color(0x99051A33),
                      child: Center(
                        child: Container(
                          width: 300,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.accent, width: 1.5)),
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Marching to steady state…', style: t.type.display.style(18, p.ink)),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(value: prog <= 0 ? null : prog, color: p.accent, backgroundColor: p.gridMajor),
                            const SizedBox(height: 8),
                            Text('Fast-forward with the column model itself, no shortcuts.', style: t.type.label.style(12.5, p.inkMuted)),
                          ]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
