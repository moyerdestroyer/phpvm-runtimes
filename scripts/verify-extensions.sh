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

# php -m lists both [PHP Modules] and [Zend Modules]. Some zend extensions
# (notably opcache in static SPC builds) are compiled in but not listed until
# explicitly enabled; fall back to a strings check for those.
ZEND_EXTENSIONS=(opcache)
MODULES="$("${PHP_BIN}" -m)"
MISSING=()

is_zend_extension() {
  local ext="$1"
  local candidate
  for candidate in "${ZEND_EXTENSIONS[@]}"; do
    [[ "${ext}" == "${candidate}" ]] && return 0
  done
  return 1
}

zend_extension_present() {
  local ext="$1"
  # Search the binary directly — piping strings→grep trips pipefail on SIGPIPE.
  grep -aEqi "${ext}|OPCACHE" "${PHP_BIN}"
}

while IFS= read -r ext; do
  [[ -n "${ext}" ]] || continue
  if grep -Fqxi "${ext}" <<<"${MODULES}"; then
    continue
  fi
  if is_zend_extension "${ext}" && zend_extension_present "${ext}"; then
    continue
  fi
  MISSING+=("${ext}")
done < <(jq -r '.catalog[]' "${EXT_JSON}")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "error: missing catalog extensions in ${PHP_BIN}:" >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  exit 1
fi

COUNT="$(jq '.catalog | length' "${EXT_JSON}")"
echo "extensions OK: ${COUNT} catalog modules present"
