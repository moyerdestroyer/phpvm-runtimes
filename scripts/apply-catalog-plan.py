#!/usr/bin/env python3
"""Apply a catalog plan to manifest.json with placeholder artifacts.

This updates the runtime rows to the planned PHP versions before tarballs are
built and before scripts/update-manifest.py injects release URLs and checksums.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any

TARGETS = (
    "x86_64-unknown-linux-gnu",
    "aarch64-apple-darwin",
)

DEFAULT_PROFILE = "dev"
ZERO_SHA256 = "0" * 64


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def minor_of(version: str) -> str:
    return ".".join(version.split(".")[:2])


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON in {path}: {exc}") from exc


def load_composer(root: Path) -> str:
    path = root / "builds" / "common" / "composer-version.txt"
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError as exc:
        raise RuntimeError(f"composer pin not found: {path}") from exc


def load_extensions(root: Path) -> dict[str, Any]:
    path = root / "builds" / "common" / "extensions.json"
    data = load_json(path)
    for key in ("catalog", "dev_profile", "minimal_profile"):
        if key not in data or not isinstance(data[key], list):
            raise RuntimeError(f"{path} missing array field {key}")
    return data


def build_profiles(ext_json: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {"name": "minimal", "extensions": ext_json["minimal_profile"]},
        {"name": "dev", "extensions": ext_json["dev_profile"]},
        {"name": "debug", "extensions": ext_json["catalog"]},
    ]


def placeholder_artifacts(version: str, github_repo: str) -> dict[str, dict[str, str]]:
    return {
        target: {
            "url": (
                f"https://github.com/{github_repo}/releases/download/"
                f"PLACEHOLDER/php-{version}-{target}.tar.gz"
            ),
            "sha256": ZERO_SHA256,
        }
        for target in TARGETS
    }


def runtime_template(
    version: str,
    existing: dict[str, dict[str, Any]],
    fallback: dict[str, Any],
    composer: str,
    extensions: list[str],
    github_repo: str,
) -> dict[str, Any]:
    base = existing.get(minor_of(version), fallback)
    runtime = copy.deepcopy(base)
    runtime["php"] = version
    runtime["composer"] = composer
    runtime["extensions"] = list(extensions)
    runtime["artifacts"] = placeholder_artifacts(version, github_repo)
    runtime["runtime_type"] = "static"
    runtime["thread_safety"] = "nts"
    runtime["default_profile"] = DEFAULT_PROFILE
    for stale in ("abi", "extension_api", "zend_extension_api", "linux_compatibility"):
        runtime.pop(stale, None)
    return runtime


def apply_plan(
    manifest: dict[str, Any],
    plan: dict[str, Any],
    ext_json: dict[str, Any],
    composer: str,
    github_repo: str,
) -> dict[str, Any]:
    desired = plan.get("desired_versions")
    if not isinstance(desired, list) or not desired:
        raise RuntimeError("plan missing desired_versions")

    runtimes = manifest.get("runtimes")
    if not isinstance(runtimes, list) or not runtimes:
        raise RuntimeError("manifest missing runtimes")

    existing_by_minor = {
        minor_of(str(runtime.get("php", ""))): runtime
        for runtime in runtimes
        if isinstance(runtime, dict) and isinstance(runtime.get("php"), str)
    }
    fallback = copy.deepcopy(runtimes[-1])

    manifest = copy.deepcopy(manifest)
    manifest["schema"] = "2.1"
    manifest["default_profile"] = DEFAULT_PROFILE
    manifest["profiles"] = build_profiles(ext_json)
    manifest["runtimes"] = [
        runtime_template(
            str(version),
            existing_by_minor,
            fallback,
            composer,
            ext_json["catalog"],
            github_repo,
        )
        for version in sorted((str(item) for item in desired), key=version_key)
    ]
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("manifest.json"),
        help="Path to manifest.json (default: manifest.json)",
    )
    parser.add_argument(
        "--plan",
        type=Path,
        required=True,
        help="Catalog plan JSON from scripts/plan-catalog-update.py",
    )
    parser.add_argument(
        "--github-repo",
        default="moyerdestroyer/phpvm-runtimes",
        help="GitHub owner/repo for placeholder URLs",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print updated manifest without writing it",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent

    try:
        manifest = load_json(args.manifest)
        plan = load_json(args.plan)
        ext_json = load_extensions(root)
        composer = load_composer(root)
        updated = apply_plan(manifest, plan, ext_json, composer, args.github_repo)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    output = json.dumps(updated, indent=2, ensure_ascii=False) + "\n"
    if args.dry_run:
        print(output, end="")
    else:
        args.manifest.write_text(output, encoding="utf-8")
        print(
            f"wrote {args.manifest} ({len(updated['runtimes'])} runtimes from {args.plan})"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
