#!/usr/bin/env python3
"""(Legacy) Write profile/compat/license metadata for dynamic runtimes.

Static catalogs (v2.1) are the supported path; profiles for dev are still
injected by update-manifest.py from its DEV_EXTENSIONS list.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

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

GLIBC_RE = re.compile(r"\bGLIBC_(\d+(?:\.\d+)+)\b")


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=check, text=True, capture_output=True)


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def runtime_objects(staging: Path) -> list[Path]:
    objects: list[Path] = []
    php = staging / "bin" / "php"
    if php.exists():
        objects.append(php)
    for directory in ("ext", "lib"):
        root = staging / directory
        if not root.is_dir():
            continue
        for path in sorted(root.iterdir()):
            if path.is_file() and (
                path.name.endswith(".so")
                or ".so." in path.name
                or path.name.endswith(".dylib")
            ):
                objects.append(path)
    return objects


def builder_glibc_version() -> str | None:
    if shutil.which("ldd") is None:
        return None
    proc = run(["ldd", "--version"], check=False)
    if proc.returncode != 0:
        return None
    first = proc.stdout.splitlines()[0] if proc.stdout.splitlines() else ""
    match = re.search(r"(\d+\.\d+)", first)
    return match.group(1) if match else None


def required_glibc_version(objects: list[Path]) -> str | None:
    if shutil.which("readelf") is None:
        return None
    versions: set[str] = set()
    for path in objects:
        proc = run(["readelf", "--version-info", str(path)], check=False)
        if proc.returncode != 0:
            continue
        versions.update(GLIBC_RE.findall(proc.stdout))
    if not versions:
        return None
    return max(versions, key=version_key)


def package_for_path(path: Path) -> str | None:
    if shutil.which("dpkg-query") is None:
        return None

    candidates = [path]
    try:
        candidates.append(path.resolve())
    except OSError:
        pass
    path_text = str(path)
    if path_text.startswith("/lib/"):
        candidates.append(Path("/usr") / path_text.lstrip("/"))

    for candidate in candidates:
        proc = run(["dpkg-query", "-S", str(candidate)], check=False)
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.split(":", 1)[0].strip()
    return None


def ldconfig_path(name: str) -> Path | None:
    if shutil.which("ldconfig") is None:
        return None
    proc = run(["ldconfig", "-p"], check=False)
    if proc.returncode != 0:
        return None
    for line in proc.stdout.splitlines():
        fields = line.split()
        if fields and fields[0] == name and "=>" in fields:
            return Path(fields[-1])
    return None


def license_path_for_package(package: str) -> Path | None:
    package_name = package.split(":", 1)[0]
    path = Path("/usr/share/doc") / package_name / "copyright"
    return path if path.is_file() else None


def source_package_for_binary(package: str) -> str:
    package_name = package.split(":", 1)[0]
    if shutil.which("dpkg-query") is None:
        return package_name
    proc = run(["dpkg-query", "-s", package_name], check=False)
    if proc.returncode != 0:
        return package_name
    for line in proc.stdout.splitlines():
        if line.startswith("Source: "):
            source = line.split(": ", 1)[1].strip()
            return source.split(" ", 1)[0]
    return package_name


def copy_license(staging: Path, package: str, source: Path) -> str:
    package_name = package.split(":", 1)[0]
    dest = staging / "licenses" / package_name / "copyright"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)
    return str(dest.relative_to(staging))


def generate_bundled_libs(staging: Path, strict: bool) -> list[dict[str, str]]:
    lib_dir = staging / "lib"
    if not lib_dir.is_dir():
        return []

    entries: list[dict[str, str]] = []
    failures: list[str] = []
    for lib in sorted(path for path in lib_dir.iterdir() if path.is_file()):
        system_path = ldconfig_path(lib.name)
        package = package_for_path(system_path) if system_path else None
        license_source = license_path_for_package(package) if package else None

        entry = {
            "file": f"lib/{lib.name}",
            "soname": lib.name,
        }
        if system_path:
            entry["system_path"] = str(system_path)
        if package:
            entry["binary_package"] = package
            entry["source_package"] = source_package_for_binary(package)
        if license_source:
            entry["license_file"] = copy_license(staging, package, license_source)
        entries.append(entry)

        if strict and (system_path is None or package is None or license_source is None):
            failures.append(lib.name)

    if failures:
        joined = ", ".join(failures)
        raise RuntimeError(f"missing package/license metadata for bundled libs: {joined}")

    return entries


def write_notices(staging: Path, libs: list[dict[str, str]]) -> None:
    lines = [
        "Third-party notices",
        "===================",
        "",
        "This runtime bundles third-party shared libraries in lib/.",
        "License notice files copied from the build system are listed below.",
        "",
    ]
    for entry in libs:
        package = entry.get("binary_package", "unknown")
        notice = entry.get("license_file", "missing")
        lines.append(f"- {entry['file']}: {package}; notice: {notice}")
    (staging / "THIRD_PARTY_NOTICES").write_text("\n".join(lines) + "\n", encoding="utf-8")


def validate_profiles(staging: Path) -> None:
    ext_dir = staging / "ext"
    available = {path.stem for path in ext_dir.glob("*.so")}
    available.update(path.stem for path in ext_dir.glob("*.dylib"))

    missing: list[str] = []
    for profile in PROFILES:
        for key in ("extensions", "zend_extensions"):
            for name in profile.get(key, []):
                if name not in available:
                    missing.append(f"{profile['name']}:{name}")
    if missing:
        raise RuntimeError("profile references missing extensions: " + ", ".join(missing))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging", type=Path)
    parser.add_argument("--strict-licenses", action="store_true")
    args = parser.parse_args()

    staging = args.staging.resolve()
    runtime_path = staging / "metadata" / "runtime.json"
    if not runtime_path.is_file():
        print(f"error: missing runtime metadata: {runtime_path}", file=sys.stderr)
        return 1

    try:
        validate_profiles(staging)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    profile_data = {"default_profile": DEFAULT_PROFILE, "profiles": PROFILES}
    write_json(staging / "etc" / "profiles" / "profiles.json", profile_data)

    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    runtime["default_profile"] = DEFAULT_PROFILE

    if os.uname().sysname == "Linux":
        objects = runtime_objects(staging)
        runtime["linux_compatibility"] = {
            "builder_glibc": builder_glibc_version(),
            "required_glibc": required_glibc_version(objects),
        }
        try:
            libs = generate_bundled_libs(staging, args.strict_licenses)
        except RuntimeError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        write_json(staging / "metadata" / "bundled-libs.json", libs)
        write_notices(staging, libs)

    write_json(runtime_path, runtime)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
