import 'dart:typed_data';

import '../core/quantity.dart';
import '../snapshot/sim_snapshot.dart';
import '../thermo/tier2_raoult.dart';
import 'explain_engine.dart' show texNum;
import 'explain_types.dart';

/// Tier 2 equation traces (PHYSICS.md 3.2, 3.14, 3.15, 4.6, 4.7, 7.1, 7.3, 7.4, 8.2; PHYSICS.md 15 ids). Every value is read from the
/// snapshot of the same state, so the overlay agrees with the simulation (VALIDATION.md VC-21).
class ExplainT2 {
  final SimSnapshot snap;
  final Tier2Raoult th;
  ExplainT2(this.snap, this.th);

  StageArrays get st => snap.stages;
  int get nc => st.nc;
  int get n => snap.layout.nTrays;

  Float64List _row(Float64List a, int j) =>
      Float64List.fromList([for (var i = 0; i < nc; i++) a[j * nc + i]]);

  double _hL(int j) => th.hL(st.t[j], _row(st.x, j));
  double _hV(int j) => th.hV(st.t[j], _row(st.y, j));

  /// Raoult equilibrium and the energy-balance vapour flow of tray [j].
  List<EquationLine> stageLines(int j) {
    final x = _row(st.x, j);
    final k = Float64List(nc);
    th.kValues(st.t[j], st.p[j], x, k);
    var s = 0.0;
    for (var i = 0; i < nc; i++) {
      s += k[i] * x[i];
    }
    final ys = st.yStar[j * nc];
    final v = st.vaporUp[j];
    final hj = _hL(j), hVj = _hV(j);
    final lUp = st.liquidDown[j - 1], vBelow = st.vaporUp[j + 1];
    final hUp = j == 1
        ? th.hL(snap.condenser!.tReflux, _row(st.x, 0))
        : _hL(j - 1);
    final hVb = _hV(j + 1);
    final fs = snap.layout.feedStages.first;
    final feed = snap.streams[StreamId.feed]!;
    final hF = th.feedEnthalpy(feed.temperature, st.p[fs], feed.composition);
    final fF = j == fs ? feed.flow : 0.0;
    final num = lUp * (hUp - hj) + vBelow * (hVb - hj) + fF * (hF - hj);
    return [
      EquationLine(
        id: 'eq.equilibrium.T2',
        physicsRef: 'PHYSICS.md (3.2, 4.2)',
        texSymbolic:
            r'K_i = \frac{P_i^{sat}(T_j)}{P_j},\quad y^*_i = \frac{K_i x_i}{\sum_k K_k x_k}',
        texSubstituted:
            'T_{$j} = ${texNum(st.t[j])}\\ \\mathrm{K},\\ P_{$j} = ${texNum(st.p[j])}\\ \\mathrm{Pa},\\ K_1 = ${texNum(k[0])},\\ \\sum K x = ${texNum(s)},\\ y^*_1 = ${texNum(ys)}',
        value: ys,
        note:
            'Raoult\'s law with the stage temperature from the bubble point (PHYSICS.md 3.6.1).',
      ),
      EquationLine(
        id: 'eq.vapourFlow.energy',
        physicsRef: 'PHYSICS.md (4.6)',
        texSymbolic:
            r'V_j = \frac{L_{j-1}(h_{j-1}-h_j) + V_{j+1}(H_{j+1}-h_j) + F_j(h_F-h_j) - C_j\tau_j\,\Delta P/\Delta t}{H_j - h_j}',
        texSubstituted:
            'V_{$j} = \\frac{${texNum(num)}\\ \\mathrm{W}}{${texNum(hVj - hj)}\\ \\mathrm{J/mol}} = ${texNum(v)}\\ \\mathrm{mol/s}',
        value: v,
        quantity: Quantity.molarFlow,
        note:
            'Quasi-steady energy balance: the vapour flow follows from the enthalpies, so it is not constant down the column. The storage term is zero at steady state.',
      ),
    ];
  }

