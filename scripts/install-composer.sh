#!/usr/bin/env bash
# Download Composer PHAR and install a bin/composer wrapper beside bin/php.
#
# Usage:
#   install-composer.sh <staging-dir> [composer-version]
#
# staging-dir must already contain bin/php (used to run the PHAR).
set -euo pipefail

usage() {
  echo "Usage: $0 <staging-dir> [composer-version]" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

STAGING="$1"
VERSION="${2:-$(cat "$(dirname "${BASH_SOURCE[0]}")/../builds/common/composer-version.txt")}"
PHP="${STAGING}/bin/php"
BIN_DIR="${STAGING}/bin"
PHP_ENV=()

if [[ ! -x "${PHP}" ]]; then
  echo "error: ${PHP} not found — build PHP first" >&2
  exit 1
fi

mkdir -p "${BIN_DIR}"
if [[ -d "${STAGING}/etc" ]]; then
  PHP_ENV+=(PHPRC="${STAGING}/etc")
fi
if [[ -d "${STAGING}/etc/conf.d" ]]; then
  PHP_ENV+=(PHP_INI_SCAN_DIR="${STAGING}/etc/conf.d")
fi
TMP="$(mktemp)"
SUM_TMP="$(mktemp)"
trap 'rm -f "${TMP}" "${SUM_TMP}"' EXIT

curl -fsSL "https://getcomposer.org/download/${VERSION}/composer.phar" -o "${TMP}"
curl -fsSL "https://getcomposer.org/download/${VERSION}/composer.phar.sha256sum" -o "${SUM_TMP}"

EXPECTED_SHA="$(awk '{print $1}' "${SUM_TMP}")"
if [[ ! "${EXPECTED_SHA}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "error: invalid Composer checksum for version ${VERSION}" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA="$(sha256sum "${TMP}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA="$(shasum -a 256 "${TMP}" | awk '{print $1}')"
else
  echo "error: sha256sum or shasum is required" >&2
  exit 1
fi

if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
  echo "error: Composer checksum mismatch for version ${VERSION}" >&2
  echo "  expected: ${EXPECTED_SHA}" >&2
  echo "  actual:   ${ACTUAL_SHA}" >&2
  exit 1
fi

mv "${TMP}" "${BIN_DIR}/composer.phar"
chmod 644 "${BIN_DIR}/composer.phar"

cat > "${BIN_DIR}/composer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${DIR}/php" "${DIR}/composer.phar" "$@"
EOF
chmod +x "${BIN_DIR}/composer"

# Wrapper invokes php; verify via the phar directly for clarity.
env "${PHP_ENV[@]}" "${PHP}" "${BIN_DIR}/composer.phar" --version
echo "composer ${VERSION} installed in ${BIN_DIR}"
