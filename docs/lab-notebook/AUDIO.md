# 音频（E027）

状态：**声卡可用；听筒出声（用户确认）；底部麦克风能采集；底部扬声器（WCD AUX → FS1599）用运行时补丁出声，用户确认“隔着房间都能听到”（2026-11-12）；根因是上游 lpass-rx-macro 的 stride2 bug，内核补丁已验证（m18：无 poke，传感器 −41.8 dBFS）**。**不要在 DT 里写 `qcom,rx/tx-channel-mapping`**（非上游属性，会把 HPHL 的 SoundWire 通道掩码改错，听筒/耳机无声）。结论等级：用户陈述 / 源码证据 / 本机验证 分别标注。

## 硬件事实（来源：本机运行时 DT private/runtime-20261109T142413Z/runtime.dts + Android vendor 音频配置 private/audio/android/，本机证据）
- 平台音频栈是 "ravelin"（SM4450），DT 声卡 `qcom,waipio-asoc-snd`、型号 `ravelin-qrd-snd-card`；寄存器布局和中断与 SM8450 相同：RX 宏 0x3200000、TX 宏 0x3220000、WSA 宏 0x3240000（未用）、VA 宏 0x33f0000、SoundWire 主控 rx 0x3210000（SPI 155）、va/tx 0x33b0000（SPI 496/520）、LPI TLMM 0x3440000（23 脚，slew 寄存器 0x34da000）。所以直接以上游 sm8450.dtsi 为模板。
- 通信走 ADSP（已在 m16 起来）：glink 通道 `adsp_apps` 上的 GPR（domain 2，intents 512×20），服务 spf_core(3)、audio-pkt(0x17)、q6prm(7)。上游 q6apm/q6prm 与此协议一致（AudioReach）。内核 PD mapper 已含 sm4450 域表（adsp_audio_pd），不需要用户态 pd-mapper。
- 编解码器 **WCD9370（wcd937x）**，经 SoundWire：rx 从机 unique id 4（0x1170224）、tx 从机 unique id 3（0x1170223），part 0x010a；复位 TLMM gpio96；供电 buck=pm6450 L20B（1.7–1.9 V）、rxtx/px=L21B（1.8 V）、麦偏置来自 3.7 V（VPH）。WCD938x 节点在运行时 DT 里是 disabled。
- **没有 WSA 扬声器功放**（`qcom,wsa-max-devs = 0`，wsa 宏 disabled）。扬声器路径（mixer_paths_ravelin_qrd.xml `speaker`）：`RX_MACRO RX2 MUX = AIF2_PB`、`RX INT2_1 MIX1 INP0 = RX2`、`AUX_RDAC Switch = 1` → WCD937x 的 AUX_OUT 模拟输出 → 外部模拟功放 **FourSemi FS1599（AP I2C 0，0x34）**（aw87xxx@0x58 从未应答，这块板没有用）；听筒（handset）= `EAR_RDAC`，耳机 = HPHL/HPHR。Android 的扬声器后端是 CODEC_DMA-LPAIF_RXTX-RX-1（RX_CODEC_DMA_RX_1，单声道，无 I2S）。
- DMIC 脚：dmic01 等在 LPI（与 sm8450 同款）；声卡的 SWR 脚：tx clk gpio0、数据 gpio1/2/14，rx clk gpio3、数据 gpio4/5（与 sm8450.dtsi 一致）。
- 耳机插座检测走 WCD937x MBHC（`qcom,msm-mbhc-*`），USB-C 数字音频未支持；fsa4480（SE8 I2C）是 Type-C 音频切换，暂不处理。

