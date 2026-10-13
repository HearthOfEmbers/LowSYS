/// Drill JSON as given in ENGINE_API.md 11.6 and 11.7 (Tier 2 content; playable from M4/M6).
const String h9Json = r'''
{
  "id": "H9_dont_trust_the_gauge",
  "kind": "drill",
  "title": "Don't trust the gauge",
  "milestone": 6,
  "topic": "instruments",
  "preset": "bt",
  "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": true,
  "view": "plant",
  "badPvShed": false,
  "levers": {
    "set": {"tc101Enable": 1, "tc101Tray": 14},
    "lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Tray"]
  },
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "cas"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"},
            "TC-101": {"mode": "auto"}},
  "timeLimit": 7200,
  "briefing": "You are taking over the board of the benzene–toluene column. Every loop is in AUTO and tray-14 temperature control (TC-101) sets the reboiler duty through FC-103. At some point during your shift either **one instrument starts lying** or **the process really changes**. Decide which, name the tag if it is an instrument, and keep the products on spec while you work it out.\n\nThis plant's old DCS does **not** put a loop in manual when its signal fails. Your tools: the **Balance** tab (every check uses meters only), each faceplate's **signal look** and **valve curve**, the trends, the temperature-profile chart with its reference, and **field checks** of the sight glasses LG-101 and LG-102 and the local gauge PG-101 (3 minutes each). You have two diagnosis attempts.",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "ft102_bias", "weight": 2,
     "fault": {"type": "instrument", "location": {"tag": "FT-102"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.7], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-102", "mode": "bias"},
     "protect": [{"tag": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102 (reflux flow) read {fault.magnitude} wrong from {fault.onset:time}.** FC-102 kept the *reading* at its set point, so the real reflux moved the other way by the same amount. The tell-tales: C4 for FV-102 went red (the valve's OP no longer matched the flow it should give), and C3 (vapour to the top: reboiler vs reflux + distillate) disagreed by the same amount, while every other check stayed green. The trend itself looked normal — a bias has normal noise. Right response: FC-102 to MAN, then set the OP from the valve curve, for example {valve[FV-102].op:0.0} %."},
    {"id": "ft102_plugged", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "FT-102"}, "params": {"kind": "plugged"}, "severityRange": [1.0, 1.0], "ramp": 300},
     "answer": {"category": "instrument", "location": "instrument:FT-102", "mode": "plugged"},
     "protect": [{"tag": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102's impulse line plugged at {fault.onset:time}.** The reading stopped following the process: its 5-minute σ dropped from about 1.2 kmol/h to under 0.1 (\"too steady\"). FC-102 then kept integrating the small offset between its set point and the trapped value, and walked the real reflux far away while the reading sat on the set point. C4 (FV-102) and C3 both failed. A stuck *valve* would have looked similar on the OP trend, but its flow reading would still have had normal noise and the balances would have agreed."},
    {"id": "ft101_drift", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-101"}, "params": {"kind": "drift", "sign": "random"}, "severityRange": [0.6, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-101", "mode": "drift"},
     "protect": [{"tag": "FC-101", "modes": ["man"]}],
     "debrief": "**FT-101 (feed flow) drifted by {fault.magnitude} per hour from {fault.onset:time}.** FC-101 held the reading, so the real feed walked away. C1 (feed in vs distillate + bottoms out) grew steadily, and so did C4 for FV-101. The sump level-vs-flows check (C5) failed in proportion to the window: drifts show best with a 30-min window."},
    {"id": "ft103_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-103"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.6], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-103", "mode": "bias"},
     "debrief": "**FT-103 (steam / reboiler duty) read {fault.magnitude} wrong from {fault.onset:time}.** This one hides well: TC-101 sets FC-103's set point from the tray-14 temperature, so it trimmed the duty set point until the real duty was right again — the product barely moved. The evidence is the energy balance: C3b (reboiler duty vs condenser duty + products) failed, and FV-103's OP did not match the duty it should give (C4). With temperature control in the loop, the right response is to *keep* the cascade and get the meter fixed."},
    {"id": "lt101_bias", "weight": 2,
     "fault": {"type": "instrument", "location": {"tag": "LT-101"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.8, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-101", "mode": "bias"},
     "protect": [{"tag": "LC-101", "modes": ["man"]}],
     "debrief": "**LT-101 (reflux drum level) read {fault.magnitude} wrong from {fault.onset:time}.** The reading jumped with no flow change to explain it. LC-101 then moved the distillate flow to bring the *reading* back to its set point, which shifted the real level by the same amount. C5 (drum level vs integrated flows) failed for one window after the jump, and the sight glass LG-101 disagreed with LT-101 at any time afterwards. That field check is the permanent proof."},
    {"id": "lt102_loss", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "LT-102"}, "params": {"kind": "signalLossLow"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-102", "mode": "signalLoss"},
     "protect": [{"tag": "LC-102", "modes": ["man"]}],
     "debrief": "**LT-102 (sump level) lost its signal at {fault.onset:time}.** The DCS flagged BAD PV (IOP−) at once. This plant does not shed the loop, so LC-102 saw −2.5 % and closed the bottoms valve, and the real sump began to fill. Diagnosis was the easy part; the score was in the response. LC-102 to MAN at the old OP within minutes, then LG-102 field checks to steer the level by hand."},
    {"id": "lt102_stuck", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "LT-102"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-102", "mode": "stuck"},
     "protect": [{"tag": "LC-102", "modes": ["man"]}],
     "debrief": "**LT-102 froze at {fault.onset:time}.** The trend became a perfectly flat line — the same digits for minutes, σ = 0 against a typical 0.8 %. LC-102 stopped correcting, so when the feed went up at 45 min the real sump level started to climb while the reading stayed put. C5 for the sump failed from then on."},
    {"id": "pt101_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "PT-101"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.3, 0.5], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:PT-101", "mode": "bias"},
     "protect": [{"tag": "PC-101", "modes": ["man"]}],
     "debrief": "**PT-101 (top pressure) read {fault.magnitude} wrong from {fault.onset:time}.** PC-101 moved the real pressure the other way, so every temperature shifted together, smoothly — that looks like a process change. What gave it away was C7: the drum temperature and the bottom temperature no longer matched the bubble points of the analysed products *at the measured pressure*, both off with the same sign (about 0.33 K per kPa). The local gauge PG-101 confirmed it."},
    {"id": "ti114_bias", "weight": 2,
     "fault": {"type": "instrument", "location": {"tag": "TI-114"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.25, 0.4], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:TI-114", "mode": "bias"},
     "protect": [{"tag": "TC-101", "modes": ["man"]}, {"tag": "FC-103", "modes": ["auto", "man"]}],
     "debrief": "**TI-114 read {fault.magnitude} wrong from {fault.onset:time}.** It is TC-101's measurement, so TC-101 moved the reboiler duty until the *reading* was back at its set point. The real stripping section was then several kelvin off, and the bottoms followed. In C6, TI-114's change since the reference sat near zero while TI-112 and TI-117 moved together: a lone bar in a quiet neighbourhood. Right response: break the cascade (TC-101 to MAN, or FC-103 to AUTO) and hold the duty."},
    {"id": "ti114_coated", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "TI-114"}, "params": {"kind": "coated"}, "severityRange": [0.8, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:TI-114", "mode": "coated"},
     "protect": [{"tag": "TC-101", "modes": ["man"]}, {"tag": "FC-103", "modes": ["auto", "man"]}],
     "debrief": "**TI-114's thermowell coated over from {fault.onset:time}:** its time constant went from 10 s to 10 × (1 + 9 × {fault.severity:0.00}) s. At steady state it reads right, so the evidence only appears in transients. When the feed rose at 45 min, TI-114 lagged its neighbours in C6 and TC-101 started to swing the duty. The fuzz on TI-114 also halved (signal look ≈ 0.5 of typical)."},
    {"id": "ti107_spiking", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "TI-107"}, "params": {"kind": "spiking"}, "severityRange": [0.5, 0.8], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:TI-107", "mode": "spiking"},
     "debrief": "**TI-107 went erratic at {fault.onset:time}:** spikes of tens of kelvin, several a minute, with BAD flickers. It controls nothing, so the process never noticed. The signal look (σ many times typical) and C6 flagged it at once."},
    {"id": "ft104_stuck", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-104"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-104", "mode": "stuck"},
     "debrief": "**FT-104 (distillate flow) froze at {fault.onset:time}.** It controls nothing in flow mode, so the column was fine. But the flat line (σ = 0) and the balances told the story: once LC-101 moved the real distillate after the feed change, C1 and C3 disagreed while C4 for LV-101 showed the valve moving with no change in the reading."},
    {"id": "feed_real", "weight": 2,
     "fault": {"type": "feedComposition", "params": {"dz": {"benzene": 0.08}, "sign": "random"}, "severityRange": [1.0, 1.0], "ramp": 900},
     "answer": {"category": "feedUpset", "location": "feed"},
     "debrief": "**Nothing was lying — the feed really changed** by {fault.sign}0.08 benzene from {fault.onset:time}, over 15 minutes. Every balance stayed green, the temperature profile moved as a smooth wave (C6, no lone bar), and the feed analyser AT-100 showed the change about 7–10 minutes later. When all the cross-checks agree, believe the instruments."}
  ],
  "events": [
    {"id": "feed_up", "at": 2700, "action": "setSp", "tag": "FC-101", "delta": 1.38889,
     "text": "Upstream raised the feed by 5 %; reflux and steam were raised 5 % with it."},
    {"at": 2700, "action": "setSp", "tag": "FC-102", "delta": 1.38889},
    {"at": 2700, "action": "setSp", "tag": "FC-103", "delta": 65000}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1200, "cost": 0.03, "text": "Open the **Balance** tab. Each row uses only meters. When a row turns red, ask which instruments feed it — the liar is one of them, unless a valve is involved."},
    {"after": 2400, "cost": 0.03, "text": "Check every loop's **valve curve** (C4). A lying flow meter fails its own valve check *and* a balance; a real process change fails neither."},
    {"after": 3300, "cost": 0.03, "text": "Look at the **signal look** on each faceplate: σ = 0 means frozen, far below typical means plugged, far above means erratic. For temperatures, compare each TI's change since the reference with its neighbours (C6)."},
    {"after": 4200, "cost": 0.03, "text": "Levels and pressure have field gauges. A field check takes 3 minutes and settles any argument about LT-101, LT-102 or PT-101."}
  ],
  "diagnosis": {
    "categories": ["instrument", "valve", "feedUpset", "fouling", "foaming", "trayDamage", "none"],
    "locations": ["instrument:*", "valve:*", "feed", "rectifying", "stripping", "reboiler", "condenser"],
    "modes": ["bias", "drift", "stuck", "signalLoss", "plugged", "spiking", "coated"],
    "attempts": 2
  },
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0.1, "mode": 0.05}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; product off-spec: {result.offSpecTime:time}; affected loop protected: {result.protectTime:time}; diagnosed: {result.diagnosisTime:time}."
}
''';

