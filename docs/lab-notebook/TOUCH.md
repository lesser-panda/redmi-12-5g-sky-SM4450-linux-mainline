# 触摸（FocalTech SPI）调查

原始取证（含 DT 属性十六进制）在 private/touch/（不入库）。以下区分来源。

## 本机验证（Android，root，只读，2026-11-09）
- 触摸设备 `fts_ts`，挂在 `spi0.0`，控制器 a84000.spi（QUP 包装器 1 的 SE1；厂商 DT 的 `spi@a84000`）。节点名 `novatek@0`，compatible = `novatek,NVT-ts-spi` + `focaltech,fts`，实际绑定的是 FocalTech 驱动（Driver V3.4 20211214，IC ID 0x8720，SPI mode 0，9.6 MHz）。另有 NVT-ts 驱动已注册但未绑定。
- 参数：reg 0；IRQ = TLMM 13，下降沿（Android 里为 msmgpio 13 Edge）；RESET = TLMM 12；最多 10 点；坐标范围 0–10800 × 0–24600（面板 1080×2460 的 10 倍）；控制器 IRQ = GIC SPI 354 电平高；SE 时钟 gcc 0x4c/0x56/0x57（se、m-ahb、s-ahb）。
- SPI 引脚（pinmux-pins 的 a84000.spi 占用）：gpio26、27、50、51。
- 厂商 DT 未列触摸供电（reset/irq 之外无 vdd/vio 属性）：供电来源待查（可能共用面板轨或常开）。
- Android 时钟：只有 gcc_qupv3_wrap1_s1_clk 开启（19.2 MHz）；gcc_qupv3_wrap1_core_clk 与 core_2x_clk 均为 0。→ 包装器 1 的“核心”供给不是靠这两个 GCC 时钟，推测来自 RPMh 互连投票（qup-core）。

## 源码证据
- 主线没有 FocalTech SPI 触摸驱动（edt-ft5x06 仅 I2C；novatek-nvt-ts 仅 I2C）。需要自写或移植厂商 FTS 驱动（GPL，厂商源码是否可得待查）。
- sky-linux/docs/touch-handoff/HANDOFF-TOUCH.md（网页线索 + 其本机记录）：SPI 控制器可探测，但传输永不执行（SE_GENI_STATUS 恒 0、无错误位）；他们 DT 有 interconnects 引用 clk_virt/gem_noc/config_noc，但内核/DT 是否真有投票未证实；加载 qupv3fw 会 panic。其结论没有解决。
- 内核树：CONFIG_INTERCONNECT_QCOM_SM4450=y、QCOM_RPMH/COMMAND_DB/RPMHPD 均已开；sm4450.dtsi 有 apps_rsc、rpmhpd、bcm-voter、cmd-db，但**没有** NoC 节点（clk_virt、config_noc、gem_noc 等），本项目 DTS 也没有。

## 假设（待验证）
H1：包装器 1 的 SE 不执行命令，是因为没有 qup-core / qup-config 互连投票（引导加载器只为包装器 0 留了状态，m3 里的 I2C 因此能用）。检验：在 DTS 加 NoC 节点（地址取自厂商 DT）与 SE 的 interconnects，观察 SE_GENI_STATUS 与传输是否完成；对照实验：先在 uart7（同包装器 SE2）验证。
H2：IC 本身需要供电/复位时序后才应答，SE 能执行后再处理。

## 下一步
从 Android 取各 NoC 的 reg/compatible（/proc/device-tree），写入 gen-m3-dts.py，先只验证 SPI 事务能完成（环回或读 IC 寄存器），再写驱动。

## 结论（2026-11-10，取代上面的假设与“下一步”；证据在 EXPERIMENT-006 E007–E009）
- H1 不成立或不完整（本机验证）：SE 的 FIFO 接口在硬件上被禁用（SE_GENI FIFO_IF_DISABLE_RO=1），该 SE 只能走 GPI DMA（gpi_dma1 @a00000）；SPI 核心为 GPI 模式映射缓冲时用 `dev->parent`（QUP 包装器节点），包装器需要 `iommus <&apps_smmu 0x403 0x0>` 与 `dma-coherent`，否则总线挂死。interconnect 节点是否必需**未消融**。
- 控制器 FT8720（TDDI）：SPI mode 0，9.6 MHz；复位 TLMM12（低有效），IRQ TLMM13 下降沿；冷启动是 ROM 态（所有读回 0xEF），每次复位后必须由主机下载固件（PRAM 0x000000 + DRAM 0xd00000，长度在固件头 0x100/0x108 以“字数+按位取反”对形式给出，字节数 = 字数×2）。帧格式、命令序列、CRC16-Kermit、报告包解析见 sources/linux-7.3/drivers/input/touchscreen/focaltech-ft8720-spi.c 顶部注释与 tools/fts-probe.c。
- 主线驱动已完成并上机验证（m6，2026-11-10）：probe 0.35 s 内完成，/dev/input/event0，手指实测 4 指，x 0–1069、y 0–2459。未验证：与画面的方向对应（tools/touch-paint.c 待上机）、挂起/唤醒（芯片是否掉固件）、供电（DT 无 supply，沿用 ABL 状态）。
- 工具：tools/fts-probe.c（用户态复刻，调试用）、tools/touch-events.py（主机解码）、tools/touch-paint.c（屏上画点 + 四角方块，m7 initramfs 内置为 /bin/touch-paint）。
