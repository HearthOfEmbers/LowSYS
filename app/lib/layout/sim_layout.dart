import 'package:flutter/material.dart';

import '../painters/effects/blueprint_grid.dart';
import '../theme/lowsys_theme.dart';
import '../widgets/column_view.dart';
import '../widgets/diagram_panel.dart';
import '../widgets/fault_panel.dart';
import '../widgets/kpi_strip.dart';
import '../widgets/time_bar.dart';
import '../widgets/tray_inspector.dart';
import 'breakpoints.dart';

/// Arranges ColumnView, DiagramPanel, ControlPanel and KpiStrip per layout class (SCOPE.md 3.3).
class SimLayout extends StatelessWidget {
  const SimLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      switch (layoutClassFor(size)) {
        case LayoutClass.compactPortrait:
          return _CompactPortrait(size: size);
        case LayoutClass.compactLandscape:
          return const _CompactLandscape();
        case LayoutClass.medium:
          return const _Medium();
        case LayoutClass.expanded:
          return const _Expanded();
      }
    });
  }
}

/// A framed drafting-sheet panel.
class SheetPanel extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  const SheetPanel({super.key, required this.child, this.title, this.trailing, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: CustomPaint(
        painter: SheetFramePainter(t, title ?? ''),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                  child: Row(children: [
                    Expanded(child: Text(title!, style: t.type.display.style(14, p.accent, weight: FontWeight.w700))),
                    if (trailing != null) trailing!,
                  ]),
                ),
              Expanded(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColumnPanel extends StatelessWidget {
  const _ColumnPanel();
  @override
  Widget build(BuildContext context) => const SheetPanel(child: ColumnView());
}

class _DiagramPanel extends StatelessWidget {
  final Widget? header;
  final bool compact;
  final bool inspector;
  const _DiagramPanel({this.header, this.compact = false, this.inspector = true});

  @override
  Widget build(BuildContext context) {
    // Phone portrait: the inspector floats over the free space under the (square) plot and scrolls, so
    // selecting a tray never squeezes the chart.
    if (compact && inspector && header == null) {
      return SheetPanel(
        child: LayoutBuilder(builder: (context, c) {
          final plotSide = (c.maxWidth - 52).clamp(40.0, c.maxHeight - 120);
          final free = (c.maxHeight - plotSide - 88).clamp(96.0, c.maxHeight * 0.6);
          return Stack(children: [
            Positioned.fill(child: DiagramBody(compact: compact)),
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: free),
                child: const SingleChildScrollView(child: TrayInspector()),
              ),
            ),
          ]);
        }),
      );
    }
    return SheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) header!,
          Expanded(child: DiagramBody(compact: compact)),
          if (inspector)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: TrayInspector(),
            ),
        ],
      ),
    );
  }
}

class _CompactPortrait extends StatelessWidget {
  final Size size;
  const _CompactPortrait({required this.size});

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    const peek = 0.30;
    return Stack(
      children: [
        Column(
          children: [
            const TimeBar(dense: true),
            const Expanded(
              child: Row(children: [
                Expanded(flex: 40, child: _ColumnPanel()),
                Expanded(flex: 60, child: _DiagramPanel(compact: true)),
              ]),
            ),
            const KpiStrip(),
            SizedBox(height: size.height * peek),
          ],
        ),
        DraggableScrollableSheet(
          initialChildSize: peek,
          minChildSize: peek,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [peek, 0.85],
          builder: (context, ctl) => Container(
            decoration: BoxDecoration(
              color: p.bgAlt,
              border: Border(top: BorderSide(color: p.accent, width: 1.5)),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10)],
            ),
            child: ControlTabs(
              controller: ctl,
              scrollTabs: true,
              handle: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(width: 44, height: 4, decoration: BoxDecoration(color: p.inkMuted, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactLandscape extends StatelessWidget {
  const _CompactLandscape();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(flex: 22, child: _ColumnPanel()),
        Expanded(
          flex: 48,
          child: Column(children: const [
            Expanded(child: _DiagramPanel(header: TimeBar(dense: true), compact: true, inspector: false)),
            KpiStrip(),
          ]),
        ),
        Expanded(
          flex: 30,
          child: SheetPanel(
            child: Column(children: const [
              Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 0), child: TrayInspector(hideWhenEmpty: true)),
              Expanded(child: ControlTabs()),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Medium extends StatefulWidget {
  const _Medium();
  @override
  State<_Medium> createState() => _MediumState();
}

class _MediumState extends State<_Medium> {
  bool open = true;
  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return LayoutBuilder(builder: (context, c) {
      return Column(
        children: [
          const TimeBar(),
          const Expanded(
            child: Row(children: [
              Expanded(flex: 30, child: _ColumnPanel()),
              Expanded(flex: 70, child: _DiagramPanel()),
            ]),
          ),
          const KpiStrip(),
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Container(
              height: 36,
              color: p.bgAlt,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text('CONTROLS', style: t.type.display.style(14, p.accent, weight: FontWeight.w700)),
                const Spacer(),
                Icon(open ? Icons.expand_more : Icons.expand_less, color: p.inkMuted),
              ]),
            ),
          ),
          if (open) SizedBox(height: c.maxHeight * 0.40, child: const ColoredBox(color: Color(0x33000000), child: ControlTabs())),
        ],
      );
    });
  }
}

class _Expanded extends StatelessWidget {
  const _Expanded();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        TimeBar(),
        Expanded(
          child: Row(children: [
            Expanded(flex: 25, child: _ColumnPanel()),
            Expanded(flex: 50, child: _DiagramPanel()),
            Expanded(flex: 25, child: SheetPanel(child: ControlTabs())),
          ]),
        ),
        KpiStrip(scroll: false),
      ],
    );
  }
}
