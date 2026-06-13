#!/usr/bin/env bash
# Verify on-disk tarballs match manifest.json artifact sha256 values.
#
# Usage:
#   verify-manifest-assets.sh [assets-dir] [manifest.json]
set -euo pipefail

ASSETS_DIR="${1:-dist}"
MANIFEST="${2:-manifest.json}"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "error: manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if [[ ! -d "${ASSETS_DIR}" ]]; then
  echo "error: assets dir not found: ${ASSETS_DIR}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

TARGETS=(
  x86_64-unknown-linux-gnu
  aarch64-apple-darwin
)

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  else
    shasum -a 256 "${path}" | awk '{print $1}'
  fi
}

MISMATCH=()
MISSING=()
CHECKED=0

while IFS= read -r entry; do
  PHP="$(jq -r '.php' <<<"${entry}")"
  for target in "${TARGETS[@]}"; do
    CHECKED=$((CHECKED + 1))
    name="php-${PHP}-${target}.tar.gz"
    path="${ASSETS_DIR}/${name}"
    expected="$(jq -r --arg t "${target}" '.artifacts[$t].sha256 // empty' <<<"${entry}")"

    if [[ ! -f "${path}" ]]; then
      MISSING+=("${name}")
      continue
    fi

    if [[ ! "${expected}" =~ ^[0-9a-fA-F]{64}$ ]]; then
      MISMATCH+=("${name} (manifest sha256 missing or invalid)")
      continue
    fi

    actual="$(sha256_file "${path}")"
    if [[ "${actual,,}" != "${expected,,}" ]]; then
      MISMATCH+=("${name} (manifest ${expected} != file ${actual})")
    fi
  done
done < <(jq -c '.runtimes[]' "${MANIFEST}")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "error: missing ${#MISSING[@]} tarball(s) in ${ASSETS_DIR}:" >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

if [[ ${#MISMATCH[@]} -gt 0 ]]; then
  echo "error: ${#MISMATCH[@]} tarball checksum(s) do not match ${MANIFEST}:" >&2
  printf '  - %s\n' "${MISMATCH[@]}" >&2
  exit 1
fi

echo "manifest assets OK: ${CHECKED} tarball checksums match ${MANIFEST}"
