# 技术债

当前无实现层临时补丁。未完成事项见 STATUS.md，不计为技术债。

## 内核补丁（E004）
- sources/linux-7.3 是带本地改动的 git 工作树（基线提交 "Linux 7.3 baseline"，补丁清单见 sources/patch-apply.log）：36 个 ROCKNIX 补丁 + 0022 手工（patch -F3）应用 + sky-linux 0001。去掉条件：上游合入对应驱动或改为在固定提交上维护补丁队列。
- 0022（PBS 类型）：7.3 里 qcom-rpmh-regulator.c 在约第 603 行另有一处 enable 地址写入，未处理 PBS，仅影响 pbs_sd/pbs_px2（SD 卡轨），本里程碑不使用。启用 SD 卡前必须审。
- pinctrl-msm：sky-linux 0001 让 TLMM 不暴露 get_direction，并把寄存器访问改成 nofault，是绕过 TZ 保护 GPIO 的临时做法；正解是 gpio-reserved-ranges，需要受保护引脚清单。
- 启动参数 clk_ignore_unused pd_ignore_unused：为保持 ABL 的屏幕扫描，待面板驱动接管后移除。
- 未应用的 12 个 ROCKNIX 补丁（0009 显示、0010/0050 面板、0024 串口、0030 音频、0040–0042 QMP combo、0053/0055/0058 手柄、0060-regulator）：对应功能做到时再 rebase。
- shim 为第三方（sky-linux）代码，经审阅后在本地副本构建；仅用于 RAM 启动。
- busybox-static 来自 Alpine，未验证 APKINDEX 签名；仅用于 RAM 内的调试 initramfs。持久化 rootfs 时改用可复现来源。
- USB m2：省略 supply/interconnect/iommus/PHY 调参，依赖 ABL 遗留状态；稳定后补齐。
- 0009 的 UBWC 手工改成 ubwc_2_0_hbb14 等价条目（见 PANEL.md）；上游若合入 sm4450 条目则删除。
- 面板驱动：2 字节命令用短写（厂商长写）；背光最大值 0xfff 为假设；DSC 版本假设 1.1；IC 未确认；PPS/序列顺序按 r66451 模板，与下游顺序未逐项核对。
- m3 DTS 省略 interconnect/RPMh 电源/PHY 调参/面板 pinctrl；arm-smmu.disable_bypass=0 为调试放行。
- 面板三条 GPIO 固定调压器加 regulator-always-on（调试期）；面板驱动稳定后删除。
- DSC 速率缓冲 hack（E006，来源 sky-linux 0003）：dpu_hw_dsc_1_2.c 以 `of_machine_is_compatible("qcom,sm4450")` 把缓冲容量改为 600/num_softslice。去掉条件：缓冲容量进 DPU catalog 字段并上游提交。其余运行 6–9 的 xmit/PHY/initial_lines 覆盖已消融并删除（见 EXPERIMENT-006）。
- 面板驱动调试旋钮 `long_writes`（默认 1）和 DCS 回读日志（sky_dump_status）：稳定后去掉回读。
- 调试工具 tools/mmio-rd.c / mmio-wr.c 经 /dev/mem；读无效偏移会令整机挂死（已发生）；initramfs 里的 /bin/rd、/bin/t.sh（t.sh 的 rebind 会挂死，已知，勿用）。
- 主机侧：/etc/udev/rules.d/99-sky-gadget.rules（MODE=0666 于 1d6b:0104 的 ttyACM），由用户安装；调试结束后建议删除。
- 面板 vddio/extvdd 目前是无 GPIO 的 always-on 固定调压器（真实控制在 PM7250B GPIO 11/12），KTD3136 HWEN 在 PM6450 GPIO6；两者都依赖尚未建立的 SPMI + pmic-gpio 节点。休眠/关屏时无法断电，亮度 0 只是背光关闭。去掉条件：加入 SPMI arbiter、pm7250b/pm6450 节点并恢复真实 GPIO 调压器。
- ktd3136.c 来自 sky-linux（GPL-2.0，已保留来源注释），本机芯片 ID 0x01 走其 LM3697 分支；上游已有 LM3697 驱动（lm3697 / ti,lm3697 的 LED 类驱动）时优先改用。
- 面板驱动未使用的 sky_create_backlight() 与 DCS 回读 sky_dump_status() 待清理。
- ktd3136.c LM3697 初始化表已改为本机 Android 的值（E019，满亮度偏暗修复）；逐项作用未二分，0x13/0x1a/0x1c 的含义未对照芯片手册。
- ktd3136.c LM3697 分支已改正寄存器字节序（0x22 低 3 位 / 0x23 高 8 位）；该分支仍来自 sky-linux 且未用 KTD3136 原生路径验证（本机芯片 ID 0x01）。
- m4 initramfs：Alpine busybox-static/busybox-extras/dropbear/musl 等 apk 仅解包，未验证 APKINDEX 签名；dropbear 仅接受 private/ssh 公钥，RAM 根每次启动重生成 host key；主机 udev 规则仍在。
- E007-DEBUG 标记已删除（挂死根因已解决）。
- 触摸驱动 m6：DT 无 supply/pinctrl（复位/IRQ 脚）；interconnect 节点是否必需未消融；坐标尺寸 1080x2460 来自显示分辨率，未用手指校准；驱动未做挂起/电源管理。
- m7（未上机）：SPMI 仲裁器 DT 值取自 Android 运行时 DT，未验证；vddio/extvdd 即使接到 PMIC GPIO 仍保持 always-on；OCP2131 偏压 IC 未建模；PM6450 无上游 dtsi，节点手写。
- 触摸 binding YAML 未经 dt-schema 校验（本机无 dt-validate）；maintainer 为占位。驱动 W=1 编译无警告。
- 桌面 rootfs（sources/dl-desktop，tools/apk-fetch.py）：APKINDEX 签名用 sources/dl-alpine-keys 中的密钥验证，密钥本身取自 https://alpinelinux.org/keys/（HTTPS 为信任根，哈希 d11f6b21…）；Alpine 包的 post-install 脚本不执行，需要的（busybox applet、fc-cache）在 start-desktop 里补；之前 m4/m5 initramfs 的旧 apk 仍只做了 C/S 校验（可用 apk-fetch.py 重取）。m8 的 reserved-memory 节点来自运行时 DT，splash 区 no-map 是我加的保守项。
- m9 的 soc `dma-ranges` 4 GiB 限制是权宜之计（所有设备 DMA 限低 4 GiB，流式 DMA 走 swiotlb 拷贝）；治本：usb_1 加 `iommus = <&apps_smmu 0x540 0x0>`（Android：IOVA 池 0x90000000+0x60000000）后再放开。m9 initramfs 的 init 计时器为 420 s（失败快速回退），需 ssh `touch /tmp/stay` 延长。
- RAM 桌面（desktop/）：weston 用 pixman（无 GPU 驱动）；chroot 内手工建 passwd/group；seatd 以 root 运行；udev 规则里的组名（tty/audio 等）缺失只警告；rootfs 在 tmpfs，断电即失（无持久化）。
- GPU（m10，2026-11-10 上机）：(1) 内核里留有 E012-DEBUG（a6xx_cp_init 失败时的寄存器转储、adreno_fw_create_bo 回读校验、dev_is_dma_coherent 打印、e012_fw_sum/len 全局量），GPU 稳定后删除。(2) a6xx_catalog.c 的 A613 项 `.revn = 612` 是为让 Mesa 26.1.6 识别（它没有 gpu_id 613）；Mesa 升级后改。(3) m10 起 4 GiB dma-ranges 权宜之计已被 `usb_1 iommus <&apps_smmu 0x540 0x0>` 替代（m9 及之前仍带权宜之计），USB 无 dma-coherent，未与 Android 的一致性设置对齐。(4) GPU OPP 表在 gen-m10-dts.py 里被削成只剩 340 MHz（LOW_OPP_ONLY，调试时加的，尚未放开，未验证高档位电压）。(5) gmu_wrapper 节点名/单位地址不一致（沿用 ROCKNIX，dtc 警告）；speed bin 读出 201（bin 1）。(6) zap 固件 a613_zap.mbn = vendor 的 gen6_3_26_0_zap.mbn；固件放 private/gpu，仅进 initramfs，不提交。
- 触摸/桌面：桌面 rootfs 现含 Mesa GL/Vulkan 工具（out/rootfs-desktop.tar sha256 b39e713b…）；gpu-test.sh 的 EGL/Vulkan 步骤要求先在 chroot 里装 busybox applet（脚本已处理）。
- m7（SPMI）的 PM7250B SID 写成了 2，应为 8（已在 gen-m7-dts.py 修正，m7 未上机、过期）；改用 m11（= m10 + SPMI，STAGE=A|B）。m11 stage B 未做。debugfs gpio 全量读取会挂死整机（见 E013）。
- m12（未上机）：WPSS 驱动内置并 auto_boot（`QCOM_Q6V5_PAS=y`），启动早期即拉起；固件 private/wifi/fw 来自 modem_a 备份，仅进 initramfs，不提交；DT 节点形状取自 ROCKNIX RG55G1（已与运行时 DT 核对数值）；`qcom,sm4450-wpss-pas` 的 pas_id=6/ssctl_id 等来自 ROCKNIX 补丁 0003，未单独验证；`qrtr-lookup`（Alpine apk，签名已验证）仅用于调试。WiFi/BT 驱动尚无，路线见 WIFI-BT.md。
- m13 蓝牙（E015）：(1) 启动时首次上电间歇性无应答，根因未明，靠手工重绑 serdev 恢复（未做自动重绑，避免无依据的重试）；(2) 四路 RPMh LDO 电压固定为厂商配置值（L14B 1.304 V、L21B/L23B 1.8 V、L7E 3.0 V），未做负载/模式调优；L23B always-on 是因为它也供 USB2 PHY（USB 节点本身仍未声明 supply）；(3) BD_ADDR 由 ROCKNIX 0045 从 SoC 序列号生成（前缀 00:03:7F），非厂商 NV 地址；(4) NVM 用主线默认选的 cmnv13.bin，Android 用的是区域版 cmnv13_cn.bin（内容大小相同，是否等价未比对）；(5) out/candidates/m13 当前是带 dyndbg 命令行的调试版（M13_BTDEBUG=1），正式用时去掉；(6) 共享 out/kbuild-m1/.config 会累积各候选的 -e 选项，m13 用 -d 去掉了 m12 的 PAS/QRTR。
- 桌面蓝牙（E015 补充）：start-desktop 里在 hci0 未完成 setup 时重绑 hci_uart_qca（启动首次上电间歇失败的权宜之计，根因未明）；dbus/bluetoothd/blueman 以 root 运行，无 polkit；blueman 的 PulseAudio/NetworkManager 插件失败（无对应组件）；glycin 无沙箱运行；配对数据在 tmpfs；bluetoothd 名称未设置；apk-fetch 不处理 install_if（glycin 加载器、可能还有别的）需手动列出。
- WiFi（E016，m14）：(1) out-of-tree 第三方模块（sky-qcacld，GPL/ISC 头，无顶层许可文件，仅私用）：vermagic 必须与内核逐字一致，每次内核改动都要重建；含 sky-dbg 调试打印和 PANIC_ON_BUG；wlan.ko 约 11 MiB。(2) out/kbuild-m1/Module.symvers 是指向 vmlinux.symvers 的手工软链；sources/sky-qcacld/src/fw-api 与 micode-sky-icnss2 是为适配作者目录布局加的软链（tools/build-wifi-modules.sh 会补）。(3) m14 为 icnss2 打开 CONFIG_IIO；qcom,icnss 节点是手写（取自 dtbo overlay 27 + sky-linux），MSA 3 MiB、cx-mx=L11B 未与 Android 运行时逐项比对。(4) WiFi 载荷（模块、固件、iw/wpa_supplicant）每次启动由 ssh 推入 tmpfs；凭据在 private/wifi/credentials.txt；未做自动联网/重连/休眠/SSR。(5) WPSS 固件内置在 initramfs 并 auto_boot；wlan0 MAC 是驱动默认值。(6) gpio-reserved-ranges 已声明但 debugfs/gpio 全量读取未复测，sky-linux 的 TLMM nofault 补丁仍在内核里。
- 蓝牙开机首次上电（E017，m14）：**根因已修**——sources/linux-7.3/drivers/power/sequencing/pwrseq-qcom-wcn.c 加 `pwoff_min_ms`（仅 wcn3950-pmu，1000 ms）并在首次上电前做一次真正的 enable→disable+等待；这是本地内核补丁（可上游：通用「最小断电时间」pdata 字段，需 SM4450 证据与测试），原文件未入 git 跟踪外备份。E015 条目里的「重绑权宜之计」只对 m13 及更早内核仍需要：desktop/start-desktop 保留它，desktop/start-kde 已删。tools/build-m14.sh 的 E017_USB_DELAY / E017_REBIND_SCAN 为实验开关，默认关，稳定后删除。L23B always-on 仍未参与断电（与 USB2 PHY 共轨）。
- KDE RAM 桌面（E018）：以 root 运行 Plasma（无普通用户、无 logind/elogind、无 polkit）；seatd -g root；session bus 用 dbus-run-session；rootfs 为 Alpine v3.24 包只解包不执行安装脚本（schema/mime/字体缓存在 start-kde 里补）；面板屏幕与壁纸靠 desktop/plasma-fix.js 在启动后用脚本修正（首次布局把面板放到 screen=-1）；无壁纸文件（用纯色）；icontasks 小部件在 Alpine 包里缺 QML，任务栏无窗口列表；未调用 kscreen-doctor（缩放由 KWin 自动约 2.65x）；NetworkManager 配置由 push-kde.sh 在手机 RAM 里用 private/wifi/credentials.txt 生成；USB NCM 推送约 6 分钟（2 GiB）；整套在 tmpfs，断电即失；sources/dl-kde、dl-kde-extra 不入库。

