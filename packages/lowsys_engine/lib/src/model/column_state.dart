import 'dart:typed_data';

/// Structure-of-arrays state of the M1 column (PHYSICS.md 1.2, ENGINE_API.md 5.1).
///
/// Stage numbering (PHYSICS.md 0.2): 0 = condenser drum, 1..N trays, N+1 = sump.
/// Per-component arrays are row-major by stage (`j * nc + i`).
class ColumnState {
  /// Number of trays N.
  final int nTrays;

  /// Number of stages N + 2.
  final int n;
  final int nc;

  /// Component holdups m_ij (mol): the dynamic state.
  final Float64List m;

  /// Total holdup M_j = sum_i m_ij (mol).
  final Float64List holdup;

  /// Liquid mole fractions x_ij.
  final Float64List x;

  /// Vapour leaving stage j, y_ij (Murphree, PHYSICS.md 4.2).
  final Float64List y;

  /// Equilibrium vapour y*_ij of the liquid on stage j.
  final Float64List yStar;

  /// Liquid flow down from stage j (L[0] = reflux), mol/s.
  final Float64List liquid;

  /// Vapour flow up from stage j (V[N+1] = boilup), mol/s. Index 0 unused.
  final Float64List vapor;

  /// Liquid molar volume per stage (m3/mol).
  final Float64List vLiq;

  /// Murphree efficiency used on each stage in the last step.
  final Float64List eff;

  /// Effective froth density alpha_e in the last step.
  final Float64List alphaE;

  /// Entrainment e_j and bypass fraction f_j (zero in ideal hydraulics, kept for the banded solve).
  final Float64List entrain;
  final Float64List bypass;

  /// Entrainment fraction filter psi_j and filtered liquid load (PHYSICS.md 5.5, 5.6), full hydraulics only.
  final Float64List psi;
  final Float64List lbar;

  // ---- Tier 2 (M4): temperatures, enthalpies, normalised K, bubble-point sensitivities, overhead (PHYSICS.md 4.5, 7)

  /// Stage temperature T_j (K), liquid enthalpy h_j and enthalpy H_j of the vapour leaving stage j (J/mol).
  final Float64List t, hLiq, hVap;

  /// Normalised K-values K~_ij (4.3), stage pressure P_j (Pa) and tau_j = dT_j/dP (K/Pa, 4.5).
  final Float64List kt, pStage, tau;

  /// Overhead pressure P_top (Pa), inert inventory n_I (mol), condensable inventory per component n_V,i (mol).
  double pTop = 101325, nI = 0;
  final Float64List nVi;

  /// Condensing temperature T_0,sat of the drum liquid, reflux temperature T_0 (K), condensation rate (mol/s),
  /// condenser duty (W), delivered reboiler duty (W), vent + relief rate (mol/s).
  double tSat0 = 350, tRefl = 350, nCond = 0, qC = 0, qR = 0, nVent = 0, nRelief = 0, dV = 0;

  /// Simulation time (s).
  double time = 0;

  /// Ideal flow-controller states (actual flows, mol/s).
  double feedAct = 0, refluxAct = 0, boilupAct = 0;

  ColumnState(this.nTrays, this.nc)
      : n = nTrays + 2,
        m = Float64List((nTrays + 2) * nc),
        holdup = Float64List(nTrays + 2),
        x = Float64List((nTrays + 2) * nc),
        y = Float64List((nTrays + 2) * nc),
        yStar = Float64List((nTrays + 2) * nc),
        liquid = Float64List(nTrays + 2),
        vapor = Float64List(nTrays + 2),
        vLiq = Float64List(nTrays + 2),
        eff = Float64List(nTrays + 2),
        alphaE = Float64List(nTrays + 2),
        entrain = Float64List(nTrays + 2),
        bypass = Float64List(nTrays + 2),
        psi = Float64List(nTrays + 2),
        lbar = Float64List(nTrays + 2),
        t = Float64List(nTrays + 2),
        hLiq = Float64List(nTrays + 2),
        hVap = Float64List(nTrays + 2),
        kt = Float64List((nTrays + 2) * nc),
        pStage = Float64List(nTrays + 2),
        tau = Float64List(nTrays + 2),
        nVi = Float64List(nc);

