#!/usr/bin/env bash
# Ensure dist/ contains every tarball required by manifest.json (4 versions × 2 targets).
#
# Usage:
#   verify-catalog-assets.sh [assets-dir] [manifest.json]
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

MISSING=()
EXPECTED=0

while IFS= read -r php; do
  for target in "${TARGETS[@]}"; do
    EXPECTED=$((EXPECTED + 1))
    name="php-${php}-${target}.tar.gz"
    if [[ ! -f "${ASSETS_DIR}/${name}" ]]; then
      MISSING+=("${name}")
    fi
  done
done < <(jq -r '.runtimes[].php' "${MANIFEST}")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "error: missing ${#MISSING[@]} of ${EXPECTED} catalog tarballs in ${ASSETS_DIR}:" >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

echo "catalog assets OK: ${EXPECTED} tarballs present in ${ASSETS_DIR}"
