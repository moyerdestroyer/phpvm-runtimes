#!/usr/bin/env bash
# (Legacy) Bundle non-system shared libraries for dynamic runtimes.
# Static is the supported catalog mode; this is kept for reference/experiments.
#
# Usage:
#   bundle-dynamic-libs.sh <staging-dir>
set -euo pipefail

usage() {
  echo "Usage: $0 <staging-dir>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

STAGING="$(cd "$1" && pwd)"
PHP_BIN="${STAGING}/bin/php"
EXT_DIR="${STAGING}/ext"
LIB_DIR="${STAGING}/lib"

[[ -x "${PHP_BIN}" ]] || {
  echo "error: missing executable ${PHP_BIN}" >&2
  exit 1
}
[[ -d "${EXT_DIR}" ]] || {
  echo "error: missing extension directory ${EXT_DIR}" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

OBJECTS="${TMP}/objects"
QUEUE="${TMP}/queue"
SEEN="${TMP}/seen"
COPIED="${TMP}/copied"
MAPPINGS="${TMP}/mappings"

: > "${OBJECTS}"
: > "${QUEUE}"
: > "${SEEN}"
: > "${COPIED}"
: > "${MAPPINGS}"

printf '%s\n' "${PHP_BIN}" >> "${OBJECTS}"
find "${EXT_DIR}" -type f \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -print | sort >> "${OBJECTS}"
cp "${OBJECTS}" "${QUEUE}"

mkdir -p "${LIB_DIR}"

has_line() {
  local needle="$1"
  local file="$2"
  grep -Fx -- "${needle}" "${file}" >/dev/null 2>&1
}

copy_dep() {
  local source="$1"
  local load_name="${2:-$1}"
  local base
  local dest

  base="$(basename "${source}")"
  dest="${LIB_DIR}/${base}"

  if [[ -e "${dest}" ]]; then
    if ! cmp -s "${source}" "${dest}" >/dev/null 2>&1; then
      echo "error: dependency basename collision for ${base}" >&2
      echo "  existing: ${dest}" >&2
      echo "  new:      ${source}" >&2
      exit 1
    fi
  else
    cp -pL "${source}" "${dest}"
    chmod u+w "${dest}"
    printf '%s\n' "${dest}" >> "${COPIED}"
  fi

  printf '%s\t%s\n' "${load_name}" "${base}" >> "${MAPPINGS}"
}

is_linux_base_lib() {
  local base="$1"
  case "${base}" in
    linux-vdso.so.*|ld-linux*.so.*|ld-musl*.so.*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libanl.so.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

linux_deps_for() {
  local file="$1"

  if ldd "${file}" 2>&1 | grep -q 'not found'; then
    echo "error: unresolved dependency while bundling ${file}" >&2
    ldd "${file}" >&2 || true
    return 1
  fi

  ldd "${file}" 2>/dev/null | awk '
    /=>/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "=>") {
          if ($(i + 1) ~ /^\//) {
            print $(i + 1)
          }
          break
        }
      }
      next
    }
    /^[[:space:]]*\// {
      print $1
    }
  '
}

