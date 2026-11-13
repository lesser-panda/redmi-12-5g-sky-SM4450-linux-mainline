# GPU

Adreno 613 (A6xx family, GMU wrapper without a separate GMU firmware). Mesa freedreno gives OpenGL ES 3.2, turnip Vulkan 1.0; GNOME Wayland composites on the GPU.

- **Firmware:** `a630_sqe.fw` (the phone's own, 32504 bytes; the `linux-firmware` file differs) and `gen6_3_26_0_zap.mbn`, the signed zap shader, installed as `qcom/sm4450/a613_zap.mbn`. A look-alike `a610_zap` is a test-signed leftover that TrustZone rejects with `-22`: check the certificate in the file, not the name.
- **Kernel:** catalog entry, `gpucc-sm4450` (HLOS1 vote, GX GDSC, gfx3d RCG ops), skip the SPTPRAC state read, DT nodes for GPU, GMU, SMMU, qfprom and OPPs (patch 0003, 0001).
- **The bug that cost 17 attempts:** a 4 GiB `dma-ranges` limit that had been added to make USB work with 8 GB RAM made DRM buffers bounce through swiotlb. Write-combined buffers (GPU microcode, ring buffer) were overwritten by stale cache lines: random illegal-instruction faults.
  The fix was to put USB behind the SMMU (`iommus = <&apps_smmu 0x540 0x0>`) and drop the limit.
- **Mesa:** the Mesa in use (26.1.x) has no id for chip 613, so the catalog entry reports `revn = 612` for now ([KNOWN-ISSUES.md](KNOWN-ISSUES.md)).
