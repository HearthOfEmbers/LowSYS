// Default crude preset at steady state (VC-15.4) with the profile; 'bp' adds the BP cross-check.
import 'column.dart';

void main(List<String> args) {
  final c = Crude();
  if (args.contains('nohyd')) c.hydDp = false;
  final sw = Stopwatch()..start();
  c.solve(verbose: args.contains('v'));
  print('solve ${sw.elapsedMilliseconds} ms');
  c.report('default', profile: true);
  if (args.contains('bp')) {
    final t1 = List.of(c.t);
    final d = c.polish(200);
    var dmax = 0.0;
    for (var a = 0; a < t1.length; a++) dmax = dmax > (c.t[a] - t1[a]).abs() ? dmax : (c.t[a] - t1[a]).abs();
    print('BP cross-check from the converged state: last-pass dT ${d.toStringAsExponential(2)} K, drift ${dmax.toStringAsExponential(2)} K');
    c.props();
    c.hydraulics();
    c.report('after BP polish');
  }
}
