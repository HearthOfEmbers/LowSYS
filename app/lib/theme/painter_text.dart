import 'package:flutter/widgets.dart';

/// Text scaling for text drawn by `CustomPainter`s (they have no `BuildContext`). [LowsysApp] sets it from the
/// platform text scaler; it is clamped to 1.0..[maxScale] because the painted layouts have fixed pixel boxes.
class PainterText {
  PainterText._();

  static const double maxScale = 1.3;

  static double _factor = 1.0;

  /// The scaler to pass to every painter `TextPainter`.
  static TextScaler get scaler => _factor == 1.0 ? TextScaler.noScaling : TextScaler.linear(_factor);

  static double get factor => _factor;

  /// Sets the factor from [scaler] (sampled at 14 px, the body size); returns it.
  static double update(TextScaler scaler) {
    _factor = (scaler.scale(14) / 14).clamp(1.0, maxScale).toDouble();
    return _factor;
  }
}
