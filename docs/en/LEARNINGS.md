# Lessons for the next porter

Short version of what cost the most time; the Chinese edition has the long, device-by-device list ([../zh-CN/LEARNINGS.md](../zh-CN/LEARNINGS.md)).

**Process**
1. Build the way back before the first experiment: `fastboot boot` (no writes), an in-image reboot timer, `panic=15`, a long power press. Over dozens of failed boots nothing needed rescuing.
2. One variable per experiment; write expectation, pass criteria and fallback before booting. Keep failures in the notes.
3. "Same input, different result" means memory or cache coherency, not a wrong register value.
4. Add read-back checks after DMA/GPU buffer writes; one comparison proved what days of register reading could not.
5. Temporary workarounds go into a debt list, and are the first suspects for anything unexplained (the 4 GiB `dma-ranges` hack silently broke the GPU).
6. Search whole files (`7z l | grep`), do not read the first page of a listing; check signing certificates, not file names, for firmware.

**Evidence**
7. The runtime device tree and the `dtbo` of the running Android are the best source of board numbers (memory banks, carve-outs, GPIOs, stream IDs, panel timings). Never copy those from another device with the same SoC.
8. The vendor image of an OTA is a firmware treasure chest (`/firmware`: GPU, touch, amplifier presets); modem/Bluetooth/WiFi firmware is only in the phone's partitions: back them up early.
9. Vendor driver sources give protocols; verify on the bus (a CRC or an ID register read) before writing a driver.

**Hardware**
10. DMA devices behind an SMMU need their `iommus`; limiting DMA ranges instead corrupts write-combined buffers through swiotlb.
11. Dangerous reads: unknown TLMM/PMIC registers and `/sys/kernel/debug/gpio` freeze the SoC. SPMI SIDs come from `reg`, not from the node name.
12. Power sequencing needs real off time (Bluetooth chip: 0.5 s with the rail off). Retries in the driver do not replace it.
13. Firmware that a driver needs at probe time must be reachable when the driver probes: a hands-free `init` that switches root within milliseconds loses initramfs firmware. Build such files into the kernel.
14. User-session units enabled globally also run for root's user manager when root has a login session; a second copy of a "watcher" can undo the first one's work.
15. Kernel timestamps do not count suspended time; use wall-clock stamps to judge suspend.
