# Mainline Linux on the Redmi 12 5G (sky, SM4450)

English | [简体中文](README.zh-CN.md)

A Debian 13 + GNOME (Wayland) desktop running on the **Redmi 12 5G** (`sky`, model 23076RN4BI, Snapdragon 4 Gen 2 / SM4450)
with a **mainline Linux 7.3 kernel**, started from the phone's own storage with Android still installed next to it.
The kernel is vanilla Linux 7.3 plus a small, documented patch series; everything else (device tree, initramfs,
boot image tooling, root filesystem scripts) is in this repository.

> **Status: it works as a pocket Linux machine; it is not a phone yet.** Display, touch, GPU, WiFi, Bluetooth, audio,
> battery/charging, suspend and USB (device, host, DisplayLink dock) work. Cellular (calls, SMS, mobile data), cameras,
> sensors and GPS do not. Details: [docs/en/STATUS.md](docs/en/STATUS.md).

## What you get

| | |
|---|---|
| Kernel | Linux 7.3 + 8 patches in [kernel/patches](kernel/patches), config in [kernel/sky_defconfig](kernel/sky_defconfig) |
| Device tree | [dts/sm4450-xiaomi-sky.dts](dts/sm4450-xiaomi-sky.dts) |
| Boot | Android boot image (shim + kernel + initramfs). Test it from RAM with `fastboot boot` (nothing is written), or install it into the `recovery_b` partition for hands-free boot |
| Userspace | Debian trixie arm64, GNOME on Wayland, Mesa freedreno/turnip, PipeWire, NetworkManager |
| Android | stays installed on slot B; `adb reboot recovery` starts Linux, a normal reboot starts Android |
| Docs | English and Chinese in [docs/](docs), the full lab notebook in [docs/lab-notebook](docs/lab-notebook) |

## Is this for me?

You need a **Redmi 12 5G (23076RN4BI / sky) with an unlocked bootloader**, a Linux PC, and the tested PixelOS 14 build
(`PixelOS_sky-14.0-20240922-0137`) on slot B. Other builds and other sky variants (the Japanese model, 4 GB version)
may differ in partition layout and firmware; the scripts check hashes and stop when something does not match.

**Risk, plainly:** the RAM boot is safe (power-cycle and you are back in Android). Installing to `recovery_b` writes one
partition and is recoverable with `fastboot`. Installing a persistent root needs a **new partition layout, which erases
all Android data**. No warranty; you are responsible for your device. Read [docs/en/RECOVERY.md](docs/en/RECOVERY.md) first.

## Quick start (RAM boot, writes nothing)

```sh
git clone git@github.com:lesser-panda/redmi-12-5g-sky-SM4450-linux-mainline.git && cd redmi-12-5g-sky-SM4450-linux-mainline
tools/fetch-sources.sh                       # kernel tarball, toolchain, shim, ... (hash-pinned)
tools/extract-vendor-files.sh --rom PixelOS_sky-14.0-20240922-0137.zip --from-phone   # your own firmware, stays in vendor/
tools/build-kernel.sh                        # about 10-30 minutes
adb reboot bootloader && tools/boot-ram.sh   # phone boots Linux from RAM; ssh root@192.168.7.1
```

The full walk-through, prerequisites and what to expect: [docs/en/BUILDING.md](docs/en/BUILDING.md).
Installing to storage: [docs/en/INSTALLING.md](docs/en/INSTALLING.md).

## What is not in this repository

Proprietary files are **never** distributed here: firmware (GPU, touch, WiFi, ADSP, Bluetooth), the speaker amplifier
preset, the vendor DisplayLink driver, Android images. You extract them from your own phone and the ROM you already
have ([docs/en/EXTRACTING-VENDOR-FILES.md](docs/en/EXTRACTING-VENDOR-FILES.md)); the expected hashes are in
[tools/vendor-files.sha256](tools/vendor-files.sha256).

## Repository map

```
kernel/          patch series against Linux 7.3, defconfig, third-party patch copies with credits
dts/             board device tree
initramfs/       init script (USB gadget, ssh, safety reboot, autoroot, switch-root hook)
tools/           fetch, extract, build, boot, flash; rootfs build and install scripts; stress test
rootfs/          files installed into the Debian root (UCM audio profile, services, GNOME defaults, DisplayLink glue)
docs/en, docs/zh-CN    documentation
docs/lab-notebook      the original experiment write-ups (E001-E037), dated, with failures kept
LICENSES/        license texts
```

## Credits

This work stands on [ROCKNIX](https://github.com/ROCKNIX/distribution) (SM4450 kernel patch queue),
[orange200213/sky-linux](https://github.com/orange200213/sky-linux) (the shim boot method and first sky bring-up) and the
Linux, Mesa, Debian and linux-msm communities. See [docs/en/CREDITS.md](docs/en/CREDITS.md) and
[kernel/third-party/README.md](kernel/third-party/README.md).

## License

Kernel patches and drivers: GPL-2.0-only (device trees keep their SPDX tag, BSD-3-Clause for most). Scripts, rootfs files
and documentation: MIT. Third-party parts keep their own licenses. Per-file SPDX tags are authoritative.
Not affiliated with or endorsed by Xiaomi, Qualcomm, Debian or the PixelOS project; product names are used to identify hardware.
