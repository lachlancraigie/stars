# asset_gen

Style-agnostic sprite generation pipeline for SHIP AI, backed by the
[Reve](https://reve.com) image API (`reve.v1.image`). Replaces the
ComfyUI/SwarmUI workflow sketched in `docs/swarm-sprite-pipeline.md` -- the
asset list, naming conventions, and QA criteria carry over, only the
generation backend changed.

## Files

| File | Purpose |
|---|---|
| `manifest.json` | Declarative list of every asset to generate: id, output path, style-neutral subject prompt, aspect ratio, size class, whether background removal is needed, optional per-asset `references`. |
| `style.json` | The active art-style pack: the locked Flat Vector style (see `docs/art-direction.md`), wired to the approved anchors in `anchors/`. |
| `style.json.example` | Template documenting the style-pack format (prefix/suffix prompt text, `anchor_images`, `category_anchors`, `category_overrides`). |
| `anchors/` | Approved style-anchor images referenced by `style.json`. |
| `generate.py` | Generates staged sprites from the manifest + style pack via the Reve API. |
| `promote.py` | Copies QA-passed staged sprites from `staging/` into their final `assets/sprites/...` locations. |
| `staging/` | Generated output + `report.json` (gitignored -- never committed). |

## Setup

```bash
pip install reve Pillow
export REVE_API_TOKEN="papi.your-token-here"   # never hardcode this anywhere
```

The committed `style.json` is already the locked Flat Vector style pack; only
touch it (or pass `--style other.json`) if the art direction changes.

`generate.py` and `promote.py` work without `reve`/`Pillow` installed as long
as you only use `--dry-run` (generate.py) or operate on already-staged files
where extensions already match (promote.py).

## Workflow

1. **Dry run first, always.** Confirms prompts compose correctly and estimates
   credit cost with no API calls and no token required:

   ```bash
   python tools/asset_gen/generate.py --phase 6 --dry-run
   ```

2. **Generate a small batch** to sanity-check the style pack before spending
   the full budget:

   ```bash
   python tools/asset_gen/generate.py --phase 6 --limit 5
   ```

   Output lands in `tools/asset_gen/staging/`, one file per asset id, plus
   `staging/report.json` recording the exact prompt used, credits spent, and
   QA results for every asset attempted so far (re-running resumes/updates
   this file rather than overwriting it).

3. **Review staged files by hand.** Open `staging/report.json` to see which
   assets QA flagged (`"qa": {"pass": false, ...}` with human-readable
   `notes`) -- flagged files are kept, not deleted, so you can eyeball them
   too.

4. **Generate the rest** once the style pack looks right:

   ```bash
   python tools/asset_gen/generate.py --phase 6
   python tools/asset_gen/generate.py --phase 7
   ```

   Use `--only id1,id2` to regenerate specific assets (e.g. after tweaking
   `style.json`), and `--limit N` to cap how many API calls a single run
   makes (useful for budget pacing -- Reve costs ~18 credits/image).

5. **Promote what passed:**

   ```bash
   python tools/asset_gen/promote.py --all-passed
   # or, to force-promote specific ids regardless of QA flags:
   python tools/asset_gen/promote.py --only room_bridge,door_open
   ```

   This copies staged files into the paths declared in `manifest.json`
   (`assets/sprites/...`), which Godot's FileSystem dock will pick up on next
   editor focus.

## Style packs and consistency

If `style.json` declares style anchors (paths to approved reference images),
`generate.py` calls `reve.v1.image.remix()` with those images as references
instead of `create()`, keeping new generations visually consistent with the
locked style. Two levels of anchoring:

- `anchor_images` -- global anchors, used for any asset whose category has no
  entry in `category_anchors` (currently: ui, fx fall back to the room anchor
  for general style pull).
- `category_anchors` -- object mapping category (rooms/doors/crew/portraits/
  ui/fx) to its own anchor list; takes precedence over `anchor_images` for
  assets of that category, so e.g. the room anchor never steers crew
  generation.

Approved anchors for the locked Flat Vector style live in
`tools/asset_gen/anchors/`. Assets with no applicable anchors at all use
plain `create()` driven by the prompt text alone.

### Per-asset references (crew pose chaining)

A manifest asset may declare its own `references` list: extra image paths
appended **after** the style anchors in the `remix()` call. In the composed
prompt, anchors are cited as "Match the established art style of
`<ref>0</ref>`..." and per-asset references as "Match the character design of
`<ref>N</ref>`..." with indices numbered anchors-first.

The crew set uses this for cross-pose consistency: each role's `idle_s`
sprite is ordered first in the manifest, and the role's other 9 sprites
reference `tools/asset_gen/staging/crew_<role>_idle_s.png` -- so within a
single top-to-bottom run, the freshly staged south-idle becomes the character
design reference for that role's remaining poses. (Workflow implication:
generate and approve each role's `idle_s` before, or in the same run as, the
rest of that role's sprites; regenerating an `idle_s` means regenerating the
poses chained to it.)

If any referenced image is missing on disk at generation time, that asset is
recorded as failed in `report.json` with a clear error and the run continues.

### Path resolution

All image paths in `style.json` (`anchor_images`, `category_anchors`) and in
manifest `references` are resolved relative to the **repo root** (two levels
up from `tools/asset_gen/`), never the current working directory, so the tool
works when invoked from anywhere. Absolute paths pass through unchanged.

## QA heuristics

Applied automatically to every generated asset, per
`docs/swarm-sprite-pipeline.md`'s auto-reject criteria:

- the image actually loads (not corrupted/empty)
- has an alpha channel when the manifest requested background removal
- corner pixels are transparent (crude "background actually got removed,
  not just made vaguely dark" check)
- aspect ratio is within tolerance of the asset's size class

None of these are auto-rejects that delete files -- they only set
`qa.pass = false` and record `qa.notes` in `report.json` so a human makes the
final call in the promote step.

## Rate limits and budget

`generate.py` retries on `ReveRateLimitError` with the SDK-provided
`retry_after` backoff (falling back to a fixed delay), and stops the run
cleanly on `ReveBudgetExhaustedError`, leaving `report.json` intact so a later
run picks up where it left off. `--dry-run` prints an estimated credit cost
for the selected assets against a working budget of ~7400 credits so you can
size `--limit`/`--phase` before spending anything.