- Debian 演练根（E021，tools/push-debian.sh、desktop-debian/）：user 账户无密码且 sudo NOPASSWD、GDM 自动登录、ssh 只收密钥；WiFi 模块由 sky-wifi.service 用 insmod 加载（第三方 out-of-tree，须与内核 vermagic 一致，内核配置变动后要重建）。去掉条件：正式安装时由用户决定账户/登录策略，WiFi 驱动上游化或打成 DKMS/内核包。
- initramfs-m14/init 的 /run/switch-root 钩子是演练用；持久根的挂载逻辑会取代它。

## 上游化清单（2026-11-11，用户同意记录；无发布授权，任何发送/发布前须用户明确授权并由用户本人做 DCO Signed-off-by）
通用前置：提交者必须是用户本人（DCO），按内核对 AI 辅助的要求加 `Assisted-by:`；不伪造署名；先在内核树和邮件列表里查重；每个补丁跑 checkpatch.pl 和 dt_binding_check；去掉调试输出。
| 项 | 内容 | 阻塞/条件 | 优先级 |
|---|---|---|---|
| 板级 DTS `sm4450-xiaomi-sky` | 从拼接生成的 DTS 拆成按功能的小补丁（串口、USB、UFS、触摸、背光、GPU） | 机器要先达到可用状态；拆分和清理 | 高 |
| SM4450 SoC 补充 | `sm4450.dtsi` 缺的 UFS PHY/主机、IPCC、SMP2P、remoteproc、SPMI、GPI DMA；数值来自本机运行时 DT，已有 UFS 硬件验证 | 补丁拆分；与现有上游 UFS PHY 驱动对齐 | 高 |
| FT8720 SPI 触摸驱动 + binding | `focaltech-ft8720-spi.c`、`focaltech,ft8720-spi.yaml`（维护者占位待用户定） | 固件为厂商版权文件，不能随补丁；先查芯片是否可不上传固件；先查是否已有上游驱动 | 中 |
| 背光寄存器修复 | `ktd3136.c` 改为 Android 的 LM3697 寄存器值（0x13/0x17/0x18/0x1a/0x1c/0x24） | 该驱动导入自 sky-linux（orange200213，GPL-2.0），须保留作者；需先联系原作者或重写；上游已有 ktd2801/ktd253 | 中 |
| WiFi（qcacld/icnss2） | 厂商第三方代码 | 不会以现形式上游；WCN6750 的正路是 ath11k，另立项 | 不做 |
| ROCKNIX 补丁（WPSS 等） | 他人成果 | 应由原作者上游，我们保留来源与作者 | 不做 |
| 仓库本身（Debian/KDE rootfs 脚本、initramfs、push/cycle 工具） | 适合作独立项目仓库，不适合内核 | 需用户决定发布、账号、许可证 | 低 |
| 不上游 | 厂商固件、私有备份、校准数据 | — | — |

