// Independent steady-state solver for the M9 crude column (PHYSICS.md §9.2–9.5 as revised in the M9 pass).
// Stages: main 1..30 (index 0..29), strippers SS1..SS3 as (top, bottom) = (30,31), (32,33), (34,35).
// Each pass: flows from the 72 mass + energy balances (dense solve, given T, x), component balances per
// component (dense 36 x 36, given flows and K), bubble-point T at the hydrocarbon partial pressure; the reflux is
// set by a secant on T_1 (TC-201); tray ΔP from the §5 valve-tray hydraulics in an outer pass.
import 'dart:math' as m;
import 'crude.dart';

const int nm = 30, ns = 36, nc = 9;

class Crude {
  // ---- operating levers (SCOPE §4.4 defaults)
  double crudeM3h = 132.5, cotC = 345, pTop = 1.6e5, tTopSpC = 125, tDrumC = 45;
  List<double> drawPct = [11.7, 16.7, 5.3]; // product rates, vol % of crude at 15.6 °C
  double paDuty = 5e6, paM3h = 120; // W; circulation at 15.6 °C (M9 defaults: COT 345 °C, PA 5 MW)
  double steamBot = 2000, steamTC = 200; // kg/h, °C
  List<double> steamSS = [300, 300, 300]; // kg/h
  double murphree = 1.0;
  // ---- topology (§9.2)
  int feedSt = 26, paDrawSt = 16, paRetSt = 14;
  List<int> drawSt = [8, 15, 21], retSt = [7, 14, 20];
  // ---- tray geometry (valve trays)
  double dc = 3.2, ts = 0.75, fd = 0.12, hw = 0.05, fv = 0.14, rmin = 0.25, dpLift = 190, cvv = 0.65, dhV = 0.040;
  bool hydDp = true;
  double dpFixed = 700;

  // ---- state
  final t = List<double>.filled(ns, 500), p = List<double>.filled(ns, 1.6e5);
  final x = List.generate(ns, (_) => List<double>.filled(nc, 0));
  final l = List<double>.filled(ns, 0), v = List<double>.filled(ns, 0); // HC liquid / vapour leaving each stage
  final sd = List<double>.filled(3, 0), pk = List<double>.filled(3, 0), steamUp = List<double>.filled(ns, 0);
  final dry = [false, false, false];
  final dp = List<double>.filled(nm, 700), flood = List<double>.filled(nm, 0), hcl = List<double>.filled(nm, 0);
  double l0 = 0, pPA = 0, fF = 0, qPA = 0, paFlowFrac = 1.0, tRmin = 393.15;
  List<double> z = crudeZ();
  Flash feed = Flash();
  int iters = 0;
  bool converged = false;
  double lMin = 0.01;

  int s1(int k) => 30 + 2 * k;
  int s2(int k) => 31 + 2 * k;
  double get tTop => t[0];
  double kgh2mol(double kgh) => kgh / 3600 / 0.018015;

  void init() {
    fF = crudeM3h / 3600 / vStdMix(z);
    for (var j = 0; j < nm; j++) {
      t[j] = 273.15 + 120 + (340 - 120) * j / (nm - 1);
      x[j] = List.of(z);
    }
    for (var k = 0; k < 3; k++) {
      t[s1(k)] = t[drawSt[k] - 1] - 5;
      t[s2(k)] = t[drawSt[k] - 1] - 10;
      x[s1(k)] = List.of(z);
      x[s2(k)] = List.of(z);
    }
    l0 = 0.5 * fF;
    setPressures();
  }

  void setPressures() {
    p[0] = pTop;
    for (var j = 1; j < nm; j++) p[j] = p[j - 1] + (hydDp ? dp[j - 1] : dpFixed);
    for (var k = 0; k < 3; k++) {
      p[s1(k)] = p[drawSt[k] - 1];
      p[s2(k)] = p[drawSt[k] - 1];
    }
  }

  void setSteam() {
    final sb = kgh2mol(steamBot);
    for (var j = 1; j <= nm; j++) {
      var s = sb;
      for (var k = 0; k < 3; k++) if (j <= retSt[k]) s += kgh2mol(steamSS[k]);
      steamUp[j - 1] = s;
    }
    for (var k = 0; k < 3; k++) {
      steamUp[s1(k)] = kgh2mol(steamSS[k]);
      steamUp[s2(k)] = kgh2mol(steamSS[k]);
    }
  }

  /// Steam mole fraction used by the bubble point: filtered (M9 rule, τ_w) and capped at ywMax.
  final ywF = List<double>.filled(ns, -1);
  double tauW = 30, ywMax = 0.98, ywRelax = 0.2;
  double ywRaw(int a) => m.min(ywMax, steamUp[a] / (steamUp[a] + m.max(v[a], 1e-9)));
  void filterYw(double w) {
    for (var a = 0; a < ns; a++) {
      final r = ywRaw(a);
      ywF[a] = ywF[a] < 0 ? r : ywF[a] + w * (r - ywF[a]);
    }
  }

  double pHC(int a) => p[a] * (1 - (ywF[a] < 0 ? ywRaw(a) : ywF[a]));
  List<double> kv(int a) {
    final ph = pHC(a);
    return [for (var i = 0; i < nc; i++) pcs[i].psat(t[a]) / ph];
  }

