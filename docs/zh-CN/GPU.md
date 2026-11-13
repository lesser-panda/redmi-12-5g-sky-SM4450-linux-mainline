# GPU

Adreno 613（A6xx 系列，GMU wrapper，没有独立 GMU 固件）。Mesa freedreno 提供 OpenGL ES 3.2，turnip 提供 Vulkan 1.0；GNOME Wayland 走 GPU 合成。

- **固件：** `a630_sqe.fw`（手机自己的，32504 字节；与 `linux-firmware` 的文件不同）和 `gen6_3_26_0_zap.mbn`（带签名的 zap shader），以 `qcom/sm4450/a613_zap.mbn` 名安装。名字相近的 `a610_zap` 是测试签名遗留，TrustZone 以 `-22` 拒绝：要看文件里的证书，不要看文件名。
- **内核：** 目录项、`gpucc-sm4450`（HLOS1 投票、GX GDSC、gfx3d RCG ops）、跳过 SPTPRAC 状态读、GPU/GMU/SMMU/qfprom/OPP 的 DT 节点（补丁 0003、0001）。
- **耗掉 17 次尝试的 bug：** 为了让 USB 在 8 GB 内存下工作加的 4 GiB `dma-ranges` 限制，让 DRM 缓冲走 swiotlb 反弹，写合并缓冲（GPU 微码、环缓冲）被旧缓存行覆盖：随机的非法指令故障。治本办法是让 USB 走 SMMU（`iommus = <&apps_smmu 0x540 0x0>`）并去掉限制。
- **Mesa：** 现用的 Mesa（26.1.x）没有芯片 613 的 id，所以目录项暂时报告 `revn = 612`（[KNOWN-ISSUES.md](KNOWN-ISSUES.md)）。