const String h10Json = r'''
{
  "id": "H10_valve_or_meter",
  "kind": "drill",
  "title": "Bad valve or bad meter?",
  "milestone": 6,
  "topic": "instruments",
  "preset": "bt",
  "overrides": {"tier": "t2", "hydraulics": "full"},
  "start": "steady",
  "noise": true,
  "view": "plant",
  "badPvShed": true,
  "levers": {"lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 7200,
  "briefing": "The reflux and steam loops on this column have been acting up. The night shift wrote: *\"FC-102 and FC-103 — one of them doesn't do what it says.\"* Maybe a control valve is sticking, maybe a flow meter is lying, maybe the feed changed and nobody told you. At 45 minutes planning will raise the reflux and duty set points by 5 %. Find out which it is: valve, meter or process.",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "fv102_stuck", "weight": 2,
     "fault": {"type": "valve", "location": {"tag": "FV-102"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "valve", "location": "valve:FV-102"},
     "protect": [{"tag": "FC-102", "modes": ["man"]}],
     "debrief": "**The reflux valve FV-102 stuck at {fault.onset:time}.** FC-102's OP started to wander, and later ran off when planning raised the set point, while the flow reading stayed within its normal noise of its old value. The flow *reading* was honest: it still had normal noise, and C3 (top vapour) and C1 stayed green. Only C4 for FV-102 failed — an OP that no longer matches the flow. The fix is the bypass: open `bypass.FV-102` and set the reflux by hand."},
    {"id": "fv103_stuck", "weight": 2,
     "fault": {"type": "valve", "location": {"tag": "FV-103"}, "params": {"kind": "stuck"}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "valve", "location": "valve:FV-103"},
     "protect": [{"tag": "FC-103", "modes": ["man"]}],
     "debrief": "**The steam valve FV-103 stuck at {fault.onset:time}.** FC-103's OP wandered and then ran to its limit when the duty set point went up, but the duty reading did not follow. The duty meter was honest: normal noise, and the energy balance C3b green. Only C4 for FV-103 failed."},
    {"id": "ft102_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-102"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.7], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-102"},
     "protect": [{"tag": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102 read {fault.magnitude} wrong from {fault.onset:time}.** The valve was fine and moved as told, but FC-102 controlled a lie, so the real reflux was off by that amount. Two checks failed together: C4 for FV-102 (OP vs flow) *and* C3/C3a (reflux + distillate vs condenser duty). A sticking valve fails only the first."},
    {"id": "ft102_plugged", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "FT-102"}, "params": {"kind": "plugged"}, "severityRange": [1.0, 1.0], "ramp": 300},
     "answer": {"category": "instrument", "location": "instrument:FT-102"},
     "protect": [{"tag": "FC-102", "modes": ["man"]}],
     "debrief": "**FT-102's impulse line plugged at {fault.onset:time}.** On the OP trend this looks exactly like a stuck valve: OP moving, reading flat. The difference was the *noise*: the reading became far too smooth (σ under a tenth of typical) and the balances disagreed. With a stuck valve the meter keeps its normal noise and the balances agree."},
    {"id": "ft103_drift", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-103"}, "params": {"kind": "drift", "sign": "random"}, "severityRange": [0.6, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-103"},
     "protect": [{"tag": "FC-103", "modes": ["man"]}],
     "debrief": "**FT-103 (duty) drifted by {fault.magnitude} per hour from {fault.onset:time}.** FC-103 held the reading, so the real duty crept away. The energy balance C3b and FV-103's valve curve (C4) both diverged steadily — a meter fault, not a valve fault."},
    {"id": "ft103_plugged", "weight": 1,
     "fault": {"type": "transmitter", "location": {"tag": "FT-103"}, "params": {"kind": "plugged"}, "severityRange": [0.9, 1.0], "ramp": 300},
     "answer": {"category": "instrument", "location": "instrument:FT-103"},
     "protect": [{"tag": "FC-103", "modes": ["man"]}],
     "debrief": "**FT-103's impulse line plugged at {fault.onset:time}.** As with FT-102, the OP moved while the reading stayed flat, but the reading was too smooth, and C3b failed as the real duty wandered."},
    {"id": "feed_real", "weight": 2,
     "fault": {"type": "feedComposition", "params": {"dz": {"benzene": 0.10}, "sign": "random"}, "severityRange": [1.0, 1.0], "ramp": 600},
     "answer": {"category": "feedUpset", "location": "feed"},
     "debrief": "**Valves and meters were fine — the feed changed** by {fault.sign}0.10 benzene from {fault.onset:time}. All the C4 valve curves stayed on their lines, the balances closed, and AT-100 showed the new feed about 7–10 minutes later. The products moved because the column was separating a different feed."}
  ],
  "events": [
    {"id": "planning", "at": 2700, "action": "setSp", "tag": "FC-102", "delta": 1.38889,
     "text": "Planning: reflux +5 kmol/h and duty +65 kW to firm up the distillate."},
    {"at": 2700, "action": "setSp", "tag": "FC-103", "delta": 65000}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1200, "cost": 0.03, "text": "For FC-102 and FC-103, open the faceplate's **valve curve** (C4). Is the operating point on the line?"},
    {"after": 2400, "cost": 0.03, "text": "A point off the valve line means the valve *or* the meter. Now look at the balances (C3a, C3b): an honest meter keeps them green."},
    {"after": 3600, "cost": 0.03, "text": "Compare the noise on the suspect flow with its typical value. Sticking valves leave the meter's noise alone; plugged meters go quiet."}
  ],
  "diagnosis": {
    "categories": ["valve", "instrument", "feedUpset", "steam", "fouling", "none"],
    "locations": ["valve:FV-102", "valve:FV-103", "instrument:FT-102", "instrument:FT-103", "instrument:FT-104",
                  "instrument:AT-100", "feed", "reboiler", "condenser"],
    "modes": [],
    "attempts": 2
  },
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0.1, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; product off-spec: {result.offSpecTime:time}; loop protected: {result.protectTime:time}; diagnosed: {result.diagnosisTime:time}."
}
''';

