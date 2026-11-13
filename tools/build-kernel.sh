#!/bin/bash
# SPDX-License-Identifier: MIT
# Build everything that goes onto the phone's boot partition, from a clean checkout:
#   1. sources/linux-7.3  = pinned Linux 7.3 tarball + kernel/patches (git apply)       [skipped when already prepared]
#   2. firmware built into the kernel: AudioReach topology (tools/build-topology.sh) and the FS1599 amplifier preset (vendor/fw)
#   3. initramfs (tools/build-initramfs.sh), kernel config (kernel/sky_defconfig), Image
#   4. device tree (dts/sm4450-xiaomi-sky.dts) compiled with the kernel's own dtc
#   5. sky-linux shim + payload -> Android boot image v4   out/boot/sky-boot-v4.img  (RAM boot with tools/boot-ram.sh)
#   6. if vendor/rom exists: the same payload as boot image v2 for recovery_b  out/boot/sky-recovery_b-v2.img (tools/flash-recovery-b.sh)
# Needs the host tools listed in docs/en/BUILDING.md (gcc, make, flex, bison, bc, libelf, openssl headers, m4, alsatplg, python3, mkbootimg, unpack_bootimg).
# Run tools/fetch-sources.sh and tools/extract-vendor-files.sh first.   Env: JOBS (default nproc), AUTOROOT (see build-initramfs.sh)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
export PATH="$ROOT/sources/toolchain/gcc-15.2.0-nolibc/aarch64-linux/bin:$PATH"
command -v aarch64-linux-gcc >/dev/null || { echo "toolchain missing: run tools/fetch-sources.sh" >&2; exit 1; }
K=sources/linux-7.3; O=$ROOT/out/kbuild; JOBS=${JOBS:-$(nproc)}
# 1. kernel tree
if [ ! -f $K/.sky-patched ]; then
  [ -d $K ] && { echo "$K exists but is not prepared by this script; remove it first" >&2; exit 1; }
  echo "== extracting Linux 7.3 and applying kernel/patches"
  tar -xf sources/dl/linux-7.3.tar.xz -C sources
  for p in kernel/patches/*.patch; do (cd $K && git apply --whitespace=nowarn "$ROOT/$p") || { echo "patch failed: $p" >&2; exit 1; }; done
  sha256sum kernel/patches/*.patch > $K/.sky-patched
fi
# 2. built-in firmware
echo "== topology and amplifier preset"
tools/build-topology.sh
[ -f vendor/fw/fs1599.fsm ] || { echo "missing vendor/fw/fs1599.fsm (run tools/extract-vendor-files.sh)" >&2; exit 1; }
mkdir -p out/extra-fw/foursemi; cp vendor/fw/fs1599.fsm out/extra-fw/foursemi/
# 3. initramfs, config, kernel
echo "== initramfs"; tools/build-initramfs.sh
cp kernel/sky_defconfig $K/arch/arm64/configs/sky_defconfig
mkdir -p $O
MK="make -C $K -j$JOBS ARCH=arm64 CROSS_COMPILE=aarch64-linux- O=$O"
$MK sky_defconfig >/dev/null
$K/scripts/config --file $O/.config --set-str INITRAMFS_SOURCE "$ROOT/out/initramfs.list" \
  --set-str EXTRA_FIRMWARE_DIR "$ROOT/out/extra-fw" --set-str EXTRA_FIRMWARE "qcom/sm8450/Redmi-12-5G-tplg.bin foursemi/fs1599.fsm" \
  -d INITRAMFS_COMPRESSION_GZIP -e INITRAMFS_COMPRESSION_NONE  
$MK olddefconfig >/dev/null
echo "== kernel (this takes a while)"
$MK Image
# 4. device tree
mkdir -p out/dts out/boot
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I $K/include -I $K/arch/arm64/boot/dts/qcom \
    -I $K/scripts/dtc/include-prefixes dts/sm4450-xiaomi-sky.dts -o out/dts/sky.pre.dts
$O/scripts/dtc/dtc -I dts -O dtb -@ -Wno-unit_address_vs_reg -o out/dts/sky.dtb out/dts/sky.pre.dts
# 5. shim + payload -> boot image v4
rm -rf out/shim-build && mkdir -p out/shim-build/shim/out && cp -r sources/sky-linux/shim sources/sky-linux/tools out/shim-build/
python3 -I out/shim-build/tools/mklinuxpayload.py $O/arch/arm64/boot/Image out/dts/sky.dtb out/shim-build/shim/out/payload.bin --load 0xc0000000
(cd out/shim-build/shim && CC=aarch64-linux-gcc OBJCOPY=aarch64-linux-objcopy NM=aarch64-linux-nm READELF=aarch64-linux-readelf ./build-sky.sh out/payload.bin)
cp out/shim-build/shim/out/sky-shim-boot-v4.img out/boot/sky-boot-v4.img
cp $O/arch/arm64/boot/Image out/boot/Image; cp out/dts/sky.dtb out/boot/sky.dtb
# 6. recovery_b image (boot image header v2 + the phone's own vendor_boot DTB and dtbo; see docs/en/ARCHITECTURE.md for why)
if [ -f vendor/rom/vendor_boot.img ] && [ -f vendor/rom/dtbo.img ]; then
  W=out/recovery-v2-work; rm -rf $W; mkdir -p $W/v4 $W/vb
  unpack_bootimg --boot_img out/boot/sky-boot-v4.img --out $W/v4 >/dev/null
  unpack_bootimg --boot_img vendor/rom/vendor_boot.img --out $W/vb >/dev/null
  mkbootimg --header_version 2 --kernel $W/v4/kernel --ramdisk $W/v4/ramdisk --dtb $W/vb/dtb --recovery_dtbo vendor/rom/dtbo.img \
    --base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --tags_offset 0x100 --dtb_offset 0x1f00000 --pagesize 4096 \
    --os_version 14.0.0 --os_patch_level 2024-09 --cmdline "console=tty0" -o out/boot/sky-recovery_b-v2.img
  rm -rf $W
fi
(cd out/boot && sha256sum * | tee SHA256SUMS)
echo "done: out/boot/"
