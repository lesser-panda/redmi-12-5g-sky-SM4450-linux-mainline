# 经验与教训（给下一个设备移植用）

来源：Redmi 12 5G（sky，SM4450）2026-11-09 起的主线 Linux 启动工作。每条标注证据等级：**[本机]** 在本机验证过；**[源码]** 读源码得出；**[推断]** 合理推断未直接证明。设备特有的细节在各自文档（PANEL/TOUCH/GPU/EXPERIMENT-006），这里只收**能迁移到别的设备**的东西。不含序列号等私有数据。

## 1. 流程与纪律（最值钱的部分）

1. **先建「回得来」的通道，再做任何实验。** 本项目全程用 `fastboot boot`（零分区写入）+ 镜像内计时器自动回 Android + `panic=15` + 长按电源键。结果：十几次失败/挂死/改错，没有一次需要救砖。计时器要在 initramfs 的 init 里（不依赖将要断开的 USB 通道）；失败要快（420 s），成功后用 `touch /tmp/stay` 延长。[本机]
2. **一次一个变量，且预先写下预期、判据、回退。** 本项目 GPU 调了 17 次，每次只改一件事（interconnect → 微码 → OPP → DMA 限制 → zap 固件 → 设备 id）。把「改了什么」写进生成脚本的注释里，之后才能解释为什么某一行在那里。[本机]
3. **先看错误是不是随机的。** 同一镜像连续两次启动结果不同（一次 `ucode version 0`，一次「非法指令」），这是**内存/缓存一致性问题的特征**，不是固件或寄存器值错。看到「同样的输入，不同的结果」立刻往内存模型上想，别继续调寄存器。[本机]
4. **加回读校验。** 往 DMA/GPU 缓冲写完数据后立刻读回比较（几行内核调试代码），一次就证明了「写进去的数据被改了」，比对着 GPU 状态寄存器猜强得多。把这种自检做成长期调试开关。[本机]
5. **别用权宜之计当基线。** m9 的 4 GiB `dma-ranges` 限制是为了让 USB 在 8 GB 内存下工作而加的「临时」措施，它在后面悄悄破坏了 GPU。临时措施要登记（TECH_DEBT），并且每次出现无法解释的现象时第一个怀疑它们。[本机]
6. **完整读输入，别只看前面一部分。** 找 zap 固件时我只看了 `ls /firmware` 的前 64 行，得出「vendor 里只有 a610_zap」，结果真正的文件（`gen6_3_26_0_zap.mbn`）排在后面。教训：找某类文件时用全文搜索（`7z l | grep -i`），并核对证书/哈希来源，不要凭文件名推断。[本机]
7. **证书比文件名可靠。** 固件是否「对」可以看签名证书：`strings` 里 "Test User / Test Attestation CA" 是通用遗留，"Xiaomi Root CA / General Use for Xiaomi Secureboot" 才是这台机器的量产文件。TZ 拒绝（SCM -EINVAL=-22）通常就是它。[本机]
8. **每步写文档。** 唯一下一步、设备状态、哈希、失败记录都进 STATUS/HANDOFF/LOG；失败记录不删。用户几小时不在场，靠这些文档（而不是对话）才接得上。[本机]
9. **用户不在场时的授权要显式。** 本项目只对明确授权的镜像（m8、m10）无人值守上机；风险高的（SPMI 仲裁器可能挂死整机）留到用户在场或明确说「挂了也没关系」之后。[本机]

## 2. 取证：从运行中的 Android 拿板级真值

