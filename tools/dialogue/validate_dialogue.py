"""Validate dialogue lines files against the closed sets in docs/dialogue_spec.md."""
import json, re, sys

TAGS = {"EMPHASIS","CONFIDENT","REASSURING","TERRIFIED","NERVOUS","ANGRY","GRUFF","WARM","TIRED",
"EXHAUSTED","PANICKED","CALM","URGENT","SARCASTIC","DRY","GRIM","HOPEFUL","WHISPERS","SHOUTS",
"MUTTERS","LAUGHS","SIGHS","PAINED","FLIRTY","EMBARRASSED","SUSPICIOUS","CURIOUS","PROUD",
"DISMISSIVE","PLEADING","RESIGNED","DEADPAN"}
INTENTS = {"greeting","farewell","smalltalk","status_report","complaint","fear_vent","reassurance",
"banter","insult","apology","romance_hint","romance_advance","romance_accept","romance_reject",
"work_talk","acknowledgment","grief","gallows_humor","suspicion_ai","praise_ai","pain","warning",
"request_help","offer_help","boast","memory","doubt"}
EVENTS = {"disease_outbreak","crew_death","reactor_failure","power_low","life_support_failure",
"hull_breach","door_locked_on_crew","ai_damaged","repair_success","crisis_resolved","combat",
"injury","quiet_shift","meal_time","shift_start","shift_end"}
LOCATIONS = {"engine_room","bridge","medbay","mess","quarters","cargo","corridor","life_support",
"ai_core","airlock","any"}
TYPES = {"declaration","opener","reply","closer"}
TAG_RE = re.compile(r"\[([A-Z ]+)\]")

total_issues = 0
for path in sys.argv[1:]:
    issues = []
    try:
        lines = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        print(f"{path}: JSON PARSE FAIL: {e}")
        total_issues += 1
        continue
    seen_ids = set()
    for ln in lines:
        k = ln.get("key", f"id{ln.get('id')}")
        if ln.get("id") in seen_ids:
            issues.append(f"{k}: duplicate id")
        seen_ids.add(ln.get("id"))
        for t in TAG_RE.findall(ln.get("text", "")):
            if t.strip() not in TAGS:
                issues.append(f"{k}: bad tag [{t}]")
        if ln.get("type") not in TYPES:
            issues.append(f"{k}: bad type {ln.get('type')}")
        if ln.get("intent") not in INTENTS:
            issues.append(f"{k}: bad intent {ln.get('intent')}")
        c = ln.get("conditions", {})
        for ev in c.get("recent_events", []) or []:
            if ev not in EVENTS:
                issues.append(f"{k}: bad event {ev}")
        for loc in c.get("location", []) or []:
            if loc not in LOCATIONS:
                issues.append(f"{k}: bad location {loc}")
        for ri in ln.get("reply_to_intents", []) or []:
            if ri not in INTENTS:
                issues.append(f"{k}: bad reply_to_intent {ri}")
        if ln.get("type") == "reply" and not ln.get("reply_to_intents"):
            issues.append(f"{k}: reply with empty reply_to_intents")
    print(f"{path}: {len(lines)} lines, {len(issues)} issues")
    for i in issues[:25]:
        print(f"  {i}")
    total_issues += len(issues)
print(f"TOTAL ISSUES: {total_issues}")
