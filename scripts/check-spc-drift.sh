#!/usr/bin/env bash
# Check whether the pinned SPC (static-php-cli) binaries still match upstream.
#
# Usage:
#   check-spc-drift.sh [--apply] [--pin-file PATH]
#
# Without --apply, prints a per-asset report and exits 0. Drift is reported,
# not fatal, so this is safe to run as a CI detector.
#
# With --apply, additionally rewrites the pin file in place with current
# upstream sha256 values for any asset that drifted.
#
# Output lines (stdout):
#   spc-linux-x86_64   bbf43260...                                   current
#   spc-linux-x86_64   0a4b9f1b... -> bbf43260...                    drift
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${ROOT}/builds/common/spc-pin.json"
APPLY=0

usage() {
  cat >&2 <<'EOF'
Usage:
  check-spc-drift.sh [--apply] [--pin-file PATH]

Options:
  --apply            Rewrite the pin file with current upstream checksums
  --pin-file PATH    Pin file to check (default: builds/common/spc-pin.json)
EOF
  exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --pin-file)
      [[ $# -ge 2 ]] || usage
      PIN_FILE="$2"; shift 2
      ;;
    -h|--help) usage 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -f "${PIN_FILE}" ]] || {
  echo "error: pin file not found: ${PIN_FILE}" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "error: sha256sum or shasum is required" >&2
    return 1
  fi
}

CHANNEL="$(jq -r '.channel' "${PIN_FILE}")"
DRIFT_COUNT=0
DRIFT_REPORT=""
UPDATED_JSON="$(jq '.assets' "${PIN_FILE}")"

while IFS=$'\t' read -r ASSET PIN; do
  URL="${CHANNEL}/${ASSET}"
  TMP="$(mktemp)"

  if ! curl --fail --silent --show-error --location \
        --retry 5 --retry-delay 2 --retry-max-time 120 --retry-all-errors \
        -o "${TMP}" "${URL}"; then
    echo "error: failed to download ${URL}" >&2
    rm -f "${TMP}"
    exit 1
  fi

  ACTUAL="$(hash_file "${TMP}")"
  rm -f "${TMP}"

  if [[ "${ACTUAL}" == "${PIN}" ]]; then
    echo "${ASSET}   ${PIN:0:12}...   current"
  else
    echo "${ASSET}   ${PIN:0:12}... -> ${ACTUAL:0:12}...   drift"
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
    DRIFT_REPORT+="${ASSET}: ${PIN} -> ${ACTUAL}"$'\n'
    UPDATED_JSON="$(jq --arg a "${ASSET}" --arg sha "${ACTUAL}" \
      '.[$a] = $sha' <<<"${UPDATED_JSON}")"
  fi
done < <(jq -r '.assets | to_entries[] | "\(.key)\t\(.value)"' "${PIN_FILE}")

if [[ "${APPLY}" -eq 1 && "${DRIFT_COUNT}" -gt 0 ]]; then
  TMP_FILE="$(mktemp)"
  jq --argjson assets "${UPDATED_JSON}" '.assets = $assets' "${PIN_FILE}" > "${TMP_FILE}"
  mv "${TMP_FILE}" "${PIN_FILE}"
  echo "updated ${DRIFT_COUNT} pin(s) in ${PIN_FILE}"
elif [[ "${APPLY}" -eq 1 ]]; then
  echo "no drift; pin file unchanged"
fi

if [[ "${DRIFT_COUNT}" -gt 0 ]]; then
  echo "---drift-report-start---"
  printf '%s' "${DRIFT_REPORT}"
  echo "---drift-report-end---"
fi

exit 0
