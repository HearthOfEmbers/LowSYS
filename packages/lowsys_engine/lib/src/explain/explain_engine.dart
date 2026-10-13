import 'dart:math' as math;

import '../config/column_config.dart';
import '../control/control_system.dart';
import '../core/ids.dart';
import '../core/quantity.dart';
import '../model/tray_hydraulics.dart';
import '../faults/fault_effects.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/tier1_constant_alpha.dart';
import '../thermo/tier2_raoult.dart';
import 'explain_t2.dart';
import 'explain_types.dart';

/// Number as TeX: 4 significant figures, scientific notation outside [1e-3, 1e5) (ENGINE_API.md 8.2).
String texNum(double v) {
  if (v.isNaN) return r'\mathrm{NaN}';
  if (v.isInfinite) return v > 0 ? r'\infty' : r'-\infty';
  if (v == 0) return '0';
  final a = v.abs();
  if (a >= 1e5 || a < 1e-3) {
    var e = (math.log(a) / math.ln10).floor();
    var m = v / math.pow(10, e);
    if (m.abs() >= 9.9995) {
      m /= 10;
      e += 1;
    }
    return '${m.toStringAsPrecision(4)}\\times10^{$e}';
  }
  return Fmt.sig(v, 4);
}

/// Builds the equation trace from a snapshot and the hydraulic arrays of the same state. Every
/// [EquationLine.value] is read from the same arrays the snapshot is built from (VC-21).
class ExplainEngine {
  final ColumnConfig config;
  final SimSnapshot snapshot;
  final HydraulicSolver hyd;
  final EffectiveParams ep;
  final Tier1ConstantAlpha thermo;
  final ControlSystem control;
  final bool full;

  /// The Tier-2 model while the column runs Tier 2 (equation lines then follow PHYSICS.md 3.2, 4.6, 7, 8.2).
  final Tier2Raoult? t2;

  ExplainEngine({
    this.t2,
    required this.config,
    required this.snapshot,
    required this.hyd,
    required this.ep,
    required this.thermo,
    required this.control,
    required this.full,
  });

  StageArrays get st => snapshot.stages;
  int get nc => st.nc;
  int get nTrays => snapshot.layout.nTrays;

  static const _noteCmo =
      'Tier 1 uses constant molar overflow: vapour flow changes only where feed vapour enters. Real columns have different latent heats (Tier 2).';
  static const _noteIdeal =
      'Hydraulics are ideal: only the Bennett weir relation is used; no pressure drop, entrainment, weeping or downcomer limit.';
  static const _noteMixed =
      'Trays are perfectly mixed stages; the Murphree efficiency lumps everything that is not equilibrium.';
  static const _noteBennett =
      'Bennett\'s correlation was fitted to air-water data; it sets the liquid residence time (seconds), not a design number.';

  ExplainResult explain(ExplainTarget t) {
    switch (t) {
      case ExplainStage():
        return _stage(t.stage);
      case ExplainStream():
        return _stream(t.stream);
      case ExplainCondenser():
        return _drum();
      case ExplainReboiler():
        return _sump();
      case ExplainFeed():
        return _feed();
      case ExplainLoop():
        return _loop(t.tag);
      case ExplainMcCabe():
        return _mccabe(t.element);
      case ExplainInstrument():
        return _instrument(t.tag);
      case ExplainValve():
        return _valve(t.valveId);
      case ExplainCheck():
        return _check(t.checkId);
    }
  }

  ExplainResult _instrument(String tag) {
    final r = snapshot.instruments.firstWhere((x) => x.tag == tag,
        orElse: () => throw ArgumentError('No instrument $tag'));
    final lines = <EquationLine>[
      EquationLine(
        id: 'eq.instrument',
        physicsRef: 'PHYSICS.md (10.5)',
        texSymbolic: r'v_{meas} = lo + \frac{I_q - 4}{16}\,(hi - lo)',
        texSubstituted: r.milliamps.isNaN
            ? 'v_{meas} = ${texNum(r.value)}'
            : 'v_{meas} = ${texNum(r.lo)} + '
                r'\frac{'
                '${texNum(r.milliamps)}'
                r' - 4}{16}\,('
                '${texNum(r.hi)} - ${texNum(r.lo)}) = ${texNum(r.value)}',
        value: r.value,
        quantity: r.quantity,
        note: r.qualityText == null
            ? 'Quality ${r.quality.name}.'
            : 'Quality ${r.quality.name} (${r.qualityText}).',
      ),
      if (r.resultAge != null)
        EquationLine(
          id: 'eq.analyser',
          physicsRef: 'PHYSICS.md (10.5)',
          texSymbolic: r'\text{age} = t - t_{sample}',
          texSubstituted:
              r'\text{age} = ' '${texNum(r.resultAge!)}' r'\ \mathrm{s}',
          value: r.resultAge!,
          quantity: Quantity.time,
          note: 'A displayed analysis is 300-600 s old.',
        ),
    ];
    return ExplainResult(
        title: 'Instrument $tag',
        groups: [EquationGroup('Signal chain', lines)],
        notes: const [
          'Noise, damping, impulse line and calibration are modelled per PHYSICS.md 10.5.'
        ],
        time: snapshot.time);
  }

