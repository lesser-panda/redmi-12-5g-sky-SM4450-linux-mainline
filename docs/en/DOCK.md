# DisplayLink dock (external monitor, keyboard, mouse)

Native video output over the USB-C port was not attempted; a **DisplayLink** USB dock works: HDMI monitor at 1920x1080@60 over USB 2, keyboard and mouse. Verified by the user.

- Needs the out-of-tree `evdi` kernel module (built against the exact kernel in the boot image: `tools/build-evdi.sh`) and the proprietary Synaptics
  DisplayLink driver (`DisplayLinkManager`, download "USB Graphics Software for Ubuntu 6.4" from the vendor yourself; it is not redistributable and not in this repository).
  `tools/displaylink-stage.sh` packs the pieces, `rootfs/displaylink/` holds our glue (service units, installer).
- **Cursor:** on the external screen the hardware cursor came out nearly transparent. GNOME is started with `MUTTER_DEBUG_DISABLE_HW_CURSORS=1` (software cursor) via `/etc/environment.d/90-sky-sw-cursor.conf`.
  Cost: every pointer move redraws part of the frame. The root cause on the evdi cursor plane is not investigated.
- evdi must be present before gnome-shell starts, otherwise Mutter's monitor list is stale; `sky-evdi.service` loads it early. Replugging the dock while the session runs works.
- Known problems with suspend on the dock are in [KNOWN-ISSUES.md](KNOWN-ISSUES.md).
