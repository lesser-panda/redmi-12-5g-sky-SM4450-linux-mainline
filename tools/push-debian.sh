#!/bin/bash
# SPDX-License-Identifier: MIT
# Host side: build a Debian trixie GNOME root in a tmpfs on the RAM-booted phone and switch PID 1 into it (systemd).
# Needs: the phone RAM-booted with the project initramfs (tools/boot-ram.sh; it provides the /run/switch-root hook), more than 5.7 GiB free RAM,
# out/rootfs-debian-stage1.tar (tools/build-debian-stage1.py after tools/deb-fetch.py), the WiFi modules (tools/build-wifi-modules.sh),
# vendor/wifi/credentials.txt (optional, ssid=/psk= lines, only copied into the phone's RAM or the new root) and your ssh key in vendor/ssh/.
# Without PERSIST=1 nothing is written to phone storage. Roughly 5 min push + 20-40 min second stage (dpkg unpack/configure of ~1000 packages on the phone).
# NOT re-run from a clean checkout since the repository was published; see docs/en/KNOWN-ISSUES.md.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
SSH="ssh -q -i vendor/ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8 root@192.168.7.1"
[ -f out/rootfs-debian-stage1.tar ] || python3 -I tools/build-debian-stage1.py
avail=$($SSH "awk '/MemAvailable/{print int(\$2/1024)}' /proc/meminfo")
echo "phone MemAvailable: ${avail} MiB"
[ "$avail" -gt 5700 ] || { echo "not enough free RAM (need > 5700 MiB; reboot into a fresh RAM boot)"; exit 1; }
$SSH "mountpoint -q /mnt/deb" && { echo "/mnt/deb already mounted: reboot into a fresh RAM boot instead of retrying on leftovers"; exit 1; }
$SSH "date -s @$(date +%s)" >/dev/null
$SSH 'touch /tmp/stay; mkdir -p /mnt/deb; mount -t tmpfs -o size=5600m tmpfs /mnt/deb'
cat out/rootfs-debian-stage1.tar | $SSH 'tar -xf - -C /mnt/deb'
# firmware + WiFi modules + vendor blobs the kernel loaded from the initramfs, so that userspace reloads (module insert, rebind) also find them
# (needs tools/extract-vendor-files.sh and tools/build-wifi-modules.sh; the modules must match the kernel in the boot image)
F=out/fw-debian; rm -rf $F; mkdir -p $F/lib/firmware/{qca,qcom/sm4450,focaltech,adrastea} $F/root/wifi
cp vendor/fw/modem/adrastea/* $F/lib/firmware/adrastea/
cp out/wifi-modules/*.ko $F/root/wifi/
for f in cmbtfw13.tlv cmnv13.bin cmnv13s.bin cmnv13t.bin; do install -m644 vendor/fw/bt/$f $F/lib/firmware/qca/$f; done
install -m644 vendor/fw/a630_sqe.fw $F/lib/firmware/qcom/a630_sqe.fw
install -m644 vendor/fw/gen6_3_26_0_zap.mbn $F/lib/firmware/qcom/sm4450/a613_zap.mbn
install -m644 vendor/fw/focaltech_ts_fw_.bin $F/lib/firmware/focaltech/ft8720-sky.bin
install -m644 vendor/fw/modem/adsp.mdt vendor/fw/modem/adsp.b[0-9][0-9] $F/lib/firmware/adrastea/
tar --owner=0 --group=0 -cf - -C $F . | $SSH 'tar -xf - -C /mnt/deb'
$SSH 'chmod 700 /mnt/deb/root'
cat vendor/ssh/id_ed25519.pub | $SSH 'cat > /mnt/deb/tmp/authorized_keys'
cat rootfs/sky-wifi-up | $SSH 'cat > /mnt/deb/tmp/sky-wifi-up'
cat rootfs/sky-wifi.service | $SSH 'cat > /mnt/deb/tmp/sky-wifi.service'
cat rootfs/sky-charge-limit | $SSH 'cat > /mnt/deb/tmp/sky-charge-limit'
cat rootfs/sky-charge-limit.service | $SSH 'cat > /mnt/deb/tmp/sky-charge-limit.service'
cat rootfs/sky-swapfile | $SSH 'cat > /mnt/deb/tmp/sky-swapfile'
cat rootfs/sky-swapfile.service | $SSH 'cat > /mnt/deb/tmp/sky-swapfile.service'
cat rootfs/sky-zram | $SSH 'cat > /mnt/deb/tmp/sky-zram'
cat rootfs/sky-zram.service | $SSH 'cat > /mnt/deb/tmp/sky-zram.service'
cat rootfs/90_sky-power.gschema.override | $SSH 'cat > /mnt/deb/tmp/90_sky-power.gschema.override'
cat rootfs/61-sky-battery.hwdb | $SSH 'cat > /mnt/deb/tmp/61-sky-battery.hwdb'
cat rootfs/10-sky-journal.conf | $SSH 'cat > /mnt/deb/tmp/10-sky-journal.conf'
# audio: UCM profile (the FS1599 amplifier is in the kernel, m24+)
tar --owner=0 --group=0 -cf - -C audio ucm2 | $SSH 'tar -xf - -C /mnt/deb/tmp'
cat rootfs/customize.sh | $SSH 'cat > /mnt/deb/tmp/customize.sh; chmod 755 /mnt/deb/tmp/customize.sh'
# DisplayLink (E031): optional, proprietary vendor files from vendor/displaylink; skipped with a warning if the inputs are missing
if tools/displaylink-stage.sh; then cat vendor/displaylink/stage.tar | $SSH 'cat > /mnt/deb/tmp/dlstage.tar'; else echo "WARNING: building the root WITHOUT DisplayLink support (see docs/en/DOCK.md)"; fi
$SSH 'mount --rbind /dev /mnt/deb/dev; mount -t proc proc /mnt/deb/proc; mount -t sysfs sysfs /mnt/deb/sys; mount -t tmpfs tmpfs /mnt/deb/run; df -m /mnt/deb | tail -1'
# second stage in the background on the phone (an ssh drop must not kill it); poll and keep the init reboot timer extended
$SSH 'rm -f /mnt/deb/second-stage.done; setsid sh -c "chroot /mnt/deb /second-stage.sh > /mnt/deb/var/log/second-stage.log 2>&1; touch /mnt/deb/second-stage.done" >/dev/null 2>&1 &'
for i in $(seq 1 360); do
  sleep 10; $SSH 'touch /tmp/stay'
  if $SSH 'test -e /mnt/deb/second-stage.done'; then break; fi
  [ $((i%6)) = 0 ] && echo "second stage: $((i/6)) min, $($SSH 'df -m /mnt/deb | tail -1 | awk "{print \$3\" MiB used\"}"; tail -n1 /mnt/deb/var/log/second-stage.log | cut -c1-80')"
done
$SSH 'cat /mnt/deb/var/log/second-stage.log | tail -n 40'
$SSH 'test -e /mnt/deb/second-stage.done' || { echo "second stage did not finish"; exit 1; }
$SSH 'chroot /mnt/deb /tmp/customize.sh'
if [ -f vendor/wifi/credentials.txt ]; then
  ssid=$(sed -n 's/^ssid=//p' vendor/wifi/credentials.txt); psk=$(sed -n 's/^psk=//p' vendor/wifi/credentials.txt)
  printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\ninterface-name=wlan0\nautoconnect=true\n[wifi]\nssid=%s\nmode=infrastructure\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n[ipv4]\nmethod=auto\n[ipv6]\nmethod=auto\n' "$ssid" "$(cat /proc/sys/kernel/random/uuid)" "$ssid" "$psk" \
    | $SSH 'umask 077; mkdir -p /mnt/deb/etc/NetworkManager/system-connections; cat > /mnt/deb/etc/NetworkManager/system-connections/home.nmconnection; chmod 600 /mnt/deb/etc/NetworkManager/system-connections/home.nmconnection'
fi
# PERSIST=1 (E026): copy the finished root to the phone's UFS partitions linuxroot (sda22) / linuxboot (sda21) -- the only storage write of this script.
# Refuses unless the GPT names are as expected; filesystems are created fresh (these partitions were created empty in E025).
if [ "${PERSIST:-0}" = 1 ]; then
  $SSH 'rm -rf /mnt/deb/debs /mnt/deb/tmp/* /mnt/deb/var/cache/apt/*.bin; umount -R -l /mnt/deb/dev /mnt/deb/proc /mnt/deb/sys /mnt/deb/run 2>/dev/null; true'
  $SSH 'set -e
    [ "$(grep PARTNAME /sys/block/sda/sda22/uevent)" = PARTNAME=linuxroot ] && [ "$(grep PARTNAME /sys/block/sda/sda21/uevent)" = PARTNAME=linuxboot ]
    chroot /mnt/deb /sbin/mke2fs -q -t ext4 -L linuxboot -F /dev/sda21
    chroot /mnt/deb /sbin/mke2fs -q -t ext4 -L linuxroot -F -E lazy_itable_init=1 /dev/sda22
    mkdir -p /mnt/persist; mount -t ext4 /dev/sda22 /mnt/persist
    cd /mnt/deb; tar -cf - --exclude "./dev/*" --exclude "./proc/*" --exclude "./sys/*" --exclude "./run/*" . | tar -xf - -C /mnt/persist
    mkdir -p /mnt/persist/boot /mnt/persist/dev /mnt/persist/proc /mnt/persist/sys /mnt/persist/run
    printf "LABEL=linuxroot / ext4 defaults,noatime 0 1\nLABEL=linuxboot /boot ext4 defaults,noatime 0 2\n" > /mnt/persist/etc/fstab
    sync; df -m /mnt/persist | tail -1; umount /mnt/persist; sync'
  echo "persisted to sda22"
fi
$SSH 'rm -rf /mnt/deb/debs /mnt/deb/tmp/* /mnt/deb/var/cache/apt/*.bin; umount -R -l /mnt/deb/dev /mnt/deb/proc /mnt/deb/sys /mnt/deb/run 2>/dev/null; df -m /mnt/deb | tail -1'
echo "switching root (the ssh session will end)"
$SSH 'echo /mnt/deb > /run/switch-root' || true
# the old-root daemons were stopped by the initramfs hook; Debian's own sshd/networkd now own usb0 and port 22
ok=0
for i in $(seq 1 60); do
  if ssh -q -i vendor/ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.7.1 'touch /run/sky-keep' 2>/dev/null; then ok=1; break; fi
  sleep 5
done
if [ $ok = 1 ]; then
  echo "Debian reachable over ssh; failsafe disarmed (/run/sky-keep)"
  ssh -q -i vendor/ssh/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.7.1 \
    'grep PRETTY /etc/os-release; systemctl is-system-running; systemctl --failed --no-legend | head; systemctl is-active gdm3 NetworkManager bluetooth ssh sky-wifi | tr "\n" " "; echo'
else
  echo "Debian NOT reachable: the 50-minute failsafe (sky-failsafe.service) reboots the phone to Android; or hold the power button ~15 s"
fi