/// h1Json: ENGINE_API.md 11.9 (M6), copied verbatim.
const String h1Json = r'''
{
  "id": "H1_creeping_dp", "kind": "drill", "title": "Creeping ΔP", "milestone": 6, "topic": "hydraulics",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"}, "start": "steady", "noise": true,
  "view": "plantCalc", "badPvShed": true,
  "levers": {"lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable", "reboilerType"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 10800,
  "briefing": "The column's temperatures and pressure drop have been drifting all week. Rates are steady. Find out whether something inside the column is changing, or something coming into it.",
  "onsetWindow": [600, 2400],
  "candidates": [
    {"id": "foul_strip", "weight": 2,
     "fault": {"type": "trayFouling", "location": {"from": 12, "to": 18}, "params": {"mode": "holes"}, "severityRange": [0.4, 0.8], "ramp": 7200},
     "answer": {"category": "fouling", "location": "stripping"},
     "debrief": "**Trays 12–18 were fouling** (holes plugging) from {fault.onset:time}. Their pressure drop rose at constant flows while trays 1–11 did not change; the separation changed little at first."},
    {"id": "foul_rect", "weight": 1,
     "fault": {"type": "trayFouling", "location": {"from": 2, "to": 8}, "params": {"mode": "holes"}, "severityRange": [0.4, 0.8], "ramp": 7200},
     "answer": {"category": "fouling", "location": "rectifying"},
     "debrief": "**Trays 2–8 were fouling** from {fault.onset:time}. The ΔP rise was in the rectifying section only, at constant flows."},
    {"id": "feed_light", "weight": 2,
     "fault": {"type": "feedComposition", "params": {"dz": {"benzene": 0.10}, "sign": 1}, "severityRange": [1.0, 1.0], "ramp": 1800},
     "answer": {"category": "feedUpset", "location": "feed"},
     "debrief": "**The feed got lighter** (+0.10 benzene) from {fault.onset:time}. Every temperature moved down together (a coherent wave on C6), AT-100 showed it, and no section's ΔP changed. More moles boiled at the same duty, so LC-101 raised the distillate."}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1500, "cost": 0.03, "text": "Look at the pressure drop tray by tray (Profiles → ΔP, a calculated value). A section whose ΔP rises while the flows stay put is changing inside."},
    {"after": 3000, "cost": 0.03, "text": "A feed change moves all the temperatures together (C6 shows a coherent wave) and shows on the feed analyser AT-100, but it does not change any section's ΔP."},
    {"after": 4500, "cost": 0.03, "text": "Fouled holes raise the dry-tray ΔP first, and the flood % of those trays rises with it."}
  ],
  "diagnosis": {"categories": ["fouling", "feedUpset", "foaming", "trayDamage", "instrument", "none"],
                "locations": ["rectifying", "stripping", "column", "feed", "instrument:*"], "modes": [], "attempts": 2},
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; diagnosed: {result.diagnosisTime:time}."
}
''';

