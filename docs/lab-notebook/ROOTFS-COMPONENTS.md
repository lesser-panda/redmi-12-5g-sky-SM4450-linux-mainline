# What lives outside the kernel (and could it move in?)

Written 2026-11-12 after the user asked whether the extra pieces that must be installed on the Debian rootfs can be confined to the kernel. Evidence level: design assessment from this project's own experience (E021–E031); none of the "could move" items has been tried.

Everything below is installed by `tools/push-debian.sh` → `desktop-debian/customize.sh` (fresh rootfs) or by the matching live installer. Inputs that are vendor files stay in `private/`.

| Piece | Where it lives now | Could it be kernel-only? | Notes / what it would take |
|---|---|---|---|
| Speaker amplifier FS1599 (on/off, preset) | **Done (E034, kernel m24):** `sound/soc/codecs/fs1599.c` (kernel-local/fs1599/), DT node `amplifier@34`, preset built in as firmware. The old `sky-fs1599`/`sky-amp-watch`/udev rule and the audio staging scripts are gone; the rootfs build only copies the UCM profile. | **Moved to the kernel.** (was:) | An ASoC codec driver (I2C 0x34) that applies the preset (via `request_firmware`) and is powered by DAPM before the PCM trigger. Removes the watcher, helper, udev rule, the `audio`-group I2C access, and the ~0.1 s clipped start. Needs porting the register sequences from `tools/fs1599.py`; local patch (no upstream driver for this chip known). |
| Audio routing (UCM) | `audio/ucm2/Xiaomi/sky/*.conf` + `alsa-ucm-conf` package | Mostly no | Routing is ALSA mixer state chosen by userspace on every qcom machine driver; UCM is the standard place. It can go upstream into `alsa-ucm-conf` (then no per-device file). A DT `audio-routing` only fixes the static part. |
| DisplayLink dock | `evdi.ko` (insmod), vendor `DisplayLinkManager` + `libevdi.so` in `/opt/displaylink`, udev rules, unit | **Module: yes. Daemon: no.** | `evdi.ko` can be built into the kernel tree (removes the vermagic constraint: "rebuild evdi after every kernel"). `DisplayLinkManager` is a proprietary userspace program and must stay in the rootfs. |
| WiFi (qcacld) | out-of-tree modules + `sky-wifi-up` (insmod order) + firmware in rootfs | Yes, in principle | Same trick as evdi (build in, drop the insmod script and the vermagic constraint); the load order learned in E016 must then be expressed through the init order. Firmware must still be found when the driver probes (see firmware row). |
| Firmware blobs (ADSP, WPSS, GPU, BT, touch) | initramfs inside the boot image + copied into the rootfs | Partly | The initramfs is freed after `switch_root`, so later loads look in the rootfs `/lib/firmware`. `CONFIG_EXTRA_FIRMWARE` keeps small blobs in the kernel image itself; big ones (ADSP/WPSS) make the image large. Vendor blobs in a private image are fine, never publish. |
| zram swap | kernel `CONFIG_ZRAM` (m21) + `sky-zram` service | Partly | The kernel side is already in the kernel. Sizing, `mkswap`, `swapon` and sysctls need userspace (zswap would be fully cmdline-configured, but it needs a swap device behind it, which again needs userspace). |
| Swap file | `sky-swapfile` service | No | Creating a file and `swapon` are userspace actions. |
| Charge limit (80%) | `desktop-debian/sky-charge-limit(.service)` | Yes, with a kernel patch | Firmware lacks the standard threshold, so a service toggles the Xiaomi `input_suspend` property. A patch to `qcom_battmgr` could expose `charge_control_end_threshold` (hysteresis done in the kernel) and GNOME's own battery-limit switch would then work. Local patch; upstream unlikely to take the private opcode. |
| Power policy, apt sources, ssh keys, user, GDM autologin, gsettings overrides | `desktop-debian/customize.sh`, `90_sky-power.gschema.override` | No | Distro/policy, belongs in the rootfs by design. |
| Android-side boot glue | recovery_b image (m20 v2) | n/a | Boot image only. |

## Guidance
- Principle used by this project: hardware knowledge (drivers, DT, firmware loading, power sequencing) belongs in the kernel/DT; policy and packaging in the rootfs. Device-specific daemons (`sky-charge-limit`, `sky-wifi-up`) are stop-gaps and are listed in TECH_DEBT.
- Suggested order of value if we ever move things in: (1) FS1599 as an ASoC codec driver, (2) build evdi (and maybe the WiFi modules) into the kernel to kill the vermagic coupling, (3) charge limit through `qcom_battmgr`, (4) embed only the small firmware blobs.
- Not decided; no work started. The user said it is fine if it cannot be done.
