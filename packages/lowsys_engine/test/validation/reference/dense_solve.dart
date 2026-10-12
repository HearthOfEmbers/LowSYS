// Small dense linear solver (Gaussian elimination with partial pivoting).
// Used only by the independent steady-state reference. No engine imports.
library;

/// Solves A x = b in place. [a] is row-major n×n, [b] length n.
/// Returns the solution (a new list). Throws on a singular matrix.
List<double> solveDense(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [for (final row in a) List<double>.from(row)];
  final r = List<double>.from(b);
  for (var k = 0; k < n; k++) {
    var p = k;
    var best = m[k][k].abs();
    for (var i = k + 1; i < n; i++) {
      final v = m[i][k].abs();
      if (v > best) {
        best = v;
        p = i;
      }
    }
    if (best < 1e-300) throw StateError('singular matrix at column $k');
    if (p != k) {
      final t = m[k];
      m[k] = m[p];
      m[p] = t;
      final tb = r[k];
      r[k] = r[p];
      r[p] = tb;
    }
    final piv = m[k][k];
    for (var i = k + 1; i < n; i++) {
      final f = m[i][k] / piv;
      if (f == 0) continue;
      final ri = m[i];
      final rk = m[k];
      for (var j = k; j < n; j++) {
        ri[j] -= f * rk[j];
      }
      r[i] -= f * r[k];
    }
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = r[i];
    for (var j = i + 1; j < n; j++) {
      s -= m[i][j] * x[j];
    }
    x[i] = s / m[i][i];
  }
  return x;
}
