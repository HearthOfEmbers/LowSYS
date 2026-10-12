import 'dart:math' as math;

/// Physical quantity kinds, used by the UI for unit conversion (ENGINE_API.md 12).
enum Quantity {
  temperature,
  temperatureDelta,
  pressure,
  pressureDelta,
  molarFlow,
  massFlow,
  volumeFlowLiquid,
  volumeFlowCrude,
  energyRate,
  enthalpyMolar,
  length,
  smallLength,
  area,
  volume,
  density,
  molarAmount,
  mass,
  time,
  fraction,
  percent,
  surfaceTension,
  viscosity,
  heatTransferCoeff,
  ua,
  velocity,
  specificArea,
  dimensionless,
}

/// Display unit system. All engine values are SI base units (mol, s, K, Pa, J, W, m, kg).
class UnitSystem {
  final String name;
  final bool _us;
  const UnitSystem._(this.name, this._us);

  static const si = UnitSystem._('SI', false);
  static const usField = UnitSystem._('US', true);

  static const double _lbMol = 453.59237;
  static const double _lb = 0.45359237;
  static const double _ft = 0.3048;
  static const double _in = 0.0254;
  static const double _psi = 6894.757293168;

  String symbol(Quantity q) {
    switch (q) {
      case Quantity.temperature:
        return _us ? '°F' : '°C';
      case Quantity.temperatureDelta:
        return _us ? '°F' : 'K';
      case Quantity.pressure:
        return _us ? 'psia' : 'bar(a)';
      case Quantity.pressureDelta:
        return _us ? 'psi' : 'kPa';
      case Quantity.molarFlow:
        return _us ? 'lb-mol/h' : 'kmol/h';
      case Quantity.massFlow:
        return _us ? 'lb/h' : 'kg/h';
      case Quantity.volumeFlowLiquid:
        return _us ? 'gpm' : 'm³/h';
      case Quantity.volumeFlowCrude:
        return _us ? 'bbl/d' : 'm³/h';
      case Quantity.energyRate:
        return _us ? 'MMBtu/h' : 'kW';
      case Quantity.enthalpyMolar:
        return 'kJ/mol';
      case Quantity.length:
        return _us ? 'ft' : 'm';
      case Quantity.smallLength:
        return _us ? 'in' : 'mm';
      case Quantity.area:
        return _us ? 'ft²' : 'm²';
      case Quantity.volume:
        return _us ? 'ft³' : 'm³';
      case Quantity.density:
        return _us ? 'lb/ft³' : 'kg/m³';
      case Quantity.molarAmount:
        return _us ? 'lb-mol' : 'kmol';
      case Quantity.mass:
        return _us ? 'lb' : 'kg';
      case Quantity.time:
        return 's';
      case Quantity.fraction:
        return '';
      case Quantity.percent:
        return '%';
      case Quantity.surfaceTension:
        return _us ? 'dyn/cm' : 'mN/m';
      case Quantity.viscosity:
        return _us ? 'cP' : 'mPa·s';
      case Quantity.heatTransferCoeff:
        return _us ? 'Btu/h·ft²·°F' : 'W/m²K';
      case Quantity.ua:
        return _us ? 'Btu/h·°F' : 'kW/K';
      case Quantity.velocity:
        return _us ? 'ft/s' : 'm/s';
      case Quantity.specificArea:
        return _us ? 'ft²/ft³' : 'm²/m³';
      case Quantity.dimensionless:
        return '';
    }
  }

