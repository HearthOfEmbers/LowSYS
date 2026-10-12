// Independent cross-check residuals and bands (PHYSICS.md §14.6) and the
// static residual each F19/F20 fault produces, for the detectability
// margins of ENGINE_API.md §11.5. Readings in kmol/h, %, kPa, K.
// No engine imports.
library;

import 'dart:math' as math;

/// B-T Tier 1 design constants.
const double n01pct = 307; // mol per 1 % drum level
const double ns1pct = 236; // mol per 1 % sump level
const double kmolhToMols = 1000 / 3600;

double band1(double fBar) => math.max(2.0, 0.02 * fBar);
double band3(double vRefl) => math.max(2.0, 0.015 * vRefl);
double band4(double fMax) => 0.015 * fMax;
double band5(double window) => 1.0 + 0.5 * window / 600;
const double band7 = 1.0; // K

/// C1 residual (kmol/h): F − D − B − (ΔN0 + ΔNS)/W.
double r1(
        double f, double d, double b, double dLt101, double dLt102, double w) =>
    f - d - b - ((dLt101 * n01pct + dLt102 * ns1pct) / kmolhToMols) / w;

/// C3 residual (Tier 1): V_boil − V_refl.
double r3(double vB, double q, double f, double l0, double d, double dLt101,
        double w) =>
    (vB + (1 - q) * f) - (l0 + d + (dLt101 * n01pct / kmolhToMols) / w);

/// C4 residual: measured − F_max · OP/100 (linear valve).
double r4(double fMeas, double fMax, double opPct) =>
    fMeas - fMax * opPct / 100;

/// C5 residual (% level): measured change − predicted change from flows.
double r5Drum(double dLtMeas, double vHat, double l0, double d, double w) =>
    dLtMeas - ((vHat - l0 - d) * kmolhToMols * w) / n01pct;

/// Static detectability: ratio |r| / band for each §11.5 minimum magnitude,
/// at the B-T design point (F 100, L0 100, D 50, B 50, V_B 150 kmol/h).
class Margin {
  final String fault, check;
  final double residual, band;
  const Margin(this.fault, this.check, this.residual, this.band);
  double get ratio => residual.abs() / band;
}

List<Margin> staticMargins() {
  final out = <Margin>[];
  // FT-102 bias 4 % of span = 12 kmol/h: loop holds the reading at SP, so the
  // true reflux is 88 and V_refl from readings is 100 + 50 = 150 while
  // V_boil = 150 → r3 is the difference between true and read reflux … the
  // boilup side is true, the reflux side reads 12 too high: r3 = −12.
  out.add(Margin('FT-102 bias 4 % span (12 kmol/h)', 'C3', -12, band3(150)));
  // C4:FV-102: OP settles so that the TRUE flow F_max·OP/100 = 88; the meter
  // says 100 → r4 = +12 vs band 0.015 × 300 = 4.5.
  out.add(Margin('FT-102 bias 4 % span', 'C4:FV-102', 12, band4(300)));
  // FT-101 drift 6 %/h of 250 = 15 kmol/h after 1 h: true feed 85, meter 100:
  // C1 = 100 − 50 − 50 − accumulation(≈ −15 drained → sump falls) ... the
  // level term reports the −15 kmol/h shortfall only as it drains: after the
  // level loops react, D + B true = 85 while meters read D, B true; r1 ≈ 15.
  out.add(
      Margin('FT-101 drift 6 %/h after 1 h (15 kmol/h)', 'C1', 15, band1(100)));
  out.add(Margin('FT-101 drift after 1 h', 'C4:FV-101', 15, band4(250)));
  // LT-101 bias 8 %: measured jump 8 pts with no flow change → r5 = 8 for one window
  out.add(Margin('LT-101 bias 8 %', 'C5:drum (W 600)', 8, band5(600)));
  // PT-101 bias 3 % of 202.65 kPa = 6.08 kPa → C7 both rows shift 0.33 K/kPa
  out.add(Margin(
      'PT-101 bias 3 % span (6.08 kPa)', 'C7 (each row)', 0.33 * 6.08, band7));
  // TI bias 5 K with neighbours quiet: |ΔT_k − ½(ΔT_a + ΔT_b)| = 5 vs max(1.0, 0) = 1
  out.add(Margin('TI bias 5 K', 'C6 (lone bar)', 5, 1.0));
  // FV-102 stuck then SP +5 kmol/h: OP runs to 100 % while the flow stays 100:
  // F_exp = 300 → r4 = 100 − 300 = −200; even the first 10 % of OP movement
  // (33.3 → 43.3 %) gives r4 = 100 − 130 = −30 vs 4.5.
  out.add(Margin('FV-102 stuck, OP +10 %', 'C4:FV-102', -30, band4(300)));
  return out;
}

/// Noise of a W-second mean of an OU-filtered reading with displayed σ and
/// effective correlation time τ_c: σ_mean ≈ σ √(2 τ_c / W).
double meanNoise(double sigma, double tauC, double w) =>
    sigma * math.sqrt(2 * tauC / w);
