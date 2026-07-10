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

All other checks (ids, type, intent, conditions, reply_to_intents) are unchanged.
"""
import json, re, sys

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
        for issue in check_tags(ln.get("text", "")):
            issues.append(f"{k}: {issue}")
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
sys.exit(1 if total_issues else 0)
