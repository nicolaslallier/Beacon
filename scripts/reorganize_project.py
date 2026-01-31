#!/usr/bin/env python3
"""
Reorganize project files into infra/applications/config/docs folders.

Default is dry-run. Use --apply to perform moves.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path


MOVE_MAP = {
    "applications": [
        "Library",
    ],
    "infra": [
        "docker-compose.yml",
        "Dockerfile",
        "monitoring",
        "traefik",
        "certbot",
        "ca",
        "certs",
        "templates",
        "conf.d",
        "html",
    ],
    "config": [
        ".env",
        ".hadolint.yaml",
        ".dockerignore",
        ".vscode",
        "makefiles",
        "Makefile",
    ],
    "docs": [
        "KEYCLOAK_SETUP.md",
        "PRIVATE_CA.md",
    ],
}

EXTRA_MOVES = [
    # Move Library observability into infra
    ("applications/Library/observability", "infra/observability"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Reorganize project folders.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform the moves. Without this, runs in dry-run mode.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Project root path (defaults to repo root).",
    )
    return parser.parse_args()


def ensure_dir(path: Path, dry_run: bool) -> None:
    if path.exists():
        return
    if dry_run:
        print(f"[dry-run] mkdir -p {path}")
        return
    path.mkdir(parents=True, exist_ok=True)


def move_item(src: Path, dest: Path, dry_run: bool) -> None:
    if not src.exists():
        print(f"[skip] missing: {src}")
        return
    if dest.exists():
        print(f"[skip] exists: {dest}")
        return
    if dry_run:
        print(f"[dry-run] mv {src} {dest}")
        return
    shutil.move(str(src), str(dest))
    print(f"[moved] {src} -> {dest}")


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    dry_run = not args.apply

    for target_dir, items in MOVE_MAP.items():
        target_path = root / target_dir
        ensure_dir(target_path, dry_run=dry_run)
        for item in items:
            src = root / item
            dest = target_path / item
            move_item(src, dest, dry_run=dry_run)

    for src_rel, dest_rel in EXTRA_MOVES:
        src = root / src_rel
        dest = root / dest_rel
        ensure_dir(dest.parent, dry_run=dry_run)
        move_item(src, dest, dry_run=dry_run)

    print("Done.")
    if dry_run:
        print("No changes made. Re-run with --apply to perform moves.")


if __name__ == "__main__":
    main()
