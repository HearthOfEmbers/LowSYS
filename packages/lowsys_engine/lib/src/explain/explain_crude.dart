// Equation traces of the crude unit (PHYSICS.md 15 crude row): eq.steamPartialPressure, eq.crudeEnthalpy, eq.stripperDraw,
// eq.paDuty, eq.crudeCondenser, eq.productTbp, eq.daubert, eq.gap, eq.overflash. Values equal the snapshot of the same state.
import '../core/quantity.dart';
import '../model/crude_column.dart';
import '../snapshot/crude_products.dart';
import 'explain_engine.dart' show texNum;
import 'explain_types.dart';

const List<String> _prodNames = ['Naphtha', 'Kerosene', 'Diesel', 'AGO', 'Residue'];

class ExplainCrude {
  final CrudeColumn col;
  final CrudeProducts prod;
  final double time;
  ExplainCrude(this.col, this.prod, this.time);

  ExplainResult explain(ExplainTarget t) {
    if (t is ExplainStage) {
      if (t.stage >= 1 && t.stage <= CrudeColumn.nm) return _stage(t.stage - 1, 'Stage ${t.stage}');
      if (t.stage == 0) return _condenser();
      return _simple('Sump', 'The sump collects the liquid of stage 30; LC-302 sets the residue flow.');
    }
    if (t is ExplainStripper) {
      final a = t.bottom ? col.s2(t.stripper) : col.s1(t.stripper);
      return _stage(a, 'Side stripper ${t.stripper + 1}, ${t.bottom ? 'bottom (boot)' : 'top'} stage', stripper: t.stripper);
    }
    if (t is ExplainCondenser) return _condenser();
    if (t is ExplainPumparound) return _pa();
    if (t is ExplainProduct) return _product(t.product);
    if (t is ExplainOverflash) return _overflash();
    return _simple('Not available', 'No equation trace for this item on the crude unit.');
  }

  ExplainResult _simple(String title, String note) =>
      ExplainResult(title: title, groups: const [], notes: [note], time: time);

  EquationLine _line(String id, String ref, String sym, String sub, double v, Quantity q, [String? note]) =>
      EquationLine(id: id, physicsRef: ref, texSymbolic: sym, texSubstituted: sub, value: v, quantity: q, note: note);

  ExplainResult _stage(int a, String title, {int? stripper}) {
    final th = col.th;
    const nc = CrudeColumn.nc;
    final p = col.p[a], yw = col.ywF[a], tK = col.t[a];
    final pHc = p * (1 - yw);
    var lnSum = 0.0;
    for (var i = 0; i < nc; i++) {
      lnSum += col.x[a * nc + i] * th.psat(i, tK) / pHc;
    }
    final hLm = col.hl[a], hVm = col.hv[a];
    final groups = <EquationGroup>[
      EquationGroup('Steam and bubble point', [
        _line(
            'eq.steamPartialPressure',
            'PHYSICS.md 9.3',
            r'P_{HC} = P_j\,(1-\tilde y_w),\quad \sum_i x_i P^{sat}_i(T_j)/P_{HC} = 1',
            'P = ${texNum(p)}\\ \\mathrm{Pa},\\ \\tilde y_w = ${texNum(yw)}\\Rightarrow P_{HC} = ${texNum(pHc)}\\ \\mathrm{Pa},\\ \\sum x_iK_i = ${texNum(lnSum)}',
            pHc,
            Quantity.pressure,
            'Steam is vapour only; the hydrocarbons boil at their partial pressure (filtered steam fraction, tau 30 s).'),
      ]),
      EquationGroup('Enthalpy', [
        _line(
            'eq.crudeEnthalpy',
            'PHYSICS.md 9.1-9.2',
            r'h_{L,i} = \int_{T_b}^{T}C_{p,L}dT,\quad h_{V,i} = \Delta H_{vap}(T_b) + \int_{T_b}^{T}C_{p,V}dT',
            'h_L = ${texNum(hLm)},\\ h_V = ${texNum(hVm)}\\ \\mathrm{J/mol}\\Rightarrow H-h = ${texNum(hVm - hLm)}',
            hVm - hLm,
            Quantity.enthalpyMolar,
            'Each component is referenced to its own saturated liquid at T_b, so H - h stays positive in the balance (4.6).'),
      ]),
    ];
    if (stripper != null) {
      groups.add(EquationGroup('Side stripper', [
        _line(
            'eq.stripperDraw',
            'PHYSICS.md 9.4',
            r'S_d = P + V_{s1} + \frac{M_{SP}-M}{\tau_{LC}}',
            'S_d = ${texNum(col.sd[stripper])},\\ P = ${texNum(col.pAct[stripper])},\\ V_{s1} = ${texNum(col.v[col.s1(stripper)])}\\ \\mathrm{mol/s}',
            col.sd[stripper],
            Quantity.molarFlow,
            'The draw follows the stripper level; the lever sets the product rate.'),
      ]));
    }
    return ExplainResult(
        title: title, groups: groups, notes: const ['Crude: theoretical stages (E = 1), 9 pseudo-components, steam as inert vapour.'], time: time);
  }

