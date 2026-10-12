// Independent Tier-2 thermodynamics (PHYSICS.md §2.1, §2.2, §3.2, §3.3,
// §3.5, §3.6): Antoine / DIPPR-101 vapour pressures, Raoult K, binary
// bubble and dew points by bisection, Watson latent heats, the §3.3
// enthalpy path, Rackett density and the Pitzer virial Z. Pure Dart, no
// engine imports. Units: K, Pa, J/mol.
library;

import 'dart:math' as math;

const double r = 8.314462618;
const double atm = 101325.0;
const double t0 = 298.15;

enum VpKind { antoineLog10MmHgC, dippr101 }

class Comp {
  final String id;
  final double mw, tb, tc, pc, omega, dHvapTb, cp0, dCp, rhoRef, zraOverride;
  final VpKind vp;
  final List<double> c;
  const Comp(this.id, this.mw, this.tb, this.tc, this.pc, this.omega,
      this.dHvapTb, this.cp0, this.dCp, this.rhoRef, this.vp, this.c,
      {this.zraOverride = double.nan});

  /// Vapour pressure (Pa).
  double psat(double t) {
    switch (vp) {
      case VpKind.antoineLog10MmHgC:
        return math.pow(10, c[0] - c[1] / (t - 273.15 + c[2])) * 133.322368;
      case VpKind.dippr101:
        return math.exp(
            c[0] + c[1] / t + c[2] * math.log(t) + c[3] * math.pow(t, c[4]));
    }
  }

  /// d ln Psat / dT.
  double dLnPsatDt(double t) {
    switch (vp) {
      case VpKind.antoineLog10MmHgC:
        final d = t - 273.15 + c[2];
        return math.ln10 * c[1] / (d * d);
      case VpKind.dippr101:
        return -c[1] / (t * t) + c[2] / t + c[3] * c[4] * math.pow(t, c[4] - 1);
    }
  }

  double hL(double t) => cp0 * (t - t0) + 0.5 * dCp * (t - t0) * (t - t0);
  double dHvap(double t) =>
      t >= tc ? 0 : dHvapTb * math.pow((tc - t) / (tc - tb), 0.38);
  double hV(double t) => hL(t) + dHvap(t);

  double get zra => zraOverride.isNaN ? 0.29056 - 0.08775 * omega : zraOverride;

  /// Rackett-ratio liquid density (kg/m³), reference 298.15 K.
  double rhoL(double t) =>
      rhoRef *
      math.pow(zra, math.pow(1 - t0 / tc, 2 / 7) - math.pow(1 - t / tc, 2 / 7));

  /// Normal boiling point from the vapour-pressure model (bisection).
  double tbModel() => bisect((t) => psat(t) - atm, 200, 0.98 * tc);
}

const benzene = Comp(
    'benzene',
    78.11,
    353.24,
    562.05,
    48.95e5,
    0.210,
    30720,
    135.69,
    0.22,
    873.6,
    VpKind.antoineLog10MmHgC,
    [6.90565, 1211.033, 220.790]);
const toluene = Comp(
    'toluene',
    92.14,
    383.78,
    591.75,
    41.08e5,
    0.264,
    33180,
    157.29,
    0.26,
    862.3,
    VpKind.antoineLog10MmHgC,
    [6.95464, 1344.800, 219.482]);
const methanol = Comp('methanol', 32.04, 337.69, 512.50, 80.84e5, 0.565, 35210,
    81.1, 0.25, 786.6, VpKind.antoineLog10MmHgC, [8.07240, 1574.990, 238.870]);
const ethanol = Comp('ethanol', 46.07, 351.44, 514.00, 61.37e5, 0.644, 38560,
    112.3, 0.30, 785.1, VpKind.antoineLog10MmHgC, [8.11220, 1592.864, 226.184]);
const acetone = Comp('acetone', 58.08, 329.22, 508.10, 47.00e5, 0.307, 29100,
    126.3, 0.15, 784.5, VpKind.antoineLog10MmHgC, [7.23160, 1277.030, 237.230]);
const chloroform = Comp(
    'chloroform',
    119.38,
    334.33,
    536.40,
    54.72e5,
    0.222,
    29240,
    114.2,
    0.08,
    1479.0,
    VpKind.antoineLog10MmHgC,
    [6.93710, 1171.200, 227.000]);
const water = Comp(
    'water',
    18.015,
    373.15,
    647.10,
    220.64e5,
    0.345,
    40660,
    75.3,
    0.01,
    997.0,
    VpKind.dippr101,
    [73.649, -7258.2, -7.3037, 4.1653e-6, 2],
    zraOverride: 0.4945);

double bisect(double Function(double) f, double lo, double hi, {int n = 200}) {
  var flo = f(lo);
  for (var i = 0; i < n; i++) {
    final mid = 0.5 * (lo + hi);
    final fm = f(mid);
    if (fm == 0 || (hi - lo) < 1e-12) return mid;
    if ((fm < 0) == (flo < 0)) {
      lo = mid;
      flo = fm;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// Binary Raoult mixture (light = a, heavy = b).
class Binary {
  final Comp a, b;
  const Binary(this.a, this.b);

  double sumKx(double t, double p, double x) =>
      (x * a.psat(t) + (1 - x) * b.psat(t)) / p;

  /// Bubble temperature at pressure p for light mole fraction x.
  double bubbleT(double p, double x) =>
      bisect((t) => sumKx(t, p, x) - 1, 150, 0.98 * math.min(a.tc, b.tc));

  /// Dew temperature for vapour light mole fraction y.
  double dewT(double p, double y) => bisect(
      (t) => (y * p / a.psat(t) + (1 - y) * p / b.psat(t)) - 1,
      150,
      0.98 * math.min(a.tc, b.tc));

  /// Equilibrium vapour light fraction at the bubble point.
  double yEq(double p, double x) {
    final t = bubbleT(p, x);
    return x * a.psat(t) / p;
  }

  double alpha(double t) => a.psat(t) / b.psat(t);

  double hL(double t, double x) => x * a.hL(t) + (1 - x) * b.hL(t);
  double hV(double t, double y) => y * a.hV(t) + (1 - y) * b.hV(t);
  double mwOf(double x) => x * a.mw + (1 - x) * b.mw;

  /// Liquid molar volume (m³/mol) from the Rackett densities.
  double vL(double t, double x) =>
      x * a.mw / 1000 / a.rhoL(t) + (1 - x) * b.mw / 1000 / b.rhoL(t);
}

const bt = Binary(benzene, toluene);
const mw = Binary(methanol, water);

/// Pitzer virial compressibility with Kay's rule (PHYSICS.md (3.12)).
double pitzerZ(double t, double p, List<Comp> comps, List<double> y) {
  var tcm = 0.0, pcm = 0.0, om = 0.0;
  for (var i = 0; i < comps.length; i++) {
    tcm += y[i] * comps[i].tc;
    pcm += y[i] * comps[i].pc;
    om += y[i] * comps[i].omega;
  }
  final tr = t / tcm, pr = p / pcm;
  final b0 = 0.083 - 0.422 / math.pow(tr, 1.6);
  final b1 = 0.139 - 0.172 / math.pow(tr, 4.2);
  return (1 + (b0 + om * b1) * pr / tr).clamp(0.30, 1.05);
}

/// Water saturation temperature at pressure p (DIPPR-101 inverse).
double waterTsat(double p) => bisect((t) => water.psat(t) - p, 273.16, 640);
