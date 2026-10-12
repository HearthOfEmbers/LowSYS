/// Guided scenario JSON as Dart raw strings (ENGINE_API.md 11.1, 11.8). M3 ships G1-G6 and the Tier 1 G11 and G12.
const String g11Json = r'''
{
  "id": "G11_flooding",
  "kind": "guided",
  "title": "Flooding",
  "milestone": 2,
  "topic": "hydraulics",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "full", "murphree": 0.7},
  "start": "steady",
  "levers": {
    "set": {},
    "lock": ["feedStage", "nTrays", "murphree", "trayType.0"],
    "show": ["feedFlow", "refluxFlow", "boilup"]
  },
  "timeLimit": 28800,
  "briefing": "A 20-tray benzene-toluene column runs at about 63 % of flood. Raise the load in steps of 10 % (feed, reflux and boilup together) and watch the column.\n\nWhat to look for: the pressure drop rises faster than the load, the liquid carried up the column (entrainment) steals separation, xD collapses and the drum level creeps up.\n\nGoal: find the load at which the column floods, then back off to a stable operating point at 80-92 % of flood where xD is still at least 0.95.",
  "objectives": [
    {"id": "o1", "text": "Push the column into flood (max flood at least 100 %).",
     "when": {"metric": "kpi.maxFloodPct", "op": ">=", "value": 100}, "holdFor": 30, "latch": true},
    {"id": "o2", "text": "Back off to 80-92 % flood with xD at least 0.95 and hold it for 10 minutes.", "after": "o1",
     "when": {"all": [{"metric": "kpi.maxFloodPct", "op": "between", "lo": 80, "hi": 92},
                      {"metric": "kpi.xD", "op": ">=", "value": 0.95}]},
     "holdFor": 600, "latch": true},
    {"id": "o3", "text": "At what throughput (% of design) did the column start to flood?",
     "answer": {"type": "number", "correct": 160, "tolerance": 10}}
  ],
  "hints": [
    {"after": 900, "text": "Raise feed, reflux and boilup together by 10 % per step; it takes about six steps of 10 % to reach flood."},
    {"when": {"metric": "kpi.maxFloodPct", "op": ">=", "value": 100}, "text": "You are flooding. Cut boilup and reflux; the trays need minutes to drain, so be patient."},
    {"after": 3600, "text": "Watch the Profiles tab: flooding starts at the bottom trays where the vapour load is highest."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1,
              "qualitySpec": {"metric": "kpi.xD", "op": ">=", "value": 0.95}},
  "debrief": "Flood margin now {kpi.maxFloodPct:0.0} %, xD {kpi.xD:0.000}, column pressure drop {kpi.columnDp:0} Pa.\n\nFlooding is not an on/off switch: entrained liquid recycles up the column, so separation falls long before the trays physically fill. Operating at 80-90 % of flood leaves room for upsets."
}
''';

const String g12Json = r'''
{
  "id": "G12_turndown",
  "kind": "guided",
  "title": "Turndown and weeping",
  "milestone": 2,
  "topic": "hydraulics",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "full", "murphree": 0.7},
  "start": "steady",
  "levers": {
    "set": {},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["feedFlow", "refluxFlow", "boilup", "trayType.0"]
  },
  "timeLimit": 28800,
  "briefing": "Demand has fallen and the plant must run at 35 % throughput. Cut feed, reflux and boilup together to 35 % (35, 35 and 52.5 kmol/h).\n\nAt low vapour velocity the sieve holes can no longer hold the liquid: it weeps through the deck and skips the contact. Watch the weeping fraction, the efficiency and xB.\n\nThen change the trays to valve trays (Advanced > tray type) at the same throughput: the valves close up as the vapour falls and keep the deck sealed.",
  "objectives": [
    {"id": "o1", "text": "Run sieve trays at 35 % throughput until weeping exceeds 30 %.",
     "when": {"all": [{"metric": "lever.feedFlow", "op": "<=", "value": 11.12},
                      {"metric": "lever.trayType.0", "op": "==", "value": 0},
                      {"metric": "kpi.maxWeepFraction", "op": ">=", "value": 0.3}]},
     "holdFor": 60, "latch": true},
    {"id": "o2", "text": "Switch to valve trays at the same throughput: weeping below 5 % and xB at most 0.03, for 5 minutes.", "after": "o1",
     "when": {"all": [{"metric": "lever.feedFlow", "op": "<=", "value": 11.12},
                      {"metric": "lever.trayType.0", "op": "==", "value": 1},
                      {"metric": "kpi.maxWeepFraction", "op": "<", "value": 0.05},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.03}]},
     "holdFor": 300, "latch": true},
    {"id": "o3", "text": "Why don't valve trays weep yet?",
     "answer": {"type": "choice",
                "options": ["They have a larger hole area", "Closed valves keep the hole velocity up", "They are heavier", "The liquid is cooler"],
                "correct": 1}}
  ],
  "hints": [
    {"after": 600, "text": "Cut all three flows to 35 %: feed 35, reflux 35, boilup 52.5 kmol/h."},
    {"when": {"metric": "kpi.maxWeepFraction", "op": ">=", "value": 0.3}, "text": "The weeping tray bypasses its inlet liquid. Compare xB with the value at full load, then try valve trays."},
    {"after": 3600, "text": "Valve trays: Advanced group, tray type 1."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1,
              "qualitySpec": {"metric": "kpi.xB", "op": "<=", "value": 0.03}},
  "debrief": "Weeping {kpi.maxWeepFraction:0.00} of the inlet liquid, xD {kpi.xD:0.000}, xB {kpi.xB:0.000}.\n\nSieve trays have a turndown of about 2:1; valve trays follow the vapour rate and reach roughly 5:1 before weeping starts."
}
''';