  ExplainResult _valve(String id) {
    final v = snapshot.valves.firstWhere((x) => x.id == id,
        orElse: () => throw ArgumentError('No valve $id'));
    return ExplainResult(
      title: 'Valve $id',
      groups: [
        EquationGroup('Valve', [
          EquationLine(
            id: 'eq.valve',
            physicsRef: 'PHYSICS.md (10.2)',
            texSymbolic: r'F = F_{max}\,g(OP)\,(1+d)',
            texSubstituted: 'F_{expected} = ${texNum(v.fMax)}'
                r'\times'
                '${texNum(v.op / 100)} = ${texNum(v.expectedFlow)}'
                r'\ \mathrm{mol/s}',
            value: v.expectedFlow,
            quantity: Quantity.molarFlow,
            note:
                'The control system sees OP only; there is no position feedback.',
          ),
        ]),
      ],
      notes: const [],
      time: snapshot.time,
    );
  }

  ExplainResult _check(String id) {
    final c = snapshot.crossChecks.firstWhere((x) => x.id == id,
        orElse: () => throw ArgumentError('No check $id'));
    final eqId = switch (c.id.split(':').first) {
      'C1' => 'eq.check.material',
      'C2' => 'eq.check.component',
      'C3' || 'C3a' => 'eq.check.topVapour',
      'C3b' => 'eq.check.energy',
      'C6' => 'eq.check.trayT',
      'C7' => 'eq.check.bubble',
      'C4' => 'eq.check.valve',
      'C5' => 'eq.check.level',
      _ => 'eq.check.material',
    };
    final terms = c.terms.entries
        .map((e) => '\\text{${e.key}} = ${texNum(e.value)}')
        .join(',\\ ');
    return ExplainResult(
      title: 'Check ${c.id}',
      groups: [
        EquationGroup('Residual', [
          EquationLine(
            id: eqId,
            physicsRef: 'PHYSICS.md 14.6',
            texSymbolic: r'r = \text{measured} - \text{predicted}',
            texSubstituted: c.status == CheckStatus.notAvailable
                ? r'\text{not available}'
                : '$terms;'
                    r'\ r = '
                    '${texNum(c.residual)},'
                    r'\ \text{band} = '
                    '${texNum(c.band)}',
            value: c.residual,
            note: c.reason,
          ),
        ]),
      ],
      notes: const [
        'Computed from instrument readings only, so it works in plant view.'
      ],
      time: snapshot.time,
    );
  }

  // ------------------------------------------------------------------ stage

