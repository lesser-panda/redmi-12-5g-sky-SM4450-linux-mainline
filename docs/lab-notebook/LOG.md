# 工作日志

## 2026-11-09
- 创建可迁移工作区；用户报告的系统情况与授权范围记录于 AGENTS.md。
- 沙箱不提供 /dev/bus/usb 且禁止 ADB 监听 socket；主机级只读调用成功启动 ADB，USB 枚举成功，设备状态 unauthorized。尚未执行任何 Android shell、重启或刷写。
- ADB 获授权并完成只读采集，确认 sky/SM4450、Android 14 与 AtomX 5.10；详见 DEVICE.md。Android 锁定属性与用户陈述冲突，经授权的 Fastboot 查询确认实际已解锁，修正了对属性的疑虑。
- E001 完成：Android 正常返回，sys.boot_completed=1、B 槽不变；采集文件校验通过。尚无镜像级备份。
- 用户补充旧恢复包找不到、曾 OTA 更新；“2013”按前文暂解释为“2023”，不是已确认日期。后续恢复依据实测 ro.modversion。
- 固定并审阅用户指定 sky-linux；发现地区/内存差异、缺失所引用板级 DTS 和 initramfs 存储写入路径，详见 SKY-LINUX-REVIEW.md。
- 查询到匹配 PixelOS_sky-14.0-20240922-0137 的官方归档及同日期 recovery，开始获取 ROM。
- ROM 默认镜像传输约数百 KiB/s，预计数小时，停止本次下载并保留 .part；尚未取得可用恢复镜像。手机仍在 Android，本轮没有重启或写设备。
- 用户将匹配 ROM 放入 private/rom/；独立复核 SHA-256 通过，包内 metadata 和 kernel 与设备采集结果一致。已提取并校验六个启动相关镜像，细节见 RECOVERY.md。
- recovery.img 不包含内核，ramdisk 为 secure user 配置；修正“可直接用同版本 recovery 临时启动取得 root”的潜在假设。下一步先准备可审阅的临时启动/备份方案，本轮没有操作手机。
- 继续评估：匹配 ROM + 官方 Magisk 的临时 root 路径优于未经核实的 TWRP；官方 APK 已获取并核对发布 digest。具体待授权范围及回退限制见 TEMP-ROOT-PLAN.md。
- 已准备默认 dry-run 的两槽启动镜像备份工具；未取得 root、未安装 APK、未生成或启动候选。当前 Android/B 槽在线，电量 100%。
- 用户授权永久 root。Magisk 31.1 安装且在设备端修补匹配 boot，内核 cmp 一致。E002 RAM 启动进入 ADB/Magisk daemon，但 Android 框架未稳定、root shell 未获准；已普通重启回原 Android，boot_completed=1、B 槽，无刷写。
- 启动 E003 原包 boot RAM 对照以区分问题，不将 E002 失败候选刷入 boot。
- 用户自行 root（手动提取并 Magisk 修补 boot_b），E002 之后的状态以此为准。授权 Shell su 后 uid=0 验证成功。
- 修复 backup-boot-chain.py 的 exec-out 引号错误（首次运行把 73 字节错误信息当镜像，被长度断言拦下，产物移入 private/failed-attempts/）。
- 备份 12 个启动链镜像到 private/backup-20261109T142217Z/，全部三方哈希一致。boot_b=Magisk 修补版；b 槽其余镜像等同 ROM 20240922；a 槽为旧版 2024-08。
- 取出 /sys/firmware/fdt 到 private/runtime-20261109T142413Z/，model "Qualcomm Technologies, Inc. Ravelin QRD"，compatible qcom,ravelin-qrd；panel msm_drm.dsi_display0=qcom,mdss_dsi_m19_42_03_0b_fhd_dsc_vid；触摸 focaltech SPI。cmdline 记录于 runtime.dts。
- 新增 tools/backup-unique.py 并执行：private/backup-unique-20261109T142656Z/ 含 75 个分区镜像（唯一/校准、底层固件、modem/dsp/bluetooth）与 12 个 GPT 头尾块（sda–sdf，4096B 扇区），全部 verified。可作恢复材料，但未做恢复演练。
- 构建主线候选 m1：拉取 Linux 7.3、ROCKNIX SM4450 补丁（36/49 可直接应用，0022 手工 fuzz 应用）、gcc 15.2.0 交叉工具链；自写最小 DTS 与 init；审阅并构建 sky-linux shim；候选哈希见 EXPERIMENT-004.md。busybox-static 下载被自动模式分类器拦截，未执行也未绕过。未碰设备。
- E004 上机：fastboot boot 候选 m1，用户确认企鹅、PID 1、心跳，120 秒自动重启回 B 槽 Android。pstore 无日志（失败记录保留）。
- 里程碑 2 候选 m2 构建：USB dwc3+HS PHY DTS、busybox 初始化脚本（ACM 串口 shell、15 分钟自动重启）、tools/acm-console.py；busybox 包经 APKINDEX 控制段 SHA-1 与大小核对。待用户确认上机。
- E005 通过：USB ACM shell。三个单变量修复：qcom,select-utmi-as-pipe-clk、去掉 dma-coherent、init 计时器；从屏幕症状到主机 journalctl -k 定位到 ep0 不应答。主线 7.3 在设备上 8 核运行，取得 dmesg。
- 解析 dtbo.img：真实面板 xiaomi_m19_42_03_0b（1080x2460@90Hz，4 lane 视频模式 DSC）在 dtbo 中，运行时 FDT 只有占位面板；写入 docs/PANEL.md。
- 0009 rebase：除 ubwc_config.c 外直接应用，UBWC 改为 7.3 共享描述符一行；整理面板板级接线（复位 GPIO92，三条 GPIO 固定调压器 GPIO11/12/127，背光 GPIO6/7）。
- m3 候选构建：启用 DRM_MSM 全内置（解决 QCOM_OCMEM/DRM_DISPLAY_HELPER 模块依赖）；新增 panel-xiaomi-sky.c（DSC，sequences 从 dtbo 生成）；gen-m3-dts.py 生成含 SMMU+显示的 DTS；内核全量 diff 与配置存 kernel-local/。待用户确认上机（E006）。
- E010 离线准备：m7 候选（SPMI/PMIC GPIO + touch-paint）已构建、未上机。tools/gen-m7-dts.py、build-m7.sh、cycle-boot-m7.sh。新发现 OCP2131 偏压 IC（PANEL.md）。用户不在场时手机保持 Android 空闲。
- E011 离线准备：m8 全内存映射、Alpine 验证下载、RAM 桌面 rootfs 与推送脚本；均未上机。
- E011 运行：m8 失败（USB 高地址 DMA），m9 通过（8 GB、memfill 0 错误、Weston 桌面在 DSI-1 运行）。
- 2026-11-10 GPU 调查（离线，docs/GPU.md）：Adreno 613（0x06010300），ROCKNIX 内核补丁已在树中，Mesa 设备表含 613（freedreno + turnip）；缺 a630_sqe.fw、a613_zap.mbn、DT 的 gpu/gmu/adreno_smmu 节点。turnip 在 A613 上无公开实测，需上机。
- E012 离线准备：m10（Adreno 613 GPU 节点+固件+GL 桌面包）已构建、未上机；固件取自 PixelOS vendor 镜像（私有）。tools/gen-m10-dts.py、build-m10.sh、cycle-boot-m10.sh、gpu-test.sh。
- E012 上机（无人值守）：17 次运行定位并修复 GPU 链路：interconnect+OPP、4 GiB dma-ranges 权宜之计破坏写合并缓冲（改 USB iommus）、zap 固件选错（应为 gen6_3_26_0_zap.mbn）、Mesa 26.1.6 无 A613（.revn=612）。结果：FD612 GLES 3.2、turnip Vulkan 1.0、Weston GL 渲染器运行。
- E013 SPMI：arbiter v7 OK；PM7250B SID 修正为 8；读 debugfs/gpio 致硬挂死（待用户恢复）。写 docs/LEARNINGS.md（通用经验）。GPU 全频率档通过（E012 补充）。
- 2026-11-10 WiFi/BT 离线调查（docs/WIFI-BT.md）：WiFi = WCN6750 adrastea（SNOC，WPSS 子系统），固件在 modem_a 备份（已提取到 private/wifi/，哈希复核）；ath11k 路线被第三方证伪，可行路线是厂商 qcacld+icnss2（未复现）；蓝牙 = WCN3950 级（Android 日志实证，下载 cmbtfw13+cmnv13，与主线 hci_qca 的 wcn3950 路径吻合），可在不依赖 WPSS 的情况下做 m13。E014 离线准备：m12（WPSS remoteproc + SMP2P/IPCC/AOSS QMP + qrtr-lookup）已构建，未上机。
- 2026-11-10 晚：**人眼验证通过**（用户陈述“Works great!”）：m10（Adreno 613）+ Weston `renderer=gl` 桌面在 DSI-1 显示，触摸可用。tools/desktop-up.sh 已改为 m10（RENDERER=gl tools/desktop-up.sh）。用户未逐项报告方向/边缘/多点，细节未单独验证。
- 2026-11-10 晚 E015：**蓝牙在主线上可用**（m13：RPMh LDO + wcn3950-pmu + QUP wrapper 0 + uart2 + qcom,wcn3950-bt，固件取自 bluetooth_a）。芯片版本与 Android 一致，补丁/NVM 下载、HCI_RESET、btmgmt 扫描均通过。坑：geni UART 需 serial 别名；L23B 兼供 USB2 PHY；启动时首次上电间歇性失败，重绑可恢复（根因未明）。
- 2026-11-10 晚：**蓝牙配对通过**（m13 + 桌面 bluez/blueman，用户与另一台手机配对，Paired/Bonded）。desktop-up.sh 支持 `M=m13`；桌面 rootfs 增加 dl-bluez/dl-glycin/dl-icons。
- 2026-11-10 夜 E016：**WiFi 在主线 7.3 上工作**（m14 RAM 启动）：WPSS 起 → WLFW(0x45) → icnss2 FW ready（bdwlanu_cn.bin）→ qcacld wlan0 → 扫描 → WPA2 → DHCP → 公网。构建过程四处修补见 EXPERIMENT-006 E016；用户批准构建第三方 sky-qcacld（经宿主 `!` 运行，因自动权限策略拦截 agent 直接 make）。fw-api 取自 MiCode/vendor_qcom_opensource_wlan@02e10575（sparse 检出）。
- 2026-11-10 夜：GPIO debugfs 在 m14 完整读出不挂死（E016 补记）；蓝牙首次上电根因=芯片需要供电断开 ≳0.5 s，已用内核补丁修复，10/10 冷启动通过（E017）；KDE Plasma 桌面通过，用户确认桌面/触摸/WiFi 菜单/蓝牙菜单（E018）。
- 2026-11-10 夜 E019：KDE 满亮度偏暗的原因是背光芯片配置（ktd3136.c 的 ginkgo 初始化表）与本机 Android 不同；读 Android 的 /proc/ktd3136_backlight/backlight_ic_info 对照，改为 Android 值后用户确认 fbcon 明显变亮（运行时写寄存器），内核补丁已入 m14 候选（Image 91e256ab…，boot 6ef21a99…）。新镜像上的亮度待用户确认；手机此刻在该 m14 RAM 系统中（fbcon，无 KDE）。
- 2026-11-10 夜 E020：UFS 在 m15 上工作（只读，未挂载）；STORAGE.md 给出存储布局与加密事实；用户选定的分割 Android 40 / Linux 68 GiB 已记录，重分区待用户明确授权。
- 2026-11-10 深夜 E021：Debian trixie GNOME 的 second stage 在手机 RAM 里 6 分钟完成；switch_root 后失联（旧根进程问题），已修复待重跑。手机需长按电源键。

