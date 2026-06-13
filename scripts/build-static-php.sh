#!/usr/bin/env bash
# Build a static PHP CLI with StaticPHP (spc v3) from the current directory's craft.yml.
#
# Expects to be run from builds/<php-version>/ (or with CRAFT_DIR set).
# Produces buildroot/bin/php. Composer is installed separately in CI / packaging.
#
# Environment:
#   SPC_BIN   — path to spc executable (default: ./spc in CRAFT_DIR parent or repo root)
#   CRAFT_DIR — directory containing craft.yml (default: cwd)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRAFT_DIR="${CRAFT_DIR:-$(pwd)}"

if [[ ! -f "${CRAFT_DIR}/craft.yml" ]]; then
  echo "error: craft.yml not found in ${CRAFT_DIR}" >&2
  exit 1
fi

SPC_BIN="${SPC_BIN:-}"
if [[ -z "${SPC_BIN}" ]]; then
  for candidate in "${CRAFT_DIR}/spc" "${ROOT}/spc" "./spc"; do
    if [[ -x "${candidate}" ]]; then
      SPC_BIN="${candidate}"
      break
    fi
  done
fi

if [[ -z "${SPC_BIN}" || ! -x "${SPC_BIN}" ]]; then
  echo "error: spc binary not found. Download from https://static-php.dev" >&2
  exit 1
fi

cd "${CRAFT_DIR}"
echo "building with ${SPC_BIN} in ${CRAFT_DIR}"
"${SPC_BIN}" doctor --auto-fix || true
"${SPC_BIN}" craft "$@"

PHP_BIN="${CRAFT_DIR}/buildroot/bin/php"
if [[ ! -x "${PHP_BIN}" ]]; then
  echo "error: build did not produce buildroot/bin/php" >&2
  exit 1
fi

"${PHP_BIN}" -v
echo "static PHP ready: ${PHP_BIN}"