bundle_linux() {
  local item
  local dep
  local base
  local deps

  for tool in ldd patchelf; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "error: required tool not found: ${tool}" >&2
      exit 1
    fi
  done

  while IFS= read -r item; do
    [[ -n "${item}" && -e "${item}" ]] || continue
    if has_line "${item}" "${SEEN}"; then
      continue
    fi
    printf '%s\n' "${item}" >> "${SEEN}"

    deps="$(linux_deps_for "${item}")" || exit 1
    while IFS= read -r dep; do
      [[ -n "${dep}" && -e "${dep}" ]] || continue
      base="$(basename "${dep}")"
      if is_linux_base_lib "${base}"; then
        continue
      fi
      copy_dep "${dep}"
      if ! has_line "${LIB_DIR}/${base}" "${QUEUE}"; then
        printf '%s\n' "${LIB_DIR}/${base}" >> "${QUEUE}"
      fi
    done <<< "${deps}"
  done < "${QUEUE}"

  while IFS= read -r item; do
    [[ -n "${item}" && -e "${item}" ]] || continue
    patchelf --set-rpath '$ORIGIN/../lib' "${item}"
  done < "${OBJECTS}"

  while IFS= read -r item; do
    [[ -n "${item}" && -e "${item}" ]] || continue
    patchelf --set-rpath '$ORIGIN' "${item}"
  done < "${COPIED}"
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

macos_deps_for() {
  local file="$1"
  otool -L "${file}" 2>/dev/null | awk 'NR > 1 {print $1}'
}

macos_rpaths_for() {
  local file="$1"
  otool -l "${file}" 2>/dev/null | awk '
    $1 == "cmd" && $2 == "LC_RPATH" {
      in_rpath = 1
      next
    }
    in_rpath && $1 == "path" {
      print $2
      in_rpath = 0
    }
  '
}

macos_resolve_rpath_dep() {
  local object="$1"
  local dep="$2"
  local suffix="${dep#@rpath/}"
  local rpath
  local candidate
  local candidate_dir

  while IFS= read -r rpath; do
    [[ -n "${rpath}" ]] || continue
    case "${rpath}" in
      @loader_path/*)
        candidate="$(cd "$(dirname "${object}")" && pwd)/${rpath#@loader_path/}/${suffix}"
        ;;
      @executable_path/*)
        candidate="${STAGING}/bin/${rpath#@executable_path/}/${suffix}"
        ;;
      /*)
        candidate="${rpath}/${suffix}"
        ;;
      *)
        continue
        ;;
    esac
    if [[ -e "${candidate}" ]]; then
      candidate_dir="$(cd "$(dirname "${candidate}")" && pwd -P)"
      printf '%s/%s\n' "${candidate_dir}" "$(basename "${candidate}")"
      return 0
    fi
  done < <(macos_rpaths_for "${object}")

  return 1
}

macos_change_dep() {
  local object="$1"
  local old="$2"
  local new="$3"

  if otool -L "${object}" 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fx -- "${old}" >/dev/null 2>&1; then
    install_name_tool -change "${old}" "${new}" "${object}"
  fi
}

macos_codesign() {
  local object="$1"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "${object}" >/dev/null 2>&1 || true
  fi
}

macos_delete_external_rpaths() {
  local object="$1"
  local rpath

  while IFS= read -r rpath; do
    [[ -n "${rpath}" ]] || continue
    case "${rpath}" in
      @loader_path/*|@executable_path/*)
        continue
        ;;
    esac
    if [[ "${rpath}" == /* ]] && ! is_macos_system_lib "${rpath}"; then
      install_name_tool -delete_rpath "${rpath}" "${object}" 2>/dev/null || true
    fi
  done < <(macos_rpaths_for "${object}")
}

bundle_macos() {
  local item
  local dep
  local base
  local old
  local new
  local deps
  local source

  for tool in otool install_name_tool; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "error: required tool not found: ${tool}" >&2
      exit 1
    fi
  done

  while IFS= read -r item; do
    [[ -n "${item}" && -e "${item}" ]] || continue
    if has_line "${item}" "${SEEN}"; then
      continue
    fi
    printf '%s\n' "${item}" >> "${SEEN}"

    deps="$(macos_deps_for "${item}")"
    while IFS= read -r dep; do
      [[ -n "${dep}" ]] || continue
      case "${dep}" in
        @rpath/*)
          if ! source="$(macos_resolve_rpath_dep "${item}" "${dep}")"; then
            echo "error: unresolved @rpath dependency while bundling ${item}: ${dep}" >&2
            exit 1
          fi
          base="$(basename "${source}")"
          copy_dep "${source}" "${dep}"
          if ! has_line "${LIB_DIR}/${base}" "${QUEUE}"; then
            printf '%s\n' "${LIB_DIR}/${base}" >> "${QUEUE}"
          fi
          continue
          ;;
        @loader_path/*|@executable_path/*)
          continue
          ;;
      esac
      if [[ "${dep}" != /* ]] || is_macos_system_lib "${dep}"; then
        continue
      fi
      if [[ ! -e "${dep}" ]]; then
        echo "error: unresolved dependency while bundling ${item}: ${dep}" >&2
        exit 1
      fi

      base="$(basename "${dep}")"
      copy_dep "${dep}" "${dep}"
      if ! has_line "${LIB_DIR}/${base}" "${QUEUE}"; then
        printf '%s\n' "${LIB_DIR}/${base}" >> "${QUEUE}"
      fi
    done <<< "${deps}"
  done < "${QUEUE}"

  while IFS="$(printf '\t')" read -r old base; do
    [[ -n "${old}" && -n "${base}" ]] || continue
    new="@loader_path/../lib/${base}"
    while IFS= read -r item; do
      [[ -n "${item}" && -e "${item}" ]] || continue
      macos_change_dep "${item}" "${old}" "${new}"
    done < "${OBJECTS}"

    new="@loader_path/${base}"
    while IFS= read -r item; do
      [[ -n "${item}" && -e "${item}" ]] || continue
      macos_change_dep "${item}" "${old}" "${new}"
    done < "${COPIED}"
  done < "${MAPPINGS}"

  while IFS= read -r item; do
    [[ -n "${item}" && -e "${item}" ]] || continue
    if [[ "${item}" == *.dylib ]]; then
      install_name_tool -id "@rpath/$(basename "${item}")" "${item}" || true
    fi
    macos_delete_external_rpaths "${item}"
    macos_codesign "${item}"
  done < "${OBJECTS}"

  while IFS= read -r item; do
    [[ -n "${item}" && -e "${item}" ]] || continue
    if [[ "${item}" == *.dylib ]]; then
      install_name_tool -id "@rpath/$(basename "${item}")" "${item}" || true
    fi
    macos_delete_external_rpaths "${item}"
    macos_codesign "${item}"
  done < "${COPIED}"
}

case "$(uname -s)" in
  Linux)
    bundle_linux
    ;;
  Darwin)
    bundle_macos
    ;;
  *)
    echo "error: unsupported host for dynamic library bundling: $(uname -s)" >&2
    exit 1
    ;;
esac

COUNT="$(find "${LIB_DIR}" -type f | wc -l | tr -d ' ')"
echo "bundled ${COUNT} shared libraries in ${LIB_DIR}"
