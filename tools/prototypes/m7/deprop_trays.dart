// M7-S4 (spec lead, 2026-10-13): `deprop` tray layouts checked with the tray equations of PHYSICS.md 5.1-5.8 at the
// design flows. Pure Dart, no engine import: dart run tools/prototypes/m7/deprop_trays.dart
//
// Input rows: the engine's full-hydraulics steady state of `deprop` on valve trays 0.55 / 0.85 m (Tier 3, E 0.7,
// design levers, PC-101 Kc 120 / Ti 400 s; no weeping, so L_j is the whole downflow). Columns: tray j, V_{j+1} (mol/s,
// vapour entering), L_j (mol/s, leaving), MW_V of V_{j+1}, MW_L, rho_L, rho_V (kg/m3), sigma (N/m), v_L (m3/mol).
// The flows hardly depend on the deck (ideal and full hydraulics agree within 0.4 % in D), so every layout is
// evaluated on the same rows. Against the engine (scratch runs, DEVIATIONS.md "Spec rulings M7-S4/M8"): the valve
// row matches exactly (Phi_min 1.173 / 0.916, jet max 66 / 64 %, dP 10.52 kPa) and the f_h 0.05 sieve row closely
// (engine Phi_min 0.642, weeping 19.7 %, jet 85 %). On the f_h 0.10 sieve deck the engine sits in a 74 %-weeping
// state with less liquid crossing the decks (Phi_min 0.341, stripping jet 52 %); the rows here assume no weeping.
import 'dart:math' as math;

const rows = <List<double>>[
  [1, 26.743, 18.256, 44.82, 44.94, 456.5, 36.91, 4.434e-3, 9.8428e-5],
  [2, 26.608, 18.121, 45.16, 45.45, 457.0, 36.95, 4.389e-3, 9.9446e-5],
  [3, 26.442, 17.956, 45.61, 46.11, 457.5, 36.99, 4.330e-3, 1.0079e-4],
  [4, 26.254, 17.769, 46.16, 46.93, 457.9, 37.04, 4.253e-3, 1.0249e-4],
  [5, 26.060, 17.577, 46.81, 47.90, 458.2, 37.10, 4.156e-3, 1.0455e-4],
  [6, 25.882, 17.402, 47.52, 48.98, 458.1, 37.16, 4.041e-3, 1.0691e-4],
  [7, 25.737, 17.260, 48.27, 50.11, 457.7, 37.22, 3.913e-3, 1.0947e-4],
  [8, 25.629, 17.156, 49.02, 51.25, 457.0, 37.28, 3.779e-3, 1.1215e-4],
  [9, 25.553, 17.086, 49.80, 52.43, 456.1, 37.31, 3.642e-3, 1.1495e-4],
  [10, 25.607, 17.098, 50.67, 53.72, 455.2, 37.33, 3.500e-3, 1.1803e-4],
  [11, 25.462, 44.732, 50.87, 56.58, 453.4, 36.70, 3.209e-3, 1.2479e-4],
  [12, 25.631, 44.901, 51.13, 56.70, 452.6, 36.80, 3.173e-3, 1.2528e-4],
  [13, 25.860, 45.131, 51.46, 56.87, 451.6, 36.93, 3.125e-3, 1.2593e-4],
  [14, 26.171, 45.444, 51.89, 57.07, 450.2, 37.09, 3.062e-3, 1.2677e-4],
  [15, 26.600, 45.875, 52.41, 57.33, 448.4, 37.29, 2.981e-3, 1.2787e-4],
  [16, 27.203, 46.482, 53.04, 57.63, 445.8, 37.54, 2.877e-3, 1.2927e-4],
  [17, 28.089, 47.377, 53.77, 57.98, 442.3, 37.84, 2.740e-3, 1.3109e-4],
  [18, 30.585, 49.902, 54.66, 58.32, 437.0, 38.23, 2.555e-3, 1.3345e-4],
  [19, 30.120, 49.430, 55.51, 58.87, 414.0, 38.59, 1.965e-3, 1.4219e-4],
  [20, 29.892, 49.199, 56.30, 59.37, 420.0, 38.95, 2.112e-3, 1.4137e-4],
  [21, 29.847, 49.152, 57.01, 59.80, 424.5, 39.30, 2.224e-3, 1.4086e-4],
  [22, 29.926, 49.232, 57.62, 60.17, 427.9, 39.60, 2.303e-3, 1.4062e-4],
  [23, 30.076, 49.383, 58.15, 60.48, 430.2, 39.87, 2.353e-3, 1.4059e-4],
  [24, 30.255, 49.564, 58.61, 60.75, 431.7, 40.10, 2.381e-3, 1.4073e-4],
  [25, 30.431, 49.743, 59.04, 61.01, 432.6, 40.29, 2.392e-3, 1.4103e-4],
  [26, 30.586, 49.901, 59.49, 61.28, 433.0, 40.45, 2.389e-3, 1.4153e-4],
  [27, 30.714, 50.033, 60.08, 61.64, 433.0, 40.61, 2.369e-3, 1.4235e-4],
  [28, 30.854, 50.111, 60.96, 62.18, 432.5, 40.81, 2.328e-3, 1.4375e-4],
];
const v1 = 26.88, mwV1 = 44.6; // V_1 = L_0 + D (total condenser) and its MW

