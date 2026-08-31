#!/usr/bin/env bash
# Build a static PHP CLI with StaticPHP (spc v3) from the current directory's craft.yml.
#
# Expects to be run from builds/<php-version>/ (or with CRAFT_DIR set).
# Produces buildroot/bin/php. Composer is installed separately in CI / packaging.
#
# Environment:
#   SPC_BIN          — path to spc executable (default: download-spc.sh → repo root spc)
#   CRAFT_DIR        — directory containing craft.yml (default: cwd)
#   EXPECTED_PHP     — exact patch to require in php -v (default: basename of CRAFT_DIR)
#   SPC_SKIP_DOCTOR  — set to 1 to skip spc doctor (not recommended)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRAFT_DIR="${CRAFT_DIR:-$(pwd)}"
SCRIPTS="${ROOT}/scripts"

if [[ ! -d "${CRAFT_DIR}" ]]; then
  echo "error: CRAFT_DIR not found: ${CRAFT_DIR}" >&2
  exit 1
fi

EXPECTED_PHP="${EXPECTED_PHP:-$(basename "${CRAFT_DIR}")}"
if [[ ! "${EXPECTED_PHP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: EXPECTED_PHP must be MAJOR.MINOR.PATCH (got '${EXPECTED_PHP}')" >&2
  exit 1
fi

"${SCRIPTS}/render-craft.sh" "${CRAFT_DIR}"

SPC_BIN="${SPC_BIN:-}"
if [[ -z "${SPC_BIN}" ]]; then
  for candidate in "${ROOT}/spc" "${CRAFT_DIR}/spc"; do
    if [[ -x "${candidate}" ]]; then
      SPC_BIN="${candidate}"
      break
    fi
  done
fi

if [[ -z "${SPC_BIN}" || ! -x "${SPC_BIN}" ]]; then
  "${SCRIPTS}/download-spc.sh" "${ROOT}/spc"
  SPC_BIN="${ROOT}/spc"
fi

cd "${CRAFT_DIR}"
echo "building with ${SPC_BIN} in ${CRAFT_DIR} (expect PHP ${EXPECTED_PHP})"

ensure_frankenphp_source_link() {
  # Workaround for SPC v3.0.0-alpha1: when building cli-only, the AVX512
  # patch is applied against source/frankenphp which doesn't exist for
  # plain CLI builds. Symlink source/php-src → source/frankenphp so the
  # patch target resolves. Remove this once upstream SPC fixes
  # getSourceDir() in unix.php (track: crazywhalecc/static-php-cli).
  if [[ ! -e "${CRAFT_DIR}/source/frankenphp" && -d "${CRAFT_DIR}/source/php-src" ]]; then
    ln -s php-src "${CRAFT_DIR}/source/frankenphp"
    echo "created source/frankenphp -> php-src compatibility symlink"
    return 0
  fi
  return 1
}

ensure_frankenphp_source_link || true

if [[ "${SPC_SKIP_DOCTOR:-0}" != "1" ]]; then
  "${SPC_BIN}" doctor --auto-fix
else
  echo "warning: skipping spc doctor (SPC_SKIP_DOCTOR=1)"
fi

if [[ "$(uname -s)" == "Darwin" && -z "${SPC_EXTRA_PHP_VARS:-}" ]]; then
  # static-php-cli nightly (since 2026-08-22, a488606e) stopped leaking the
  # macOS framework flags into php's ./configure, so the static libcurl
  # conftest link fails with "The libcurl check failed". Pass them through
  # LIBS explicitly until upstream restores framework handling for Darwin.
  export SPC_EXTRA_PHP_VARS="LIBS='-lresolv -framework CoreFoundation -framework CoreServices -framework SystemConfiguration'"
fi

dump_failure_logs() {
  echo "spc craft failed; dumping diagnostic logs" >&2
  local log_file
  for log_file in \
    "${CRAFT_DIR}/log/php-src.config.log" \
    "${CRAFT_DIR}/log/spc.output.log" \
    "${CRAFT_DIR}/log/spc.shell.log"; do
    if [[ -f "${log_file}" ]]; then
      echo "===== ${log_file} (errors, last 40) =====" >&2
      grep -iE "error|cannot|not found|failed" "${log_file}" | tail -40 >&2 || true
      echo "===== ${log_file} (tail 120) =====" >&2
      tail -120 "${log_file}" >&2 || true
    else
      echo "warning: log not found: ${log_file}" >&2
    fi
  done
}

if ! "${SPC_BIN}" craft "$@"; then
  if ensure_frankenphp_source_link; then
    echo "retrying spc craft after creating compatibility symlink"
    if ! "${SPC_BIN}" craft "$@"; then
      dump_failure_logs
      exit 1
    fi
  else
    dump_failure_logs
    exit 1
  fi
fi

PHP_BIN="${CRAFT_DIR}/buildroot/bin/php"
if [[ ! -x "${PHP_BIN}" ]]; then
  echo "error: build did not produce buildroot/bin/php" >&2
  exit 1
fi

VERSION_LINE="$("${PHP_BIN}" -v | head -1)"
if [[ "${VERSION_LINE}" != *"PHP ${EXPECTED_PHP}"* ]]; then
  echo "error: built PHP version mismatch" >&2
  echo "  expected patch: ${EXPECTED_PHP}" >&2
  echo "  got: ${VERSION_LINE}" >&2
  exit 1
fi

"${SCRIPTS}/verify-extensions.sh" "${PHP_BIN}"

"${PHP_BIN}" -v
echo "static PHP ready: ${PHP_BIN}"
