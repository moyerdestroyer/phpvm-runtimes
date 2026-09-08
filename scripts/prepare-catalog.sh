#!/usr/bin/env bash
# Prepare a complete catalog from release tarballs in dist/.
#
# Usage:
#   prepare-catalog.sh --catalog-tag catalog-YYYY-MM-DD [options]
#
# Options:
#   --assets-dir DIR       Directory containing current tarballs (default: dist)
#   --reuse-dir DIR        Copy any missing tarballs from a previous catalog dir
#   --github-repo OWNER/REPO
#   --manifest FILE        Manifest to update (default: manifest.json)
#   --published-at TIME    ISO-8601 timestamp for manifest
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  prepare-catalog.sh --catalog-tag catalog-YYYY-MM-DD [options]

Options:
  --assets-dir DIR       Directory containing current tarballs (default: dist)
  --reuse-dir DIR        Copy any missing tarballs from a previous catalog dir
  --github-repo OWNER/REPO
  --manifest FILE        Manifest to update (default: manifest.json)
  --published-at TIME    ISO-8601 timestamp for manifest
EOF
  exit "${1:-1}"
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT}/dist"
REUSE_DIR=""
GITHUB_REPO=""
MANIFEST="${ROOT}/manifest.json"
CATALOG_TAG=""
PUBLISHED_AT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assets-dir)
      [[ $# -ge 2 ]] || usage
      ASSETS_DIR="$2"
      shift 2
      ;;
    --reuse-dir)
      [[ $# -ge 2 ]] || usage
      REUSE_DIR="$2"
      shift 2
      ;;
    --github-repo)
      [[ $# -ge 2 ]] || usage
      GITHUB_REPO="$2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || usage
      MANIFEST="$2"
      shift 2
      ;;
    --catalog-tag)
      [[ $# -ge 2 ]] || usage
      CATALOG_TAG="$2"
      shift 2
      ;;
    --published-at)
      [[ $# -ge 2 ]] || usage
      PUBLISHED_AT="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

[[ -n "${CATALOG_TAG}" ]] || {
  echo "error: --catalog-tag is required" >&2
  usage
}

if [[ -z "${GITHUB_REPO}" ]]; then
  GITHUB_REPO="$(git -C "${ROOT}" remote get-url origin 2>/dev/null \
    | sed -E 's#.*github.com[:/]##; s#\.git$##' || true)"
fi
[[ -n "${GITHUB_REPO}" ]] || {
  echo "error: could not derive OWNER/REPO from the origin git remote" >&2
  echo "pass --github-repo explicitly" >&2
  exit 1
}

[[ -f "${MANIFEST}" ]] || {
  echo "error: manifest not found: ${MANIFEST}" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

mkdir -p "${ASSETS_DIR}"

"${ROOT}/scripts/render-craft.sh" --all

if [[ -n "${REUSE_DIR}" ]]; then
  [[ -d "${REUSE_DIR}" ]] || {
    echo "error: reuse dir not found: ${REUSE_DIR}" >&2
    exit 1
  }

  while IFS= read -r archive; do
    if [[ ! -f "${ASSETS_DIR}/${archive}" && -f "${REUSE_DIR}/${archive}" ]]; then
      cp "${REUSE_DIR}/${archive}" "${ASSETS_DIR}/${archive}"
      echo "reused ${archive}"
    fi

    sidecar="${archive}.sha256"
    if [[ ! -f "${ASSETS_DIR}/${sidecar}" && -f "${REUSE_DIR}/${sidecar}" ]]; then
      cp "${REUSE_DIR}/${sidecar}" "${ASSETS_DIR}/${sidecar}"
      echo "reused ${sidecar}"
    fi
  done < <(
    jq -r '
      .runtimes[].php as $php
      | ["x86_64-unknown-linux-gnu", "aarch64-apple-darwin"][]
      | "php-\($php)-\(.)" + ".tar.gz"
    ' "${MANIFEST}"
  )
fi

"${ROOT}/scripts/verify-catalog-assets.sh" "${ASSETS_DIR}" "${MANIFEST}"

UPDATE_ARGS=(
  "${ROOT}/scripts/update-manifest.py"
  --manifest "${MANIFEST}"
  --assets-dir "${ASSETS_DIR}"
  --catalog-tag "${CATALOG_TAG}"
  --github-repo "${GITHUB_REPO}"
)

if [[ -n "${PUBLISHED_AT}" ]]; then
  UPDATE_ARGS+=(--published-at "${PUBLISHED_AT}")
fi

python3 "${UPDATE_ARGS[@]}"
"${ROOT}/scripts/verify-manifest-assets.sh" "${ASSETS_DIR}" "${MANIFEST}"
"${ROOT}/scripts/verify-manifest.sh" --strict "${MANIFEST}"

echo "catalog ready: ${CATALOG_TAG}"