  ExplainResult _stage(int j) {
    final N = nTrays;
    if (j == 0) return _drum();
    if (j == N + 1) return _sump();
    final feed = snapshot.layout.feedStages.first;
    final section = j == feed
        ? 'feed tray'
        : (j < feed ? 'rectifying section' : 'stripping section');
    final groups = <EquationGroup>[];
    final x = st.xAt(j, 0), y = st.yAt(j, 0), ys = st.yStarAt(j, 0);
    final L = st.liquidDown[j], V = st.vaporUp[j], vBelow = st.vaporUp[j + 1];
    final yb = st.yAt(j + 1, 0);
    final E = st.efficiency[j];
    final alpha = thermo.alpha[0] / thermo.alpha[1];
    final light = snapshot.components.first;

    // --- material balance of the light component (4.1)
    final e = st.entrain[j];
    final eNext = j + 1 <= N ? st.entrain[j + 1] : 0.0;
    final fj = full ? hyd.bypass[j] : 0.0;
    final fPrev = j >= 2 && full ? hyd.bypass[j - 1] : 0.0;
    final lUp = st.liquidDown[j - 1];
    final xUp = st.xAt(j - 1, 0);
    final lUp2 = j >= 2 ? st.liquidDown[j - 2] : 0.0;
    final xUp2 = j >= 2 ? st.xAt(j - 2, 0) : 0.0;
    final xDn = st.xAt(j + 1, 0);
    final fFeed = j == feed ? snapshot.streams[StreamId.feed]!.flow : 0.0;
    final zF = snapshot.streams[StreamId.feed]!.composition[0];
    final inflow = (1 - fj) * lUp * xUp +
        fPrev * lUp2 * xUp2 +
        vBelow * yb +
        eNext * xDn +
        fFeed * zF;
    final outflow = (L + e) * x + V * y;
    final dmdt = inflow - outflow;
    groups.add(EquationGroup('Material balance', [
      EquationLine(
        id: 'eq.componentBalance',
        physicsRef: 'PHYSICS.md (4.1)',
        texSymbolic:
            r'\frac{dm_{i,j}}{dt} = (1-f_j)L_{j-1}x_{i,j-1} + f_{j-1}L_{j-2}x_{i,j-2} + V_{j+1}y_{i,j+1} + e_{j+1}x_{i,j+1} + F_j z_i - (L_j+e_j)x_{i,j} - V_j y_{i,j}',
        texSubstituted:
            'm_{$light} \\text{ rate} = ${texNum((1 - fj) * lUp * xUp)} + ${texNum(fPrev * lUp2 * xUp2)} + ${texNum(vBelow * yb)} + ${texNum(eNext * xDn)} + ${texNum(fFeed * zF)} - ${texNum((L + e) * x)} - ${texNum(V * y)} = ${texNum(dmdt)}\\ \\mathrm{mol/s}',
        value: dmdt,
        note: 'Light component ($light); mol/s. Zero at steady state.',
      ),
    ]));

    // --- equilibrium and Murphree (3.1, 4.2)
    final tier2 = t2 != null && snapshot.tier != ThermoTier.t1;
    final t2Lines = tier2 ? ExplainT2(snapshot, t2!).stageLines(j) : const <EquationLine>[];
    groups.add(EquationGroup('Equilibrium and efficiency', [
      if (tier2) t2Lines[0],
      if (!tier2) EquationLine(
        id: 'eq.equilibrium.T1',
        physicsRef: 'PHYSICS.md (3.1)',
        texSymbolic: r'y^*_j = \frac{\alpha x_j}{1 + (\alpha-1)x_j}',
        texSubstituted:
            'y^*_{$j} = \\frac{${texNum(alpha)}\\times${texNum(x)}}{1 + (${texNum(alpha)}-1)\\times${texNum(x)}} = ${texNum(ys)}',
        value: ys,
        note: 'Constant relative volatility; no temperature in Tier 1.',
      ),
      EquationLine(
        id: 'eq.murphree',
        physicsRef: 'PHYSICS.md (4.2)',
        texSymbolic: r'y_j = y_{j+1} + E_j\,(y^*_j - y_{j+1})',
        texSubstituted:
            'y_{$j} = ${texNum(yb)} + ${texNum(E)}\\,(${texNum(ys)} - ${texNum(yb)}) = ${texNum(y)}',
        value: y,
        note:
            'Murphree vapour efficiency, including the dry-tray factor min(1, h_cl / 5 mm).',
      ),
      if (tier2) t2Lines[1],
      if (!tier2) EquationLine(
        id: 'eq.vapourFlow.cmo',
        physicsRef: 'PHYSICS.md (4.5)',
        texSymbolic: r'V_j = V_{j+1} + (1-q_j)F_j',
        texSubstituted:
            'V_{$j} = ${texNum(vBelow)} + (1-${texNum(snapshot.feedQ)})\\times${texNum(fFeed)} = ${texNum(V)}\\ \\mathrm{mol/s}',
        value: V,
        quantity: Quantity.molarFlow,
      ),
    ]));

    // --- hydraulics
    final hl = <EquationLine>[];
    final vl =
        (st.holdup[j] > 0) ? st.hcl[j] * hyd.aAct[j] / st.holdup[j] : 0.0;
    if (full) {
      hl.addAll([
        EquationLine(
          id: 'eq.bennett',
          physicsRef: 'PHYSICS.md (5.2)',
          texSymbolic:
              r'h_{cl} = \frac{M_j v_L}{A_a},\quad \alpha_e = e^{-12.55K_s^{0.91}},\quad K_s = U_s\sqrt{\rho_V/(\rho_L-\rho_V)}',
          texSubstituted:
              'h_{cl} = \\frac{${texNum(st.holdup[j])}\\times${texNum(vl)}}{${texNum(hyd.aAct[j])}} = ${texNum(st.hcl[j])}\\ \\mathrm{m},\\ K_s = ${texNum(hyd.ks[j])},\\ \\alpha_e = ${texNum(hyd.alphaE[j])}',
          value: st.hcl[j],
          quantity: Quantity.smallLength,
          note:
              'Clear-liquid height from the holdup; froth height ${texNum(st.froth[j])} m.',
        ),
        EquationLine(
          id: 'eq.dryDP',
          physicsRef: hyd.trayType.name == 'valve'
              ? 'PHYSICS.md (5.4)'
              : 'PHYSICS.md (5.3)',
          texSymbolic: hyd.trayType.name == 'valve'
              ? r'\Delta P_{dry} = \max\!\big(\text{closed, balancing } \Delta P_{lift}, \text{open}\big)'
              : r'\Delta P_{dry} = \frac{\rho_V}{2}\left(\frac{u_h}{C_0}\right)^2,\quad u_h = \frac{Q_{in}}{A_{h,eff}}',
          texSubstituted:
              'u_h = ${texNum(hyd.uh[j])}\\ \\mathrm{m/s}\\Rightarrow \\Delta P_{dry} = ${texNum(st.dpDry[j])}\\ \\mathrm{Pa}',
          value: st.dpDry[j],
          quantity: Quantity.pressureDelta,
        ),
        EquationLine(
          id: 'eq.trayDP',
          physicsRef: 'PHYSICS.md (5.5)',
          texSymbolic:
              r'\Delta P_j = \Delta P_{dry} + \rho_L g\,h_{cl} + \frac{4\sigma}{d_h}',
          texSubstituted:
              '\\Delta P_{$j} = ${texNum(st.dpDry[j])} + ${texNum(hyd.rhoL * 9.80665 * st.hcl[j])} + ${texNum(st.dp[j] - st.dpDry[j] - hyd.rhoL * 9.80665 * st.hcl[j])} = ${texNum(st.dp[j])}\\ \\mathrm{Pa}',
          value: st.dp[j],
          quantity: Quantity.pressureDelta,
        ),
        EquationLine(
          id: 'eq.jetFlood',
          physicsRef: 'PHYSICS.md (5.5)',
          texSymbolic:
              r'\varphi_j = \frac{Q_{out}/A_n}{U_{nf}},\quad U_{nf} = C_{SB}\left(\frac{\sigma}{0.02}\right)^{0.2}\sqrt{\frac{\rho_L-\rho_V}{\rho_V}}\,SF\,f_{hole}',
          texSubstituted:
              'F_{LV} = ${texNum(hyd.fLV[j])},\\ C_{SB} = ${texNum(hyd.csb[j])},\\ U_{nf} = ${texNum(hyd.unf[j])}\\ \\mathrm{m/s},\\ \\varphi_{$j} = \\frac{${texNum(hyd.qOut[j] / hyd.d.aN)}}{${texNum(hyd.unf[j])}} = ${texNum(st.jetFlood[j])}',
          value: st.jetFlood[j],
          note:
              'Fractional approach to jet flood (Fair, Lygeros-Magoulas fit).',
        ),
        EquationLine(
          id: 'eq.entrainment',
          physicsRef: 'PHYSICS.md (5.7, 5.8)',
          texSymbolic:
              r'\psi_{eq} = \min\!\big(0.6,\ 4\times10^{-5}(F_{LV}/0.1)^{-0.83}e^{7.5\varphi}\big),\quad e_j = \frac{\psi}{1-\psi}L_j + e_{ov}',
          texSubstituted:
              '\\psi_{eq} = ${texNum(hyd.psiEq[j])},\\ e_{$j} = ${texNum(st.entrain[j])}\\ \\mathrm{mol/s}',
          value: st.entrain[j],
          quantity: Quantity.molarFlow,
          note:
              'Entrained liquid is carried to the tray above; the separation loss is emergent.',
        ),
        EquationLine(
          id: 'eq.downcomer',
          physicsRef: 'PHYSICS.md (5.10, 5.11)',
          texSymbolic:
              r'h_{dc} = \frac{\Delta P_j}{\rho_L g} + h_{norm,j+1} + 0.166\,u_{ap}^2,\quad \text{flood when } h_{dc}/\phi_{dc} \ge TS + h_w',
          texSubstituted:
              'h_{dc} = ${texNum(hyd.hDc[j])}\\ \\mathrm{m}\\ \\Rightarrow\\ ${texNum(100 * st.dcFlood[j])}\\ \\%\\ \\text{of the limit}',
          value: st.dcFlood[j],
          note: 'Downcomer backup as a fraction of its limit.',
        ),
        EquationLine(
          id: 'eq.weeping',
          physicsRef: 'PHYSICS.md (5.12-5.14)',
          texSymbolic:
              r'\Phi_j = \sqrt{h_{dry}/h_{cl}},\quad w_j = \mathrm{clamp}\big((0.75-\Phi_j)/0.55,\,0,\,1\big)',
          texSubstituted:
              '\\Phi_{$j} = ${texNum(st.stability[j])}\\ \\Rightarrow\\ w_{$j} = ${texNum(st.weepFrac[j])}',
          value: st.weepFrac[j],
          note: 'Fraction of the inlet liquid that falls through the deck.',
        ),
      ]);
      groups.add(EquationGroup('Tray hydraulics', hl));
    } else {
      groups.add(EquationGroup('Tray hydraulics (ideal)', [
        EquationLine(
          id: 'eq.bennett',
          physicsRef: 'PHYSICS.md (5.2)',
          texSymbolic:
              r'q_w = L_w\,\alpha_e\left[\frac{h_{cl}/\alpha_e - h_w}{C}\right]^{1.5}',
          texSubstituted:
              'h_{cl} = ${texNum(st.hcl[j])}\\ \\mathrm{m},\\ \\alpha_e = ${texNum(st.froth[j] > 0 ? st.hcl[j] / st.froth[j] : 1)},\\ L_j = ${texNum(L)}\\ \\mathrm{mol/s}',
          value: st.hcl[j],
          quantity: Quantity.smallLength,
        ),
      ]));
    }
    final notes = <String>[
      if (tier2)
        'Tier 2: ideal vapour-liquid equilibrium (Raoult) with enthalpy balances on every tray; the vapour flow is not constant.'
      else
        _noteCmo,
      _noteMixed,
      if (full) _noteBennett else _noteIdeal
    ];
    return ExplainResult(
        title: 'Tray $j ($section)',
        groups: groups,
        notes: notes,
        time: snapshot.time);
  }