- **运行时设备树**是最有价值的证据：`/proc/device-tree` 或 `dtc -I fs`。从中取：内存 banks 与 31 个 no-map 保留区、各控制器寄存器地址与中断、SMMU stream id、GPIO 编号、时钟/电源域、PMIC 拓扑、`qcom,chipid`、speed bin 位置。**不要抄同 SoC 其他设备的板级值**（例：ROCKNIX 的 zap 保留区在 0x8941a000，本机是 0x89c1a000）。[本机]
- `/proc/iomem` 的 System RAM 要和「DT memory banks 减去 no-map 区」逐段对比，本项目用 `tools/memmap.py` 做到完全相等，8 GB 才敢整块放开。[本机]
- **OTA/包里的 vendor 镜像是固件宝库**：`payload-dumper-go -p vendor` + `debugfs -R 'dump /firmware/x ...'`（或 `7z l`）。GPU 的 SQE/zap/gmu、触摸固件、音频配置都在里面。本机没有 root 时也能拿。[本机]
- **dtbo 里有面板真实参数**（运行时 DT 只有占位面板）：时序、DSC、初始化命令序列要从 dtbo 解析。[本机]
- 厂商触摸/面板驱动源码（GPL 仓库、社区 fork）给出协议；用 **逻辑分析**（读已知寄存器验证 CRC、ID）比盲目改驱动快。FT8720：CRC16-Kermit、固件下载序列、ECC 校验都从厂商源码读出后在 SPI 总线上验证。[本机]

## 3. 通用硬件/内核坑（高通平台，部分适用于其他平台）

### 3.1 内存、DMA、SMMU
- 默认只放开一小块内存（本项目 518 MiB）是为了启动安全；全 8 GB 需要「banks + 所有 no-map 保留区」。放开后**所有 DMA 设备都可能拿到 4 GiB 以上地址**。USB（DWC3）在 Android 里走 SMMU stream（本机 0x540），裸物理地址的 DMA 在高地址会失败。**正解是给它 `iommus`**，不是限制 DMA 范围。[本机]
- **swiotlb 反弹会跳过原页的缓存清理**：DMA 设备掩码够不到的页走 swiotlb，`dma_map`/`sync` 针对反弹缓冲做缓存维护，原页的脏缓存行仍在。之后 CPU 通过 **写合并（WC）映射**写进去的数据，会被旧缓存行覆盖。症状：GPU 微码/环缓冲「随机」坏掉；回读比对有 32–96 个 dword 不同（整条缓存行）。[本机，根因为推断，去掉限制后消失]
- QUP 串行引擎有 `FIFO_IF_DISABLE=1` 时只能走 GPI DMA（SPI 触摸），wrapper 需要 `iommus` + `dma-coherent`，否则 DMA 地址不对、总线挂死。[本机]
- 一致性属性（`dma-coherent`）要和 SMMU 实际状态一致：SMMU 在 ABL 的 bypass 状态下，给 USB 加 `dma-coherent` 会让 ep0 不响应；加了 `iommus` 之后用非一致（让内核做缓存维护）也能工作。[本机]

### 3.2 危险操作清单（会挂死整机）
- 通过 `/dev/mem` 读**未确认**的 TLMM 引脚寄存器会挂死；读无效偏移同样。只读已知安全的、先看设备树/厂商驱动确认。[本机]
- 重启 RAM 镜像回 Android：`reboot -f` 比 ACM 控制台可靠；ssh 的 `sync; reboot -f` 会让 ssh 会话挂住（用 `timeout`）。[本机]
- SPMI 仲裁器、GPU 时钟/GDSC、PMIC 写寄存器：第一次碰都单独测、用户在场或明确接受挂死。[本机方针]
- **`cat /sys/kernel/debug/gpio` 会遍历所有 gpiochip（TLMM 受保护脚 + 每个 PMIC GPIO 的多个寄存器），本机上让整机硬挂死**（USB 消失，内核死了，init 计时器也救不了，需长按电源）。要看某个控制器，只读它自己的 `/sys/kernel/debug/pinctrl/<ctrl>/pinconf-pins`，并在读之前让 dmesg 实时落盘。[本机；具体是哪一路挂死未区分]
- **SPMI 的 SID 不是 DT 节点名里的数字**：运行时 DT 里 `qcom,pm7250b@2` 的 `reg = <0x08 0x00>`，真实 SID 是 8。写 DT 时 `pmic@<SID>` 和 `reg = <SID SPMI_USID>` 取 `reg`，不要取节点名。写错的症状：`pmic_arb_check_chnl_status_v1: transaction failed (0x3)`（对不存在的从设备读）。仲裁器本身（`PMIC arbiter version v7`）在 ee0/channel0 下读写正常，不会因为 SPMI 一启用就挂死。[本机]

