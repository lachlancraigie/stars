#!/usr/bin/env python3
"""Validator for mission/scenario content JSON (docs/mission-system-spec.md §12).

Usage:  python tools/missions/validate_content.py  [--root D:/code/stars]

Exit 0 = clean (warnings allowed), exit 1 = errors. Canonical skill names and
item ids/tags are parsed live out of crew_gen.gd / items.gd so this never drifts
from the game's own registries.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# --- Closed sets (docs/mission-system-spec.md §3/§4/§5) ---

MISSION_TYPES = {
    "rendezvous", "planet_survey", "delivery", "salvage", "repair_yard",
    "distress", "escort", "passenger", "mining", "patrol", "science",
    "evacuation", "quarantine_run", "crew_transfer", "homecoming",
}
OBJECTIVE_KINDS = {
    "reach_destination", "dock_with_ship", "away_team", "deliver_cargo",
    "survive_until", "return_home", "repair_to", "keep_alive", "scenario_flag",
}
PHASES = {"transit_out", "arrival", "on_station", "transit_back"}
# Hook keys = phases + the away-return pseudo-phase (fires on shuttle_returned).
HOOK_KEYS = PHASES | {"away_return"}
CONTEXTS = {
    "transit", "arrival", "planet_orbit", "away_return", "docked",
    "derelict", "station", "aftermath", "any",
}
AXES = {"bio", "systems", "social", "combat", "mystery"}
RISK_TIERS = {"low", "moderate", "high", "extreme"}
STATUS_FLAGS = {"infected", "changed", "shaken", "marked"}
INTRUDER_TYPES = {"stalker", "nest", "mimic"}
DEST_KINDS = {"planet", "ship", "station", "point", "home"}
STATS_AND_SAVES = {"strength", "speed", "intellect", "combat", "sanity", "fear", "body"}
CREW_SELECTOR = re.compile(r"^(random|all|away_team|contact|role:\w+|cast:\w+|status:\w+)$")

CONDITION_TYPES = {
    "resource_below", "resource_above", "flag_set", "flag_unset",
    "crew_state_count", "ai_trust_below", "ai_suspicion_above",
    "crew_has_skill", "item_aboard", "mission_phase", "away_team_out",
    "crew_status_any", "intruder_present", "docked", "leg_at_least",
    "crew_count_below", "hull_below",
}
OUTCOME_TYPES = {
    "resource_delta", "crew_fear_spike", "set_flag", "spawn_event",
    "ai_trust_delta", "scenario_end", "reactor_failure", "life_support_failure",
    "ai_core_damage", "ai_core_repair", "ship_destroyed",
    "crew_injury", "crew_stress", "crew_status_flag", "crew_join", "crew_leave",
    "crew_kill", "grant_item", "remove_item", "hull_damage", "hull_repair",
    "spawn_intruder", "intruder_remove", "radio_line", "objective_complete",
    "objective_fail", "mission_abort", "door_lock_room", "air_vent_room",
}
# Bespoke GDScript scenarios + known morph stubs allowed as morph targets.
BUILTIN_SCENARIO_IDS = {"the_quarantine", "the_narrow_passage"}

errors: list[str] = []
warnings: list[str] = []


def err(path: Path, msg: str) -> None:
    errors.append(f"{path.name}: {msg}")


def warn(path: Path, msg: str) -> None:
    warnings.append(f"{path.name}: {msg}")


def parse_gd_registries(root: Path) -> tuple[set[str], set[str], set[str]]:
    """Extract canonical skill names, item ids, and item tags from GDScript."""
    skills: set[str] = set()
    crew_gen = (root / "scripts/procedural/crew_gen.gd").read_text(encoding="utf-8")
    # Skill arrays + upgrade maps: harvest every quoted Title-Case-ish string in the
    # skill constant block (between CLASS_BASE_SKILLS and ROLE_SKILL_POOL's end).
    m = re.search(r"const CLASS_BASE_SKILLS.*?const AGE_RANGE", crew_gen, re.S)
    block = m.group(0) if m else crew_gen
    for s in re.findall(r'"([A-Z][A-Za-z0-9\- ]*)"', block):
        if s not in {"Trained", "Expert", "Master", "Marine", "Android", "Teamster", "Scientist"}:
            skills.add(s)

    items_gd = (root / "scripts/core/items.gd").read_text(encoding="utf-8")
    item_ids = set(re.findall(r'^\t"(\w+)": \{', items_gd, re.M))
    item_tags = set(re.findall(r'"(\w+(?:_bonus|_mult|_advantage|_disadvantage))":', items_gd))
    return skills, item_ids, item_tags


def load_catalog(folder: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not folder.is_dir():
        return out
    for f in sorted(folder.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            err(f, f"JSON parse error: {e}")
            continue
        fid = data.get("id", "")
        if fid != f.stem:
            err(f, f'id "{fid}" != filename stem "{f.stem}"')
        if fid in out:
            err(f, f'duplicate id "{fid}"')
        out[fid] = data
        data["__path"] = str(f)
    return out


def check_outcomes(path: Path, outcomes, skills, item_ids, where: str) -> None:
    if not isinstance(outcomes, list):
        err(path, f"{where}: outcomes must be a list")
        return
    for o in outcomes:
        t = o.get("type", "")
        if t not in OUTCOME_TYPES:
            err(path, f"{where}: unknown outcome type '{t}'")
            continue
        tgt = o.get("target", "")
        if tgt and not CREW_SELECTOR.match(str(tgt)):
            err(path, f"{where}: bad target selector '{tgt}'")
        if t in {"grant_item", "remove_item"} and o.get("item_id") not in item_ids:
            err(path, f"{where}: unknown item_id '{o.get('item_id')}'")
        if t == "spawn_intruder" and o.get("intruder_type") not in INTRUDER_TYPES:
            err(path, f"{where}: unknown intruder_type '{o.get('intruder_type')}'")
        if t == "crew_status_flag" and o.get("flag") not in STATUS_FLAGS:
            err(path, f"{where}: crew_status_flag '{o.get('flag')}' not in {sorted(STATUS_FLAGS)}")
        if t == "radio_line":
            txt = o.get("text", "")
            if not txt:
                err(path, f"{where}: radio_line with no text")
            elif len(txt) > 120:
                warn(path, f"{where}: radio_line >120 chars ('{txt[:40]}…')")


def check_conditions(path: Path, conditions, skills, item_ids, where: str) -> None:
    if not isinstance(conditions, list):
        err(path, f"{where}: conditions must be a list")
        return
    for c in conditions:
        t = c.get("type", "")
        if t not in CONDITION_TYPES:
            err(path, f"{where}: unknown condition type '{t}'")
        if t == "crew_has_skill" and c.get("skill") not in skills:
            err(path, f"{where}: unknown skill '{c.get('skill')}'")
        if t == "item_aboard" and c.get("item_id") not in item_ids:
            err(path, f"{where}: unknown item_id '{c.get('item_id')}'")
        if t == "mission_phase" and c.get("phase") not in PHASES:
            err(path, f"{where}: unknown phase '{c.get('phase')}'")


def validate_mission(path: Path, m: dict, all_ids: set[str], all_tags: set[str],
                     skills: set[str], item_ids: set[str]) -> None:
    for field in ("id", "title", "mission_type", "briefing", "destination",
                  "objectives", "weight", "tags", "scenario_hooks"):
        if field not in m:
            err(path, f"missing required field '{field}'")
    if m.get("mission_type") not in MISSION_TYPES:
        err(path, f"unknown mission_type '{m.get('mission_type')}'")
    dest = m.get("destination", {})
    if dest.get("kind") not in DEST_KINDS:
        err(path, f"unknown destination.kind '{dest.get('kind')}'")

    obj_ids = set()
    for o in m.get("objectives", []):
        oid = o.get("id", "")
        if oid in obj_ids:
            err(path, f"duplicate objective id '{oid}'")
        obj_ids.add(oid)
        if o.get("kind") not in OBJECTIVE_KINDS:
            err(path, f"objective '{oid}': unknown kind '{o.get('kind')}'")
        for sk in o.get("params", {}).get("suggested_skills", []):
            if sk not in skills:
                err(path, f"objective '{oid}': unknown skill '{sk}'")

    risk = m.get("away_risk")
    has_away = any(o.get("kind") == "away_team" for o in m.get("objectives", []))
    if has_away and not risk:
        err(path, "away_team objective but no away_risk block")
    if risk:
        if risk.get("tier") not in RISK_TIERS:
            err(path, f"unknown away_risk.tier '{risk.get('tier')}'")
        for sk in risk.get("skill_mitigators", []):
            if sk not in skills:
                err(path, f"away_risk: unknown skill '{sk}'")
        for it in risk.get("item_mitigators", []):
            if it not in item_ids:
                err(path, f"away_risk: unknown item '{it}'")

    for phase, hook in m.get("scenario_hooks", {}).items():
        if phase not in HOOK_KEYS:
            err(path, f"scenario_hooks: unknown phase '{phase}'")
        if hook.get("context") not in CONTEXTS:
            err(path, f"scenario_hooks[{phase}]: unknown context '{hook.get('context')}'")

    for it in m.get("rewards", {}).get("items", []):
        if it not in item_ids:
            err(path, f"rewards: unknown item '{it}'")

    for fo in m.get("follow_ons", []):
        for nxt in fo.get("next", []):
            if nxt.startswith("tag:"):
                if nxt[4:] not in all_tags:
                    err(path, f"follow_on tag '{nxt}' matches no mission's tags")
            elif nxt not in all_ids:
                err(path, f"follow_on id '{nxt}' is not a mission id")


def validate_scenario(path: Path, s: dict, all_ids: set[str],
                      skills: set[str], item_ids: set[str], item_tags: set[str]) -> None:
    for field in ("id", "title", "pressure_axis", "intensity", "contexts",
                  "expected_length", "weight", "win_flags", "events", "monitor", "solves"):
        if field not in s:
            err(path, f"missing required field '{field}'")
    if s.get("pressure_axis") not in AXES:
        err(path, f"unknown pressure_axis '{s.get('pressure_axis')}'")
    if s.get("intensity") not in (1, 2, 3):
        err(path, f"intensity must be 1|2|3, got {s.get('intensity')!r}")
    for c in s.get("contexts", []):
        if c not in CONTEXTS:
            err(path, f"unknown context '{c}'")
    ts = s.get("trigger_status", "")
    if ts and ts not in STATUS_FLAGS:
        err(path, f"trigger_status '{ts}' not in {sorted(STATUS_FLAGS)}")

    settable: set[str] = set()

    def harvest_flags(outcomes) -> None:
        for o in outcomes or []:
            if o.get("type") == "set_flag":
                settable.add(o.get("flag", ""))

    ev_ids = set()
    for e in s.get("events", []):
        eid = e.get("event_id", "")
        if eid in ev_ids:
            err(path, f"duplicate event_id '{eid}'")
        ev_ids.add(eid)
        check_conditions(path, e.get("conditions", []), skills, item_ids, f"event {eid}")
        check_outcomes(path, e.get("outcomes", []), skills, item_ids, f"event {eid}")
        harvest_flags(e.get("outcomes"))

    mon = s.get("monitor", {})
    for t in mon.get("timers", []):
        check_outcomes(path, t.get("outcomes", []), skills, item_ids, "monitor timer")
        harvest_flags(t.get("outcomes"))
    for w in mon.get("watches", []):
        check_conditions(path, w.get("conditions", []), skills, item_ids, "monitor watch")
        check_outcomes(path, w.get("outcomes", []), skills, item_ids, "monitor watch")
        harvest_flags(w.get("outcomes"))
    for c in mon.get("checks", []):
        cid = c.get("id", "?")
        sel = str(c.get("crew", ""))
        if not (CREW_SELECTOR.match(sel) or sel.startswith("best_skill:")):
            err(path, f"check '{cid}': bad crew selector '{sel}'")
        if sel.startswith("best_skill:") and sel[11:] not in skills:
            err(path, f"check '{cid}': unknown skill in selector '{sel}'")
        if c.get("stat") not in STATS_AND_SAVES:
            err(path, f"check '{cid}': unknown stat '{c.get('stat')}'")
        if c.get("skill") and c["skill"] not in skills:
            err(path, f"check '{cid}': unknown skill '{c.get('skill')}'")
        if c.get("item_tag") and c["item_tag"] not in item_tags:
            err(path, f"check '{cid}': unknown item_tag '{c.get('item_tag')}'")
        for key in ("on_success", "on_fail", "on_crit_success", "on_crit_fail", "on_solved"):
            check_outcomes(path, c.get(key, []), skills, item_ids, f"check '{cid}'.{key}")
            harvest_flags(c.get(key))

    for wf in s.get("win_flags", []):
        if wf not in settable:
            err(path, f"win_flag '{wf}' is never set by any event/monitor outcome")

    for edge in s.get("morph_edges", []):
        tgt = edge.get("to", "")
        if tgt not in all_ids and tgt not in BUILTIN_SCENARIO_IDS:
            err(path, f"morph_edges: target '{tgt}' does not exist")
        if not edge.get("condition_flags"):
            err(path, "morph_edges: edge with empty condition_flags never fires")

    for solve in s.get("solves", []):
        if solve.get("skill") and solve["skill"] not in skills:
            err(path, f"solves: unknown skill '{solve.get('skill')}'")
        for it in solve.get("items_help", []):
            if it not in item_ids:
                err(path, f"solves: unknown item '{it}'")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="repo root (contains resources/, scripts/)")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    if not (root / "scripts/core/items.gd").exists():
        # allow running from tools/missions/ or repo root
        for cand in (root.parent.parent, root.parent):
            if (cand / "scripts/core/items.gd").exists():
                root = cand
                break
    skills, item_ids, item_tags = parse_gd_registries(root)
    if len(skills) < 10:
        warnings.append(f"only {len(skills)} skills parsed from crew_gen.gd — extraction may be stale")

    missions = load_catalog(root / "resources/missions")
    scenarios = load_catalog(root / "resources/scenarios")
    mission_tags = {t for m in missions.values() for t in m.get("tags", [])}

    for m in missions.values():
        validate_mission(Path(m["__path"]), m, set(missions), mission_tags, skills, item_ids)
    for s in scenarios.values():
        validate_scenario(Path(s["__path"]), s, set(scenarios), skills, item_ids, item_tags)

    print(f"validated {len(missions)} missions, {len(scenarios)} scenarios "
          f"({len(skills)} skills, {len(item_ids)} items known)")
    for w in warnings:
        print(f"  WARN  {w}")
    for e in errors:
        print(f"  ERROR {e}")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
