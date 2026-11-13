#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the sky-osk GNOME Shell extension (layouts -> gresource) and install it on the phone.
# Usage: tools/build-sky-osk.sh            generate the layout JSON locally (rootfs/sky-osk/layouts/)
#        tools/build-sky-osk.sh install    also copy everything to the phone over ssh, compile the gresource there
#                                          (glib-compile-resources comes with Debian's libglib2.0-dev-bin; this script installs it if missing)
#                                          and put the extension into the user's extension directory. Layout changes are picked up by
#                                          disabling and enabling the extension (gnome-extensions), code changes need a new login on Wayland.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
E=rootfs/sky-osk
UUID=sky-osk@redmi-12-5g.local
python3 -I tools/gen-sky-osk-layouts.py
{
  echo '<?xml version="1.0" encoding="UTF-8"?><gresources><gresource prefix="/org/gnome/shell/osk-layouts">'
  for f in $E/layouts/*.json; do echo "  <file>$(basename "$f")</file>"; done
  echo '</gresource></gresources>'
} > $E/layouts/sky-osk.gresource.xml
[ "$1" = install ] || exit 0
SSH="ssh -q -i ${SKY_SSH_KEY:-vendor/ssh/id_ed25519} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.7.1"
D=/home/user/.local/share/gnome-shell/extensions/$UUID
tar -C $E -cf - metadata.json extension.js stylesheet.css config.json layouts | $SSH "set -e
mkdir -p $D && tar -C $D -xf -
command -v glib-compile-resources >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libglib2.0-dev-bin >/dev/null
cd $D/layouts && glib-compile-resources --sourcedir=. --target=$D/sky-osk-layouts.gresource sky-osk.gresource.xml
chown -R user:user /home/user/.local/share/gnome-shell/extensions
echo installed $D"
