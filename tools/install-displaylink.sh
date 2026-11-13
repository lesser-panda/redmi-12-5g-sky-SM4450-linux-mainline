#!/bin/sh
# SPDX-License-Identifier: MIT
# E031: install the Synaptics DisplayLink userspace on a RUNNING phone (live update; a fresh rootfs gets the same files through tools/push-debian.sh).
# DisplayLinkManager 6.4.0 is proprietary (the user downloaded it and accepted the licence), kept in vendor/displaylink/ only. No dkms/linux-headers:
# the kernel module is our own out/evdi/evdi.ko (tools/build-evdi.sh), loaded with insmod by the displaylink-driver unit. Re-runnable.
# Usage: HOST=<phone-ip> tools/install-displaylink.sh
# First run: libevdi.so is built on the phone from the vendor-bundled library (needs build-essential libdrm-dev pkg-config there) and copied back to
# vendor/displaylink/aarch64/ so that later installs and rootfs builds need no compiler.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
HOST=${HOST:-192.168.7.1}
E=vendor/displaylink/x/evdi-bundled; L=vendor/displaylink/aarch64/libevdi.so
SSHO="-q -i vendor/ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=6"
R() { ssh $SSHO root@$HOST "$@"; }
if [ ! -e $L ]; then
  [ -e $E/library/Makefile ] || { echo "missing $E/library (extract the vendor .run payload first)" >&2; exit 2; }
  R 'rm -rf /root/dlbuild && mkdir -p /root/dlbuild'
  tar -C $E -cf - library module/evdi_drm.h | R 'tar -C /root/dlbuild -xf -'
  R 'sh -s' <<'REMOTE'
set -e
export DEBIAN_FRONTEND=noninteractive
dpkg -s build-essential libdrm-dev pkg-config >/dev/null 2>&1 || apt-get install -y -qq build-essential libdrm-dev pkg-config
make -C /root/dlbuild/library -j"$(nproc)" >/root/dlbuild/build.log 2>&1 || { tail -20 /root/dlbuild/build.log; exit 1; }
REMOTE
  mkdir -p vendor/displaylink/aarch64
  scp -q $(echo $SSHO | sed 's/-q //; s/-o ConnectTimeout=6//') root@$HOST:/root/dlbuild/library/libevdi.so $L
fi
tools/displaylink-stage.sh
R 'rm -rf /root/dlinst && mkdir -p /root/dlinst'
R 'tar -C /root/dlinst -xf -' < vendor/displaylink/stage.tar
R 'bash /root/dlinst/install-target.sh /root/dlinst'
echo "done. Plug the dock (or: udevadm trigger --action=add on its usb device); then: journalctl -u displaylink-driver -f"
