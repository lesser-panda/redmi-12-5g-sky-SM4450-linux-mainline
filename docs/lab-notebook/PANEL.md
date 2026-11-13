# 面板：xiaomi_m19_42_03_0b（本机证据）

来源：private/rom/extracted/dtbo.img（PixelOS 20240922 发行包）。29 个 DT 覆盖层，其中 22 个含 `m19_42_03_0b`/`0c` 变体；解析：Android dtbo 头（大端），逐项 dtc 反编译，见 private/dtbo-extract/NN.dts（不提交）。
运行时 FDT（/sys/firmware/fdt）只有 Qualcomm "Simulator" 占位面板，真实面板节点在 dtbo。bootargs 指定 `msm_drm.dsi_display0=qcom,mdss_dsi_m19_42_03_0b_fhd_dsc_vid`，故本机用 0b。
未确认：dtbo 的 22 个变体里哪个条目被 ABL 选中（0b 与 0c 的 DCS 序列第 4 个字节不同：ff 87 20 vs ff 87 25）。用户陈述 + cmdline 指向 0b，覆盖层选择仍需核实。

## 参数（entry 00，0b）
- 视频模式（dsi_video_mode），4 lane，burst，24 bpp，lp11-init。
- 1080 x 2460（0x438 x 0x99c），90 Hz（dfps 列表 90/60/49/30），物理 69 x 158 mm。
- 时序：h 前肩 76、后肩 56、脉宽 8；v 前肩 10、后肩 20、脉宽 10；phy-timings `00 18 06 06 15 20 06 06 07 02 04 00 15 0b`；t-clk-pre 0x15、post 0x0b。
- DSC：block-prediction，8 bpc，8 bpp，slice 540 x 20，每包 2 slice；topology 1/1/1。
- 复位序列：<0 1 1 4 0 1 1 12>（电平/毫秒对）。
- ESD：读 0x0a 期望 0x9c。
- DCS 初始化：`qcom,mdss-dsi-on-command` 约 90 条厂商命令（含 `ff 87 20 xx` 解锁序列），CABC（0x55 0..3），off 序列。
- 面板控制芯片型号尚未识别。

## 对 framebuffer 的印证
1080 x 2460 与 sky-linux 的 simple-framebuffer 尺寸一致（ABL 扫描 1080x2460，stride 4320），这条原先标"未验证"，现在有本机 dtbo 证据（高度 0x99c = 2460）。

## 下一步（面板驱动路线）
1. 整理 on/off 命令为可读的 DCS 序列；识别 IC。
2. rebase ROCKNIX 0009（SM4450 DPU/MDSS）到 7.3；核对上游 DSC 支持。
3. 写 panel 驱动骨架（mipi_dsi、DSC、regulator/reset GPIO、背光），GPIO/电源从 runtime DT 的 panel 供电节点取证。
4. 单变量实验：先不接管，只验证 DSI 链路。

## 板级接线（本机证据：运行时 FDT + dtbo，2026-11-09）
| 项 | 值 | 来源 |
|---|---|---|
| 复位 | TLMM GPIO 92（dtbo `qcom,platform-reset-gpio = <&tlmm 0x5c>`） | dtbo |
| vddio | 固定调压器 display_panel_vddio，GPIO 11 高有效，1.8 V，boot-on | 运行时 FDT |
| extvdd | 固定调压器 display_panel_extvdd，GPIO 12 高有效，1.2 V，boot-on | 运行时 FDT |
| avdd | 固定调压器 display_panel_avdd，GPIO 127 高有效，5.5 V，boot-on，ramp 233 µs | 运行时 FDT |
| 面板 supply 约束 | vddio 1.8–2.0 V；avdd 4.6–6.0 V | dtbo dsi_panel_pwr_supply_lcd |
| 背光 | GPIO 7 PWM 功能（func1）+ GPIO 6 使能；真实面板的 bl 控制类型未在覆盖层确认 | 运行时 FDT |
| TE | dtbo 有 `qcom,platform-te-gpio`，引脚号待解 | dtbo |
| SoC 显示块 | MDSS ae00000、DPU ae01000、DSI0 ae94000、DSI PHY ae94400（sm4450-dsi-phy-5nm / sm8450 兼容），DISPCC 已有 | ROCKNIX 板文件 + 运行时 DT 地址 |
ROCKNIX 板文件同样用 TLMM 92 复位，但其面板是 FocalTech FT7131M（手持机），供电、背光、面板驱动均不适用于本机。
三条轨都是 GPIO 固定调压器且 boot-on：ABL 已经上电，Linux 接管时只要不关它们（regulator-always-on 或 boot-on）屏幕就不会灭。

## 0009 rebase 结果（2026-11-09）
ROCKNIX 0009 除 `drivers/soc/qcom/ubwc_config.c` 外直接应用（git apply --exclude）。该文件的 hunk 在 7.3 里重构成共享描述符；核对 include/linux/soc/qcom/ubwc.h 后确认 `ubwc_2_0_hbb14`（UBWC 2.0、HBB 14）在 7.3 中隐含 swizzle=LVL2|LVL3、bank_spread=true，等价于补丁里的 sm4450_data，故改成一行 `{ .compatible = "qcom,sm4450", .data = &ubwc_2_0_hbb14 }`。
尚未编译（sky-m1.config 里 DRM_MSM 未启用），尚未上机。

## 风险与待办
- DPU 需要 IOMMU：主线要有 apps_smmu 节点。一旦 arm-smmu 驱动接管，USB（stream 0x540）也必须挂 iommus，否则 USB DMA 会被拦（目前 USB 靠 ABL 遗留的 bypass 工作）。单变量排查顺序：先只加 smmu + USB iommus 验证 USB 不坏，再接显示。
- interconnect 节点同样缺（mdp0-mem 等），ROCKNIX 板文件有，需核对。
- 面板驱动自写：on/off 序列已解码（private/dtbo-extract/panel-0b-sequences.txt）；DSC 参数（8 bpp、slice 540x20）要交给 DPU/DSI 的 DSC 帮助函数。

## OCP2131 偏压 IC（本机证据，2026-11-10 从运行时 DT 发现）
- 运行时 DT：面板 I2C（QUP wrapper0 SE1，与 KTD3136 背光同总线）上 `ocp2131@3e`（compatible `qcom,ocp2131_bias`），`lcm-enp-gpio = <PM7250B gpio2>`、`lcm-enn-gpio = <PM7250B gpio4>`。这是 LCD 正/负偏压（AVDD/AVEE 类）使能，此前文档未提及；目前沿用 ABL 遗留状态，Linux 未触碰。
- 影响：真正的关屏/休眠断电顺序需要它；要在 SPMI + pm7250b-gpio 建立后才能控制。主线暂无该 IC 驱动（需另查：可能用 regulator-gpio/固定调压器模型，I2C 寄存器是否需配置未知）。
