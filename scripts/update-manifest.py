#!/usr/bin/env python3
"""Inject release URLs, SHA-256 checksums, and runtime metadata into manifest.json."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tarfile
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

TARGETS = (
    "x86_64-unknown-linux-gnu",
    "aarch64-apple-darwin",
)

ZEND_EXTENSIONS = frozenset({"opcache", "xdebug"})
DEFAULT_PROFILE = "dev"
MINIMAL_EXTENSIONS = ["openssl", "phar", "mbstring"]
DEV_EXTENSIONS = [
    "openssl",
    "phar",
    "mbstring",
    "curl",
    "dom",
    "fileinfo",
    "gd",
    "intl",
    "mysqli",
    "pdo",
    "pdo_mysql",
    "pdo_sqlite",
    "session",
    "simplexml",
    "sockets",
    "sqlite3",
    "tokenizer",
    "xml",
    "xmlreader",
    "xmlwriter",
    "zip",
    "zlib",
]
PROFILES = [
    {"name": "minimal", "extensions": MINIMAL_EXTENSIONS},
    {"name": "dev", "extensions": DEV_EXTENSIONS},
    {"name": "debug", "extensions": DEV_EXTENSIONS, "zend_extensions": ["xdebug"]},
]
DEFAULT_EXTENSIONS = frozenset(DEV_EXTENSIONS)
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


def inspect_dynamic_archive(archive: Path) -> tuple[dict, list[dict]]:
    with TemporaryDirectory() as tmp:
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(tmp, filter="data")

        root = next(Path(tmp).iterdir())
        metadata_path = root / "metadata" / "runtime.json"
        profiles_path = root / "etc" / "profiles" / "profiles.json"
        ext_dir = root / "ext"
        if not metadata_path.is_file() or not ext_dir.is_dir():
            raise ValueError(f"{archive.name} is not a dynamic runtime bundle")

        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if profiles_path.is_file():
            metadata["profiles"] = json.loads(profiles_path.read_text(encoding="utf-8"))
        extensions: list[dict] = []
        for ext_file in sorted(ext_dir.glob("*.so")) + sorted(ext_dir.glob("*.dylib")):
            name = ext_file.stem
            ext_type = "zend_extension" if name in ZEND_EXTENSIONS else "extension"
            extensions.append(
                {
                    "name": name,
                    "type": ext_type,
                    "bundled": True,
                    "default": name in DEFAULT_EXTENSIONS,
                    "file": f"ext/{ext_file.name}",
                }
            )

        if not extensions:
            raise ValueError(f"{archive.name} has no loadable extensions")

        return metadata, extensions


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
    manifest["catalog_tag"] = args.catalog_tag
    manifest["published_at"] = args.published_at or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    manifest["default_profile"] = DEFAULT_PROFILE
    manifest["profiles"] = PROFILES

    runtimes = manifest.get("runtimes", [])
    expected = len(runtimes) * len(TARGETS)
    updated = 0
    dynamic = False

    for runtime in runtimes:
        php = runtime.get("php", "")
        if not php:
            print("error: runtime row missing php version", file=sys.stderr)
            return 1

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

        linux_archive = assets.get((php, "x86_64-unknown-linux-gnu"))
        if linux_archive is None:
            print(
                f"error: missing Linux tarball for runtime metadata: {php}",
                file=sys.stderr,
            )
            return 1

        try:
            metadata, extensions = inspect_dynamic_archive(linux_archive)
        except ValueError as exc:
            runtime["runtime_type"] = "static"
            runtime["extensions"] = runtime.get("extensions", [])
            continue

        dynamic = True
        runtime["runtime_type"] = metadata.get("runtime_type", "dynamic")
        runtime["thread_safety"] = metadata.get("thread_safety", "nts")
        runtime["abi"] = metadata["abi"]
        runtime["extension_api"] = metadata["extension_api"]
        runtime["zend_extension_api"] = metadata["zend_extension_api"]
        runtime["default_profile"] = metadata.get("default_profile", DEFAULT_PROFILE)
        if "linux_compatibility" in metadata:
            runtime["linux_compatibility"] = metadata["linux_compatibility"]
        runtime["extensions"] = extensions
        print(f"updated {php} runtime metadata from {linux_archive.name}")

    manifest["schema"] = "3.0" if dynamic else "2.1"

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
            f"wrote {args.manifest} ({updated} artifacts, schema {manifest['schema']})"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
