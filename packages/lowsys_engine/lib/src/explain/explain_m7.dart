import 'dart:typed_data';

import '../snapshot/fug.dart';
import 'explain_engine.dart';
import 'explain_types.dart';

/// M7 equation traces: the Hengstebeck pseudo-binary (PHYSICS.md 14.2) and the FUG panel (14.3).
extension ExplainM7 on ExplainEngine {
  /// `eq.hengstebeck`. The value is alpha' = K_LK / K_HK on the top tray (the snapshot's y* / x ratio).
  ExplainResult hengstebeck() {
    final keys = config.effectiveKeys;
    final lk = keys.lk, hk = keys.hk;
    double prime(Float64List a, int j) {
      final l = a[j * nc + lk], h = a[j * nc + hk];
      return l + h > 1e-12 ? l / (l + h) : 0.0;
    }

    const j = 1;
    final xl = st.x[j * nc + lk], xh = st.x[j * nc + hk];
    final yl = st.yStar[j * nc + lk], yh = st.yStar[j * nc + hk];
    final ap = xl > 1e-12 && xh > 1e-12 && yh > 1e-12 ? (yl / xl) / (yh / xh) : double.nan;
    final lines = [
      EquationLine(
        id: 'eq.hengstebeck',
        physicsRef: 'PHYSICS.md (14.2)',
        texSymbolic:
            r"x'_j = \frac{x_{LK,j}}{x_{LK,j}+x_{HK,j}},\quad y^{*\prime}_j = \frac{K_{LK} x_{LK,j}}{K_{LK} x_{LK,j}+K_{HK} x_{HK,j}}",
        texSubstituted:
            "x'_{1} = ${texNum(prime(st.x, j))},\\ y^{*\\prime}_{1} = ${texNum(prime(st.yStar, j))},\\ \\alpha' = K_{LK}/K_{HK} = ${texNum(ap)}",
        value: ap,
        note:
            'Hengstebeck pseudo-binary: the other components distort it, so the staircase is only a guide. The stage points make a locus, not a closed-form curve.',
      ),
    ];
    return ExplainResult(
      title: 'Pseudo-binary McCabe-Thiele',
      groups: [EquationGroup('Hengstebeck construction', lines)],
      notes: const ['The primed diagram ignores every component except the two keys; the q-line is approximate for a multicomponent feed.'],
      time: snapshot.time,
    );
  }

