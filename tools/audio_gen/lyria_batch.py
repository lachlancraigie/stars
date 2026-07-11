#!/usr/bin/env python3
"""Bulk-generate the 'Cold Circuit' soundtrack via Lyria 3 Pro on OpenRouter.

Manifest-driven (tools/audio_gen/lyria_tracks.json, distilled from
docs/music-direction.md): 9 heat/tone-mapped moods x N tracks each
(~2.94 min/track measured) => ~3.8 h of score for roughly $6.

EMPIRICAL API FINDINGS (2026-07-11 probes, this repo's session):
  - model "google/lyria-3-pro-preview" via POST /api/v1/chat/completions.
  - "stream": true is REQUIRED (400 "Audio output requires stream" otherwise).
  - "modalities" MUST be ["audio"] alone. With ["text","audio"] the model
    returns only section markers ([[A0]]...) and NO audio data.
  - Audio arrives as choices[].delta.audio.data base64 chunks; the advertised
    format field says "wav" but the payload is an ID3-tagged MP3 (~176 s,
    measured by MPEG frame walk). We save .mp3 accordingly.
  - Cost: ~$0.08/track (usage.cost) despite catalogue pricing showing 0.
  - The clip sibling ("lyria-3-clip-preview") yields 30 s clips at $0.04 --
    4x worse $/minute; not used.

Resume-safe: existing output files are skipped, so an interrupted run
continues where it left off. A credits floor guard (default $2.00) stops the
run before draining the shared OpenRouter balance (sprite pipeline shares it).

Usage:
  python lyria_batch.py --dry-run          # plan + cost estimate, no calls
  python lyria_batch.py --mood calm_routine --limit 2   # targeted test
  python lyria_batch.py                    # full manifest (background-friendly)

Output: assets/music/<mood>/<mood>_<NN>.mp3  (docs/music-direction.md layout;
directory is expected to be gitignored -- ~340 MB when complete).
Reads OPENROUTER_API_KEY from tools/image_gen/.env (never printed).
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
MANIFEST = SCRIPT_DIR / "lyria_tracks.json"
OUT_ROOT = REPO_ROOT / "assets" / "music"

sys.path.insert(0, str(REPO_ROOT / "tools" / "image_gen"))
import generate as g  # noqa: E402  (load_api_key; key handling stays in one place)

API_URL = "https://openrouter.ai/api/v1/chat/completions"
CREDITS_URL = "https://openrouter.ai/api/v1/credits"
MODEL = "google/lyria-3-pro-preview"

CREDITS_FLOOR = 2.00        # stop when remaining balance dips below this
CREDITS_CHECK_EVERY = 4     # tracks between balance checks
MAX_RETRIES = 3
RETRY_BASE_SECONDS = 10
EST_COST_PER_TRACK = 0.08


def remaining_credits(key: str) -> float:
    req = urllib.request.Request(CREDITS_URL, headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        d = json.loads(r.read().decode())["data"]
    return float(d["total_credits"]) - float(d["total_usage"])


def generate_track(key: str, style: str, prompt: str, variation: int) -> tuple[bytes, float]:
    """One streaming Lyria call. Returns (mp3_bytes, reported_cost)."""
    full_prompt = (
        f"[Instrumental] {prompt} Style: {style}. "
        f"Variation {variation}: keep the same mood and instrumentation but a "
        f"distinct melodic/harmonic take from other variations."
    )
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": full_prompt}],
        "modalities": ["audio"],   # audio-only: text+audio yields markers, no audio
        "stream": True,
        "max_tokens": 65536,
        "temperature": 1.0,
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    chunks: list[str] = []
    cost = 0.0
    with urllib.request.urlopen(req, timeout=900) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                c = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if c.get("usage"):
                cost = float(c["usage"].get("cost", 0.0))
            for ch in c.get("choices", []):
                a = (ch.get("delta") or {}).get("audio") or {}
                if a.get("data"):
                    chunks.append(a["data"])
    if not chunks:
        raise RuntimeError("stream completed with no audio chunks")
    return base64.b64decode("".join(chunks)), cost


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mood", help="only this mood")
    ap.add_argument("--limit", type=int, default=0, help="max tracks this run (0 = no cap)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--floor", type=float, default=CREDITS_FLOOR)
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    anchor = manifest["style_anchor"]
    exclude = manifest["exclude_styles"]

    plan: list[tuple[str, int, dict]] = []
    for mood, spec in manifest["moods"].items():
        if args.mood and mood != args.mood:
            continue
        variants = spec["variants"]
        for i in range(spec["count"]):
            out = OUT_ROOT / mood / f"{mood}_{i:02d}.mp3"
            if out.exists():
                continue
            plan.append((mood, i, variants[i % len(variants)]))
    if args.limit:
        plan = plan[: args.limit]

    print(f"planned: {len(plan)} tracks (~{len(plan) * 2.94:.0f} min, "
          f"~${len(plan) * EST_COST_PER_TRACK:.2f})")
    if args.dry_run or not plan:
        return 0

    key = g.load_api_key()
    spent = 0.0
    done = 0
    for n, (mood, i, variant) in enumerate(plan):
        if n % CREDITS_CHECK_EVERY == 0:
            rem = remaining_credits(key)
            print(f"[credits] remaining ${rem:.2f}")
            if rem < args.floor:
                print(f"[credits] below floor ${args.floor:.2f} -- stopping gracefully "
                      f"({done} tracks this run)")
                break
        style = f"{anchor}, {variant['style']}. {exclude}"
        out = OUT_ROOT / mood / f"{mood}_{i:02d}.mp3"
        out.parent.mkdir(parents=True, exist_ok=True)
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                mp3, cost = generate_track(key, style, variant["prompt"], i)
                out.write_bytes(mp3)
                spent += cost
                done += 1
                print(f"[{done}/{len(plan)}] {out.relative_to(REPO_ROOT)} "
                      f"({len(mp3)//1024} KB, ${cost:.2f}, total ${spent:.2f})")
                break
            except Exception as e:  # noqa: BLE001 -- retry then surface
                if attempt == MAX_RETRIES:
                    print(f"FAILED {mood}_{i:02d} after {MAX_RETRIES} attempts: {e}")
                else:
                    wait = RETRY_BASE_SECONDS * attempt
                    print(f"retry {attempt} for {mood}_{i:02d} in {wait}s: {e}")
                    time.sleep(wait)
    print(f"done: {done} tracks, ${spent:.2f} reported cost")
    return 0


if __name__ == "__main__":
    sys.exit(main())