  ExplainResult drum() {
    final c = snap.condenser!;
    final k = snap.kpis;
    final v1 = st.vaporUp[1];
    final l0 = snap.streams[StreamId.reflux]!.flow;
    final net = c.nCond + st.entrain[1] - l0 - k.d;
    final lines = <EquationLine>[
      EquationLine(
        id: 'eq.condenserDuty',
        physicsRef: 'PHYSICS.md (7.3)',
        texSymbolic:
            r'Q_C = \frac{UA_{eff}\,(T_{0,sat}-T_{cw,in})}{1 + UA_{eff}/(2\,\dot m_{cw}c_{p,w})}',
        texSubstituted:
            'UA_{eff} = ${texNum(c.uaEff)}\\ \\mathrm{W/K},\\ T_{0,sat} = ${texNum(c.tCond)}\\ \\mathrm{K},\\ T_{cw,in} = ${texNum(c.tCwIn)}\\ \\mathrm{K},\\ \\dot m_{cw} = ${texNum(c.cwFlow)}\\ \\mathrm{kg/s} \\Rightarrow Q_C = ${texNum(c.qC)}\\ \\mathrm{W}',
        value: c.qC,
        quantity: Quantity.energyRate,
        note:
            'The water outlet is ${texNum(c.tCwOut)} K; inerts lower the condensing temperature and blanket the tubes.',
      ),
      EquationLine(
        id: 'eq.condensation',
        physicsRef: 'PHYSICS.md (7.4)',
        texSymbolic:
            r'N_{cond} = \frac{V_1\,(H_V(y_1,T_{0,sat}) - H_1) + Q_C}{H_V(y_1,T_{0,sat}) - h_L(x_0,T_0)}',
        texSubstituted:
            'V_1 = ${texNum(v1)},\\ Q_C = ${texNum(c.qC)}\\ \\mathrm{W} \\Rightarrow N_{cond} = ${texNum(c.nCond)}\\ \\mathrm{mol/s}',
        value: c.nCond,
        quantity: Quantity.molarFlow,
      ),
      EquationLine(
        id: 'eq.overheadPressure',
        physicsRef: 'PHYSICS.md (7.1, 7.4)',
        texSymbolic:
            r'P_{top} = \frac{(n_V + n_I)\,R\,T_0}{V_{ovh}},\quad \frac{dn_V}{dt} = V_1 - N_{cond} - D_V - N_{vent}(1-y_I) - N_{relief}(1-y_I)',
        texSubstituted:
            'n_V = ${texNum(c.vaporMoles)}\\ \\mathrm{mol},\\ y_I = ${texNum(c.inertFraction)},\\ P_{top} = ${texNum(k.pTop)}\\ \\mathrm{Pa},\\ \\text{vent } ${texNum(c.nVent)},\\ \\text{relief } ${texNum(c.nRelief)}\\ \\mathrm{mol/s}',
        value: k.pTop,
        quantity: Quantity.pressure,
        note: 'The pressure is solved implicitly each step together with the column\'s heat storage.',
      ),
      EquationLine(
        id: 'eq.drumBalance',
        physicsRef: 'PHYSICS.md (7.6)',
        texSymbolic: r'\frac{dM_0}{dt} = N_{cond} + e_1 - L_0 - D',
        texSubstituted:
            '\\frac{dM_0}{dt} = ${texNum(c.nCond)} + ${texNum(st.entrain[1])} - ${texNum(l0)} - ${texNum(k.d)} = ${texNum(net)}\\ \\mathrm{mol/s}',
        value: net,
        quantity: Quantity.molarFlow,
      ),
    ];
    return ExplainResult(
      title: 'Condenser and reflux drum',
      groups: [EquationGroup('Condenser, overhead and drum', lines)],
      notes: const [
        'The condenser is limited by its heat-transfer area and the cooling water, so the pressure floats until the duty balances the vapour load (Tier 2).'
      ],
      time: snap.time,
    );
  }

