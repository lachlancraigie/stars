#!/usr/bin/env python3
"""
tools/image_gen/reskin_batch.py
================================
Bulk character-reskin pipeline for gen3_chars.

Paints a distinct character onto the 4 mannequin animation sheets (idle/walk/
run/punch) via OpenRouter's Gemini image-edit endpoint, palette-snaps each
character onto a palette EXTRACTED FROM ITS OWN idle sheet (not the fixed
gen2 steel palette in palette_snap.py -- that palette is one specific look;
reusing it verbatim here would flatten all 33 distinct characters onto the
same suit colors, defeating the point of a varied roster. We reuse
palette_snap's mechanics -- extract_bands()/snap_image() -- with a per-
character palette instead of its module-level CHARACTER_PALETTE constant),
QA-gates on silhouette IoU + post-snap color drift, slices into per-frame
128px master + 64px game PNGs (alpha via flood-fill of the white background,
preserving enclosed whites like eyes), and writes a preview GIF + a shared
manifest.json.

Pipeline per sheet: generate -> flood-fill white->alpha -> (idle sheet only)
extract a character palette -> snap all 4 sheets onto it -> QA -> slice.

Model notes (from this session's proven test calls, see assets/scratch/
_reskin_test/): gpt-image-family models redraw the whole layout when used as
an edit source and are NOT used here. Gemini image models on OpenRouter don't
expose background/quality params (confirmed empirically) -- this script POSTs
directly (model, prompt, aspect_ratio, input_references), no background/
quality fields, mirroring the proven call shape. generate.py's higher-level
generate_image() wrapper is NOT used for the paint calls for that reason; we
only reuse its load_api_key().

Usage:
    python reskin_batch.py --list                        # print roster table, no network calls
    python reskin_batch.py --credits                      # check OpenRouter balance (free)
    python reskin_batch.py --slice-test                    # offline: QA+slice existing _reskin_test sheets
    python reskin_batch.py --character CH_FE_ENG_CM        # run one character end to end
    python reskin_batch.py --run-all [--start N] [--limit N] [--kind crew|npc|robot]

Writable outputs: assets/sprites/gen3_chars/**. Never commits 4K intermediates
(those live under assets/scratch/, already gitignored). Never prints the API key.
"""
from __future__ import annotations

import argparse
import base64
import json
import math
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
sys.path.insert(0, str(SCRIPT_DIR))
import generate as g          # noqa: E402  (load_api_key only -- paint calls are raw POSTs, see module docstring)
import palette_snap as ps     # noqa: E402  (extract_bands / snap_image mechanics, custom per-character palette)

SCRATCH = REPO_ROOT / "assets" / "scratch"
TEST_DIR = SCRATCH / "_reskin_test"
# Per-sheet checkpoints (raw pre-snap RGBA + QA sidecar) live in scratch, NOT
# in gen3_chars: they are paid intermediates that must survive a crash or shell
# timeout mid-character, but must never be committed. assets/scratch/ stays
# untracked by design.
CKPT_ROOT = SCRATCH / "_reskin_checkpoints"
OUT_ROOT = REPO_ROOT / "assets" / "sprites" / "gen3_chars"
MANIFEST_PATH = OUT_ROOT / "manifest.json"
ARCHETYPES_DIR = REPO_ROOT / "resources" / "dialogue" / "archetypes"

IMAGES_ENDPOINT = "https://openrouter.ai/api/v1/images"
CREDITS_ENDPOINT = "https://openrouter.ai/api/v1/credits"

GRID = {"idle": (8, 8), "walk": (12, 8), "run": (6, 8), "punch": (4, 8)}   # (cols, rows)
# NOTE: "punch" is a 4x8 grid (width:height = 1:2), but OpenRouter's Gemini
# image-edit provider only accepts a fixed aspect_ratio enum (1:1, 2:3, 3:2,
# 3:4, 4:3, 4:5, 5:4, 9:16, 16:9, 21:9) -- discovered live (HTTP 400) during
# the first pilot run. idle (8x8=1:1), walk (12x8=3:2) and run (6x8=3:4) all
# have EXACT enum matches and QA fine; punch does not, and requesting 9:16
# against a 1:2 reference made the model re-compose the layout (punch IoU
# 0.33-0.67 across the first five characters, failing even on pro while the
# other three sheets passed). Fix: PAD the punch reference with a white right
# margin to exactly 9:16 before the call, then crop the output back to the
# original 1:2 region -- the canvas then matches the requested ratio and the
# edit-in-place behavior returns. See _padded_reference()/PAD_CROP.
ASPECT = {"idle": "1:1", "walk": "3:2", "run": "3:4", "punch": "9:16"}
# sheets needing reference padding: sheet -> (target_w/target_h as a fraction)
PAD_TO_RATIO = {"punch": 9 / 16}
SHEETS = ["idle", "walk", "run", "punch"]

MODEL_FLASH = "google/gemini-2.5-flash-image"
MODEL_PRO = "google/gemini-3-pro-image"
EST_COST = {MODEL_FLASH: 0.04, MODEL_PRO: 0.137}