  // ------------------------------------------------------------------ drum, sump, feed, streams

  ExplainResult _drum() {
    if (t2 != null && snapshot.tier != ThermoTier.t1 && snapshot.condenser != null) {
      return ExplainT2(snapshot, t2!).drum();
    }
    final k = snapshot.kpis;
    final v1 = st.vaporUp[1];
    final e1 = st.entrain[1];
    final l0 = snapshot.streams[StreamId.reflux]!.flow;
    final d = k.d;
    final net = v1 + e1 - l0 - d;
    return ExplainResult(
      title: 'Condenser and reflux drum',
      groups: [
        EquationGroup('Drum', [
          EquationLine(
            id: 'eq.drumBalance',
            physicsRef: 'PHYSICS.md (7.6, 12.2)',
            texSymbolic: r'\frac{dM_0}{dt} = V_1 + e_1 - L_0 - D',
            texSubstituted:
                '\\frac{dM_0}{dt} = ${texNum(v1)} + ${texNum(e1)} - ${texNum(l0)} - ${texNum(d)} = ${texNum(net)}\\ \\mathrm{mol/s}',
            value: net,
            quantity: Quantity.molarFlow,
            note:
                'Total condenser: all overhead vapour condenses (Tier 1 has no pressure or duty).',
          ),
          EquationLine(
            id: 'eq.drumLevel',
            physicsRef: 'PHYSICS.md (7.3)',
            texSymbolic: r'\text{level} = 100\,M_0 v_L / V_{drum}',
            texSubstituted: '\\text{level} = ${texNum(k.drumLevelPct)}\\ \\%',
            value: k.drumLevelPct,
            quantity: Quantity.percent,
          ),
        ]),
      ],
      notes: const [
        'The level controller LC-101 moves the distillate valve to hold the drum level (PI, Kc 2, Ti 1800 s).'
      ],
      time: snapshot.time,
    );
  }

