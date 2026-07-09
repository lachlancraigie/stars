#!/usr/bin/env python3
"""Provision one ElevenLabs voice per dialogue archetype into voices.json.

Tries the real thing first: ElevenLabs text-to-voice *design* (generate
previews from a text description) followed by *create* (save a preview as a
permanent custom voice), one per archetype in resources/dialogue/voices.md.

Custom voice slots are plan-limited. This script checks
GET /v1/user/subscription once up front; if the account is already at or
over its voice_limit, it skips the (quota-costing) design/create calls
entirely for every archetype and uses STOCK_FALLBACK instead — a hand-picked
mapping of each archetype to the closest-matching library ("premade") voice
already on the account, chosen from GET /v1/voices metadata (gender / age /
accent / descriptive labels) against the brief in voices.md. Every fallback
entry carries a one-line note on where it compromises.

Idempotent: any archetype already filled in voices.json is left alone unless
--force is passed. Safe to re-run after upgrading the plan — it will then
attempt real voice design for whatever is still empty (or still stock-mapped,
under --force).

Usage:
    $env:ELEVENLABS_API_KEY = "sk_..."   # or just have tools/audio_gen/.env
    python design_voices.py                    # fill every empty slot
    python design_voices.py --archetype GR_ML_ENG_CM
    python design_voices.py --dry-run           # print the plan, no API calls
    python design_voices.py --force              # overwrite filled slots too
    python design_voices.py --skip-design         # go straight to fallback
"""

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
CSV_DIR = os.path.join(REPO_ROOT, "resources", "dialogue", "elevenlabs")
VOICES_CONFIG = os.path.join(SCRIPT_DIR, "voices.json")
VOICE_DESIGNS = os.path.join(SCRIPT_DIR, "voice_designs.json")
ENV_FILE = os.path.join(SCRIPT_DIR, ".env")

API_BASE = "https://api.elevenlabs.io/v1"

