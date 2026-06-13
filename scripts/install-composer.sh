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

if [[ ! -x "${PHP}" ]]; then
  echo "error: ${PHP} not found — build PHP first" >&2
  exit 1
fi

mkdir -p "${BIN_DIR}"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

curl -fsSL "https://getcomposer.org/download/${VERSION}/composer.phar" -o "${TMP}"
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
"${PHP}" "${BIN_DIR}/composer.phar" --version
echo "composer ${VERSION} installed in ${BIN_DIR}"