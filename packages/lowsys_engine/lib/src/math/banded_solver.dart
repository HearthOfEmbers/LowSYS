import 'dart:typed_data';

/// Thomas elimination extended by one sub-diagonal (PHYSICS.md 12.3).
///
/// Solves, for rows j = 0..n-1,
///   g[j] x[j-2] + a[j] x[j-1] + b[j] x[j] + c[j] x[j+1] = d[j]
/// without pivoting (the matrices of the stage model are diagonally dominant).
/// Eliminating the g entry only adds to the existing a entry, so there is no fill-in.
///
/// [cp] and [dp] are scratch arrays of length n; the solution is written to [out]
/// (which may alias [d]).
class BandedSolver {
  const BandedSolver._();

  static void solve(
    int n,
    Float64List g,
    Float64List a,
    Float64List b,
    Float64List c,
    Float64List d,
    Float64List out,
    Float64List cp,
    Float64List dp,
  ) {
    for (var j = 0; j < n; j++) {
      var aStar = a[j];
      var dStar = d[j];
      if (j >= 2) {
        final gj = g[j];
        aStar -= gj * cp[j - 2];
        dStar -= gj * dp[j - 2];
      }
      var bStar = b[j];
      if (j >= 1) {
        bStar -= aStar * cp[j - 1];
        dStar -= aStar * dp[j - 1];
      }
      cp[j] = c[j] / bStar;
      dp[j] = dStar / bStar;
    }
    out[n - 1] = dp[n - 1];
    for (var j = n - 2; j >= 0; j--) {
      out[j] = dp[j] - cp[j] * out[j + 1];
    }
  }
}
