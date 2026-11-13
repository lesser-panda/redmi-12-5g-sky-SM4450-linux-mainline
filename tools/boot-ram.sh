#!/bin/bash
# SPDX-License-Identifier: MIT
# Boot the built kernel from RAM only (nothing is written to the phone) and wait for the USB network.
# The phone must be in fastboot mode (from Android: `adb reboot bootloader`). After a reboot it returns to the normal Android boot.
# Usage: tools/boot-ram.sh [out/boot/sky-boot-v4.img]      then: ssh -i vendor/ssh/id_ed25519 root@192.168.7.1
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
IMG=${1:-out/boot/sky-boot-v4.img}; [ -f "$IMG" ] || { echo "missing $IMG (run tools/build-kernel.sh)" >&2; exit 1; }
fastboot devices | grep -q . || { echo "no device in fastboot mode (adb reboot bootloader)" >&2; exit 1; }
fastboot boot "$IMG"
echo "waiting for 192.168.7.1 ..."
for i in $(seq 1 60); do ping -c1 -W1 192.168.7.1 >/dev/null 2>&1 && { echo "up. ssh -i vendor/ssh/id_ed25519 root@192.168.7.1"; exit 0; }; sleep 2; done
echo "no answer after 2 minutes: the screen/serial may tell more (see docs/en/RECOVERY.md)" >&2; exit 1
