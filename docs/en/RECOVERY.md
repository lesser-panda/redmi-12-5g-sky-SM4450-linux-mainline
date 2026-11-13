# Safety and recovery

## Rules the project followed (and you should too)

1. **Start from RAM.** `fastboot boot` writes nothing. Every kernel change was first tried this way.
2. **A safety net inside the image.** The initramfs reboots after 7 minutes (the phone boots Android by default) unless told otherwise; `panic=15` reboots after a kernel panic.
3. **Read the battery before leaving Android**, keep it above 50 %.
4. **One partition at a time.** `tools/flash-recovery-b.sh` writes `recovery_b` only (the PixelOS slot-B recovery, which nothing else uses), saves the old content first and reads it back.
5. **Keep the fallback.** The previous working image stays on your disk; Android's own boot, vendor_boot and dtbo are never touched.

## Getting out of trouble

| Situation | What to do |
|---|---|
| Phone in a bootloader (fastboot) loop after flashing `recovery_b` | `fastboot boot out/boot/sky-boot-v4.img` (RAM boot) to get a Linux shell, then `reboot`. Or restore the saved image: `fastboot flash recovery_b vendor/backup/recovery_b-<time>.img`, or flash the stock `recovery.img` from the ROM |
| Phone dark, no screen, no USB | hold power for 10-15 s (hard reset); the phone then boots Android (default slot), from where `adb reboot bootloader` gets you to fastboot |
| Linux hangs | hold power 10-15 s. Android boots next. `reboot -f` from Debian has once left the phone unreachable: use `systemctl reboot` |
| Android lost its data after repartitioning | expected (see INSTALLING.md); the restore path is the saved GPT plus a factory reset |
| You want Android back completely | `fastboot flash recovery_b` the stock recovery from the ROM; the partitions you added can stay unused or be merged back with the saved GPT |

## Known sharp edges

- `cat /sys/kernel/debug/gpio` or reading unknown TLMM/PMIC registers through `/dev/mem` can hard-freeze the SoC. Do not.
- Flashing a boot image with the wrong header version to `recovery_b` makes the bootloader refuse it and fall back to fastboot, as described in
  [ARCHITECTURE.md](ARCHITECTURE.md). It is recoverable as above.
- `adb reboot bootloader` followed by `fastboot reboot` does not leave a persistent boot flag; Android keeps booting by default.
- Nothing here relocks the bootloader. Do not relock a device running a modified boot chain.