/// h2Json: ENGINE_API.md 11.9 (M6), copied verbatim.
const String h2Json = r'''
{
  "id": "H2_pressure", "kind": "drill", "title": "Pressure won't hold", "milestone": 6, "topic": "condenser",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"}, "start": "steady", "noise": true,
  "view": "model", "badPvShed": true,
  "levers": {"lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable", "reboilerType", "cwInletT", "cwMaxFlow"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 10800,
  "briefing": "PC-101 is struggling to hold the top pressure. Is the cooling water letting you down, is the condenser dirty, or is something in the overhead that will not condense?",
  "onsetWindow": [600, 2400],
  "candidates": [
    {"id": "cw_temp", "weight": 1,
     "fault": {"type": "coolingLoss", "params": {"mode": "temperature"}, "severityRange": [0.6, 1.0], "ramp": 1800},
     "answer": {"category": "cooling", "location": "condenser"},
     "debrief": "**The cooling water got warmer** by {fault.magnitude} K from {fault.onset:time} (TI-201). PC-101 opened the CW valve to 100 %, then the pressure rose; the reflux was *less* subcooled."},
    {"id": "cw_flow", "weight": 1,
     "fault": {"type": "coolingLoss", "params": {"mode": "flow"}, "severityRange": [0.6, 0.7], "ramp": 0},
     "answer": {"category": "cooling", "location": "condenser"},
     "debrief": "**A cooling-water pump tripped** at {fault.onset:time}: FT-201 fell at once and the CW valve went to 100 %; the pressure rose and the reflux was less subcooled."},
    {"id": "cond_foul", "weight": 1,
     "fault": {"type": "condenserFouling", "severityRange": [0.7, 1.0], "ramp": 7200},
     "answer": {"category": "fouling", "location": "condenser"},
     "debrief": "**The condenser was fouling** from {fault.onset:time}. CW temperature and flow were normal, the CW valve crept open over an hour, and the subcooling fell."},
    {"id": "inerts", "weight": 1,
     "fault": {"type": "nonCondensables", "severityRange": [0.7, 1.0], "ramp": 0},
     "answer": {"category": "inerts", "location": "condenser"},
     "debrief": "**Non-condensables were building up** from {fault.onset:time}. They blanket tubes, so the condensate came out *more* subcooled while the pressure rose — the classic tell. Opening the vent clears them."}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1500, "cost": 0.03, "text": "Check the cooling water first: inlet temperature TI-201 and flow FT-201. A supply problem shows there."},
    {"after": 3000, "cost": 0.03, "text": "Watch the reflux subcooling on the condenser panel. Blanketing by inerts *raises* it; a weaker condenser lowers it."},
    {"after": 4500, "cost": 0.03, "text": "Fouling is slow (an hour or more); a pump trip is a step; inerts accumulate steadily and a vent clears them."}
  ],
  "diagnosis": {"categories": ["cooling", "fouling", "inerts", "instrument", "valve", "none"],
                "locations": ["condenser", "instrument:*", "valve:*"], "modes": [], "attempts": 2},
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; diagnosed: {result.diagnosisTime:time}."
}
''';

