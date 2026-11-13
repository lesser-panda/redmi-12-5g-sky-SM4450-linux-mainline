#!/bin/bash
# SPDX-License-Identifier: MIT
# Download and verify the third-party inputs pinned in tools/sources.lock into sources/ (kernel tarball, cross toolchain,
# sky-linux shim, audioreach topology sources, payload-dumper-go). Nothing is executed from the downloads.
# Usage: tools/fetch-sources.sh [--rootfs]   (safe to re-run; verified files are kept; --rootfs adds the WiFi driver, fw-api headers and evdi)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
mkdir -p sources/dl
lock() { awk -F'|' -v n="$1" '{gsub(/^ +| +$/,"",$1)} $1==n {gsub(/^ +| +$/,"",$3); gsub(/^ +| +$/,"",$4); print $3 " " $4}' tools/sources.lock; }
fetch_tar() {  # name file
  read -r url pin < <(lock "$1"); want=${pin#sha256 }; f=sources/dl/$2
  if [ ! -f "$f" ] || [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$want" ]; then
    echo "download $1"; curl -fL --retry 3 -sS -o "$f.part" "$url"; mv "$f.part" "$f"
  fi
  [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$want" ] || { echo "sha256 mismatch for $f" >&2; exit 1; }
  echo "ok  $1 ($want)"
}
fetch_git() {  # name dir
  read -r url pin < <(lock "$1"); want=${pin#commit }
  [ -d "sources/$2/.git" ] || git clone --quiet "$url" "sources/$2"
  git -C "sources/$2" cat-file -e "$want^{commit}" 2>/dev/null || git -C "sources/$2" fetch --quiet origin
  git -C "sources/$2" checkout --quiet "$want"
  echo "ok  $1 (commit $want)"
}
fetch_tar linux-7.3 linux-7.3.tar.xz
fetch_tar toolchain toolchain.tar.xz
fetch_tar payload-dumper-go payload-dumper-go.tar.gz
fetch_git sky-linux sky-linux
fetch_git audioreach-topology audioreach-topology
[ -d sources/toolchain ] || { mkdir -p sources/toolchain; tar -xf sources/dl/toolchain.tar.xz -C sources/toolchain; }
[ -x sources/payload-dumper-go/payload-dumper-go ] || { mkdir -p sources/payload-dumper-go; tar -xzf sources/dl/payload-dumper-go.tar.gz -C sources/payload-dumper-go; }
# Alpine signing key (trust anchor for tools/apk-fetch.py); the pinned hash is the one the project used
mkdir -p sources/dl-alpine-keys; K=sources/dl-alpine-keys/alpine-devel@lists.alpinelinux.org-616ae350.rsa.pub
[ -f "$K" ] || curl -fsSL -o "$K" https://alpinelinux.org/keys/alpine-devel@lists.alpinelinux.org-616ae350.rsa.pub
[ "$(sha256sum "$K" | cut -d' ' -f1)" = d11f6b21c61b4274e182eb888883a8ba8acdbf820dcc7a6d82a7d9fc2fd2836d ] || { echo "alpine key hash mismatch" >&2; exit 1; }
echo "ok  alpine signing key"
if [ "${1:-}" = --rootfs ]; then
  fetch_git sky-qcacld sky-qcacld
  fetch_git evdi evdi-src/evdi
  read -r url pin < <(lock fw-api); want=${pin#commit }; want=${want%% *}
  if [ ! -d sources/dl-fwapi/repo/.git ]; then
    mkdir -p sources/dl-fwapi; git clone --quiet --filter=blob:none --sparse "$url" sources/dl-fwapi/repo
    git -C sources/dl-fwapi/repo sparse-checkout set fw-api
  fi
  git -C sources/dl-fwapi/repo checkout --quiet "$want"; echo "ok  fw-api (commit $want)"
fi
echo "sources ready"