  List<double> yOf(int a, List<double> k) {
    final y = [for (var i = 0; i < nc; i++) k[i] * x[a][i]];
    final s = y.reduce((a, b) => a + b);
    return [for (final e in y) e / s];
  }

  double get tSteam => steamTC + 273.15;
  double get tDrum => tDrumC + 273.15;

  // steam enthalpy flow into stage a minus out (W)
  double qSteam(int a) {
    if (a < nm) {
      final j = a + 1;
      var qin = (j < nm) ? steamUp[a + 1] * water.hV(t[a + 1]) : kgh2mol(steamBot) * water.hV(tSteam);
      for (var k = 0; k < 3; k++) if (retSt[k] == j) qin += kgh2mol(steamSS[k]) * water.hV(t[s1(k)]);
      return qin - steamUp[a] * water.hV(t[a]);
    }
    final k = (a - 30) ~/ 2;
    final top = a == s1(k);
    final tin = top ? t[s2(k)] : tSteam;
    return kgh2mol(steamSS[k]) * (water.hV(tin) - water.hV(t[a]));
  }

  late List<List<double>> kk, yy;
  late List<double> hl, hv;

  void props() {
    kk = [for (var a = 0; a < ns; a++) kv(a)];
    yy = [for (var a = 0; a < ns; a++) yOf(a, kk[a])];
    hl = [for (var a = 0; a < ns; a++) hLmix(x[a], t[a])];
    hv = [for (var a = 0; a < ns; a++) hVmix(yy[a], t[a])];
  }

  /// Flow solve: 72 unknowns.
  void solveFlows() {
    const n = 72;
    final a = List.generate(n, (_) => List<double>.filled(n, 0));
    final b = List<double>.filled(n, 0);
    int uL(int j) => j - 1;
    int uV(int j) => 29 + j;
    int uLs1(int k) => 60 + 3 * k;
    int uVs1(int k) => 61 + 3 * k;
    int uVs2(int k) => 62 + 3 * k;
    int uSd(int k) => 69 + k;
    final hr = hLmix(yy[0], tDrum); // reflux = condensed V1
    final paHR = hl[paDrawSt - 1] - qPA / pPA;
    // L_j coefficient helper (handles L0 and dry draw stages)
    void addL(int row, int j, double c, double hcoef) {
      if (j == 0) {
        b[row] -= c * l0 * hcoef;
        return;
      }
      for (var k = 0; k < 3; k++) {
        if (dry[k] && drawSt[k] == j) {
          b[row] -= c * lMin * hcoef;
          return;
        }
      }
      a[row][uL(j)] += c * hcoef;
    }

    void addP(int row, int k, double c) {
      if (dry[k]) {
        a[row][uL(drawSt[k])] += c;
      } else {
        b[row] -= c * pk[k];
      }
    }

    for (var j = 1; j <= nm; j++) {
      final rm = j - 1, re = 29 + j, aj = j - 1;
      // mass
      addL(rm, j - 1, 1, 1);
      if (j < nm) a[rm][uV(j + 1)] += 1;
      addL(rm, j, -1, 1);
      a[rm][uV(j)] -= 1;
      // energy
      addL(re, j - 1, 1, j == 1 ? hr : hl[aj - 1]);
      if (j < nm) a[re][uV(j + 1)] += hv[aj + 1];
      addL(re, j, -1, hl[aj]);
      a[re][uV(j)] -= hv[aj];
      var fm = 0.0, fe = qSteam(aj);
      if (j == feedSt) {
        fm += fF;
        fe += fF * feed.h;
      }
      if (j == paRetSt) {
        fm += pPA;
        fe += pPA * paHR;
      }
      if (j == paDrawSt) {
        fm -= pPA;
        fe -= pPA * hl[aj];
      }
      for (var k = 0; k < 3; k++) {
        if (retSt[k] == j) {
          a[rm][uVs1(k)] += 1;
          a[re][uVs1(k)] += hv[s1(k)];
        }
        if (drawSt[k] == j) {
          a[rm][uSd(k)] -= 1;
          a[re][uSd(k)] -= hl[aj];
        }
      }
      b[rm] -= fm;
      b[re] -= fe;
    }
    for (var k = 0; k < 3; k++) {
      final r1 = 60 + 4 * k, r2 = r1 + 1, r3 = r1 + 2, r4 = r1 + 3;
      final at = s1(k), ab = s2(k), ad = drawSt[k] - 1;
      a[r1][uSd(k)] += 1;
      a[r1][uVs2(k)] += 1;
      a[r1][uLs1(k)] -= 1;
      a[r1][uVs1(k)] -= 1;
      a[r2][uSd(k)] += hl[ad];
      a[r2][uVs2(k)] += hv[ab];
      a[r2][uLs1(k)] -= hl[at];
      a[r2][uVs1(k)] -= hv[at];
      b[r2] -= qSteam(at);
      a[r3][uLs1(k)] += 1;
      addP(r3, k, -1);
      a[r3][uVs2(k)] -= 1;
      a[r4][uLs1(k)] += hl[at];
      a[r4][uVs2(k)] -= hv[ab];
      b[r4] -= qSteam(ab);
      // product enthalpy
      if (dry[k]) {
        a[r4][uL(drawSt[k])] -= hl[ab];
      } else {
        b[r4] += pk[k] * hl[ab];
      }
    }
    final u = solveDense(a, b);
    final w = wFlow;
    double bl(double o, double n) => o + w * (n - o);
    for (var j = 1; j <= nm; j++) {
      v[j - 1] = m.max(bl(v[j - 1], u[uV(j)]), 1e-6);
      l[j - 1] = bl(l[j - 1], u[uL(j)]);
    }
    for (var k = 0; k < 3; k++) {
      sd[k] = m.max(bl(sd[k], u[uSd(k)]), 0);
      l[s1(k)] = m.max(bl(l[s1(k)], u[uLs1(k)]), 1e-6);
      v[s1(k)] = m.max(bl(v[s1(k)], u[uVs1(k)]), 1e-6);
      v[s2(k)] = m.max(bl(v[s2(k)], u[uVs2(k)]), 1e-6);
      if (dry[k]) {
        pk[k] = m.max(u[uL(drawSt[k])], 0);
        l[drawSt[k] - 1] = lMin;
      }
      l[s2(k)] = pk[k];
    }
    for (var j = 0; j < nm; j++) l[j] = m.max(l[j], 1e-6);
  }

