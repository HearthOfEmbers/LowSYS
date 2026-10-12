// VC-17 units: SI and US-field display conversions, exact round trips.
library;

import 'package:lowsys_engine/lowsys_engine.dart';
import 'package:test/test.dart';

import 'reference/units_reference.dart' as ref;
import 'reference/validation_expectations_m2.dart';

void main() {
  const si = UnitSystem.si;
  const us = UnitSystem.usField;

  test('VC-17 temperature 373.15 K → 100.00 °C / 212.00 °F', () {
    expect(si.fromSI(Quantity.temperature, vc17.tK), closeTo(vc17.tC, 1e-9));
    expect(us.fromSI(Quantity.temperature, vc17.tK), closeTo(vc17.tF, 1e-9));
  });
  test('VC-17 pressure 101 325 Pa → 1.01325 bar(a) / 14.6959 psia', () {
    expect(si.fromSI(Quantity.pressure, vc17.pPa), closeTo(vc17.pBar, 1e-4));
    expect(us.fromSI(Quantity.pressure, vc17.pPa), closeTo(vc17.pPsia, 1e-4));
  });
  test('VC-17 molar flow 1 mol/s → 3.6 kmol/h / 7.93664 lb-mol/h', () {
    expect(si.fromSI(Quantity.molarFlow, 1), closeTo(vc17.kmolh, 1e-5));
    expect(us.fromSI(Quantity.molarFlow, 1), closeTo(vc17.lbmolh, 1e-5));
  });
  test('VC-17 energy rate 1e6 W → 1000 kW / 3.41214 MMBtu/h', () {
    expect(si.fromSI(Quantity.energyRate, 1e6), closeTo(vc17.kw, 1e-5));
    expect(us.fromSI(Quantity.energyRate, 1e6), closeTo(vc17.mmbtuh, 1e-5));
  });
  test('VC-17 crude flow 132.5 m³/h → 20 001.6 bbl/d', () {
    final siVal = 132.5 / 3600; // m3/s
    expect(si.fromSI(Quantity.volumeFlowCrude, siVal), closeTo(132.5, 1e-9));
    expect(us.fromSI(Quantity.volumeFlowCrude, siVal), closeTo(vc17.bblD, 0.1));
    expect(us.toSI(Quantity.volumeFlowCrude, 20000) * 3600,
        closeTo(vc17.bbl20000InM3h, 1e-3));
  });
  test('VC-17 length 0.0254 m → 25.4 mm / 1.000 in', () {
    expect(si.fromSI(Quantity.smallLength, vc17.lenM), closeTo(vc17.mm, 1e-9));
    expect(
        us.fromSI(Quantity.smallLength, vc17.lenM), closeTo(vc17.inch, 1e-9));
  });
  test('VC-17 density 800 kg/m³ → 49.942 lb/ft³', () {
    expect(si.fromSI(Quantity.density, 800), closeTo(800, 1e-9));
    expect(us.fromSI(Quantity.density, 800), closeTo(vc17.lbft3, 1e-3));
  });
  test('VC-17 temperature difference 10 K → 18 °F', () {
    expect(si.fromSI(Quantity.temperatureDelta, 10), closeTo(10, 1e-9));
    expect(us.fromSI(Quantity.temperatureDelta, 10), closeTo(vc17.dF, 1e-9));
  });

  test(
      'VC-17 engine factors agree with primary definitions (independent reference)',
      () {
    expect(us.fromSI(Quantity.pressure, 1e5), closeTo(ref.paToPsia(1e5), 1e-9));
    expect(us.fromSI(Quantity.molarFlow, 2.5),
        closeTo(ref.molsToLbmolh(2.5), 1e-9));
    expect(
        us.fromSI(Quantity.energyRate, 3e6), closeTo(ref.wToMmbtuh(3e6), 1e-9));
    expect(us.fromSI(Quantity.volumeFlowCrude, 0.05),
        closeTo(ref.m3hToBblD(0.05 * 3600), 1e-6));
    expect(
        us.fromSI(Quantity.density, 650), closeTo(ref.kgm3ToLbft3(650), 1e-9));
    expect(us.fromSI(Quantity.length, 3), closeTo(3 / ref.ftToM, 1e-9));
  });

  test(
      'VC-17 round trip toSI(fromSI(v)) = v to 1e-12 relative for every quantity and system',
      () {
    for (final sys in [si, us]) {
      for (final q in Quantity.values) {
        for (final v in [1e-6, 0.37, 1.0, 42.0, 1e5, 3.7e8]) {
          final back = sys.toSI(q, sys.fromSI(q, v));
          // Temperature is affine (K − 273.15): the round trip carries the
          // absolute rounding of the offset, so it is judged absolutely.
          final tol = q == Quantity.temperature ? 1e-9 : 1e-12 * v.abs();
          expect((back - v).abs(), lessThanOrEqualTo(tol),
              reason: '${sys.name} $q v=$v');
        }
        if (q != Quantity.fraction &&
            q != Quantity.dimensionless &&
            q != Quantity.percent)
          expect(sys.symbol(q), isNotEmpty,
              reason: '$q has a symbol in ${sys.name}');
      }
    }
  });

  test('VC-17 affine quantities round-trip through zero and negatives', () {
    for (final sys in [si, us]) {
      for (final v in [0.0, -40.0, 273.15, 1000.0]) {
        expect(
            sys.toSI(Quantity.temperature, sys.fromSI(Quantity.temperature, v)),
            closeTo(v, 1e-10));
      }
    }
    // −40 is the same in °C and °F
    expect(si.fromSI(Quantity.temperature, 233.15), closeTo(-40, 1e-9));
    expect(us.fromSI(Quantity.temperature, 233.15), closeTo(-40, 1e-9));
  });
}
