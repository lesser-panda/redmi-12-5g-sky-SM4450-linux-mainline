#!/bin/bash
# SPDX-License-Identifier: MIT
# Write the built boot image into the recovery_b partition so the phone starts Linux hands-free (adb reboot recovery) and keeps Android as the default boot.
# This is the only command in this repository that writes to the phone's storage. Read docs/en/INSTALLING.md and docs/en/RECOVERY.md first.
#   - only recovery_b is written (the PixelOS slot B recovery); boot, vendor_boot, dtbo and the A slot are not touched
#   - the current content is saved to vendor/backup/recovery_b-<time>.img first (via adb + root) and its hash is printed
#   - after the write the partition is read back and compared with the image
# Usage: tools/flash-recovery-b.sh [out/boot/sky-recovery_b-v2.img]     (phone running Android with USB debugging and root, battery above 50 %)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
IMG=${1:-out/boot/sky-recovery_b-v2.img}; [ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }
SIZE=$(stat -c %s "$IMG")
[ "$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')" = _b ] || { echo "the phone is not running slot B; this recipe was only tested on slot B" >&2; exit 1; }
BAT=$(adb shell "su -c 'cat /sys/class/power_supply/battery/capacity'" | tr -d '\r'); echo "battery $BAT %"; [ "$BAT" -gt 50 ] || { echo "charge the phone above 50 % first" >&2; exit 1; }
mkdir -p vendor/backup; B=vendor/backup/recovery_b-$(date +%Y%m%dT%H%M%S).img
adb exec-out "su -c 'dd if=/dev/block/by-name/recovery_b bs=1M 2>/dev/null'" > "$B"; echo "saved current recovery_b: $B  sha256 $(sha256sum "$B" | cut -d' ' -f1)"
echo "image: $IMG  $SIZE bytes  sha256 $(sha256sum "$IMG" | cut -d' ' -f1)"
read -r -p "Write this to recovery_b? [type yes] " a; [ "$a" = yes ] || { echo aborted; exit 1; }
adb reboot bootloader
for i in $(seq 1 30); do fastboot devices | grep -q . && break; sleep 2; done
fastboot flash recovery_b "$IMG"
fastboot reboot
adb wait-for-device
for i in $(seq 1 60); do [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break; sleep 3; done
got=$(adb shell "su -c 'head -c $SIZE /dev/block/by-name/recovery_b | sha256sum'" | cut -d' ' -f1)
[ "$got" = "$(sha256sum "$IMG" | cut -d' ' -f1)" ] && echo "readback matches" || { echo "READBACK MISMATCH: reflash, or restore $B" >&2; exit 1; }
echo "Done. Start Linux with: adb reboot recovery     Back to Android from Linux: systemctl reboot (or reboot)"