  double wFlow = 1.0;
  bool fixedFlows = false;

  /// Mass-consistent starting flows (no energy balance): ideal yields, 3 % overflash, internal reflux 0.3 F.
  void guessFlows() {
    updateSpecs();
    final fF0 = fF;
    final o = 0.03 * crudeM3s / vStdMix(x[feedSt - 2]);
    final sv = 0.04 * fF0;
    final vs1 = [for (var k = 0; k < 3; k++) 0.2 * pk[k]], vs2 = [for (var k = 0; k < 3; k++) 0.1 * pk[k]];
    for (var k = 0; k < 3; k++) {
      sd[k] = pk[k] + vs1[k];
      l[s1(k)] = pk[k] + vs2[k];
      v[s1(k)] = vs1[k];
      v[s2(k)] = vs2[k];
      l[s2(k)] = pk[k];
    }
    final lg = List<double>.filled(nm + 1, 0); // lg[j] = L_j, lg[0] = L0
    final r = 0.3 * fF0;
    for (var j = 1; j <= nm; j++) {
      double lj;
      if (j >= feedSt) {
        lj = j == nm ? 0 : sv; // + B below
      } else {
        lj = o + r * (feedSt - 1 - j) / (feedSt - 1);
        for (var k = 0; k < 3; k++) if (drawSt[k] > j) lj += sd[k];
        if (j == paRetSt || j == paRetSt + 1) lj += pPA;
      }
      lg[j] = lj;
    }
    // residue B from the overall balance; naphtha from the ideal 20 %
    final dN = 0.20 * crudeM3s / vStdMix(x[0]);
    final b = fF0 - dN - pk.reduce((a, c) => a + c);
    for (var j = feedSt; j <= nm; j++) lg[j] += b;
    lg[0] = r + o;
    l0 = lg[0];
    // bottom-up V from the mass balances
    var vb = 0.0;
    for (var j = nm; j >= 1; j--) {
      var vin = lg[j - 1] + vb + (j == feedSt ? fF0 : 0) + (j == paRetSt ? pPA : 0) - (j == paDrawSt ? pPA : 0);
      for (var k = 0; k < 3; k++) {
        if (retSt[k] == j) vin += v[s1(k)];
        if (drawSt[k] == j) vin -= sd[k];
      }
      final vj = vin - lg[j];
      v[j - 1] = m.max(vj, 1e-3);
      l[j - 1] = lg[j];
      vb = v[j - 1];
    }
  }

  /// Component balances (E = murphree applied as y_j = E K x_j + (1-E) y_in on main trays is not used: E = 1).
  void solveComponents(double relax) {
    final xn = List.generate(ns, (_) => List<double>.filled(nc, 0));
    for (var i = 0; i < nc; i++) {
      final a = List.generate(ns, (_) => List<double>.filled(ns, 0));
      final b = List<double>.filled(ns, 0);
      for (var j = 1; j <= nm; j++) {
        final r = j - 1;
        if (j == 1) {
          a[r][0] += l0 * kk[0][i];
        } else {
          a[r][j - 2] += l[j - 2];
        }
        if (j < nm) a[r][j] += v[j] * kk[j][i];
        var out = l[r] + v[r] * kk[r][i];
        if (j == paDrawSt) out += pPA;
        if (j == paRetSt) a[r][paDrawSt - 1] += pPA;
        if (j == feedSt) b[r] -= fF * z[i];
        for (var k = 0; k < 3; k++) {
          if (drawSt[k] == j) out += sd[k];
          if (retSt[k] == j) a[r][s1(k)] += v[s1(k)] * kk[s1(k)][i];
        }
        a[r][r] -= out + relax;
        b[r] -= relax * x[r][i];
      }
      for (var k = 0; k < 3; k++) {
        final at = s1(k), ab = s2(k);
        a[at][drawSt[k] - 1] += sd[k];
        a[at][ab] += v[ab] * kk[ab][i];
        a[at][at] -= l[at] + v[at] * kk[at][i] + relax;
        b[at] -= relax * x[at][i];
        a[ab][at] += l[at];
        a[ab][ab] -= pk[k] + v[ab] * kk[ab][i] + relax;
        b[ab] -= relax * x[ab][i];
      }
      final sol = solveDense(a, b);
      for (var s = 0; s < ns; s++) xn[s][i] = m.max(sol[s], 0);
    }
    for (var s = 0; s < ns; s++) {
      final sum = xn[s].reduce((a, b) => a + b);
      for (var i = 0; i < nc; i++) x[s][i] = xn[s][i] / sum;
    }
  }

