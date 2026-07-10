#!/usr/bin/env python3
"""
tools/image_gen/generate.py
============================

Small reusable client for the Ship AI "gen2" sprite pipeline: prompt in,
PNG out, via OpenRouter's dedicated Images API. Built to feed
tools/image_gen/pilot_batch.py, which composes prompts from
docs/style-bible-v2.md and enforces the 512x512 canvas / 130x65 floor
diamond @ (256,311) grid contract from scripts/ship/iso_kit.gd.

RECON FINDINGS (2026-07-10, from the live OpenRouter catalogue + empirical
test calls against a real API key in tools/image_gen/.env)
--------------------------------------------------------------------------
OpenRouter has a *dedicated* Images API, separate from /chat/completions:

    GET  https://openrouter.ai/api/v1/images/models            (no auth needed)
    GET  https://openrouter.ai/api/v1/images/models/{id}/endpoints
    POST https://openrouter.ai/api/v1/images                   (Bearer auth)

Model catalogue as of recon date (`GET .../images/models`), filtered to the
gpt-image family the user pointed at:

    model                     background enum              $/output-img-token
    openai/gpt-image-2        ["auto","opaque"]             0.00003
    openai/gpt-image-1        ["auto","transparent","opaque"] 0.00004
    openai/gpt-image-1-mini   ["auto","transparent","opaque"] 0.000008

=> "openai/gpt-image-2" (the user's suggested model) EXISTS on OpenRouter and
   generates fine, but its schema does NOT offer "transparent" as a
   background value -- only "auto" or "opaque". This was confirmed two ways:
   (1) the model's supported_parameters.background enum simply omits it, and
   (2) empirically, via `python generate.py --selftest`: POSTing
   background="transparent" against gpt-image-2 gets a hard reject --
   HTTP 400, `{"error":{"message":"background: not supported. Accepted:
   auto, opaque","code":400}}`. Not a silent fallback; the request never
   produces an image. The identical prompt/params against
   "openai/gpt-image-1-mini" (background="transparent") succeeded and
   returned a real RGBA PNG with a transparent (alpha=0) surround, verified
   by sampling all four corners (see has_real_alpha()) AND by a full pixel
   dump (alpha=0 at all 4 corners, alpha=255 at the subject center, a clean
   bimodal 591/433 split sampling every 32px). "openai/gpt-image-1" (full,
   non-mini) shares the same background enum and is expected to behave
   identically -- not re-verified live to conserve the generation budget,
   since gpt-image-1-mini already proved the family's transparency path
   works and costs 5x less.

   QUIRK worth flagging: pixels with alpha=0 still carry non-zero "ghost"
   RGB data (e.g. corner (91,60,20,0) -- an olive-brown, not black or
   white). Some naive viewers (ones that show raw RGB without compositing
   alpha) will render a visible gradient in the "transparent" area instead
   of a checkerboard/void. This does NOT affect Godot -- Sprite2D/GPU
   compositing always respects the alpha channel and ignores RGB where
   alpha=0 -- but it means "eyeballing" a raw PNG in a plain image viewer
   can look wrong even when the alpha data is correct. The QA step in
   pilot_batch.py checks the actual alpha channel, not a visual proxy.

=> None of the gpt-image-* endpoints list `resolution` or `aspect_ratio` as a
   supported_parameter (unlike the Gemini/Recraft/Seedream/FLUX entries in
   the same catalogue) -- output comes back at a fixed 1024x1024 square
   (OpenAI's Images API default) regardless of what we ask for. We downscale
   and pad into the game's 512x512 canvas ourselves in pilot_batch.py; this
   script only ever hands back the raw model output.

=> Gemini image models (google/gemini-3-pro-image, gemini-2.5-flash-image,
   etc.) and the other catalogue entries (Recraft, FLUX.2, Seedream,
   Riverflow, MAI, Grok Imagine) do not expose a `background` parameter at
   all in their schema -- no native transparency control. They were not
   pursued further since gpt-image-1 already solved transparency natively
   and matches the user's requested model family.

DECISION: default model = "openai/gpt-image-1-mini". It supports native
background="transparent" (same as gpt-image-1) at 1/5th the per-token cost
of gpt-image-1 and 1/3.75th the cost of gpt-image-2 -- important for staying
well under the 40-generation pilot cap with retries. Measured real cost from
the selftest call: ~$0.033/image (4160 image tokens x $0.000008 + a small
prompt-token charge), so a 40-generation cap is ~$1.35 worst case. gpt-image-1
(full, non-mini) is available via --model for a quality upgrade pass later if
the pilot shows the mini tier isn't sharp enough at 512px.

Fallback path (--chroma-key / background=opaque + magenta prompt clause):
implemented and available (see chroma_key_to_alpha() below) for any model
that lacks native transparency (gemini, recraft, flux, or gpt-image-2 if a
future job specifically wants image-2's quality tier). Uses PIL color-
distance thresholding against pure magenta (#FF00FF), not rembg (rembg is
not installed in this environment and pulls in a heavy onnxruntime
dependency; PIL chroma-keying is sufficient for flat cel-shaded art with a
solid background prompt instruction and keeps the dependency footprint to
just Pillow + requests, both already available).

Usage
-----
    python generate.py "PROMPT TEXT" --out out.png
    python generate.py "PROMPT TEXT" --out out.png --model openai/gpt-image-1
    python generate.py "PROMPT TEXT" --out out.png --background opaque --chroma-key
    python generate.py --selftest        # tiny live smoke test, prints findings

Reads OPENROUTER_API_KEY from tools/image_gen/.env (gitignored, never
printed, never logged). Nothing in this file hardcodes or echoes the key.
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
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
ENV_PATH = SCRIPT_DIR / ".env"

IMAGES_ENDPOINT = "https://openrouter.ai/api/v1/images"

DEFAULT_MODEL = "openai/gpt-image-1-mini"
DEFAULT_BACKGROUND = "transparent"
DEFAULT_QUALITY = "high"

MAGENTA = (255, 0, 255)

MAX_RETRIES = 3
RETRY_BASE_SECONDS = 4


class GenerationError(RuntimeError):
    """Raised when the OpenRouter Images API returns an error we can't retry past."""


