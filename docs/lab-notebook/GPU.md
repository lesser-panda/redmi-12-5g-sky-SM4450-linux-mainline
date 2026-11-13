# GPU（Adreno 613）调查

日期：2026-11-10。只做离线调查，未上机。结论标注来源：[本机] 本机运行时 DT/源码核对；[源码] 上游或 ROCKNIX 源码；[网页] 搜索线索，未核实。

## 结论
- GPU 是 Adreno 613（chip id 0x06010300，gen6_3_26_0）。[本机] 运行时 DT `qcom,chipid = <0x6010300>`、`qcom,gpu-model = "Adreno613v1"`；与 Retroid Pocket Classic / Anbernic RG55G1（同 SM4450）一致。
- 内核侧已有 ROCKNIX 补丁并已应用到 sources/linux-7.3：0001（A613 目录项，沿用 `a630_sqe.fw` + `a613_zap.mbn`，GMU wrapper，无独立 GMU 固件）、0013/0014/0017/0018（gpucc-sm4450：hlos1 投票时钟、GX GDSC、gfx3d RCG ops）、0015（A613 无 SPTPRAC，跳过状态读）。[源码]
- Mesa 侧：Mesa main 的 freedreno_devices.py 把 613 与 608/612 同列为 `a6xx_gen1_low`（`GPUId(613)`），所以 freedreno（Gallium GL/GLES）和 turnip（Vulkan）都按同一设备表识别。[源码，已下载核对]
- turnip 是否「可用」：设备表里有它，ROCKNIX 的 SM4450 选项也启用了 `GRAPHIC_DRIVERS=freedreno` 与 `VULKAN_SUPPORT=yes`（说明他们的镜像带 turnip）。[源码] 但没有找到 A613 上 turnip 实测的公开记录，也不知道 gen1_low 的功能缺口；A610 级别的 turnip 历史上只有 Vulkan 1.1 且有缺项（mesa issue 9453）。[网页] **结论：大概率能出 Vulkan 设备，能否跑 Vulkan 1.3 应用未知，需上机实测。**
- 对桌面更重要的是 freedreno Gallium（GLES/EGL），不是 turnip：Weston/GNOME/Sway 合成器要 EGL/GLES，turnip 只给 Vulkan 应用。Alpine v3.24 的 mesa 26.1.6 有 `mesa-dri-gallium`、`mesa-egl`、`mesa-gles`、`mesa-vulkan-freedreno`（2.6 MB）。[本机，APKINDEX]

## 还缺什么（上机前）
1. **固件**：`qcom/a630_sqe.fw`（linux-firmware 有，本机没有，需下载并记录哈希）；`a613_zap.mbn`（高通签名的 zap shader，来自厂商 vendor 分区，不在 linux-firmware）。本机 private/ 里只有 boot/vendor_boot/dtbo 等，没有 vendor 镜像；PixelOS OTA（private/rom/…zip，1.75 GB）的 payload 里可能带 vendor，需用 sources/payload-dumper-go 提取后核对；或在 Android 下用 root 从 /vendor/firmware 取。固件属私有，放 private/，不提交。
2. **DT**：mainline sm4450.dtsi 只有 gpucc，没有 gpu、gmu_wrapper、adreno_smmu、OPP 表和 speed_bin nvmem。可参考 ROCKNIX 的 sm4450-retroid-pocket-classic-common.dtsi（gpu@3d00000、gmu@3d6a000、iommu@3da0000）。本机差异：保留给 zap 的 `gpu-microcode` 区在 **0x89c1a000**（本机运行时 DT；m8/m9 已按它保留），ROCKNIX Retroid 是 0x8941a000，不要照抄。
3. **内核配置**：DRM_MSM 已内置，GPU 部分（a6xx）随 DRM_MSM 编译，QCOM_SCM/PAS/MDT_LOADER 由其 select；要确认 SM_GPUCC_4450 改为内置或 initramfs 放模块（现为 =m）。
4. **speed bin**：ROCKNIX 用 `nvmem-cells = <&gpu_speed_bin>`，需要 qfprom 节点；本机未建模，可先用最低 OPP 或确认 qfprom 偏移。
5. **风险**：zap shader 经 TZ（SCM）认证，失败通常只是 GPU 初始化失败（不影响显示），但 GPU 时钟/GDSC 操作若出错可能挂死整机——同 mmio 的教训，首次上机需要用户在场并流式看 dmesg。

## 建议路线
1. 离线：下载 linux-firmware 的 a630_sqe.fw；从 OTA 提取 vendor 找 a613_zap；写 m10 DTS（= m9 + gpu/gmu/smmu/OPP，先不放开 speed bin）；Alpine 加 mesa-dri-gallium/egl/gles/vulkan-freedreno，Weston 改 gl 渲染器。
2. 上机（用户在场）：看 `msm_drm` / `adreno` 的 dmesg、`/dev/dri/renderD128`，再用 `vulkaninfo` / `kmscube`/`weston --renderer=gl` 验证。
3. 失败退路：m9 + pixman 桌面不变。

## 更新（同日，离线准备完成）
- 固件已取得：PixelOS OTA 的 vendor 镜像（private/gpu/ota/vendor.img，由 payload-dumper-go 提取）里 /firmware 有 `a630_sqe.fw`（32504 B）和 `a610_zap.{mdt,b00,b01,b02,elf}`；没有 a613 命名的文件。A613 的 zap 推断为 a610_zap（vendor 唯一的低端 Adreno zap）。提取结果在 private/gpu/fw/，上机时 `a610_zap.elf` 以 `qcom/sm4450/a613_zap.mbn` 名进 initramfs（驱动用 request_firmware_direct 读单文件 ELF）。
- DT、构建、桌面包、测试脚本已就绪：m10 候选（out/candidates/m10，哈希见 EXPERIMENT-006 E012）、tools/gpu-test.sh。尚未上机。

## 结果（2026-11-10，m10 已上机，详见 EXPERIMENT-006 E012 运行记录）
- 可用：A613 硬件初始化通过；Mesa freedreno（EGL/GLES 3.2，渲染器名 FD612）和 turnip（Vulkan **1.0**）可用；Weston 以 `renderer=gl` 运行，kmscube 跑通。
- 与上面「还缺什么」的修正：zap 固件不是 a610_zap（test 签名遗留，TZ 拒绝，-22），而是 vendor 的 `firmware/gen6_3_26_0_zap.mbn`；SQE 用 vendor 的 `a630_sqe.fw`（32504 B，与 linux-firmware 版不同）。
- 关键坑（给下一个移植者）：m9 的 4 GiB `dma-ranges` 权宜之计会让 DRM 设备的 GEM 页走 swiotlb 反弹，写合并缓冲（GPU 微码/环缓冲）被旧缓存行覆盖 -> CP 非法指令/挂起检测。治本：USB 放进 SMMU（`iommus = <&apps_smmu 0x540 0x0>`），去掉 dma-ranges 限制。
- 关键坑 2：Mesa（Alpine 26.1.6）设备表没有 A613；内核 `.revn = 612` 作为权宜之计（见 TECH_DEBT）。更新 Mesa（带 `GPUId(613)`）后改回 `.revn = 613` 或去掉。
- 未做：多档 GPU 频率（目前 OPP 只留 340 MHz）、interconnect 带宽值（保留 ROCKNIX 的 opp-peak）、GPU 电源管理/休眠、Mesa 版本升级、屏幕上的人眼验证。