  void updateSpecs() {
    for (var k = 0; k < 3; k++) {
      if (!dry[k]) pk[k] = drawPct[k] / 100 * crudeM3h / 3600 / vStdMix(x[s2(k)]);
    }
    pPA = paFlowFrac * paM3h / 3600 / vStdMix(x[paDrawSt - 1]);
    feed = flash(z, cotC + 273.15, p[feedSt - 1]);
  }

  /// Inner loop at fixed reflux. Returns max |ΔT| of the last pass.
  double inner(int maxIt, {double relax = 0.0, double damp = 0.7}) {
    var dtMax = 0.0;
    for (var it = 0; it < maxIt; it++) {
      iters++;
      updateSpecs();
      props();
      if (!fixedFlows) solveFlows();
      // draw-dry active set
      for (var k = 0; k < 3 && !fixedFlows; k++) {
        final ld = l[drawSt[k] - 1];
        if (!dry[k] && ld < lMin) dry[k] = true;
        final spec = drawPct[k] / 100 * crudeM3h / 3600 / vStdMix(x[s2(k)]);
        if (dry[k] && pk[k] > spec) {
          dry[k] = false;
          pk[k] = spec;
        }
      }
      props();
      filterYw(ywRelax);
      solveComponents(relax);
      dtMax = 0.0;
      for (var s = 0; s < ns; s++) {
        final tn = bubbleT(x[s], pHC(s), t[s]);
        var d = damp * (tn - t[s]);
        if (d > 10) d = 10;
        if (d < -10) d = -10;
        t[s] += d;
        dtMax = m.max(dtMax, d.abs());
      }
      if (dtMax < 1e-9 && it > 5) break;
    }
    return dtMax;
  }

  /// Steady state by dynamic relaxation (cold: from the §13.1-style guess). The BP iteration above (inner) is kept
  /// only as a cross-check from a converged state: [polish] runs it and reports the largest T change.
  void solve({bool verbose = false, bool cold = true, double tEnd = 43200, double tol = 1e-7}) {
    if (cold) {
      init();
      setSteam();
      setPressures();
      updateSpecs();
      guessFlows();
      initDyn();
    }
    setSteam();
    final used = runDyn(tEnd, tol: tol, verbose: verbose);
    props();
    hydraulics();
    converged = used < tEnd;
    settle = used;
  }

  double settle = 0;

  double polish(int n) {
    fixedFlows = false;
    wFlow = 1.0;
    return inner(n, damp: 1.0);
  }

  // ------------------------------------------------------------ dynamic relaxation (cold start)
  // Engine-like time stepping: weir outflow from holdup, V from the quasi-steady energy balance (4.6) bottom-up
  // (strippers first), implicit component step, bubble-point T, TC-201 PI on the reflux, ideal drum and sump
  // levels, stripper bottom level on the draw (P-only with the feed-forward P_k + V_s1).
  final hold = List<double>.filled(ns, 0);
  double ssDia = 1.0, tcKc = 0.0, tcTi = 300, tcI = 0;
  double tSim = 0;
  final drawReq = List<double>.filled(3, 0);
  bool drumLimited = false;

  double diaOf(int a) => a < nm ? (a + 1 >= stripFrom ? dcStrip : dc) : ssDia;
  double aAof(int a) => m.pi * diaOf(a) * diaOf(a) / 4 * (1 - 2 * fd);
  double aNof(int a) => m.pi * diaOf(a) * diaOf(a) / 4 * (1 - fd);
  double lwOf(int a) => lw * diaOf(a) / dc;
  double dcStrip = 1.7;
  int stripFrom = 27;
  double vL(int a) => 1.15 * vStdMix(x[a]);
  double m0(int a) => aAof(a) * hw * 0.5 / vL(a);
  double weir(int a) {
    const al = 0.5;
    final cc = 0.501 + 0.438 * m.exp(-137.8 * hw);
    final h = hold[a] * vL(a) / (aAof(a) * al) - hw;
    if (h <= 0) return 0;
    return lwOf(a) * al * m.pow(h / cc, 1.5) / vL(a);
  }