STOP_THRESHOLD = 1.50
PRO_ESCALATION_THRESHOLD = 3.00

QA_MEAN_IOU_MIN = 0.65
QA_MIN_IOU_MIN = 0.40
QA_DRIFT_MAX = 35.0

WHITE_THRESHOLD = 240
GAME_CELL = 64
MASTER_CELL = 128

MAX_RETRIES = 3
RETRY_BASE_SECONDS = 4


# ---------------------------------------------------------------------------
# Roster construction -- derives the 24 crew from the dialogue archetypes,
# plus 6 fixed NPCs and 3 fixed robots, per the class/temperament/rank rules.
# ---------------------------------------------------------------------------

OUTFIT_BY_CLASS = {
    "teamster_engineer": "olive-drab and rust-orange coveralls with rolled sleeves, "
                          "a canvas tool rig/belt hung with visible tools, heavy grey work boots",
    "scientist_medic": "a pale off-white lab tunic over a dark fitted under-layer, "
                        "clipped instrument pouches on the chest, soft-soled shoes",
    "marine": "an armored tactical vest over combat fatigues, knee and elbow padding, "
              "load-bearing webbing gear, heavy combat boots",
    "android": "a graphite-grey synthetic bodysuit with visible seam-panel lines and "
               "smooth matte plating at the shoulders and forearms, pale synthetic skin "
               "with a faint grey undertone",
}
CLASS_ID = {"teamster_engineer": "eng", "scientist_medic": "sci", "marine": "mar", "android": "and"}

ACCENT_BY_TEMPERAMENT = {
    "cheerful": ["a warm marigold-yellow accent (piping, patches)", "a warm coral-orange accent (piping, patches)"],
    "even": ["a muted slate-blue accent (piping, patches)", "a muted grey-blue accent (piping, patches)"],
    "gruff": ["a heavy desaturated ochre accent, faded and worn", "a heavy desaturated moss-green accent, faded and worn"],
    "paranoid": ["a cold teal-violet accent, asymmetric patch placement", "a cold violet-teal accent, nervously mismatched patches"],
}
TEMPERAMENT_ID = {"cheerful": "ch", "even": "ev", "gruff": "gr", "paranoid": "pa"}

RANK_TRIM = {
    "captain": "gold shoulder trim / epaulettes marking command rank",
    "officer": "silver shoulder trim / rank bars",
    "crew_mate": "no rank trim or insignia",
}
RANK_ID = {"captain": "ca", "officer": "of", "crew_mate": "cm"}

HAIR_COLORS = ["jet-black", "dark brown", "chestnut brown", "auburn red", "sandy blonde",
               "platinum blonde", "salt-and-pepper grey", "silver-white", "deep burgundy red",
               "ash brown", "warm copper", "charcoal black"]
HAIR_CUTS = ["a close buzzcut", "a short practical crop", "shoulder-length hair tied back",
             "a tight undercut", "shaved sides with a top knot", "a messy short crop",
             "a long single braid", "short hair slicked back", "a cropped pixie cut",
             "regulation short back-and-sides", "loose shoulder-length waves", "a high tight bun"]
SKIN_TONES = ["deep brown skin", "medium brown skin", "olive-tan skin", "warm tan skin",
              "light tan skin", "pale freckled skin", "pale skin", "rich dark skin",
              "golden-tan skin", "sun-weathered tan skin"]