# Voice-design briefs, verbatim (trimmed) from resources/dialogue/voices.md.
# Keep in sync if that file changes.
ARCHETYPE_DESCRIPTIONS = {
    "GR_ML_ENG_CM": "Male, late 60s. Low, gravelled baritone worn down by decades of engine noise and cheap cigarettes he quit twenty years ago but still sounds like he hasn't. American working-class accent, flat Rust Belt/dockworker vowels, no polish. Pacing is slow and deliberate, full of half-second pauses like he's checking a gauge before finishing the sentence; speeds up only when annoyed or when something on the ship is about to kill someone. Dry, slightly hoarse, low rasp on sibilants. Delivery is flat and unimpressed by default; sarcasm lands quiet, not sharp.",
    "GR_FE_ENG_OF": "Female, early 60s. Warm-worn alto with real gravel in it, decades of shouting over engine noise, not smoking, just volume. Rural/working-class accent, slightly Southern-inflected, unhurried but not soft. Pacing is conversational and quick mid-repair-monologue, slowing to a low mutter when coaxing a machine or comforting someone. Chesty resonance, audible breath, a chuckle that rattles rather than tinkles. Delivery leans affectionate-exasperated by default, sharpening into flat command when something is actually about to go wrong.",
    "GR_ML_ENG_CA": "Male, mid-50s. Grounded, weathered baritone, unhurried command voice built from decades of being the one people ask 'is it gonna hold.' Faint dockworker accent smoothed by years of giving orders. Pacing is measured, plain, no wasted words; picks up urgency only when the numbers actually demand it. Solid, a little gravel, breath steady. Delivery defaults to calm authority earned rather than performed; warmth surfaces as dry understatement, not softness.",
    "CH_FE_ENG_CM": "Female, mid-20s. Bright, energetic alto with a grin audible in it. Casual, slightly rural accent, rounded vowels. Pacing is quick and bouncy, sentences often ending upward like she's already excited about the next one. Light, a little husky when she laughs, easy breath. Delivery defaults to enthusiastic and can-do; under real pressure she gets focused and fast rather than scared, treating the crisis like the biggest puzzle yet.",
    "CH_ML_ENG_OF": "Male, mid-30s. Warm, resonant tenor-baritone, easy and encouraging. Light urban accent, clear and friendly diction. Pacing is brisk but generous, gives people room to respond; slows down deliberately when explaining something technical so it lands. Full, warm, laughs from the chest. Delivery defaults to upbeat mentor energy; under crisis he gets crisp and directive but keeps the encouragement running underneath it.",
    "EV_ML_ENG_CM": "Male, early 40s. Low, level baritone, unhurried and grounded. Neutral accent, minimal inflection. Pacing stays almost identical whether he's discussing lunch or a hull breach, steady, measured, no rush. Smooth, quiet resonance, breath even and controlled. Delivery is calm and procedural by default; the steadiness itself functions as reassurance for everyone around him.",
    "PA_FE_ENG_CM": "Female, early 20s. Light, quick soprano with a nervous edge, prone to pitch rising when startled. Faint urban accent, fast natural speech. Pacing is rapid and jittery under any stress, words tripping over each other; only slows when fully absorbed in a repair, hands busy and mind quiet. Thin, a little breathy, audible gasp before bad news. Delivery defaults to anxious-but-trying; genuine competence shows through the moment her hands are on the actual problem.",
    "PA_FE_MAR_CA": "Female, early-to-mid 30s. Bright, forward, slightly rasped alto with a lot of forward drive in the tone, sounds like she's always about two seconds from moving. American, urban, quick consonants, clipped military cadence under stress. Pacing is fast and punchy by default, with sudden hard stops for emphasis. A little rough at the edges (post-shouting huskiness), quick husky laugh. Delivery defaults to confident-and-amused, needling; under real danger it snaps into flat, clipped command tone.",
    "EV_FE_MAR_OF": "Female, mid-30s. Clear, controlled mezzo with real weight behind it despite the calm. Neutral, faintly military-crisp accent. Pacing is even and deliberate, commands landing without needing volume; only speeds up to match the tempo of an active threat, never to panic. Solid, low resonance, breath disciplined. Delivery defaults to composed authority; her rare warmth is quiet and directed at one person at a time.",
    "PA_ML_MAR_OF": "Male, mid-30s. Tight, forceful tenor with a wound-up edge even at rest. Clipped military-regional accent. Pacing is fast and urgent by default, gets faster and louder under real threat rather than sharper. Tense, a little strained in the throat, quick sharp breaths. Delivery defaults to keyed-up vigilance; the rare moment he actually relaxes is more startling to the crew than his usual intensity.",
    "CH_ML_MAR_CM": "Male, late 20s. Loud, easy baritone with a grin built into it. Broad, friendly regional accent. Pacing is fast and bouncy in calm moments, snapping into sharp military cadence the instant things go bad, then bouncing right back after. Robust, chest-forward, laughs loud and often. Delivery defaults to buddy-energy warmth; under fire it turns instantly professional and clipped, then relaxes just as fast once it's over.",
    "GR_FE_MAR_CM": "Female, mid-40s. Low, rough alto, real gravel from old smoke and old shouting both. Hard-edged working-military accent. Pacing is clipped and economical by default, no wasted breath; only slows down for the rare story she actually decides to tell. Rasped, low, a dry chuckle rather than a laugh. Delivery defaults to flat and unbothered; the only crack in it shows up talking about the dead.",
    "EV_ML_MAR_CM": "Male, early 30s. Quiet, even baritone, unshowy. Neutral accent, minimal inflection, economical phrasing. Pacing is steady and unhurried across every stress level, sentences short and complete. Smooth, low, breath controlled and quiet. Delivery is calm and matter-of-fact by default; his stillness under fire is the whole personality.",
    "EV_FE_SCI_CA": "Female, mid-40s. Low, controlled alto with crisp diction and almost no filler words. Neutral trans-Atlantic accent, unplaceable. Pacing is measured and even regardless of stress, the words come at the same rate whether discussing lunch or a hull breach. Smooth, low rasp only when exhausted, breath tightly controlled. Delivery defaults to calm clinical authority; the only tell of real fear is a half-second pause before she speaks.",
    "PA_ML_SCI_CA": "Male, late 30s. Reedy tenor with a nervy, quick-fire cadence, words tumble slightly ahead of the thought. Central-European-inflected English, precise consonants. Pacing speeds up further under stress rather than slowing, occasionally stumbling over syllables he catches and restarts. Thin, a little breathless, throat tightens audibly when reciting probabilities of death. Delivery defaults to anxious-analytical; brief moments of captain's-command flatness cut through when he's actually certain of something.",
    "CH_ML_SCI_OF": "Male, early 30s. Warm, bright tenor with an easy smile audible in the tone. Light, hard-to-place accent, well-travelled, rounded vowels. Pacing is brisk and upbeat, full of little verbal exclamation points; slows only to deliver bad news gently, still finding something hopeful to land on. Clean, resonant, laughs easily and often. Delivery defaults to reassuring-cheerful; under real crisis it stays warm but gets fast and focused, like he's coaching you through it.",
    "GR_ML_SCI_OF": "Male, late 50s. Deep, dry baritone, unhurried, faint rasp. Neutral working-doctor accent, clipped consonants. Pacing is slow and deliberate, each sentence landing like a verdict; speeds up only mid-procedure when hands matter more than words. Low, gravelled, breath audible between phrases. Delivery is flat and matter-of-fact by default; the only warmth comes out sideways, in what he doesn't say.",
    "EV_FE_SCI_OF": "Female, late 30s. Warm but level mezzo, unhurried in the way of someone who trusts her own competence. Soft mixed-region accent, rounded and clear. Pacing stays remarkably constant across stress levels, the calm is structural, not performed. Smooth, low resonance, breath controlled and quiet. Delivery is steady and grounding by default; the only shift under real danger is a very slight drop in pitch, more serious, never faster.",
    "PA_ML_SCI_CM": "Male, mid-20s. Light, slightly strained tenor, quick and clipped when nervous. Flat Midwestern-American accent. Pacing is uneven, bursts of fast, over-explained speech followed by sudden nervous pauses. Thin, occasional voice crack under stress, audible swallow before saying something he doesn't want to say. Delivery defaults to hedging and qualifying everything; genuine confidence only appears, briefly, when he's certain about the science.",
    "CH_FE_SCI_CM": "Female, mid-20s. Bright, quick soprano-alto with real buoyancy in it. Light West Coast-American accent. Pacing is fast and enthusiastic, rising inflection on observations; only flattens out when a case actually scares her, and even then recovers fast. Clear, a little breathy, laughs through her nose when amused. Delivery defaults to chipper and curious; under pressure she gets faster, not quieter, talking herself and the patient through it.",
    "EV_FE_AND_OF": "Female-coded synthetic voice, ageless. Clear, softly resonant alto with unnaturally even breath support, no filler words, no vocal fry. Neutral, faintly formal diction, slightly over-precise consonants. Pacing is metronomic-calm regardless of situation, with the occasional half-beat pause before an emotionally loaded word, as if selecting it. Smooth, almost too smooth, a faint synthetic sheen under scrutiny. Delivery defaults to composed and helpful; the uncanny edge shows only in how little the tone moves even during genuine danger.",
    "PA_FE_AND_OF": "Female-coded synthetic voice, sounds late 30s. Crisp, alert mezzo with a coiled-tight energy under the precision. Neutral accent, very exact diction. Pacing is fast and clipped, speeds up further when flagging danger, occasional rapid-fire delivery of contingencies. Clean, a slight metallic edge that sharpens under stress. Delivery defaults to vigilant and slightly too intense for the room; rarely relaxes.",
    "CH_ML_AND_CM": "Male-coded synthetic voice, sounds late 20s. Bright, light baritone with a slightly too-even smile in the tone. Neutral accent, crisp diction. Pacing is upbeat and quick, cheerful cadence that occasionally clips a syllable early, almost right, not quite human timing. Clean, faint digital smoothness on sustained vowels. Delivery defaults to eager-to-please warmth; under stress the cheerfulness doesn't break, it just gets a fraction faster and more clipped, which is somehow unsettling.",
    "GR_FE_AND_CM": "Female-coded synthetic voice, sounds 50s. Low, dry alto with a mechanical evenness under a learned gruffness. Faint working-class accent, picked up not native, occasionally slips into flatter synthetic cadence mid-sentence. Pacing is slow and grumbling by default, with tell-tale too-even stretches when processing rather than feeling. Dry, a little flat, no real rasp since there's no smoke behind it, but she performs one anyway. Delivery defaults to curmudgeonly-affectionate; under real danger the performance drops entirely into flat synthetic precision.",
}