  ExplainResult _sump() {
    if (t2 != null && snapshot.tier != ThermoTier.t1) {
      return ExplainT2(snapshot, t2!).sump();
    }
    final k = snapshot.kpis;
    final N = nTrays;
    final lN = st.liquidDown[N];
    final vB = st.vaporUp[N + 1];
    final b = k.b;
    final net = lN - vB - b;
    return ExplainResult(
      title: 'Sump and reboiler',
      groups: [
        EquationGroup('Sump', [
          EquationLine(
            id: 'eq.boilup',
            physicsRef: 'PHYSICS.md (4.4, 8.1)',
            texSymbolic:
                r'V_{N+1} = V_B\, s_{sump},\quad \frac{dM_{N+1}}{dt} = L_N - V_{N+1} - B',
            texSubstituted:
                'V_{N+1} = ${texNum(vB)},\\ \\frac{dM_{N+1}}{dt} = ${texNum(lN)} - ${texNum(vB)} - ${texNum(b)} = ${texNum(net)}\\ \\mathrm{mol/s}',
            value: vB,
            quantity: Quantity.molarFlow,
            note:
                'Tier 1: the boilup lever is used directly; heat transfer limits do not apply.',
          ),
        ]),
      ],
      notes: const [
        'The sump is an equilibrium stage (E = 1). Starvation factor s_sump drops below 1 only when the sump runs nearly dry.'
      ],
      time: snapshot.time,
    );
  }

