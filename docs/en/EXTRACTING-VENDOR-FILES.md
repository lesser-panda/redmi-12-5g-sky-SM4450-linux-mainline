# Extracting the proprietary files from your own phone

The kernel needs binary blobs that belong to Xiaomi, Qualcomm and others. They are **not** in this repository and must not be
published. `tools/extract-vendor-files.sh` collects them from two sources you already have:

1. **The PixelOS ROM zip** `PixelOS_sky-14.0-20240922-0137.zip` (sha256 `f37e76809187646b24408fda323f8f11851d347f30969fc17d295b19bc8e3b48`,
   from the PixelOS download page for `sky`). The script runs `payload-dumper-go` on it and takes `vendor_boot.img`, `dtbo.img` and
   the `/firmware` directory of `vendor.img`.
2. **The phone's own `modem_a` and `bluetooth_a` partitions**, which carry the ADSP, WiFi processor, WiFi calibration and Bluetooth
   firmware of your exact device (the ROM does not contain them). Read them with `--from-phone` (needs root, e.g. Magisk; the script only reads),
   or pass dumps you made earlier with `--modem` / `--bluetooth`.

```sh
tools/extract-vendor-files.sh --rom PixelOS_sky-14.0-20240922-0137.zip --from-phone
# or, with existing dumps
tools/extract-vendor-files.sh --rom ... --modem modem_a.img --bluetooth bluetooth_a.img
```

## What ends up where

| Path in `vendor/` | Source | Used for |
|---|---|---|
| `rom/vendor_boot.img`, `rom/dtbo.img` | ROM | the `recovery_b` boot image (the boot loader needs a DTB blob and a dtbo overlay there) |
| `rom/recovery.img` | ROM | the stock recovery, to restore `recovery_b` |
| `fw/a630_sqe.fw`, `fw/gen6_3_26_0_zap.mbn` | ROM `vendor.img:/firmware` | Adreno 613 microcode and the signed zap shader |
| `fw/focaltech_ts_fw_.bin` | ROM `vendor.img:/firmware` | FT8720 touch controller firmware (downloaded by the driver at each reset) |
| `fw/fs1599.fsm` | ROM `vendor.img:/firmware` | FS1599 speaker amplifier preset, built into the kernel image |
| `fw/modem/adsp.*` | `modem_a` | ADSP remoteproc (audio, battery, USB-C) |
| `fw/modem/adrastea/*` | `modem_a` | WiFi processor (`wpss.*`), `regdb.bin`, WiFi board data `bdwlan*` |
| `fw/bt/*` | `bluetooth_a` | Bluetooth firmware and NVM |

Every file is compared with [tools/vendor-files.sha256](../../tools/vendor-files.sha256), the hashes of the files the project was tested with.
A difference is reported but is not fatal (another firmware build can work, or not). The ROM hash is checked strictly.

## Back up your phone first

Before you experiment, copy the boot-chain partitions and the GPT headers off the phone (read-only, from Android with root): `boot`,
`vendor_boot`, `dtbo`, `recovery`, `vbmeta*` of both slots, `modem`, `bluetooth`, `persist`, `modemst1/2`, `fsg`, `fsc`, and the first and last
MiB of `sda` (the GPT). The persistent install repartitions `sda`; those GPT backups are what lets you put the old table back.
The lab notebook (E003) lists what was backed up and how it was checked (device-side hash equals host-side hash).
The audio topology firmware is **not** a vendor file: it is built from upstream sources by `tools/build-topology.sh`.