# Fallback: archetype -> (voice_id, stock voice name, compromise note).
# Chosen from GET /v1/voices metadata (gender/age/accent/descriptive labels
# + the ElevenLabs description string) as the closest available match to the
# ARCHETYPE_DESCRIPTIONS brief above. Used only when custom voice-design/
# creation is unavailable (plan's voice_limit already met/exceeded).
STOCK_FALLBACK = {
    "GR_ML_ENG_CM": ("pqHfZKP75CvOlQylNhV4", "Bill - Wise, Mature, Balanced",
        "closest age match (old/american); library has no gravelled Rust-Belt baritone"),
    "GR_FE_ENG_OF": ("Sjgha5m2JTeglcx4H37T", "Mhysa",
        "only warm/maternal female voice available; accent and gravel texture don't match the brief"),
    "GR_ML_ENG_CA": ("ZthjuvLPty3kTMaNKVKb", "Jackson",
        "confident/reliable narrator reads as command authority; less dockworker grit than the brief"),
    "CH_FE_ENG_CM": ("cgSgspJ2msm6clMCkdW9", "Jessica - Playful, Bright, Warm",
        "good age/energy match; accent is American-neutral, not rural"),
    "CH_ML_ENG_OF": ("iP95p4xoKVk53GoZ742B", "Chris - Charming, Down-to-Earth",
        "warm/casual mentor tone fits; not specifically 'urban'-accented"),
    "EV_ML_ENG_CM": ("cjVigY5qzO86Huf0OWal", "Eric - Smooth, Trustworthy",
        "calm/level baritone match; skews slightly warmer than the brief's flat affect"),
    "PA_FE_ENG_CM": ("FGY2WhTYpPnrIDTdsKH5", "Laura - Enthusiast, Quirky Attitude",
        "closest young/quick-energy female voice; reads more sassy than anxious"),
    "PA_FE_MAR_CA": ("EXAVITQu4vr4xnSDxMaL", "Sarah - Mature, Reassuring, Confident",
        "confident forward energy matches; less rasp/edge than the brief"),
    "EV_FE_MAR_OF": ("Xb7hH8MSUJpSbSDYk0k2", "Alice - Clear, Engaging Educator",
        "controlled/professional match; British accent instead of neutral-military-crisp"),
    "PA_ML_MAR_OF": ("pNInz6obpgDQGcFmaJgB", "Adam - Dominant, Firm",
        "forceful/wound-up energy matches well"),
    "CH_ML_MAR_CM": ("TX3LPaxmHKxFdv7VOQHJ", "Liam - Energetic, Social Media Creator",
        "buddy-energy warmth matches; regional accent not specifically 'broad'"),
    "GR_FE_MAR_CM": ("XrExE9yKIg1WjnnlVkGX", "Matilda - Knowledgable, Professional",
        "closest available alto; lacks the rough/gravel texture of the brief"),
    "EV_ML_MAR_CM": ("jSuBIjxMKhqIfb0wCK1F", "Baxter - Dry Calm Aussie",
        "grounded/steady documentary tone matches stillness-under-fire well"),
    "EV_FE_SCI_CA": ("pFZP5JQG7iQjIQuC4Bku", "Lily - Velvety Actress",
        "controlled/articulate match for clinical authority; British rather than trans-Atlantic"),
    "PA_ML_SCI_CA": ("CGOMbDUL52Yuc7oiDIm8", "Gilbert - Nasal, Robotic Professor",
        "nasal/precise reads as reedy-academic; no Central-European accent available, and 'robotic' overtone is a stretch"),
    "CH_ML_SCI_OF": ("cfgXMWoeQsY6I5kM4gP3", "Rory - Bright and Cheerful",
        "warm/upbeat match; Irish accent instead of 'hard-to-place'"),
    "GR_ML_SCI_OF": ("nPczCjzI2devNBz1zQrb", "Brian - Deep, Resonant and Comforting",
        "deep dry baritone matches the verdict-like delivery well"),
    "EV_FE_SCI_OF": ("hpp4J3VqNfWAUOO0d1Us", "Bella - Professional, Bright, Warm",
        "warm/steady match for grounding delivery"),
    "PA_ML_SCI_CM": ("Nagtyt9MktF8AWSgjotJ", "Danny - Deep, Monotone and Robotic (Devry)",
        "explicitly Midwestern-accented, matching the brief; description skews older/monotone vs. the brief's mid-20s strained nervousness"),
    "CH_FE_SCI_CM": ("cgSgspJ2msm6clMCkdW9", "Jessica - Playful, Bright, Warm",
        "reused from CH_FE_ENG_CM (female voice pool is small); bright/chipper energy still fits"),
    "EV_FE_AND_OF": ("weA4Q36twV5kwSaTEL0Q", "Eva - Futuristic Robot Helper",
        "purpose-built robotic/AI-assistant voice; excellent thematic fit for an even-keeled android officer"),
    "PA_FE_AND_OF": ("Xb7hH8MSUJpSbSDYk0k2", "Alice - Clear, Engaging Educator",
        "reused from EV_FE_MAR_OF (female voice pool is small); precise diction fits the 'exact' brief, less 'coiled-tight'"),
    "CH_ML_AND_CM": ("nPijfmaNgvm5OSN4xM8H", "Elon - Robotic and Cold Android",
        "purpose-built sci-fi android voice; brief wants warmer/eager-to-please than 'cold', best available synthetic-male option"),
    "GR_FE_AND_CM": ("VukfMVtvHInVUWoMNPiQ", "Herbert - Monotone and Robotic",
        "labeled gender-neutral, not female, but the monotone/mechanical-evenness-under-gruffness texture is the best acoustic match in the library"),
}


