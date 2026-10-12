import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../layout/breakpoints.dart';
import '../theme/lowsys_theme.dart';

/// Hosts the math overlay (SCOPE.md S2c): a bottom sheet on phones and tablets, a floating draggable panel
/// on desktop, a right-hand sheet in compact landscape.
class MathOverlayHost extends StatefulWidget {
  const MathOverlayHost({super.key});
  @override
  State<MathOverlayHost> createState() => _MathOverlayHostState();
}

class _MathOverlayHostState extends State<MathOverlayHost> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    return Positioned.fill(
      child: ValueListenableBuilder<ExplainTarget?>(
      valueListenable: sim.mathTarget,
      builder: (context, target, _) {
        if (target == null) return const IgnorePointer(child: SizedBox.shrink());
        return LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final cls = layoutClassFor(size);
          final body = _OverlayBody(onClose: sim.closeMath, onDragTitle: cls == LayoutClass.expanded ? (d) => setState(() => _drag += d) : null);
          Widget wrap(Widget w) => Stack(children: [w]);
          switch (cls) {
            case LayoutClass.expanded:
              final w = 480.0, h = size.height * 0.78;
              return wrap(Positioned(
                left: (size.width - w - 24 + _drag.dx).clamp(0.0, size.width - w),
                top: (60 + _drag.dy).clamp(0.0, size.height - 120),
                width: w,
                height: h,
                child: _frame(context, body, shadow: true),
              ));
            case LayoutClass.compactLandscape:
              return wrap(Positioned(right: 0, top: 0, bottom: 0, width: size.width * 0.46, child: _frame(context, body)));
            default:
              return wrap(Positioned(left: 0, right: 0, bottom: 0, height: size.height * 0.7, child: _frame(context, body, shadow: true)));
          }
        });
      },
    ));
  }

  Widget _frame(BuildContext context, Widget body, {bool shadow = false}) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return Material(
      color: p.bgAlt,
      elevation: 0,
      shape: Border.all(color: p.accent, width: 1.5),
      child: body,
    );
  }
}

class _OverlayBody extends StatelessWidget {
  final VoidCallback onClose;
  final void Function(Offset)? onDragTitle;
  const _OverlayBody({required this.onClose, this.onDragTitle});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ValueListenableBuilder<ExplainResult?>(
      valueListenable: sim.mathResult,
      builder: (context, r, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onPanUpdate: onDragTitle == null ? null : (d) => onDragTitle!(d.delta),
              child: Container(
                color: p.surface,
                padding: const EdgeInsets.only(left: 12),
                height: 48,
                child: Row(children: [
                  Icon(Icons.functions, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r?.title ?? '…', style: t.type.display.style(17, p.ink, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (r != null) Text('t = ${_clock(r.time)}', style: t.type.number.style(12, p.inkMuted)),
                  IconButton(tooltip: 'Close', icon: Icon(Icons.close, color: p.inkMuted), onPressed: onClose),
                ]),
              ),
            ),
            Expanded(
              child: r == null
                  ? const SizedBox()
                  : ValueListenableBuilder<UnitSystem>(
                      valueListenable: sim.units,
                      builder: (context, u, _) => ListView(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        children: [
                          for (final g in r.groups) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Text(g.title.toUpperCase(), style: t.type.display.style(13.5, p.accent, weight: FontWeight.w700)),
                            ),
                            for (final l in g.lines) _Line(line: l, units: u, t: t),
                          ],
                          if (r.notes.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 4),
                              child: Text('WHAT THIS SIMPLIFICATION HIDES', style: t.type.display.style(13, p.inkMuted, weight: FontWeight.w700)),
                            ),
                            for (final n in r.notes)
                              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $n', style: t.type.label.style(13, p.inkMuted))),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  static String _clock(double t) {
    final s = t.floor();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}';
  }
}

class _Line extends StatelessWidget {
  final EquationLine line;
  final UnitSystem units;
  final LowsysTheme t;
  const _Line({required this.line, required this.units, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    // Long equations scroll sideways (touch or mouse drag) with a fade at the right edge as the hint.
    Widget tex(String src, Color color, double size) => ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Colors.white, Color(0x00FFFFFF)], stops: [0, 0.9, 1]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet(), scrollbars: false),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 28),
              child: Math.tex(
                src,
                textStyle: t.type.math.style(size, color),
                mathStyle: MathStyle.text,
                onErrorFallback: (e) => Text(src, style: t.type.number.style(12, color)),
              ),
            ),
          ),
        );
    var echo = '';
    if (line.quantity != Quantity.dimensionless && units == UnitSystem.usField) {
      echo = ' = ${Fmt.value(line.quantity, line.value, units)} ${units.symbol(line.quantity)}';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.5), border: Border(left: BorderSide(color: p.accent, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(line.id, style: t.type.number.style(12, p.inkMuted)),
          const Spacer(),
          Text(line.physicsRef, style: t.type.number.style(12, p.inkFaint)),
        ]),
        const SizedBox(height: 4),
        tex(line.texSymbolic, p.ink, 16),
        const SizedBox(height: 6),
        tex(line.texSubstituted, p.accent, 16),
        if (echo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(echo.substring(3), style: t.type.number.style(13, p.warn))),
        if (line.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(line.note!, style: t.type.label.style(12.5, p.inkMuted))),
      ]),
    );
  }
}
