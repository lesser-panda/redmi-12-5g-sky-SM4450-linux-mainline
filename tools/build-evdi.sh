#!/bin/sh
# SPDX-License-Identifier: MIT
# E030: cross-build the DisplayLink evdi kernel module (GPL-2.0-only, sources/evdi-src/evdi, upstream DisplayLink/evdi) against out/kbuild, the tree of the CURRENT candidate.
# Run it AFTER the kernel build (tools/build-m20.sh): vermagic/symbol CRCs must match that tree. Compile + link only; nothing executes on the host.
# Usage: tools/build-evdi.sh   -> out/evdi/evdi.ko, log in out/evdi/build.log
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/sources/toolchain/gcc-15.2.0-nolibc/aarch64-linux/bin:$PATH"
K="$ROOT/out/kbuild"; S="$ROOT/sources/evdi-src/evdi/module"; OUT="$ROOT/out/evdi"
mkdir -p "$OUT"
[ -e "$K/include/config/kernel.release" ] || { echo "kernel tree $K is not prepared (build the kernel first)" >&2; exit 1; }
make -C "$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux- modules_prepare >"$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; exit 1; }
find "$S" -maxdepth 1 \( -name '*.o' -o -name '*.ko' -o -name '*.mod' -o -name '*.mod.c' -o -name modules.order -o -name Module.symvers -o -name '.*.cmd' -o -name 'evdi_detect.h*' \) -delete
{
  echo "kernel.release: $(cat "$K/include/config/kernel.release")"
  make -C "$K" M="$S" ARCH=arm64 CROSS_COMPILE=aarch64-linux- -j"$(nproc)" modules
} >>"$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; echo "BUILD FAILED, see $OUT/build.log" >&2; exit 1; }
cp -f "$S/evdi.ko" "$OUT/evdi.ko"
printf '%s  evdi.ko  %s\n' "$(sha256sum "$OUT/evdi.ko" | cut -c1-16)" "$(modinfo -F vermagic "$OUT/evdi.ko" 2>/dev/null)"