## 方案（源码证据）
- DT：tools/gen-m17-dts.py = m16 + ADSP `gpr`(q6apm/q6prm) + sm8450 的 rx/tx/va 宏、swr1(rx)/swr2(tx)、lpass_tlmm（逐字从 sm8450.dtsi 提取）+ wcd9370 编解码器 + `qcom,sm8450-sndcard` 声卡（链路：RX_CODEC_DMA_RX_0 ↔ wcd9370 0/swr1/rxmacro、TX_CODEC_DMA_TX_3 ↔ wcd9370 1/swr2/txmacro、VA_CODEC_DMA_TX_0 ↔ vamacro）。q6apm DAI 的 SMMU SID 取运行时 DT 的 0x1001（掩码 0）。
- 拓扑固件：上游 sc8280xp 机器驱动要加载 `qcom/sm8450/<model>-tplg.bin`；用 sources/audioreach-topology（linux-msm/audioreach-topology，BSD-3-Clause，提交 d6bb205a）的 SM8450-HDK.m4 经 m4 + alsatplg（Fedora alsa-topology-utils，解包到 out/alsatplg）生成 private/audio/tplg/qcom/sm8450/Redmi-12-5G-tplg.bin（sha256 506b435f…）。该拓扑含 WSA/MI2S/WCD/VA 后端，我们只用 RX_CODEC_DMA_RX_0、TX_CODEC_DMA_TX_3、VA_CODEC_DMA_TX_0。alsatplg 对 "undefined sink widget" 的告警是正常的（内核侧解析）。
- 内核：build-m17.sh 增加 SND/SND_SOC_QCOM/QDSP6/SC8280XP/APM/PRM/WCD937X_SDW/LPASS 宏/SOUNDWIRE_QCOM/LPASS LPI pinctrl(sm8450)/QCOM_APR/AW87390/I2C_CHARDEV 且全部内建（initramfs 没有模块；拓扑放进 initramfs，因为声卡在 initramfs 阶段就 probe）。

## 风险与未知（先写判据，再上机）
- 预期（m17 冷启动后）：dmesg 里 `q6apm` 通过 PDR 等到 audio_pd；`q6prm` 时钟；`lpass-*-macro`、`soundwire` 主控、`wcd937x`（复位 gpio96 后读到 SDW 从机 enumerate）；`aplay -l` 出现 "Redmi-12-5G" 声卡。判据：`/proc/asound/cards` 有声卡、`aplay -l` 有 MultiMedia 前端；失败时按最早失败层查（ADSP audio_pd → GPR → prm 时钟 → LPI pinctrl → SDW 枚举 → wcd937x）。
- 回退：和以前一样，m17 只是 fastboot boot 的 RAM 镜像，不写存储；Android 与 Debian(sda22) 不受影响。WiFi 模块是为 m16 内核编译的，内核配置变化后可能需要重编（`! tools/build-wifi-modules.sh`）。
- 风险：SM4450 的宏编解码版本可能与 sm8450 不同（版本从硬件寄存器读，不在 DT）；SWR 端口时序参数（sinterval/offset 等）取自 sm8450，可能与 sky 的下游值不同（下游 rx 6 端口、va 3 端口）；ADSP 固件里 AudioReach 模块是否齐全；喇叭功放（aw87xxx）上游驱动 aw87390 不一定匹配这颗芯片（先读 I2C 0x58 的 ID 寄存器确认型号）。
- 未做：扬声器（AUX→aw87xxx）、听筒、耳机检测、麦克风、Debian 用户态（pipewire/wireplumber + UCM）。

## 复现
`python3 -I tools/gen-m17-dts.py`（只写 dts/）；构建由用户运行 `! tools/build-m17.sh`（需要先有 private/audio/tplg/…-tplg.bin 与 out/alsatplg）；上机 `tools/cycle-boot-m17.sh`（需遵守 AGENTS.md：先读电量，记录输入哈希）。