### 3.3 显示
- 借用 ABL 画面首次点亮，同时 `clk_ignore_unused pd_ignore_unused` 保住扫描；原生接管（msm DPU/DSI + 面板驱动 + 背光驱动）要尽快并行做，亮度/休眠都依赖它。[本机]
- 面板电源轨常在 **PMIC GPIO** 上（本机 PM7250B GPIO11/12），没有 SPMI/PMIC 节点时只能建「always-on 固定调压器」并登记债；休眠无法断电。偏压 IC（OCP2131，I2C）同理。[本机]
- 同一个 DT 节点要同时有真实 panel 和 DSC 参数；DSC 速率缓冲在某些 SoC 上要补丁（sky-linux 0003 的 hack）。[本机]
- 内核换代后第一件事：RAM 启动后比对 dmesg 与上一代的差异。[skill 经验]

### 3.4 触摸
- 主线没有的触摸 IC：自己写 input 驱动，用 `INPUT_MT_DIRECT` + `touchscreen_report_pos` + `touchscreen_parse_properties`；固件文件走 `request_firmware`，路径写在 DT `firmware-name`。[本机]
- 复位线、IRQ 线用 GPIO/IRQ 描述；复位脉冲本身安全，但**别在没确认时扫描 GPIO**。[本机]
- 触摸坐标范围要用手指/画点工具校准，不能只信显示分辨率（本机 x 最大约 1069 而不是 1079，原因未明）。[本机，待确认]

### 3.5 GPU（Adreno，对其他 a6xx 设备通用）
1. 内核侧要有：目录项（`a6xx_catalog.c`）、`gpucc` 驱动、GPU/GMU wrapper/SMMU/qfprom 的 DT 节点、SQE 和 zap 固件。社区（ROCKNIX 等）补丁给骨架，**板级数值仍取本机**。[本机]
2. **GPU 内存路径要完整**：interconnect（gem_noc → mc_virt EBI1）、`iommus`、OPP 的带宽值要和 interconnect 路径一致（有 `opp-peak-kBps` 却没有路径数 → OPP 核心返回 -EINVAL，GPU 驱动 probe 失败，连带 `msm_dpu` 绑定失败，显示都回退）。[本机]
3. **CP 超时的诊断顺序**：先看 `RBBM_INT_0_STATUS`、`CP_INTERRUPT_STATUS`（0x80 = 非法指令）、`CP_STATUS_1`、`ROQ`。同一镜像结果不稳 → 内存一致性（见 3.1）；SQE 版本字节是否为 0；换 SQE 看现象是否变化（a660_sqe 去掉了「非法指令」但 CP 仍不前进，说明根因不在微码）。[本机]
4. **zap shader 来自本机 vendor 的 `firmware/`**，名字可能是 `genX_Y_Z_zap`（`gen6_3_26_0_zap.mbn` 对应 A613），而不是 `aNNN_zap`。`mbn` 单文件和 `mdt+bNN` 拆分的元数据相同，**TZ 拒绝（-22）看的是签名内容**。DT 的 `firmware-name` 带 `qcom/<soc>/` 前缀并放在 initramfs `/lib/firmware`（用 `request_firmware_direct`）。zap 保留区必须是本机的。[本机]
5. **speed bin 在 `MSM_PARAM_CHIP_ID` 的高 32 位**（本机 `0xc9` = 201 → bin 1）。没有 `.revn` 的目录项会把 speed bin 放进 chip id 并让 `gpu_id=0`，**Mesa 只按 `gpu_id` 匹配 A6xx 低端款**：Mesa 26.1.6 有 608/612 没有 613，所以内核里设 `.revn = 612`（Mesa 里 608/612/613 是同一份配置）。**检查办法**：对着 `freedreno_devices.py`（对应 Mesa 版本的 tag，而不是 main）核对。[本机]
6. 低端 A6xx（gen1_low）的 turnip 是 **Vulkan 1.0**，不是 1.3（`conformanceVersion` 1.2.7.1 是 CTS 版本）。桌面更看重 freedreno 的 GLES/EGL：Weston `renderer=gl`，`GL renderer: FD612`。[本机]
7. 验证 GPU 的最小命令集：`eglinfo -B -p gbm`、`vulkaninfo --summary`、`kmscube -D /dev/dri/card1`、`weston --backend=drm`（renderer=gl）。顺序：先 no-start 推 rootfs 做前三项，再起 Weston。[本机]