def _crew_roster() -> list[dict]:
    roster = []
    for path in sorted(ARCHETYPES_DIR.glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        dim = d["dimensions"]
        personality, gender, career, rank = dim["personality"], dim["gender"], dim["career"], dim["rank"]
        model_id = f"{TEMPERAMENT_ID[personality]}_{'fe' if gender == 'female' else 'ml'}_{CLASS_ID[career]}_{RANK_ID[rank]}"
        i = len(roster)
        hair_color = HAIR_COLORS[i % len(HAIR_COLORS)]
        hair_cut = HAIR_CUTS[(i * 5) % len(HAIR_CUTS)]
        skin = "pale synthetic skin with a faint grey undertone" if career == "android" else SKIN_TONES[(i * 7) % len(SKIN_TONES)]
        accent = ACCENT_BY_TEMPERAMENT[personality][i % 2]
        gender_word = "a woman" if gender == "female" else "a man"
        desc = (
            f"{gender_word}, {hair_cut} in {hair_color} hair, {skin}, wearing "
            f"{OUTFIT_BY_CLASS[career]}, {accent}, {RANK_TRIM[rank]}"
        )
        roster.append({
            "id": model_id,
            "kind": "crew",
            "tag": d["tag"],
            "name": d["names"][0],
            "description": desc,
        })
    return roster


NPC_ROSTER = [
    {"id": "dockhand", "kind": "npc", "name": "Dockhand",
     "description": "a man, short practical brown hair, sun-weathered tan skin, wearing a "
                     "hi-vis orange/yellow vest over dark coveralls with faint mechanical "
                     "exo-frame struts visible along the arms and legs, scuffed heavy boots"},
    {"id": "corporate_rep", "kind": "npc", "name": "Corporate Representative",
     "description": "a woman, neat short black hair, light tan skin, wearing a sharp dark "
                     "charcoal business suit, crisp white shirt, polished black shoes, no "
                     "visible weapon or equipment"},
    {"id": "salvager", "kind": "npc", "name": "Salvager",
     "description": "a man, shaggy grey-brown hair, olive-tan weathered skin, wearing a "
                     "bulky patched vacuum suit with mismatched repair patches in different "
                     "faded colors, scavenged parts and pouches strapped on, a worn dark "
                     "visor pushed up off the face"},
    {"id": "pirate_raider", "kind": "npc", "name": "Pirate Raider (Sixfold Line)",
     "description": "a woman, shaved-sides undercut in dark red hair, pale scarred skin, "
                     "wearing dark matte armor plating with aggressive red accent stripes "
                     "and a stenciled Sixfold Line insignia, tactical rig, menacing bearing"},
    {"id": "cult_prophet", "kind": "npc", "name": "Cult Prophet",
     "description": "a man, long unkempt silver-white hair, gaunt pale skin, wearing heavy "
                     "hooded dark robes over a flightsuit, strange pale symbols stitched into "
                     "the fabric, an unsettling gaunt presence"},
    {"id": "colonist_survivor", "kind": "npc", "name": "Colonist Survivor",
     "description": "a woman, messy dirty-blonde hair, pale exhausted skin, wearing worn "
                     "dirty plain civilian clothes layered for warmth, a haggard exhausted look"},
]

ROBOT_ROSTER = [
    {"id": "robot_maintenance", "kind": "robot", "name": "Maintenance Automaton",
     "description": "a maintenance robot: matte chassis painted safety yellow with black "
                     "hazard stripes, visible panel seams, a single small round utility optic, "
                     "industrial joint plating, a blank smooth head unit with no human face"},
    {"id": "robot_security", "kind": "robot", "name": "Security Unit",
     "description": "a security robot: dark gunmetal-grey armored chassis, a single glowing "
                     "red optic lens as the head, angular military-style plating, no human face"},
    {"id": "robot_cargo_loader", "kind": "robot", "name": "Cargo Loader Frame",
     "description": "a cargo loader robot: bulky industrial safety-orange plating, thick "
                     "reinforced limb joints, a wide-stance heavy chassis, a blank utility "
                     "head unit, black hazard markings"},
]


def build_roster() -> list[dict]:
    return _crew_roster() + NPC_ROSTER + ROBOT_ROSTER


# ---------------------------------------------------------------------------
# Credits
# ---------------------------------------------------------------------------

def get_remaining_credits(key: str) -> float:
    req = urllib.request.Request(CREDITS_ENDPOINT, headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    d = data.get("data", data)
    return float(d["total_credits"]) - float(d["total_usage"])


# ---------------------------------------------------------------------------
# Generation (raw POST -- proven call shape for Gemini image-edit models;
# see module docstring for why generate.generate_image() isn't used here)
# ---------------------------------------------------------------------------

PROMPT_TEMPLATE = (
    "Edit this image in place. It is a videogame animation sprite sheet: a grid of "
    "{rows} rows x {cols} columns. Each row is one compass facing of the same "
    "character; each column is one animation frame. The figures are blank white "
    "mannequins. Paint EVERY mannequin as the same single character: {character}. "
    "Do NOT move, resize, add, remove or re-pose any figure. Do NOT change the grid: "
    "the output must have exactly the same {rows}x{cols} layout, same figure positions "
    "and sizes, same silhouettes and limb poses as the input. Only fill in surface "
    "detail: clothing, hair, skin, face, boots. Identical outfit and colors in every "
    "cell. Flat cel-shaded sprite style, clean dark outlines, max 3 shading tones per "
    "surface, pure white background, no grid lines, no text."
)

PROMPT_TEMPLATE_EMPHASIZED = (
    "Edit this image in place. It is a videogame animation sprite sheet: a grid of "
    "{rows} rows x {cols} columns. Each row is one compass facing of the same "
    "character; each column is one animation frame. The figures are blank white "
    "mannequins. Paint EVERY mannequin as the same single character: {character}. "
    "Do NOT move, resize, add, remove or re-pose any figure. Do NOT change the grid: "
    "the output must have exactly the same {rows}x{cols} layout, same figure positions "
    "and sizes, same silhouettes and limb poses as the input. Only fill in surface "
    "detail: clothing, hair, skin, face, boots. STRICT REQUIREMENT: use the EXACT SAME "
    "colors, hairstyle, and outfit details in every single cell without ANY variation -- "
    "treat this as one photograph of one specific individual, copy-pasted into every cell "
    "with only the pose changing. Do not reinterpret, re-shade, or re-color the character "
    "between cells; every cell must be pixel-identical in palette to every other cell. "
    "Flat cel-shaded sprite style, clean dark outlines, max 3 shading tones per surface, "
    "pure white background, no grid lines, no text."
)


def _padded_reference(sheet: str) -> tuple[Path, float]:
    """For sheets whose grid ratio has no exact aspect_ratio enum entry, build
    (once, cached in scratch) a white-right-padded copy of the mannequin sheet
    at the requested ratio. Returns (reference_path, crop_fraction) where
    crop_fraction is the width fraction of the output that contains the real
    grid (1.0 = no padding)."""
    src = SCRATCH / f"isometric_character_{sheet}_4k.png"
    ratio = PAD_TO_RATIO.get(sheet)
    if ratio is None:
        return src, 1.0
    padded_path = SCRATCH / f"_padded_{sheet}_4k.png"
    im = Image.open(src).convert("RGB")
    w, h = im.size
    target_w = round(h * ratio)
    if target_w <= w:
        return src, 1.0
    canvas = Image.new("RGB", (target_w, h), (255, 255, 255))
    canvas.paste(im, (0, 0))
    canvas.save(padded_path)
    return padded_path, w / target_w


def call_openrouter_images(model: str, prompt: str, aspect_ratio: str, ref_png: Path, key: str) -> bytes:
    b64 = base64.b64encode(ref_png.read_bytes()).decode("ascii")
    body = {
        "model": model,
        "prompt": prompt,
        "aspect_ratio": aspect_ratio,
        "input_references": [
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}}
        ],
    }
    req = urllib.request.Request(
        IMAGES_ENDPOINT,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    attempt = 0
    while True:
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            body_txt = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < MAX_RETRIES:
                attempt += 1
                wait = RETRY_BASE_SECONDS * (2 ** (attempt - 1))
                print(f"    [http {e.code}] retry {attempt}/{MAX_RETRIES} in {wait}s")
                time.sleep(wait)
                continue
            raise RuntimeError(f"HTTP {e.code}: {body_txt[:500]}")
        except urllib.error.URLError as e:
            if attempt < MAX_RETRIES:
                attempt += 1
                wait = RETRY_BASE_SECONDS * (2 ** (attempt - 1))
                print(f"    [network error] retry {attempt}/{MAX_RETRIES} in {wait}s: {e}")
                time.sleep(wait)
                continue
            raise RuntimeError(f"network error: {e}")

    imgs = data.get("data") or []
    if not imgs:
        raise RuntimeError(f"no image in response: {json.dumps(data)[:500]}")
    b64_json = imgs[0].get("b64_json")
    if b64_json:
        return base64.b64decode(b64_json)
    url = imgs[0].get("url") or ""
    if url.startswith("data:"):
        return base64.b64decode(url.split(",", 1)[1])
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


# ---------------------------------------------------------------------------
# Flood-fill alpha (white exterior -> transparent; enclosed whites like eyes
# survive because they aren't border-connected). Same algorithm as
# reskin_qa.py's silhouette(), but emits a real RGBA image.
# ---------------------------------------------------------------------------

def flood_fill_alpha(im: Image.Image, threshold: int = WHITE_THRESHOLD) -> Image.Image:
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = list(rgb.getdata())
    is_white = [r >= threshold and gc >= threshold and b >= threshold for r, gc, b in px]
    bg = bytearray(w * h)
    border = [i for i in range(w)] + [(h - 1) * w + i for i in range(w)] + \
             [r * w for r in range(h)] + [r * w + w - 1 for r in range(h)]
    stack = [i for i in border if is_white[i]]
    for i in stack:
        bg[i] = 1
    while stack:
        i = stack.pop()
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if is_white[j] and not bg[j]:
                    bg[j] = 1
                    stack.append(j)
    out = rgb.convert("RGBA")
    data = list(out.getdata())
    data = [(r, gc, b, 0 if bg[i] else 255) for i, (r, gc, b, _a) in enumerate(data)]
    out.putdata(data)
    return out


# ---------------------------------------------------------------------------
# Per-character palette (built from the idle sheet, snapped onto all 4 sheets)
# ---------------------------------------------------------------------------

def build_character_palette(idle_rgba: Image.Image, bands: int = 8, top_n: int = 3) -> list[tuple[int, int, int]]:
    bands_data = ps.extract_bands(idle_rgba, bands=bands, top_n=top_n)
    colors: list[tuple[int, int, int]] = []
    for band in bands_data:
        for color, _count in band:
            if any(math.dist(color, c) < 14 for c in colors):
                continue
            colors.append(color)
    if not colors:
        colors = [(0x14, 0x17, 0x1C), (0xE0, 0xB8, 0x98)]
    return colors


# ---------------------------------------------------------------------------
# QA: silhouette IoU (mannequin vs painted, per cell) + post-snap color drift
# ---------------------------------------------------------------------------

def _mannequin_silhouette(rgb_cell: Image.Image) -> list[bool]:
    rgb = rgb_cell.convert("RGB")
    w, h = rgb.size
    px = list(rgb.getdata())
    is_white = [r >= WHITE_THRESHOLD and gc >= WHITE_THRESHOLD and b >= WHITE_THRESHOLD for r, gc, b in px]
    bg = [False] * (w * h)
    border = [i for i in range(w)] + [(h - 1) * w + i for i in range(w)] + \
             [r * w for r in range(h)] + [r * w + w - 1 for r in range(h)]
    stack = [i for i in border if is_white[i]]
    for i in stack:
        bg[i] = True
    while stack:
        i = stack.pop()
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if is_white[j] and not bg[j]:
                    bg[j] = True
                    stack.append(j)
    return [not b for b in bg]


def qa_sheet(mannequin_path: Path, painted_rgba: Image.Image, sheet: str) -> dict:
    cols, rows = GRID[sheet]
    cell = 128
    size = (cols * cell, rows * cell)
    mannequin = Image.open(mannequin_path).convert("RGB").resize(size, Image.LANCZOS)
    # Resize RGB and alpha independently (NOT the composited RGBA as one resize):
    # PIL premultiplies color by alpha for RGBA resampling, which muddies pixels
    # near our hard 0/255 flood-fill edges and silently deflates the color-drift
    # signal. Splitting first keeps this numerically identical to reskin_qa.py's
    # plain-RGB approach (verified against its CLI output on the proven test sheets).
    painted_rgb = painted_rgba.convert("RGB").resize(size, Image.LANCZOS)
    painted_alpha = painted_rgba.split()[3].resize(size, Image.LANCZOS)

    ious, colors = [], []
    for r in range(rows):
        for c in range(cols):
            box = (c * cell, r * cell, (c + 1) * cell, (r + 1) * cell)
            m_mask = _mannequin_silhouette(mannequin.crop(box))
            p_mask = [v > 127 for v in painted_alpha.crop(box).getdata()]
            inter = sum(1 for x, y in zip(m_mask, p_mask) if x and y)
            union = sum(1 for x, y in zip(m_mask, p_mask) if x or y)
            ious.append(inter / union if union else 1.0)

            # Color drift uses reskin_qa.py's own mean_fg_color definition verbatim
            # (plain RGB near-white threshold, independent of the alpha/flood-fill
            # silhouette) so the drift number stays calibrated against this
            # session's proven baselines (13.7 excellent / 51.6 fixable-flash).
            pix = list(painted_rgb.crop(box).getdata())
            fg = [p for p in pix if not (p[0] >= WHITE_THRESHOLD and p[1] >= WHITE_THRESHOLD and p[2] >= WHITE_THRESHOLD)]
            if fg:
                n = len(fg)
                colors.append((sum(p[0] for p in fg) / n, sum(p[1] for p in fg) / n, sum(p[2] for p in fg) / n))
            else:
                colors.append((255.0, 255.0, 255.0))

    mean_iou = sum(ious) / len(ious)
    min_iou = min(ious)
    if colors:
        gm = tuple(sum(ch[i] for ch in colors) / len(colors) for i in range(3))
        drift = max(math.dist(ch, gm) for ch in colors)
    else:
        drift = 999.0
    passed = mean_iou >= QA_MEAN_IOU_MIN and min_iou >= QA_MIN_IOU_MIN and drift <= QA_DRIFT_MAX
    return {"mean_iou": round(mean_iou, 3), "min_iou": round(min_iou, 3), "drift": round(drift, 1), "pass": passed}


# ---------------------------------------------------------------------------
# Slicing + preview GIF
# ---------------------------------------------------------------------------

def slice_sheet(rgba: Image.Image, sheet: str, out_dir: Path) -> None:
    cols, rows = GRID[sheet]
    w, h = rgba.size
    cw, ch = w / cols, h / rows
    frames_dir = out_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    for r in range(rows):
        for c in range(cols):
            box = (round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch))
            cell = rgba.crop(box)
            cell.resize((MASTER_CELL, MASTER_CELL), Image.LANCZOS).save(frames_dir / f"{sheet}_{r}_{c}_128.png")
            cell.resize((GAME_CELL, GAME_CELL), Image.LANCZOS).save(frames_dir / f"{sheet}_{r}_{c}.png")


