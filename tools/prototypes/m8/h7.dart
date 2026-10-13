// bt_packed in Tier 2 (Raoult/Antoine, §3.3 enthalpies, §3.5 properties, Robbins ΔP in the pressure profile):
// preset defaults, the H7 base (narrower beds), the planning event, and F21 / F23 per bed.
import 'pk.dart';

Column mk({double dia = 1.2, double k = 1.0, int malBed = -1, double malF = 0, int crushBed = -1, double crush = 0,
    bool ideal = false}) {
  final c = Column([
    Section.bed(struct250, 4.5, diameter: dia, designFlux: 1.9),
    Section.bed(struct250, 4.5, diameter: dia, designFlux: 4.0),
  ], tier: 2, feedStage: 10, f: 100 * k / 3.6, idealHyd: ideal);
  if (malBed >= 0) c.sections[malBed].malF = malF;
  if (crushBed >= 0) c.sections[crushBed].crush = crush;
  return c;
}

const tiTrays = [1, 3, 5, 7, 9, 10, 12, 14, 16, 18];

void report(Column c, String tag, {bool profile = false}) {
  final ti = tiTrays.map((j) => f4(c.tC(j), 2)).join(' ');
  print('$tag: xD ${f4(c.xD, 5)} xB ${f4(c.xB, 5)} D ${f4(c.dKmolh, 3)} Qc ${f4(c.qc / 1000, 1)} kW  '
      'TB ${f4(c.tC(c.nT + 1), 2)} colDP ${f4(c.colDp, 1)} Pa  outer ${c.outer}');
  for (var s = 0; s < 2; s++) {
    final b = c.bed[s];
    print('   bed ${s + 1}: dP ${f4(b.dp, 1)} Pa  maxPhi ${f4(b.maxPhi, 4)}  S ${f4(b.s, 4)}  nTh ${f4(b.nTh, 3)}  Emal ${f4(b.eMal, 4)}');
  }
  print('   TI ${tiTrays.join("/")}: $ti');
  if (profile) {
    for (var j = 1; j <= c.nT; j++) {
      final si = c.seg[j];
      print('    $j T ${f4(c.tC(j), 2)} x ${f4(c.x[j][0], 5)} L\' ${f4(si.lp, 4)} G\' ${f4(si.gp, 4)} rV ${f4(si.rhoV, 3)} rL ${f4(si.rhoL, 1)} '
          'sig ${f4(si.sigma * 1000, 2)} phi ${f4(si.phi, 4)} hetp ${f4(si.hetp, 4)} lam ${f4(si.lam, 4)} Emv ${f4(si.emv, 4)} hL ${f4(si.hL, 5)}');
    }
  }
}

void main(List<String> args) {
  final c = mk();
  c.solve(l0kmolh: 100, qrKW: 1300);
  report(c, 'bt_packed T2 defaults', profile: true);
  final ci = mk(ideal: true);
  ci.solve(l0kmolh: 100, qrKW: 1300);
  report(ci, 'bt_packed T2 ideal hydraulics');

  if (args.contains('design')) {
    for (final dia in [1.0, 1.05, 1.1]) {
      final b = mk(dia: dia);
      b.solve(l0kmolh: 100, qrKW: 1300);
      report(b, 'H7 base D $dia');
      final e = mk(dia: dia, k: 1.25);
      e.solve(l0kmolh: 125, qrKW: 1625, dGuessKmolh: 62.5);
      report(e, 'H7 +25 % D $dia');
    }
    return;
  }
  // H7 at D 1.0 m: healthy base and the planning event, then F21 / F23 per bed, before and after the event.
  for (final k in [1.0, 1.25]) {
    final h = mk(dia: 1.0, k: k);
    h.solve(l0kmolh: 100 * k, qrKW: 1300 * k, dGuessKmolh: 50 * k);
    report(h, 'healthy k $k');
    for (final bedI in [0, 1]) {
      for (final s in [0.5, 0.75, 1.0]) {
        final c = mk(dia: 1.0, k: k, malBed: bedI, malF: 0.6 * s);
        c.solve(l0kmolh: 100 * k, qrKW: 1300 * k, dGuessKmolh: 50 * k);
        report(c, 'k $k F21 bed ${bedI + 1} s $s (f ${0.6 * s})');
      }
      for (final s in [0.3, 0.5, 0.7]) {
        final c = mk(dia: 1.0, k: k, crushBed: bedI, crush: s);
        c.solve(l0kmolh: 100 * k, qrKW: 1300 * k, dGuessKmolh: 50 * k);
        report(c, 'k $k F23 bed ${bedI + 1} s $s');
      }
    }
  }
}
