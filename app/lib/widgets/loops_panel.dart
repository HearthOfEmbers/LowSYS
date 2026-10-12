import 'package:flutter/material.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../controllers/sim_controller.dart';
import '../theme/lowsys_theme.dart';

const Map<String, String> kLoopValve = {
  'FC-101': 'FV-101',
  'FC-102': 'FV-102',
  'FC-103': 'FV-103',
  'LC-101': 'LV-101',
  'LC-102': 'LV-102',
};

const Map<String, String> kLoopTitle = {
  'FC-101': 'Feed flow',
  'FC-102': 'Reflux flow',
  'FC-103': 'Boilup',
  'LC-101': 'Drum level',
  'LC-102': 'Sump level',
};

const Map<String, String> kLoopGauge = {'LC-101': 'LG-101', 'LC-102': 'LG-102'};

String qualityBadge(InstrumentReading r) {
  switch (r.quality) {
    case Quality.good:
      return '';
    case Quality.uncertain:
      return r.qualityText ?? 'OOR';
    case Quality.bad:
      return r.qualityText ?? 'BAD';
    case Quality.oos:
      return 'OOS';
  }
}

Color checkColor(ThemePalette p, CheckStatus? s) => switch (s) {
  CheckStatus.ok => p.ok,
  CheckStatus.check => p.warn,
  CheckStatus.fail => p.alarm,
  _ => p.inkFaint,
};

/// Loops tab: one faceplate per loop with mode, PV, SP, OP, signal look, valve curve and the field actions
/// (PHYSICS.md 10, SCOPE.md M3).
class LoopsPanel extends StatelessWidget {
  final ScrollController? controller;
  final Widget? header;
  const LoopsPanel({super.key, this.controller, this.header});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    return ListenableBuilder(
      listenable: Listenable.merge([sim.snapshot, sim.units, sim.selectedLoop]),
      builder: (context, _) {
        final s = sim.snapshot.value;
        if (s == null) return const SizedBox();
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
          children: [
            if (header != null) header!,
            for (final l in s.loops) Faceplate(loop: l, snap: s),
          ],
        );
      },
    );
  }
}

class Faceplate extends StatelessWidget {
  final LoopSnapshot loop;
  final SimSnapshot snap;
  const Faceplate({super.key, required this.loop, required this.snap});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final u = sim.units.value;
    final tag = loop.tag;
    final r = snap.instruments.firstWhere((x) => x.loopTag == tag);
    final valve = snap.valves.firstWhere((v) => v.id == kLoopValve[tag]);
    final open = sim.selectedLoop.value == tag;
    final q = r.quantity;
    final bad = r.quality == Quality.bad || r.quality == Quality.oos;
    final badge = qualityBadge(r);
    String f(double v) => Fmt.value(q, v, u);
    final unit = u.symbol(q);
    final auto = loop.mode == LoopMode.auto;
    final man = loop.mode == LoopMode.man;
    final c4 = snap.crossChecks
        .where((c) => c.id == 'C4:${valve.id}')
        .firstOrNull;
    final ratio = r.typicalSigma > 0 ? r.sigma5min / r.typicalSigma : 1.0;
    final lookOdd = ratio < 0.2 || ratio > 5;
    final border = bad ? p.alarm : (loop.shed ? p.warn : p.gridMajor);

