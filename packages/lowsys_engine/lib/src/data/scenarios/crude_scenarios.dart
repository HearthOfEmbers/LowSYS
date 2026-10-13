/// Guided scenario G16 (ENGINE_API.md 11.8, M9).
const String g16Json = r'''
{
  "id": "G16_crude_gaps",
  "kind": "guided",
  "title": "Crude cut points and gaps",
  "milestone": 9,
  "topic": "crude",
  "preset": "crude",
  "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": false,
  "view": "model",
  "levers": {
    "set": {},
    "lock": ["crudeRate", "pTop", "topTSp", "drumTSp", "hydraulics", "noise", "view"],
    "show": ["drawRate.kero", "drawRate.diesel", "drawRate.ago", "paDuty", "cot", "steam.bottom", "steam.ss1", "steam.ss2", "steam.ss3"]
  },
  "timeLimit": 21600,
  "parTime": 7200,
  "briefing": "The crude unit runs at 20 000 bbl/d with a furnace outlet at 345 °C and a 5 MW pumparound. The kerosene is too heavy and overlaps the diesel: the kerosene D86 95 % is 238 °C against a limit of 235 °C, and the diesel–kerosene gap is −9 K. Change the draws, the pumparound duty and the stripping steam to meet both specs, without letting the residue's front end drop (residue TBP 5 % must stay at or above 355 °C). Each move takes two to three hours of process time to settle: use the fast-forward.",
  "objectives": [
    {"id": "o1", "text": "Kerosene D86 95 % at or below 235 °C and diesel–kerosene gap at or above 0 K, with the residue TBP 5 % at or above 355 °C, at steady state.",
     "when": {"all": [{"metric": "crude.d86p95.kero", "op": "<=", "value": 508.15},
                      {"metric": "crude.gap.dieselKero", "op": ">=", "value": 0},
                      {"metric": "crude.residueTbp5", "op": ">=", "value": 628.15},
                      {"metric": "steady", "op": "==", "value": true}]},
     "holdFor": 600, "latch": true},
    {"id": "o2", "text": "What opened the diesel–kerosene gap?", "after": "o1",
     "answer": {"type": "choice",
                "options": ["more liquid flowing between the kero and diesel draws (less PA duty), or more diesel stripping steam",
                            "a smaller kero draw",
                            "more bottom steam",
                            "a lower top temperature"],
                "correct": 0}},
    {"id": "o3", "text": "What does a lower PA duty cost?", "after": "o2",
     "answer": {"type": "choice",
                "options": ["more condenser duty and more flood at the top: heat that the PA recovered at ≈ 265 °C now leaves through the cooling water",
                            "nothing, the heat balance is unchanged",
                            "a colder flash zone",
                            "less kerosene"],
                "correct": 0}}
  ],
  "hints": [
    {"after": 0, "text": "Open the Products tab. The kero D86 95 % and the diesel–kero gap bar both fail at the start."},
    {"after": 1800, "text": "Draws move cut points: a smaller kero draw lowers the kero's 95 % point. A gap needs fractionation: liquid flowing down between the two draws, or steam stripping the lighter tail."},
    {"after": 3600, "text": "The pumparound takes heat out below the kero draw, so less PA duty sends more reflux down past it. Diesel stripper steam lifts the diesel's 5 % point."}
  ],
  "events": [],
  "scoring": {"objectives": 0.6, "time": 0.2, "safety": 0.1, "quality": 0.1,
              "qualitySpec": {"metric": "crude.gap.dieselKero", "op": ">=", "value": 0}},
  "debrief": "Draw rates set cut points; fractionation and stripping set gaps. Moving 1 % of the crude from kero to diesel brought the kero's 95 % point under 235 °C. It left the diesel–kero overlap almost where it was: −7 K against −9 K at the start. What opened the gap was liquid flowing between the draws or steam in the diesel stripper. With the PA cut from 5 to 3 MW, the condenser duty rose by about a fifth and the top trays loaded up. Refiners pay that price when product quality matters more than the heat the pumparound recovers at about 265 °C."
}
''';

