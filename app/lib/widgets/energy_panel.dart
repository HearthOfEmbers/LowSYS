import 'package:flutter/material.dart';
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
                'Tier 1 has no energy balance: the vapour flow is the same on every tray and the heat duties are not modelled. Switch to Tier 2 with the T1/T2 badge to see the condenser, the reboiler and the column energy balance.',
                key: const ValueKey('energy-t1'),
                style: t.type.label.style(14, p.inkMuted),
              ),
            ],
          );
        }
        final u = sim.units.value;
        final plant = s.view == SimView.plant;
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (header != null) header!,
            _CondenserCard(s: s, u: u, plant: plant, t: t),
            _ReboilerCard(s: s, u: u, plant: plant, t: t),
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
      title: 'CONDENSER',
      t: t,
      rows: [
        _Row('Duty Q_C', _kw(u, c.qC), t),
        if (!plant) ...[
          _Row('UA effective / clean', _ua(u, c.uaEff), t, sub: '/ ${_ua(u, c.uaClean)}'),
          _Bar(c.uaEff, c.uaClean, t, color: c.uaEff < 0.97 * c.uaClean ? p.warn : null),
        ],
        _Row('Cooling water in / out', _temp(u, c.tCwIn), t, sub: '→ ${_temp(u, c.tCwOut)}'),
        _Row('CW valve PV-101', c.cwOp.isNaN ? '—' : '${c.cwOp.toStringAsFixed(1)} %', t,
            valueColor: c.cwOp >= 99.5 ? p.warn : null),
        if (!plant) ...[
          _Row('Condensing temperature', _temp(u, c.tCond), t),
          _Row('Reflux subcooling', _dT(u, c.subcooling), t, sub: 'reflux ${_temp(u, c.tReflux)}'),
          _Row('Inerts y_I', '${(100 * c.inertFraction).toStringAsFixed(1)} %', t,
              sub: blanket > 0.005 ? 'tubes blanketed ${(100 * blanket).toStringAsFixed(0)} %' : null,
              valueColor: c.inertFraction > 0.02 ? p.warn : null),
          _Row('Top pressure', _bar(u, s.kpis.pTop), t),
          if (c.partial)
            _Row(
              'Vapour product PV-102',
              '${u.fromSI(Quantity.molarFlow, c.vaporProduct).toStringAsFixed(1)} ${u.symbol(Quantity.molarFlow)}',
              t,
            ),
          if (c.nRelief > 1e-6) _Row('Relief valve', 'LIFTING', t, valueColor: p.alarm),
        ] else
          _Row('Reflux temperature TI-100', _temp(u, c.tReflux), t),
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
      title: 'REBOILER',
      t: t,
      flag: r.dutyLimited ? 'DUTY LIMITED' : null,
      flagColor: p.warn,
      rows: [
        _Row('Duty delivered', _kw(u, r.qDelivered), t, sub: plant || r.qMax.isNaN ? null : 'of ${_kw(u, r.qMax)} max'),
        if (!plant) _Bar(r.qDelivered, r.qMax, t, color: r.dutyLimited ? p.warn : null),
        if (!plant) _Row('UA effective / clean', _ua(u, r.uaEff), t, sub: '/ ${_ua(u, r.uaClean)}'),
        _Row('Steam header', _bar(u, r.steamP), t, sub: 'T_st ${_temp(u, r.steamT)}'),
        _Row('Steam valve FV-103', r.steamValveOp.isNaN ? '—' : '${r.steamValveOp.toStringAsFixed(1)} %', t,
            valueColor: r.steamValveOp >= 99.5 ? p.warn : null),
        _Row('Sump temperature', _temp(u, r.tSump), t),
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
      title: 'COLUMN ENERGY BALANCE',
      t: t,
      rows: [
        if (!plant && e != null) ...[
          _Row('In: feed + reboiler', _kw(u, e.feed + e.reboiler), t, sub: '${_kw(u, e.feed)} + ${_kw(u, e.reboiler)}'),
          _Row('Out: condenser + products', _kw(u, e.condenser + e.distillate + e.bottoms + e.vaporProduct), t,
              sub: '${_kw(u, e.condenser)} + ${_kw(u, e.distillate + e.bottoms)}${e.vaporProduct != 0 ? " + ${_kw(u, e.vaporProduct)} vapour" : ""}'),
          _Row('Residual', _kw(u, e.residual), t,
              sub: s.kpis.energyResidual.isNaN ? null : '${(100 * s.kpis.energyResidual).toStringAsExponential(1)} % of Q_R'),
        ],
        checkRow('C3a', 'C3a  Condenser duty vs reflux + distillate'),
        checkRow('C3b', 'C3b  Energy balance from the readings'),
        if (plant)
          Text(
            'On a real plant only the readings are known: FT-201, TI-201, TI-202, PT-201 and FT-103.',
            style: t.type.label.style(12, p.inkMuted),
          ),
      ],
    );
  }
}