## 2026-11-11
- E021 运行 2 通过：Debian trixie + GNOME（Wayland）systemd 启动，WiFi/BT/GPU 在位。E020 补充：UFS HS-G3 2 lane，2 GiB 顺序读 156 MB/s（两次 sha256 一致），health EOL 0x01。
- 构建 m16（ADSP/pmic-glink/按键/RTC）；从 Debian `reboot -f` 后手机从 USB 消失，等待用户长按电源。
- 2026-11-11 晚：从 Debian 用 systemctl reboot（先停 sky-charge-limit 并写 3 0 恢复充电输入）回到 Android，成功（对照 reboot -f 的消失）。

## 2026-11-11（夜，E027 音频）
- 去掉非上游的 `qcom,rx/tx-channel-mapping`（m17e）后 SoundWire 通道掩码一致，听筒出声（用户确认）；扬声器仍只有爆音。
- 时钟校正 + timesyncd，外网可用。
- m17f–m17i：麦克风采集打通（tx-port-mapping、DEC0+DEC1 两车道、大缓冲），建立声学环回传感器；扬声器客观无声（−123 dBFS vs 听筒 −88 dBFS）；ear3 判别实验把问题定位在 FS1599 之前；SWR master 端口 4 为 1 bit 端口（字长假设被否定）。工具见 tools/（mic-on、route、loop、tone-detect、poke-test、swrpoke/peek/dump、mmio）。

