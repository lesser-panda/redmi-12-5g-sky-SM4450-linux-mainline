#!/bin/bash
# SPDX-License-Identifier: MIT
# E016: bring WiFi up on a RAM-booted m14 (ssh over USB): push payload, load modules, wpa_supplicant (WPA2-PSK), DHCP, DNS.
# Needs vendor/wifi/payload.tar (strip'ed modules + firmware + iw/wpa_supplicant) and vendor/wifi/credentials.txt (ssid=/psk=). Nothing here is committed.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
SSH="ssh -q -i vendor/ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 root@192.168.7.1"
ssid=$(sed -n 's/^ssid=//p' vendor/wifi/credentials.txt); psk=$(sed -n 's/^psk=//p' vendor/wifi/credentials.txt)
$SSH 'touch /tmp/stay; [ -d /sys/class/net/wlan0 ] && echo "wlan0 already present"' || true
if ! $SSH 'test -d /sys/class/net/wlan0'; then
  $SSH 'tar -xf - -C /' < vendor/wifi/payload.tar          # payload tar is built with --owner=0 --group=0
  $SSH 'chown 0:0 / /root; chmod 700 /root; cd /root/wifi && insmod cnss_utils.ko && insmod wlan_firmware_service.ko && insmod icnss2.ko'
  for i in $(seq 1 20); do $SSH 'dmesg | grep -q "WLAN FW is ready"' && break; sleep 1; done
  $SSH 'dmesg | grep -q "WLAN FW is ready"' || { echo "FW not ready"; exit 1; }
  $SSH 'insmod /root/wifi/wlan.ko'
  for i in $(seq 1 20); do $SSH 'test -d /sys/class/net/wlan0' && break; sleep 1; done
fi
[ "${WIFI_CONNECT:-1}" = 0 ] && { echo "wlan0 present, left unconfigured (NetworkManager will manage it)"; exit 0; }
printf 'ctrl_interface=/tmp/wpa\nupdate_config=0\nnetwork={\n ssid="%s"\n psk="%s"\n key_mgmt=WPA-PSK\n}\n' "$ssid" "$psk" | $SSH 'umask 077; cat > /tmp/wpa.conf'
$SSH 'ip link set wlan0 up; mkdir -p /tmp/wpa /usr/share/udhcpc
printf "#!/bin/sh\ncase \$1 in bound|renew) ip addr flush dev \$interface; ip addr add \$ip/\${mask:-24} dev \$interface; [ -n \"\$router\" ] && ip route replace default via \${router%% *} dev \$interface; : > /etc/resolv.conf; for d in \$dns; do echo nameserver \$d >> /etc/resolv.conf; done;; esac\n" > /usr/share/udhcpc/default.script; chmod +x /usr/share/udhcpc/default.script
pidof wpa_supplicant >/dev/null || (wpa_supplicant -D nl80211 -i wlan0 -c /tmp/wpa.conf -t >/tmp/wpa.log 2>&1 &)
for i in $(seq 1 20); do wpa_cli -p /tmp/wpa status 2>/dev/null | grep -q wpa_state=COMPLETED && break; sleep 1; done
udhcpc -i wlan0 -n -q -t 5 >/dev/null 2>&1; ping -c2 -W2 1.1.1.1 >/dev/null && echo "wifi online" || echo "wifi NOT online"'