## 2026-11-11 新增债务
| 项 | 位置 | 原因 | 去掉条件 |
|---|---|---|---|
| qcom_battmgr `xm_set` 调试属性 | sources/linux-7.3/drivers/power/supply/qcom_battmgr.c | 小米充电固件私有 input_suspend（opcode 0x51 prop 3），80% 上限的执行机制 | 改成标准 charge_control_* 的内核实现（带滞回），或上游认可的 vendor 扩展 |
| pdc-ranges 覆盖 | tools/gen-m16-dts.py | 上游 sm4450.dtsi 的 `<94 494 31>` 与本机运行时值（<94 609 31>、多一段 <126 716 12>）不符；音量上等 PDC 路由的引脚收不到中断 | 上游 dtsi 修正后删除；是上游补丁候选 |
| USB PHY 供电 + L25B 常开 | tools/gen-m16-dts.py | ADSP 启动后撤掉 ABL 的投票，PHY 供电必须在 DT 声明 | 上游板级 DTS 里正式建模（regulator 命名与负载） |
| USB gadget 睡眠恢复靠脚本重绑 dwc3 | initramfs-m14/sleeptest | dwc3-qcom 带连接 gadget 做 suspend 后恢复失败（ep0out） | 找到 dwc3 恢复缺陷根因（otg+role-switch 在本 SoC 上的 PHY/L2 状态） |
| 初始化脚本里的屏上观察器 | initramfs-m14/init（E022 observer） | 在 USB 不可用时看日志 | USB 稳定后删除 |
| battmgr "unknown notification 0x50" | 日志 | 小米 xm 属性通知，主线不认 | 实现 xm 属性解析或忽略该通知 |
| 去掉 DT 里的 `qcom,*-channel-mapping` | tools/gen-m17-dts.py | 非上游属性，把 HPHL 的 SoundWire 通道掩码改错（听筒/耳机只有爆音） | 永久不加；若以后需要通道映射，先上游 binding |
| tx-port-mapping <1 1 2 3> + SWR_INPUT0←ADC2 | tools/gen-m17-dts.py | master 端口 2（lane 2）只出 0；原因未查（lane-control 0x02 / 硬件 lane 未接？） | 查清 TX lane 后恢复 <1 2 3 4>（同时用 ADC1+ADC2） |
| LPASS_HW_MACRO_VOTE 固定时钟桩 | tools/gen-m17-dts.py（lpass_macro_vote_stub） | ADSP 对 LPASS core hw 请求返回 EFAILED（运行时 DT 里该 vote 被禁用） | 找到正确的 clock/vote 方式或去掉依赖 |
| （已退役 2026-11-13）SoundWire debugfs / /dev/mem 写寄存器的实验工具 | 存档 private/audio/retired-userspace-amp/tools/（swrpoke.sh、tone-detect.py） | 无仪器时的运行时实验 | 已不需要 |
| PMIC RTC 不保存时间 | 内核 rtc-pm8xxx（读回 1970） | 断网冷启动时间错 | 查 RTC 是否可写/是否被小米固件占用，或始终靠 NTP |
| apt 源手工配置、stage1 构建缺 e2fsprogs/libss2/logsave | Debian rootfs | 构建器遗漏 | 修 build-debian-stage1.py 并重建镜像 |
| m17j 候选含无用的第二 DAI link | tools/gen-m17-dts.py（M17_RX1=1） | q6apm 没有 RX_CODEC_DMA_RX_1 mixer，实验失败 | 删除候选 m17j 与该开关 |

