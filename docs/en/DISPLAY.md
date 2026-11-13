# Display and backlight

- **Panel:** Xiaomi "m19_42_03_0b", 1080x2460, 4 DSI lanes, video mode with DSC. Timings, DSC parameters and the DCS init/off sequences were read from the phone's own `dtbo`
  (the runtime device tree only has a placeholder). Driver: `drivers/gpu/drm/panel/panel-xiaomi-sky.c`, written for this project on the pattern of `panel-visionox-r66451.c`.
- **Display pipeline:** MDSS/DPU 8.6 (`dpu_8_6_sm4450.h`), DSC, DSI controller and PHY, driven by `msm`. ABL leaves the panel lit with a splash framebuffer
  (continuous splash); the patches let the driver take over that framebuffer and stop the boot scan-out.
- **Backlight:** KTD3136 on I2C 0x36 (`ktd3136.c`, imported from sky-linux). The chip initialisation table from sky-linux (taken from another phone) gave a dim screen at full brightness; the values from this phone's Android
  (registers 0x13/0x17/0x18/0x1a/0x1c/0x24) fixed it.
- **Refresh rate:** the driver exposes one mode, 1080x2460 at 90 Hz (pixel clock 274.5 MHz). The vendor device tree also lists 60, 49 and 30 Hz variants; they are not implemented.
- **Cursor:** over an external DisplayLink monitor GNOME needs the software cursor, see [DOCK.md](DOCK.md).

Why the bootloader matters: the display only comes up if the ABL leaves the panel lit. A boot image without a valid `recovery_dtbo` makes the ABL power the panel down; the driver cannot cold-start it ([ARCHITECTURE.md](ARCHITECTURE.md)).

## Rotation
There is no accelerometer Linux can read (see [STATUS.md](STATUS.md), sensors), so the screen does not rotate by itself. The `sky-rotate` GNOME Shell extension (`rootfs/sky-rotate/`)
adds a top bar button with a drop-down: **Portrait**, **Landscape left** (top of the phone towards the left, the camera hole on the left) and **Landscape right**; the current one has a dot.
It asks Mutter's `org.gnome.Mutter.DisplayConfig` D-Bus service to change the transform of the built-in panel only (scale, mode and any dock monitor stay as they are). The configuration is applied as a
temporary one, which avoids Mutter's "keep these display settings?" countdown, so the extension remembers the choice in `~/.config/sky-rotate/orientation` and applies it again two seconds after login.
The touch keyboard follows the orientation (portrait or split layout, [KEYBOARD.md](KEYBOARD.md)). Install: `tools/push-debian.sh` puts it into the root filesystem and enables it by default; on a running phone copy `rootfs/sky-rotate/` to
`~/.local/share/gnome-shell/extensions/sky-rotate@redmi-12-5g.local` and log in again (Wayland only finds new extensions in a new session).
