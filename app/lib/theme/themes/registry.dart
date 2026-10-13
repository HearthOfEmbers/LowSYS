import '../lowsys_theme.dart';
import 'blueprint.dart';
import 'control_room.dart';
import 'paper.dart';

/// Every theme the app ships. M4 adds the Control Room, M5 Paper; Phosphor and Brass arrive in M7 and M9.
const List<LowsysTheme> kThemes = [blueprintTheme, controlRoomTheme, paperTheme];

LowsysTheme themeById(String id) => kThemes.firstWhere((t) => t.id == id, orElse: () => blueprintTheme);