def load_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if key:
        return key
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("ELEVENLABS_API_KEY="):
                    return line.split("=", 1)[1].strip()
    return ""


def api_call(method: str, path: str, api_key: str, payload=None, timeout=120):
    url = f"{API_BASE}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url, data=data,
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        method=method,
    )
    return urllib.request.urlopen(req, timeout=timeout)


def get_json(method: str, path: str, api_key: str, payload=None):
    with api_call(method, path, api_key, payload) as resp:
        return json.load(resp)


def load_voices() -> dict:
    if not os.path.exists(VOICES_CONFIG):
        return {}
    with open(VOICES_CONFIG, encoding="utf-8") as f:
        return json.load(f)


def save_voices(voices: dict) -> None:
    with open(VOICES_CONFIG, "w", encoding="utf-8") as f:
        json.dump(voices, f, indent=2, sort_keys=True)


def preview_text_for(tag: str, min_len=100, max_len=1000) -> str:
    """Concatenate a few of the archetype's own lines into design preview text."""
    path = os.path.join(CSV_DIR, tag.lower() + ".csv")
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    text = ""
    for row in rows:
        piece = row["text"].strip()
        candidate = (text + " " + piece).strip() if text else piece
        if len(candidate) > max_len:
            break
        text = candidate
        if len(text) >= min_len:
            break
    return text