/// Drill H8 (ENGINE_API.md 11.12, M9).
const String h8Json = r'''
{
  "id": "H8_crude_drift", "kind": "drill", "title": "Crude product drift", "milestone": 9, "topic": "crude",
  "preset": "crude",
  "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady", "noise": true, "view": "plantCalc", "badPvShed": true,
  "levers": {"lock": ["tier", "hydraulics", "noise", "view", "badPvShed"]},
  "loops": {"TC-301": {"mode": "auto"}, "FC-301": {"mode": "cas"}, "LC-301": {"mode": "auto"}, "LC-302": {"mode": "auto"},
            "FC-311": {"mode": "auto"}, "FC-312": {"mode": "auto"}, "FC-313": {"mode": "auto"}, "FC-314": {"mode": "auto"},
            "TC-320": {"mode": "auto"}, "FC-321": {"mode": "auto"}, "FC-322": {"mode": "auto"}, "FC-323": {"mode": "auto"}, "FC-324": {"mode": "auto"}},
  "timeLimit": 7200,
  "briefing": "The crude unit runs steady at 20 000 bbl/d. The lab says the products have started to drift, and the shift log is empty. Find the cause: a stripping-steam problem, the pumparound, or the furnace?",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "steam_loss", "weight": 1,
     "fault": {"type": "strippingSteamLoss", "location": {"steam": "bottom"}, "severityRange": [0.7, 1.0], "ramp": 60},
     "answer": {"category": "steamLoss", "location": "steam:bottom"},
     "debrief": "**The bottom stripping steam failed** at {fault.onset:time} ({fault.magnitude}): FC-321 ran to 100 % with the flow far below its SP. With less steam the residue kept its diesel: the stage-30 temperature *rose* by 8–15 K, because there was less vaporisation to cool it. The residue yield rose and the diesel and AGO got heavier. Less vapour went up, so the condenser duty fell by a fifth or more. A furnace problem would have cooled the bottom instead."},
    {"id": "pa_trip", "weight": 1,
     "fault": {"type": "pumparoundTrip", "location": {"equipment": "pumparound"}, "severityRange": [0.7, 1.0], "ramp": 0},
     "answer": {"category": "pumparound", "location": "pumparound"},
     "debrief": "**The pumparound lost circulation** at {fault.onset:time} ({fault.magnitude}). FI-314 fell, and FC-314 could not hold the duty even with the cooler bypass shut. The heat it used to remove went up the column. The top temperature jumped several kelvin before TC-301 raised the reflux, and the condenser duty stayed 14–53 % higher. The diesel ran heavy for the first ten minutes. The bottom of the column hardly noticed."},
    {"id": "cot_low", "weight": 1,
     "fault": {"type": "cotUpset", "location": {"equipment": "furnace"}, "severityRange": [0.6, 1.0], "ramp": 300, "params": {"dT": -15}},
     "answer": {"category": "furnace", "location": "furnace"},
     "debrief": "**The furnace outlet was colder than TI-320 said** from {fault.onset:time} ({fault.magnitude}). TC-320 held its reading, but the crude reached the flash zone colder. The flash-zone and stage-30 temperatures *both* fell, by 7–14 K. The overflash dried up, the wash trays ran short of liquid, and the AGO got heavier. Raise the COT set point by the same amount, then get the thermocouple checked."}
  ],
  "offSpec": {"when": {"any": [{"metric": "crude.d86p95.kero", "from": "start", "op": ">", "value": 8},
                               {"metric": "crude.d86p95.diesel", "from": "start", "op": ">", "value": 10},
                               {"metric": "crude.yield.residue", "from": "start", "op": ">", "value": 1.0}]}, "holdFor": 300},
  "hints": [
    {"after": 1200, "cost": 0.03, "text": "Compare the bottom of the column with the flash zone (TI-350 and TI-349). Did they move together, or in opposite directions?"},
    {"after": 2400, "cost": 0.03, "text": "Look at the overhead: the top temperature TI-341, the reflux and the condenser duty. Heat that is not removed lower down ends up there."},
    {"after": 3600, "cost": 0.03, "text": "TI-320 is what the furnace controller sees. The flash-zone temperature is what the crude actually brings. Steam and pumparound flows have their own meters."}
  ],
  "diagnosis": {"categories": ["steamLoss", "pumparound", "furnace", "instrument", "none"],
                "locations": ["steam:*", "pumparound", "furnace", "instrument:TI-320", "instrument:TI-349"], "modes": [], "attempts": 2},
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "debrief": "Fault: {fault.magnitude} from {fault.onset:time}. First cross-check to fail: {result.firstFlaggedCheck}; product off-spec: {result.offSpecTime:time}; diagnosed: {result.diagnosisTime:time}."
}
''';
