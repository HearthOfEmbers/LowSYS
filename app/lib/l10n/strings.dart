/// Every user-facing string of the app chrome in one place (SCOPE.md M10: "all user strings in one localisation
/// file"). Only English ships; a second language would add a sibling class with the same members and switch
/// [S.current]. Text that lives in the engine (scenario briefings, hints, debriefs, alarm texts, lever and KPI
/// labels from `LeverSpec`) is content, not chrome, and is localised with the engine's scenario JSON
/// (docs/DEVIATIONS.md "M10 (coder, 2026-10-13)").
abstract final class S {
  // ---- app and simulator screen
  static const String appTitle = 'LowSYS';
  static const String settingUp = 'Setting up the drawing board…';
  static const String steadyTitle = 'Marching to steady state…';
  static const String steadyBody = 'Fast-forward with the column model itself, no shortcuts.';

  // ---- time bar menu
  static const String menuTooltip = 'Presets and options';
  static const String menuScenarios = 'Guided scenarios…';
  static const String menuLibrary = 'Library…';
  static const String menuTutorial = 'Tutorial…';
  static const String menuLeaveScenario = 'Leave scenario (sandbox)';
  static const String menuResetSteady = 'Reset to steady state';
  static const String menuShowRmin = 'Show R_min construction';
  static const String menuHideRmin = 'Hide R_min construction';
  static const String menuShading = 'Composition shading';
  static String menuUnits(bool si) => 'Units: ${si ? 'SI → US field' : 'US field → SI'} (U)';
  static String menuTheme(String name) => 'Theme: $name';
  static String menuSave(int slot) => 'Save sandbox to slot $slot';
  static String menuLoad(int slot) => 'Load sandbox slot $slot';

  // ---- generic
  static const String close = 'Close';
  static const String back = 'Back';
  static const String next = 'Next';
  static const String start = 'Start';
  static const String skip = 'Skip';
  static const String done = 'Done';
  static const String cancel = 'Cancel';
  static const String set = 'Set';

  // ---- scenario list and briefing
  static const String scenariosTitle = 'Guided scenarios';
  static const String drillTag = '(drill)';
  static const String coldStart = 'cold start';
  static const String startsSteady = 'starts steady';
  static String limit(String clock) => '$clock limit';
  static const String drillIntro = 'One fault is hidden in the plant and starts some minutes after you begin. Press Diagnose when you know the category and the location.';
  static String drillAttempts(int n) => 'You have $n attempts; wrong ones cost points.';
  static const String whatToDo = 'WHAT TO DO';
  static const String goals = 'GOALS';
  static const String savedAttempts = 'Your saved attempts (pick one to replay the same fault)';
  static String timeLimit(String clock) => 'Time limit $clock.';
  static String parTime(String par, String limit) => 'Par time $par, limit $limit.';

  // ---- lever and KPI semantics (accessibility)
  static String leverSemantics(String label, String value, String unit, {bool locked = false, bool loopSetpoint = false}) {
    final u = unit.isEmpty ? '' : ' $unit';
    return '$label${loopSetpoint ? ', set point' : ''}: $value$u${locked ? ', locked by the scenario' : ''}';
  }

  static const String leverEditHint = 'Double tap to type a value';
  static String leverDecrease(String label) => 'Decrease $label';
  static String leverIncrease(String label) => 'Increase $label';
  static String kpiSemantics(String label, String value, String unit) => '$label: $value${unit.isEmpty ? '' : ' $unit'}';
  static const String kpiHint = 'Double tap for the equations behind this value';
  static const String alarmOkWord = 'normal';
  static const String alarmWord = 'in alarm';

  // ---- library (S8)
  static const String libraryTitle = 'Library';
  static const String librarySubtitle = 'Short notes on the ideas the scenarios demonstrate. Open the scenario to see each one move.';
  static const String libraryOpenScenario = 'Open the scenario';
  static String libraryDemo(String scenarioTitle) => 'Shown in: $scenarioTitle';