  void initDyn() {
    for (var a = 0; a < ns; a++) hold[a] = 3 * m0(a);
    for (var a = 0; a < nm; a++) v[a] = m.max(v[a], 0.3 * fF);
    for (var k = 0; k < 3; k++) {
      v[s1(k)] = m.max(v[s1(k)], 0.2 * pk[k]);
      v[s2(k)] = m.max(v[s2(k)], 0.1 * pk[k]);
    }
    for (var a = 0; a < ns; a++) ywF[a] = ywRaw(a);
    tcKc = 2 * 95.0 / 50; // TC-201: Kc 1.0 on a 50 K span, FC-201 span 0–2 x 342 kmol/h (95 mol/s)
    tcI = l0;
  }

  void step(double dt) {
    updateSpecs();
    props();
    final lw0 = [for (var a = 0; a < ns; a++) weir(a)];
    // stripper level control on the draw; product limited when the stripper bottom runs low
    final pAct = List<double>.filled(3, 0);
    for (var k = 0; k < 3; k++) {
      final mref = 3 * m0(s2(k));
      pAct[k] = pk[k] * ((hold[s2(k)] - 0.2 * mref) / (0.3 * mref)).clamp(0.0, 1.0);
      drawReq[k] = m.max(0, pAct[k] + v[s1(k)] + (mref - hold[s2(k)]) / 60);
      final ad = drawSt[k] - 1;
      final avail = m.max(0.0, (hold[ad] - 0.3 * m0(ad)) / 1.0);
      sd[k] = m.min(drawReq[k], avail);
    }
    final ap = paDrawSt - 1;
    final paAct = m.min(pPA, m.max(0.0, (hold[ap] - 0.3 * m0(ap)) / 1.0));
    qPA = paAct <= 1e-9 ? 0.0 : m.min(paDuty, paAct * (hl[ap] - hLmix(x[ap], tRmin)));
    // liquid flows
    for (var j = 0; j < nm; j++) l[j] = lw0[j];
    for (var k = 0; k < 3; k++) {
      l[s1(k)] = lw0[s1(k)];
      l[s2(k)] = pAct[k];
    }
    // energy balance: strippers, then main bottom-up
    for (var k = 0; k < 3; k++) {
      final at = s1(k), ab = s2(k), ad = drawSt[k] - 1;
      v[ab] = m.max(0, (l[at] * (hl[at] - hl[ab]) + qSteam(ab)) / (hv[ab] - hl[ab]));
      v[at] = m.max(0, (sd[k] * (hl[ad] - hl[at]) + v[ab] * (hv[ab] - hl[at]) + qSteam(at)) / (hv[at] - hl[at]));
    }
    final hr = hLmix(yy[0], tDrum);
    final paH = hl[ap] - qPA / m.max(paAct, 1e-9);
    for (var j = nm; j >= 1; j--) {
      final a = j - 1;
      var num = qSteam(a);
      if (j == 1) {
        num += l0 * (hr - hl[0]);
      } else {
        num += l[a - 1] * (hl[a - 1] - hl[a]);
      }
      if (j < nm) num += v[a + 1] * (hv[a + 1] - hl[a]);
      if (j == feedSt) num += fF * (feed.h - hl[a]);
      if (j == paRetSt && paAct > 0) num += paAct * (paH - hl[a]);
      for (var k = 0; k < 3; k++) if (retSt[k] == j) num += v[s1(k)] * (hv[s1(k)] - hl[a]);
      v[a] = m.max(0, num / (hv[a] - hl[a]));
    }
    // TC-201 (PI, reverse acting: T1 high -> more reflux)
    final e = t[0] - (tTopSpC + 273.15);
    tcI += tcKc * e * dt / tcTi;
    l0 = m.max(0, tcI + tcKc * e);
    drumLimited = l0 > v[0];
    if (drumLimited) l0 = v[0];
    filterYw(m.min(1.0, dt / tauW));
    // holdups
    final mNew = List<double>.of(hold);
    for (var j = 1; j <= nm; j++) {
      final a = j - 1;
      var d = (j == 1 ? l0 : l[a - 1]) + (j < nm ? v[a + 1] : 0) - l[a] - v[a];
      if (j == feedSt) d += fF;
      if (j == paRetSt) d += paAct;
      if (j == paDrawSt) d -= paAct;
      for (var k = 0; k < 3; k++) {
        if (retSt[k] == j) d += v[s1(k)];
        if (drawSt[k] == j) d -= sd[k];
      }
      mNew[a] = m.max(1e-3, hold[a] + dt * d);
    }
    for (var k = 0; k < 3; k++) {
      mNew[s1(k)] = m.max(1e-3, hold[s1(k)] + dt * (sd[k] + v[s2(k)] - l[s1(k)] - v[s1(k)]));
      mNew[s2(k)] = m.max(1e-3, hold[s2(k)] + dt * (l[s1(k)] - pAct[k] - v[s2(k)]));
    }
    // implicit component step
    final xn = List.generate(ns, (_) => List<double>.filled(nc, 0));
    for (var i = 0; i < nc; i++) {
      final a = List.generate(ns, (_) => List<double>.filled(ns, 0));
      final b = List<double>.filled(ns, 0);
      for (var j = 1; j <= nm; j++) {
        final r = j - 1;
        a[r][r] = mNew[r] / dt;
        b[r] = hold[r] * x[r][i] / dt;
        if (j == 1) {
          a[r][0] -= l0 * kk[0][i];
        } else {
          a[r][r - 1] -= l[r - 1];
        }
        if (j < nm) a[r][r + 1] -= v[r + 1] * kk[r + 1][i];
        var out = l[r] + v[r] * kk[r][i];
        if (j == paDrawSt) out += paAct;
        if (j == paRetSt) a[r][ap] -= paAct;
        if (j == feedSt) b[r] += fF * z[i];
        for (var k = 0; k < 3; k++) {
          if (drawSt[k] == j) out += sd[k];
          if (retSt[k] == j) a[r][s1(k)] -= v[s1(k)] * kk[s1(k)][i];
        }
        a[r][r] += out;
      }
      for (var k = 0; k < 3; k++) {
        final at = s1(k), ab = s2(k);
        a[at][at] = mNew[at] / dt + l[at] + v[at] * kk[at][i];
        b[at] = hold[at] * x[at][i] / dt;
        a[at][drawSt[k] - 1] -= sd[k];
        a[at][ab] -= v[ab] * kk[ab][i];
        a[ab][ab] = mNew[ab] / dt + pAct[k] + v[ab] * kk[ab][i];
        b[ab] = hold[ab] * x[ab][i] / dt;
        a[ab][at] -= l[at];
      }
      final sol = solveDense(a, b);
      for (var s = 0; s < ns; s++) xn[s][i] = m.max(sol[s], 0);
    }
    for (var s = 0; s < ns; s++) {
      final sum = xn[s].reduce((a, b) => a + b);
      for (var i = 0; i < nc; i++) x[s][i] = xn[s][i] / sum;
      hold[s] = mNew[s];
      t[s] = bubbleT(x[s], pHC(s), t[s]);
    }
    for (var k = 0; k < 3; k++) pkAct[k] = pAct[k];
    paActual = paAct;
    tSim += dt;
  }

