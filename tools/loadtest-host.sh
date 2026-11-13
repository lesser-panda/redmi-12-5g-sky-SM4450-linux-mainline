#!/bin/bash
# SPDX-License-Identifier: MIT
# E032 laptop-side companion of tools/loadtest.sh: every 20 s checks the phone over USB (192.168.7.1) and WiFi ($WIFI_IP, the phone's address on your WiFi), every ~80 s moves
# ~100 MB over the USB network (ssh, dwc3 gadget path), logs to vendor/e032/host-<time>.log, exits when the phone's SUMMARY.txt exists
# (test finished) or when both paths failed 6 times in a row (phone down; exit code 2). Usage: tools/loadtest-host.sh [OUTDIR_ON_PHONE]
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
WIFI_IP=${WIFI_IP:?set WIFI_IP to the phone address on your WiFi network}
OUTDIR=${1:-}; LOG=vendor/e032/host-$(date +%Y%m%d-%H%M).log; mkdir -p vendor/e032
SSHO="-q -i vendor/ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2"
echo "$(date +%T) start phone-out=$OUTDIR" | tee -a "$LOG"
fails=0; n=0; usbfail=0; wififail=0; streams=0; streamfail=0
while :; do
  n=$((n+1)); u=ok; w=ok
  ssh $SSHO root@192.168.7.1 'cut -d" " -f1-3 /proc/loadavg' > /tmp/lt-usb.$$ 2>/dev/null || { u=FAIL; usbfail=$((usbfail+1)); }
  ssh $SSHO root@$WIFI_IP 'cat /sys/class/power_supply/battery/capacity' > /tmp/lt-wifi.$$ 2>/dev/null || { w=FAIL; wififail=$((wififail+1)); }
  echo "$(date +%T) usb=$u wifi=$w load=$(cat /tmp/lt-usb.$$ 2>/dev/null) cap=$(cat /tmp/lt-wifi.$$ 2>/dev/null) usbfails=$usbfail wififails=$wififail streams=$streams streamfails=$streamfail" >> "$LOG"
  if [ $u = FAIL ] && [ $w = FAIL ]; then fails=$((fails+1)); else fails=0; fi
  [ $fails -ge 6 ] && { echo "$(date +%T) EXIT: phone unreachable on both paths 6x" | tee -a "$LOG"; exit 2; }
  if [ $((n%4)) = 0 ] && [ $u = ok ]; then
    streams=$((streams+1))
    b=$(ssh $SSHO root@192.168.7.1 'head -c 100000000 /dev/zero' 2>/dev/null | wc -c); [ "$b" = 100000000 ] || { streamfail=$((streamfail+1)); echo "$(date +%T) stream short: $b bytes" >> "$LOG"; }
  fi
  if [ -n "$OUTDIR" ] && ssh $SSHO root@$WIFI_IP "test -s $OUTDIR/SUMMARY.txt" 2>/dev/null; then echo "$(date +%T) test finished (SUMMARY present)" | tee -a "$LOG"; exit 0; fi
  sleep 20
done
