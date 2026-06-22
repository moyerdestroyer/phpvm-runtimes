#!/usr/bin/env python3
"""Inject release URLs, SHA-256 checksums, and runtime metadata into manifest.json.

Reads profile definitions from builds/common/extensions.json so that the
manifest profiles and runtime extension lists are always derived from the
single source of truth.
"""

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

ZEND_EXTENSIONS = frozenset({"opcache"})
DEFAULT_PROFILE = "dev"
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


def load_extensions_json(root: Path) -> dict:
    ext_path = root / "builds" / "common" / "extensions.json"
    if not ext_path.is_file():
        print(f"error: {ext_path} not found", file=sys.stderr)
        sys.exit(1)
    return json.loads(ext_path.read_text(encoding="utf-8"))


def build_profiles(ext_json: dict) -> list[dict]:
    """Derive all three profiles from extensions.json.

    minimal -> minimal_profile subset
    dev     -> dev_profile subset
    debug   -> entire catalog (every compiled-in extension enabled)
    """
    catalog = ext_json["catalog"]
    dev = ext_json["dev_profile"]
    minimal = ext_json["minimal_profile"]
    return [
        {"name": "minimal", "extensions": minimal},
        {"name": "dev", "extensions": dev},
        {"name": "debug", "extensions": catalog},
    ]


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

    root = Path(__file__).resolve().parent.parent

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

    ext_json = load_extensions_json(root)
    catalog_extensions = ext_json["catalog"]
    profiles = build_profiles(ext_json)

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    manifest["schema"] = "2.1"
    manifest["catalog_tag"] = args.catalog_tag
    manifest["published_at"] = args.published_at or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    manifest["default_profile"] = DEFAULT_PROFILE
    manifest["profiles"] = profiles

    runtimes = manifest.get("runtimes", [])
    expected = len(runtimes) * len(TARGETS)
    updated = 0

    for runtime in runtimes:
        php = runtime.get("php", "")
        if not php:
            print("error: runtime row missing php version", file=sys.stderr)
            return 1

        # Static runtime metadata.
        runtime["runtime_type"] = "static"
        runtime["thread_safety"] = "nts"
        runtime["default_profile"] = DEFAULT_PROFILE
        runtime["extensions"] = list(catalog_extensions)

        # Remove stale dynamic-era fields that are meaningless for static
        # musl builds (no glibc dependency; ABI fields were dynamic-inspected).
        for stale in ("abi", "extension_api", "zend_extension_api", "linux_compatibility"):
            runtime.pop(stale, None)

        artifacts = runtime.setdefault("artifacts", {})
        for target in TARGETS:
            key = (php, target)
            if key not in assets:
                print(
                    f"error: missing tarball for {php} / {target} in {args.assets_dir}",
                    file=sys.stderr,
                )
                return 1
            archive = assets[key]
            filename = archive.name
            artifacts[target] = {
                "url": release_url(args.github_repo, args.catalog_tag, filename),
                "sha256": sha256_file(archive),
            }
            updated += 1
            print(f"updated {php} / {target} <- {archive.name}")

    if updated != expected:
        print(
            f"error: updated {updated} of {expected} required artifacts",
            file=sys.stderr,
        )
        return 1

    output = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if args.dry_run:
        print(output)
    else:
        args.manifest.write_text(output, encoding="utf-8")
        print(
            f"wrote {args.manifest} ({updated} artifacts, "
            f"{len(catalog_extensions)} extensions, schema {manifest['schema']})"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
