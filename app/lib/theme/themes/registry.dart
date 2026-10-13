import '../lowsys_theme.dart';
import 'blueprint.dart';
import 'control_room.dart';

/// Every theme the app ships. M4 adds the Control Room; Paper, Phosphor and Brass arrive in M5, M7 and M9.
const List<LowsysTheme> kThemes = [blueprintTheme, controlRoomTheme];

LowsysTheme themeById(String id) => kThemes.firstWhere((t) => t.id == id, orElse: () => blueprintTheme);
