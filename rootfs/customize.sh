#!/bin/bash
# SPDX-License-Identifier: MIT
# Run inside the Debian chroot on the phone after /second-stage.sh (E021): hostname, user, ssh, GDM autologin, services. Debug conveniences are
# listed in docs/TECH_DEBT.md (passwordless sudo, autologin, key-only ssh for root and user).
set -e
export LC_ALL=C PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo sky > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 sky\n' > /etc/hosts
getent group render >/dev/null || groupadd -r render
for g in sudo video render input audio netdev bluetooth plugdev; do getent group $g >/dev/null || groupadd -r $g; done
id user >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,video,render,input,audio,netdev,bluetooth,plugdev user
passwd -l root >/dev/null; passwd -d user >/dev/null || true
echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-sky-debug; chmod 440 /etc/sudoers.d/90-sky-debug
mkdir -p /root/.ssh /home/user/.ssh; chmod 700 /root/.ssh /home/user/.ssh
cp /tmp/authorized_keys /root/.ssh/authorized_keys; cp /tmp/authorized_keys /home/user/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys /home/user/.ssh/authorized_keys; chown -R user:user /home/user/.ssh
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/; s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d; printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\n' > /etc/ssh/sshd_config.d/10-sky.conf
mkdir -p /etc/gdm3; printf '[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=user\nWaylandEnable=true\n' > /etc/gdm3/daemon.conf
# apt sources (the stage-1 root has none) incl. security updates; Flathub for Flatpak (needs network; skipped quietly when offline)
mkdir -p /etc/apt/sources.list.d
printf 'Types: deb\nURIs: http://deb.debian.org/debian\nSuites: trixie trixie-updates\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n\nTypes: deb\nURIs: http://deb.debian.org/debian-security\nSuites: trixie-security\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n' > /etc/apt/sources.list.d/debian.sources
command -v flatpak >/dev/null && flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
mkdir -p /etc/NetworkManager/conf.d
printf '[keyfile]\nunmanaged-devices=interface-name:usb0;interface-name:p2p0;interface-name:wifi-aware0\n' > /etc/NetworkManager/conf.d/10-sky.conf
install -m755 /tmp/sky-wifi-up /usr/local/sbin/sky-wifi-up
install -m644 /tmp/sky-wifi.service /etc/systemd/system/sky-wifi.service
install -m755 /tmp/sky-charge-limit /usr/local/bin/sky-charge-limit
install -m644 /tmp/sky-charge-limit.service /etc/systemd/system/sky-charge-limit.service
printf 'LIMIT=80\nRESUME=75\nINTERVAL=30\nFLOOR=30\n' > /etc/sky-charge-limit.conf
# swap file: created by the service on the first boot from the persistent ext4 root (a RAM root has none); modest swappiness for flash storage
install -m755 /tmp/sky-swapfile /usr/local/sbin/sky-swapfile
install -m644 /tmp/sky-swapfile.service /etc/systemd/system/sky-swapfile.service
printf 'SIZE_MB=4096\nMIN_FREE_MB=8192\nPRIORITY=10\n' > /etc/sky-swapfile.conf
mkdir -p /etc/sysctl.d; printf 'vm.swappiness=30\n' > /etc/sysctl.d/90-sky-swap.conf
# no idle suspend (E031 run 3): GNOME default overrides, compiled into the schema cache
install -m644 /tmp/90_sky-power.gschema.override /usr/share/glib-2.0/schemas/90_sky-power.gschema.override
install -D -m644 /tmp/61-sky-battery.hwdb /etc/udev/hwdb.d/61-sky-battery.hwdb && systemd-hwdb update
glib-compile-schemas /usr/share/glib-2.0/schemas
# zram swap (kernel m21+ has CONFIG_ZRAM; the service skips itself on kernels without it); it raises vm.swappiness to 100 when active
install -m755 /tmp/sky-zram /usr/local/sbin/sky-zram
install -m644 /tmp/sky-zram.service /etc/systemd/system/sky-zram.service
printf 'SIZE_PCT=50\nALGO=zstd\nPRIORITY=100\nSWAPPINESS=100\n' > /etc/sky-zram.conf
systemctl --root=/ enable gdm3.service NetworkManager.service bluetooth.service ssh.service sky-wifi.service sky-charge-limit.service sky-swapfile.service sky-zram.service >/dev/null 2>&1 || true
mkdir -p /etc/systemd/system; ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
systemctl --root=/ mask systemd-networkd-wait-online.service NetworkManager-wait-online.service >/dev/null 2>&1 || true
# no RTC on this phone: keep the pushed clock until timesyncd gets a network
echo "LANG=C.UTF-8" > /etc/default/locale
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
# usb0 (CDC-NCM gadget): systemd-networkd serves 192.168.7.1/24 + DHCP to the host, like the initramfs did; NetworkManager leaves usb0 alone (10-sky.conf)
mkdir -p /etc/systemd/network
printf '[Match]\nName=usb0\n\n[Network]\nAddress=192.168.7.1/24\nDHCPServer=yes\n\n[DHCPServer]\nPoolOffset=10\nPoolSize=40\nEmitDNS=no\n' > /etc/systemd/network/10-usb0.network
systemctl --root=/ enable systemd-networkd.service >/dev/null 2>&1 || true
# debug console on the gadget serial port (root, no login) and a failsafe: reboot unless someone confirmed access by touching /run/sky-keep
mkdir -p /etc/systemd/system/serial-getty@ttyGS0.service.d
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I 115200 linux\n' > /etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf
mkdir -p /etc/systemd/system/getty.target.wants; ln -sf /usr/lib/systemd/system/serial-getty@.service /etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service
cat > /etc/systemd/system/sky-failsafe.service <<'UNIT'
[Unit]
Description=Reboot to Android if nobody confirmed access within 50 minutes (RAM-root experiments only)

[Service]
Type=simple
ExecStart=/bin/sh -c 'sleep 3000; [ -e /run/sky-keep ] || /usr/bin/systemctl reboot --force --force'

[Install]
WantedBy=multi-user.target
UNIT
systemctl --root=/ enable sky-failsafe.service >/dev/null 2>&1 || true
# audio: UCM profile (staged as /tmp/ucm2 by tools/push-debian.sh; the FS1599 amplifier is handled by the kernel)
if [ -d /tmp/ucm2/Xiaomi/sky ]; then
  mkdir -p /usr/share/alsa/ucm2/Xiaomi/sky /usr/share/alsa/ucm2/conf.d/sm8450
  cp /tmp/ucm2/Xiaomi/sky/*.conf /usr/share/alsa/ucm2/Xiaomi/sky/
  ln -sf ../../Xiaomi/sky/sky.conf /usr/share/alsa/ucm2/conf.d/sm8450/Redmi-12-5G.conf
fi
# DisplayLink dock support (E031): staged by tools/push-debian.sh from vendor/displaylink (vendor binary, evdi.ko for the matching kernel)
if [ -f /tmp/dlstage.tar ]; then
  mkdir -p /tmp/dlinst; tar -xf /tmp/dlstage.tar -C /tmp/dlinst
  bash /tmp/dlinst/install-target.sh /tmp/dlinst
fi
echo customize done