# ---------------------------------------------------------------------------
# .env loading -- never print the value, never log it, never put it in an
# exception message.
# ---------------------------------------------------------------------------


def load_api_key(env_path: Path = ENV_PATH) -> str:
    if not env_path.exists():
        raise SystemExit(
            f"{env_path} not found. Create it with a single line:\n"
            "OPENROUTER_API_KEY=sk-or-v1-..."
        )
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == "OPENROUTER_API_KEY":
            value = value.strip().strip('"').strip("'")
            if not value:
                raise SystemExit("OPENROUTER_API_KEY is present in .env but empty")
            return value
    raise SystemExit(f"OPENROUTER_API_KEY not found in {env_path}")


# ---------------------------------------------------------------------------
# Core API call
# ---------------------------------------------------------------------------


def generate_image(
    prompt: str,
    *,
    model: str = DEFAULT_MODEL,
    background: str = DEFAULT_BACKGROUND,
    quality: str = DEFAULT_QUALITY,
    output_compression: int | None = None,
    input_references: list[Path] | None = None,
    api_key: str | None = None,
    timeout: float = 180.0,
) -> dict[str, Any]:
    """Call POST /api/v1/images. Returns a dict with keys:
    png_bytes, model, background_requested, usage (raw usage block, if any),
    raw (full parsed JSON response, for debugging).

    Retries on 429/5xx with exponential backoff; raises GenerationError on a
    non-retryable failure (4xx other than 429) with the response body
    included (OpenRouter error bodies do not contain the API key).
    """
    key = api_key or load_api_key()

    body: dict[str, Any] = {
        "model": model,
        "prompt": prompt,
        "background": background,
        "quality": quality,
    }
    if output_compression is not None:
        body["output_compression"] = output_compression
    if input_references:
        # Reference images (style anchors / edit sources). Format per the
        # OpenRouter image-generation docs: array of {type: "image_url",
        # image_url: {url}} objects; base64 data URLs are accepted, which we
        # use so local staged sprites never need public hosting.
        body["input_references"] = [
            {
                "type": "image_url",
                "image_url": {
                    "url": "data:image/png;base64,"
                    + base64.b64encode(Path(p).read_bytes()).decode("ascii")
                },
            }
            for p in input_references
        ]

    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        IMAGES_ENDPOINT,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/ship-ai/gen2-pipeline",
            "X-Title": "Ship AI gen2 sprite pipeline",
        },
    )

    attempt = 0
    while True:
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            if exc.code in (429, 500, 502, 503, 504) and attempt < MAX_RETRIES:
                attempt += 1
                wait = RETRY_BASE_SECONDS * (2 ** (attempt - 1))
                print(f"  [http {exc.code}] retrying in {wait}s (attempt {attempt}/{MAX_RETRIES})")
                time.sleep(wait)
                continue
            raise GenerationError(f"HTTP {exc.code} from OpenRouter images API: {error_body}") from exc
        except urllib.error.URLError as exc:
            if attempt < MAX_RETRIES:
                attempt += 1
                wait = RETRY_BASE_SECONDS * (2 ** (attempt - 1))
                print(f"  [network error] retrying in {wait}s (attempt {attempt}/{MAX_RETRIES}): {exc}")
                time.sleep(wait)
                continue
            raise GenerationError(f"network error calling OpenRouter images API: {exc}") from exc

    images = payload.get("data") or []
    if not images:
        raise GenerationError(f"no images in response: {json.dumps(payload)[:500]}")

    b64 = images[0].get("b64_json")
    if not b64:
        raise GenerationError(f"response image has no b64_json field: {json.dumps(images[0])[:500]}")

    return {
        "png_bytes": base64.b64decode(b64),
        "model": model,
        "background_requested": background,
        "usage": payload.get("usage"),
        "raw": payload,
    }


