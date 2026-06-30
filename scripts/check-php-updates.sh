#!/usr/bin/env bash
# Check php.net for catalog changes relative to manifest.json.
#
# Usage:
#   check-php-updates.sh [manifest.json]
#
# Exit codes:
#   0 - all current (or updates printed to stdout)
#   1 - error fetching/planning
#
# Output format:
#   UPDATE 8.3 8.3.31 -> 8.3.32
#   ADD    8.5 8.5.0
#   REMOVE 8.1 8.1.34
set -euo pipefail

MANIFEST="${1:-manifest.json}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "error: manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

PLAN="$(mktemp)"
trap 'rm -f "${PLAN}"' EXIT

"${ROOT}/scripts/plan-catalog-update.py" --manifest "${MANIFEST}" > "${PLAN}"

jq -r '.updated[] | "UPDATE \(.minor) \(.from) -> \(.to)"' "${PLAN}"
jq -r '.added[] | "ADD    \(. | split(".")[:2] | join(".")) \(.)"' "${PLAN}"
jq -r '.removed[] | "REMOVE \(. | split(".")[:2] | join(".")) \(.)"' "${PLAN}"

if [[ "$(jq -r '.has_update' "${PLAN}")" != "true" ]]; then
  jq -r '.desired_versions[] | "OK     \(. | split(".")[:2] | join(".")) \(.)"' "${PLAN}" >&2
fi

exit 0