  final pkAct = List<double>.filled(3, 0);
  double paActual = 0;

  /// Run until |dT/dt| < tol (K/s) over a window, or tEnd. Returns the time used.
  double runDyn(double tEnd, {double dt = 1.0, double tol = 1e-6, bool verbose = false}) {
    final t0s = tSim;
    var tPrev = List<double>.of(t);
    var last = tSim;
    while (tSim - t0s < tEnd) {
      step(dt);
      if (tSim - last >= 300) {
        if (hydDp) {
          props();
          hydraulics();
          setPressures();
        }
        var dmax = 0.0;
        for (var s = 0; s < ns; s++) dmax = m.max(dmax, (t[s] - tPrev[s]).abs() / (tSim - last));
        if (verbose) {
          print('  t ${f(tSim / 3600, 2)} h  max dT/dt ${dmax.toStringAsExponential(2)}  T1 ${f(t[0] - 273.15)} T26 ${f(t[25] - 273.15)} '
              'L0 ${f(l0 * 3.6, 1)} D ${f((v[0] - l0) * 3.6, 1)} B ${f(l[nm - 1] * 3.6, 1)} sd ${sd.map((e) => f(e * 3.6, 1)).join("/")} '
              'pk ${pkAct.map((e) => f(e * 3.6, 1)).join("/")}');
        }
        tPrev = List<double>.of(t);
        last = tSim;
        if (dmax < tol) break;
      }
    }
    return tSim - t0s;
  }

  // ------------------------------------------------------------ hydraulics (§5, valve trays)
  double get aT => m.pi * dc * dc / 4;
  double get aN => aT * (1 - fd);
  double get aA => aT * (1 - 2 * fd);
  double get lw {
    var th = 2.0;
    for (var it = 0; it < 50; it++) {
      th -= ((th - m.sin(th)) / (2 * m.pi) - fd) / ((1 - m.cos(th)) / (2 * m.pi));
    }
    return dc * m.sin(th / 2);
  }

  double rhoLmix(int a) {
    var vl = 0.0, mw = 0.0;
    for (var i = 0; i < nc; i++) {
      vl += x[a][i] * pcs[i].mw / (1000 * pcs[i].rhoL(t[a]));
      mw += x[a][i] * pcs[i].mw;
    }
    return mw / 1000 / vl;
  }

  double mwL(int a) {
    var mw = 0.0;
    for (var i = 0; i < nc; i++) mw += x[a][i] * pcs[i].mw;
    return mw;
  }

  double sigmaMix(int a) {
    var s = 0.0;
    for (var i = 0; i < nc; i++) s += x[a][i] * m.pow(pcs[i].sigma(t[a]), 0.25);
    return m.pow(s, 4).toDouble();
  }

  /// vapour leaving stage a (HC + steam): [mol/s, MW, rho]
  List<double> vapour(int a) {
    final y = yy[a];
    final vh = v[a], sw = steamUp[a], tot = vh + sw;
    if (tot < 1e-6) return [0.0, 100.0, p[a] * 0.1 / (rGas * t[a])];
    var mw = 0.0, tc = 0.0, pc = 0.0, om = 0.0;
    for (var i = 0; i < nc; i++) {
      final yi = y[i] * vh / tot;
      mw += yi * pcs[i].mw;
      tc += yi * pcs[i].tc;
      pc += yi * pcs[i].pc * 1e5;
      om += yi * pcs[i].om;
    }
    final yw = sw / tot;
    mw += yw * water.mw;
    tc += yw * water.tc;
    pc += yw * water.pc * 1e5;
    om += yw * water.om;
    final tr = t[a] / tc, pr = p[a] / pc;
    final b0 = 0.083 - 0.422 / m.pow(tr, 1.6), b1 = 0.139 - 0.172 / m.pow(tr, 4.2);
    final zz = (1 + (b0 + om * b1) * pr / tr).clamp(0.30, 1.05);
    return [tot, mw, p[a] * mw / (1000 * zz * rGas * t[a])];
  }

