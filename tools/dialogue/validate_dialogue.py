"""Validate dialogue lines files against docs/dialogue_spec.md.

Fish Audio v2 revoice (Phase A): delivery tags are no longer a closed vocabulary
(docs/dialogue_spec.md, "Delivery tags (Fish Audio S2.1 syntax)"). Tag checking is
now syntax-based instead of a fixed whitelist, so this validator accepts BOTH the
old closed-vocab UPPERCASE tags (e.g. [NERVOUS]) and new free-form/well-tested Fish
tags (e.g. [nervous, speaking quickly]) without error -- both are well-formed
bracket tags. That keeps the corpus green during the Phase B tag-rewrite transition.

Tag rules enforced (structure only, not vocabulary):
  - well-formed, non-empty [..] tags (no [], no unbalanced/nested brackets)
  - no (parentheses) tags -- Fish S2.1 requires [] , not () (S1 syntax)
  - no dangling descriptive tag at the end of the text (a tag must be followed by
    spoken text, never sit alone at line end)
  - flag more than 3 tags in a single line's text

Mission-system expansion (2026-07-11, docs/dialogue_spec.md "Mission-system line
categories"): adds 24 new engine-triggered `intent` values (away ops, briefing
acks, docking, shuttle ops, scenario-axis ambient dread) plus a new `shuttlebay`
location. These categories are OPTIONAL per archetype -- a file with zero lines in
any of them is still valid -- but WHEN a line uses one of these intents, its format
is checked: it must be a bare `declaration` targeting `open_air` with no
`reply_to_intents` (they are barks, not conversation turns; see spec for why).

All other checks (ids, type, intent, conditions, reply_to_intents) are unchanged.
"""
import json, re, sys

INTENTS = {"greeting","farewell","smalltalk","status_report","complaint","fear_vent","reassurance",
"banter","insult","apology","romance_hint","romance_advance","romance_accept","romance_reject",
"work_talk","acknowledgment","grief","gallows_humor","suspicion_ai","praise_ai","pain","warning",
"request_help","offer_help","boast","memory","doubt"}

# Mission-system intents: category prefix -> allowed sub-keys. Additive, optional
# per archetype (see module docstring / dialogue_spec.md). Kept as a dict (rather
# than a flat set literal) so the per-file coverage report below can group by
# category without re-deriving the prefix from each string.
MISSION_INTENT_CATEGORIES = {
    "away_depart": ["surface", "derelict", "station", "other_ship"],
    "away_radio": ["calm", "tense", "bad"],
    "away_return": ["fine", "shaken", "injured"],
    "briefing_ack": ["routine", "risky", "grim"],
    "docking": ["approach", "clamped", "undock"],
    "shuttle_ops": ["prep", "launch", "land"],
    "scenario_axis": ["bio", "systems", "social", "combat", "mystery"],
}
MISSION_INTENTS = {
    f"{prefix}_{suffix}"
    for prefix, suffixes in MISSION_INTENT_CATEGORIES.items()
    for suffix in suffixes
}
INTENTS |= MISSION_INTENTS
_INTENT_TO_CATEGORY = {
    f"{prefix}_{suffix}": prefix
    for prefix, suffixes in MISSION_INTENT_CATEGORIES.items()
    for suffix in suffixes
}


def mission_category(intent: str) -> str:
    """Category prefix (e.g. 'away_depart') for a mission-system intent string."""
    return _INTENT_TO_CATEGORY[intent]

EVENTS = {"disease_outbreak","crew_death","reactor_failure","power_low","life_support_failure",
"hull_breach","door_locked_on_crew","ai_damaged","repair_success","crisis_resolved","combat",
"injury","quiet_shift","meal_time","shift_start","shift_end"}
LOCATIONS = {"engine_room","bridge","medbay","mess","quarters","cargo","corridor","life_support",
"ai_core","airlock","shuttlebay","any"}
TYPES = {"declaration","opener","reply","closer"}