## 扬声器（E027 续，2026-11-11 夜）
**FS1599 开关序列（源码证据：vendor fs15xx_dlkm.ko 反汇编；本机验证：probe 读回、写入后读回与预设一致）**——寄存器 8 位、值 16 位大端，I2C0@0x34；实现见内核驱动 kernel-local/fs1599/fs1599.c（E034，m24 起；用户态原型 fs1599.py 已存档到 private/audio/retired-userspace-amp/tools/）。
- reset/就绪：reg0x10←2，15 ms，reg0x10←1，读 reg0x0e 必须 0x0003 或 0x0300（vendor 最多重试 5 次）。
- 载入预设：reg0x1f←0x0091；公共表（类型 2，10 项）；场景表（类型 3，每项带掩码，掩码 = 1<<场景号，Android speaker 路径设 FSM_Scene=6 → 0x40）；reg0x1f←0。表项 {hdr,val}：hdr=0xF0rr 为整寄存器写，否则位域读改写（长度=(hdr>>12)+1，位置=(hdr>>8)&0xf，寄存器=hdr&0xff）。
- start_up：0x1f←0xca91，0xc0←0x10，0x10←0，0x11←0xc0，10 ms，0xc0←0，0x1f←0。shut_down：0x11←0，20 ms，0x10←1。vendor 探测时先 reg_init 再 shut_down，所以空闲时 amp 是掉电态（0x10=1，0x11=0）。set_mute(非 0) = 清 reg0x3f bit15 并把当前场景记为 0；set_mute(0) 什么也不做。
- 预设文件 private/audio/android/fw/fs1599.fsm（sha256 9c2ae240…，来自 Android vendor，不提交）。

**路由坑（本机验证）**
1. 上游 rx 宏的 `RX INT2_1 INTERP` 是 mux，必须设为 `RX INT2_1 MIX1`（Android 的 mixer_paths 没有这一项，下游驱动自动处理）；`RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1` 在每次开机后默认关，不开则 aplay 报 `audio open error: Invalid argument`。
2. **RX_CODEC_DMA_RX_0 端口一次推 RX0 和 RX1 两条车道，两条都必须被消费**：只把 RX1 接到 INT2 而 RX0 悬空时，DSP 的 codec DMA 在约 0.5 s 后停转（hw_ptr 停在 0，aplay 报 `pcm_write: Input/output error`，内核日志里什么都没有）。解法：`RX INT2_1 MIX1 INP0=RX0`、`INP1=RX1`（把立体声和成单声道送 AUX），hw_ptr 立刻走动。Android 用的是 RX_CODEC_DMA_RX_1（RX2 车道，单声道）+ AIF2_PB；我们的 DT 暂时没有第二条 DAI 链路，所以复用 RX_0。
3. 扬声器 mixer（当前能走流的组合）：`RX_MACRO RX0 MUX=AIF1_PB`、`RX_MACRO RX1 MUX=AIF1_PB`、`RX INT2_1 MIX1 INP0=RX0`、`INP1=RX1`、`RX INT2_1 INTERP=RX INT2_1 MIX1`、`AUX_RDAC Switch=1`、`LO Switch=1`、`CLSH PA Switch=1`（后两个是否必要未单独核对）、`RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1=on`，再 `python3 tools/fs1599.py --fsm …/fs1599.fsm on --scene 6`。
4. 调试办法：播放用 `aplay -B 8000000` 加大缓冲，这样停转要 3 s 以上才报错，期间可读 `/proc/asound/card0/pcm0p/sub0/status` 的 hw_ptr、`/sys/kernel/debug/asoc/Redmi-12-5G/*/dapm/*` 的 DAPM 通路状态（"in/out" 计数、On/Off）。

**未验证**：听感（用户陈述待收）；音量/失真/破音；FS1599 的保护与故障寄存器（reg 0x00/0x03/0x04 的含义）；在 DT 里补第二条 RX_CODEC_DMA_RX_1 + AIF2_PB 链路（拓扑也要有对应后端）；Debian 用户态（UCM + pipewire）里的开关时序（amp on/off 应挂在 UCM/脚本上，或者做成内核 codec 驱动，见 TECH_DEBT）。

## 听筒（E027 run 3，用户确认出声）
mixer（本机验证）：`RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1=1`、`RX_MACRO RX0/RX1 MUX=AIF1_PB`、`RX INT0_1 MIX1 INP0=RX0`、`INP1=RX1`、`RX INT0_1 INTERP=RX INT0_1 MIX1`、`RX INT0 DEM MUX=CLSH_DSM_OUT`、`RDAC3_MUX=RX1`、`EAR_RDAC Switch=1`、`RX_EAR Mode Switch=1`、`HPHL Switch=1`、`CLSH PA Switch=1`。注意 RX_CODEC_DMA_RX_0 的 RX0/RX1 两条车道都要有人消费。
## 排错工具（本机）
`/root/sdwprobe.sh`（播放中读 master/slave SoundWire 使能）、debugfs `soundwire/master-N-0/{qualcomm-sdw/qualcomm-registers, sdw:*/registers}` 和 `regmap/sdw:3:…-wcd937x_csr/registers`（播放中读安全；**整目录乱读 regmap 会让手机消失**）。

