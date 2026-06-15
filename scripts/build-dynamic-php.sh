#!/usr/bin/env bash
# Build a dynamic PHP CLI runtime from source for the current host.
#
# Usage:
#   build-dynamic-php.sh <php-version> <staging-dir>
#
# The source is downloaded from php.net by default. Set
# PHPVM_DYNAMIC_USE_EXISTING_SOURCE=1 to reuse builds/<php-version>/source/php-src.
# This script does not use sudo. Missing library headers should be installed by
# the caller, then the script can be rerun.
set -euo pipefail
trap 'status=$?; echo "error: ${BASH_SOURCE[0]}:${LINENO}: command failed with status ${status}" >&2' ERR

usage() {
  echo "Usage: $0 <php-version> <staging-dir>" >&2
  exit 1
}

[[ $# -eq 2 ]] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHP_VERSION="$1"
STAGING="$2"
BUILD_DIR="${ROOT}/builds/${PHP_VERSION}"
WORK_DIR="${BUILD_DIR}/dynamic-work"
INSTALL_DIR="${WORK_DIR}/install"
BUILD_SOURCE="${WORK_DIR}/php-src"
SOURCE_ARCHIVE="${WORK_DIR}/php-${PHP_VERSION}.tar.gz"
XDEBUG_VERSION="${PHPVM_XDEBUG_VERSION:-3.5.3}"

if [[ ! "${PHP_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: php version must be MAJOR.MINOR.PATCH (got '${PHP_VERSION}')" >&2
  exit 1
fi

for tool in gcc make autoconf bison re2c pkg-config rsync; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required build tool not found: ${tool}" >&2
    exit 1
  fi
done

pkg_exists() {
  pkg-config --exists "$1" >/dev/null 2>&1
}

require_pkg() {
  local pkg="$1"
  if ! pkg_exists "${pkg}"; then
    echo "error: required pkg-config package not found: ${pkg}" >&2
    exit 1
  fi
}

for pkg in libxml-2.0 openssl zlib libcurl sqlite3 icu-uc oniguruma libzip; do
  require_pkg "${pkg}"
done

ICONV_ARG="--with-iconv=shared"
if [[ "$(uname -s)" == "Darwin" ]]; then
  ICONV_PREFIX="${PHPVM_ICONV_PREFIX:-}"
  if [[ -z "${ICONV_PREFIX}" ]] && command -v brew >/dev/null 2>&1; then
    ICONV_PREFIX="$(brew --prefix libiconv 2>/dev/null || true)"
  fi
  if [[ -z "${ICONV_PREFIX}" || ! -d "${ICONV_PREFIX}" ]]; then
    echo "error: libiconv prefix not found; install libiconv or set PHPVM_ICONV_PREFIX" >&2
    exit 1
  fi
  ICONV_ARG="--with-iconv=shared,${ICONV_PREFIX}"
fi

rm -rf "${WORK_DIR}" "${STAGING}"
mkdir -p "${WORK_DIR}" "${STAGING}"

if [[ "${PHPVM_DYNAMIC_USE_EXISTING_SOURCE:-0}" == "1" ]]; then
  SOURCE_DIR="${BUILD_DIR}/source/php-src"
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "error: PHP source not found: ${SOURCE_DIR}" >&2
    exit 1
  fi
  rsync -a --delete \
    --exclude=.git \
    --exclude=autom4te.cache \
    --exclude=modules \
    --exclude=libs \
    --exclude='*.lo' \
    --exclude='*.la' \
    --exclude='*.o' \
    "${SOURCE_DIR}/" "${BUILD_SOURCE}/"
else
  echo "downloading clean PHP ${PHP_VERSION} source"
  curl -fsSL "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" -o "${SOURCE_ARCHIVE}"
  tar -C "${WORK_DIR}" -xzf "${SOURCE_ARCHIVE}"
  mv "${WORK_DIR}/php-${PHP_VERSION}" "${BUILD_SOURCE}"
fi

CONFIGURE=(
  "./configure"
  "--prefix=${INSTALL_DIR}"
  "--with-config-file-path=${INSTALL_DIR}/etc"
  "--with-config-file-scan-dir=${INSTALL_DIR}/etc/conf.d"
  "--disable-cgi"
  "--disable-phpdbg"
  "--enable-cli"
  "--enable-shared"
  "--with-openssl=shared"
  "--with-zlib=shared"
  "--with-curl=shared"
  "--enable-dom=shared"
  "--enable-fileinfo=shared"
  "--enable-gd=shared"
  "--with-jpeg"
  "--with-webp"
  "--with-freetype"
  "${ICONV_ARG}"
  "--enable-intl=shared"
  "--enable-mbstring=shared"
  "--with-mysqli=shared,mysqlnd"
  "--enable-opcache=shared"
  "--enable-pdo=shared"
  "--with-pdo-mysql=shared,mysqlnd"
  "--with-pdo-sqlite=shared"
  "--enable-phar=shared"
  "--enable-session=shared"
  "--enable-simplexml=shared"
  "--enable-soap=shared"
  "--enable-sockets=shared"
  "--with-sqlite3=shared"
  "--enable-tokenizer=shared"
  "--enable-xml=shared"
  "--enable-xmlreader=shared"
  "--enable-xmlwriter=shared"
  "--with-zip=shared"
)

cd "${BUILD_SOURCE}"

if [[ ! -x ./configure ]]; then
  ./buildconf --force
fi

echo "configuring dynamic PHP ${PHP_VERSION}"
"${CONFIGURE[@]}"

JOBS="${PHPVM_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
echo "building dynamic PHP ${PHP_VERSION} with ${JOBS} jobs"
make -j"${JOBS}"
make install

PHP_BIN="${INSTALL_DIR}/bin/php"
if [[ ! -x "${PHP_BIN}" ]]; then
  echo "error: build did not produce ${PHP_BIN}" >&2
  exit 1
fi

VERSION_OUTPUT="$("${PHP_BIN}" -n -v)"
VERSION_LINE="${VERSION_OUTPUT%%$'\n'*}"
if [[ "${VERSION_LINE}" != *"PHP ${PHP_VERSION}"* ]]; then
  echo "error: built PHP version mismatch" >&2
  echo "  expected patch: ${PHP_VERSION}" >&2
  echo "  got: ${VERSION_LINE}" >&2
  exit 1
fi

EXT_BUILD_DIR="$("${PHP_BIN}" -n -r 'echo ini_get("extension_dir");')"
if [[ ! -d "${EXT_BUILD_DIR}" ]]; then
  echo "error: extension build directory not found: ${EXT_BUILD_DIR}" >&2
  exit 1
fi

mkdir -p "${STAGING}/bin" "${STAGING}/ext" "${STAGING}/etc/conf.d" "${STAGING}/etc/profiles" "${STAGING}/metadata"
cp "${INSTALL_DIR}/bin/php" "${STAGING}/bin/php"

shopt -s nullglob
for file in "${EXT_BUILD_DIR}"/*.so; do
  cp "${file}" "${STAGING}/ext/"
done

if [[ "${PHPVM_SKIP_XDEBUG:-0}" != "1" ]]; then
  XDEBUG_WORK="${WORK_DIR}/xdebug-${XDEBUG_VERSION}"
  XDEBUG_ARCHIVE="${WORK_DIR}/xdebug-${XDEBUG_VERSION}.tgz"
  echo "building Xdebug ${XDEBUG_VERSION}"
  curl -fsSL "https://xdebug.org/files/xdebug-${XDEBUG_VERSION}.tgz" -o "${XDEBUG_ARCHIVE}"
  tar -C "${WORK_DIR}" -xzf "${XDEBUG_ARCHIVE}"
  cd "${XDEBUG_WORK}"
  "${INSTALL_DIR}/bin/phpize"
  ./configure --with-php-config="${INSTALL_DIR}/bin/php-config"
  XDEBUG_JOBS="${JOBS}"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    XDEBUG_JOBS=1
  fi
  if ! make -j"${XDEBUG_JOBS}"; then
    if [[ ! -f "modules/xdebug.so" ]]; then
      exit 1
    fi
    echo "warning: Xdebug make returned a non-zero status after producing modules/xdebug.so" >&2
  fi
  cp "modules/xdebug.so" "${STAGING}/ext/xdebug.so"
  cd "${BUILD_SOURCE}"
fi

cat > "${STAGING}/etc/php.ini" <<EOF
; Base php.ini for phpvm dynamic runtime.
; phpvm sets PHPRC to etc/ and PHP_INI_SCAN_DIR to etc/conf.d.
extension_dir = "${STAGING}/ext"
display_errors = On
error_reporting = E_ALL
EOF

cat > "${STAGING}/etc/conf.d/00-default.ini" <<EOF
; Required for bundled Composer and secure PHAR workflows.
extension=${STAGING}/ext/openssl.so
extension=${STAGING}/ext/phar.so
extension=${STAGING}/ext/mbstring.so
EOF

PHP_INFO="$("${PHP_BIN}" -n -i)"
ABI="$(printf '%s\n' "${PHP_INFO}" | awk -F'=> ' '/^PHP API =>/ {print $2}')"
EXT_API="$(printf '%s\n' "${PHP_INFO}" | awk -F'=> ' '/^PHP Extension =>/ {print $2}')"
ZEND_EXT_API="$(printf '%s\n' "${PHP_INFO}" | awk -F'=> ' '/^Zend Extension =>/ {print $2}')"

jq -n \
  --arg php "${PHP_VERSION}" \
  --arg abi "${ABI}" \
  --arg extension_api "${EXT_API}" \
  --arg zend_extension_api "${ZEND_EXT_API}" \
  '{
    php: $php,
    runtime_type: "dynamic",
    thread_safety: "nts",
    abi: $abi,
    extension_api: $extension_api,
    zend_extension_api: $zend_extension_api
  }' > "${STAGING}/metadata/runtime.json"

"${PHP_BIN}" -n -v
echo "dynamic PHP ready: ${STAGING}"
