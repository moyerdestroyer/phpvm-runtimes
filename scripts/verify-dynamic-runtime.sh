#!/usr/bin/env bash
# Verify a staged dynamic phpvm runtime bundle.
#
# Usage:
#   verify-dynamic-runtime.sh <staging-dir>
set -euo pipefail

usage() {
  echo "Usage: $0 <staging-dir>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

STAGING="$1"
PHP_BIN="${STAGING}/bin/php"
COMPOSER_BIN="${STAGING}/bin/composer"
EXT_DIR="${STAGING}/ext"

[[ -x "${PHP_BIN}" ]] || {
  echo "error: missing executable ${PHP_BIN}" >&2
  exit 1
}
[[ -x "${COMPOSER_BIN}" ]] || {
  echo "error: missing executable ${COMPOSER_BIN}" >&2
  exit 1
}
[[ -d "${EXT_DIR}" ]] || {
  echo "error: missing extension directory ${EXT_DIR}" >&2
  exit 1
}

"${PHP_BIN}" -v >/dev/null
PHPRC="${STAGING}/etc" PHP_INI_SCAN_DIR="${STAGING}/etc/conf.d" "${COMPOSER_BIN}" -V >/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mkdir -p "${TMP}/phprc" "${TMP}/conf.d"
cat > "${TMP}/phprc/php.ini" <<EOF
extension_dir = "${EXT_DIR}"
EOF

shopt -s nullglob
EXT_FILES=("${EXT_DIR}"/*.so "${EXT_DIR}"/*.dylib "${EXT_DIR}"/*.dll)
if [[ ${#EXT_FILES[@]} -eq 0 ]]; then
  echo "error: dynamic runtime has no extension files in ${EXT_DIR}" >&2
  exit 1
fi

extension_priority() {
  local name="$1"
  case "${name}" in
    opcache|xdebug) echo "10" ;;
    pdo) echo "20" ;;
    *) echo "30" ;;
  esac
}

for file in "${EXT_FILES[@]}"; do
  base="$(basename "${file}")"
  name="${base%.*}"
  priority="$(extension_priority "${name}")"
  if [[ "${name}" == "opcache" || "${name}" == "xdebug" ]]; then
    echo "zend_extension=${file}" > "${TMP}/conf.d/${priority}-${name}.ini"
  else
    echo "extension=${file}" > "${TMP}/conf.d/${priority}-${name}.ini"
  fi
done

PHP_INI_SCAN_DIR="${TMP}/conf.d" PHPRC="${TMP}/phprc" "${PHP_BIN}" -m >/dev/null
PHP_INI_SCAN_DIR="${TMP}/conf.d" PHPRC="${TMP}/phprc" "${PHP_BIN}" --ini >/dev/null

echo "dynamic runtime OK: ${STAGING} (${#EXT_FILES[@]} extension files)"
