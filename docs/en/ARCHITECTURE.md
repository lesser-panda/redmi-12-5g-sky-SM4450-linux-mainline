# How it boots, and why it looks this way

## The boot chain

```
power on -> Qualcomm boot ROM -> XBL -> ABL (Android bootloader, unlocked)
              |                                   |
              |                       default: boot_b -> Android (PixelOS)
              |                       adb reboot recovery: recovery_b -> our image
              v
        our boot image (Android boot image header v2)
              kernel   = "shim" (sky-linux): a tiny arm64 program that relocates the payload and jumps to it
              payload  = Linux 7.3 Image (initramfs built in) + our device tree
              dtb      = the phone's stock vendor_boot DTB (ignored by the shim, but the ABL insists on one)
              recovery_dtbo = the stock dtbo.img
```

- **The shim.** The stock ABL expects an Android kernel with the vendor device tree and applies overlays itself. The shim (from
  [sky-linux](https://github.com/orange200213/sky-linux)) takes the control back: it carries our own device tree, loads Linux 7.3 at 0xC0000000
  and hands over. The display is left lit by the bootloader (continuous splash), which is why the first frames on screen are the
  firmware's framebuffer, taken over by the `msm` driver later.
- **Why `recovery_b` and header v2.** `fastboot boot` needs a PC. For a hands-free start the image has to live in a partition the
  bootloader loads by itself. With a kernel inside `recovery_b` the ABL loads only vbmeta, the recovery image and the dtbo partition; it
  does **not** read `vendor_boot`. A header-v4 image therefore has no DTB and the ABL falls back to fastboot ("LoadImageAndAuthVB2() Not Found").
  Header v2 carries its own DTB (we embed the stock vendor_boot DTB). It also needs `recovery_dtbo`: without it the ABL reports a bad
  dtbo header, does not set up the splash region and powers the panel down, so the display driver has to cold-start the panel and fails.
  The working combination is v2 + stock DTB blob + stock dtbo as `recovery_dtbo` (this took seven attempts; see the lab notebook, E028).
- **Android stays default.** Slot B's `boot` is not modified. `adb reboot recovery` starts Linux, a plain reboot starts Android,
  `systemctl reboot` in Linux goes back to Android. Slot A is unused.
- **The safety reboot.** The initramfs `init` reboots after 7 minutes unless extended, so an image that comes up but cannot be reached
  returns to Android by itself. The built-in `autoroot` marker makes it mount the Linux root and `switch_root` into it, which also disables that timer.

## The initramfs

Busybox (static), dropbear (key-only ssh), a DHCP server and a USB gadget with ACM serial and NCM Ethernet (`192.168.7.1`).
Vendor firmware that drivers request early lives here (`/lib/firmware`): GPU, touch, ADSP, WiFi processor, Bluetooth.
Two firmware files are built into the **kernel** instead: the audio topology and the FS1599 amplifier preset
(`CONFIG_EXTRA_FIRMWARE`). Reason: the sound card probes at about 7 s, while the hands-free `init` switches to the real root within milliseconds; the firmware
was no longer reachable by then and the card failed with "No soundcards found". Built-in firmware has no such race.

## Storage layout (persistent install)

`sda` is the main UFS LUN. The install shrinks `userdata` (`sda20`, f2fs, encrypted by Android so it cannot be resized offline) from about 108 GiB to 40 GiB
and adds `linuxboot` (`sda21`, 1 GiB ext4, `/boot`) and `linuxroot` (`sda22`, ~67 GiB ext4). Android is reset to factory state on the smaller `userdata`.
Boot chain partitions are on other LUNs and are not touched. `init` mounts `sda22` only if its GPT name is `linuxroot`.

## Device tree

`dts/sm4450-xiaomi-sky.dts` is a board file written from the phone's own runtime device tree (memory banks, reserved regions, GPIOs,
regulators, SMMU stream IDs) and its dtbo (panel timings, DSC, init sequence). SoC nodes come from the upstream `sm4450.dtsi` plus the
patches. Board numbers were never copied from other SM4450 devices (they differ: for example the GPU zap shader carve-out).

## Kernel patch series

| Patch | Contents |
|---|---|
| 0001 platform | clocks, power domains, interconnect, SMMU, PAS remoteprocs, RPMh regulators, pd-mapper, TLMM, UFS PHY, `sm4450.dtsi` |
| 0002 display | DPU for SM4450 with DSC, boot-scanout handling |
| 0003 gpu | Adreno 613 |
| 0004 panel-backlight | Xiaomi sky DSI panel, KTD3136 backlight |
| 0005 touch-input | FocalTech FT8720 SPI touch driver, edt-ft5x06 power-follow |
| 0006 bluetooth-wifi | WCN3950 Bluetooth, power sequencer minimum off time |
| 0007 audio | RX macro stride fix, FS1599 amplifier driver |
| 0008 power-usb | battery software charge limit, dwc3-qcom resume fix |
