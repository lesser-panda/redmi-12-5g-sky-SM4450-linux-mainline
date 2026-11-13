#!/bin/sh
# SPDX-License-Identifier: MIT
# E016: cross-build the third-party sky-qcacld modules (cnss_utils, wlan_firmware_service,
# icnss2, wlan) against out/kbuild (the tree the m14 Image was built from).
# Source: sources/sky-qcacld (sky-linux, GPL-2.0, authors preserved in-tree). Output is for private
# RAM-boot use only; nothing here executes on the host (compile + link only).
# Usage: tools/build-wifi-modules.sh        -> out/wifi-modules/*.ko, log in vendor/wifi/build.log
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/sources/toolchain/gcc-15.2.0-nolibc/aarch64-linux/bin:$PATH"
K="$ROOT/out/kbuild"
S="$ROOT/sources/sky-qcacld"
OUT="$ROOT/out/wifi-modules"
LOG="$ROOT/vendor/wifi/build.log"
# quiet the driver's debug traces (pr_err -> pr_debug) and the periodic RCPI error line; applied once, skipped when already present
if ! git -C "$S" apply --reverse --check "$ROOT/tools/qcacld-quiet-debug.patch" 2>/dev/null; then git -C "$S" apply "$ROOT/tools/qcacld-quiet-debug.patch"; fi
# fw-api headers (MiCode sky-t-oss 02e10575, sparse checkout in sources/dl-fwapi) are expected at src/fw-api
[ -e "$S/src/fw-api/fw/athdefs.h" ] || ln -sfn ../../dl-fwapi/repo/fw-api "$S/src/fw-api"
# Kbuild expects the icnss2 headers at <repo>/micode-sky-icnss2/include (original author layout)
[ -e "$S/micode-sky-icnss2/include" ] || ln -sfn src/icnss2 "$S/micode-sky-icnss2"
mkdir -p "$OUT" "$(dirname "$LOG")"
# stale products of an earlier failed run make kbuild report "No rule to make target cnss_utils.ko"
find "$S/src/icnss2" -maxdepth 1 \( -name "*.o" -o -name "*.mod" -o -name "*.mod.c" -o -name modules.order -o -name Module.symvers -o -name ".*.cmd" \) -delete
M() { make -C "$S/src/icnss2" -f port.mk KERNEL_SRC="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux- -j"$(nproc)" "$@"; }
{
  echo "kernel.release: $(cat "$K/include/config/kernel.release")"
  M dependencies
  M platform
  M WLAN_DIR="$S/src/qcacld-3.0" wlan
} >"$LOG" 2>&1 || { tail -40 "$LOG"; echo "BUILD FAILED, see $LOG" >&2; exit 1; }
for f in $(find "$S/src" -name '*.ko' -newer "$K/include/config/kernel.release"); do cp -f "$f" "$OUT/"; done
cd "$OUT"
for f in *.ko; do
  printf '%s  %s  %s\n' "$(sha256sum "$f" | cut -c1-12)" "$f" "$(modinfo -F vermagic "$f" 2>/dev/null)"
done
