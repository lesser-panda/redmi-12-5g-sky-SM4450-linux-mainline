# tools/

Run everything from the repository root (scripts find their own location).

## The main flow (verified)
| Script | What it does |
|---|---|
| `fetch-sources.sh` | download and hash-check the kernel tarball, cross toolchain, sky-linux shim, topology sources, payload-dumper-go (`sources.lock`); `--rootfs` adds the WiFi driver, fw-api and evdi |
| `extract-vendor-files.sh` | collect your proprietary firmware from the ROM zip and your phone's partitions into `vendor/` (`vendor-files.sha256` lists the tested hashes) |
| `build-topology.sh` | build the AudioReach topology firmware from the upstream source |
| `build-initramfs.sh` | stage the initramfs tree and list (uses `apk-fetch.py`, `gen-initramfs-list.py`) |
| `build-kernel.sh` | patch tree, config, build, device tree, boot images: everything up to `out/boot/` |
| `boot-ram.sh` | `fastboot boot` the image and wait for `192.168.7.1` (writes nothing) |
| `flash-recovery-b.sh` | the only script that writes to the phone: `recovery_b`, with backup, confirmation and read-back |

## Root filesystem (used for the original install, not re-run from a clean checkout)
`deb-fetch.py`, `build-debian-stage1.py`, `debian-roots.txt`, `debian-base.txt` (verified Debian trixie base),
`push-debian.sh` (build and optionally persist the root), `gpt-split-sda.py` (dry-run partition planner),
`build-wifi-modules.sh`, `wifi-up.sh` (vendor WiFi driver), `build-evdi.sh`, `displaylink-stage.sh`, `install-displaylink.sh` (dock).

## Validation
`loadtest.sh` (runs on the phone) and `loadtest-host.sh` (on the PC), `memhog.py`: the synthetic load test used for the stability run (see the lab notebook, E032).
