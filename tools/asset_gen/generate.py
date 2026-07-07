#!/usr/bin/env python3
"""Style-agnostic sprite generation pipeline for SHIP AI, backed by the Reve image API.

Reads a declarative manifest.json (what to generate) and a style.json (how it should
look), composes prompts, calls the Reve v1 image API, runs lightweight QA on the
result, and writes everything to a staging directory for human review. Nothing is
written directly into assets/ -- use promote.py for that once staged files pass QA.

Usage:
    python generate.py --dry-run                       # sanity-check prompts, no API calls
    python generate.py --phase 6 --limit 5              # generate the first 5 phase-6 assets
    python generate.py --only room_bridge,door_closed    # generate specific ids
    python generate.py --style my_style.json --out-dir staging_v2

See README.md in this directory for the full workflow.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent

DEFAULT_MANIFEST = SCRIPT_DIR / "manifest.json"
DEFAULT_STYLE = SCRIPT_DIR / "style.json"
DEFAULT_STYLE_EXAMPLE = SCRIPT_DIR / "style.json.example"
DEFAULT_OUT_DIR = SCRIPT_DIR / "staging"

CREDITS_PER_IMAGE_ESTIMATE = 18  # rough budgeting figure, see docs/swarm-sprite-pipeline.md
BUDGET_CREDITS = 7400

MAX_RATE_LIMIT_RETRIES = 5
DEFAULT_RETRY_SECONDS = 5

# ---------------------------------------------------------------------------
# Optional dependencies -- guarded so --dry-run works without them installed.
# ---------------------------------------------------------------------------

try:
    from PIL import Image

    PIL_AVAILABLE = True
except ImportError:  # pragma: no cover - exercised only when Pillow is missing
    Image = None  # type: ignore[assignment]
    PIL_AVAILABLE = False

try:
    from reve.v1.image import create, get_balance, remix
    from reve.v1.postprocessing import fit_image, remove_background
    from reve.exceptions import (
        ReveAPIError,
        ReveBudgetExhaustedError,
        ReveRateLimitError,
    )

    REVE_AVAILABLE = True
except ImportError:  # pragma: no cover - exercised only when reve is missing
    REVE_AVAILABLE = False


# ---------------------------------------------------------------------------
# Manifest / style loading
# ---------------------------------------------------------------------------


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"manifest not found: {path}")
    with path.open() as f:
        data = json.load(f)
    if "assets" not in data:
        raise SystemExit(f"manifest {path} has no 'assets' key")
    return data


def load_style(path: Path, *, dry_run: bool) -> dict[str, Any]:
    if not path.exists():
        if dry_run and DEFAULT_STYLE_EXAMPLE.exists():
            print(
                f"[warn] {path} not found; previewing with "
                f"{DEFAULT_STYLE_EXAMPLE.name} (placeholder, dry-run only)"
            )
            path = DEFAULT_STYLE_EXAMPLE
        else:
            raise SystemExit(
                f"style file not found: {path}\n"
                f"Copy style.json.example to style.json and lock in an art style first."
            )
    with path.open() as f:
        return json.load(f)


def filter_assets(
    assets: list[dict[str, Any]],
    *,
    phase: int | None,
    only: set[str] | None,
) -> list[dict[str, Any]]:
    result = assets
    if phase is not None:
        result = [a for a in result if a.get("phase") == phase]
    if only is not None:
        by_id = {a["id"]: a for a in result}
        missing = only - by_id.keys()
        if missing:
            raise SystemExit(f"--only referenced unknown asset id(s): {sorted(missing)}")
        result = [by_id[i] for i in only]
        # preserve manifest ordering rather than --only ordering
        order = {a["id"]: idx for idx, a in enumerate(assets)}
        result.sort(key=lambda a: order[a["id"]])
    return result


# ---------------------------------------------------------------------------
# Prompt composition
# ---------------------------------------------------------------------------


def compose_prompt(asset: dict[str, Any], style: dict[str, Any]) -> str:
    parts = [style.get("style_prefix", "").strip()]
    parts.append(asset["subject"].strip())

    override = style.get("category_overrides", {}).get(asset.get("category", ""))
    if override:
        parts.append(override.strip())

    parts.append(style.get("style_suffix", "").strip())

    anchors = style.get("anchor_images") or []
    if anchors:
        refs = ", ".join(f"<ref>{i}</ref>" for i in range(len(anchors)))
        parts.append(f"Match the established art style and character design shown in {refs}.")

    return " ".join(p for p in parts if p)


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------


def staged_path(out_dir: Path, asset: dict[str, Any]) -> Path:
    ext = ".png" if asset.get("remove_background") else ".jpg"
    return out_dir / f"{asset['id']}{ext}"


def build_postprocessing(asset: dict[str, Any], size_classes: dict[str, Any]) -> list[Any]:
    steps = []
    if asset.get("remove_background"):
        steps.append(remove_background())
    size_class = size_classes.get(asset.get("size_class", ""))
    if size_class:
        steps.append(fit_image(max_width=size_class["width"], max_height=size_class["height"]))
    return steps


def call_with_retry(fn, *args, **kwargs):
    """Call fn(*args, **kwargs), retrying on rate limit with backoff.

    Lets ReveBudgetExhaustedError (and any other ReveAPIError) propagate --
    those are not retryable.
    """
    attempt = 0
    while True:
        try:
            return fn(*args, **kwargs)
        except ReveRateLimitError as exc:
            attempt += 1
            if attempt > MAX_RATE_LIMIT_RETRIES:
                raise
            wait = getattr(exc, "retry_after", None) or DEFAULT_RETRY_SECONDS
            print(
                f"  [rate limit] retrying in {wait}s "
                f"(attempt {attempt}/{MAX_RATE_LIMIT_RETRIES})"
            )
            time.sleep(wait)


def generate_one(
    asset: dict[str, Any],
    style: dict[str, Any],
    size_classes: dict[str, Any],
    out_dir: Path,
) -> dict[str, Any]:
    prompt = compose_prompt(asset, style)
    postprocessing = build_postprocessing(asset, size_classes)
    anchors = style.get("anchor_images") or []

    if anchors:
        mode = "remix"
        result = call_with_retry(
            remix,
            prompt,
            anchors,
            aspect_ratio=asset["aspect_ratio"],
            postprocessing=postprocessing,
        )
    else:
        mode = "create"
        result = call_with_retry(
            create,
            prompt,
            aspect_ratio=asset["aspect_ratio"],
            postprocessing=postprocessing,
        )

    dest = staged_path(out_dir, asset)
    result.save(dest)

    qa = run_qa(dest, asset, size_classes)

    return {
        "id": asset["id"],
        "phase": asset.get("phase"),
        "category": asset.get("category"),
        "mode": mode,
        "prompt": prompt,
        "staged_path": str(dest),
        "final_output": asset["output"],
        "credits_used": getattr(result, "credits_used", None),
        "credits_remaining": getattr(result, "credits_remaining", None),
        "qa": qa,
    }


# ---------------------------------------------------------------------------
# QA
# ---------------------------------------------------------------------------


def run_qa(
    image_path: Path,
    asset: dict[str, Any],
    size_classes: dict[str, Any],
) -> dict[str, Any]:
    """Lightweight QA per docs/swarm-sprite-pipeline.md.

    Checks: image loads, has an alpha channel when bg removal was requested,
    corners are actually transparent (not a near-solid background left behind),
    and the aspect ratio is in the right ballpark for its size class.

    Failures are flagged, not fatal -- the staged file is kept for human review.
    """
    qa: dict[str, Any] = {
        "loaded": False,
        "has_alpha": None,
        "corners_transparent": None,
        "aspect_ok": None,
        "pass": False,
        "notes": [],
    }

    if not PIL_AVAILABLE:
        qa["notes"].append("Pillow not installed; QA skipped")
        return qa

    try:
        img = Image.open(image_path)
        img.load()
    except Exception as exc:  # noqa: BLE001 - report any load failure as QA data
        qa["notes"].append(f"failed to load image: {exc}")
        return qa

    qa["loaded"] = True
    expect_alpha = bool(asset.get("remove_background"))

    if expect_alpha:
        has_alpha = img.mode in ("RGBA", "LA") or "transparency" in img.info
        qa["has_alpha"] = has_alpha
        if not has_alpha:
            qa["notes"].append("expected alpha channel (background removal requested) but none found")
        else:
            rgba = img.convert("RGBA")
            w, h = rgba.size
            corners = [
                rgba.getpixel((0, 0)),
                rgba.getpixel((w - 1, 0)),
                rgba.getpixel((0, h - 1)),
                rgba.getpixel((w - 1, h - 1)),
            ]
            alpha_threshold = 25
            transparent_corners = sum(1 for px in corners if px[3] <= alpha_threshold)
            corners_transparent = transparent_corners >= 3
            qa["corners_transparent"] = corners_transparent
            if not corners_transparent:
                qa["notes"].append(
                    "background does not look removed: "
                    f"only {transparent_corners}/4 corners are transparent"
                )
    else:
        qa["has_alpha"] = None
        qa["corners_transparent"] = None

    size_class = size_classes.get(asset.get("size_class", ""))
    if size_class:
        expected_ratio = size_class["width"] / size_class["height"]
        actual_ratio = img.width / img.height
        tolerance = 0.35
        aspect_ok = abs(actual_ratio - expected_ratio) / expected_ratio <= tolerance
        qa["aspect_ok"] = aspect_ok
        if not aspect_ok:
            qa["notes"].append(
                f"aspect ratio {actual_ratio:.2f} is far from expected "
                f"{expected_ratio:.2f} for size class {asset.get('size_class')}"
            )
    else:
        qa["aspect_ok"] = None

    qa["pass"] = qa["loaded"] and (qa["has_alpha"] is not False) and (
        qa["corners_transparent"] is not False
    ) and (qa["aspect_ok"] is not False)

    return qa


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def load_report(report_path: Path) -> dict[str, Any]:
    if report_path.exists():
        with report_path.open() as f:
            return json.load(f)
    return {"results": {}}


def save_report(report_path: Path, report: dict[str, Any]) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w") as f:
        json.dump(report, f, indent=2)
        f.write("\n")


# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------


def dry_run(
    assets: list[dict[str, Any]],
    style: dict[str, Any],
    size_classes: dict[str, Any],
    out_dir: Path,
) -> None:
    anchors = style.get("anchor_images") or []
    mode = "remix" if anchors else "create"

    for asset in assets:
        prompt = compose_prompt(asset, style)
        dest = staged_path(out_dir, asset)
        pp_steps = []
        if asset.get("remove_background"):
            pp_steps.append("remove_background()")
        size_class = size_classes.get(asset.get("size_class", ""))
        if size_class:
            pp_steps.append(f"fit_image(max_width={size_class['width']}, max_height={size_class['height']})")

        print(f"--- {asset['id']} (phase {asset.get('phase')}, {asset.get('category')}) ---")
        print(f"  mode:        {mode}")
        print(f"  prompt:      {prompt}")
        print(f"  aspect:      {asset['aspect_ratio']}  size_class: {asset.get('size_class')}")
        print(f"  postproc:    {', '.join(pp_steps) if pp_steps else '(none)'}")
        print(f"  staged path: {dest}")
        print(f"  final dest:  {asset['output']}")

    n = len(assets)
    estimated_cost = n * CREDITS_PER_IMAGE_ESTIMATE
    print()
    print(f"[dry-run] {n} asset(s) selected")
    print(
        f"[dry-run] estimated cost: {estimated_cost} credits "
        f"(~{CREDITS_PER_IMAGE_ESTIMATE}/image, budget {BUDGET_CREDITS})"
    )
    if estimated_cost > BUDGET_CREDITS:
        print("[dry-run] WARNING: estimated cost exceeds budget -- use --limit or --phase to split the run")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--style", type=Path, default=DEFAULT_STYLE)
    parser.add_argument("--phase", type=int, default=None, help="only generate assets from this phase")
    parser.add_argument("--only", type=str, default=None, help="comma-separated asset ids")
    parser.add_argument("--limit", type=int, default=None, help="stop after generating N assets")
    parser.add_argument("--dry-run", action="store_true", help="print composed prompts, no API calls")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    manifest = load_manifest(args.manifest)
    style = load_style(args.style, dry_run=args.dry_run)
    size_classes = manifest.get("size_classes", {})

    only = set(args.only.split(",")) if args.only else None
    assets = filter_assets(manifest["assets"], phase=args.phase, only=only)
    if args.limit is not None:
        assets = assets[: args.limit]

    if not assets:
        print("no assets matched the given filters")
        return 0

    if args.dry_run:
        dry_run(assets, style, size_classes, args.out_dir)
        return 0

    if not PIL_AVAILABLE:
        raise SystemExit("Pillow is required for real generation runs (pip install Pillow)")
    if not REVE_AVAILABLE:
        raise SystemExit("reve is required for real generation runs (pip install reve)")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.out_dir / "report.json"
    report = load_report(report_path)

    try:
        balance = get_balance()
        print(f"[reve] starting balance: {balance.get('new_balance')}")
    except ReveAPIError as exc:
        print(f"[reve] could not fetch balance: {exc}")

    total_credits_used = 0
    generated = 0
    stopped_early = False

    for asset in assets:
        print(f"generating {asset['id']} ...")
        try:
            record = generate_one(asset, style, size_classes, args.out_dir)
        except ReveBudgetExhaustedError as exc:
            print(f"[reve] budget exhausted, stopping: {exc}")
            stopped_early = True
            break
        except ReveAPIError as exc:
            print(f"  [error] {asset['id']}: {exc}")
            report["results"][asset["id"]] = {
                "id": asset["id"],
                "phase": asset.get("phase"),
                "category": asset.get("category"),
                "error": str(exc),
                "qa": {"pass": False, "notes": [f"generation failed: {exc}"]},
            }
            save_report(report_path, report)
            continue

        report["results"][record["id"]] = record
        save_report(report_path, report)

        credits_used = record.get("credits_used") or 0
        total_credits_used += credits_used
        generated += 1

        qa_status = "PASS" if record["qa"].get("pass") else "FLAGGED"
        print(
            f"  saved {record['staged_path']}  "
            f"[{qa_status}]  credits_used={credits_used} "
            f"credits_remaining={record.get('credits_remaining')}"
        )

    print()
    print(f"generated {generated}/{len(assets)} asset(s); {total_credits_used} credits used this run")
    if stopped_early:
        print("run stopped early -- re-run the same command later to resume where it left off")
    print(f"report written to {report_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
