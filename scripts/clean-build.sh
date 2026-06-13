#!/usr/bin/env bash
# Remove StaticPHP working trees (never commit these).
#
# Usage:
#   clean-build.sh              # repo root + every builds/<version>/
#   clean-build.sh 8.3.31       # one version only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

clean_dir() {
  local base="$1"
  [[ -d "${base}" ]] || return 0
  rm -rf \
    "${base}/.spc" \
    "${base}/.spc.cache.php" \
    "${base}/buildroot" \
    "${base}/source" \
    "${base}/downloads" \
    "${base}/pkgroot" \
    "${base}/log"
}

if [[ $# -eq 1 ]]; then
  clean_dir "${ROOT}/builds/${1}"
  echo "cleaned builds/${1}"
  exit 0
fi

clean_dir "${ROOT}"
for version_dir in "${ROOT}"/builds/[0-9]*.[0-9]*.[0-9]*; do
  [[ -d "${version_dir}" ]] || continue
  clean_dir "${version_dir}"
done
echo "cleaned repo root and all builds/<version>/ working trees"