  ExplainResult _feed() {
    if (t2 != null && snapshot.tier != ThermoTier.t1) {
      return ExplainT2(snapshot, t2!).feed();
    }
    final f = snapshot.streams[StreamId.feed]!;
    final q = snapshot.feedQ;
    final fs = snapshot.layout.feedStages.first;
    return ExplainResult(
      title: 'Feed (tray $fs)',
      groups: [
        EquationGroup('Thermal condition', [
          EquationLine(
            id: 'eq.qValue',
            physicsRef: 'PHYSICS.md (4.5)',
            texSymbolic:
                r'q = \text{liquid fraction of the feed},\quad V_{j} - V_{j+1} = (1-q)F',
            texSubstituted:
                'q = ${texNum(q)},\\ (1-q)F = ${texNum((1 - q) * f.flow)}\\ \\mathrm{mol/s}',
            value: q,
            note:
                'q > 1 subcooled, q = 1 saturated liquid, q < 0 superheated vapour.',
          ),
        ]),
      ],
      notes: const [_noteCmo],
      time: snapshot.time,
    );
  }

  ExplainResult _stream(StreamId id) {
    final k = snapshot.kpis;
    final f = snapshot.streams[StreamId.feed]!;
    final zF = f.composition[0];
    final line = EquationLine(
      id: 'eq.overallBalance',
      physicsRef: 'PHYSICS.md (14.1)',
      texSymbolic: r'F z = D x_D + B x_B',
      texSubstituted:
          '${texNum(f.flow)}\\times${texNum(zF)} = ${texNum(k.d)}\\times${texNum(k.xD)} + ${texNum(k.b)}\\times${texNum(k.xB)}\\quad(\\text{residual }${texNum(k.balanceResidual)})',
      value: k.balanceResidual,
      note:
          'Live relative residual of the light-component balance; zero at steady state.',
    );
    final s = snapshot.streams[id]!;
    final comp = EquationLine(
      id: 'eq.streamComposition',
      physicsRef: 'PHYSICS.md (12.3)',
      texSymbolic: r'x_{light} \text{ and flow}',
      texSubstituted:
          'x = ${texNum(s.composition[0])},\\ \\text{flow} = ${texNum(s.flow)}\\ \\mathrm{mol/s}',
      value: s.flow,
      quantity: Quantity.molarFlow,
    );
    final names = {
      StreamId.feed: 'Feed',
      StreamId.reflux: 'Reflux',
      StreamId.distillate: 'Distillate D',
      StreamId.bottoms: 'Bottoms B',
      StreamId.boilup: 'Boilup',
      StreamId.vaporProduct: 'Vapour product',
    };
    return ExplainResult(
      title: names[id]!,
      groups: [
        EquationGroup('Stream', [comp]),
        EquationGroup('Overall balance', [line]),
      ],
      notes: const [
        'Product flows come from the level controllers, so the balance closes at steady state, not at every instant.'
      ],
      time: snapshot.time,
    );
  }

