# asset_gen

Style-agnostic sprite generation pipeline for SHIP AI, backed by the
[Reve](https://reve.com) image API (`reve.v1.image`). Replaces the
ComfyUI/SwarmUI workflow sketched in `docs/swarm-sprite-pipeline.md` -- the
asset list, naming conventions, and QA criteria carry over, only the
generation backend changed.

## Files

| File | Purpose |
|---|---|
| `manifest.json` | Declarative list of every asset to generate: id, output path, style-neutral subject prompt, aspect ratio, size class, whether background removal is needed. |
| `style.json.example` | Template for the art-style pack (prefix/suffix prompt text, optional style anchor reference images, per-category overrides). Copy to `style.json` once an art style is locked in. |
| `generate.py` | Generates staged sprites from the manifest + style pack via the Reve API. |
| `promote.py` | Copies QA-passed staged sprites from `staging/` into their final `assets/sprites/...` locations. |
| `staging/` | Generated output + `report.json` (gitignored -- never committed). |

## Setup

```bash
pip install reve Pillow
export REVE_API_TOKEN="papi.your-token-here"   # never hardcode this anywhere
cp tools/asset_gen/style.json.example tools/asset_gen/style.json
# edit style.json once the art style is decided
```

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

If `style.json` declares `anchor_images` (paths to a handful of approved,
already-generated reference images), `generate.py` calls
`reve.v1.image.remix()` with those images as references for every asset
instead of `create()`, keeping new generations visually consistent with the
locked style. Until anchors exist, everything uses plain `create()` driven by
`style_prefix` / `style_suffix` / `category_overrides` text alone.

Recommended bootstrap sequence: generate a handful of assets with `create()`
only (no anchors), hand-pick the best 2-3 as anchors, add their paths to
`style.json`'s `anchor_images`, then regenerate everything else with
`remix()` for consistency.

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