def write_preview_gif(rgba: Image.Image, sheet: str, row: int, out_path: Path, fps: int = 8) -> None:
    cols, rows = GRID[sheet]
    if row >= rows:
        row = rows - 1
    w, h = rgba.size
    cw, ch = w / cols, h / rows
    frames = []
    for c in range(cols):
        box = (round(c * cw), round(row * ch), round((c + 1) * cw), round((row + 1) * ch))
        frame = rgba.crop(box).resize((GAME_CELL, GAME_CELL), Image.LANCZOS).convert("RGBA")
        bg = Image.new("RGBA", frame.size, (255, 255, 255, 255))
        bg.alpha_composite(frame)
        frames.append(bg.convert("RGB"))
    frames[0].save(out_path, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0)


# ---------------------------------------------------------------------------
# Per-character pipeline
# ---------------------------------------------------------------------------

def generate_one_sheet(character_id: str, description: str, sheet: str, key: str,
                        palette: list[tuple[int, int, int]] | None = None,
                        ) -> tuple[Image.Image | None, dict, str, float]:
    """Generate + QA one sheet, with the flash->flash(emphasized)->pro escalation
    ladder. Returns (RAW rgba_image_or_None (pre-snap), qa_dict, model_used, cost).

    Gate placement per spec: IoU is structural (snap never touches alpha) but
    the drift gate applies AFTER palette snap -- so we QA a snap PREVIEW here,
    using the character's real palette (idle-derived) when available, else a
    palette extracted from the candidate itself. Gating raw drift pre-snap
    (the first pilot's behavior) escalated to pro for drift failures that the
    snap fixes for free."""
    cols, rows = GRID[sheet]
    src = SCRATCH / f"isometric_character_{sheet}_4k.png"
    ref, crop_frac = _padded_reference(sheet)

    def _qa_candidate(rgba: Image.Image) -> dict:
        gate_palette = palette or build_character_palette(rgba)
        preview = ps.snap_image(rgba, palette=gate_palette)
        return qa_sheet(src, preview, sheet)

    def _receive(png: bytes) -> Image.Image:
        img = Image.open(__import__("io").BytesIO(png))
        if crop_frac < 1.0:
            w, h = img.size
            img = img.crop((0, 0, round(w * crop_frac), h))
        return flood_fill_alpha(img)

    margin_clause = (
        " The blank white strip on the right edge of the canvas is intentional "
        "margin: leave it completely blank white, paint nothing there."
        if crop_frac < 1.0 else ""
    )

    attempts = [
        (MODEL_FLASH, PROMPT_TEMPLATE),
        (MODEL_FLASH, PROMPT_TEMPLATE_EMPHASIZED),
    ]

    last_qa, last_img, last_model, total_cost = None, None, None, 0.0
    for i, (model, template) in enumerate(attempts):
        remaining = get_remaining_credits(key)
        if remaining < STOP_THRESHOLD:
            print(f"    [budget] remaining ${remaining:.2f} < ${STOP_THRESHOLD} -- stopping before {model}")
            return None, {"pass": False, "reason": "budget"}, model, total_cost
        prompt = template.format(rows=rows, cols=cols, character=description) + margin_clause
        print(f"    [{sheet}] attempt {i+1}: {model} (credits remaining ${remaining:.2f})", flush=True)
        try:
            png = call_openrouter_images(model, prompt, ASPECT[sheet], ref, key)
        except RuntimeError as e:
            print(f"    [{sheet}] generation FAILED: {e}")
            continue
        total_cost += EST_COST[model]
        rgba = _receive(png)
        qa = _qa_candidate(rgba)
        print(f"    [{sheet}] {model}: mean_iou={qa['mean_iou']} min_iou={qa['min_iou']} drift(post-snap)={qa['drift']} pass={qa['pass']}", flush=True)
        last_qa, last_img, last_model = qa, rgba, model
        if qa["pass"]:
            return rgba, qa, model, total_cost

    # escalate to pro if we still have headroom
    remaining = get_remaining_credits(key)
    if remaining > PRO_ESCALATION_THRESHOLD:
        print(f"    [{sheet}] escalating to {MODEL_PRO} (credits remaining ${remaining:.2f})", flush=True)
        prompt = PROMPT_TEMPLATE_EMPHASIZED.format(rows=rows, cols=cols, character=description) + margin_clause
        try:
            png = call_openrouter_images(MODEL_PRO, prompt, ASPECT[sheet], ref, key)
            total_cost += EST_COST[MODEL_PRO]
            rgba = _receive(png)
            qa = _qa_candidate(rgba)
            print(f"    [{sheet}] {MODEL_PRO}: mean_iou={qa['mean_iou']} min_iou={qa['min_iou']} drift(post-snap)={qa['drift']} pass={qa['pass']}", flush=True)
            return rgba, qa, MODEL_PRO, total_cost
        except RuntimeError as e:
            print(f"    [{sheet}] pro generation FAILED: {e}")

    return last_img, (last_qa or {"pass": False, "reason": "no successful generation"}), last_model or "none", total_cost


