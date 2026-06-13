#!/usr/bin/env bash
# Build, stage, smoke-test, and package one runtime for the current host.
#
# Usage:
#   build-runtime-local.sh <php-version> [target] [output-dir]
#
# The target defaults to the current host triple. Cross-compiling is not
# supported here; use GitHub Actions for non-host targets.
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
CRAFT_DIR="${ROOT}/builds/${PHP_VERSION}"

if [[ ! "${PHP_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: php version must be MAJOR.MINOR.PATCH (got '${PHP_VERSION}')" >&2
  exit 1
fi

if [[ "${TARGET}" != "${HOST_TARGET}" ]]; then
  echo "error: local build target ${TARGET} does not match host ${HOST_TARGET}" >&2
  echo "use GitHub Actions for cross-platform catalog builds" >&2
  exit 1
fi

if [[ ! -d "${CRAFT_DIR}" ]]; then
  echo "error: build recipe not found: ${CRAFT_DIR}" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo "building PHP ${PHP_VERSION} for ${TARGET}"
CRAFT_DIR="${CRAFT_DIR}" EXPECTED_PHP="${PHP_VERSION}" "${ROOT}/scripts/build-static-php.sh"

mkdir -p "${STAGING}/bin"
cp "${CRAFT_DIR}/buildroot/bin/php" "${STAGING}/bin/php"
"${ROOT}/scripts/install-composer.sh" "${STAGING}"

"${ROOT}/scripts/package-runtime.sh" \
  "${STAGING}" \
  "${PHP_VERSION}" \
  "${TARGET}" \
  "${OUT_DIR}"

echo "runtime ready in ${OUT_DIR}: php-${PHP_VERSION}-${TARGET}.tar.gz"
