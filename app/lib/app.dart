import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'controllers/sim_controller.dart';
import 'painters/column_painter.dart';
import 'screens/sim_screen.dart';
import 'theme/lowsys_theme.dart';
import 'theme/theme_bridge.dart';
import 'theme/themes/blueprint.dart';
import 'theme/themes/registry.dart';

class LowsysApp extends StatefulWidget {
  final SimController? controller;
  final LowsysTheme theme;
  const LowsysApp({super.key, this.controller, this.theme = blueprintTheme});
  @override
  State<LowsysApp> createState() => _LowsysAppState();
}

class _LowsysAppState extends State<LowsysApp> {
  late final SimController _sim = widget.controller ?? SimController();
  final ColumnAnimation _anim = ColumnAnimation();

  @override
  void initState() {
    super.initState();
    _sim.themeId.value = widget.theme.id;
  }

  @override
  void dispose() {
    _sim.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _sim.themeId,
      builder: (context, id, _) {
        final theme = id == widget.theme.id ? widget.theme : themeById(id);
        return MaterialApp(
          title: 'LowSYS',
          debugShowCheckedModeBanner: false,
          theme: materialThemeFor(theme),
          builder: (context, child) => LowsysThemeScope(
            theme: theme,
            child: AppScope(sim: _sim, anim: _anim, child: child!),
          ),
          home: const SimScreen(),
        );
      },
    );
  }
}
