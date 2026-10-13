import '../core/quantity.dart';
import '../model/packed_hydraulics.dart';
import 'explain_engine.dart';
import 'explain_types.dart';

/// Equation lines of a packed segment (PHYSICS.md 15, M8): `eq.robbins`, `eq.kisterGill`, `eq.packHoldup`, `eq.hetp`,
/// `eq.lewis` and, when the bed's distributor fault is visible, `eq.maldistribution`. Values come from the packed model
/// arrays and the snapshot of the same state (VALIDATION.md VC-21).
extension ExplainPacked on ExplainEngine {
  EquationGroup packedGroup(int j) {
    final pk = hyd.pk!;
    final b = pk.bedOf[j];
    final bed = pk.beds[b];
    final pack = bed.section.packing;
    final fp = pk.fpEff(b);
    final h = pk.hSeg[j];
    final lines = <EquationLine>[
      EquationLine(
        id: 'eq.robbins',
        physicsRef: 'PHYSICS.md (6.1)',
        texSymbolic:
            r'\frac{\Delta P}{H} = t + 0.4\left(\frac{L_f}{20000}\right)^{0.1}t^4,\quad t = 7.4\times10^{-8}G_f^2\,10^{2.7\times10^{-5}L_f}',
        texSubstituted:
            "L' = ${texNum(pk.lp[j])},\\ G' = ${texNum(pk.gp[j])}\\ \\mathrm{kg/m^2/s},\\ F_p = ${texNum(fp)}\\Rightarrow \\Delta P/H = ${texNum(pk.dpPerM[j])}\\ \\mathrm{Pa/m},\\ \\Delta P_{$j} = ${texNum(st.dp[j])}\\ \\mathrm{Pa}",
        value: st.dp[j],
        quantity: Quantity.pressureDelta,
        note: 'Robbins (1991), F_pd = F_p; segment height ${texNum(h)} m.',
      ),
      EquationLine(
        id: 'eq.kisterGill',
        physicsRef: 'PHYSICS.md (6.2)',
        texSymbolic: r"\Delta P_{flood} = 0.115\,F_p^{0.7}\ \text{in H}_2\text{O/ft},\quad \varphi_p = G'/G'_{fl}",
        texSubstituted:
            "\\Delta P_{flood} = ${texNum(PackedHydraulics.kisterGillFloodDp(fp))}\\ \\mathrm{Pa/m},\\ G'_{fl} = ${texNum(pk.gfl[j])}\\Rightarrow \\varphi_p = ${texNum(st.packFlood[j])}",
        value: st.packFlood[j],
        note: 'Approach to flood; the bed floods at 1.',
      ),
      EquationLine(
        id: 'eq.packHoldup',
        physicsRef: 'PHYSICS.md (6.3)',
        texSymbolic:
            r'h_L = h_{L,S}\,(1 + 1.2\varphi_p^{13}),\quad h_{L,S} = \left(\frac{12\mu_L a^2 u_L}{\rho_L g}\right)^{1/3}',
        texSubstituted:
            'h_{L,S} = ${texNum(pk.hLs[j])},\\ \\varphi_p = ${texNum(st.packFlood[j])}\\Rightarrow h_L = ${texNum(st.packHoldup[j])}',
        value: st.packHoldup[j],
        note: 'Liquid holdup as a volume fraction of the bed.',
      ),
      EquationLine(
        id: 'eq.hetp',
        physicsRef: 'PHYSICS.md (6.5)',
        texSymbolic: r'HETP = HETP_{ref}\,\max(1, a_{w,ref}/a_w)\,g(\varphi_p)',
        texSubstituted:
            'HETP = ${texNum(pack.hetpRef)}\\times${texNum(pk.wetting[j])}\\times${texNum(PackedHydraulics.loadingFactor(st.packFlood[j]))} = ${texNum(st.hetp[j])}\\ \\mathrm{m},\\ a_w/a = ${texNum(st.wetFrac[j])}',
        value: st.hetp[j],
        quantity: Quantity.smallLength,
        note: 'Onda wetting at the segment liquid load, and the loading factor near flood.',
      ),
      EquationLine(
        id: 'eq.lewis',
        physicsRef: 'PHYSICS.md (4.3)',
        texSymbolic: r'E_{MV} = \frac{\lambda^{E_O}-1}{\lambda-1},\quad E_O = \min(1, H_k/HETP)\,E_{mal}',
        texSubstituted:
            '\\lambda = ${texNum(pk.lam[j])},\\ E_O = ${texNum(pk.eo[j])}\\Rightarrow E_{MV} = ${texNum(st.efficiency[j])}',
        value: st.efficiency[j],
        note: 'Murphree vapour efficiency of the segment, from its overall efficiency (Lewis).',
      ),
    ];
    final bi = b < snapshot.beds.length ? snapshot.beds[b] : null;
    if (bi != null && !bi.eMal.isNaN && (bi.eMal < 1 || bi.maldistribution > 0)) {
      lines.add(EquationLine(
        id: 'eq.maldistribution',
        physicsRef: 'PHYSICS.md (6.6)',
        texSymbolic: r'E_{mal} = n_{eff}/n_{th}\quad\text{(two parallel Kremser columns)}',
        texSubstituted:
            'f = ${texNum(bi.maldistribution)},\\ n_{th} = ${texNum(bi.nTheoretical)},\\ S = ${texNum(pk.bedS[b])}\\Rightarrow E_{mal} = ${texNum(bi.eMal)}',
        value: bi.eMal,
        note: 'Bed ${bi.bed} as a whole: a plugged distributor sends more liquid to one side.',
      ));
    }
    return EquationGroup('Packed segment hydraulics and efficiency', lines);
  }
}
