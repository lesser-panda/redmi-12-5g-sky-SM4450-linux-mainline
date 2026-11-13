# EXPERIMENT-011 (E035): publication prep and clean-checkout verification (2026-11-13)

## Goal
A stranger with the same phone must be able to reproduce the tested kernel. Verify the published flow (`release/`) from a copy that contains no workspace state.

## Setup
- `out/clone-test` = copy of `release/` + the pinned downloads (`tools/fetch-sources.sh` ran there: kernel tarball and toolchain were pre-seeded from the workspace cache, all hashes checked; sky-linux, audioreach-topology, payload-dumper-go, Alpine key fetched) + `vendor/` from `tools/extract-vendor-files.sh` run against the original ROM zip and the 2026-11-09 partition dumps (all 296 files equal `tools/vendor-files.sha256`).
- Offline equivalence checks (done): kernel patch series applied to a fresh Linux 7.3 tarball reproduces `sources/linux-7.3` (diff -r empty); `kernel/sky_defconfig` + the three path/firmware settings reproduces the m24 `.config` exactly; `dts/sm4450-xiaomi-sky.dts` compiled with the kernel's own dtc is byte-identical to `sky-m24.dtb`; `tools/build-topology.sh` output sha256 506b435f… equals the tested topology.
- Differences from m24 on purpose: initramfs without the lab helper binaries (spi-xfer, fts-probe, touch-paint, memfill, rd/wr, sleeptest) and without the Bluetooth/QRTR userland, new clean `init` (no experiment observers), a freshly generated ssh key, Alpine packages resolved to the then-current versions.

## Plan: RAM boot of the clean-checkout build
- Input: `out/clone-test/out/boot/sky-boot-v4.img` (hash recorded below after the build). Phone: Android slot B, battery read first. `fastboot boot` only; recovery_b keeps m24.
- Run A (default, AUTOROOT=1): expected to switch into the Debian root on sda22 within ~10 s of boot; criteria: ssh as root works with the OLD project key (Debian has it), `uname -v` shows the new build, journal has `fs1599 … scene 6, 24 register entries` and `status register 0x0003`, sound card present, 0 failed units, GPU/display/touch/WiFi/BT unchanged (spot check), amp ON/OFF register test as in E034.
- Run B (AUTOROOT=0): initramfs shell only; criteria: `192.168.7.1` answers, ssh with the NEW key from `out/clone-test/vendor/ssh` works, dropbear listening, gadget bound, `ls /sys/class/drm`/`input` present, firmware requests (GPU, touch, ADSP, WPSS, BT) succeed in dmesg, safety reboot after 7 min returns to Android (not waited for, checked by reading the timer log).
- Fallback: power-cycle returns to Android; recovery_b still holds m24 (d8e0770e…).

## Build result (2026-11-13)
`tools/build-kernel.sh` in out/clone-test finished with exit 0 (log out/clone-test/build.log). out/boot/SHA256SUMS: Image 3198c107…, sky.dtb 537d8117… (identical to the m24 DTB), sky-boot-v4.img 5e67db36…, sky-recovery_b-v2.img 8591530c…. Needed `ALSATPLG=` because the build host has no alsatplg in PATH (documented in BUILDING.md).

## Run A result: RAM boot of the clean-checkout build (2026-11-13)
Input `out/clone-test/out/boot/sky-boot-v4.img` (5e67db36…), `tools/boot-ram.sh` (public flow), battery 78 % read in Android first, `fastboot boot` only.
- Booted into Debian on `/dev/sda22` through autoroot. `uname -v`: `#1 SMP PREEMPT Fri Nov 13 12:29:42 CET 2026` (the new build).
- Journal: `fs1599 0-0034: preset foursemi/fs1599.fsm: scene 6, 24 register entries`, `status register 0x0003`. Sound card present, card1/DSI-1/renderD128, 5 input devices (power key, resin, FocalTech touchscreen, gpio-keys, headset jack), `hci0` on UART.
- systemd `degraded`: only `sky-evdi.service` and `sky-wifi.service` failed with "Invalid module format". Cause: `qcacld` and `evdi` are out-of-tree modules built against the m24 kernel (vermagic/CRC), the rootfs still carries those; the clean kernel is a different build. Expected, not a build defect. Anyone who rebuilds the kernel must rebuild these modules (documented in BUILDING.md / KNOWN-ISSUES.md).
- Not run: the amp ON/OFF register test (no audio played on purpose), WiFi and dock on the clean build (modules above), touch/display by eye.

## Run B (AUTOROOT=0, initramfs only): built, NOT booted
The image was built (`sky-boot-v4.img` ce9b29e2…, exit 0) but not booted; no claim is made about the initramfs-only environment beyond what the init script says. The BUILDING.md wording was changed accordingly.