def save_png(png_bytes: bytes, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(png_bytes)


# ---------------------------------------------------------------------------
# Transparency helpers
# ---------------------------------------------------------------------------


def has_real_alpha(png_bytes: bytes) -> bool:
    """True if the image already has a non-trivial alpha channel (i.e. the
    model's native background=transparent actually worked), checked by
    sampling the four corners."""
    from PIL import Image
    import io

    im = Image.open(io.BytesIO(png_bytes))
    if im.mode not in ("RGBA", "LA"):
        return False
    rgba = im.convert("RGBA")
    w, h = rgba.size
    corners = [rgba.getpixel((0, 0)), rgba.getpixel((w - 1, 0)), rgba.getpixel((0, h - 1)), rgba.getpixel((w - 1, h - 1))]
    transparent = sum(1 for px in corners if px[3] <= 25)
    return transparent >= 3


def chroma_key_to_alpha(
    png_bytes: bytes,
    key_color: tuple[int, int, int] = MAGENTA,
    tolerance: int = 60,
    edge_feather: int = 2,
) -> bytes:
    """Replace pixels near key_color with transparency, PIL-only (no rembg).

    Distance-based threshold in RGB space with a soft falloff band
    (tolerance .. tolerance+edge_feather*20) so the cutout edge isn't a hard
    aliased ring. Returns new PNG bytes (RGBA).
    """
    import io
    import math

    from PIL import Image

    im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    px = im.load()
    w, h = im.size
    kr, kg, kb = key_color
    soft_band = max(1, edge_feather * 20)

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dist = math.sqrt((r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2)
            if dist <= tolerance:
                px[x, y] = (r, g, b, 0)
            elif dist <= tolerance + soft_band:
                # linear falloff across the soft band for a cleaner edge
                frac = (dist - tolerance) / soft_band
                px[x, y] = (r, g, b, int(a * frac))

    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _selftest() -> int:
    """Tiny live smoke test: generate one image with gpt-image-2 and one with
    the default model, both requesting background=transparent, and report
    whether each actually came back with usable alpha. This is the empirical
    check referenced in the module docstring's recon findings.
    """
    prompt = (
        "a single small red cube icon, flat cel-shaded, thick black outline, "
        "isolated on a plain background, no shadow, no text"
    )
    key = load_api_key()
    for model in ("openai/gpt-image-2", DEFAULT_MODEL):
        print(f"--- selftest: {model} background=transparent ---")
        try:
            result = generate_image(prompt, model=model, background="transparent", api_key=key)
        except GenerationError as exc:
            print(f"  FAILED: {exc}")
            continue
        alpha_ok = has_real_alpha(result["png_bytes"])
        out = SCRIPT_DIR / f"selftest_{model.replace('/', '_')}.png"
        save_png(result["png_bytes"], out)
        print(f"  saved: {out}")
        print(f"  native transparency present: {alpha_ok}")
        print(f"  usage: {result['usage']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("prompt", nargs="?", help="prompt text")
    parser.add_argument("--out", type=Path, help="output PNG path")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--background", default=DEFAULT_BACKGROUND, choices=["auto", "transparent", "opaque"])
    parser.add_argument("--quality", default=DEFAULT_QUALITY, choices=["auto", "low", "medium", "high"])
    parser.add_argument("--chroma-key", action="store_true", help="post-process a magenta background to alpha")
    parser.add_argument("--selftest", action="store_true", help="run the live transparency smoke test")
    args = parser.parse_args(argv)

    if args.selftest:
        return _selftest()

    if not args.prompt or not args.out:
        parser.error("prompt and --out are required unless --selftest is given")

    result = generate_image(args.prompt, model=args.model, background=args.background)
    png_bytes = result["png_bytes"]

    if args.chroma_key:
        png_bytes = chroma_key_to_alpha(png_bytes)
    elif args.background == "transparent" and not has_real_alpha(png_bytes):
        print(
            f"  [warn] requested background=transparent from {args.model} but no alpha "
            "came back -- consider --chroma-key with a magenta background prompt clause"
        )

    save_png(png_bytes, args.out)
    print(f"saved {args.out}  usage={result['usage']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