    Widget modeButton(String label, LoopMode m, {bool enabled = true}) =>
        Expanded(
          child: InkWell(
            onTap: enabled && loop.mode != m
                ? () => sim.setLoopMode(tag, m)
                : null,
            child: Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: loop.mode == m ? p.accent : Colors.transparent,
                border: Border.all(color: enabled ? p.accent : p.inkFaint),
              ),
              child: Text(
                label,
                style: t.type.display.style(
                  13,
                  loop.mode == m ? p.bgAlt : (enabled ? p.accent : p.inkFaint),
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.55),
        border: Border.all(color: border, width: bad ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => sim.selectedLoop.value = open ? null : tag,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tag,
                              style: t.type.display.style(
                                15,
                                p.accent,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                kLoopTitle[tag] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: t.type.label.style(12.5, p.inkMuted),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          loop.shed
                              ? 'MAN (shed: bad PV)'
                              : loop.mode.name.toUpperCase(),
                          style: t.type.label.style(
                            12.5,
                            loop.shed ? p.warn : p.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => sim.openMath(ExplainInstrument(r.tag)),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (badge.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    color: bad ? p.alarm : p.warn,
                                    child: Text(
                                      badge,
                                      style: t.type.number.style(
                                        11.5,
                                        p.bgAlt,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                Text(
                                  bad ? f(r.lastGoodValue) : f(r.value),
                                  style: t.type.number.style(
                                    18,
                                    bad ? p.inkFaint : p.ink,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  unit,
                                  style: t.type.label.style(12, p.inkMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            'SP ${f(loop.sp)}   OP ${loop.op.toStringAsFixed(1)} %',
                            style: t.type.number.style(12.5, p.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: p.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      modeButton('MAN', LoopMode.man),
                      const SizedBox(width: 6),
                      modeButton('AUTO', LoopMode.auto, enabled: !bad),
                    ],
                  ),
                  if (loop.spTracked && auto)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'SP tracked the PV when you switched to AUTO.',
                        style: t.type.label.style(12, p.inkMuted),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _slider(
                    context,
                    label: 'SP',
                    enabled: !man || true,
                    value: u.fromSI(q, loop.sp),
                    min: u.fromSI(q, loop.spLo),
                    max: u.fromSI(q, loop.spHi),
                    text: f(loop.sp),
                    onChanged: (v) => sim.setLoopSp(tag, u.toSI(q, v)),
                    note: man ? 'stored; acts in AUTO' : null,
                  ),
                  _slider(
                    context,
                    label: 'OP',
                    enabled: man,
                    value: loop.op,
                    min: loop.opLo,
                    max: loop.opHi,
                    text: '${loop.op.toStringAsFixed(1)} %',
                    onChanged: (v) => sim.setLoopOp(tag, v),
                    note: man ? null : 'MAN only',
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.typicalSigma <= 0
                              ? ''
                              : 'Signal look: σ ${Fmt.sig(u.fromSI(q, r.sigma5min), 2)} (typical ${Fmt.sig(u.fromSI(q, r.typicalSigma), 2)}), digits unchanged for ${r.digitsAge.floor()} s',
                          style: t.type.label.style(
                            12.5,
                            lookOdd ? p.warn : p.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (lookOdd)
                    Text(
                      ratio < 0.2
                          ? 'Too steady: frozen or plugged?'
                          : 'Too erratic: spikes?',
                      style: t.type.label.style(
                        12.5,
                        p.warn,
                        weight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => sim.openMath(ExplainValve(valve.id)),
                        child: SizedBox(
                          width: 120,
                          height: 96,
                          child: CustomPaint(
                            painter: ValveCurvePainter(t, valve, r, c4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              valve.id,
                              style: t.type.display.style(
                                13.5,
                                p.accent,
                                weight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              c4 == null ||
                                      c4.status == CheckStatus.notAvailable
                                  ? 'Valve curve: collecting data'
                                  : 'Expects ${Fmt.value(q, c4.terms['expected'] ?? double.nan, u)} $unit at OP ${(c4.terms['op'] ?? 0).toStringAsFixed(1)} %, meter says ${Fmt.value(q, c4.terms['measured'] ?? double.nan, u)} (band ±${Fmt.value(q, c4.band, u)})',
                              style: t.type.label.style(
                                12.5,
                                checkColor(p, c4?.status),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _BypassRow(valve: valve, sim: sim),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      if (kLoopGauge[tag] != null)
                        TextButton(
                          onPressed: () => sim.fieldCheck(kLoopGauge[tag]!),
                          child: Text(
                            'Field check ${kLoopGauge[tag]}',
                            style: t.type.label.style(
                              13,
                              p.accent,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (kLoopGauge[tag] != null)
                        _fieldResult(context, snap, kLoopGauge[tag]!, r, u),
                      if (sim.scenarioDef == null || !sim.scenarioDef!.isDrill)
                        TextButton(
                          onPressed: () => sim.maintenance(r.tag),
                          child: Text(
                            'Maintenance ${r.tag}',
                            style: t.type.label.style(
                              13,
                              p.warn,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => sim.openMath(ExplainLoop(tag)),
                        child: Text(
                          'Show the PID math',
                          style: t.type.label.style(13, p.inkMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fieldResult(
    BuildContext context,
    SimSnapshot s,
    String gauge,
    InstrumentReading r,
    UnitSystem u,
  ) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final fc = s.fieldChecks.where((x) => x.gaugeTag == gauge).firstOrNull;
    if (fc == null) return const SizedBox.shrink();
    if (fc.value == null) {
      final left = (fc.readyAt - s.time).clamp(0, 180).round();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'walking to the gauge… $left s',
          style: t.type.label.style(12.5, p.inkMuted),
        ),
      );
    }
    final diff = (r.value - fc.value!).abs();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '$gauge read ${fc.value!.toStringAsFixed(0)} %; transmitter ${r.value.toStringAsFixed(1)} % (differs by ${diff.toStringAsFixed(1)})',
        style: t.type.label.style(12.5, diff > 5 ? p.alarm : p.ok),
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required bool enabled,
    required double value,
    required double min,
    required double max,
    required String text,
    required void Function(double) onChanged,
    String? note,
  }) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: t.type.label.style(13, enabled ? p.ink : p.inkFaint),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max > min ? max : min + 1,
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            text,
            style: t.type.number.style(13, enabled ? p.accent : p.inkFaint),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _BypassRow extends StatelessWidget {
  final ValveSnapshot valve;
  final SimController sim;
  const _BypassRow({required this.valve, required this.sim});

  @override
  Widget build(BuildContext context) {
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    final on = valve.bypass >= 0;
    return Row(
      children: [
        Text('Bypass', style: t.type.label.style(12.5, p.inkMuted)),
        const SizedBox(width: 6),
        SizedBox(
          height: 28,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            onPressed: () => sim.setLever('bypass.${valve.id}', on ? -1 : 50),
            child: Text(
              on ? 'close' : 'open to 50 %',
              style: t.type.label.style(12.5, p.warn, weight: FontWeight.w700),
            ),
          ),
        ),
        if (on)
          Text(
            '${valve.bypass.toStringAsFixed(0)} %',
            style: t.type.number.style(12.5, p.warn),
          ),
      ],
    );
  }
}

/// Flow versus OP with the straight characteristic, the band and the operating point (PHYSICS.md 14.6, C4).
class ValveCurvePainter extends CustomPainter {
  final LowsysTheme t;
  final ValveSnapshot valve;
  final InstrumentReading meter;
  final CrossCheckResult? check;
  ValveCurvePainter(this.t, this.valve, this.meter, this.check);

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.palette;
    final area = Rect.fromLTWH(22, 4, size.width - 28, size.height - 22);
    final axis = Paint()
      ..color = p.gridMajor
      ..style = PaintingStyle.stroke;
    canvas.drawRect(area, axis);
    final fMax = valve.fMax.isNaN ? 1.0 : valve.fMax;
    Offset at(double op, double flow) => Offset(
      area.left + area.width * op / 100,
      area.bottom - area.height * (flow / fMax).clamp(-0.05, 1.05),
    );
    final band = 0.015 * fMax;
    final path = Path()
      ..moveTo(at(0, band).dx, at(0, band).dy)
      ..lineTo(at(100, fMax + band).dx, at(100, fMax + band).dy)
      ..lineTo(at(100, fMax - band).dx, at(100, fMax - band).dy)
      ..lineTo(at(0, -band).dx, at(0, -band).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = p.ok.withValues(alpha: 0.18));
    canvas.drawLine(
      at(0, 0),
      at(100, fMax),
      Paint()
        ..color = p.ok
        ..strokeWidth = 1.2,
    );
    final dot = Paint()..color = checkColor(p, check?.status);
    final pt = at(valve.op, meter.value);
    canvas.drawCircle(pt, 4, dot);
    final tp = TextPainter(
      text: TextSpan(text: 'OP %', style: t.type.label.style(10, p.inkMuted)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(area.center.dx - tp.width / 2, size.height - tp.height),
    );
    final tp2 = TextPainter(
      text: TextSpan(text: 'F', style: t.type.label.style(10, p.inkMuted)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(ValveCurvePainter old) =>
      old.valve != valve ||
      old.meter != meter ||
      old.check != check ||
      old.t != t;
}
