#!/usr/bin/env bash
# Validate manifest.json schema (v2.1) and optional release readiness.
#
# Usage:
#   verify-manifest.sh [--strict] [manifest.json]
#
# --strict additionally requires catalog_tag, published_at, non-placeholder
# artifact urls/checksums, catalog_tag embedded in download urls, composer
# version aligned with builds/common/composer-version.txt, and profile
# extensions that exist in the runtime catalog set.
set -euo pipefail

STRICT=0
MANIFEST="manifest.json"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSIONS_JSON="${ROOT}/builds/common/extensions.json"
COMPOSER_PIN="${ROOT}/builds/common/composer-version.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--strict] [manifest.json]"
      exit 0
      ;;
    *)
      MANIFEST="$1"
      shift
      ;;
  esac
done

if [[ ! -f "${MANIFEST}" ]]; then
  echo "error: manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

TARGETS=(
  "x86_64-unknown-linux-gnu"
  "aarch64-apple-darwin"
)

fail() {
  echo "error: $*" >&2
  exit 1
}

SCHEMA="$(jq -r '.schema // empty' "${MANIFEST}")"
[[ "${SCHEMA}" == "2.1" ]] || fail "schema must be 2.1 (got '${SCHEMA}')"

RUNTIME_COUNT="$(jq '.runtimes | length' "${MANIFEST}")"
[[ "${RUNTIME_COUNT}" -eq 4 ]] || fail "expected exactly 4 runtimes, got ${RUNTIME_COUNT}"

EXPECTED_EXTENSIONS=""
if [[ -f "${EXTENSIONS_JSON}" ]]; then
  EXPECTED_EXTENSIONS="$(jq -r '.catalog | sort | @tsv' "${EXTENSIONS_JSON}")"
fi

EXPECTED_COMPOSER=""
if [[ -f "${COMPOSER_PIN}" ]]; then
  EXPECTED_COMPOSER="$(tr -d '[:space:]' < "${COMPOSER_PIN}")"
fi

if [[ "${STRICT}" -eq 1 ]]; then
  TAG="$(jq -r '.catalog_tag // empty' "${MANIFEST}")"
  [[ -n "${TAG}" && "${TAG}" != "null" ]] || fail "--strict: catalog_tag must be set"
  PUBLISHED="$(jq -r '.published_at // empty' "${MANIFEST}")"
  [[ -n "${PUBLISHED}" && "${PUBLISHED}" != "null" ]] || fail "--strict: published_at must be set"
fi

# Track minor lines — one runtime per major.minor.
declare -A SEEN_MINOR=()

while IFS= read -r entry; do
  PHP="$(jq -r '.php' <<<"${entry}")"
  COMPOSER="$(jq -r '.composer' <<<"${entry}")"
  EXT_COUNT="$(jq '.extensions | length' <<<"${entry}")"

  [[ -n "${PHP}" ]] || fail "runtime has empty php version"
  [[ -n "${COMPOSER}" ]] || fail "runtime ${PHP} has empty composer version"
  if [[ -n "${EXPECTED_COMPOSER}" && "${COMPOSER}" != "${EXPECTED_COMPOSER}" ]]; then
    fail "runtime ${PHP} composer ${COMPOSER} does not match ${COMPOSER_PIN} (${EXPECTED_COMPOSER})"
  fi
  [[ "${EXT_COUNT}" -gt 0 ]] || fail "runtime ${PHP} has empty extensions list"

  if [[ -n "${EXPECTED_EXTENSIONS}" ]]; then
    RUNTIME_EXTENSIONS="$(jq -r '.extensions | sort | @tsv' <<<"${entry}")"
    if [[ "${RUNTIME_EXTENSIONS}" != "${EXPECTED_EXTENSIONS}" ]]; then
      fail "runtime ${PHP} extensions do not match builds/common/extensions.json catalog"
    fi
  fi

  if [[ ! "${PHP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "runtime ${PHP} is not MAJOR.MINOR.PATCH"
  fi

  MINOR="${PHP%.*}"
  if [[ -n "${SEEN_MINOR[${MINOR}]:-}" ]]; then
    fail "duplicate minor line ${MINOR} (${SEEN_MINOR[${MINOR}]} and ${PHP})"
  fi
  SEEN_MINOR["${MINOR}"]="${PHP}"

  for target in "${TARGETS[@]}"; do
    URL="$(jq -r --arg t "${target}" '.artifacts[$t].url // empty' <<<"${entry}")"
    SHA="$(jq -r --arg t "${target}" '.artifacts[$t].sha256 // empty' <<<"${entry}")"

    [[ -n "${URL}" ]] || fail "runtime ${PHP} missing artifacts.${target}.url"
    [[ -n "${SHA}" ]] || fail "runtime ${PHP} missing artifacts.${target}.sha256"

    [[ "${URL}" == https://* ]] || fail "runtime ${PHP} ${target} url must be https://"

    if [[ "${STRICT}" -eq 1 ]]; then
      [[ "${URL}" != *PLACEHOLDER* ]] || fail "runtime ${PHP} ${target} url still has PLACEHOLDER"
      [[ "${SHA}" != "0000000000000000000000000000000000000000000000000000000000000000" ]] \
        || fail "runtime ${PHP} ${target} sha256 is still zero placeholder"
    fi

    if [[ ! "${SHA}" =~ ^[0-9a-fA-F]{64}$ ]]; then
      fail "runtime ${PHP} ${target} sha256 must be 64 hex chars"
    fi

    EXPECTED_NAME="php-${PHP}-${target}.tar.gz"
    if [[ "${STRICT}" -eq 1 && "${URL}" != *"/${EXPECTED_NAME}" ]]; then
      fail "runtime ${PHP} ${target} url must end with /${EXPECTED_NAME}"
    fi

    if [[ "${STRICT}" -eq 1 ]]; then
      [[ "${URL}" == *"/releases/download/${TAG}/"* ]] \
        || fail "runtime ${PHP} ${target} url must use catalog_tag ${TAG}"
    fi
  done
done < <(jq -c '.runtimes[]' "${MANIFEST}")

# Profile names must be non-empty; profile extensions must exist in the catalog runtime set.
CATALOG_EXTENSIONS="$(jq -r '.runtimes[0].extensions[]' "${MANIFEST}")"
while IFS= read -r profile; do
  PROFILE_NAME="$(jq -r '.name' <<<"${profile}")"
  [[ -n "${PROFILE_NAME}" ]] || fail "profile has empty name"

  while IFS= read -r ext; do
    [[ -n "${ext}" ]] || continue
    if ! grep -Fxq "${ext}" <<<"${CATALOG_EXTENSIONS}"; then
      fail "profile ${PROFILE_NAME} extension '${ext}' is not in runtime catalog extensions"
    fi
  done < <(jq -r '.extensions[]?' <<<"${profile}")
done < <(jq -c '.profiles[]' "${MANIFEST}")

echo "manifest OK: ${MANIFEST} (${RUNTIME_COUNT} runtimes, schema ${SCHEMA})"
if [[ "${STRICT}" -eq 1 ]]; then
  echo "strict checks passed (ready to publish)"
fi