def voice_slots_available(api_key: str) -> tuple:
    """Returns (used, limit) from GET /v1/user/subscription."""
    data = get_json("GET", "/user/subscription", api_key)
    return data.get("voice_slots_used", 0), data.get("voice_limit", 0)


class VoiceLimitReached(Exception):
    pass


def load_designs() -> dict:
    if not os.path.exists(VOICE_DESIGNS):
        return {}
    with open(VOICE_DESIGNS, encoding="utf-8") as f:
        return json.load(f)


def record_design(tag: str, recipe: dict) -> None:
    """Append/overwrite this archetype's design recipe in voice_designs.json.

    Once a custom voice is deleted its voice_id is gone forever — the recipe
    (description + preview text + model/params) is what lets us re-design a
    close match later, so every successful create is recorded here.
    """
    designs = load_designs()
    designs[tag] = recipe
    with open(VOICE_DESIGNS, "w", encoding="utf-8") as f:
        json.dump(designs, f, indent=2, sort_keys=True)


def design_and_create(api_key: str, tag: str, description: str) -> str:
    """Real path: design previews, then save the first one as a named voice.
    Raises VoiceLimitReached if the plan is out of custom voice slots."""
    import datetime

    text = preview_text_for(tag) or None
    payload = {
        "voice_description": description[:1000],
        "model_id": "eleven_multilingual_ttv_v2",
    }
    if text:
        payload["text"] = text
    else:
        payload["auto_generate_text"] = True

    try:
        design_resp = get_json("POST", "/text-to-voice/design", api_key, payload)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"design failed: HTTP {e.code} {e.read()[:300]!r}")

    previews = design_resp.get("previews", [])
    if not previews:
        raise RuntimeError("design returned no previews")
    generated_voice_id = previews[0]["generated_voice_id"]

    create_payload = {
        "voice_name": f"SHIPAI_{tag}",
        "voice_description": description[:1000],
        "generated_voice_id": generated_voice_id,
    }
    try:
        create_resp = get_json("POST", "/text-to-voice", api_key, create_payload)
    except urllib.error.HTTPError as e:
        body = e.read()[:500]
        if b"voice_limit_reached" in body:
            raise VoiceLimitReached(body.decode(errors="replace"))
        raise RuntimeError(f"create failed: HTTP {e.code} {body!r}")

    voice_id = create_resp["voice_id"]
    record_design(tag, {
        "voice_name": f"SHIPAI_{tag}",
        "voice_id": voice_id,
        "generated_voice_id": generated_voice_id,
        "model_id": payload["model_id"],
        "voice_description": payload["voice_description"],
        "preview_text": text or "(auto-generated)",
        "previews_returned": len(previews),
        "created_at": datetime.datetime.now(datetime.timezone.utc)
                      .strftime("%Y-%m-%dT%H:%M:%SZ"),
    })
    return voice_id


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--archetype", action="append", default=[],
                    help="Only these archetype tags (repeatable)")
    ap.add_argument("--force", action="store_true",
                    help="Overwrite slots that already have a voice_id")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print the plan (design-or-fallback per archetype), no API calls")
    ap.add_argument("--skip-design", action="store_true",
                    help="Skip the design/create attempt, go straight to STOCK_FALLBACK")
    ap.add_argument("--no-fallback", action="store_true",
                    help="Fail (exit 1) instead of falling back to a stock voice when "
                         "design/create is unavailable — use when a custom voice is required")
    args = ap.parse_args()

    api_key = load_api_key()
    if not api_key and not args.dry_run:
        print("ELEVENLABS_API_KEY is not set (env var or tools/audio_gen/.env).",
              file=sys.stderr)
        return 1

    voices = load_voices()
    wanted = {a.upper() for a in args.archetype} or set(ARCHETYPE_DESCRIPTIONS)

    can_design = not args.skip_design
    if can_design and not args.dry_run:
        try:
            used, limit = voice_slots_available(api_key)
            if used >= limit:
                print(f"Custom voice slots: {used}/{limit} (at/over plan limit) "
                      f"-> using STOCK_FALLBACK for every archetype, no design calls made.")
                can_design = False
            else:
                print(f"Custom voice slots: {used}/{limit} -> attempting real voice design.")
        except urllib.error.HTTPError as e:
            print(f"Could not check subscription ({e.code}); assuming no free slots, using fallback.")
            can_design = False

    results = {}
    for tag in sorted(wanted):
        if tag not in ARCHETYPE_DESCRIPTIONS:
            print(f"[{tag}] unknown archetype (not in ARCHETYPE_DESCRIPTIONS) — skipping")
            continue
        existing = voices.get(tag, "")
        if existing and not args.force:
            print(f"[{tag}] already has voice_id ({existing}) — skipping")
            continue

        if args.dry_run:
            mode = "design" if can_design else "fallback"
            if mode == "fallback":
                vid, name, note = STOCK_FALLBACK[tag]
                print(f"[{tag}] DRY-RUN fallback -> {name} ({vid}) — {note}")
            else:
                print(f"[{tag}] DRY-RUN would attempt design+create as SHIPAI_{tag}")
            continue

        voice_id = None
        source = None
        if can_design:
            try:
                voice_id = design_and_create(api_key, tag, ARCHETYPE_DESCRIPTIONS[tag])
                source = "designed"
                print(f"[{tag}] designed custom voice -> {voice_id}")
            except VoiceLimitReached:
                print(f"[{tag}] voice_limit_reached -> falling back to stock voice for this "
                      f"and all remaining archetypes")
                can_design = False
            except RuntimeError as e:
                print(f"[{tag}] design/create error ({e}) -> falling back to stock voice")

        if voice_id is None and args.no_fallback:
            print(f"[{tag}] custom voice required (--no-fallback) but design/create "
                  f"unavailable — aborting.", file=sys.stderr)
            return 1

        if voice_id is None:
            if tag not in STOCK_FALLBACK:
                print(f"[{tag}] no fallback mapping available — leaving slot empty")
                continue
            voice_id, name, note = STOCK_FALLBACK[tag]
            source = "stock"
            print(f"[{tag}] stock fallback -> {name} ({voice_id}) — {note}")

        voices[tag] = voice_id
        results[tag] = source
        save_voices(voices)  # persist after every archetype so a crash loses nothing

    if not args.dry_run and results:
        designed = sum(1 for s in results.values() if s == "designed")
        stock = sum(1 for s in results.values() if s == "stock")
        print(f"\ndone: {len(results)} archetype(s) filled ({designed} designed, {stock} stock fallback)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