## 麦克风采集（E027 run 4–6，本机验证）
- DT（m17h）：`qcom,tx-port-mapping = <1 1 2 3>`（同上游 qcm6490-idp 的 WCD9370 板），audio-routing `"TX SWR_INPUT0", "ADC2_OUTPUT"`（不再路由 ADC1）。<1 2 3 4> + SWR_INPUT4 也试过：master 端口 2（lane 2）只出 0，端口 1（lane 1）才有真数据。
- mixer：`tools/mic-on.sh`（原厂 amic3 食谱改成 upstream 命名）。**CODEC DMA 为 2 声道、消费 TX 宏的 DEC0 与 DEC1 两条车道**，所以两个 DEC 都要开（都选 SWR_MIC0）；只开一个或开 DEC1+DEC2 会 `avail` 恒 0、arecord 在缓冲时间后报 EIO。**录音必须用大缓冲**：`arecord -D hw:0,2 -c 2 -r 48000 -f S16_LE -B 8000000 -F 1000000`（默认缓冲约 0.6 s 就超时）。ADC1/ADC3 Switch 关。
- 灵敏度很低（听筒 −30 dBFS 1 kHz 在底部麦克风只有 −88 dBFS，静音 −131 dBFS），但检测器（Goertzel 1 kHz）重复性好，足以做有/无判决。
- 未做：增益调校、AMIC1/AMIC2（耳机麦）、数字麦克风（VA 路径录到全 0，原因未查）、Debian 用户态。

## 声学环回与运行时寄存器工具（device 侧，tools/）
`loop.sh <ear|spk|ear3|none> [wav]`：路由 → 同时录底部麦克风并播 1 kHz → 输出 1 kHz 电平（ch0）。基线：静音 ≈ −131…−139 dBFS，听筒（−30 dBFS 播放）≈ −88 dBFS；扬声器 ≈ −123 dBFS（等于没有）。`poke-test.sh`、`swrpoke.sh`/`swrpeek.sh`/`swrdump.sh`（SoundWire debugfs 的 command/go 接口，数据来自 /lib/firmware 里的文件；会污染内核，仅实验）、`mmio.py`（/dev/mem；只在块有时钟时用）。regmap debugfs 显示的是缓存，不是芯片；真读用 swrpeek。

## 扬声器：已排除与未决（E027 run 6–7）
已排除：路由停转、SoundWire 通道掩码、master/slave 端口 4 参数（si=8/offset1=1/EN 两端一致）、端口字长（master 端口 4 的 BLOCK_CTRL_1 固定为 0，1 bit PDM）、AUXPA bit4、DIG/ANA 时钟位、macro INT2 通路寄存器（与 INT0 对称）、AUX PDM 看门狗（每次起播一次）。**判别实验**：AUX 数字路径喂给听筒（`route.sh ear3`）无声，而 INT0/HPHL 路径喂听筒有声 → 数据没经 LO 端口/RX3 到达 DAC，问题在 FS1599 之前。未决与下一步见 EXPERIMENT-006“E027 阶段结论”。vendor 对照（反汇编 vendor_dlkm 的 wcd937x，位于 private/audio/android/ko/，只读）：RX3 PRE_PMU 连 SDW 端口 14（LO）；aux_dac_event 设 ANA_CLK bit2、DIG_CLK bit2、AUX_GAIN bit0、classH AUX；aux_pa 里 `swr_slvdev_datapath_control` 后调用 `fsm_speaker_onn`。RX 端口参数不在 DT 里（只有 TX 的 `qcom,swr-tx-port-params`），在 vendor swr_ctrl_dlkm.ko 里（`swrm_copy_data_port_config`），尚未解读。

