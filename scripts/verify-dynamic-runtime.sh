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
SOURCE_PHP_BIN="${STAGING}/bin/php"
SOURCE_COMPOSER_BIN="${STAGING}/bin/composer"
SOURCE_EXT_DIR="${STAGING}/ext"

[[ -x "${SOURCE_PHP_BIN}" ]] || {
  echo "error: missing executable ${SOURCE_PHP_BIN}" >&2
  exit 1
}
[[ -x "${SOURCE_COMPOSER_BIN}" ]] || {
  echo "error: missing executable ${SOURCE_COMPOSER_BIN}" >&2
  exit 1
}
[[ -d "${SOURCE_EXT_DIR}" ]] || {
  echo "error: missing extension directory ${SOURCE_EXT_DIR}" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

RUNTIME="${TMP}/runtime"
mkdir -p "${RUNTIME}"
cp -a "${STAGING}/." "${RUNTIME}/"

PHP_BIN="${RUNTIME}/bin/php"
COMPOSER_BIN="${RUNTIME}/bin/composer"
EXT_DIR="${RUNTIME}/ext"
LIB_DIR="${RUNTIME}/lib"
RUNTIME_METADATA="${RUNTIME}/metadata/runtime.json"
PROFILE_METADATA="${RUNTIME}/etc/profiles/profiles.json"

shopt -s nullglob
EXT_FILES=("${EXT_DIR}"/*.so "${EXT_DIR}"/*.dylib "${EXT_DIR}"/*.dll)
if [[ ${#EXT_FILES[@]} -eq 0 ]]; then
  echo "error: dynamic runtime has no extension files in ${EXT_DIR}" >&2
  exit 1
fi
LIB_FILES=("${LIB_DIR}"/*.so "${LIB_DIR}"/*.so.* "${LIB_DIR}"/*.dylib)

if [[ ! -f "${RUNTIME_METADATA}" ]]; then
  echo "error: missing runtime metadata: ${RUNTIME_METADATA}" >&2
  exit 1
fi
if [[ ! -f "${PROFILE_METADATA}" ]]; then
  echo "error: missing profile metadata: ${PROFILE_METADATA}" >&2
  exit 1
fi
if command -v jq >/dev/null 2>&1; then
  DEFAULT_PROFILE="$(jq -r '.default_profile // empty' "${PROFILE_METADATA}")"
  [[ "${DEFAULT_PROFILE}" == "dev" ]] || {
    echo "error: runtime default profile must be dev" >&2
    exit 1
  }
  for required_profile in minimal dev debug; do
    if ! jq -e --arg name "${required_profile}" '.profiles[] | select(.name == $name)' "${PROFILE_METADATA}" >/dev/null; then
      echo "error: missing runtime profile ${required_profile}" >&2
      exit 1
    fi
  done
fi

check_linux_deps() {
  local file
  local output
  local failed=0

  command -v ldd >/dev/null 2>&1 || return 0

  for file in "${PHP_BIN}" "${EXT_FILES[@]}" "${LIB_FILES[@]}"; do
    [[ -e "${file}" ]] || continue
    output="$(ldd "${file}" 2>&1 || true)"
    if printf '%s\n' "${output}" | grep -q 'not found'; then
      echo "error: unresolved shared library dependency in ${file}" >&2
      printf '%s\n' "${output}" >&2
      failed=1
    fi
  done

  [[ "${failed}" -eq 0 ]]
}

is_macos_system_lib() {
  local dep="$1"
  case "${dep}" in
    /usr/lib/*|/System/Library/*|/Library/Apple/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_macos_deps() {
  local file
  local dep
  local rpath
  local failed=0

  command -v otool >/dev/null 2>&1 || return 0

  for file in "${PHP_BIN}" "${EXT_FILES[@]}" "${LIB_FILES[@]}"; do
    [[ -e "${file}" ]] || continue
    while IFS= read -r dep; do
      [[ -n "${dep}" ]] || continue
      case "${dep}" in
        @rpath/*)
          echo "error: unresolved portable dylib reference in ${file}: ${dep}" >&2
          failed=1
          continue
          ;;
        @loader_path/*|@executable_path/*)
          continue
          ;;
      esac
      if [[ "${dep}" == /* ]] && ! is_macos_system_lib "${dep}"; then
        echo "error: non-system absolute dylib reference in ${file}: ${dep}" >&2
        failed=1
      fi
    done < <(otool -L "${file}" 2>/dev/null | awk 'NR > 1 {print $1}')

    while IFS= read -r rpath; do
      [[ -n "${rpath}" ]] || continue
      case "${rpath}" in
        @loader_path/*|@executable_path/*)
          continue
          ;;
      esac
      if [[ "${rpath}" == /* ]] && ! is_macos_system_lib "${rpath}"; then
        echo "error: non-system absolute rpath in ${file}: ${rpath}" >&2
        failed=1
      fi
    done < <(otool -l "${file}" 2>/dev/null | awk '
      $1 == "cmd" && $2 == "LC_RPATH" {
        in_rpath = 1
        next
      }
      in_rpath && $1 == "path" {
        print $2
        in_rpath = 0
      }
    ')
  done

  [[ "${failed}" -eq 0 ]]
}

case "$(uname -s)" in
  Linux)
    if [[ ! -f "${RUNTIME}/metadata/bundled-libs.json" ]]; then
      echo "error: missing bundled library metadata" >&2
      exit 1
    fi
    if [[ ! -f "${RUNTIME}/THIRD_PARTY_NOTICES" ]]; then
      echo "error: missing third-party notices" >&2
      exit 1
    fi
    if command -v jq >/dev/null 2>&1; then
      for file in "${LIB_FILES[@]}"; do
        [[ -e "${file}" ]] || continue
        rel="lib/$(basename "${file}")"
        if ! jq -e --arg file "${rel}" '.[] | select(.file == $file and .license_file)' "${RUNTIME}/metadata/bundled-libs.json" >/dev/null; then
          echo "error: missing bundled library license metadata for ${rel}" >&2
          exit 1
        fi
      done
      REQUIRED_GLIBC="$(jq -r '.linux_compatibility.required_glibc // empty' "${RUNTIME_METADATA}")"
      [[ -n "${REQUIRED_GLIBC}" ]] || {
        echo "error: missing required glibc metadata" >&2
        exit 1
      }
    fi
    check_linux_deps
    ;;
  Darwin)
    check_macos_deps
    ;;
esac

PHPRC_DIR="${TMP}/phprc"
CONF_DIR="${TMP}/conf.d"
mkdir -p "${PHPRC_DIR}" "${CONF_DIR}"
cat > "${PHPRC_DIR}/php.ini" <<EOF
extension_dir = "${EXT_DIR}"
EOF

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

env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH "${PHP_BIN}" -v >/dev/null
env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH PHPRC="${PHPRC_DIR}" PHP_INI_SCAN_DIR="${CONF_DIR}" "${COMPOSER_BIN}" -V >/dev/null
env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH PHPRC="${PHPRC_DIR}" PHP_INI_SCAN_DIR="${CONF_DIR}" "${PHP_BIN}" -m >/dev/null
env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH PHPRC="${PHPRC_DIR}" PHP_INI_SCAN_DIR="${CONF_DIR}" "${PHP_BIN}" --ini >/dev/null

echo "dynamic runtime OK: ${STAGING} (${#EXT_FILES[@]} extension files)"