const String g1Json = r'''
{
  "id": "G1_meet_the_column",
  "kind": "guided",
  "title": "Meet the column",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal", "murphree": 1.0},
  "start": "cold",
  "noise": false,
  "levers": {
    "set": {},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["feedFlow", "refluxFlow", "boilup"]
  },
  "timeLimit": 28800,
  "parTime": 14400,
  "briefing": "A benzene-toluene column starts cold: every tray holds the feed composition. Run it at 300x and watch the staircase on the McCabe-Thiele diagram settle as benzene climbs the column.\n\nWhen the steady indicator turns green, find the feed stage on the diagram: it is where the staircase switches from the rectifying operating line to the stripping line.",
  "objectives": [
    {"id": "o1", "text": "Let the column reach steady state.",
     "when": {"metric": "steady", "op": "==", "value": true}, "latch": true},
    {"id": "o2", "text": "Tap the feed stage on the McCabe-Thiele diagram.",
     "answer": {"type": "stage", "correct": [10]}}
  ],
  "hints": [
    {"after": 600, "text": "Use 300x and watch the staircase settle."},
    {"after": 3600, "text": "The feed stage is where the staircase switches lines."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1},
  "debrief": "Steady state reached with xD {kpi.xD:0.000} and xB {kpi.xB:0.000}.\n\nStarting from a cold column is the same as the textbook's start-up at total reflux: the composition profile builds from the middle outwards, and the slowest part is the sump and drum inventory."
}
''';

const String g2Json = r'''
{
  "id": "G2_min_reflux",
  "kind": "guided",
  "title": "Minimum reflux",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal", "murphree": 1.0,
                "sections[0].trays": 60, "feeds[0].stage": 30},
  "start": "steady",
  "noise": false,
  "levers": {
    "set": {"refluxMode": 1, "refluxRatio": 1.3, "boilup": 31.9444},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["refluxRatio", "boilup", "feedZ.benzene"]
  },
  "loops": {"LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}},
  "timeLimit": 86400,
  "parTime": 43200,
  "briefing": "A 60-tray column with a perfect tray efficiency separates benzene from toluene at a reflux ratio R = 1.3. Lower R in steps and watch the staircase squeeze against the pinch where the operating lines meet the equilibrium curve.\n\nGoal: keep xD at least 0.95 and xB at most 0.05 at steady state with R at most 1.20, then report the minimum reflux ratio R_min of the separation.",
  "objectives": [
    {"id": "o1", "text": "Hold xD at least 0.95 and xB at most 0.05 at steady state with R at most 1.20.",
     "when": {"all": [{"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "kpi.refluxRatio", "op": "<=", "value": 1.20},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 600, "latch": true},
    {"id": "o2", "text": "Report R_min.",
     "answer": {"type": "number", "correct": 1.10, "tolerance": 0.055}}
  ],
  "hints": [
    {"after": 0, "text": "Each time you change R, set boilup = 50 x (R + 1) kmol/h so that D stays at 50."},
    {"after": 14400, "text": "Watch the staircase near the q-line: the steps shrink as R falls. R_min is the ratio at which they would become infinitely many."},
    {"when": {"metric": "kpi.refluxRatio", "op": "<", "value": 1.12}, "text": "You are close to the pinch. Use the R_min construction on the diagram."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1,
              "qualitySpec": {"metric": "kpi.xD", "op": ">=", "value": 0.95}},
  "debrief": "At R = {kpi.refluxRatio:0.00} the column makes xD = {kpi.xD:0.000}. Your answer: R_min = {answer.o2:0.00}; the construction on the diagram gives 1.10.\n\nBelow R_min no number of trays can reach the specification; above it, every extra bit of reflux buys purity at the price of energy."
}
''';