  /// SI base value to the display value.
  double fromSI(Quantity q, double v) {
    switch (q) {
      case Quantity.temperature:
        return _us ? v * 9 / 5 - 459.67 : v - 273.15;
      case Quantity.temperatureDelta:
        return _us ? v * 1.8 : v;
      case Quantity.pressure:
        return _us ? v / _psi : v / 1e5;
      case Quantity.pressureDelta:
        return _us ? v / _psi : v / 1e3;
      case Quantity.molarFlow:
        return _us ? v * 3600 / _lbMol : v * 3.6;
      case Quantity.massFlow:
        return _us ? v * 3600 / _lb : v * 3600;
      case Quantity.volumeFlowLiquid:
        return _us ? v / 6.30901964e-5 : v * 3600;
      case Quantity.volumeFlowCrude:
        return _us ? v * 86400 / 0.158987294928 : v * 3600;
      case Quantity.energyRate:
        return _us ? v * 3600 / 1.05505585262e9 : v / 1e3;
      case Quantity.enthalpyMolar:
        return v / 1e3;
      case Quantity.length:
        return _us ? v / _ft : v;
      case Quantity.smallLength:
        return _us ? v / _in : v * 1e3;
      case Quantity.area:
        return _us ? v / (_ft * _ft) : v;
      case Quantity.volume:
        return _us ? v / (_ft * _ft * _ft) : v;
      case Quantity.density:
        return _us ? v / 16.018463373960138 : v;
      case Quantity.molarAmount:
        return _us ? v / _lbMol : v / 1e3;
      case Quantity.mass:
        return _us ? v / _lb : v;
      case Quantity.surfaceTension:
        return v * 1e3;
      case Quantity.viscosity:
        return v * 1e3;
      case Quantity.heatTransferCoeff:
        return _us ? v / 5.678263 : v;
      case Quantity.ua:
        return _us ? v * 3600 / 1.05505585262e3 / 1.8 : v / 1e3;
      case Quantity.velocity:
        return _us ? v / _ft : v;
      case Quantity.specificArea:
        return _us ? v * _ft : v;
      case Quantity.time:
      case Quantity.fraction:
      case Quantity.percent:
      case Quantity.dimensionless:
        return v;
    }
  }

  /// Display value back to the SI base value.
  double toSI(Quantity q, double v) {
    switch (q) {
      case Quantity.temperature:
        return _us ? (v + 459.67) * 5 / 9 : v + 273.15;
      case Quantity.temperatureDelta:
        return _us ? v / 1.8 : v;
      case Quantity.pressure:
        return _us ? v * _psi : v * 1e5;
      case Quantity.pressureDelta:
        return _us ? v * _psi : v * 1e3;
      case Quantity.molarFlow:
        return _us ? v * _lbMol / 3600 : v / 3.6;
      case Quantity.massFlow:
        return _us ? v * _lb / 3600 : v / 3600;
      case Quantity.volumeFlowLiquid:
        return _us ? v * 6.30901964e-5 : v / 3600;
      case Quantity.volumeFlowCrude:
        return _us ? v * 0.158987294928 / 86400 : v / 3600;
      case Quantity.energyRate:
        return _us ? v * 1.05505585262e9 / 3600 : v * 1e3;
      case Quantity.enthalpyMolar:
        return v * 1e3;
      case Quantity.length:
        return _us ? v * _ft : v;
      case Quantity.smallLength:
        return _us ? v * _in : v / 1e3;
      case Quantity.area:
        return _us ? v * _ft * _ft : v;
      case Quantity.volume:
        return _us ? v * _ft * _ft * _ft : v;
      case Quantity.density:
        return _us ? v * 16.018463373960138 : v;
      case Quantity.molarAmount:
        return _us ? v * _lbMol : v * 1e3;
      case Quantity.mass:
        return _us ? v * _lb : v;
      case Quantity.surfaceTension:
        return v / 1e3;
      case Quantity.viscosity:
        return v / 1e3;
      case Quantity.heatTransferCoeff:
        return _us ? v * 5.678263 : v;
      case Quantity.ua:
        return _us ? v * 1.8 * 1.05505585262e3 / 3600 : v * 1e3;
      case Quantity.velocity:
        return _us ? v * _ft : v;
      case Quantity.specificArea:
        return _us ? v / _ft : v;
      case Quantity.time:
      case Quantity.fraction:
      case Quantity.percent:
      case Quantity.dimensionless:
        return v;
    }
  }
}

/// Number formatting with sensible precision per quantity.
abstract final class Fmt {
  static String value(Quantity q, double v,
      [UnitSystem system = UnitSystem.si]) {
    if (v.isNaN) return '—';
    if (v.isInfinite) return v > 0 ? '∞' : '-∞';
    final d = system.fromSI(q, v);
    switch (q) {
      case Quantity.fraction:
        return d.toStringAsFixed(d.abs() > 0.99 ? 6 : 4);
      case Quantity.temperature:
      case Quantity.temperatureDelta:
        return d.toStringAsFixed(1);
      case Quantity.percent:
        return d.toStringAsFixed(1);
      case Quantity.pressure:
        return sig(d, 4);
      default:
        return sig(d, 3);
    }
  }

  /// [digits] significant figures, no exponent for ordinary magnitudes.
  static String sig(double v, int digits) {
    if (v == 0) return '0';
    final a = v.abs();
    if (a >= 1e6 || a < 1e-3) return v.toStringAsExponential(digits - 1);
    final decimals =
        (digits - 1 - (math.log(a) / math.ln10).floor()).clamp(0, 12);
    return v.toStringAsFixed(decimals);
  }
}
