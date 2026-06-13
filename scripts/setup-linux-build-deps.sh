#!/usr/bin/env bash
# Install distro packages needed for StaticPHP builds on Debian/Ubuntu/Mint.
# musl-wrapper is still installed by spc doctor (requires sudo).
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "skip: setup-linux-build-deps.sh is Linux-only"
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "error: apt-get not found — install build deps manually" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y \
  make bison re2c flex gperf \
  git autoconf automake autopoint \
  tar unzip gzip gcc g++ \
  bzip2 cmake patch xz-utils libtool debianutils \
  pkg-config curl ca-certificates jq

echo "linux build deps installed"
