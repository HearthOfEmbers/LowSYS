// G15 / bt_packed in Tier 1 (PHYSICS.md §2.3 M8 rules): 2 × 4.5 m struct250 in the B-T shell, feed on stage 10.
import 'dart:math';
import 'pk.dart';

Column btPacked({int tier = 1, double d1 = 1.9, double d2 = 4.2, double dia = 1.2, bool ideal = false}) => Column([
      Section.bed(struct250, 4.5, diameter: dia, designFlux: d1),
      Section.bed(struct250, 4.5, diameter: dia, designFlux: d2),
    ], tier: tier, feedStage: 10, idealHyd: ideal);

void report(Column c, {bool segs = true}) {
  print('xD ${f4(c.xD, 5)} xB ${f4(c.xB, 5)} D ${f4(c.dKmolh, 3)}  outer ${c.outer}');
  for (var s = 0; s < c.sections.length; s++) {
    final b = c.bed[s];
    print(' bed ${s + 1}: dP ${f4(b.dp, 1)} Pa  maxPhi ${f4(b.maxPhi, 4)}  S ${f4(b.s, 4)} nTh ${f4(b.nTh, 4)} Emal ${f4(b.eMal, 4)}');
  }
  if (!segs) return;
  for (var j = 1; j <= c.nT; j++) {
    final si = c.seg[j];
    print('  $j x ${f4(c.x[j][0], 5)} L\' ${f4(si.lp, 4)} G\' ${f4(si.gp, 4)} dP/H ${f4(si.dpPerM, 2)} phi ${f4(si.phi, 4)} '
        'hetp ${f4(si.hetp, 4)} lam ${f4(si.lam, 4)} EO ${f4(si.eo, 4)} Emv ${f4(si.emv, 4)} hL ${f4(si.hL, 5)}');
  }
}

void main() {
  print('=== bt_packed Tier 1, L0 100, VB 150 (designFlux placeholder 0.1) ===');
  var c = btPacked(d1: 0.1, d2: 0.1);
  c.solve(l0kmolh: 100, vbKmolh: 150);
  report(c);
  var lmin1 = 1e9, lmin2 = 1e9, lavg1 = 0.0, lavg2 = 0.0;
  for (var j = 1; j <= 9; j++) { lmin1 = min(lmin1, c.seg[j].lp); lavg1 += c.seg[j].lp / 9; }
  for (var j = 10; j <= 18; j++) { lmin2 = min(lmin2, c.seg[j].lp); lavg2 += c.seg[j].lp / 9; }
  print('bed L\' min/avg: ${f4(lmin1)} / ${f4(lavg1)};  ${f4(lmin2)} / ${f4(lavg2)}');

  print('\n=== bt_packed Tier 1 with designFlux 1.9 / 4.2 ===');
  c = btPacked();
  c.solve(l0kmolh: 100, vbKmolh: 150);
  report(c, segs: false);
  print('column dP ${f4(c.bed[0].dp + c.bed[1].dp, 1)} Pa; ratio 14.49 kPa / packed = ${f4(14490 / (c.bed[0].dp + c.bed[1].dp), 3)}');
  print('capacity gain at equal flood % (trays 62.9 %): ${f4(100 * (0.629 / c.maxPhi - 1), 2)} %');
  for (final b in c.bed) print('  bed gain ${f4(100 * (0.629 / b.maxPhi - 1), 2)} %');

  print('\n=== ideal hydraulics (HETP_ref, no dP) ===');
  final ci = btPacked(ideal: true);
  ci.solve(l0kmolh: 100, vbKmolh: 150);
  report(ci, segs: false);

  print('\n=== trays Tier 1, 20 trays E 0.7 feed 10 (ideal hydraulics; VC-4.1 self-check 0.981183) ===');
  final ct = Column([Section.trays(20, 0.7)], tier: 1, feedStage: 10);
  ct.solve(l0kmolh: 100, vbKmolh: 150);
  print('xD ${f4(ct.xD, 6)} xB ${f4(ct.xB, 6)}');

  print('\n=== throughput scan, packed T1 (F, L0, VB scaled) ===');
  for (final k in [1.0, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5]) {
    final cs = Column([
      Section.bed(struct250, 4.5, designFlux: 1.9),
      Section.bed(struct250, 4.5, designFlux: 4.2),
    ], tier: 1, feedStage: 10, f: 100 * k / 3.6);
    cs.solve(l0kmolh: 100 * k, vbKmolh: 150 * k);
    print('k $k xD ${f4(cs.xD, 5)} xB ${f4(cs.xB, 5)} dP ${f4(cs.bed[0].dp, 1)} / ${f4(cs.bed[1].dp, 1)} phi ${f4(cs.bed[0].maxPhi, 4)} / ${f4(cs.bed[1].maxPhi, 4)}');
  }

  print('\n=== mixed: struct250 4.5 m rectifying (9 seg) above 10 sieve trays E 0.7, feed 10 ===');
  final cm = Column([
    Section.bed(struct250, 4.5, designFlux: 1.9),
    Section.trays(11, 0.7),
  ], tier: 1, feedStage: 10);
  cm.solve(l0kmolh: 100, vbKmolh: 150);
  report(cm, segs: false);
  final cmi = Column([
    Section.bed(struct250, 4.5, designFlux: 1.9),
    Section.trays(11, 0.7),
  ], tier: 1, feedStage: 10, idealHyd: true);
  cmi.solve(l0kmolh: 100, vbKmolh: 150);
  print('mixed, ideal hydraulics: xD ${f4(cmi.xD, 5)} xB ${f4(cmi.xB, 5)}');

  print('\n=== VC-13 flooding steps: bt_packed T1, F, L0 and boilup together +10 % per step ===');
  for (var n = 0; n <= 6; n++) {
    final k = pow(1.1, n).toDouble();
    final vb = 150 * k;
    final cs = Column([
      Section.bed(struct250, 4.5, designFlux: 1.9),
      Section.bed(struct250, 4.5, designFlux: 4.0),
    ], tier: 1, feedStage: 10, f: 100 * k / 3.6);
    cs.solve(l0kmolh: 100 * k, vbKmolh: vb);
    print('n $n VB ${f4(vb, 1)} xD ${f4(cs.xD, 5)} xB ${f4(cs.xB, 5)} dP ${f4(cs.bed[0].dp, 1)} / ${f4(cs.bed[1].dp, 1)} '
        'phi ${f4(cs.bed[0].maxPhi, 4)} / ${f4(cs.bed[1].maxPhi, 4)} hL18 ${f4(cs.seg[18].hL, 5)} hetp18 ${f4(cs.seg[18].hetp, 4)}');
  }
}
