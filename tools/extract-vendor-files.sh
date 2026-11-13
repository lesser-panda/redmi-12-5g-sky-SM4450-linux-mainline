#!/bin/bash
# SPDX-License-Identifier: MIT
# Collect the proprietary files the build needs from YOUR OWN phone and the PixelOS ROM it runs. Nothing is downloaded from
# anywhere except what you pass in; the files stay in vendor/ (git-ignored) and must never be published.
#
#   tools/extract-vendor-files.sh --rom PixelOS_sky-14.0-20240922-0137.zip  (--from-phone | --modem modem_a.img --bluetooth bluetooth_a.img)
#
#  --rom FILE        the ROM zip (sha256 is checked). Gives vendor_boot, dtbo and /vendor/firmware (GPU, touch, FS1599).
#  --from-phone      read modem_a and bluetooth_a from the phone over adb (needs root, e.g. Magisk; read-only dd). Uses $ANDROID_SERIAL or the only device.
#  --modem/--bluetooth  use existing partition dumps instead.
# Result: vendor/rom/{vendor_boot.img,dtbo.img,recovery.img}, vendor/fw/{a630_sqe.fw,...}, vendor/fw/modem/*, vendor/fw/bt/*; every file is checked
# against tools/vendor-files.sha256 (hashes of the files the project was tested with; a mismatch is reported, not fatal).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
ROM=; MODEM=; BT=; PHONE=0
while [ $# -gt 0 ]; do case $1 in --rom) ROM=$2; shift 2;; --modem) MODEM=$2; shift 2;; --bluetooth) BT=$2; shift 2;; --from-phone) PHONE=1; shift;; *) echo "unknown option $1" >&2; exit 2;; esac; done
[ -n "$ROM" ] && [ -f "$ROM" ] || { sed -n 3,14p "$0" | sed 's/^# \?//'; exit 2; }
for c in 7z debugfs; do command -v $c >/dev/null || { echo "need $c" >&2; exit 1; }; done
PDG=sources/payload-dumper-go/payload-dumper-go; [ -x "$PDG" ] || PDG=$(command -v payload-dumper-go || true); [ -n "$PDG" ] || { echo "run tools/fetch-sources.sh (payload-dumper-go) first" >&2; exit 1; }
want=$(awk '/PixelOS ROM/ {print $NF}' tools/sources.lock); got=$(sha256sum "$ROM" | cut -d' ' -f1)
[ "$got" = "$want" ] || { echo "ROM sha256 $got does not match the tested ROM ($want); stop (other builds may carry other firmware)" >&2; exit 1; }
mkdir -p vendor/rom vendor/fw/modem vendor/fw/bt vendor/work
echo "== ROM partitions (vendor, vendor_boot, dtbo, recovery)"
"$PDG" -p vendor,vendor_boot,dtbo,recovery -o vendor/work "$ROM" >/dev/null
P=$(find vendor/work -name vendor.img | head -1); D=$(dirname "$P")
cp "$D/vendor_boot.img" "$D/dtbo.img" "$D/recovery.img" vendor/rom/
for f in a630_sqe.fw gen6_3_26_0_zap.mbn focaltech_ts_fw_.bin fs1599.fsm; do
  debugfs -R "dump /firmware/$f vendor/fw/$f" "$P" >/dev/null 2>&1 || { echo "missing /firmware/$f in vendor.img" >&2; exit 1; }
done
rm -rf vendor/work
if [ $PHONE = 1 ]; then
  command -v adb >/dev/null || { echo "adb not found" >&2; exit 1; }
  echo "== reading modem_a and bluetooth_a from the phone (read-only)"
  for p in modem_a bluetooth_a; do adb exec-out "su -c 'dd if=/dev/block/by-name/$p bs=1M 2>/dev/null'" > vendor/work-$p.img; done
  MODEM=vendor/work-modem_a.img; BT=vendor/work-bluetooth_a.img
fi
[ -n "$MODEM" ] && [ -n "$BT" ] || echo "NOTE: no modem/bluetooth dump given; WiFi, ADSP and Bluetooth firmware are missing" >&2
if [ -n "$MODEM" ]; then
  7z x -y -ovendor/work-modem "$MODEM" 'image/adsp.*' 'image/adrastea/*' >/dev/null 2>&1 || true
  # ADSP: split image adsp.mdt + adsp.bNN; WPSS (WiFi processor) split image, WiFi board data (bdwlan*) and regdb.bin live in image/adrastea/
  cp vendor/work-modem/image/adsp.* vendor/fw/modem/
  mkdir -p vendor/fw/modem/adrastea; cp vendor/work-modem/image/adrastea/* vendor/fw/modem/adrastea/
fi
if [ -n "$BT" ]; then
  7z x -y -ovendor/work-bt "$BT" >/dev/null 2>&1 || true
  for f in cmbtfw13.tlv cmnv13.bin cmnv13s.bin cmnv13t.bin; do cp vendor/work-bt/image/$f vendor/fw/bt/; done
fi
rm -rf vendor/work-modem vendor/work-bt vendor/work-modem_a.img vendor/work-bluetooth_a.img
echo "== checking against tools/vendor-files.sha256"
bad=0; while read -r h n; do f=$(find vendor -type f -name "$n" | head -1); if [ -z "$f" ]; then echo "  missing  $n"; bad=1
  elif [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$h" ]; then echo "  DIFFERS  $f"; bad=1; fi; done < tools/vendor-files.sha256
[ $bad = 0 ] && echo "all files match the tested set" || echo "some files are missing or differ from the tested set (see above)"
