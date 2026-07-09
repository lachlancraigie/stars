#!/usr/bin/env python3
"""Bulk-generate crew voice lines through the ElevenLabs API.

Reads the per-archetype CSVs the dialogue pipeline emits
(resources/dialogue/elevenlabs/*.csv, header: id,text) and produces one MP3
per line in assets/audio/dialogue/, named exactly after the line id
(e.g. GR_ML_ENG_CM_00042.mp3) so the game can match audio to dialogue keys.

Resume-safe: already-generated files are skipped unless --force is passed,
so re-running after a quota/rate limit just picks up where it left off.

Setup:
  1. Design one voice per archetype in ElevenLabs (descriptions in
     resources/dialogue/voices.md), or pick library voices.
  2. Set the API key:   $env:ELEVENLABS_API_KEY = "sk_..."   (PowerShell)
  3. Run once with --init-voices to write/refresh voices.json, then paste
     each archetype's voice_id into it. --list-voices prints your account's
     voices to help.
  4. python elevenlabs_batch.py            # everything not yet generated
     python elevenlabs_batch.py --archetype GR_ML_ENG_CM --limit 5 --dry-run

Model note: eleven_v3 natively reads inline audio tags like [whispers] or
[terrified]; our corpus stores tags in UPPERCASE, so they are lowercased on
the way out. [EMPHASIS] has no v3 tag — it is dropped and the following word
is uppercased instead, which v3 reads as emphasis.
"""

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
DEFAULT_CSV_DIR = os.path.join(REPO_ROOT, "resources", "dialogue", "elevenlabs")
DEFAULT_OUT_DIR = os.path.join(REPO_ROOT, "assets", "audio", "dialogue")
VOICES_CONFIG = os.path.join(SCRIPT_DIR, "voices.json")

API_BASE = "https://api.elevenlabs.io/v1"
TAG_RE = re.compile(r"\[([A-Z ]+)\]\s?")

# Emotive-tag handling for eleven_v3. Default: lowercase the tag and keep it
# inline ([TERRIFIED] -> [terrified]) — v3 accepts freeform emotional tags.
# Entries mapping to None are dropped entirely; "EMPHASIS" is special-cased
# in convert_tags().
TAG_OVERRIDES = {
    "EMPHASIS": None,  # handled by uppercasing the next word
}


def convert_tags(text: str) -> str:
    """Corpus emotive tags -> eleven_v3 audio tags.

    [EMPHASIS] word  ->  WORD          (v3 reads caps as emphasis)
    [ANYTHING ELSE]  ->  [anything else], unless TAG_OVERRIDES drops/remaps it.
    """
    text = re.sub(r"\[EMPHASIS\]\s*(\S+)", lambda m: m.group(1).upper(), text)

    def repl(m):
        tag = m.group(1).strip()
        if tag in TAG_OVERRIDES:
            mapped = TAG_OVERRIDES[tag]
            return f"[{mapped}] " if mapped else ""
        return f"[{tag.lower()}] "

    return TAG_RE.sub(repl, text)


def load_voices() -> dict:
    if not os.path.exists(VOICES_CONFIG):
        return {}
    with open(VOICES_CONFIG, encoding="utf-8") as f:
        return json.load(f)


def init_voices_config(csv_dir: str) -> None:
    voices = load_voices()
    added = 0
    for name in sorted(os.listdir(csv_dir)):
        if name.lower().endswith(".csv"):
            tag = os.path.splitext(name)[0].upper()
            if tag not in voices:
                voices[tag] = ""
                added += 1
    with open(VOICES_CONFIG, "w", encoding="utf-8") as f:
        json.dump(voices, f, indent=2, sort_keys=True)
    print(f"voices.json updated ({added} new archetype slots, {len(voices)} total).")
    print("Paste an ElevenLabs voice_id into each empty slot (see --list-voices).")