class Deck {
  final String name;
  final bool valve;
  final double dc, hw, fh, fv, ts, fd;
  const Deck(this.name, {this.valve = false, required this.dc, this.hw = 0.05, this.fh = 0.10, this.fv = 0.14, this.ts = 0.9, this.fd = 0.12});
}

const g = 9.80665;
double weirLength(double d, double fd) {
  var th = 2.0;
  for (var i = 0; i < 50; i++) {
    th -= ((th - math.sin(th)) / (2 * math.pi) - fd) / ((1 - math.cos(th)) / (2 * math.pi));
  }
  return d * math.sin(th / 2);
}

/// One tray at vapour scale [s] (V and L scaled together). Returns [jet, Phi, h_dc without the receiving tray, dP, h_cl, dc limit].
List<double> tray(Deck k, List<double> r, double vOut, double mwVout, double s) {
  final vin = r[1] * s, l = r[2] * s, mwv = r[3], mwl = r[4], rl = r[5], rv = r[6], sig = r[7], vl = r[8];
  final aT = math.pi * k.dc * k.dc / 4, aD = k.fd * aT, aN = aT - aD, aA = aT - 2 * aD, lw = weirLength(k.dc, k.fd);
  final qIn = vin * mwv / (1000 * rv), qOut = vOut * s * mwVout / (1000 * rv);
  final ks = qIn / aA * math.sqrt(rv / (rl - rv));
  final ae = math.exp(-12.55 * math.pow(ks, 0.91));
  final c = 0.501 + 0.438 * math.exp(-137.8 * k.hw);
  final q = l * vl;
  final hcl = ae * (k.hw + c * math.pow(q / (lw * ae), 2 / 3)); // Bennett (5.2) at the tray's own outflow
  double dpDry, ahRatio;
  if (!k.valve) {
    final ah = k.fh * aA;
    dpDry = rv / 2 * math.pow(qIn / ah / 0.73, 2);
    ahRatio = k.fh;
  } else {
    final aMin = 0.25 * k.fv * aA, aMax = k.fv * aA;
    final dpc = rv / 2 * math.pow(qIn / (0.65 * aMin), 2);
    if (dpc < 190) {
      dpDry = dpc;
    } else {
      final aBal = qIn / (0.65 * math.sqrt(2 * 190 / rv));
      dpDry = aBal <= aMax ? 190 : rv / 2 * math.pow(qIn / (0.65 * aMax), 2);
    }
    ahRatio = k.fv;
  }
  final dh = k.valve ? 0.040 : 0.0127;
  final dp = dpDry + rl * g * hcl + 4 * sig / dh;
  final flv = ((l * mwl) / (vOut * s * mwVout) * math.sqrt(rv / rl)).clamp(0.01, 2.0);
  final csb = 0.0105 + 8.127e-4 * math.pow(k.ts * 1000, 0.755) * math.exp(-1.463 * math.pow(flv, 0.842));
  final fHole = ahRatio >= 0.10 ? 1.0 : math.max(0.5, 5 * ahRatio + 0.5);
  final unf = csb * math.pow(sig / 0.020, 0.2) * math.sqrt((rl - rv) / rv) * fHole;
  final jet = (qOut / aN) / unf;
  final phi = math.sqrt(dpDry / (rl * g) / hcl);
  final uap = q / (lw * 0.038);
  final hdc = dp / (rl * g) + 0.166 * uap * uap;
  return [jet, phi, hdc, dp, hcl, 0.5 * (k.ts + k.hw)];
}