const String g3Json = r'''
{
  "id": "G3_total_reflux",
  "kind": "guided",
  "title": "Total reflux and Fenske",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal", "murphree": 1.0,
                "sections[0].trays": 5, "feeds[0].stage": 3},
  "start": "steady",
  "noise": false,
  "levers": {
    "set": {},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["feedFlow", "refluxFlow", "boilup", "distillateValve", "bottomsValve"]
  },
  "timeLimit": 28800,
  "parTime": 7200,
  "briefing": "A short column of 5 trays. Put it on total reflux: stop the feed, close both product valves (level loops to MAN at 0 % OP) and set the reflux equal to the boilup.\n\nWhen it settles, the separation is the most the column can do: the Fenske equation gives the minimum number of equilibrium stages from xD and xB. Report N_min.",
  "objectives": [
    {"id": "o1", "text": "Total reflux: feed zero, both product valves closed, steady.",
     "when": {"all": [{"metric": "lever.feedFlow", "op": "<=", "value": 0.001},
                      {"metric": "loop[LC-101].mode", "op": "==", "value": "man"},
                      {"metric": "loop[LC-101].op", "op": "<=", "value": 0.1},
                      {"metric": "loop[LC-102].mode", "op": "==", "value": "man"},
                      {"metric": "loop[LC-102].op", "op": "<=", "value": 0.1},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 300, "latch": true},
    {"id": "o2", "text": "Report N_min from the Fenske equation.",
     "answer": {"type": "number", "correct": 6.0, "tolerance": 0.05}}
  ],
  "hints": [
    {"after": 600, "text": "With nothing leaving, reflux must equal boilup."},
    {"after": 3600, "text": "Fenske: N_min = ln[(xD/(1-xD)) ((1-xB)/xB)] / ln(alpha). The 5 trays plus the reboiler are 6 equilibrium stages."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1},
  "debrief": "At total reflux xD = {kpi.xD:0.0000}, xB = {kpi.xB:0.0000}. N_min from your numbers: {answer.o2:0.00}.\n\nNo real operation beats total reflux for separation; it is the limit that minimum reflux (G2) approaches from the other side."
}
''';

const String g4Json = r'''
{
  "id": "G4_q_line",
  "kind": "guided",
  "title": "The q-line",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal"},
  "start": "steady",
  "noise": false,
  "levers": {
    "set": {},
    "lock": ["feedStage", "nTrays", "murphree"],
    "show": ["feedQ", "refluxFlow", "boilup"]
  },
  "timeLimit": 172800,
  "parTime": 86400,
  "briefing": "The feed condition q tells how much of the feed is liquid: 1.2 subcooled, 1.0 saturated liquid, 0.5 half vapour, 0 saturated vapour. For each q, find a boilup that just meets the specification xD at least 0.95 and xB at most 0.05 with D held at 50 kmol/h.\n\nWatch the q-line on the diagram: all of its lines pass through the point (z, z) on the diagonal.",
  "objectives": [
    {"id": "o1", "text": "q = 1.2: meet the specs with boilup within 5 % of the minimum.",
     "when": {"all": [{"metric": "lever.feedQ", "op": "between", "lo": 1.19, "hi": 1.21},
                      {"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "steady", "op": "==", "value": true},
                      {"metric": "kpi.boilup", "op": "<=", "value": 37.625}]},
     "holdFor": 300, "latch": true},
    {"id": "o2", "text": "q = 1.0: the same.", "after": "o1",
     "when": {"all": [{"metric": "lever.feedQ", "op": "between", "lo": 0.99, "hi": 1.01},
                      {"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "steady", "op": "==", "value": true},
                      {"metric": "kpi.boilup", "op": "<=", "value": 33.6875}]},
     "holdFor": 300, "latch": true},
    {"id": "o3", "text": "q = 0.5: the same.", "after": "o2",
     "when": {"all": [{"metric": "lever.feedQ", "op": "between", "lo": 0.49, "hi": 0.51},
                      {"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "steady", "op": "==", "value": true},
                      {"metric": "kpi.boilup", "op": "<=", "value": 25.389}]},
     "holdFor": 300, "latch": true},
    {"id": "o4", "text": "q = 0: the same.", "after": "o3",
     "when": {"all": [{"metric": "lever.feedQ", "op": "between", "lo": -0.01, "hi": 0.01},
                      {"metric": "kpi.xD", "op": ">=", "value": 0.95},
                      {"metric": "kpi.xB", "op": "<=", "value": 0.05},
                      {"metric": "steady", "op": "==", "value": true},
                      {"metric": "kpi.boilup", "op": "<=", "value": 19.53}]},
     "holdFor": 300, "latch": true},
    {"id": "o5", "text": "Where does the q-line pivot?",
     "answer": {"type": "choice",
                "options": ["(xD, xD) on the diagonal", "(z, z) on the diagonal", "(xB, xB) on the diagonal", "(0, 0)"],
                "correct": 1}}
  ],
  "hints": [
    {"after": 600, "text": "Keep D = 50: reflux = boilup + (1 - q) x 100 - 50 kmol/h."},
    {"after": 7200, "text": "A colder feed needs more boilup, because the extra liquid must be heated by the vapour. A vapour feed needs the least."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1},
  "debrief": "Minimum boilup for the specs with D = 50 kmol/h: q = 1.2 needs about 129 kmol/h, q = 1.0 about 115.5, q = 0.5 about 87 and q = 0 about 67. A hotter feed brings its own vapour, so the reboiler does less.\n\nThe q-line, the operating lines and the diagonal all meet at the feed composition's pivot (z, z)."
}
''';

