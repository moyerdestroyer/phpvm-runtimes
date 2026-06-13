#!/usr/bin/env bash
# Validate a staged runtime tree and produce a release tarball + sha256 sidecar.
#
# Usage:
#   package-runtime.sh <staging-dir> <php-version> <target> [output-dir]
#
# staging-dir must contain bin/php and bin/composer (executables).
# Output:
#   php-{version}-{target}.tar.gz
#   php-{version}-{target}.tar.gz.sha256
set -euo pipefail

usage() {
  echo "Usage: $0 <staging-dir> <php-version> <target> [output-dir]" >&2
  exit 1
}

[[ $# -ge 3 && $# -le 4 ]] || usage

STAGING="$(cd "$1" && pwd)"
PHP_VERSION="$2"
TARGET="$3"
OUT_DIR="${4:-$(pwd)}"

if [[ ! -d "${STAGING}/bin" ]]; then
  echo "error: staging dir missing bin/: ${STAGING}" >&2
  exit 1
fi

for bin in php composer; do
  if [[ ! -x "${STAGING}/bin/${bin}" ]]; then
    echo "error: missing executable ${STAGING}/bin/${bin}" >&2
    exit 1
  fi
done

# Smoke test PHP and catalog extensions before packaging.
"${STAGING}/bin/php" -v >/dev/null
"${STAGING}/bin/composer" -V >/dev/null
"$(dirname "${BASH_SOURCE[0]}")/verify-extensions.sh" "${STAGING}/bin/php"

ARCHIVE_NAME="php-${PHP_VERSION}-${TARGET}.tar.gz"
ROOT_NAME="php-${PHP_VERSION}-${TARGET}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PACK_ROOT="${WORK}/${ROOT_NAME}"
mkdir -p "${PACK_ROOT}/bin"
cp -a "${STAGING}/bin/php" "${PACK_ROOT}/bin/"
cp -a "${STAGING}/bin/composer" "${PACK_ROOT}/bin/"
if [[ -f "${STAGING}/bin/composer.phar" ]]; then
  cp -a "${STAGING}/bin/composer.phar" "${PACK_ROOT}/bin/"
fi

# Copy optional runtime deps (e.g. lib/) without following external symlinks.
if [[ -d "${STAGING}/lib" ]]; then
  cp -a "${STAGING}/lib" "${PACK_ROOT}/"
fi

mkdir -p "${OUT_DIR}"
ARCHIVE_PATH="${OUT_DIR}/${ARCHIVE_NAME}"

tar -C "${WORK}" -czf "${ARCHIVE_PATH}" "${ROOT_NAME}"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${ARCHIVE_PATH}" | awk '{print $1}' > "${ARCHIVE_PATH}.sha256"
else
  shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}' > "${ARCHIVE_PATH}.sha256"
fi

echo "packaged ${ARCHIVE_PATH}"
echo "checksum $(cat "${ARCHIVE_PATH}.sha256")"