void main() {
  final layouts = <String, List<Deck>>{
    'sieve 0.55 / 0.85, f_h 0.10 (M7 close-out)': [const Deck('top', dc: 0.55), const Deck('bot', dc: 0.85)],
    'sieve 0.55 / 0.85, stripping f_h 0.05': [const Deck('top', dc: 0.55), const Deck('bot', dc: 0.85, fh: 0.05)],
    'sieve 0.55 / 0.85, stripping f_h 0.045, h_w 25 mm': [const Deck('top', dc: 0.55), const Deck('bot', dc: 0.85, fh: 0.045, hw: 0.025)],
    'sieve 0.55 / 0.70, stripping f_h 0.06, h_w 25 mm': [const Deck('top', dc: 0.55), const Deck('bot', dc: 0.70, fh: 0.06, hw: 0.025)],
    'valve 0.55 / 0.85 (B-T valve data)': [const Deck('top', valve: true, dc: 0.55), const Deck('bot', valve: true, dc: 0.85)],
    'valve 0.55 / 0.75': [const Deck('top', valve: true, dc: 0.55), const Deck('bot', valve: true, dc: 0.75)],
  };
  for (final e in layouts.entries) {
    print(e.key);
    for (final s in [1.0, 0.8, 0.6]) {
      final res = <List<double>>[];
      for (var j = 1; j <= 28; j++) {
        final r = rows[j - 1];
        final k = e.value[j <= 10 ? 0 : 1];
        final vOut = j == 1 ? v1 : rows[j - 2][1];
        final mwOut = j == 1 ? mwV1 : rows[j - 2][3];
        res.add(tray(k, r, vOut, mwOut, s));
      }
      // (5.10): add the receiving tray's clear-liquid height (its own outflow is a close stand-in for h_norm)
      for (var j = 0; j < 28; j++) {
        res[j][2] = (res[j][2] + (j < 27 ? res[j + 1][4] : 0.0)) / res[j][5];
      }
      String sec(int a, int b) {
        final t = res.sublist(a - 1, b);
        final jet = t.map((x) => x[0]), phi = t.map((x) => x[1]), dcf = t.map((x) => x[2]);
        final wmax = phi.map((p) => ((0.75 - p) / 0.55).clamp(0.0, 1.0)).reduce(math.max);
        return 'jet ${(100 * jet.reduce(math.min)).toStringAsFixed(0)}-${(100 * jet.reduce(math.max)).toStringAsFixed(0)} %, '
            'Phi_min ${phi.reduce(math.min).toStringAsFixed(3)} (weep ${(100 * wmax).toStringAsFixed(0)} %), dc <= ${(100 * dcf.reduce(math.max)).toStringAsFixed(0)} %';
      }
      final dpTot = res.map((x) => x[3]).reduce((a, b) => a + b);
      print('  load ${(100 * s).toStringAsFixed(0)} %: top ${sec(1, 10)} | stripping ${sec(11, 28)} | dP ${(dpTot / 1000).toStringAsFixed(2)} kPa');
    }
  }
}