/// h3Json: ENGINE_API.md 11.9 (M6), copied verbatim.
const String h3Json = r'''
{
  "id": "H3_lost_separation", "kind": "drill", "title": "Lost separation", "milestone": 6, "topic": "hydraulics",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"}, "start": "steady", "noise": true,
  "view": "plantCalc", "badPvShed": true,
  "levers": {"lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable", "reboilerType"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 7200,
  "briefing": "The distillate is going off-spec and nobody touched the set points. Something inside the column — or one of its meters — has changed. Find it.",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "broken_tray", "weight": 1,
     "fault": {"type": "trayDamage", "location": {"from": 5, "to": 5}, "severityRange": [0.8, 1.0], "ramp": 0},
     "answer": {"category": "trayDamage", "location": "rectifying"},
     "debrief": "**Tray 5 was broken** at {fault.onset:time}: its calculated ΔP dropped to a small fraction of its neighbours', the column ΔP fell, and the distillate purity fell at the same L/D."},
    {"id": "foam", "weight": 1,
     "fault": {"type": "foaming", "location": {"from": 1, "to": 20}, "severityRange": [0.8, 1.0], "ramp": 600},
     "answer": {"category": "foaming", "location": "column"},
     "debrief": "**The column was foaming** from {fault.onset:time}. Flood % went to 100 % at normal rates while the measured column ΔP hardly moved. Antifoam fixes it."},
    {"id": "ft102_bias", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "FT-102"}, "params": {"kind": "bias", "sign": "random"}, "severityRange": [0.4, 0.6], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:FT-102"},
     "debrief": "**FT-102 (reflux) read {fault.magnitude} wrong** from {fault.onset:time}. FC-102 held the reading, so the real reflux changed. C3a (vapour from the condenser duty vs reflux + distillate) and C4 for FV-102 went red."}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1200, "cost": 0.03, "text": "Look at the calculated ΔP of each tray. One tray with almost none is a hole in the column."},
    {"after": 2400, "cost": 0.03, "text": "Compare the flood % (calc) with the measured column ΔP (PDT-101). Foam floods the trays without raising the ΔP much."},
    {"after": 3300, "cost": 0.03, "text": "Open the Balance tab: if C3a and a valve check disagree, suspect a meter, not the column."}
  ],
  "diagnosis": {"categories": ["trayDamage", "foaming", "instrument", "valve", "fouling", "feedUpset", "none"],
                "locations": ["rectifying", "stripping", "column", "feed", "instrument:*", "valve:*"], "modes": [], "attempts": 2},
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; product off-spec: {result.offSpecTime:time}; diagnosed: {result.diagnosisTime:time}."
}
''';

