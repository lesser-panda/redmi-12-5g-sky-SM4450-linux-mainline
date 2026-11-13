#!/bin/bash
# SPDX-License-Identifier: MIT
# Stage the initramfs tree (busybox, dropbear, init, firmware) and write out/initramfs.list for CONFIG_INITRAMFS_SOURCE.
# Alpine packages are verified by tools/apk-fetch.py (signature chain) and only unpacked with tar, never executed on the host.
# Inputs: vendor/fw/* (tools/extract-vendor-files.sh), an ssh public key (SSH_PUBKEY, default vendor/ssh/id_ed25519.pub; generated if missing).
# Env: AUTOROOT=1 (default) builds the hands-free marker /etc/autoroot; AUTOROOT=0 leaves it out.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
need() { [ -e "$1" ] || { echo "missing $1 (run tools/extract-vendor-files.sh)" >&2; exit 1; }; }
for f in a630_sqe.fw gen6_3_26_0_zap.mbn focaltech_ts_fw_.bin bt/cmbtfw13.tlv bt/cmnv13.bin bt/cmnv13s.bin bt/cmnv13t.bin modem/adsp.mdt modem/adrastea/wpss.mdt; do need vendor/fw/$f; done
[ -d sources/dl-alpine-keys ] || { echo "run tools/fetch-sources.sh first" >&2; exit 1; }
python3 -I tools/apk-fetch.py sources/dl-rootfs busybox-static dropbear busybox-extras
T=out/initramfs-root; rm -rf "$T"; mkdir -p $T/{bin,sbin,lib,usr/lib,usr/bin,usr/sbin,etc,dev,proc,sys,tmp,run,root/.ssh,var/empty,mnt}
for p in sources/dl-rootfs/*.apk; do tar -xzf "$p" -C $T --warning=no-unknown-keyword 2>/dev/null || true; done
rm -f $T/.PKGINFO $T/.SIGN* $T/.post-* $T/.pre-*
install -m755 $T/bin/busybox.static $T/bin/busybox 2>/dev/null || install -m755 "$(ls $T/usr/bin/busybox.static $T/bin/busybox.static 2>/dev/null | head -1)" $T/bin/busybox
ln -sf busybox $T/bin/sh
install -m755 initramfs/init $T/init
[ "${AUTOROOT:-1}" = 1 ] && touch $T/etc/autoroot
printf 'root:x:0:0:root:/root:/bin/sh\n' > $T/etc/passwd; printf 'root:x:0:\n' > $T/etc/group; printf '/bin/sh\n' > $T/etc/shells
# firmware (vendor files stay in the image only; the kernel binary carries just the audio topology and the amplifier preset)
F=$T/lib/firmware; mkdir -p $F/qcom/sm4450 $F/focaltech $F/qca $F/adrastea
install -m644 vendor/fw/a630_sqe.fw $F/qcom/a630_sqe.fw
install -m644 vendor/fw/gen6_3_26_0_zap.mbn $F/qcom/sm4450/a613_zap.mbn
install -m644 vendor/fw/focaltech_ts_fw_.bin $F/focaltech/ft8720-sky.bin
for f in cmbtfw13.tlv cmnv13.bin cmnv13s.bin cmnv13t.bin; do install -m644 vendor/fw/bt/$f $F/qca/$f; done
install -m644 vendor/fw/modem/adsp.mdt vendor/fw/modem/adsp.b[0-9][0-9] $F/adrastea/
install -m644 vendor/fw/modem/adrastea/wpss.mdt vendor/fw/modem/adrastea/wpss.b[0-9][0-9] $F/adrastea/
# ssh access: your public key
K=${SSH_PUBKEY:-vendor/ssh/id_ed25519.pub}
if [ ! -f "$K" ]; then mkdir -p vendor/ssh; ssh-keygen -q -t ed25519 -N '' -C sky-mainline -f vendor/ssh/id_ed25519; K=vendor/ssh/id_ed25519.pub; echo "generated an ssh key pair in vendor/ssh/"; fi
install -m600 "$K" $T/root/.ssh/authorized_keys; chmod 700 $T/root/.ssh
python3 -I tools/gen-initramfs-list.py $T > out/initramfs.list
printf 'nod /dev/console 0600 0 0 c 5 1\nnod /dev/null 0666 0 0 c 1 3\n' >> out/initramfs.list
echo "initramfs staged: out/initramfs.list ($(wc -l < out/initramfs.list) entries)"
