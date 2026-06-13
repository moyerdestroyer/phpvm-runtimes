#!/usr/bin/env bash
# Verify a built PHP binary exposes every catalog extension from extensions.json.
#
# Usage:
#   verify-extensions.sh <php-binary> [extensions.json]
set -euo pipefail

usage() {
  echo "Usage: $0 <php-binary> [extensions.json]" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

PHP_BIN="$1"
EXT_JSON="${2:-$(dirname "${BASH_SOURCE[0]}")/../builds/common/extensions.json}"

if [[ ! -x "${PHP_BIN}" ]]; then
  echo "error: php binary not executable: ${PHP_BIN}" >&2
  exit 1
fi

if [[ ! -f "${EXT_JSON}" ]]; then
  echo "error: extensions.json not found: ${EXT_JSON}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

MODULES="$("${PHP_BIN}" -m)"
MISSING=()

while IFS= read -r ext; do
  [[ -n "${ext}" ]] || continue
  if ! grep -Fqxi "${ext}" <<<"${MODULES}"; then
    MISSING+=("${ext}")
  fi
done < <(jq -r '.catalog[]' "${EXT_JSON}")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "error: missing catalog extensions in ${PHP_BIN}:" >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

COUNT="$(jq '.catalog | length' "${EXT_JSON}")"
echo "extensions OK: ${COUNT} catalog modules present"