  void copyFrom(ColumnState o) {
    m.setAll(0, o.m);
    holdup.setAll(0, o.holdup);
    x.setAll(0, o.x);
    y.setAll(0, o.y);
    yStar.setAll(0, o.yStar);
    liquid.setAll(0, o.liquid);
    vapor.setAll(0, o.vapor);
    vLiq.setAll(0, o.vLiq);
    eff.setAll(0, o.eff);
    alphaE.setAll(0, o.alphaE);
    entrain.setAll(0, o.entrain);
    bypass.setAll(0, o.bypass);
    psi.setAll(0, o.psi);
    lbar.setAll(0, o.lbar);
    t.setAll(0, o.t);
    hLiq.setAll(0, o.hLiq);
    hVap.setAll(0, o.hVap);
    kt.setAll(0, o.kt);
    pStage.setAll(0, o.pStage);
    tau.setAll(0, o.tau);
    nVi.setAll(0, o.nVi);
    pTop = o.pTop;
    nI = o.nI;
    tSat0 = o.tSat0;
    tRefl = o.tRefl;
    nCond = o.nCond;
    qC = o.qC;
    qR = o.qR;
    nVent = o.nVent;
    nRelief = o.nRelief;
    dV = o.dV;
    time = o.time;
    feedAct = o.feedAct;
    refluxAct = o.refluxAct;
    boilupAct = o.boilupAct;
  }

  static List<double> _l(Float64List a) => a.toList(growable: false);

  Map<String, Object?> toJson() => {
        'nTrays': nTrays,
        'nc': nc,
        'm': _l(m),
        'holdup': _l(holdup),
        'x': _l(x),
        'y': _l(y),
        'yStar': _l(yStar),
        'liquid': _l(liquid),
        'vapor': _l(vapor),
        'vLiq': _l(vLiq),
        'eff': _l(eff),
        'alphaE': _l(alphaE),
        'psi': _l(psi),
        'lbar': _l(lbar),
        'T': _l(t),
        'pTop': pTop,
        'nI': nI,
        'nVi': _l(nVi),
        'tSat0': tSat0,
        'tRefl': tRefl,
        'qC': qC,
        'qR': qR,
        'time': time,
        'feedAct': feedAct,
        'refluxAct': refluxAct,
        'boilupAct': boilupAct,
      };

  static void _load(Float64List dst, Object? src) {
    final l = src! as List<Object?>;
    for (var i = 0; i < dst.length; i++) {
      dst[i] = (l[i]! as num).toDouble();
    }
  }

  void loadJson(Map<String, Object?> j) {
    _load(m, j['m']);
    _load(holdup, j['holdup']);
    _load(x, j['x']);
    _load(y, j['y']);
    _load(yStar, j['yStar']);
    _load(liquid, j['liquid']);
    _load(vapor, j['vapor']);
    _load(vLiq, j['vLiq']);
    _load(eff, j['eff']);
    _load(alphaE, j['alphaE']);
    if (j['psi'] != null) _load(psi, j['psi']);
    if (j['lbar'] != null) _load(lbar, j['lbar']);
    if (j['T'] != null) {
      _load(t, j['T']);
      _load(nVi, j['nVi']);
      pTop = (j['pTop']! as num).toDouble();
      nI = (j['nI']! as num).toDouble();
      tSat0 = (j['tSat0']! as num).toDouble();
      tRefl = (j['tRefl']! as num).toDouble();
      qC = (j['qC']! as num).toDouble();
      qR = (j['qR']! as num).toDouble();
    }
    time = (j['time']! as num).toDouble();
    feedAct = (j['feedAct']! as num).toDouble();
    refluxAct = (j['refluxAct']! as num).toDouble();
    boilupAct = (j['boilupAct']! as num).toDouble();
  }
}

/// Runtime lever values that the stepper reads (SI).
class StepInputs {
  double feedFlowSp = 0;
  double refluxFlowSp = 0;
  double refluxRatio = 2.0;
  bool ratioMode = false;
  double boilupSp = 0;
  double feedQ = 1.0;

  /// Feed temperature (K, Tiers 2/3) before fault effects, and reflux subcooling (K), inert vent opening (%).
  double feedT = 365;
  double refluxSub = 0;
  double inertVent = 0;
  int feedStage = 1;
  double murphree = 0.7;
  final Float64List z;
  StepInputs(int nc) : z = Float64List(nc);
}

/// Exact per-step flows for conservation accounting (VALIDATION.md 0, VC-5). The values
/// are those the solver used in the most recent step.
class StepDebug {
  /// Step length (s).
  double dt = 0;

  /// Flows used in the step (mol/s).
  double feedFlow = 0,
      refluxFlow = 0,
      distillateFlow = 0,
      bottomsFlow = 0,
      boilupFlow = 0;

  /// Component rates (mol/s) per component: feed in, distillate out (D m0_new / M0hat), bottoms out.
  final Float64List feedRate, distillateRate, bottomsRate;

  /// Component rates (mol/s) that leave through the vent, the relief valve and the vapour product (Tiers 2/3).
  final Float64List ventRate;
  StepDebug(int nc)
      : feedRate = Float64List(nc),
        distillateRate = Float64List(nc),
        bottomsRate = Float64List(nc),
        ventRate = Float64List(nc);
}