  /// Concept cards: id, title, body, and the id of the scenario that demonstrates the idea.
  static const List<LibraryCard> libraryCards = [
    LibraryCard('min_reflux', 'Minimum reflux',
        'At minimum reflux the operating line touches the equilibrium curve and the separation needs infinitely many trays. Real columns run at 1.1 to 1.5 times R_min, where adding reflux buys trays back quickly at first and then slowly.',
        'G2_min_reflux'),
    LibraryCard('total_reflux', 'Total reflux and Fenske',
        'With no product withdrawn the operating lines lie on the diagonal and the steps are as large as they can be. Fenske gives the least number of stages from the end compositions and the relative volatility alone.',
        'G3_total_reflux'),
    LibraryCard('q_line', 'The q-line',
        'q is the liquid fraction of the feed, and the q-line is where the two operating lines meet. A colder feed tilts it, adds liquid below the feed, and raises the boilup you need.',
        'G4_q_line'),
    LibraryCard('feed_tray', 'Where to feed',
        'A feed on the wrong tray wastes separation: too high and the stripping section is short of trays, too low and the rectifying section is. The best tray is where the stepping crosses the intersection of the operating lines.',
        'G5_where_to_feed'),
    LibraryCard('murphree', 'Murphree efficiency',
        'A real tray reaches only part of the way to equilibrium. The Murphree efficiency is that fraction, and 0.7 means you need about 40 % more trays than the ideal count.',
        'G6_real_trays'),
    LibraryCard('cmo', 'Constant molar overflow',
        'The textbook assumption that vapour and liquid flows stay constant up the column. When latent heats differ, flows change from tray to tray and the energy balances, not the stepping alone, set the profile.',
        'G7_what_cmo_hides'),
    LibraryCard('pressure', 'Pressure and relative volatility',
        'Raising the pressure raises the boiling points and usually squeezes the relative volatility toward one. A higher pressure is cheaper to condense but harder to separate.',
        'G8_pressure_volatility'),
    LibraryCard('azeotrope', 'Azeotropes',
        'At an azeotrope the vapour and the liquid have the same composition, so no number of trays can go past it. Distillation alone stops at the azeotropic composition.',
        'G9_azeotrope_wall'),
    LibraryCard('flooding', 'Flooding',
        'At high vapour load the liquid cannot come down: froth backs up, the pressure drop climbs and separation collapses. Jet flooding and downcomer backup are the two limits to watch.',
        'G11_flooding'),
    LibraryCard('weeping', 'Weeping and turndown',
        'At low vapour load the liquid leaks through the holes instead of crossing the tray. Efficiency falls, and the lowest load a tray can take is its turndown limit.',
        'G12_turndown'),
    LibraryCard('thermosyphon', 'Thermosyphon reboilers',
        'Natural circulation depends on the density difference in the riser. Near its limits the loop can oscillate, so tuning means finding the steady circulation, not just more heat.',
        'G14_thermosyphon'),
    LibraryCard('keys', 'Key components and FUG',
        'In a multicomponent feed the light key and the heavy key decide the split. Fenske, Underwood and Gilliland give a quick estimate of stages and reflux from them.',
        'G13_debutanizer_fug'),
    LibraryCard('packing', 'Packing and HETP',
        'Packed beds are rated in height equivalent to a theoretical plate. Maldistribution and loading near flood make the HETP grow, and the pressure drop with it.',
        'G15_packing_retrofit'),
    LibraryCard('crude', 'Crude cut points and gaps',
        'A crude column makes several products with side strippers and pumparounds. Cut points are read from the TBP curves, and the gap between neighbouring cuts says how sharp the fractionation is.',
        'G16_crude_gaps'),
    LibraryCard('instruments', 'Do not trust one gauge',
        'A reading is a measurement, not the process. Mass and energy balances across the column tell you which instrument is lying.',
        'H9_dont_trust_the_gauge'),
  ];

  // ---- onboarding tutorial
  static const String tutorialTitle = 'Quick tour';
  static String tutorialStep(int i, int n) => 'Step $i of $n';
  static const List<TutorialStep> tutorialSteps = [
    TutorialStep('The column', 'The column is drawn live: liquid runs down the trays and vapour rises. Tap a tray or a stream to see the equations behind its numbers.'),
    TutorialStep('Levers', 'Reflux, boilup, feed and the rest are on the control panel. Move a slider, use the minus and plus buttons for fine steps, or tap the value to type one.'),
    TutorialStep('Time', 'The speed control at the top runs the plant faster than real time. Space pauses, and S marches straight to a steady state.'),
    TutorialStep('Read the results', 'The strip of numbers shows purities, flows, duties and the flood margin. Alarms appear at the top and carry a text label, never colour alone.'),
    TutorialStep('Learn more', 'The menu holds guided scenarios, hidden-fault drills and the Library of short notes, and you can reopen this tour from there.'),
  ];
}

/// One Library card.
class LibraryCard {
  final String id, title, body, scenarioId;
  const LibraryCard(this.id, this.title, this.body, this.scenarioId);
}

/// One tutorial step.
class TutorialStep {
  final String title, body;
  const TutorialStep(this.title, this.body);
}