  ExplainResult sump() {
    final r = snap.reboiler;
    final k = snap.kpis;
    final nT = n;
    final vB = st.vaporUp[nT + 1];
    final lN = st.liquidDown[nT];
    final b = k.b;
    final hB = _hL(nT + 1), hVB = _hV(nT + 1);
    return ExplainResult(
      title: 'Sump and reboiler',
      groups: [
        EquationGroup('Kettle reboiler', [
          EquationLine(
            id: 'eq.kettleDuty',
            physicsRef: 'PHYSICS.md (8.2, 10.3)',
            texSymbolic:
                r'Q_{max} = UA_{R,eff}(T_{st}-T_{N+1}),\quad Q_R = \min(Q_v,\ Q_{max})',
            texSubstituted:
                'UA_{R,eff} = ${texNum(r.uaEff)}\\ \\mathrm{W/K},\\ T_{st} = ${texNum(r.steamT)}\\ \\mathrm{K},\\ T_{N+1} = ${texNum(r.tSump)}\\ \\mathrm{K} \\Rightarrow Q_{max} = ${texNum(r.qMax)}\\ \\mathrm{W},\\ Q_R = ${texNum(r.qDelivered)}\\ \\mathrm{W}',
            value: r.qDelivered,
            quantity: Quantity.energyRate,
            note: r.dutyLimited
                ? 'The steam valve asks for more than the exchanger can transfer: the duty is limited.'
                : 'The steam valve FV-103 delivers duty; FC-103 positions it on the measured duty.',
          ),
          EquationLine(
            id: 'eq.boilup',
            physicsRef: 'PHYSICS.md (4.7)',
            texSymbolic:
                r'V_B = s_{sump}\,\frac{L_N(h_N-h_B) + Q_R - C_B\tau\,\Delta P/\Delta t}{H_B - h_B}',
            texSubstituted:
                'V_B = ${texNum(vB)}\\ \\mathrm{mol/s}\\ (H_B - h_B = ${texNum(hVB - hB)}\\ \\mathrm{J/mol},\\ L_N = ${texNum(lN)},\\ B = ${texNum(b)}\\ \\mathrm{mol/s})',
            value: vB,
            quantity: Quantity.molarFlow,
          ),
        ]),
      ],
      notes: const [
        'The sump is an equilibrium stage; the boilup is the heat delivered divided by the latent heat of the bottoms.'
      ],
      time: snap.time,
    );
  }

  ExplainResult feed() {
    final f = snap.streams[StreamId.feed]!;
    final fs = snap.layout.feedStages.first;
    final p = st.p[fs];
    final z = f.composition;
    double beta = double.nan;
    try {
      beta = th.flashTP(f.temperature, p, z).beta;
    } catch (_) {}
    return ExplainResult(
      title: 'Feed (tray $fs)',
      groups: [
        EquationGroup('Thermal condition', [
          EquationLine(
            id: 'eq.flash',
            physicsRef: 'PHYSICS.md (3.14)',
            texSymbolic:
                r'\sum_i \frac{z_i(K_i-1)}{1+\beta(K_i-1)} = 0',
            texSubstituted:
                'T_F = ${texNum(f.temperature)}\\ \\mathrm{K},\\ P = ${texNum(p)}\\ \\mathrm{Pa} \\Rightarrow \\beta = ${texNum(beta)}',
            value: beta,
            note: 'Rachford-Rice: the vapour fraction of the feed.',
          ),
          EquationLine(
            id: 'eq.qValue',
            physicsRef: 'PHYSICS.md (3.15)',
            texSymbolic: r'q = \frac{H_{V,sat} - h_F}{H_{V,sat} - h_{L,sat}}',
            texSubstituted: 'q = ${texNum(f.q)}',
            value: f.q,
            note:
                'q > 1 subcooled liquid, q = 1 saturated liquid, 0 < q < 1 part vapour, q < 0 superheated vapour.',
          ),
        ]),
      ],
      notes: const [],
      time: snap.time,
    );
  }
}
