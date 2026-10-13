import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'package:lowsys_engine/lowsys_engine.dart';

import '../app_scope.dart';
import '../theme/lowsys_theme.dart';
import 'loops_panel.dart' show checkColor;

/// Energy panel (Equipment tab, SCOPE.md 8): condenser, reboiler and column energy balance cards. In plant view
/// the cards show readings only (FT-201, TI-201/202, PT-201, FT-103) and the C3a/C3b checks.
class EnergyPanel extends StatelessWidget {
  final ScrollController? controller;
  final Widget? header;
  const EnergyPanel({super.key, this.controller, this.header});

  @override
  Widget build(BuildContext context) {
    final sim = AppScope.of(context).sim;
    final t = LowsysThemeScope.of(context);
    final p = t.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([sim.snapshot, sim.units]),
      builder: (context, _) {
        final s = sim.snapshot.value;
        if (s == null) return const SizedBox();
        if (s.tier == ThermoTier.t1 || s.condenser == null) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (header != null) header!,
              Text(
                S.tier1NoEnergyBalance,
                key: const ValueKey('energy-t1'),
                style: t.type.label.style(14, p.inkMuted),
              ),
            ],
          );
        }
        final u = sim.units.value;
        final plant = s.view.isPlant;
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (header != null) header!,
            _CondenserCard(s: s, u: u, plant: plant, t: t),
            _ReboilerCard(s: s, u: u, plant: plant, t: t),
            if (s.reboiler.type == ReboilerType.thermosyphon) _ThermosyphonCard(s: s, u: u, t: t),
            _BalanceCard(s: s, u: u, plant: plant, t: t, sim: sim),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? flag;
  final Color? flagColor;
  final List<Widget> rows;
  final LowsysTheme t;
  final Key? cardKey;
  const _Card({
    required this.title,
    required this.rows,
    required this.t,
    this.flag,
    this.flagColor,
    this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    return Container(
      key: cardKey,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.55),
        border: Border.all(color: p.gridMajor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: t.type.display.style(15, p.accent, weight: FontWeight.w700),
                ),
              ),
              if (flag != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: flagColor ?? p.warn),
                  ),
                  child: Text(
                    flag!,
                    style: t.type.number.style(12, flagColor ?? p.warn, weight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final String? sub;
  final LowsysTheme t;
  final Color? valueColor;
  const _Row(this.label, this.value, this.t, {this.sub, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            flex: 3,
            child: Text(label, overflow: TextOverflow.ellipsis, style: t.type.label.style(13.5, p.inkMuted)),
          ),
          Flexible(
            flex: 3,
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: t.type.number.style(14, valueColor ?? p.ink, weight: FontWeight.w600),
            ),
          ),
          if (sub != null)
            Flexible(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(sub!, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: t.type.number.style(12, p.inkMuted)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A horizontal bar of [value] against [limit] with a tick at the limit.
class _Bar extends StatelessWidget {
  final double value, limit;
  final LowsysTheme t;
  final Color? color;
  const _Bar(this.value, this.limit, this.t, {this.color});

  @override
  Widget build(BuildContext context) {
    final p = t.palette;
    final f = (limit > 0 && value.isFinite) ? (value / limit).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 1, bottom: 3),
      child: SizedBox(
        height: 6,
        child: CustomPaint(
          painter: _BarPainter(f, color ?? p.inkMuted, p.gridMajor, p.ink),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double f;
  final Color fill, back, tick;
  _BarPainter(this.f, this.fill, this.back, this.tick);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = back);
    c.drawRect(Rect.fromLTWH(0, 0, s.width * f, s.height), Paint()..color = fill);
    c.drawLine(Offset(s.width - 1, 0), Offset(s.width - 1, s.height), Paint()..color = tick..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.f != f || o.fill != fill;
}

String _kw(UnitSystem u, double w) =>
    w.isNaN ? '—' : '${Fmt.value(Quantity.energyRate, w, u)} ${u.symbol(Quantity.energyRate)}';
String _temp(UnitSystem u, double k) =>
    k.isNaN ? '—' : '${Fmt.value(Quantity.temperature, k, u)} ${u.symbol(Quantity.temperature)}';
String _dT(UnitSystem u, double k) =>
    k.isNaN ? '—' : '${Fmt.value(Quantity.temperatureDelta, k, u)} ${u.symbol(Quantity.temperatureDelta)}';
String _bar(UnitSystem u, double pa) =>
    pa.isNaN ? '—' : '${Fmt.value(Quantity.pressure, pa, u)} ${u.symbol(Quantity.pressure)}';
String _ua(UnitSystem u, double w) =>
    w.isNaN ? '—' : '${Fmt.value(Quantity.ua, w, u)} ${u.symbol(Quantity.ua)}';

class _CondenserCard extends StatelessWidget {
  final SimSnapshot s;
  final UnitSystem u;
  final bool plant;
  final LowsysTheme t;
  const _CondenserCard({required this.s, required this.u, required this.plant, required this.t});

  @override
  Widget build(BuildContext context) {
    final c = s.condenser!;
    final p = t.palette;
    final blanket = c.inertFraction.isNaN ? 0.0 : (3 * c.inertFraction).clamp(0.0, 0.95);
    return _Card(
      cardKey: const ValueKey('energy-condenser'),
      title: S.condenserHeading,
      t: t,
      rows: [
        _Row(S.dutyQC, _kw(u, c.qC), t),
        if (!plant) ...[
          _Row(S.uaEffectiveClean, _ua(u, c.uaEff), t, sub: '/ ${_ua(u, c.uaClean)}'),
          _Bar(c.uaEff, c.uaClean, t, color: c.uaEff < 0.97 * c.uaClean ? p.warn : null),
        ],
        _Row(S.coolingWaterInOut, _temp(u, c.tCwIn), t, sub: '→ ${_temp(u, c.tCwOut)}'),
        _Row(S.cwValvePv101, c.cwOp.isNaN ? '—' : '${c.cwOp.toStringAsFixed(1)} %', t,
            valueColor: c.cwOp >= 99.5 ? p.warn : null),
        if (!plant) ...[
          _Row(S.condensingTemperature, _temp(u, c.tCond), t),
          _Row(S.refluxSubcooling, _dT(u, c.subcooling), t, sub: 'reflux ${_temp(u, c.tReflux)}'),
          _Row(S.inertsYI, '${(100 * c.inertFraction).toStringAsFixed(1)} %', t,
              sub: blanket > 0.005 ? 'tubes blanketed ${(100 * blanket).toStringAsFixed(0)} %' : null,
              valueColor: c.inertFraction > 0.02 ? p.warn : null),
          _Row(S.topPressure, _bar(u, s.kpis.pTop), t),
          if (c.partial)
            _Row(
              S.vapourProductPv102,
              '${u.fromSI(Quantity.molarFlow, c.vaporProduct).toStringAsFixed(1)} ${u.symbol(Quantity.molarFlow)}',
              t,
            ),
          if (c.nRelief > 1e-6) _Row(S.reliefValve, 'LIFTING', t, valueColor: p.alarm),
        ] else
          _Row(S.refluxTemperatureTi100, _temp(u, c.tReflux), t),
      ],
    );
  }
}

class _ReboilerCard extends StatelessWidget {
  final SimSnapshot s;
  final UnitSystem u;
  final bool plant;
  final LowsysTheme t;
  const _ReboilerCard({required this.s, required this.u, required this.plant, required this.t});

  @override
  Widget build(BuildContext context) {
    final r = s.reboiler;
    final p = t.palette;
    return _Card(
      cardKey: const ValueKey('energy-reboiler'),
      title: S.reboilerHeading,
      t: t,
      flag: r.dutyLimited ? 'DUTY LIMITED' : null,
      flagColor: p.warn,
      rows: [
        _Row(S.dutyDelivered, _kw(u, r.qDelivered), t, sub: plant || r.qMax.isNaN ? null : 'of ${_kw(u, r.qMax)} max'),
        if (!plant) _Bar(r.qDelivered, r.qMax, t, color: r.dutyLimited ? p.warn : null),
        if (!plant) _Row(S.uaEffectiveClean, _ua(u, r.uaEff), t, sub: '/ ${_ua(u, r.uaClean)}'),
        _Row(S.steamHeader, _bar(u, r.steamP), t, sub: 'T_st ${_temp(u, r.steamT)}'),
        _Row(S.steamValveFv103, r.steamValveOp.isNaN ? '—' : '${r.steamValveOp.toStringAsFixed(1)} %', t,
            valueColor: r.steamValveOp >= 99.5 ? p.warn : null),
        _Row(S.sumpTemperature, _temp(u, r.tSump), t),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final SimSnapshot s;
  final UnitSystem u;
  final bool plant;
  final LowsysTheme t;
  final dynamic sim;
  const _BalanceCard({required this.s, required this.u, required this.plant, required this.t, required this.sim});

  @override
  Widget build(BuildContext context) {
    final e = s.energy;
    final p = t.palette;
    CrossCheckResult? chk(String id) {
      for (final c in s.crossChecks) {
        if (c.id == id) return c;
      }
      return null;
    }

    Widget checkRow(String id, String label) {
      final c = chk(id);
      final col = c == null ? p.inkFaint : checkColor(p, c.status);
      final txt = c == null
          ? '—'
          : (c.status == CheckStatus.ok || c.status == CheckStatus.check || c.status == CheckStatus.fail)
              ? '${c.status.name.toUpperCase()} ${(c.residual.abs() / c.band).toStringAsFixed(1)}×'
              : 'n/a';
      return _Row(label, txt, t, valueColor: col);
    }

    return _Card(
      cardKey: const ValueKey('energy-balance'),
      title: S.columnEnergyBalanceHeading,
      t: t,
      rows: [
        if (!plant && e != null) ...[
          _Row(S.inFeedReboiler, _kw(u, e.feed + e.reboiler), t, sub: '${_kw(u, e.feed)} + ${_kw(u, e.reboiler)}'),
          _Row(S.outCondenserProducts, _kw(u, e.condenser + e.distillate + e.bottoms + e.vaporProduct), t,
              sub: '${_kw(u, e.condenser)} + ${_kw(u, e.distillate + e.bottoms)}${e.vaporProduct != 0 ? " + ${_kw(u, e.vaporProduct)} vapour" : ""}'),
          _Row(S.residual, _kw(u, e.residual), t,
              sub: s.kpis.energyResidual.isNaN ? null : '${(100 * s.kpis.energyResidual).toStringAsExponential(1)} % of Q_R'),
        ],
        checkRow('C3a', 'C3a  Condenser duty vs reflux + distillate'),
        checkRow('C3b', 'C3b  Energy balance from the readings'),
        if (plant)
          Text(
            S.plantReadingsKnown,
            style: t.type.label.style(12, p.inkMuted),
          ),
      ],
    );
  }
}

/// Thermosyphon loop card (M6, PHYSICS.md 8.3): circulation, exit and riser quality, the instability index against its
/// 1.0 limit, the oscillation and the line pressure drops. In plant view the loop is not observable; with the engineering
/// calculations (plantCalc) the calculated values carry a "calc" label.
class _ThermosyphonCard extends StatelessWidget {
  final SimSnapshot s;
  final UnitSystem u;
  final LowsysTheme t;
  const _ThermosyphonCard({required this.s, required this.u, required this.t});

  @override
  Widget build(BuildContext context) {
    final r = s.reboiler;
    final p = t.palette;
    final calc = s.view == SimView.plantCalc;
    final plant = s.view.isPlant;
    final tag = calc ? ' calc' : '';
    String num2(double v, String unit, [int d = 2]) => v.isNaN ? '—' : '${v.toStringAsFixed(d)} $unit';
    final surging = !r.instabilityIndex.isNaN && r.instabilityIndex > 1.0;
    if (plant && !calc) {
      return _Card(
        cardKey: const ValueKey('energy-thermosyphon'),
        title: S.thermosyphonHeading,
        t: t,
        rows: [
          _LoopSchematic(r: r, t: t, show: false, surging: false),
          _Row(S.inletValve, '${r.inletValve.toStringAsFixed(0)} % open', t),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              S.thermosyphonNotObservable,
              style: t.type.label.style(13, p.inkMuted),
            ),
          ),
        ],
      );
    }
    return _Card(
      cardKey: const ValueKey('energy-thermosyphon'),
      title: calc ? 'THERMOSYPHON (calc)' : 'THERMOSYPHON',
      t: t,
      flag: surging ? 'SURGING' : null,
      flagColor: p.alarm,
      rows: [
        _LoopSchematic(r: r, t: t, show: true, surging: surging),
        _Row('Circulation W$tag', num2(r.circulation, 'kg/s'), t),
        _Row('Exit quality x_e$tag', num2(r.exitQuality, '', 3), t,
            sub: r.exitQuality > 0.30 ? 'above 0.30: mist flow' : null,
            valueColor: r.exitQuality > 0.30 ? p.warn : null),
        _Row('Riser quality x_r$tag', num2(r.riserQuality, '', 3), t),
        _Row('Surge index I_s$tag', num2(r.instabilityIndex, '', 2), t, sub: S.limit100, valueColor: surging ? p.alarm : null),
        _Bar(r.instabilityIndex.isNaN ? 0 : r.instabilityIndex, 1.0, t, color: surging ? p.alarm : p.ok),
        _Row('Oscillation$tag', r.oscAmplitude.isNaN ? '—' : '${(100 * r.oscAmplitude).toStringAsFixed(1)} %', t,
            sub: r.oscAmplitude > 0.005 ? 'period ${r.oscPeriod.toStringAsFixed(1)} s' : null,
            valueColor: r.oscAmplitude > 0.02 ? p.alarm : null),
        _Row('Inlet line dP$tag', _bar(u, r.inletLineDp), t),
        _Row('Outlet line dP$tag', _bar(u, r.outletLineDp), t),
        _Row(S.inletValve, '${r.inletValve.toStringAsFixed(0)} % open', t),
        _Row(S.steamSideDutyFt, _kw(u, r.steamSideDuty), t, sub: S.meanOfTheLoop),
      ],
    );
  }
}

/// Thermosyphon loop drawing: sump on the left, inlet line down to the heater tubes, riser up to the column return.
/// The two-phase leg is shaded by the exit quality and the loop turns red while it surges; the inlet valve shows its
/// opening. With [show] false (plant view) only the inlet valve is drawn: the loop is not observable.
class _LoopSchematic extends StatelessWidget {
  final ReboilerSnapshot r;
  final LowsysTheme t;
  final bool show, surging;
  const _LoopSchematic({required this.r, required this.t, required this.show, required this.surging});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: SizedBox(
          key: const ValueKey('ts-schematic'),
          height: 120,
          child: CustomPaint(
            painter: _LoopPainter(
              palette: t.palette,
              valve: r.inletValve.isNaN ? 100 : r.inletValve,
              xe: show && !r.exitQuality.isNaN ? r.exitQuality : null,
              surging: surging,
              style: t.type.label.style(11, t.palette.inkMuted),
            ),
          ),
        ),
      );
}

class _LoopPainter extends CustomPainter {
  final dynamic palette;
  final double valve;
  final double? xe;
  final bool surging;
  final TextStyle style;
  _LoopPainter({required this.palette, required this.valve, required this.xe, required this.surging, required this.style});

  void _label(Canvas c, String text, Offset at) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..color = palette.ink as Color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final hot = surging ? palette.alarm as Color : palette.accent as Color;
    final q = ((xe ?? 0) / 0.4).clamp(0.0, 1.0);
    final twoPhase = Paint()
      ..color = Color.lerp(palette.ink as Color, hot, xe == null ? 0 : 0.3 + 0.7 * q)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final x0 = w * 0.12, x1 = w * 0.38, x2 = w * 0.62, x3 = w * 0.88;
    final yTop = h * 0.14, yLiq = h * 0.34, yBot = h * 0.84;
    // column sump (left) and the column return (right)
    final sump = Rect.fromLTRB(x0 - 22, yTop, x0 + 22, yBot - 14);
    canvas.drawRect(sump, line);
    final liquid = Paint()..color = (palette.accent as Color).withValues(alpha: 0.25);
    canvas.drawRect(Rect.fromLTRB(sump.left + 1, yLiq, sump.right - 1, sump.bottom - 1), liquid);
    canvas.drawLine(Offset(sump.left, yLiq), Offset(sump.right, yLiq), line);
    // inlet line: sump bottom -> valve -> heater bottom
    canvas.drawLine(Offset(x0, sump.bottom), Offset(x0, yBot), line);
    canvas.drawLine(Offset(x0, yBot), Offset(x1, yBot), line);
    // heater (tubes)
    final heater = Rect.fromLTRB(x1, yTop + 8, x2, yBot + 6);
    canvas.drawRect(heater, line);
    for (var i = 1; i < 5; i++) {
      final x = heater.left + heater.width * i / 5;
      canvas.drawLine(Offset(x, heater.top + 4), Offset(x, heater.bottom - 4), line..strokeWidth = 1);
    }
    line.strokeWidth = 2;
    // riser: heater top -> column return, drawn thick in the two-phase colour
    final riser = Path()
      ..moveTo((x1 + x2) / 2, heater.top)
      ..lineTo((x1 + x2) / 2, yTop - 6 + 8)
      ..lineTo(x3, yTop + 2)
      ..lineTo(x3, yLiq - 4);
    canvas.drawPath(riser, twoPhase);
    canvas.drawRect(Rect.fromLTRB(x3 - 22, yLiq - 4, x3 + 22, yBot - 14), line);
    // inlet valve (bowtie), its fill follows the opening
    final vx = (x0 + x1) / 2, vy = yBot;
    final vp = Path()
      ..moveTo(vx - 8, vy - 7)
      ..lineTo(vx + 8, vy + 7)
      ..lineTo(vx + 8, vy - 7)
      ..lineTo(vx - 8, vy + 7)
      ..close();
    canvas.drawPath(vp, Paint()..color = (palette.ok as Color).withValues(alpha: (valve / 100).clamp(0.1, 1.0)));
    canvas.drawPath(vp, line);
    _label(canvas, S.sump, Offset(x0 - 14, yTop - 12));
    _label(canvas, 'inlet ${valve.toStringAsFixed(0)} %', Offset(x0 - 10, h - 14));
    _label(canvas, S.heater, Offset(x1 + 4, h - 14));
    _label(canvas, xe == null ? 'riser' : 'riser x_e ${xe!.toStringAsFixed(2)}', Offset(x2 + 4, yTop - 12));
    _label(canvas, S.column, Offset(x3 - 18, h - 14));
  }

  @override
  bool shouldRepaint(_LoopPainter o) => o.valve != valve || o.xe != xe || o.surging != surging || o.palette != palette;
}