| rx macro stride2 补丁仅在本地 | kernel-local/linux-7.3-local.diff | m18 验证通过（扬声器出声）；尚未向上游提交 | 向上游提交 lpass-rx-macro 补丁，合入后删除本地 hunk |

| USB gadget 线缆拔插后不恢复 | 内核 dwc3-qcom / gadget | 出现 “HS-PHY not in L2 / failed to enable ep0out” 后 UDC 一直 not attached（用户重新插线也不恢复）；本机验证：解绑再绑定 dwc3-qcom 驱动（tools/usb-rebind.sh）即恢复 | 找到根因（dwc3 在断线后的 PHY 状态）并修复，或加 udev 规则自动重绑；开发时用 WiFi ssh 兜底 |
| 传感器（加速度计/磁力计/光感）不可用 | — | 在 ADSP/TZ 持有的总线上（GPIO0-3、18-21 为 TZ 保留），AP 直连会导致系统失联（E029 m17l） | 研究经 ADSP SNS/QSH 读取（FastRPC/QMI），或接受没有自动旋转 |
- recovery_b 被占用（E028；现为 m21 的 v2 镜像）：放着 header v2 镜像（含 vendor_boot DTB 与 dtbo，ROM 20240922），`reboot recovery` 进 Debian 而不是 PixelOS recovery。去掉条件：改用 boot_a 路线，或不再需要手机独立启动；回退 `fastboot flash recovery_b private/rom/extracted/recovery.img`。镜像带厂商文件，不能发布。
- 原生显示依赖 abl 先点亮 DSI：冷启动 msm_dsi 时 `DSI PLL lock failed`，DPU 等 vblank 超时把 CPU 拖死（E028 运行 5）。目前靠 abl 保留 splash 绕开；若 abl 关屏（如 recovery 路径缺 dtbo），Linux 会卡死。去掉条件：修好 DSI PLL 冷启动，或 DPU 在 DSI 未就绪时不阻塞。
- 残留：tools/gen-m17-dts.py 的 M17_NODISPLAY 实验开关与 out/candidates/m19nd、m19r（运行 5/6 的失败变体）可删。
- DisplayLink（E031）：专有 DisplayLinkManager 只在 private/，rootfs 一旦包含就不能公开发布；evdi.ko 必须与启动镜像内核 vermagic 一致，内核重建后要重跑 tools/build-evdi.sh；软件光标开关 `MUTTER_DEBUG_DISABLE_HW_CURSORS=1`（/etc/environment.d/90-sky-sw-cursor.conf）绕开 evdi 硬件光标平面 ~95% 透明的问题，代价是指针移动要整帧更新（USB2 上更吃力）。去掉条件：查明 evdi/Mutter 光标平面问题并修掉，或 evdi 上游修复；发布版改为让用户自己下载厂商安装包。
- 深度休眠在接了 DisplayLink 坞（xhci 主机、evdi）时没有唤醒（E031 运行 3，2026-11-12 20:42）：日志在 `PM: suspend entry (deep)` 后中断，需长按电源键强制关机；E022–E024（m16，无 USB 主机栈和坞）深度休眠可唤醒。怀疑 xhci/dwc3 主机角色、evdi/DisplayLinkManager 或 USB 坞挂在休眠路径上，尚未复现隔离。触发是用户在黑屏时按电源键（power-button-action=suspend）。**根因线索（2026-11-12 21:53 复现，EXPERIMENT-009 运行 8）**：恢复时 `xhci-hcd: xHC error in resume, USBSTS 0x411, Reinit` → xhci_plat_resume_common 超时 -110，卡住约 31 s（整机黑屏、ssh 不通）后才 PM: suspend exit，坞全部断开；第一次“不唤醒”很可能就是这 30 s 被强制关机打断。恢复办法（已验证）：解绑再绑定 dwc3-qcom + `echo host > usb_role/.../role`。临时措施：GNOME 空闲休眠和电源键休眠都关闭（desktop-debian/90_sky-power.gschema.override，power-button-action='nothing'）。去掉条件：无坞/有坞各做一次 s2idle 与 deep 唤醒对照（带 pm_debug_messages），找到卡住的设备并修好，再恢复休眠。
  - **2026-11-12 更新（m22，本机验证）**：xHCI 恢复卡顿已由 dwc3-qcom 的 resume 补丁（重设 UTMI 时钟选择，kernel-local/dwc3-qcom-utmi-resume.diff）修复，坞在休眠后自动恢复（EXPERIMENT-009 运行 9）。补丁尚在 m22 RAM 候选，未写入 recovery_b。**更正（2026-11-13）**：此前“40–50 ms 就被唤醒、没有省电”是误读——内核时间戳在休眠期间不走；按 WLAN 墙钟戳，实际睡了约 2 s/0.1 s/36 s/32 s（EXPERIMENT-009 更正节）。**遗留**：带坞时有几次只睡 0.1–2 s 就自己醒（唤醒源未查明，候选：坞上键鼠/集线器远程唤醒、BT 唤醒线、WLAN）；排查需要 PM_DEBUG（m23，已备脚本）。