  void hydraulics() {
    props();
    final lW0 = lw;
    for (var j = 1; j <= nm; j++) {
      final a = j - 1;
      final rl = rhoLmix(a), sig = sigmaMix(a);
      final vo = vapour(a);
      final qOut = vo[0] * vo[1] / (1000 * vo[2]);
      // vapour entering from below (stage j+1 vapour + stripper return at j, or bottom steam)
      double qIn;
      if (j < nm) {
        final vb = vapour(a + 1);
        qIn = vb[0] * vb[1] / (1000 * vb[2]);
        for (var k = 0; k < 3; k++) {
          if (retSt[k] == j) {
            final vs = vapour(s1(k));
            qIn += vs[0] * vs[1] / (1000 * vs[2]);
          }
        }
      } else {
        final sw = kgh2mol(steamBot);
        qIn = sw * rGas * t[a] / p[a];
      }
      final rv = vo[2];
      final mwl = mwL(a);
      final flv = vo[0] < 1e-6 ? 2.0 : ((l[a] * mwl) / (vo[0] * vo[1]) * m.sqrt(rv / rl)).clamp(0.01, 2.0);
      final csb = 0.0105 + 8.127e-4 * m.pow(ts * 1000, 0.755) * m.exp(-1.463 * m.pow(flv, 0.842));
      final unf = csb * m.pow(sig / 0.020, 0.2) * m.sqrt((rl - rv) / rv);
      flood[a] = (qOut / aNof(a)) / unf;
      // valve dry ΔP
      final aA = aAof(a), lW = lW0 * diaOf(a) / dc;
      final amin = rmin * fv * aA, amax = fv * aA;
      final dpc = rv / 2 * m.pow(qIn / (cvv * amin), 2);
      double dry0;
      if (dpc < dpLift) {
        dry0 = dpc;
      } else {
        final abal = qIn / (cvv * m.sqrt(2 * dpLift / rv));
        dry0 = abal <= amax ? dpLift : rv / 2 * m.pow(qIn / (cvv * amax), 2);
      }
      final ks = (qIn / aA) * m.sqrt(rv / (rl - rv));
      final ae = m.exp(-12.55 * m.pow(ks, 0.91));
      final cc = 0.501 + 0.438 * m.exp(-137.8 * hw);
      final qw = l[a] * mwl / (1000 * rl);
      hcl[a] = ae * (hw + cc * m.pow(qw / (lW * ae), 2 / 3));
      dp[a] = dry0 + rl * 9.80665 * hcl[a] + 4 * sig / dhV;
    }
  }

  // ------------------------------------------------------------ reporting
  List<double> get naphthaX => yy[0];
  List<double> prodX(int k) => x[s2(k)]; // 0 kero, 1 diesel, 2 AGO
  List<double> get residueX => x[nm - 1];
  double get dNaph => v[0] - l0;
  double get crudeM3s => crudeM3h / 3600;
  double volPct(double mol, List<double> xx) => 100 * mol * vStdMix(xx) / crudeM3s;
  double massKgh(double mol, List<double> xx) {
    var mw = 0.0;
    for (var i = 0; i < nc; i++) mw += xx[i] * pcs[i].mw;
    return mol * mw / 1000 * 3600;
  }

  double get yNaph => volPct(dNaph, naphthaX);
  double yProd(int k) => volPct(pkAct[k], prodX(k));
  double get yRes => volPct(l[nm - 1], residueX);
  double get overflash => volPct(l[feedSt - 2], x[feedSt - 2]);
  double get qc {
    final y1 = yy[0];
    return v[0] * (hVmix(y1, t[0]) - hLmix(y1, tDrum)) + steamUp[0] * (water.hV(t[0]) - water.hL(tDrum));
  }

  double get paReturnT {
    final x16 = x[paDrawSt - 1];
    final h = hl[paDrawSt - 1] - qPA / paActual;
    var tt = t[paDrawSt - 1];
    for (var it = 0; it < 50; it++) {
      var cp = 0.0;
      for (var i = 0; i < nc; i++) cp += x16[i] * (pcs[i].cp0 + pcs[i].dcp * (tt - t0));
      tt -= (hLmix(x16, tt) - h) / cp;
    }
    return tt;
  }

  double get waterDewMargin {
    final pw = p[0] * steamUp[0] / (steamUp[0] + v[0]);
    // T_sat of water at pw
    var tt = 360.0;
    for (var it = 0; it < 50; it++) tt -= (water.lnPsat(tt) - m.log(pw)) / water.dlnPsat(tt);
    return t[0] - tt;
  }

