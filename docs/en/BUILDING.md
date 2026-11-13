# Building and booting from RAM

This builds everything up to a bootable image and starts it **from RAM**. Nothing is written to the phone.

## What you need

**Phone:** Redmi 12 5G (23076RN4BI), bootloader unlocked, PixelOS 14 `PixelOS_sky-14.0-20240922-0137` on slot B,
USB debugging on, root (Magisk) if you want the script to read the modem/Bluetooth partitions itself.
Battery above 50 %. A good USB cable.

**Host:** x86-64 Linux, about 30 GB free disk, internet for the first fetch.

| Tool | Used for | Fedora / Debian package |
|---|---|---|
| gcc, make, flex, bison, bc, openssl and libelf headers, perl, cpio | kernel build | `gcc make flex bison bc openssl-devel elfutils-libelf-devel perl cpio` / `build-essential flex bison bc libssl-dev libelf-dev perl cpio` |
| git, curl, python3, openssl | fetching, helper scripts | `git curl python3 openssl` |
| m4, alsatplg | audio topology (if `alsatplg` is not in `PATH`, run `ALSATPLG=/path/to/alsatplg tools/build-kernel.sh`) | `m4 alsa-utils` |
| adb, fastboot, mkbootimg, unpack_bootimg | boot images, talking to the phone | `android-tools` / `android-tools-adb android-tools-fastboot mkbootimg` (unpack_bootimg ships with it or with AOSP `mkbootimg`) |
| 7z, debugfs | unpacking firmware partitions | `p7zip e2fsprogs` / `p7zip-full e2fsprogs` |

The cross compiler (GCC 15.2.0, `nolibc` build from kernel.org) is downloaded by the fetch script.

## Steps

```sh
# 1. inputs, hash-checked (kernel tarball, toolchain, sky-linux shim, audio topology sources, payload-dumper-go)
tools/fetch-sources.sh

# 2. your own proprietary files (see EXTRACTING-VENDOR-FILES.md); stays in vendor/, never committed
tools/extract-vendor-files.sh --rom ~/Downloads/PixelOS_sky-14.0-20240922-0137.zip --from-phone

# 3. build: patched kernel tree, topology, initramfs, kernel, device tree, boot images  -> out/boot/
tools/build-kernel.sh

# 4. start it from RAM (phone in fastboot mode)
adb reboot bootloader
tools/boot-ram.sh
ssh -i vendor/ssh/id_ed25519 root@192.168.7.1
```

`build-kernel.sh` does, in order: unpack Linux 7.3 and `git apply` the patches from `kernel/patches/`; build the audio topology;
stage the initramfs (busybox, dropbear, your ssh public key, firmware); configure from `kernel/sky_defconfig`; build `Image`;
compile `dts/sm4450-xiaomi-sky.dts`; wrap everything in the sky-linux shim as an Android boot image (`out/boot/sky-boot-v4.img`);
if `vendor/rom/` exists also produce the `recovery_b` variant (`out/boot/sky-recovery_b-v2.img`, header v2, see [ARCHITECTURE.md](ARCHITECTURE.md)).
`SHA256SUMS` in `out/boot/` lists the results. The kernel embeds a build timestamp, so the hashes differ between builds even from identical inputs.

## What to expect

- The screen shows the kernel console after a few seconds; USB then enumerates as a gadget with a serial port and an Ethernet interface.
- Your PC gets `192.168.7.x` from the phone's DHCP server; the phone is `192.168.7.1`. Log in with the key from `vendor/ssh/`.
- The initramfs reboots the phone after 7 minutes unless you `touch /tmp/stay` on it (adds an hour each time). That is the safety net: a hang can never strand you.
- Without a root filesystem you land in a small busybox system with working display, touch, GPU, WiFi (once you load the modules), audio and so on.
  A full desktop needs the root filesystem steps in [INSTALLING.md](INSTALLING.md).

## What was verified from a clean checkout

The kernel patch series applies to a fresh Linux 7.3 tarball and reproduces the tested tree file for file; the defconfig reproduces
the tested `.config` exactly; the device tree compiles byte for byte to the tested blob; the audio topology rebuilds byte for byte.
The vendor-file extraction was run against the original ROM and partition dumps and all 296 files matched. The complete
`tools/build-kernel.sh` result (default options, with the Debian root already on the phone) was booted from RAM: it starts Debian,
loads the speaker amplifier preset and brings up display, GPU, input, audio card and Bluetooth (lab notebook, E035). The
initramfs-only variant (`AUTOROOT=0`) builds but has not been booted. The out-of-tree modules (`qcacld` WiFi, `evdi`) are tied to the exact
kernel build: after you build your own kernel, rebuild them (see [KNOWN-ISSUES.md](KNOWN-ISSUES.md)); an old module fails with "Invalid module format".
The optional root filesystem scripts (Debian build, WiFi module build, DisplayLink) are the ones used for the original install and
have not been re-run from a clean checkout; treat them as a reference. See [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `fetch-sources.sh` hash mismatch | upstream changed or a download was cut off; delete `sources/dl/<file>` and retry |
| `git apply` fails in `build-kernel.sh` | `sources/linux-7.3` was modified; remove it and let the script recreate it |
| fastboot lists no device | `adb reboot bootloader`; check the cable; the phone must show the fastboot screen |
| `fastboot boot` works but no `192.168.7.1` | wait 90 s; look at the screen; on the PC an interface `enx...` must appear (NetworkManager may need to set it to "shared" or you can add `192.168.7.2/24` by hand) |
| after writing `recovery_b` the phone ends up in fastboot or does not boot Linux | see [RECOVERY.md](RECOVERY.md); the Android slot is untouched, `fastboot boot out/boot/sky-boot-v4.img` always works |