## 2026-11-12 重新 root（用户授权：安装 Magisk 并刷入已修补镜像）
- Magisk-v31.1.apk（sha256 89cefac0…，sources/magisk-v31.1/）已 adb 安装。
- 计划：fastboot flash boot_b private/rom/magisk_patched-boot.img（sha256 836ef70f…，由 private/rom/boot.img 5c36ecdd… 修补，与 ROM 20240922 匹配，pre-init=sda12=metadata 仍然正确）；回退：fastboot flash boot_b private/rom/boot.img。当前槽 _b，电量 99%。
- 结果：boot_b 刷入 OKAY，重启回 Android（_b），/debug_ramdisk 存在（Magisk 生效）；等待用户在 Magisk app 授权 adb shell su。
- 2026-11-12：magiskd 在运行，但 adb shell 的 su 仍 'inaccessible or not found'；Magisk app（31.1，装在 user 0）无法用 adb 启动其 MainActivity（stub 式 APK，需要用户在桌面点图标完成首次启动并授权）。手机锁屏中。
- 2026-11-12：重新 root（见上）；Android 基线对比（regmap debugfs + rx_swr_ctrl）找到扬声器根因（rx macro stride2），运行时 poke 验证出声（传感器 −36 dBFS，用户确认听到）；内核补丁写入 kernel-local/linux-7.3-local.diff，tools/build-m18.sh 待用户运行。
- 2026-11-12：m18（rx macro stride2 补丁）构建并 RAM 启动验证：扬声器无需 poke 即出声（传感器 −41.8 dBFS），听筒不退化。
- 2026-11-12 09:2x：m18 RAM 启动约 15 分钟后 USB gadget 掉线（dwc3-qcom: 'port-1 HS-PHY not in L2'、'failed to enable ep0out'，UDC not attached，usb0 DOWN、无 ACM）；系统本身正常，WiFi（<phone-wifi-ip>）可 ssh。回 Android 需要 ssh over WiFi 执行 systemctl reboot。待查：USB 掉线原因（是否与睡眠/断线有关）。
- 2026-11-12：Debian 用户态音频：alsa-ucm-conf + 自写 UCM（audio/ucm2/Xiaomi/sky）+ sky-fs1599 + udev 规则，tools/install-audio.sh 安装；PipeWire 出现扬声器/底部麦克风，pw-play/pw-record 与 GNOME 系统声音通过（用户确认）。
- 2026-11-12：USB gadget 在 m18 启动约 16 分钟时掉线（dwc3-qcom “failed to enable ep0out”），线缆是否被动过待用户确认；WiFi ssh 可用。
- 2026-11-12：USB gadget 掉线后用户重新插线仍不恢复；`echo a600000.usb > /sys/bus/platform/drivers/dwc3-qcom/{unbind,bind}`（tools/usb-rebind.sh）恢复（UDC configured，ACM/usb0 回来）。
- 2026-11-12：冷启动音频验证通过（m18 + UCM + PipeWire，无手工步骤，传感器 −54.4 dBFS）。
- 2026-11-12：E028 方案写入 docs/EXPERIMENT-007.md（Linux 放 recovery_b，Android 默认不动）；initramfs-m14/init 加 /etc/autoroot 自动 root（门控，不影响其它候选）；tools/build-m19.sh 待用户运行。
- 2026-11-12：加速度计调研（只读）：Android sensorservice：BOSCH bma4xy Accelerometer（I2C 地址 0x18，bus_instance 1，DRI 中断 GPIO 61，vddio 由 PMIC client sensor_vddio），Memsic mmc56x3x 磁力计，ROHM bu27030 光感，另有备选 lis2hh12（0x1e）与 sx933x（SAR），原始配置在 private/sensors/（私有）。AP 侧 DT 看不到这些传感器（ADSP 的传感器核心管理）；recovery_b 当前哈希 == ROM recovery.img（7d208cd1…）。
- 2026-11-12：E029 传感器总线探测：m17k（pinctrl -EINVAL，保留 GPIO）、m17l（删保留范围）→ 手机失联约 7 分钟后自动回 Android；结论 AP 不能直连传感器总线（EXPERIMENT-008）。
- 2026-11-12 10:xx：E028 运行 3：`adb reboot recovery` 进的是 fastboot（m19 在 recovery_b 不被 abl 启动）；之后手机每次启动都停 fastboot——misc 里残留 `bootonce-bootloader`。已 RAM 启动 m19 进 Debian、备份 misc（private/e028/）、清零 BCB command 32 字节、重启，Android 回来（B 槽，root 可用）。recovery_b 已恢复为 ROM 原版。详见 EXPERIMENT-007 运行 3。
- 2026-11-12 下午：E028 运行 4：abl 日志（logfs 分区）证明 recovery 自带内核路径不载入 vendor_boot → 找不到 DTB → fastboot；运行 3 对 misc 的因果判断已更正。详见 EXPERIMENT-007。
- 2026-11-12 晚：E028 运行 7 通过：recovery_b 放 header v2 镜像（附 dtbo 做 recovery_dtbo），`adb reboot recovery` 手机自己启动 Debian（健康，显示正常），`systemctl reboot` 回 Android。运行 5 手机因显示冷启动卡死后关机，运行 6 无反应（原因未查明）。详见 EXPERIMENT-007 运行 4–7。
- 2026-11-12 晚：音量上+电源键进入 recovery_b 的 Debian 经用户确认（独立启动，拔线场景用户已试）。DisplayLink 坞与 USB-C 键盘无反应：查明内核没有 xhci（USB 主机栈缺失）。新增 tools/build-m20.sh（m19 + USB 主机/存储/以太网 + FUSE/squashfs/overlayfs/binfmt_misc）、tools/build-evdi.sh、sources/evdi-src（上游 DisplayLink/evdi HEAD 8acd0b28，GPL-2.0），方案见 docs/EXPERIMENT-009.md。待用户运行 build-m20.sh。