### 3.6 RAM 桌面（不碰存储也能验证整套显示/触摸/GPU）
- Alpine v3.24 aarch64 闭包（`tools/apk-fetch.py` 验证 APKINDEX 签名和 .apk 校验和）通过 USB NCM 推进 tmpfs，chroot 里跑 eudev（libinput 要）、seatd、Weston（DRM 后端）、foot。要点：`mount --rbind /dev`（终端要 devpts）、`seatd -g root`、手工建 `/etc/passwd`/`/etc/group`、`busybox --install -s`（chroot 里没有 applet）、`LIBSEAT_BACKEND=seatd`。[本机]
- 主机 OpenSSL 在 Fedora 上拒绝 SHA-1 签名；Alpine APKINDEX 仍是 RSA-SHA1 → 用纯 Python 实现 PKCS#1 v1.5 验证，并带负对照。[本机]
- 内核 initramfs 内嵌 `CONFIG_INITRAMFS_SOURCE` 的 gen_init_cpio 列表，固件放 `lib/firmware/...`；重建只要 30 秒左右。[本机]

## 4. 工具与工作方式

- **把「重启 → 等 Android → fastboot boot → 等 ssh → 延长计时器 → 存 dmesg」做成一个脚本**（`tools/ram-retry.sh`）。17 次 GPU 迭代每次约 2.5 分钟，没有它做不到。[本机]
- 每个设备命令显式指定 serial，输出用 `sed` 屏蔽；日志、固件、备份只放 `private/`。[本机]
- 批量替换版本号（m6→m7）时别用裸 `s/m6/m7/g`：会把 `arm64`、`-m644` 弄坏；用带边界的正则。[本机]
- 长命令用后台任务 + 通知，不要轮询；过期的后台通知不是用户输入。[本机]
- 生成式 DTS（`tools/gen-mN-dts.py`）：每个候选 = 上一个候选 + 一组清楚标注的改动。比手改一份大 DTS 更容易追溯、回退、做单变量对照。[本机]
- GPU 频率/负载测试：`kmscube` 会 poll stdin，ssh 无 tty 时读到 EOF 就当「用户中断」立刻退出（0 帧，容易误判成「跑了 12 秒」）；保持 stdin 打开用 FIFO（`mkfifo f; exec 3<>f; kmscube <&3`），别用 `tail -f | kmscube`（管道不结束）。算帧率看它自己打印的 `Rendered N frames ... fps`；面板 90 Hz 时 90.00 fps = vsync 限速，不是性能指标。[本机]
- 内核本地改动：`git diff > kernel-local/linux-7.3-local.diff` 和基线提交一起保留；调试输出统一加标记（`E012-DEBUG`），登记进 TECH_DEBT 以便清理。[本机]
- `adb`/`fastboot` 不可见时先看 `lsusb`；ACM 重启不一定生效；Android 起来后再等 25 秒才稳。[本机]

## 5. 新设备开工清单（建议顺序）

1. 立项：确认授权范围（清数据？重分区？无人值守上机？），建立 AGENTS.md、STATUS/HANDOFF/LOG/TECH_DEBT。
2. 只读取证：运行时 DT、`/proc/iomem`、分区表、vendor/OTA 镜像（固件、dtbo）、电量；备份启动链并校验。
3. 找复用：同 SoC 社区项目（本项目：ROCKNIX、sky-linux）、上游补丁；按接口词搜索（芯片名、驱动名、协议）。
4. 构建环境：工具链、ccache、长期 OUT；参考内核原样构建一次。
5. 通道与回退：`fastboot boot` 镜像 + init 计时器 + USB ACM/NCM + ssh 公钥；pstore 不可靠时靠 USB 日志。
6. 最小 DT：内存（先小）、串口/USB、SMMU、时钟/电源域；显示（借用 ABL 画面）→ 触摸 → 全内存 → RAM 桌面 → PMIC/SPMI → GPU → 存储。
7. 每步：预期/判据/回退写好 → 上机 → 日志存 `private/` → 文档更新 → 金件备份。
8. 无人值守窗口：只上已验证风险等级的候选；用 `ram-retry.sh` 式脚本迭代。