  ExplainResult _loop(String tag) {
    final l = control.loop(tag);
    final pv = snapshot.loops.firstWhere((x) => x.tag == tag).pv;
    final e = l.params.action == Action.direct ? pv - l.sp : l.sp - pv;
    return ExplainResult(
      title: 'Controller $tag',
      groups: [
        EquationGroup('PID, velocity form', [
          EquationLine(
            id: 'eq.pid',
            physicsRef: 'PHYSICS.md (10.1)',
            texSymbolic:
                r'\Delta OP_k = K_c\Big[(e_k-e_{k-1}) + \frac{\Delta t}{T_i}e_k\Big],\quad OP_k = \mathrm{clamp}(OP_{k-1}+\Delta OP_k,0,100)',
            texSubstituted:
                'K_c = ${texNum(l.params.kc)},\\ T_i = ${texNum(l.params.ti)}\\ \\mathrm{s},\\ e = ${texNum(e)}\\ \\%,\\ OP = ${texNum(l.op)}\\ \\%',
            value: l.op,
            quantity: Quantity.percent,
          ),
        ]),
      ],
      notes: const [
        'Level loops are tuned for averaging: they absorb flow upsets instead of passing them on.'
      ],
      time: snapshot.time,
    );
  }

  ExplainResult _mccabe(McCabeElement el) {
    final k = snapshot.kpis;
    final l0 = snapshot.streams[StreamId.reflux]!.flow;
    final d = k.d;
    final v1 = l0 + d;
    final slope = v1 > 0 ? l0 / v1 : 1.0;
    final q = snapshot.feedQ;
    final lines = <EquationLine>[];
    switch (el) {
      case McCabeElement.opLine:
        lines.add(EquationLine(
          id: 'eq.operatingLine',
          physicsRef: 'PHYSICS.md (14.1)',
          texSymbolic: r'y = \frac{L_0}{V_1}x + \frac{D x_D}{V_1}',
          texSubstituted:
              'y = ${texNum(slope)}\\,x + ${texNum(v1 > 0 ? d * k.xD / v1 : 0)}',
          value: slope,
        ));
      case McCabeElement.qLine:
        lines.add(EquationLine(
          id: 'eq.qLine',
          physicsRef: 'PHYSICS.md (14.1)',
          texSymbolic: r'y = \frac{q}{q-1}\,x - \frac{z}{q-1}',
          texSubstituted: q == 1
              ? r'x = z\ (\text{vertical, saturated liquid})'
              : 'y = ${texNum(q / (q - 1))}\\,x',
          value: q,
        ));
      case McCabeElement.rmin:
        final z = snapshot.streams[StreamId.feed]!.composition[0];
        final a = thermo.alpha[0] / thermo.alpha[1];
        final rm = (k.xD - (a * z / (1 + (a - 1) * z))) /
            ((a * z / (1 + (a - 1) * z)) - z);
        lines.add(EquationLine(
          id: 'eq.rmin',
          physicsRef: 'PHYSICS.md (14.1)',
          texSymbolic:
              r'\frac{R_{min}}{R_{min}+1} = \frac{x_D - y^*}{x_D - x^*}',
          texSubstituted: 'R_{min} = ${texNum(rm)}',
          value: rm,
        ));
      case McCabeElement.equilibrium:
        lines.add(EquationLine(
          id: 'eq.equilibrium.T1',
          physicsRef: 'PHYSICS.md (3.1)',
          texSymbolic: r'y^* = \frac{\alpha x}{1+(\alpha-1)x}',
          texSubstituted:
              '\\alpha = ${texNum(thermo.alpha[0] / thermo.alpha[1])}',
          value: thermo.alpha[0] / thermo.alpha[1],
        ));
    }
    return ExplainResult(
      title: 'McCabe-Thiele: ${el.name}',
      groups: [EquationGroup('Construction', lines)],
      notes: const [_noteCmo],
      time: snapshot.time,
    );
  }
}