  ExplainResult _condenser() => ExplainResult(title: 'Condenser and drum', groups: [
        EquationGroup('Overhead duty', [
          _line(
              'eq.crudeCondenser',
              'PHYSICS.md (9.4)',
              r'Q_C = V_{HC,1}\,[H_V(y_1,T_1)-h_L(y_1,T_{drum})] + S_1\,[h_{V,w}(T_1)-h_{L,w}(T_{drum})]',
              'V_{HC,1} = ${texNum(col.v[0])}\\ \\mathrm{mol/s},\\ T_1 = ${texNum(col.t[0])},\\ T_{drum} = ${texNum(col.inp.drumT)}\\Rightarrow Q_C = ${texNum(col.qc)}\\ \\mathrm{W}',
              col.qc,
              Quantity.energyRate,
              'Ideal overhead: the pressure and drum temperature are held; Q_C,max is only flagged.'),
        ]),
      ], notes: const ['Water leaves through the boot; the hydrocarbon condenses completely.'], time: time);

  ExplainResult _pa() => ExplainResult(title: 'Pumparound', groups: [
        EquationGroup('Duty', [
          _line(
              'eq.paDuty',
              'PHYSICS.md (9.3)',
              r'Q_{PA} = \min\{Q_{SP},\ P_{PA}\,[h_L(x_{16},T_{16})-h_L(x_{16},T_{R,min})]\}',
              'Q_{SP} = ${texNum(col.inp.paDuty)},\\ \\text{limit} = ${texNum(col.qPAmax)}\\Rightarrow Q_{PA} = ${texNum(col.qPA)}\\ \\mathrm{W}',
              col.qPA,
              Quantity.energyRate,
              'The cooler cannot bring the return below 120 °C.'),
        ]),
      ], notes: const [], time: time);

  ExplainResult _product(int k) {
    final x = k == 0 ? col.yy : (k == 4 ? col.xSump : col.x);
    final off = k == 0 ? 0 : (k == 4 ? 0 : col.s2(k - 1) * CrudeColumn.nc);
    final groups = <EquationGroup>[];
    final t5 = prod.tbpTrimmed(x, off, 5), t50 = prod.tbpTrimmed(x, off, 50), t95 = prod.tbpTrimmed(x, off, 95);
    groups.add(EquationGroup('Product TBP', [
      _line(
          'eq.productTbp',
          'PHYSICS.md 9.6',
          r'v_i = x_iMW_i/\rho_i,\ \text{each } v_i \text{ spread over its cut range; 0 and 100 read at 1 and 99 \%}',
          'TBP_5 = ${texNum(t5)},\\ TBP_{50} = ${texNum(t50)},\\ TBP_{95} = ${texNum(t95)}\\ \\mathrm{K}',
          t5,
          Quantity.temperature,
          '${_prodNames[k]}: TBP 5 % shown as the value.'),
    ]));
    if (k < 4) {
      final d = prod.productD86(x, off);
      groups.add(EquationGroup('ASTM D86', [
        _line(
            'eq.daubert',
            'PHYSICS.md 9.6',
            r'D86_{50} = (TBP_{50}/0.8718)^{1/1.0258},\quad \Delta D86 = (\Delta TBP/A)^{1/B}',
            'D86_5 = ${texNum(d[1])},\\ D86_{50} = ${texNum(d[4])},\\ D86_{95} = ${texNum(d[7])}\\ \\mathrm{K}',
            d[1],
            Quantity.temperature,
            'Daubert (1994); the value is D86 5 %.'),
      ]));
      if (k >= 1) {
        final dl = prod.productD86(k == 1 ? col.yy : col.x, k == 1 ? 0 : col.s2(k - 2) * CrudeColumn.nc);
        final g = d[1] - dl[7];
        groups.add(EquationGroup('Gap', [
          _line('eq.gap', 'PHYSICS.md 9.6', r'gap = D86_{5,heavy} - D86_{95,light}',
              'gap = ${texNum(d[1])} - ${texNum(dl[7])} = ${texNum(g)}\\ \\mathrm{K}', g, Quantity.temperatureDelta,
              'Positive: a clear gap; negative: overlap.'),
        ]));
      }
    }
    return ExplainResult(title: _prodNames[k], groups: groups, notes: const [], time: time);
  }

  ExplainResult _overflash() {
    final v = col.overflash;
    return ExplainResult(title: 'Overflash', groups: [
      EquationGroup('Overflash', [
        _line('eq.overflash', 'PHYSICS.md 9.2', r'\text{overflash} = 100\,L_{25}\,v_{25}/F_{crude}',
            'L_{25} = ${texNum(col.l[col.feedSt - 2])}\\ \\mathrm{mol/s}\\Rightarrow ${texNum(v)}\\ \\%', v, Quantity.dimensionless,
            'The liquid flowing from stage 25 to the flash zone, as vol % of the crude.'),
      ]),
    ], notes: const [], time: time);
  }
}
