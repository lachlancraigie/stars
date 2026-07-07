#!/usr/bin/env python3
"""Promote QA-passed staged sprites into their final assets/sprites/... locations.

generate.py never writes into assets/ directly -- staged files sit in staging/
(or a custom --out-dir) until a human has looked at them. This script is the
human-in-the-loop gate: it reads staging/report.json and copies staged files
whose QA passed (or that you name explicitly) into the paths declared in
manifest.json, creating destination directories as needed.

Usage:
    python promote.py --all-passed                 # promote everything QA marked as pass
    python promote.py --only room_bridge,door_open  # promote specific ids regardless of QA
    python promote.py --all-passed --dry-run        # preview without copying
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent

DEFAULT_MANIFEST = SCRIPT_DIR / "manifest.json"
DEFAULT_STAGING = SCRIPT_DIR / "staging"

try:
    from PIL import Image

    PIL_AVAILABLE = True
except ImportError:  # pragma: no cover - exercised only when Pillow is missing
    Image = None  # type: ignore[assignment]
    PIL_AVAILABLE = False


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"manifest not found: {path}")
    with path.open() as f:
        data = json.load(f)
    return {a["id"]: a for a in data["assets"]}


def load_report(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"report not found: {path} -- run generate.py first")
    with path.open() as f:
        return json.load(f).get("results", {})


def copy_asset(staged_path: Path, dest_path: Path, *, dry_run: bool) -> None:
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if dry_run:
        return
    if staged_path.suffix.lower() == dest_path.suffix.lower() or not PIL_AVAILABLE:
        shutil.copy2(staged_path, dest_path)
    else:
        # Extensions differ (e.g. staged .jpg promoted to a .png destination) --
        # re-save through PIL so the destination is a valid file of its own format.
        img = Image.open(staged_path)
        img.save(dest_path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--staging-dir", type=Path, default=DEFAULT_STAGING)
    parser.add_argument("--only", type=str, default=None, help="comma-separated asset ids")
    parser.add_argument(
        "--all-passed", action="store_true", help="promote every asset whose QA passed"
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=REPO_ROOT,
        help="repo root that asset 'output' paths are relative to",
    )
    parser.add_argument("--dry-run", action="store_true", help="print what would be promoted")
    args = parser.parse_args(argv)

    if not args.only and not args.all_passed:
        raise SystemExit("specify --all-passed and/or --only id1,id2")

    assets_by_id = load_manifest(args.manifest)
    report = load_report(args.staging_dir / "report.json")

    only_ids = set(args.only.split(",")) if args.only else set()

    to_promote: list[str] = []
    for asset_id, record in report.items():
        if asset_id in only_ids:
            to_promote.append(asset_id)
        elif args.all_passed and record.get("qa", {}).get("pass"):
            to_promote.append(asset_id)

    unknown_only = only_ids - report.keys()
    if unknown_only:
        print(f"[warn] --only id(s) not found in report.json, skipping: {sorted(unknown_only)}")

    if not to_promote:
        print("nothing to promote")
        return 0

    promoted = 0
    for asset_id in to_promote:
        record = report[asset_id]
        asset = assets_by_id.get(asset_id)
        if asset is None:
            print(f"[warn] {asset_id}: not in manifest, skipping")
            continue

        staged_path = Path(record["staged_path"])
        if not staged_path.exists():
            print(f"[warn] {asset_id}: staged file missing ({staged_path}), skipping")
            continue

        dest_path = args.repo_root / asset["output"]
        qa_pass = record.get("qa", {}).get("pass")
        flag = "" if qa_pass else "  [QA FLAGGED -- promoting anyway]"
        print(f"{asset_id}: {staged_path} -> {dest_path}{flag}")

        copy_asset(staged_path, dest_path, dry_run=args.dry_run)
        promoted += 1

    verb = "would promote" if args.dry_run else "promoted"
    print(f"\n{verb} {promoted}/{len(to_promote)} asset(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
