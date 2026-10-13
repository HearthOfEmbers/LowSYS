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
  // ================ widgets and painters (M10 coder pass 2)
  // ---- alarm_bar.dart
  static const String ack = 'ACK';
  static const String alarms = 'Alarms';
  static const String acknowledgeAll = 'Acknowledge all';
  static const String noActiveAlarms = 'No active alarms.';

  // ---- balance_panel.dart
  static const String window = 'Window';
  static const String checksUseMetersOnly = 'Every check uses meters and analysers only. A fault larger than about twice the band is unambiguous.';
  static const String c1MaterialBalance = 'C1  Material balance';
  static const String c2ComponentBalance = 'C2  Component balance';
  static const String c3TopVapour = 'C3  Top vapour';
  static const String c3aTopVapourFrom = 'C3a  Top vapour from the condenser duty';
  static const String c3bColumnEnergyBalance = 'C3b  Column energy balance';

  // ---- c6_card.dart
  static const String c6TrayTemperatures = 'C6  Tray temperatures';
  static const String setReference = 'Set reference';
  static const String collectingData = 'Collecting data';

  // ---- crude_fault_panel.dart
  static const String noFaultIsActive = 'No fault is active.';
  static const String clear = 'Clear';
  static const String f27NotInjectable = 'F27 (draw tray dry) is not injectable: raise the kero draw above about 15.5 % or the PA duty above about 7.5 MW and watch the product flows.';
  static const String loss = 'Loss';
  static const String severity = 'Severity';

  // ---- crude_products_panel.dart
  static const String tbpCurves = 'TBP curves';
  static const String volDistilled = 'vol % distilled';
  static const String volEvaporated = 'vol % evaporated';
  static const String n595GapsD86 = '5–95 gaps (D86 5 % heavy minus 95 % light)';
  static const String yieldsVolOfCrude = 'Yields (vol % of crude)';
  static const String actual = 'actual';
  static const String ideal = 'ideal';
  static const String overflash = 'Overflash';
  static const String residueTbp5 = 'Residue TBP 5 %';

  // ---- diagram_head.dart
  static const String tier1CannotRepresent = 'Tier 1 cannot represent this system: constant alpha has no azeotrope. Switch to Tier 3.';
  static const String notAvailableOnPlant = 'Not available on a real plant. The analysers show xD and xB, and the Balance tab checks the meters against each other.';
  static const String exportFigurePNG = 'Export figure (PNG)';

  // ---- drill_ui.dart
  static const String diagnose = 'Diagnose';
  static const String whatKindOfFault = 'What kind of fault is it?';
  static const String whereIsIt = 'Where is it?';
  static const String howDidItFail = 'How did it fail? (optional)';
  static const String submit = 'Submit';
  static const String coolingWater = 'Cooling water';
  static const String fouling = 'Fouling';
  static const String nonCondensables = 'Non-condensables';
  static const String foaming = 'Foaming';
  static const String trayDamage = 'Tray damage';
  static const String instrument = 'Instrument';
  static const String valve = 'Valve';
  static const String feedUpset = 'Feed upset';
  static const String steamSupply = 'Steam supply';
  static const String thermosyphon = 'Thermosyphon';
  static const String maldistribution = 'Maldistribution';
  static const String nothingIsWrong = 'Nothing is wrong';
  static const String restriction = 'Restriction';
  static const String condensateSteamTrap = 'Condensate / steam trap';
  static const String condenser = 'Condenser';
  static const String reboiler = 'Reboiler';
  static const String rectifyingSection = 'Rectifying section';
  static const String strippingSection = 'Stripping section';
  static const String feed = 'Feed';
  static const String packedBed = 'Packed bed';
  static const String packingDamageCrushed = 'Packing damage (crushed)';
  static const String floodingOperatingLimit = 'Flooding (operating limit)';
  static const String strippingSteamLoss = 'Stripping steam loss';
  static const String pumparound = 'Pumparound';
  static const String furnaceCOT = 'Furnace / COT';
  static const String wholeColumn = 'Whole column';
  static const String reboilerInletLine = 'Reboiler inlet line';
  static const String reboilerOutletLine = 'Reboiler outlet line';
  static const String bias = 'Bias';
  static const String drift = 'Drift';
  static const String stuck = 'Stuck';
  static const String signalLoss = 'Signal loss';
  static const String pluggedLine = 'Plugged line';
  static const String spiking = 'Spiking';
  static const String coated = 'Coated';
  static const String bottomStrippingSteamFc = 'Bottom stripping steam (FC-321)';
  static const String keroStripperSteamFc = 'Kero stripper steam (FC-322)';
  static const String dieselStripperSteamFc = 'Diesel stripper steam (FC-323)';
  static const String agoStripperSteamFc = 'AGO stripper steam (FC-324)';

  // ---- energy_panel.dart
  static const String tier1NoEnergyBalance = 'Tier 1 has no energy balance: the vapour flow is the same on every tray and the heat duties are not modelled. Switch to Tier 2 with the T1/T2 badge to see the condenser, the reboiler and the column energy balance.';
  static const String plantReadingsKnown = 'On a real plant only the readings are known: FT-201, TI-201, TI-202, PT-201 and FT-103.';
  static const String thermosyphonNotObservable = 'The circulation, exit quality and surge index are not observable on a real plant. Watch the boilup and the bottom temperatures for a ripple of 5 to 20 s.';
  static const String columnEnergyBalanceHeading = 'COLUMN ENERGY BALANCE';
  static const String limit100 = 'limit 1.00';
  static const String meanOfTheLoop = 'mean of the loop duty';
  static const String dutyQC = 'Duty Q_C';
  static const String uaEffectiveClean = 'UA effective / clean';
  static const String coolingWaterInOut = 'Cooling water in / out';
  static const String cwValvePv101 = 'CW valve PV-101';
  static const String condensingTemperature = 'Condensing temperature';
  static const String refluxSubcooling = 'Reflux subcooling';
  static const String inertsYI = 'Inerts y_I';
  static const String topPressure = 'Top pressure';
  static const String vapourProductPv102 = 'Vapour product PV-102';
  static const String reliefValve = 'Relief valve';
  static const String refluxTemperatureTi100 = 'Reflux temperature TI-100';
  static const String dutyDelivered = 'Duty delivered';
  static const String steamHeader = 'Steam header';
  static const String steamValveFv103 = 'Steam valve FV-103';
  static const String sumpTemperature = 'Sump temperature';
  static const String inFeedReboiler = 'In: feed + reboiler';
  static const String outCondenserProducts = 'Out: condenser + products';
  static const String residual = 'Residual';
  static const String inletValve = 'Inlet valve';
  static const String steamSideDutyFt = 'Steam-side duty (FT-103)';
  static const String sump = 'sump';
  static const String heater = 'heater';
  static const String column = 'column';

  // ---- fault_panel.dart
  static const String trayFaultsNeedFullHydraulics = 'Tray faults need full hydraulics. Switch Internals > Hydraulics to Full on the Levers tab.';
  static const String active = 'ACTIVE';
  static const String instrumentFault = 'Instrument fault';
  static const String f19AndF28A = 'F19 and F28: a transmitter lies, freezes, plugs or fails. Use the Balance tab and the signal look to find it.';
  static const String reads = 'Reads';
  static const String high = 'high';
  static const String low = 'low';
  static const String valveFaultF20 = 'Valve fault (F20)';
  static const String stuckValveNote = 'A stuck valve moves nothing while its OP wanders. Open the bypass to work around it.';
  static const String bed = 'Bed';
  static const String tray = 'Tray';
  static const String opening = 'Opening';
  static const String from = 'From';
  static const String to = 'To';
  static const String plugging = 'Plugging';
  static const String size = 'Size';
  static const String tabLevers = 'LEVERS';
  static const String tabLoops = 'LOOPS';
  static const String tabBalance = 'BALANCE';
  static const String tabTrends = 'TRENDS';
  static const String tabFaults = 'FAULTS';
  static const String tabEnergy = 'ENERGY';
  static const String step = 'step';
  static const String oneHourRamp = '1 h ramp';

  // ---- figure_chrome.dart
  static const String raoult = ' (Raoult)';
  static const String nrtl = ' (NRTL)';
  static const String dePriester = ' (DePriester)';

  // ---- lever_panel.dart
  static const String sp = 'SP';
  static const String hydraulics = 'Hydraulics';
  static const String tc101Cascade = 'TC-101 (cascade to the reboiler duty)';
  static const String trayType = 'Tray type';
  static const String antifoam = 'Antifoam';
  static const String measurementNoise = 'Measurement noise';
  static const String view = 'View';
  static const String loopOnBadSignal = 'Loop on a bad signal';
  static const String full = 'Full';
  static const String refluxFlow = 'Reflux flow';
  static const String refluxRatio = 'Reflux ratio';
  static const String total = 'Total';
  static const String partial = 'Partial';
  static const String kettle = 'Kettle';
  static const String off = 'Off';
  static const String onLabel = 'On';
  static const String trays = 'Trays';
  static const String packing = 'Packing';
  static const String mixed = 'Mixed';
  static const String sieve = 'Sieve';
  static const String modelTrueValues = 'Model (true values)';
  static const String plantReadingsOnly = 'Plant (readings only)';
  static const String plantCalculations = 'Plant + calculations';
  static const String keepsRunning = 'Keeps running';
  static const String dropsToMAN = 'Drops to MAN';

  // ---- loops_panel.dart
  static const String enableTheCascadeFC = 'Enable the cascade (FC-103 goes to CAS)';
  static const String spTrackedPv = 'SP tracked the PV when you switched to AUTO.';
  static const String signalLook5Min = 'Signal look (5 min σ)';
  static const String digitsLastChanged = 'Digits last changed';
  static const String showThePIDMath = 'Show the PID math';
  static const String bypass = 'Bypass';
  static const String op = 'OP';
  static const String man = 'MAN';
  static const String auto = 'AUTO';
  static const String cas = 'CAS';
  static const String feedFlow = 'Feed flow';
  static const String boilup = 'Boilup';
  static const String drumLevel = 'Drum level';
  static const String sumpLevel = 'Sump level';
  static const String trayTemperature = 'Tray temperature';
  static const String oos = 'OOS';

  // ---- math_overlay.dart
  static const String whatThisHides = 'WHAT THIS SIMPLIFICATION HIDES';

  // ---- process_fault_card.dart
  static const String feedAndUtilityFaults = 'Feed and utility faults (Tier 2)';
  static const String f08ToF15Their = 'F08 to F15. Their symptoms are on the Energy and Balance tabs.';
  static const String openTrapBypass = 'Open trap bypass';
  static const String n1Min = '1 min';
  static const String n30Min = '30 min';

  // ---- products_panel.dart
  static const String rBelowRmin = 'R is below R_min: no finite column reaches these recoveries.';
  static const String gcAnalysers = 'GC analysers (mole fractions)';
  static const String meanOfTopAnd = 'mean of top and bottom';
  static const String stagesInclReboiler = 'stages incl. reboiler';
  static const String sumOfEPlus = 'sum of E, plus reboiler';
  static const String alphaLKHK = 'alpha (LK/HK)';
  static const String nMinFenske = 'N_min (Fenske)';
  static const String rMinUnderwood = 'R_min (Underwood)';
  static const String rUsed = 'R used';
  static const String nGilliland = 'N (Gilliland)';
  static const String nRAboveFeed = 'N_R above feed (Kirkbride)';
  static const String rigorousNAct = 'Rigorous: N_act';
  static const String nRActAbove = 'N_R,act above feed';
  static const String rAct = 'R_act';
  static const String liveColumn = 'Live column';
  static const String targets98 = 'Targets 98 %';
  static const String n98R13 = '98 %, R = 1.3 R_min';

  // ---- scenario_ui.dart
  static const String answer = 'Answer…';
  static const String hints = 'Hints';
  static const String noHintsYetThey = 'No hints yet. They unlock as you work.';
  static const String retry = 'Retry';
  static const String backToSandbox = 'Back to sandbox';
  static const String yourAnswer = 'Your answer';

  // ---- time_bar.dart
  static const String runToSteadyState = 'Run to steady state (S)';
  static const String simulationSpeed = 'Simulation speed (+ / -)';
  static const String benzeneTolueneTextbook = 'Benzene–toluene (textbook)';
  static const String methanolWater = 'Methanol–water';
  static const String custom = 'Custom α';
  static const String ethanolWater = 'Ethanol–water';
  static const String acetoneChloroform = 'Acetone–chloroform';
  static const String isobutaneNButaneC4 = 'Isobutane–n-butane (C4 splitter)';
  static const String debutanizer6Components = 'Debutanizer (6 components)';
  static const String depropanizer6Components = 'Depropanizer (6 components)';
  static const String benzeneToluenePacked2 = 'Benzene–toluene, packed (2 × 4.5 m)';
  static const String crudeUnit20000 = 'Crude unit (20 000 bbl/d)';
  static const String tier1ConstantRelative = 'Tier 1: constant relative volatility and molar overflow.';
  static const String tier2IdealVLE = 'Tier 2: ideal VLE (Raoult) with energy balances.';
  static const String tier3NonIdeal = 'Tier 3: non-ideal VLE (NRTL or DePriester K) with energy balances.';

  // ---- tray_inspector.dart
  static const String tapTrayToInspect = 'Tap a tray on the column or a stage on the diagram to inspect it.';
  static const String trayNotObservable = 'Not observable on a real plant: tray compositions and flows are not measured. Use the Loops, Balance and Trends tabs.';
  static const String equations = 'Equations';
  static const String condenserDrum = 'condenser drum';
  static const String sumpAndReboilerEquilibrium = 'sump and reboiler (equilibrium stage)';
  static const String flood = 'flood';
  static const String hetp = 'HETP';
  static const String liquidHoldup = 'liquid holdup';
  static const String wetted = 'wetted';
  static const String downcomer = 'downcomer';
  static const String weeping = 'weeping';
  static const String refluxL0 = 'reflux L0';

  // ---- trends_panel.dart
  static const String now = 'now';
  static const String n10Min = '10 min';
  static const String n1H = '1 h';
  static const String n2H = '2 h';

  // ---- txy_chart.dart
  static const String txy = 'T-x-y';
  static const String xy = 'x-y';

  // ---- column_painter.dart

  // ---- crude_painter.dart
  static const String reflux = 'Reflux';
  static const String qcLimit = 'Q_C limit';
  static const String cot = 'COT';

  // ---- mccabe_painter.dart
  static const String yVapour = 'y  vapour';
  static const String pinch = 'pinch';
  static const String equilibrium = 'equilibrium';
  static const String actualOperatingLocus = 'actual operating locus';
  static const String qLine = 'q-line';
  static const String stages = 'stages';

  // ---- profile_painter.dart
  static const String idealHydraulicsNoTray = 'ideal hydraulics: no tray hydraulics (switch to Full)';
  static const String holdup = 'Holdup';
  static const String barTotalDPTick = 'bar = total dP, tick = dry dP';
  static const String barJetFloodFroth = 'bar = jet flood / froth fill, tick = downcomer';
  static const String barLiquidXTick = 'bar = liquid x, tick = vapour y';

  // ---- sim_layout.dart
  static const String controls = 'CONTROLS';
  // ================ remaining positional strings (M10 coder pass 2)
  // ---- crude_fault_panel.dart
  static const String f24TheSteamDelivered = 'F24: the steam delivered at one injection point is cut. Its FC saturates. The bottom steam shifts the stage-30 temperature up; stripper steam lightens that product.';
  static const String cutTheSteam = 'Cut the steam';
  static const String pumparoundCirculationLoss = 'Pumparound circulation loss';
  static const String f25ThePumpDelivers = 'F25: the pump delivers (1 − s) of its flow; s = 1 is a trip. The heat the pumparound removed goes up the column to the condenser.';
  static const String slowThePump = 'Slow the pump';
  static const String furnaceOutletUpset = 'Furnace outlet upset';
  static const String f26TheCrudeArrives = 'F26: the crude arrives colder than TC-320 thinks (true COT = SP + s × −15 K); TI-320 keeps reading the SP. Raise the SP to compensate.';
  static const String upsetTheFurnace = 'Upset the furnace';

  // ---- fault_panel.dart
  static const String packingMaldistribution = 'Packing maldistribution';
  static const String f21APluggedDistributor = 'F21: a plugged distributor sends more liquid to one side of the bed (f = 0.6 s). The pressure drop hardly moves; the separation and the bed temperature profile do.';
  static const String plugTheDistributor = 'Plug the distributor';
  static const String crushedPacking = 'Crushed packing';
  static const String f23ThePackingFactor = 'F23: the packing factor rises by 150 % of s and the bed gets 15 % of s shorter. Higher dP at the same load, earlier flooding.';
  static const String crushThePacking = 'Crush the packing';
  static const String brokenTray = 'Broken tray';
  static const String f04PartOfThe = 'F04: part of the deck is missing. Liquid and vapour bypass it.';
  static const String breakTray = 'Break tray';
  static const String fouledTrays = 'Fouled trays';
  static const String f05PluggedHolesOr = 'F05: plugged holes or a blocked downcomer. Pressure drop creeps up first.';
  static const String foulTrays = 'Foul trays';
  static const String f06TheFrothGets = 'F06: the froth gets lighter and the flood capacity falls. Antifoam works after a delay.';
  static const String startFoaming = 'Start foaming';
  static const String feedCompositionUpset = 'Feed composition upset';
  static const String f07MoreOfThe = 'F07: more of the light component in the feed (+15 points at full severity).';
  static const String upsetTheFeed = 'Upset the feed';

  // ---- kpi_strip.dart
  static const String drum = 'Drum';
  static const String naphtha = 'Naphtha';
  static const String kero = 'Kero';
  static const String diesel = 'Diesel';
  static const String ago = 'AGO';
  static const String residue = 'Residue';
  static const String keroD86P95 = 'Kero D86 95';
  static const String dieselKeroGap = 'D–K gap';
  static const String resTbp5 = 'Res TBP 5';

  // ---- products_panel.dart
  static const String theKeysAreNot = 'The keys are not adjacent in volatility: Fenske and Underwood need the light key and heavy key next to each other.';
  static const String theseRecoveriesDoNot = 'These recoveries do not split the keys: the light key must go to D and the heavy key to B.';

  // ---- tray_inspector.dart
  static const String tStarIdeal = 'T* (ideal)';
  static const String floodCap = 'Flood';
  static const String weepingCap = 'Weeping';
  static const String trayLower = 'tray';
  static const String ackButton = 'Ack';
  static const String condenserHeading = 'CONDENSER';
  static const String reboilerHeading = 'REBOILER';
  static const String thermosyphonHeading = 'THERMOSYPHON';
  static const String sumpCap = 'Sump';
  static const String idealCap = 'Ideal';
  // ================ dynamic captions (M10 coder pass 2)
  static const String alarmUnack = 'UNACK';
  static const String alarmRtn = 'RTN';
  static String alarmsAllAcked(int n) => '$n active, all acknowledged';
  static String alarmsNewOf(int newCount, int n) => '$newCount new / $n';
  static String alarmSince(String state, String clock) => '$state · since $clock';
  static String diagnosisResult(bool fullyCorrect, bool categoryOk, bool locationOk, int attemptsLeft) {
    if (fullyCorrect) return 'Correct.';
    final head = categoryOk
        ? 'The category is right, the location is not.'
        : (locationOk ? 'The location is right, the category is not.' : 'Not it.');
    return head + (attemptsLeft > 0 ? ' $attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} left.' : ' No attempts are left.');
  }
  static String answerResult(bool correct, int attemptsLeft) => correct
      ? 'Correct.'
      : (attemptsLeft > 0 ? 'Not quite. $attemptsLeft attempts left.' : 'Not correct, and no attempts are left.');
  static const String scenarioWord = 'Scenario';
  static String debriefTitle(String title, Object score) => '$title — $score / 100';
  static String debriefVerdict(bool completed, bool drill) =>
      completed ? (drill ? 'Diagnosed.' : 'All goals met.') : (drill ? 'Not diagnosed.' : 'Not all goals met.');
  static const String category = 'Category';
  static const String goalsWord = 'Goals';
  static const String timeWord = 'Time';
  static const String safetyWord = 'Safety';
  static const String location = 'Location';
  static const String productQuality = 'Product quality';
  static String scoreRow(String label, int? of) => of == null ? label : '$label (of $of)';
  static String faultSeverityLine(String description, double severity, double finalSeverity) =>
      '$description\nseverity ${(100 * severity).toStringAsFixed(0)} % (final ${(100 * finalSeverity).toStringAsFixed(0)} %)';
  static String injectOn(String target) => 'Inject on $target';
  static String rampLabel(String ramp) => 'ramp $ramp';
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
