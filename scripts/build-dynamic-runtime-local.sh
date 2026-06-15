#!/usr/bin/env bash
# Build, stage, smoke-test, and package one dynamic runtime for the current host.
#
# Usage:
#   build-dynamic-runtime-local.sh <php-version> [target] [output-dir]
set -euo pipefail

usage() {
  echo "Usage: $0 <php-version> [target] [output-dir]" >&2
  exit 1
}

host_target() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "x86_64-unknown-linux-gnu" ;;
    Darwin-arm64) echo "aarch64-apple-darwin" ;;
    *)
      echo "error: unsupported host $(uname -s) $(uname -m)" >&2
      return 1
      ;;
  esac
}

[[ $# -ge 1 && $# -le 3 ]] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHP_VERSION="$1"
TARGET="${2:-$(host_target)}"
OUT_DIR="${3:-${ROOT}/dist}"
HOST_TARGET="$(host_target)"
STAGING="${ROOT}/builds/${PHP_VERSION}/dynamic-staging"

if [[ "${TARGET}" != "${HOST_TARGET}" ]]; then
  echo "error: local build target ${TARGET} does not match host ${HOST_TARGET}" >&2
  echo "use GitHub Actions for cross-platform catalog builds" >&2
  exit 1
fi

echo "building dynamic PHP ${PHP_VERSION} for ${TARGET}"
"${ROOT}/scripts/build-dynamic-php.sh" "${PHP_VERSION}" "${STAGING}"
"${ROOT}/scripts/install-composer.sh" "${STAGING}"

"${ROOT}/scripts/package-runtime.sh" \
  "${STAGING}" \
  "${PHP_VERSION}" \
  "${TARGET}" \
  "${OUT_DIR}"

echo "dynamic runtime ready in ${OUT_DIR}: php-${PHP_VERSION}-${TARGET}.tar.gz"