## 2026-11-12
- E031 run 2: DisplayLink dock via evdi + DisplayLinkManager; Mutter needed a display-manager restart to list DVI-I-1 (details in docs/EXPERIMENT-009.md). Monitor output awaiting user confirmation.
- E031 run 2 confirmed by user: DisplayLink HDMI screen works, hot replug works, software cursor fixes the pointer. DisplayLink added to rootfs build (tools/displaylink-stage.sh, desktop-debian/displaylink/, push-debian.sh, customize.sh); live installer refactored onto the same files.
- Everyday packages installed on the phone; tools/debian-roots.txt created (root set for deb-fetch); customize.sh writes apt sources incl. security + Flathub.
- Applied 47 package updates on the phone (snapshot private/e031/dpkg-before-upgrade.txt); verified services/displays/Firefox; see EXPERIMENT-009.
- Swap file service (4 GiB /swapfile, auto-created on persistent root, swappiness 30) installed and tested live; hooked into rootfs build. User confirmed sound is good.
- zram: tools/build-m21.sh (CONFIG_ZRAM built in) and desktop-debian/sky-zram(.service) written; service installed on the phone (no-op until m21). Kernel build pending (user runs it).
- E031 run 3: m20 v2 written to recovery_b (readback ok, boots Debian). Dock incident = user pressed power on a blanked screen → power-button-action suspend → deep suspend never resumed (journal + user statement); power button and idle suspend now disabled, resume failure with dock logged in TECH_DEBT.
- Amp power saving: sky-amp-watch user service (amp on only while the PipeWire Speaker sink is idle/running; measured ~21 mA idle saving); audio setup now packaged (audio-stage.sh/install-target.sh) for live install and rootfs build. m21 (zram) kernel built OK; evdi rebuild + RAM test pending.
- docs/ROOTFS-COMPONENTS.md: inventory of what lives outside the kernel and which pieces could move in (assessment only). Amp watcher user-confirmed (tone and beeps heard).
- m21 (zram) RAM-tested then written to recovery_b (readback ok, boots Debian, zram active). evdi.ko rebuilt/reinstalled for m21.
- 2026-11-12 night: m22 (dwc3-qcom UTMI-clock resume fix: dock survives suspend, no 31 s stall; qcom_battmgr kernel charge limit 75/80; local hwdb for UPower) RAM-tested, then written to recovery_b (readback b9dd59b9…, boots Debian). EXPERIMENT-009 runs 9–13.
- Dock dark after cold boot: Mutter ignores an evdi GPU created after it started; added sky-evdi.service (evdi pre-loaded with a device before GDM), verified by simulated boot order; cold-boot confirmation pending.
- tools/phone-monitor.sh started (4 h, 30 s interval) while the user leaves the phone idle on the dock (screen off after 2 min, no suspend); evdi-in-kernel queued in HANDOFF/EXPERIMENT-009.
- Idle monitor findings: screen blank/off as configured, SPMI RTC alarm-enable write spam (92% of the log) logged in TECH_DEBT; monitor still running.
- Wake from screen-off with the dock mouse works (monitor log 21:42:27); keyboard wake still to try. Monitor still running.
- Manual suspend with dock: wake took ~35 s (xHCI resume -110 timeout) and the dock was lost; recovered by dwc3-qcom rebind + role host (no replug). Likely the cause of the first no-wake incident. Monitor restarted.
- E032 load test (391 min, 14 cycles) finished: PASS, 0 kernel errors/OOM kills/verify errors, 75/80 limiter held over 22 transitions; remaining items listed in EXPERIMENT-010.
- m23 (tplg built into kernel + PM_DEBUG) persisted in recovery_b, audio card 3/3 boots (E033).
- E034 prepared: in-kernel FS1599 amp driver + DT + tools/build-m24.sh (not built); watcher unit yields to the kernel driver and excludes root (E033 follow-up).
- 2026-11-13 E034: m24 (in-kernel FS1599 amp) persisted in recovery_b (v2 d8e0770e…, readback equal), 3/3 cold boots from recovery_b: preset loaded, card present, 0 failed units, amp ON during playback / OFF after. User confirmed both speakers. Userspace amp watcher, sky-fs1599, 90-sky-audio.rules removed from the rootfs build (audio/install-target.sh, tools/audio-stage.sh) and from the phone; originals archived in private/audio/retired-userspace-amp/. TECH_DEBT rows for the watcher and the i2c udev rule deleted.
- 2026-11-13: audio packaging scripts and bring-up debug scripts (route/mic-on/speaker-on/loop/poke-test/fs1599.py) removed; UCM install folded into push-debian.sh + customize.sh (untested until the next full rootfs build). Archive: private/audio/retired-userspace-amp/tools/.
- 2026-11-13: tools/tone-detect.py and tools/swrpoke.sh retired too (archived with the other audio debug scripts). Publication prep started on user request (no push; see docs/PUBLISHING.md once written).
- 2026-11-13: publication prep: docs/PUBLISHING.md (decisions, plan), tools/release-scan.sh (privacy/licence scan), LICENSES/ (GPL-2.0-only, MIT); 2 personal-data hits fixed. Nothing pushed.
- 2026-11-13 E035: clean-checkout build of the published tree (release/) booted from RAM: Debian, fs1599 preset loaded, card/GPU/display/input/BT up; out-of-tree modules (qcacld, evdi) fail on the new kernel build as expected; AUTOROOT=0 variant built, not booted. See EXPERIMENT-011.md.