- 内核日志被 SPMI 报错刷屏（E031，2026-11-12）：`spmi spmi-0: disallowed SPMI write to sid=0, addr=0x6146` 约 70–110 条/秒（启动后约 60 s 起持续，爆发时约 1400/秒），占本次启动日志 92%（12 分钟 5.4 万行）；journal 已 573 MB（写 UFS）、dmesg 环形缓冲被淹没。地址 0x6146 = pm8xxx RTC 的 alarm 控制寄存器（rtc-pm8xxx，c400000.spmi:pmic@0:rtc@6100）；RTC 闹钟中断计数为 0，没有用户态进程打开 /dev/rtc0，内核无 tracefs/kprobe，所以触发者未查明。成本：journald 约占一个核 4–13%，调低控制台日志级别（7→1）无可测的电流或 CPU 差别（噪声 ±10 mA）。E024（m16）里 RTC 闹钟唤醒是好的，之后某个版本起 sid 0 的这次写被仲裁器拒绝（怀疑权限/所有者变化，如 ADSP 起来后），未验证。去掉条件：查出谁在写并修掉（或确认 RTC 闹钟归别的 EE 并在 DT 里关掉相关用途），在 spmi-pmic-arb 里把 dev_err 改为限速；设置 journald SystemMaxUse 作为兜底。