# Matches a single well-formed, non-nested [tag]. Nested/unbalanced brackets are
# caught separately by comparing raw '[' / ']' counts against what this consumes.
TAG_RE = re.compile(r"\[([^\[\]]*)\]")
PAREN_TAG_RE = re.compile(r"\(([^()]*)\)")
MAX_TAGS_PER_LINE = 3


def check_tags(text: str) -> list:
    """Syntax-only tag validation. Returns a list of issue strings (may be empty)."""
    issues = []

    matches = list(TAG_RE.finditer(text))

    # Unbalanced/nested brackets: if stripping every well-formed [..] match still
    # leaves a stray '[' or ']' behind, something's malformed.
    stripped = TAG_RE.sub("", text)
    if "[" in stripped or "]" in stripped:
        issues.append("malformed/unbalanced [] tag")

    # Empty tags: [] or [   ]
    for m in matches:
        if not m.group(1).strip():
            issues.append("empty [] tag")

    # Parenthetical tags are not allowed under Fish S2.1 syntax (square brackets only).
    for m in PAREN_TAG_RE.finditer(text):
        issues.append(f"parenthetical tag not allowed, use [] instead: ({m.group(1)})")

    # Dangling descriptive tag: nothing but whitespace follows the last tag.
    if matches:
        last = matches[-1]
        if not text[last.end():].strip():
            issues.append(f"dangling tag at end of line: [{last.group(1)}]")

    # Cap on tags per line (typical is 0-2, >3 is flagged, not hard-blocked elsewhere).
    if len(matches) > MAX_TAGS_PER_LINE:
        issues.append(f"{len(matches)} tags in one line, exceeds max {MAX_TAGS_PER_LINE}")

    return issues


total_issues = 0
mission_coverage_totals = {cat: 0 for cat in MISSION_INTENT_CATEGORIES}
mission_lines_total = 0
for path in sys.argv[1:]:
    issues = []
    try:
        lines = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        print(f"{path}: JSON PARSE FAIL: {e}")
        total_issues += 1
        continue
    seen_ids = set()
    file_mission_intents = set()
    for ln in lines:
        k = ln.get("key", f"id{ln.get('id')}")
        if ln.get("id") in seen_ids:
            issues.append(f"{k}: duplicate id")
        seen_ids.add(ln.get("id"))
        for issue in check_tags(ln.get("text", "")):
            issues.append(f"{k}: {issue}")
        if ln.get("type") not in TYPES:
            issues.append(f"{k}: bad type {ln.get('type')}")
        intent = ln.get("intent")
        if intent not in INTENTS:
            issues.append(f"{k}: bad intent {intent}")
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
        # Mission-system format rule (docs/dialogue_spec.md "Mission-system line
        # categories"): these are engine-triggered barks, not conversation turns.
        if intent in MISSION_INTENTS:
            mission_lines_total += 1
            file_mission_intents.add(intent)
            mission_coverage_totals[mission_category(intent)] += 1
            if ln.get("type") != "declaration":
                issues.append(f"{k}: mission-system intent {intent} must be type declaration, got {ln.get('type')}")
            if "open_air" not in (c.get("target") or []):
                issues.append(f"{k}: mission-system intent {intent} must target open_air")
            if ln.get("reply_to_intents"):
                issues.append(f"{k}: mission-system intent {intent} must have empty reply_to_intents")
    print(f"{path}: {len(lines)} lines, {len(issues)} issues")
    for i in issues[:25]:
        print(f"  {i}")
    if file_mission_intents:
        covered_cats = sorted({
            p for p in MISSION_INTENT_CATEGORIES
            for s in MISSION_INTENT_CATEGORIES[p]
            if f"{p}_{s}" in file_mission_intents
        })
        print(f"  mission-system coverage: {len(file_mission_intents)}/{len(MISSION_INTENTS)} "
              f"intents used, categories touched: {', '.join(covered_cats)}")
    total_issues += len(issues)
print(f"TOTAL ISSUES: {total_issues}")
breakdown = ", ".join(f"{cat}={n}" for cat, n in mission_coverage_totals.items() if n)
print(f"TOTAL mission-system lines across corpus: {mission_lines_total}"
      + (f" ({breakdown})" if breakdown else ""))
sys.exit(1 if total_issues else 0)
