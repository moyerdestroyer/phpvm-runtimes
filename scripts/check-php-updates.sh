#!/usr/bin/env bash
# Check php.net for newer patches than the ones in manifest.json.
#
# Usage:
#   check-php-updates.sh [manifest.json]
#
# Exit codes:
#   0 — all current (or updates printed to stdout)
#   1 — error fetching
#
# Output format (one line per outdated version):
#   UPDATE 8.3 8.3.31 -> 8.3.32
set -euo pipefail

MANIFEST="${1:-manifest.json}"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "error: manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

OUTDATED=0

while IFS= read -r current; do
  [[ -n "${current}" ]] || continue
  minor="${current%.*}"

  # php.net provides JSON release info per major version.
  # The endpoint returns all releases for that branch; we take the latest.
  json_url="https://www.php.net/releases/index.php?json=1&max=1&version=${minor}"
  latest="$(curl -fsSL --retry 3 --max-time 15 "${json_url}" 2>/dev/null | jq -r 'keys[0]' 2>/dev/null || true)"

  if [[ -z "${latest}" || "${latest}" == "null" ]]; then
    # Fallback: parse the downloads page
    latest="$(curl -fsSL --retry 3 --max-time 15 "https://www.php.net/downloads/index.php" 2>/dev/null \
      | grep -oE "Current Release.*${minor}\.[0-9]+" \
      | grep -oE "${minor}\.[0-9]+" \
      | head -1 || true)"
  fi

  if [[ -z "${latest}" || "${latest}" == "null" ]]; then
    echo "WARN  could not determine latest ${minor}.x from php.net" >&2
    continue
  fi

  if [[ "${latest}" != "${current}" ]]; then
    echo "UPDATE ${minor} ${current} -> ${latest}"
    OUTDATED=1
  else
    echo "OK     ${minor} ${current}" >&2
  fi
done < <(jq -r '.runtimes[].php' "${MANIFEST}")

exit 0