def run_character(entry: dict, key: str, existing: dict | None = None) -> dict:
    """existing: this character's previous manifest entry, if any -- sheets that
    already passed QA and have a sheet_*.png on disk are reused instead of
    re-spending on them (resume-safe partial reruns, e.g. after a bugfix that
    only affected one sheet type)."""
    model_id = entry["id"]
    out_dir = OUT_ROOT / model_id
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n=== {model_id} ({entry['kind']}) ===\n  {entry['description']}")

    raw_sheets: dict[str, Image.Image] = {}
    qa_by_sheet: dict[str, dict] = {}
    models_used: dict[str, str] = {}
    total_cost = 0.0
    needs_regen = []

    ckpt_dir = CKPT_ROOT / model_id
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    ckpt_path = ckpt_dir / "checkpoint.json"
    ckpt = json.loads(ckpt_path.read_text(encoding="utf-8")) if ckpt_path.exists() else {}

    # The character palette comes from the idle sheet (generated first) and is
    # both the QA-gate palette for the remaining sheets and the final snap target.
    palette: list[tuple[int, int, int]] | None = None

    for sheet in SHEETS:
        # Reuse order: (1) finalized manifest entry + snapped sheet on disk,
        # (2) crash/timeout checkpoint (raw pre-snap sheet in scratch). Both
        # avoid re-spending on a sheet that already passed QA.
        existing_qa = (existing or {}).get("qa", {}).get(sheet, {})
        existing_path = out_dir / f"sheet_{sheet}.png"
        ckpt_entry = ckpt.get(sheet, {})
        ckpt_raw = ckpt_dir / f"raw_{sheet}.png"
        if existing_qa.get("pass") and existing_path.exists():
            print(f"    [{sheet}] reusing passing sheet from manifest (skip regen)")
            raw_sheets[sheet] = Image.open(existing_path).convert("RGBA")
            qa_by_sheet[sheet] = existing_qa
            models_used[sheet] = (existing or {}).get("model_used", {}).get(sheet, "reused")
        elif ckpt_entry.get("qa", {}).get("pass") and ckpt_raw.exists():
            print(f"    [{sheet}] reusing passing sheet from checkpoint (skip regen)")
            raw_sheets[sheet] = Image.open(ckpt_raw).convert("RGBA")
            qa_by_sheet[sheet] = ckpt_entry["qa"]
            models_used[sheet] = ckpt_entry.get("model", "checkpoint")
        else:
            rgba, qa, model, cost = generate_one_sheet(model_id, entry["description"], sheet, key,
                                                        palette=palette)
            total_cost += cost
            qa_by_sheet[sheet] = qa
            models_used[sheet] = model
            if rgba is None:
                needs_regen.append(sheet)
                continue
            raw_sheets[sheet] = rgba
            if not qa.get("pass"):
                needs_regen.append(sheet)
            else:
                # Checkpoint immediately: a later crash/timeout must not lose
                # this paid, passing sheet.
                rgba.save(ckpt_raw)
                ckpt[sheet] = {"qa": qa, "model": model, "cost": cost}
                ckpt_path.write_text(json.dumps(ckpt, indent=2), encoding="utf-8")

        if sheet == "idle" and palette is None and "idle" in raw_sheets:
            palette = build_character_palette(raw_sheets["idle"])

    if not raw_sheets:
        return {
            "id": model_id, "kind": entry["kind"], "name": entry.get("name"), "tag": entry.get("tag"),
            "description": entry["description"], "palette": [], "qa": qa_by_sheet, "model_used": models_used,
            "spend": round(total_cost, 4), "needs_regeneration": SHEETS, "status": "failed",
        }

    # Character palette: idle-derived (set during the sheet loop); fall back to
    # any available sheet if idle never passed.
    if palette is None:
        palette = build_character_palette(next(iter(raw_sheets.values())))
    palette_hex = [f"#{r:02x}{gc:02x}{b:02x}" for r, gc, b in palette]

    for sheet, rgba in raw_sheets.items():
        snapped = ps.snap_image(rgba, palette=palette)
        raw_sheets[sheet] = snapped
        # Authoritative manifest QA is post-snap (matches the gate's snap preview
        # for freshly generated sheets; re-verifies reused ones).
        qa_by_sheet[sheet] = qa_sheet(SCRATCH / f"isometric_character_{sheet}_4k.png", snapped, sheet)
        if not qa_by_sheet[sheet]["pass"] and sheet not in needs_regen:
            needs_regen.append(sheet)
        snapped.save(out_dir / f"sheet_{sheet}.png")
        slice_sheet(snapped, sheet, out_dir)

    if "walk" in raw_sheets:
        write_preview_gif(raw_sheets["walk"], "walk", row=3, out_path=out_dir / "preview_walk.gif")

    status = "complete" if not needs_regen else "partial"

    # Checkpoint hygiene: finished sheets are now persisted under gen3_chars,
    # so drop their scratch copies; sheets that ended in needs_regen (e.g. a
    # post-snap drift fail) must NOT keep a "passing" checkpoint or a rerun
    # would reuse the bad sheet forever instead of regenerating it.
    if status == "complete":
        for p in ckpt_dir.glob("*"):
            p.unlink()
        try:
            ckpt_dir.rmdir()
        except OSError:
            pass
    else:
        for sheet in needs_regen:
            ckpt.pop(sheet, None)
            (ckpt_dir / f"raw_{sheet}.png").unlink(missing_ok=True)
        ckpt_path.write_text(json.dumps(ckpt, indent=2), encoding="utf-8")
    return {
        "id": model_id, "kind": entry["kind"], "name": entry.get("name"), "tag": entry.get("tag"),
        "description": entry["description"], "palette": palette_hex, "qa": qa_by_sheet,
        "model_used": models_used, "spend": round(total_cost, 4), "needs_regeneration": needs_regen,
        "status": status,
    }


