import '../lowsys_theme.dart';
import 'blueprint.dart';
import 'brass.dart';
import 'control_room.dart';
import 'paper.dart';
import 'phosphor.dart';

/// Every theme the app ships. M4 adds the Control Room, M5 Paper; M7 adds Phosphor, M9 Brass.
const List<LowsysTheme> kThemes = [blueprintTheme, controlRoomTheme, phosphorTheme, paperTheme, brassTheme];

LowsysTheme themeById(String id) => kThemes.firstWhere((t) => t.id == id, orElse: () => blueprintTheme);
