#!/usr/bin/env python3
"""Plan the desired phpvm runtime catalog from php.net release metadata.

The output is machine-readable JSON for GitHub Actions and local dry runs.
It applies the repository policy of one latest patch per PHP minor line and a
fixed catalog size: when a new supported minor appears, the oldest minor line
is removed.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TARGETS = (
    "x86_64-unknown-linux-gnu",
    "aarch64-apple-darwin",
)

PHP_RELEASES_URL = "https://www.php.net/releases/index.php?json=1&max=20"
PHP_MINOR_RELEASES_URL = (
    "https://www.php.net/releases/index.php?json=1&max=1&version={minor}"
)


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def minor_of(version: str) -> str:
    parts = version.split(".")
    if len(parts) < 2:
        raise ValueError(f"invalid PHP version: {version}")
    return ".".join(parts[:2])


def fetch_json(url: str) -> Any:
    last_error: Exception | None = None
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(url, timeout=20) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt < 3:
                time.sleep(attempt)
    raise RuntimeError(f"failed to fetch {url}: {last_error}") from last_error


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"manifest not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"manifest is not valid JSON: {path}: {exc}") from exc


def load_release_fixture(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"release fixture not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"release fixture is not valid JSON: {path}: {exc}") from exc

    if "latest_patch" in data:
        return data

    # Also accept a lightly normalized php.net-style response for tests.
    latest_patch: dict[str, str] = {}
    supported_versions: list[str] = []
    for value in data.values():
        if not isinstance(value, dict):
            continue
        version = value.get("version")
        if isinstance(version, str) and version.count(".") == 2:
            latest_patch[minor_of(version)] = version
        supported = value.get("supported_versions")
        if isinstance(supported, list) and supported:
            supported_versions = [str(item) for item in supported]

    return {
        "supported_versions": supported_versions,
        "latest_patch": latest_patch,
    }


def current_versions(manifest: dict[str, Any]) -> list[str]:
    versions = []
    for runtime in manifest.get("runtimes", []):
        php = runtime.get("php")
        if not isinstance(php, str) or php.count(".") != 2:
            raise RuntimeError(f"manifest runtime has invalid php version: {php!r}")
        versions.append(php)
    if not versions:
        raise RuntimeError("manifest has no runtimes")
    return sorted(versions, key=version_key)


def supported_minors_from_php_net() -> list[str]:
    data = fetch_json(PHP_RELEASES_URL)
    supported: list[str] = []
    newest_supported_owner: tuple[int, ...] | None = None

    if isinstance(data, dict):
        for value in data.values():
            if not isinstance(value, dict):
                continue
            versions = value.get("supported_versions")
            if not isinstance(versions, list) or not versions:
                continue
            release_version = str(value.get("version", "0.0.0"))
            owner_key = version_key(release_version)
            if newest_supported_owner is None or owner_key > newest_supported_owner:
                newest_supported_owner = owner_key
                supported = [str(item) for item in versions]

    if not supported:
        raise RuntimeError("php.net response did not include supported_versions")

    return sorted(set(supported), key=version_key)


def latest_patch_from_php_net(minor: str) -> str:
    data = fetch_json(PHP_MINOR_RELEASES_URL.format(minor=minor))
    if not isinstance(data, dict) or not data:
        raise RuntimeError(f"php.net response did not include releases for {minor}")
    versions = [key for key in data.keys() if isinstance(key, str) and key.startswith(f"{minor}.")]
    if not versions:
        raise RuntimeError(f"php.net response did not include a {minor}.x release")
    return sorted(versions, key=version_key)[-1]


def latest_patch_for_minor(minor: str, fixture: dict[str, Any] | None) -> str:
    if fixture is not None:
        latest = fixture.get("latest_patch", {})
        if not isinstance(latest, dict) or minor not in latest:
            raise RuntimeError(f"release fixture missing latest_patch for {minor}")
        return str(latest[minor])
    return latest_patch_from_php_net(minor)


def choose_target_minors(
    current: list[str],
    supported: list[str],
    count: int,
) -> list[str]:
    current_minors = [minor_of(version) for version in current]
    if not supported:
        supported = current_minors

    # Keep only the newest supported lines, preserving the fixed manifest size.
    selected = sorted(set(supported), key=version_key)[-count:]

    if len(selected) < count:
        # This should not happen for current PHP 8 support, but keep the planner
        # deterministic if php.net returns fewer supported lines.
        missing = [
            minor
            for minor in current_minors
            if minor not in selected
        ]
        selected = sorted(set(missing + selected), key=version_key)[-count:]

    return selected


def build_plan(
    manifest: dict[str, Any],
    release_fixture: dict[str, Any] | None = None,
) -> dict[str, Any]:
    current = current_versions(manifest)
    current_by_minor = {minor_of(version): version for version in current}

    if release_fixture is not None:
        supported = [
            str(item)
            for item in release_fixture.get("supported_versions", [])
        ]
        supported = sorted(set(supported), key=version_key)
    else:
        supported = supported_minors_from_php_net()

    target_minors = choose_target_minors(current, supported, len(current))
    desired = [
        latest_patch_for_minor(minor, release_fixture)
        for minor in target_minors
    ]
    desired = sorted(desired, key=version_key)
    desired_by_minor = {minor_of(version): version for version in desired}

    added = [
        desired_by_minor[minor]
        for minor in sorted(set(desired_by_minor) - set(current_by_minor), key=version_key)
    ]
    removed = [
        current_by_minor[minor]
        for minor in sorted(set(current_by_minor) - set(desired_by_minor), key=version_key)
    ]
    updated = []
    unchanged = []
    for minor in sorted(set(current_by_minor) & set(desired_by_minor), key=version_key):
        before = current_by_minor[minor]
        after = desired_by_minor[minor]
        if before == after:
            unchanged.append(after)
        else:
            updated.append({"minor": minor, "from": before, "to": after})

    matrix = {
        "include": [
            {"php_version": php, "target": target}
            for php in desired
            for target in TARGETS
        ]
    }

    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "policy": "fixed-count-newest-supported-minors",
        "current_versions": current,
        "supported_minors": supported,
        "target_minors": target_minors,
        "desired_versions": desired,
        "added": added,
        "removed": removed,
        "updated": updated,
        "unchanged": unchanged,
        "has_update": bool(added or removed or updated),
        "matrix": matrix,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("manifest.json"),
        help="Path to manifest.json (default: manifest.json)",
    )
    parser.add_argument(
        "--releases-file",
        type=Path,
        help="Fixture JSON for tests; avoids network access",
    )
    parser.add_argument(
        "--format",
        choices=("plan", "matrix", "versions"),
        default="plan",
        help="Output format (default: plan)",
    )
    args = parser.parse_args()

    try:
        manifest = load_manifest(args.manifest)
        fixture = load_release_fixture(args.releases_file) if args.releases_file else None
        plan = build_plan(manifest, fixture)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.format == "matrix":
        output = plan["matrix"]
    elif args.format == "versions":
        output = plan["desired_versions"]
    else:
        output = plan

    print(json.dumps(output, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
