#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs ON THE TARGET (inside the rootfs chroot during tools/push-debian.sh, or on the live phone via tools/install-displaylink.sh).
# usage: install-target.sh STAGEDIR     STAGEDIR comes from tools/displaylink-stage.sh and holds the vendor DisplayLinkManager (proprietary,
# vendor/displaylink only), libusb, libevdi.so, our evdi.ko, the vendor udev-installer.sh and our unit/config. Re-runnable.
set -e
S=${1:-/tmp/dlinst}
for f in DisplayLinkManager libusb-1.0.so.0.6.0 libevdi.so evdi.ko udev-installer.sh displaylink-driver.service sky-evdi.service; do [ -e "$S/$f" ] || { echo "missing $S/$f" >&2; exit 2; }; done
install -d /opt/displaylink /var/log/displaylink /usr/local/lib/sky-modules /etc/environment.d
install -m0755 "$S/DisplayLinkManager" "$S/libusb-1.0.so.0.6.0" "$S/libevdi.so" /opt/displaylink/
ln -sf libusb-1.0.so.0.6.0 /opt/displaylink/libusb-1.0.so.0; ln -sf libusb-1.0.so.0.6.0 /opt/displaylink/libusb-1.0.so
for f in "$S"/*.spkg "$S/LICENSE" "$S/3rd_party_licences.txt"; do [ -e "$f" ] && install -m0644 "$f" /opt/displaylink/; done
install -m0644 "$S/evdi.ko" /usr/local/lib/sky-modules/evdi.ko
# vendor-generated udev rules + hotplug helper (starts/stops displaylink-driver when a DisplayLink USB device appears/disappears)
bash "$S/udev-installer.sh" systemd /usr/lib/udev/rules.d/99-displaylink.rules /opt/displaylink/udev.sh
install -m0644 "$S/displaylink-driver.service" /usr/lib/systemd/system/displaylink-driver.service
install -m0644 "$S/sky-evdi.service" /etc/systemd/system/sky-evdi.service
systemctl --root=/ enable sky-evdi.service >/dev/null 2>&1 || ln -sf /etc/systemd/system/sky-evdi.service /etc/systemd/system/multi-user.target.wants/sky-evdi.service
# Mutter draws the pointer into the frame instead of using the cursor plane: over evdi the hardware cursor came out ~95% transparent (E031)
echo "MUTTER_DEBUG_DISABLE_HW_CURSORS=1" > /etc/environment.d/90-sky-sw-cursor.conf
systemctl daemon-reload >/dev/null 2>&1 || true
udevadm control --reload >/dev/null 2>&1 || true
echo "evdi.ko vermagic: $(modinfo -F vermagic "$S/evdi.ko" 2>/dev/null || echo unknown)"
LD_LIBRARY_PATH=/opt/displaylink ldd /opt/displaylink/DisplayLinkManager | grep -i "not found" || echo "ldd: DisplayLinkManager libraries resolved"
LD_LIBRARY_PATH=/opt/displaylink ldd /opt/displaylink/libevdi.so | grep -i "not found" || echo "ldd: libevdi libraries resolved"
echo "displaylink installed"