  /// The FUG panel's equation lines. Values: alpha = alpha_LK (geometric mean), fenske = N_min, split = the Fenske
  /// distillate flow, underwood = R_min, gilliland = N, kirkbride = N_R, rigorous = N_act.
  ExplainResult fug(FugTargets? targets) {
    final keys = config.effectiveKeys;
    final model = t2 ?? thermo;
    final r = const FugCalculator().compute(snapshot, keys, targets: targets, thermo: model);
    if (r == null || !r.valid) {
      return ExplainResult(
          title: 'FUG shortcut',
          groups: const [],
          notes: [
            r == null
                ? 'Not observable on a real plant.'
                : (r.reason == FugInvalidReason.notAdjacent ? 'Keys must be adjacent in volatility.' : 'No key split to analyse.')
          ],
          time: snapshot.time);
    }
    final names = snapshot.components;
    final lk = keys.lk, hk = keys.hk;
    final dTot = r.d.fold<double>(0, (a, b) => a + b);
    String tex(double v) => texNum(v);
    final lines = <EquationLine>[
      EquationLine(
        id: 'eq.fug.alpha',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic: r'\alpha_i = \sqrt{\alpha_{i,1}\,\alpha_{i,N+1}},\quad \alpha_i = K_i / K_{HK}',
        texSubstituted: [for (var i = 0; i < names.length; i++) '\\alpha_{\\mathrm{${names[i]}}} = ${tex(r.alpha[i])}'].join(',\\ '),
        value: r.alpha[lk],
        note: 'One geometric-mean alpha per component stands in for an alpha that varies down the column.',
      ),
      EquationLine(
        id: 'eq.fug.fenske',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic: r'N_{min} = \frac{\ln\left[(d_{LK}/b_{LK})(b_{HK}/d_{HK})\right]}{\ln(\alpha_{LK}/\alpha_{HK})}',
        texSubstituted: 'r_{LK} = ${tex(r.rLK)},\\ r_{HK} = ${tex(r.rHK)},\\ N_{min} = ${tex(r.nMin)}',
        value: r.nMin,
      ),
      EquationLine(
        id: 'eq.fug.split',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic: r'\frac{d_i}{b_i} = \alpha_i^{N_{min}}\,\frac{d_{HK}}{b_{HK}}',
        texSubstituted: [for (var i = 0; i < names.length; i++) '(d/b)_{\\mathrm{${names[i]}}} = ${tex(r.dToB[i])}'].join(',\\ '),
        value: dTot,
        note: 'The non-key distribution at minimum stages; the value is the distillate flow it implies.',
      ),
      EquationLine(
        id: 'eq.fug.underwood',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic: r'\sum_i \frac{\alpha_i z_i}{\alpha_i-\theta} = 1-q,\quad R_{min}+1 = \sum_i \frac{\alpha_i x_{D,i}}{\alpha_i-\theta}',
        texSubstituted: 'q = ${tex(r.q)},\\ \\theta = ${tex(r.theta)},\\ R_{min} = ${tex(r.rMin)}',
        value: r.rMin,
      ),
      EquationLine(
        id: 'eq.fug.gilliland',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic:
            r'X = \frac{R-R_{min}}{R+1},\ Y = 1-\exp\left[\frac{1+54.4X}{11+117.2X}\,\frac{X-1}{\sqrt{X}}\right],\ N = \frac{N_{min}+Y}{1-Y}',
        texSubstituted: r.belowRmin
            ? 'R = ${tex(r.r)} \\le R_{min}:\\ N = \\infty'
            : 'R = ${tex(r.r)},\\ X = ${tex(r.x)},\\ Y = ${tex(r.y)},\\ N = ${tex(r.nGilliland)}',
        value: r.nGilliland,
        note: r.belowRmin ? 'Below minimum reflux: no finite number of stages.' : null,
      ),
      EquationLine(
        id: 'eq.fug.kirkbride',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic: r'\frac{N_R}{N_S} = \left[\frac{z_{HK}}{z_{LK}}\left(\frac{x_{B,LK}}{x_{D,HK}}\right)^2\frac{B}{D}\right]^{0.206}',
        texSubstituted: 'N_R/N_S = ${tex(r.nrOverNs)},\\ N_R = ${tex(r.nR)}\\ (\\text{stages above the feed})',
        value: r.nR,
      ),
      EquationLine(
        id: 'eq.fug.rigorous',
        physicsRef: 'PHYSICS.md (14.3)',
        texSymbolic: r'N_{act} = \sum_j E_j^{eff} + 1,\quad N_{R,act} = \sum_{j<n_F} E_j^{eff},\quad R_{act} = L_0/D',
        texSubstituted: 'N_{act} = ${tex(r.nActual)},\\ N_{R,act} = ${tex(r.nRActual)},\\ R_{act} = ${tex(r.rActual)}',
        value: r.nActual,
        note: 'The rigorous column next to the shortcut; N x E is the textbook approximation of its effective stages.',
      ),
    ];
    return ExplainResult(
      title: 'FUG shortcut (${names[lk]} / ${names[hk]})',
      groups: [EquationGroup('Fenske, Underwood, Gilliland, Kirkbride', lines)],
      notes: const [
        "FUG uses one mean alpha per component, the Fenske non-key split and Molokanov's fit of Gilliland's correlation. It is shown next to the rigorous column, not used by it."
      ],
      time: snapshot.time,
    );
  }
}