## 扬声器出声（E027 run 9，2026-11-12，用户确认）
- **根因**：Linux 7.3 `lpass-rx-macro.c`：codec version ≥2.5 时 `rxn_reg_stride2=0`，INT2(AUX) 的 `DSM_CTL`/`SEC7` 落在 0x5c0/0x5b4（应为 0x5cc/0x5c0）。DSM 时钟没开 → 数据没进 SWR；INT0/INT1 不受影响（听筒/耳机正常）。补丁：`rxn_reg_stride2 = 0xc`（`kernel-local/linux-7.3-local.diff`，m18 待构建）。
- **发现方法**：在 root 过的 Android 里扬声器播放时读 debugfs（`/sys/kernel/debug` 要先 `mount -t debugfs`）：`regmap/wcd937x-slave.*/registers`、`regmap/soc:spf_core_platform:lpass-cdc/registers`（RX macro 基址 0x1000）、`rx_swr_ctrl/swrm_reg_dump`（SWR master，全部一致，排除）；与 Linux 同状态对比（`private/audio/android-base/`，私有）。
- **补丁前的运行时配方**（RAM 内核 m17h/i/j）：`mmio.py 0x32005cc 1`（在 `route.sh spk` 之前，打开 RX2 DSM 时钟）→ `route.sh spk` + 播放 → 播放中 `mmio.py 0x32005c0 2; mmio.py 0x32005b4 0`。传感器 1 kHz：−133…−143 dBFS → −36 dBFS（听筒 −88）。只开时钟不修 0x5c0/0x5b4 → 4.6 kHz 宽带噪声。
- 已验证无关：master/slave 端口参数、CLSH、AUXPA bit4、PDM_WD、字长、第二条 DAI link（q6apm 里没有 RX_CODEC_DMA_RX_1 的 mixer，m17j 无用）。
- m18（内核补丁）已验证：`KERNEL=m18 tools/boot-linux.sh`，`route.sh spk` 不需要任何 poke。未做：音量/FS1599 保护；Debian 用户态（UCM/pipewire）；耳机；上游补丁（lpass-rx-macro stride2）。

## Debian 用户态音频（E027 run 11，2026-11-12，用户确认听到）
- 安装：新 rootfs 由 tools/push-debian.sh 把 audio/ucm2 送进 chroot、desktop-debian/customize.sh 装到 `/usr/share/alsa/ucm2/Xiaomi/sky/{sky,HiFi}.conf` + 符号链接 `conf.d/sm8450/Redmi-12-5G.conf`（需 `alsa-ucm-conf`）；在线手机：`scp` 这两个文件并建同样的链接后重启 wireplumber。功放由内核处理（E034），不装任何用户态助手。（2026-11-13 前的 tools/install-audio.sh、audio-stage.sh、install-target.sh 已删除，存档 private/audio/retired-userspace-amp/）
- UCM 设备：Speaker（INT2→AUX→FS1599；功放由内核 DAPM 在 AUX 通路上电时开、停播后关，UCM 不再 exec 任何东西）、Earpiece（INT0→EAR，与 Speaker 互斥）、Mic（底部麦克风，DEC0+DEC1 两车道）。设计来源：早期调试脚本 route.sh、mic-on.sh（已删除，存档在 private/audio/retired-userspace-amp/tools/）。
- 验证（PipeWire 1.4.2/WirePlumber 0.5.8，GNOME 48）：`wpctl status` 出现 “Built-in Audio Speaker playback”、“Bottom microphone”；`pw-play` 播 1 kHz 经 `pw-record`（底部麦克风）回采 −57.8 dBFS（音量 0.4）；GNOME 系统声音（message/bell/complete）用户确认听到。默认 ALSA 缓冲（不再需要大缓冲）即可播放与采集。
- 已知问题：UCM 设备选中期间 AUX_RDAC/FS1599 一直保持开启（PipeWire 节点 suspended 时 amp 仍通电，0x11=0xc0）→ 待办：功放随流开关（内核侧 amp 驱动 + DAPM，或 wireplumber 钩子）；Earpiece 的端口切换（GNOME 里选“听筒”）与耳机/蓝牙未测；麦克风增益未调；必须用含 stride2 补丁的内核（m18）；耳机孔此机没有（用户无有线耳机），蓝牙音频未测。