## 6. 还没解决/本项目的开放问题（接手者先读）

- 屏幕上的 Weston 桌面与触摸方向/边缘没有经人眼验证（没有截图通道）。
- SPMI + PM6450/PM7250B GPIO 控制器已能注册（m11 stage A，E013）；阶段 B（把面板供电和背光 HWEN 接到 PMIC GPIO）未做；面板电源轨仍是 always-on 假调压器。读 `debugfs/gpio` 会挂死整机。
- 持久化（rootfs 放哪）需要重分区，未授权。
- 主线 Mesa 对 A613 的支持（升级 Mesa 后撤掉 `.revn = 612`）；GPU 高频档的稳定性与电压（见 GPU.md 最新节）。
- 上游化：触摸驱动 binding 未用 dt-schema 校验；panel/backlight 驱动里有 vendor 来源代码，署名与许可见 TECH_DEBT。

## 无线（WiFi/BT）移植的前置判断（2026-11-10，详见 WIFI-BT.md）
- 先分清总线（SNOC/PCIe）与驱动路线，再动手；同一颗 WCN 芯片在 DT 里有多种写法，指向互不兼容的驱动。第三方“某路线走不通”的结论先标“未复现”，用最便宜的只读判据复核。
- WiFi 与 BT 共用 WPSS 与电源轨：先把 WPSS 作为独立里程碑（IPCC + AOSS QMP + SMP2P + PAS + 固件 + QRTR 服务可见）打通，再叠驱动。
- 固件多半不在 OTA 镜像里，而在 modem/bluetooth 等分区：做分区备份时一并保留，既是恢复依据也是固件来源；厂商镜像是分段 mdt 时，DT 的 firmware-name 必须写 .mdt。
- 运行时 DT 中 disabled 的节点不等于芯片不存在：dtbo 覆盖层按板号注入，要核对实际启用的覆盖层。
- 内核自带 QRTR 名字服务，调试只需 qrtr-lookup（不需要 qrtr-ns）。

## 间歇性「开机首次上电失败」类问题（E017）
- 先量化再猜：写一个脚本做 N 次冷启动、每次分类（成功/失败/重试次数）并记录，基线失败率 + 对照条件几次就能判假设；注意脚本自己别出错（两个循环同时跑、ssh 在设备重启时不超时挂住、回 Android 以 sys.boot_completed 为准，否则中止该次）。
- 在**失败的那次启动里**直接做受控扫描最快：init 里加开关，在失败后按不同参数（断电 0.05/0.2/0.5/1/2 s）重绑，一次启动就能看到阈值；比重启几十次省得多。
- 「X 假设已否」的结论要记下**怎么检验的**，否则以后无法复核：本例的旧结论「断电时长无关」是错的，真正的阈值在 0.2–0.5 s 之间。
- 芯片侧复位往往需要供电真正掉电一段时间（去耦电容放电）；驱动重试里毫秒级的 off/on 不等于复位。共用的供电轨在上一个系统（Android）遗留为开，首次上电时芯片可能从没经历过掉电——首次上电前先做一次真正的断电。
- 工具坑：`pkill -f 模式` 会匹配到自己的命令行（含模式文本）把当前 shell 杀死（退出码 144）；用 PID 或 `[x]` 括号写法，且命令行里不要再出现完整模式字符串。

- switch_root 之后，旧根里的进程仍以（已被清空的）旧根为 `/`；要让新根接管服务（sshd/串口/网络），必须在切换前杀掉旧根的守护进程，并让新根自己带同类服务。能把远程通道切断的实验，先装好新根里的回程（定时重启）再切换。[本机]