const String g5Json = r'''
{
  "id": "G5_where_to_feed",
  "kind": "guided",
  "title": "Where to feed",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal"},
  "start": "steady",
  "noise": false,
  "levers": {
    "set": {"feedStage": 6},
    "lock": ["nTrays", "murphree"],
    "show": ["feedStage", "refluxFlow", "boilup"]
  },
  "timeLimit": 172800,
  "parTime": 43200,
  "briefing": "The feed enters at tray 6, too high for this column. Move the feed tray and watch xD change at the same reflux and boilup. The diagram shows why: the best feed stage is where the staircase crosses the intersection of the operating lines.",
  "objectives": [
    {"id": "o1", "text": "Which feed tray gives the highest xD?",
     "answer": {"type": "stage", "correct": [11]}},
    {"id": "o2", "text": "Put the feed on that tray and let the column settle.",
     "when": {"all": [{"metric": "lever.feedStage", "op": "==", "value": 11},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 300, "latch": true}
  ],
  "hints": [
    {"after": 600, "text": "Try every feed tray from 8 to 14 and compare xD at steady state."},
    {"after": 7200, "text": "The optimum is where the staircase crosses the operating-line intersection."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1},
  "debrief": "With the feed on tray {lever.feedStage:0} the column makes xD = {kpi.xD:0.0000}. The best tray (11 here) puts the feed where the liquid on the tray matches the feed composition.\n\nA misplaced feed costs separation without costing any energy."
}
''';

const String g6Json = r'''
{
  "id": "G6_real_trays",
  "kind": "guided",
  "title": "Real trays (Murphree)",
  "milestone": 3,
  "topic": "textbook",
  "preset": "bt",
  "overrides": {"tier": "t1", "hydraulics": "ideal", "murphree": 0.5},
  "start": "steady",
  "noise": false,
  "levers": {
    "set": {},
    "lock": ["murphree", "feedStage"],
    "show": ["nTrays", "refluxFlow", "boilup"]
  },
  "timeLimit": 86400,
  "parTime": 28800,
  "briefing": "Real trays do not reach equilibrium: with a Murphree efficiency of 0.5 a tray does half the work of an ideal one. How many real trays does it take to reach xD = 0.98 at the same reflux and boilup?\n\nAdd trays a few at a time, let the column settle and read xD. The feed tray follows the column.",
  "objectives": [
    {"id": "o1", "text": "Reach xD of at least 0.98 at steady state.",
     "when": {"all": [{"metric": "kpi.xD", "op": ">=", "value": 0.98},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 300, "latch": true},
    {"id": "o2", "text": "Report the fewest trays that reached 0.98.",
     "answer": {"type": "number", "correct": 28, "tolerance": 1}},
    {"id": "o3", "text": "What stays about constant?",
     "answer": {"type": "choice",
                "options": ["The number of trays", "N x E (the equilibrium stages)", "The reflux ratio", "The feed rate"],
                "correct": 1}}
  ],
  "hints": [
    {"after": 600, "text": "Add trays a few at a time."},
    {"after": 7200, "text": "20 trays at E = 0.7 give 14 equilibrium stages. How many trays at E = 0.5 give 14?"}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1},
  "debrief": "xD = {kpi.xD:0.0000} with {lever.nTrays:0} trays. The product N x E, the number of equilibrium stages, is what sets the separation: 20 x 0.7 = 28 x 0.5 = 14."
}
''';
