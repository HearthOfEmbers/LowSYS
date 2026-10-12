import 'package:flutter/widgets.dart';

/// Layout classes of SCOPE.md 3.3, from the logical size of the window.
enum LayoutClass { compactPortrait, compactLandscape, medium, expanded }

LayoutClass layoutClassFor(Size s) {
  final w = s.width, h = s.height;
  if (h < 500 && w > h) return LayoutClass.compactLandscape;
  if (w < 600 && h >= w) return LayoutClass.compactPortrait;
  if (w < 1000) return LayoutClass.medium;
  return LayoutClass.expanded;
}