/// h4Json: ENGINE_API.md 11.9 (M6), copied verbatim.
const String h4Json = r'''
{
  "id": "H4_reboiler", "kind": "drill", "title": "Reboiler can't keep up", "milestone": 6, "topic": "reboiler",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"}, "start": "steady", "noise": true,
  "view": "model", "badPvShed": true,
  "levers": {"lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable", "reboilerType", "steamHeaderP"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 10800,
  "briefing": "The reboiler is not delivering the duty FC-103 asks for. Is it the exchanger, its steam trap, or the steam supply?",
  "onsetWindow": [600, 2400],
  "candidates": [
    {"id": "reb_foul", "weight": 1,
     "fault": {"type": "reboilerFouling", "location": {"equipment": "reboiler"}, "severityRange": [0.7, 1.0], "ramp": 5400},
     "answer": {"category": "fouling", "location": "reboiler"},
     "debrief": "**The reboiler was fouling** from {fault.onset:time}. The steam valve crept open for about three quarters of an hour and then saturated, and only then did the duty fall short. The header pressure (PT-201) stayed normal."},
    {"id": "trap", "weight": 1,
     "fault": {"type": "condensateBackup", "location": {"equipment": "reboiler"}, "severityRange": [0.7, 1.0], "ramp": 60},
     "answer": {"category": "condensate", "location": "reboiler"},
     "debrief": "**The steam trap failed** at {fault.onset:time}, and condensate backed up over the tubes. The duty fell short within minutes with the valve at 100 % and a normal header pressure. The fix is to open the trap bypass."},
    {"id": "header", "weight": 1,
     "fault": {"type": "steamHeaderLoss", "location": {"equipment": "reboiler"}, "severityRange": [0.7, 1.0], "ramp": 120},
     "answer": {"category": "steam", "location": "steamSupply"},
     "debrief": "**The steam header pressure fell** at {fault.onset:time} (PT-201), so the steam was colder. FC-103 saturated at 100 % with the duty below its set point; the exchanger itself was fine."}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1500, "cost": 0.03, "text": "Check the steam supply first: the header pressure PT-201."},
    {"after": 3000, "cost": 0.03, "text": "How fast did it happen? Fouling takes most of an hour; a failed trap takes minutes."},
    {"after": 4500, "cost": 0.03, "text": "A degraded exchanger raises the duty-limited alarm; a header loss does not, because the valve's own capacity fell with it."}
  ],
  "diagnosis": {"categories": ["fouling", "condensate", "steam", "valve", "instrument", "none"],
                "locations": ["reboiler", "steamSupply", "instrument:*", "valve:*"], "modes": [], "attempts": 2},
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; product off-spec: {result.offSpecTime:time}; diagnosed: {result.diagnosisTime:time}."
}
''';

