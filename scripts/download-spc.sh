#!/usr/bin/env bash
# Download and verify the pinned StaticPHP (spc) binary for this host or a named asset.
#
# Usage:
#   download-spc.sh [output-path]
#   download-spc.sh spc-linux-x86_64 [output-path]
#
# Default asset is chosen from the host OS/arch. SHA-256 pins live in
# builds/common/spc-pin.json (bump when intentionally upgrading spc).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${ROOT}/builds/common/spc-pin.json"

if [[ ! -f "${PIN_FILE}" ]]; then
  echo "error: pin file not found: ${PIN_FILE}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

CHANNEL="$(jq -r '.channel' "${PIN_FILE}")"
ASSET=""
OUT=""

if [[ $# -eq 0 ]]; then
  OUT="${ROOT}/spc"
elif [[ $# -eq 1 ]]; then
  if [[ "$1" == spc-* ]]; then
    ASSET="$1"
    OUT="${ROOT}/spc"
  else
    OUT="$1"
  fi
elif [[ $# -eq 2 ]]; then
  ASSET="$1"
  OUT="$2"
else
  echo "Usage: $0 [asset-name] [output-path]" >&2
  exit 1
fi

if [[ -z "${ASSET}" ]]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  ASSET=spc-linux-x86_64 ;;
    Linux-aarch64) ASSET=spc-linux-aarch64 ;;
    Darwin-x86_64) ASSET=spc-macos-x86_64 ;;
    Darwin-arm64)  ASSET=spc-macos-aarch64 ;;
    *)
      echo "error: unsupported host $(uname -s) $(uname -m); pass an asset name explicitly" >&2
      exit 1
      ;;
  esac
fi

PIN="$(jq -r --arg a "${ASSET}" '.assets[$a] // empty' "${PIN_FILE}")"
[[ -n "${PIN}" ]] || {
  echo "error: no sha256 pin for asset ${ASSET} in ${PIN_FILE}" >&2
  exit 1
}

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

URL="${CHANNEL}/${ASSET}"
echo "downloading ${URL}"
curl --fail --silent --show-error --location \
  --retry 5 --retry-delay 2 --retry-max-time 120 --retry-all-errors \
  -o "${TMP}" "${URL}"
chmod +x "${TMP}"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "${TMP}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL="$(shasum -a 256 "${TMP}" | awk '{print $1}')"
else
  echo "error: sha256sum or shasum is required" >&2
  exit 1
fi

if [[ "${ACTUAL}" != "${PIN}" ]]; then
  echo "error: spc checksum mismatch for ${ASSET}" >&2
  echo "  expected: ${PIN}" >&2
  echo "  actual:   ${ACTUAL}" >&2
  echo "  bump builds/common/spc-pin.json if upgrading spc intentionally" >&2
  exit 1
fi

mv "${TMP}" "${OUT}"
trap - EXIT
echo "spc ready: ${OUT} (${ASSET}, sha256 ${PIN:0:12}...)"