# ---------------------------------------------------------------------------
# Manifest persistence
# ---------------------------------------------------------------------------

def load_manifest() -> dict:
    if MANIFEST_PATH.exists():
        return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    return {"_meta": {"total_spend": 0.0}, "characters": {}}


def save_manifest(manifest: dict) -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_list() -> None:
    roster = build_roster()
    print(f"{len(roster)} models planned:")
    for e in roster:
        print(f"  [{e['kind']:5s}] {e['id']:20s} {e.get('name',''):28s} {e['description'][:90]}")


def cmd_credits() -> None:
    key = g.load_api_key()
    remaining = get_remaining_credits(key)
    print(f"remaining credits: ${remaining:.2f}")


def cmd_slice_test() -> None:
    """Offline dry run: exercise QA + slicing + GIF on the existing proven test
    sheets in assets/scratch/_reskin_test/ -- no network calls."""
    tests = [
        ("idle", TEST_DIR / "engineer_idle_gemini3.png"),
        ("walk", TEST_DIR / "engineer_walk_flash.png"),
        ("walk", TEST_DIR / "engineer_walk_gemini3.png"),
    ]
    out_dir = REPO_ROOT / "assets" / "scratch" / "_reskin_test" / "_slice_dry_run"
    out_dir.mkdir(parents=True, exist_ok=True)
    for sheet, path in tests:
        if not path.exists():
            print(f"skip (missing): {path}")
            continue
        img = Image.open(path)
        rgba = flood_fill_alpha(img)
        qa = qa_sheet(SCRATCH / f"isometric_character_{sheet}_4k.png", rgba, sheet)
        print(f"{path.name} [{sheet}]: {qa}")
        palette = build_character_palette(rgba) if sheet == "idle" else build_character_palette(rgba)
        snapped = ps.snap_image(rgba, palette=palette)
        qa2 = qa_sheet(SCRATCH / f"isometric_character_{sheet}_4k.png", snapped, sheet)
        print(f"  post-snap: {qa2}  (palette size={len(palette)})")
        d = out_dir / path.stem
        d.mkdir(exist_ok=True)
        slice_sheet(snapped, sheet, d)
        if sheet == "walk":
            write_preview_gif(snapped, "walk", row=3, out_path=d / "preview_walk.gif")
        print(f"  sliced -> {d}")


