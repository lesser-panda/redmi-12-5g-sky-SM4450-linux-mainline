# Installing to the phone

Two levels. Do level 1 first; level 2 is only needed for the persistent desktop system and **erases Android's user data**.

## Level 1: hands-free start from `recovery_b` (one partition, recoverable)

Prerequisite: [BUILDING.md](BUILDING.md) worked and `out/boot/sky-recovery_b-v2.img` exists; the RAM boot reached a shell.

```sh
# phone: Android, slot B, USB debugging, root, battery > 50 %
tools/flash-recovery-b.sh
```

The script refuses on the wrong slot or a low battery, saves the current `recovery_b` to `vendor/backup/`, asks for confirmation,
flashes with `fastboot`, reads the partition back and compares hashes. Then:

```sh
adb reboot recovery     # starts Linux
ssh -i vendor/ssh/id_ed25519 root@192.168.7.1
# in Linux:  systemctl reboot   -> back in Android (on the busybox image: reboot)
```

Without a Linux root partition this boots the small initramfs system and, after 7 minutes, returns to Android on its own.

## Level 2: Debian + GNOME on internal storage (destructive)

What changes: the phone's main flash chip gets a new partition table, the Android data partition shrinks from about 108 GiB to 40 GiB and is
wiped (Android comes back through its first-boot setup), and two partitions are added for Linux. Boot-chain partitions, `modem`, `persist` and slot A are not touched.
Back up everything you care about first, and save the GPT as described in [EXTRACTING-VENDOR-FILES.md](EXTRACTING-VENDOR-FILES.md).

1. **Plan the layout.** `tools/gpt-split-sda.py <gpt-head.bin> <gpt-tail.bin> <outdir> [userdata_gib] [boot_gib]` reads the first and last MiB
   of `sda` (taken from your phone) and writes the new GPT blocks and a plan to `<outdir>` without touching any device. Check the plan with
   `sfdisk` (22 partitions, no overlap, no free gap). We **do not ship an automatic writer**: writing three GPT blocks (primary table,
   backup entries, backup header) is the one step where a typo costs the phone's partition table, so do it by hand, from a RAM-booted Linux,
   after comparing the live blocks with your backup byte for byte. The exact sequence used on the test phone, with checks, is in the lab notebook (E025).
2. **Reset Android's data.** Zero `metadata` (`sda12`) and the start of `userdata` from the RAM-booted Linux, then let Android do its first-boot setup (enable USB debugging again).
3. **Build the Debian root.** `tools/deb-fetch.py` and `tools/build-debian-stage1.py` assemble a verified Debian trixie arm64 base
   (`debootstrap --foreign` style: nothing from the packages runs on your PC). `tools/push-debian.sh` pushes it to the RAM-booted phone, runs the second stage
   (`dpkg --configure`, 20-40 minutes), applies `rootfs/customize.sh` (user, GNOME autologin, services, power defaults, UCM audio profile) and, with `PERSIST=1`,
   creates the ext4 filesystems (it refuses unless the GPT names of `sda21`/`sda22` are `linuxboot`/`linuxroot`) and copies the root there.
4. **WiFi and the dock (optional).** `tools/fetch-sources.sh --rootfs`, then `tools/build-wifi-modules.sh` (vendor `qcacld` driver, out of tree, must match the kernel in the boot image) before step 3;
   DisplayLink needs the vendor driver archive and `tools/build-evdi.sh` + `tools/displaylink-stage.sh` (see [DOCK.md](DOCK.md)).
5. **Boot it.** With `/etc/autoroot` in the image (the default) `adb reboot recovery` mounts `sda22` and switches into it. Login: the desktop user `user`
   (autologin on the screen), `ssh` with your key as root over USB, and GNOME. WiFi credentials are not shipped: `vendor/wifi/credentials.txt` with `ssid=`/`psk=` lines is read by `push-debian.sh`, or use GNOME settings.

**Status of level 2:** these scripts built the system that the project ran and tested for days, but they have **not been re-run from a clean checkout** since publication
(each depends on a live phone and takes about an hour). Expect to fix small things, and please send fixes.
