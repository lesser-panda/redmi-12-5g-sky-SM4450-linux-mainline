# Known issues and technical debt

Honest list of what is rough. Items marked (code) are visible in the tree.

## Hardware not working
Cellular, cameras, sensors, GPS, NFC, fingerprint, vibrator: see [STATUS.md](STATUS.md).

## Behaviour
- **Dock + suspend:** with the DisplayLink dock attached the phone sometimes wakes from suspend after 0.1-2 s by itself; keyboard wake and a power-key press may retrigger a wake. The wake source is not identified (kernel built with `PM_DEBUG`; the `pm_wakeup_irq` test is still to do). GNOME idle suspend and the power-key suspend are disabled by default for that reason.
- **Resume with USB host attached:** one xHCI resume timeout of about 35 s was seen; recovery needed a `dwc3-qcom` rebind (a resume fix is in patch 0008, hypothesis not fully proven).
- **`reboot -f` from Debian** once left the phone unreachable; use `systemctl reboot`.
- **glmark2** shows a ~15 % score drop in some periods of the load test; cause not found.
- **PMIC RTC** cannot be written by Linux (the SPMI arbiter denies writes, the peripheral belongs to another subsystem) and does not keep time; NTP sets the clock at boot. `CONFIG_RTC_SYSTOHC` is off because every NTP sync made the kernel retry the denied write about 60 times a second (seen in the log as `disallowed SPMI write to sid=0, addr=0x6146`; the message is now rate limited too).
- **Bluetooth** needs the 1 s minimum power-off patch to come up reliably after cold boot.
- **WLAN driver:** the vendor `qcacld` driver is out of tree and must match the kernel exactly. Its leftover `sky-dbg` traces are quiet (`tools/qcacld-quiet-debug.patch`, applied by `build-wifi-modules.sh`); some info-level driver lines remain.

## Code and configuration debt
- (code) The kernel tree contains leftover GPU debug code (register dump on CP init failure, firmware readback checks).
- (code) The A613 catalog entry reports `revn = 612` so that Mesa 26.1.x accepts it. Change it back to 613 when Mesa knows the id.
- (code) ROCKNIX files that this phone does not use are kept so the tree equals what was tested: `rsinput.c`, `aw88166.c`, an ath10k change.
- (code) The thermal zones come from the ROCKNIX SM4450 board file and use generic 95 C / 115 C trips; they are not tuned for this phone and throttling has not been exercised. There are no low CPU max-frequency limits yet.
- (code) The boot image carries Android-specific header tricks (v2 header, stock DTB blob, `recovery_dtbo`) that exist only to satisfy the ABL.
- (rootfs) `rootfs/` scripts are for Debian trixie and use a hand-made `debootstrap --foreign` replacement that was not designed for reuse.
- **Out-of-tree modules are bound to the kernel build.** `qcacld` (WiFi) and `evdi` (dock) must be rebuilt for every kernel you build; a module from another build fails with "Invalid module format" and `sky-wifi.service` / `sky-evdi.service` fail. The rootfs scripts build them against `sources/linux-7.3`.
- (tools) `evdi` is an out-of-tree kernel module for the DisplayLink dock; the DisplayLink driver is a proprietary download.
- The Alpine packages in the initramfs are resolved to the current version at build time (verified signatures, but versions drift).
- Linux 7.3 is a development kernel; nothing here is on an upstream path yet except candidates in [UPSTREAMING.md](UPSTREAMING.md).
