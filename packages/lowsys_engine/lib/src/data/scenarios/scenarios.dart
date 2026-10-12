/// Guided scenario JSON as Dart raw strings (ENGINE_API.md 11.1). M2 ships G11 and G12 (Tier 1 versions).
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
  "briefing": "A 20-tray benzene-toluene column runs at about 83 % of flood. Raise the load in steps of 10 % (feed, reflux and boilup together) and watch the column.\n\nWhat to look for: the pressure drop rises faster than the load, the liquid carried up the column (entrainment) steals separation, xD collapses and the drum level creeps up.\n\nGoal: find the load at which the column floods, then back off to a stable operating point at 80-92 % of flood where xD is still at least 0.95.",
  "objectives": [
    {"id": "o1", "text": "Push the column into flood (max flood at least 100 %).",
     "when": {"metric": "kpi.maxFloodPct", "op": ">=", "value": 100}, "holdFor": 30, "latch": true},
    {"id": "o2", "text": "Back off to 80-92 % flood with xD at least 0.95 and hold it for 10 minutes.", "after": "o1",
     "when": {"all": [{"metric": "kpi.maxFloodPct", "op": "between", "lo": 80, "hi": 92},
                      {"metric": "kpi.xD", "op": ">=", "value": 0.95}]},
     "holdFor": 600}
  ],
  "hints": [
    {"after": 900, "text": "Raise reflux and boilup together: the vapour velocity sets the flood margin."},
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
     "holdFor": 300}
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
