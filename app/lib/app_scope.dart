import 'package:flutter/widgets.dart';

import 'controllers/sim_controller.dart';
import 'painters/column_painter.dart';

/// Exposes the controllers to the widget tree (ENGINE_API.md 13.2; no state-management package).
class AppScope extends InheritedWidget {
  final SimController sim;
  final ColumnAnimation anim;
  const AppScope({super.key, required this.sim, required this.anim, required super.child});

  static AppScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'No AppScope above this context');
    return s!;
  }

  @override
  bool updateShouldNotify(AppScope old) => old.sim != sim || old.anim != anim;
}