def cmd_character(name: str) -> None:
    roster = {e["id"].lower(): e for e in build_roster()}
    entry = roster.get(name.lower())
    if not entry:
        # allow matching by tag too
        for e in build_roster():
            if e.get("tag", "").lower() == name.lower():
                entry = e
                break
    if not entry:
        print(f"unknown character id/tag: {name}")
        sys.exit(1)
    key = g.load_api_key()
    manifest = load_manifest()
    result = run_character(entry, key, existing=manifest["characters"].get(entry["id"]))
    manifest["characters"][entry["id"]] = result
    manifest["_meta"]["total_spend"] = round(manifest["_meta"].get("total_spend", 0.0) + result["spend"], 4)
    save_manifest(manifest)
    print(f"\n{entry['id']}: status={result['status']} spend=${result['spend']:.3f} needs_regen={result['needs_regeneration']}")


def cmd_run_all(start: int, limit: int | None, kind: str | None) -> None:
    roster = build_roster()
    if kind:
        roster = [e for e in roster if e["kind"] == kind]
    roster = roster[start:]
    if limit:
        roster = roster[:limit]

    key = g.load_api_key()
    manifest = load_manifest()
    done = 0
    for entry in roster:
        prev = manifest["characters"].get(entry["id"])
        if prev and prev.get("status") == "complete":
            print(f"\n>>> {entry['id']}: already complete, skipping")
            done += 1
            continue
        remaining = get_remaining_credits(key)
        print(f"\n>>> credits remaining: ${remaining:.2f}")
        if remaining < STOP_THRESHOLD:
            print(f">>> STOPPING: remaining ${remaining:.2f} < ${STOP_THRESHOLD} threshold. "
                  f"{done}/{len(roster)} of this run completed.")
            break
        result = run_character(entry, key, existing=manifest["characters"].get(entry["id"]))
        manifest["characters"][entry["id"]] = result
        manifest["_meta"]["total_spend"] = round(manifest["_meta"].get("total_spend", 0.0) + result["spend"], 4)
        save_manifest(manifest)
        done += 1
    print(f"\n=== run-all complete: {done}/{len(roster)} models processed this invocation ===")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--credits", action="store_true")
    ap.add_argument("--slice-test", action="store_true")
    ap.add_argument("--character", type=str)
    ap.add_argument("--run-all", action="store_true")
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--kind", type=str, choices=["crew", "npc", "robot"], default=None)
    args = ap.parse_args()

    if args.list:
        cmd_list()
    elif args.credits:
        cmd_credits()
    elif args.slice_test:
        cmd_slice_test()
    elif args.character:
        cmd_character(args.character)
    elif args.run_all:
        cmd_run_all(args.start, args.limit, args.kind)
    else:
        ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
