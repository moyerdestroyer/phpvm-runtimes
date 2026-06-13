#!/usr/bin/env python3
"""Inject release URLs and SHA-256 checksums into manifest.json."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

TARGETS = (
    "x86_64-unknown-linux-gnu",
    "aarch64-apple-darwin",
)

PLACEHOLDER_SHA = "0" * 64
ARCHIVE_RE = re.compile(r"^php-(?P<version>\d+\.\d+\.\d+)-(?P<target>.+)\.tar\.gz$")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def discover_assets(assets_dir: Path) -> dict[tuple[str, str], Path]:
    found: dict[tuple[str, str], Path] = {}
    for path in sorted(assets_dir.glob("php-*.tar.gz")):
        match = ARCHIVE_RE.match(path.name)
        if not match:
            continue
        key = (match.group("version"), match.group("target"))
        found[key] = path
    return found


def release_url(github_repo: str, catalog_tag: str, filename: str) -> str:
    return (
        f"https://github.com/{github_repo}/releases/download/"
        f"{catalog_tag}/{filename}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("manifest.json"),
        help="Path to manifest.json (default: manifest.json)",
    )
    parser.add_argument(
        "--assets-dir",
        type=Path,
        required=True,
        help="Directory containing php-{version}-{target}.tar.gz files",
    )
    parser.add_argument(
        "--catalog-tag",
        required=True,
        help="GitHub release tag (e.g. catalog-2026-06-13)",
    )
    parser.add_argument(
        "--github-repo",
        default="moyerdestroyer/phpvm-runtimes",
        help="GitHub owner/repo for download URLs",
    )
    parser.add_argument(
        "--published-at",
        help="ISO-8601 timestamp (default: now UTC)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print changes without writing manifest.json",
    )
    args = parser.parse_args()

    if not args.manifest.is_file():
        print(f"error: manifest not found: {args.manifest}", file=sys.stderr)
        return 1
    if not args.assets_dir.is_dir():
        print(f"error: assets dir not found: {args.assets_dir}", file=sys.stderr)
        return 1

    assets = discover_assets(args.assets_dir)
    if not assets:
        print(f"error: no php-*.tar.gz files in {args.assets_dir}", file=sys.stderr)
        return 1

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    manifest["schema"] = "2.1"
    manifest["catalog_tag"] = args.catalog_tag
    manifest["published_at"] = args.published_at or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    updated = 0
    for runtime in manifest.get("runtimes", []):
        php = runtime.get("php", "")
        artifacts = runtime.setdefault("artifacts", {})
        for target in TARGETS:
            key = (php, target)
            if key not in assets:
                continue
            archive = assets[key]
            filename = archive.name
            artifacts[target] = {
                "url": release_url(args.github_repo, args.catalog_tag, filename),
                "sha256": sha256_file(archive),
            }
            updated += 1
            print(f"updated {php} / {target} <- {archive.name}")

    if updated == 0:
        print("error: no manifest rows matched assets", file=sys.stderr)
        return 1

    output = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if args.dry_run:
        print(output)
    else:
        args.manifest.write_text(output, encoding="utf-8")
        print(f"wrote {args.manifest} ({updated} artifacts)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
