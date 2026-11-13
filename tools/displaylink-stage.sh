#!/bin/sh
# SPDX-License-Identifier: MIT
# Host: pack everything the target needs for DisplayLink into vendor/displaylink/stage.tar (never committed or published: it contains the vendor
# DisplayLinkManager). Inputs, all checked: the vendor payload (vendor/displaylink/x/payload, extracted from the downloaded .run), libevdi.so
# (vendor/displaylink/aarch64/libevdi.so, built once from the vendor-bundled library by tools/install-displaylink.sh), out/evdi/evdi.ko
# (tools/build-evdi.sh, must match the kernel in the boot image) and our own rootfs/displaylink/ files.
# Used by tools/push-debian.sh (rootfs build) and tools/install-displaylink.sh (live phone).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
P=${1:-vendor/displaylink/x/payload}; L=vendor/displaylink/aarch64/libevdi.so; K=out/evdi/evdi.ko
for f in $P/aarch64-linux-gnu/DisplayLinkManager $P/aarch64-linux-gnu/libusb-1.0.so.0.6.0 $P/udev-installer.sh $L $K rootfs/displaylink/install-target.sh rootfs/displaylink/displaylink-driver.service rootfs/displaylink/sky-evdi.service; do
  [ -e "$f" ] || { echo "displaylink-stage: missing $f" >&2; exit 2; }
done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp $P/aarch64-linux-gnu/DisplayLinkManager $P/aarch64-linux-gnu/libusb-1.0.so.0.6.0 $P/udev-installer.sh $P/LICENSE $P/3rd_party_licences.txt $P/*.spkg "$T/"
cp $L $K rootfs/displaylink/install-target.sh rootfs/displaylink/displaylink-driver.service rootfs/displaylink/sky-evdi.service "$T/"
tar --owner=0 --group=0 -cf vendor/displaylink/stage.tar -C "$T" .
echo "stage: vendor/displaylink/stage.tar sha256 $(sha256sum vendor/displaylink/stage.tar | cut -c1-16)…  evdi.ko vermagic: $(strings -a $K | sed -n 's/^vermagic=//p' | head -1)"