  List<List<double>> d86All() => [
        productD86(naphthaX),
        productD86(prodX(0)),
        productD86(prodX(1)),
        productD86(prodX(2)),
      ];

  double resTbp(double pct) => productTbp(residueX, pct);

  double energyResidual() {
    // in: feed, steam; out: products, water, Qc, Qpa
    var hin = fF * feed.h + kgh2mol(steamBot) * water.hV(tSteam);
    for (var k = 0; k < 3; k++) hin += kgh2mol(steamSS[k]) * water.hV(tSteam);
    final wTot = kgh2mol(steamBot) + kgh2mol(steamSS[0]) + kgh2mol(steamSS[1]) + kgh2mol(steamSS[2]);
    var hout = dNaph * hLmix(naphthaX, tDrum) + wTot * water.hL(tDrum) + qc + qPA;
    for (var k = 0; k < 3; k++) hout += pkAct[k] * hl[s2(k)];
    hout += l[nm - 1] * hl[nm - 1];
    return (hin - hout) / (fF * feed.h);
  }

  double massResidual() {
    double mw(List<double> xx) {
      var s = 0.0;
      for (var i = 0; i < nc; i++) s += xx[i] * pcs[i].mw;
      return s;
    }

    final fin = fF * mw(z);
    var out = dNaph * mw(naphthaX) + l[nm - 1] * mw(residueX);
    for (var k = 0; k < 3; k++) out += pkAct[k] * mw(prodX(k));
    return (fin - out) / fin;
  }

  void report(String tag, {bool profile = false}) {
    final d = d86All();
    final names = ['naph', 'kero', 'dsl', 'AGO'];
    print('== $tag  (settled ${f(settle / 3600, 2)} h, converged $converged, drum limited $drumLimited)');
    print('  yields vol%: naph ${f(yNaph)} kero ${f(yProd(0))} dsl ${f(yProd(1))} AGO ${f(yProd(2))} res ${f(yRes)}'
        '  overflash ${f(overflash)}  feed vap ${f(100 * volPct(fF * feed.beta, feed.y) / 100)} vol% (beta ${f(feed.beta, 4)})');
    print('  T °C: top ${f(t[0] - 273.15)} kero ${f(t[drawSt[0] - 1] - 273.15)} dsl ${f(t[drawSt[1] - 1] - 273.15)} '
        'PA ${f(t[paDrawSt - 1] - 273.15)}->${f(paReturnT - 273.15)} AGO ${f(t[drawSt[2] - 1] - 273.15)} '
        'FZ ${f(t[feedSt - 1] - 273.15)} bot ${f(t[nm - 1] - 273.15)}  SS bottoms ${[0, 1, 2].map((k) => f(t[s2(k)] - 273.15)).join("/")}');
    print('  reflux ${f(l0 * 3.6, 2)} kmol/h  naphtha ${f(dNaph * 3.6, 2)} kmol/h  Qc ${f(qc / 1e6, 3)} MW  '
        'P1 ${f(p[0] / 1e5, 3)} P26 ${f(p[feedSt - 1] / 1e5, 3)} P30 ${f(p[nm - 1] / 1e5, 3)} bar  colDP ${f((p[nm - 1] - p[0] + dp[nm - 1]) / 1000, 2)} kPa');
    print('  D86 5/50/95: ${[0, 1, 2, 3].map((k) => '${names[k]} ${f(d[k][1], 1)}/${f(d[k][4], 1)}/${f(d[k][7], 1)}').join("  ")}');
    print('  gaps: K-N ${f(d[1][1] - d[0][7], 1)}  D-K ${f(d[2][1] - d[1][7], 1)}  A-D ${f(d[3][1] - d[2][7], 1)}  '
        'res TBP 5 % ${f(resTbp(5), 1)}  waterDew margin ${f(waterDewMargin, 1)} K');
    print('  flood % min ${f(100 * flood.reduce(m.min), 1)} max ${f(100 * flood.reduce(m.max), 1)} (tray ${flood.indexOf(flood.reduce(m.max)) + 1})'
        '  dP/tray ${f(dp.reduce(m.min), 0)}..${f(dp.reduce(m.max), 0)} Pa  mass ${massResidual().toStringAsExponential(1)} energy ${energyResidual().toStringAsExponential(1)}');
    if (profile) {
      for (var j = 1; j <= nm; j++) {
        final a = j - 1;
        print('   ${j.toString().padLeft(2)} T ${f(t[a] - 273.15)} P ${f(p[a] / 1e5, 4)} L ${f(l[a] * 3.6, 1)} V ${f(v[a] * 3.6, 1)} '
            'S ${f(steamUp[a] * 3.6, 1)} flood ${f(100 * flood[a], 1)} dP ${f(dp[a], 0)} hcl ${f(hcl[a] * 1000, 1)}mm');
      }
      for (var k = 0; k < 3; k++) {
        print('   SS${k + 1}: draw ${f(sd[k] * 3.6, 2)} prod ${f(pk[k] * 3.6, 2)} Vtop ${f(v[s1(k)] * 3.6, 2)} kmol/h  T ${f(t[s1(k)] - 273.15)}/${f(t[s2(k)] - 273.15)}');
      }
    }
  }
}