def api_request(path: str, api_key: str, payload=None, timeout=120):
    url = f"{API_BASE}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        method="POST" if payload is not None else "GET",
    )
    return urllib.request.urlopen(req, timeout=timeout)


def list_voices(api_key: str) -> None:
    with api_request("/voices", api_key) as resp:
        data = json.load(resp)
    for v in data.get("voices", []):
        print(f"{v['voice_id']}  {v['name']}")


def tts(api_key: str, voice_id: str, text: str, model: str, out_path: str,
        output_format: str, retries: int = 4) -> bool:
    payload = {"text": text, "model_id": model}
    path = f"/text-to-speech/{voice_id}?output_format={output_format}"
    for attempt in range(retries):
        try:
            with api_request(path, api_key, payload) as resp:
                audio = resp.read()
            tmp = out_path + ".part"
            with open(tmp, "wb") as f:
                f.write(audio)
            os.replace(tmp, out_path)
            return True
        except urllib.error.HTTPError as e:
            body = e.read()[:300]
            if e.code in (429, 500, 502, 503) and attempt < retries - 1:
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
    ap.add_argument("--csv-dir", default=DEFAULT_CSV_DIR)
    ap.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    ap.add_argument("--archetype", action="append", default=[],
                    help="Only these archetype tags (repeatable), e.g. GR_ML_ENG_CM")
    ap.add_argument("--limit", type=int, default=0,
                    help="Stop after N lines generated (across all archetypes)")
    ap.add_argument("--model", default="eleven_v3")
    ap.add_argument("--output-format", default="mp3_44100_128")
    ap.add_argument("--delay", type=float, default=0.5,
                    help="Seconds to sleep between API calls")
    ap.add_argument("--force", action="store_true", help="Regenerate existing files")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would be generated (with converted text), no API calls")
    ap.add_argument("--init-voices", action="store_true",
                    help="Create/refresh voices.json slots from the CSV dir and exit")
    ap.add_argument("--list-voices", action="store_true",
                    help="List voices on the ElevenLabs account and exit")
    args = ap.parse_args()

    if args.init_voices:
        init_voices_config(args.csv_dir)
        return 0

    api_key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ELEVENLABS_API_KEY is not set.", file=sys.stderr)
        return 1

    if args.list_voices:
        list_voices(api_key)
        return 0

    voices = load_voices()
    if not voices and not args.dry_run:
        print("voices.json missing/empty — run with --init-voices first.", file=sys.stderr)
        return 1

    os.makedirs(args.out_dir, exist_ok=True)
    wanted = {a.upper() for a in args.archetype}

    generated = skipped = failed = no_voice = 0
    chars = 0

    for name in sorted(os.listdir(args.csv_dir)):
        if not name.lower().endswith(".csv"):
            continue
        tag = os.path.splitext(name)[0].upper()
        if wanted and tag not in wanted:
            continue
        voice_id = voices.get(tag, "")
        if not voice_id and not args.dry_run:
            print(f"[{tag}] no voice_id in voices.json — skipping archetype")
            no_voice += 1
            continue

        with open(os.path.join(args.csv_dir, name), encoding="utf-8", newline="") as f:
            rows = list(csv.DictReader(f))
        print(f"[{tag}] {len(rows)} lines (voice {voice_id or 'DRY'})")

        for row in rows:
            line_id, raw = row["id"].strip(), row["text"]
            out_path = os.path.join(args.out_dir, f"{line_id}.mp3")
            if os.path.exists(out_path) and not args.force:
                skipped += 1
                continue
            text = convert_tags(raw)
            chars += len(text)
            if args.dry_run:
                print(f"  {line_id}: {text}")
                generated += 1
            else:
                print(f"  {line_id} ({len(text)} chars)")
                if tts(api_key, voice_id, text, args.model, out_path, args.output_format):
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
    print(f"characters sent{' (would be)' if args.dry_run else ''}: {chars}"
          f"  (ElevenLabs bills per character)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
