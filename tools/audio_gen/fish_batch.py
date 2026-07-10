#!/usr/bin/env python3
"""Bulk-generate crew voice lines through the Fish Audio S2.1 Pro API.

Fish Audio v2 revoice (Phase A), replacing elevenlabs_batch.py / ElevenLabs.
Unlike the ElevenLabs script, this reads the canonical dialogue corpus directly
(resources/dialogue/lines/*.json, array of Line objects per docs/dialogue_spec.md)
instead of an intermediate CSV export -- there is no export step anymore, the
corpus text (with inline Fish [] delivery tags) is sent to the API as written.

Produces one MP3 per line in assets/audio/dialogue_v2/, named
{ARCHETYPE_TAG}_{id:05d}.mp3 (e.g. GR_ML_ENG_CM_00042.mp3) -- same naming
convention as the v1 (ElevenLabs) output in assets/audio/dialogue/, so the two
can sit side by side during the transition.

Resume-safe: already-generated files are skipped unless --force is passed, so
re-running after a rate limit / interrupted run just picks up where it left off.

Setup:
  1. Voice mapping lives in tools/audio_gen/fish_voices.json (one primary Fish
     reference_id + delivery_baseline per archetype). See skills/fishaudio.md
     for the full API reference.
  2. Set the API key. Either:
       $env:FISH_API_KEY = "..."          (PowerShell), or
     let this script load it itself from tools/audio_gen/.env (FISH_API_KEY=...)
     when the env var isn't already set -- it does this automatically, no flag
     needed. (The ElevenLabs script required the env var to be set by hand and
     that silent requirement burned a session; this one is self-sufficient.)
  3. python fish_batch.py --archetype GR_ML_ENG_CM --limit 3 --dry-run
     python fish_batch.py                      # everything not yet generated

Tag handling: the corpus stores delivery tags inline as `[...]` (old closed-vocab
UPPERCASE tags and/or new Fish free-form tags -- both are valid [] syntax, see
docs/dialogue_spec.md). Text is sent as-is. If a line has NO leading tag, this
script prepends the archetype's `delivery_baseline` tag from fish_voices.json so
every line gets at least a baseline delivery direction.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
DEFAULT_LINES_DIR = os.path.join(REPO_ROOT, "resources", "dialogue", "lines")
DEFAULT_OUT_DIR = os.path.join(REPO_ROOT, "assets", "audio", "dialogue_v2")
VOICES_CONFIG = os.path.join(SCRIPT_DIR, "fish_voices.json")
ENV_FILE = os.path.join(SCRIPT_DIR, ".env")

API_URL = "https://api.fish.audio/v1/tts"
DEFAULT_MODEL = "s2.1-pro-free"

# HTTP codes worth backing off and retrying on (Fair Use / rate limiting / 5xx).
RETRYABLE_CODES = {403, 429, 500, 502, 503}


def load_env_file(path: str) -> None:
    """Load KEY=VALUE pairs from a .env file into os.environ, without
    overwriting anything already set and without ever printing values."""
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def get_api_key() -> str:
    if not os.environ.get("FISH_API_KEY"):
        load_env_file(ENV_FILE)
    return os.environ.get("FISH_API_KEY", "")


def load_voices() -> dict:
    if not os.path.exists(VOICES_CONFIG):
        return {}
    with open(VOICES_CONFIG, encoding="utf-8") as f:
        data = json.load(f)
    return data.get("archetypes", {})


def has_leading_tag(text: str) -> bool:
    return text.lstrip().startswith("[")


def build_text(raw: str, delivery_baseline: str) -> str:
    """Prepend the archetype's delivery_baseline tag when the line has no
    leading [tag] of its own."""
    if has_leading_tag(raw) or not delivery_baseline:
        return raw
    return f"{delivery_baseline} {raw}"


def tts(api_key: str, voice_id: str, text: str, model: str, out_path: str,
        fmt: str, mp3_bitrate: int, temperature: float, repetition_penalty: float,
        retries: int = 5, timeout: int = 120) -> bool:
    payload = {
        "text": text,
        "reference_id": voice_id,
        "format": fmt,
        "mp3_bitrate": mp3_bitrate,
        "temperature": temperature,
        "repetition_penalty": repetition_penalty,
        "condition_on_previous_chunks": True,
    }
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "model": model,
    }

    for attempt in range(retries):
        req = urllib.request.Request(API_URL, data=data, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                audio = resp.read()
            if not audio:
                print("    FAILED: empty response body")
                return False
            tmp = out_path + ".part"
            with open(tmp, "wb") as f:
                f.write(audio)
            os.replace(tmp, out_path)
            return True
        except urllib.error.HTTPError as e:
            body = e.read()[:300]
            if e.code in RETRYABLE_CODES and attempt < retries - 1:
                wait = 2 ** (attempt + 1)
                print(f"    HTTP {e.code}, retrying in {wait}s... {body!r}")
                time.sleep(wait)
                continue
            print(f"    FAILED HTTP {e.code}: {body!r}")
            return False
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < retries - 1:
                wait = 2 ** (attempt + 1)
                print(f"    network error ({e}), retrying in {wait}s...")
                time.sleep(wait)
                continue
            print(f"    FAILED: {e}")
            return False
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lines-dir", default=DEFAULT_LINES_DIR,
                    help="Directory of resources/dialogue/lines/*.json (default: %(default)s)")
    ap.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    ap.add_argument("--archetype", action="append", default=[],
                    help="Only these archetype tags (repeatable), e.g. GR_ML_ENG_CM")
    ap.add_argument("--limit", type=int, default=0,
                    help="Stop after N lines generated (across all archetypes)")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--format", default="mp3", choices=["mp3", "wav", "pcm", "opus"])
    ap.add_argument("--mp3-bitrate", type=int, default=128, choices=[64, 128, 192])
    ap.add_argument("--temperature", type=float, default=0.45)
    ap.add_argument("--repetition-penalty", type=float, default=1.2)
    ap.add_argument("--delay", type=float, default=0.4,
                    help="Seconds to sleep between API calls")
    ap.add_argument("--force", action="store_true", help="Regenerate existing files")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would be generated (with final text), no API calls")
    args = ap.parse_args()

    api_key = get_api_key()
    if not api_key and not args.dry_run:
        print("FISH_API_KEY is not set (checked environment and tools/audio_gen/.env).",
              file=sys.stderr)
        return 1

    voices = load_voices()
    if not voices and not args.dry_run:
        print(f"{VOICES_CONFIG} missing/empty archetypes -- nothing to generate.",
              file=sys.stderr)
        return 1

    os.makedirs(args.out_dir, exist_ok=True)
    wanted = {a.upper() for a in args.archetype}

    generated = skipped = failed = no_voice = 0
    chars = 0

    for name in sorted(os.listdir(args.lines_dir)):
        if not name.lower().endswith(".json"):
            continue
        tag = os.path.splitext(name)[0].upper()
        if wanted and tag not in wanted:
            continue

        info = voices.get(tag, {})
        voice_id = info.get("primary", {}).get("voice_id", "")
        delivery_baseline = info.get("delivery_baseline", "")
        if not voice_id and not args.dry_run:
            print(f"[{tag}] no primary voice_id in fish_voices.json -- skipping archetype")
            no_voice += 1
            continue

        with open(os.path.join(args.lines_dir, name), encoding="utf-8") as f:
            rows = json.load(f)
        print(f"[{tag}] {len(rows)} lines (voice {voice_id or 'DRY'})")

        for row in rows:
            line_id = row["id"]
            out_path = os.path.join(args.out_dir, f"{tag}_{line_id:05d}.mp3")
            if os.path.exists(out_path) and not args.force:
                skipped += 1
                continue
            text = build_text(row.get("text", ""), delivery_baseline)
            chars += len(text)
            if args.dry_run:
                print(f"  {tag}_{line_id:05d}: {text}")
                generated += 1
            else:
                print(f"  {tag}_{line_id:05d} ({len(text)} chars)")
                if tts(api_key, voice_id, text, args.model, out_path, args.format,
                       args.mp3_bitrate, args.temperature, args.repetition_penalty):
                    generated += 1
                else:
                    failed += 1
                time.sleep(args.delay)
            if args.limit and generated >= args.limit:
                print(f"--limit {args.limit} reached")
                break
        if args.limit and generated >= args.limit:
            break

    print(f"\ndone: {generated} generated, {skipped} already existed, "
          f"{failed} failed, {no_voice} archetypes without voice_id")
    print(f"characters sent{' (would be)' if args.dry_run else ''}: {chars}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