/// h5Json: ENGINE_API.md 11.9 (M6), copied verbatim.
const String h5Json = r'''
{
  "id": "H5_bottoms_swings", "kind": "drill", "title": "Bottoms level swings", "milestone": 6, "topic": "reboiler",
  "preset": "bt", "overrides": {"tier": "t2", "hydraulics": "full"}, "start": "steady", "noise": true,
  "view": "plantCalc", "badPvShed": true,
  "levers": {"set": {"reboilerType": 1, "tsInletValve": 100},
             "lock": ["nTrays", "feedStage", "murphree", "trayType.0", "hydraulics", "noise", "view", "badPvShed", "tc101Enable", "reboilerType"]},
  "loops": {"FC-101": {"mode": "auto"}, "FC-102": {"mode": "auto"}, "FC-103": {"mode": "auto"},
            "LC-101": {"mode": "auto"}, "LC-102": {"mode": "auto"}, "PC-101": {"mode": "auto"}},
  "timeLimit": 14400,
  "briefing": "This column has a thermosyphon reboiler. The night shift reported that the boilup and the bottoms were 'swinging' at times. Watch the loop on the Equipment tab and find the cause before it gets worse.",
  "onsetWindow": [600, 1800],
  "candidates": [
    {"id": "lt102_drift", "weight": 1,
     "fault": {"type": "instrument", "location": {"tag": "LT-102"}, "params": {"kind": "drift", "sign": 1}, "severityRange": [1.0, 1.0], "ramp": 0},
     "answer": {"category": "instrument", "location": "instrument:LT-102"},
     "debrief": "**LT-102 (sump level) drifted high** by 10 % per hour from {fault.onset:time}. LC-102 kept the *reading* at its set point, so the true level fell. Less head meant less circulation and a higher exit quality, and the loop began to surge once the true level was below about 30 %. The sight glass LG-102 and C5 (sump) gave it away."},
    {"id": "ts_inlet", "weight": 1,
     "fault": {"type": "tsInletRestriction", "location": {"equipment": "reboiler"}, "severityRange": [0.3, 0.8], "ramp": 1800},
     "answer": {"category": "restriction", "location": "tsInletLine"},
     "debrief": "**The reboiler inlet line was restricting** from {fault.onset:time}. The inlet-line ΔP rose, the circulation fell and the exit quality rose, but the loop did *not* surge: friction at the inlet stabilises a thermosyphon."},
    {"id": "ts_outlet", "weight": 1,
     "fault": {"type": "tsOutletRestriction", "location": {"equipment": "reboiler"}, "severityRange": [0.2, 0.6], "ramp": 1800},
     "answer": {"category": "restriction", "location": "tsOutletLine"},
     "debrief": "**The reboiler outlet line was restricting** from {fault.onset:time}. The outlet-line ΔP rose, I_s went above 1 and the boilup surged with a period of about 10–13 s. Throttling the inlet valve damps it until the line is cleared."}
  ],
  "offSpec": {"when": {"any": [{"metric": "kpi.xD", "from": "start", "op": "<", "value": -0.01},
                               {"metric": "kpi.xB", "from": "start", "op": ">", "value": 0.01}]}, "holdFor": 120},
  "hints": [
    {"after": 1500, "cost": 0.03, "text": "Open the Equipment tab: the circulation, the exit quality and I_s tell you how healthy the loop is, and the inlet- and outlet-line ΔPs tell you where it is being squeezed."},
    {"after": 3000, "cost": 0.03, "text": "Is the sump level real? Compare LT-102 with C5 (sump) on the Balance tab — try the 1-hour window — and do a field check of LG-102."},
    {"after": 4500, "cost": 0.03, "text": "Inlet restriction lowers circulation without surging; outlet restriction makes the loop surge."}
  ],
  "diagnosis": {"categories": ["restriction", "instrument", "fouling", "condensate", "steam", "valve", "none"],
                "locations": ["tsInletLine", "tsOutletLine", "reboiler", "steamSupply", "instrument:*", "valve:*"], "modes": [], "attempts": 2},
  "scoring": {"category": 0.5, "location": 0.2, "time": 0.2, "safety": 0.1, "timeFull": 600, "timeZero": 3600,
              "wrongPenalty": 0.1, "bonus": {"protectBeforeOffSpec": 0, "mode": 0}},
  "debrief": "Fault onset {fault.onset:time}; first cross-check to fail: {result.firstFlaggedCheck}; diagnosed: {result.diagnosisTime:time}."
}
''';
