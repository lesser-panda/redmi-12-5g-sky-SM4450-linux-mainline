# E004：主线内核 RAM 启动（里程碑 1a，simple-framebuffer）

状态：候选已构建，**未上机**；等待用户确认后执行。

## 目的与路线
证明主线 Linux 7.3 能在本机以 `fastboot boot` 从 RAM 启动，并在 ABL 留下的屏幕上显示内核日志和 PID 1 心跳。
先用 simple-framebuffer（用户选择）；成功后再做 DSI 面板驱动（里程碑 1b/2，另立实验）。本实验无 USB shell；USB gadget 为下一里程碑。

## 输入（out/candidates/m1/SHA256SUMS）
| 文件 | SHA-256 |
|---|---|
| sky-m1-shim-boot-v4.img（要 fastboot boot 的镜像，37457920 B） | de71c48dc655212298fe501f6616482cdcf446f6489e844d7a70bb96a07cbc29 |
| Image（Linux 7.3 + 补丁，内嵌 initramfs） | b2027ba270dcd64dd0743a70f057025e3daff476204c338eab41e4c4e09fc5df |
| sky-m1.dtb（dts/sm4450-xiaomi-sky-m1.dts） | 8a715ebaf010b1ca1df031b63823818b3779e153d42a729a94afc9d9137c195f |
| init（本项目自写，无 libc） | 1ab609a3ca5844d8dfe29d5df24aa7c5c00511fbca6fabc3e23725551471bc6d |

来源：
- 内核 linux-7.3.tar.xz，sha256 87363c24…，与 kernel.org 一致。
- 补丁：ROCKNIX distribution 提交 e0fb1430ceaf7a7144be06751730c3d06325fe54，projects/ROCKNIX/devices/SM4450/patches/linux/ 中可干净应用的 36 个 + 0022（fuzz 3 手工应用）；sky-linux 提交 d78c42a2 的 kernel/patches/0001（pinctrl TZ 保护 GPIO）。其余 12 个未应用（显示/面板/音频/QMP combo/手柄），本里程碑不需要。
- 配置：sky-linux kernel/configs/sky-m1.config（为 7.3 做 olddefconfig，INITRAMFS_SOURCE 改为本项目路径）。
- shim：sky-linux shim/（逐行审阅：只画屏幕顶部状态条、复制内核/DTB 到 RAM、清 BSS、跳转；无存储写入、无 PSCI/看门狗/PMIC 访问）。在 out/shim-build/ 副本中用本项目工具链构建，sources/ 未改动。
- 工具链：kernel.org crosstool gcc 15.2.0 nolibc aarch64，sha256 a3b99f6f…。
- 复现：tools/build-m1.sh（含手工应用 0022 的前置步骤，见 TECH_DEBT.md）。

## 内存与保留区（本机证据）
DTS memory 仅 0xc0000000–0xe05fffff（518 MiB）：Android /proc/iomem 的连续 System RAM，无 reserved 子区。
shim 在 0xA8000000（ABL 加载 boot.img 处，Android 内核也在此），内核装载 0xc0000000，DTB 0xc2800000。
simple-framebuffer：0xb8000000，长度 0x2b00000（runtime DT 的 cont_splash_region），1080x2460，stride 4320，a8r8g8b8。stride 和高度来自 sky-linux 在另一台机器上的 shim 实测，本机未验证；若画面错位，改 DTS 重测。
ramoops：0x97700000，2 MiB，与 Android 运行时 DT 的 ramoops 参数相同，使 Android 能读出 Linux 的控制台日志。

## 预期与判据
通过（PASS）：屏幕出现 shim 蓝条，最后一行 `LINUX jumping`；随后内核日志刷屏；出现 `*** sky mainline m1: userspace PID 1 reached ***` 和每 5 秒的 heartbeat；约 120 秒后自动重启，回到 B 槽 Android（boot_completed=1）。
加分：回到 Android 后 root 读 /sys/fs/pstore/console-ramoops-0 含上述内核日志（验证无 USB 的取证通道）。
部分：shim 显示但无 `LINUX jumping`/无内核日志 → 地址或 payload 问题；内核日志停在某驱动 → 记录最后一行，按驱动定位。
失败：无任何画面 → 可能 fastboot boot 未接受镜像、framebuffer 地址不同。

## 回退与风险
- 不 flash、不 set_active、不改 vbmeta、不解锁，仅 `fastboot boot`；所有分区保持原样，boot_b 仍是用户的 Magisk 镜像。
- 正常：init 120 秒后 reboot；panic 时 `panic=15` 15 秒后重启。重启后回到 B 槽 Android。
- 卡死：长按电源键约 10–15 秒强制重启（用户需在场）；若进入 fastboot，则 `fastboot reboot`。
- 电量 100% 且充电中（2026-11-09 实测）；离开 Android 前再读一次。
- 最坏情形下的恢复材料：private/backup-20261109T142217Z/（启动链两槽）、private/backup-unique-20261109T142656Z/（固件/校准/GPT）；未做恢复演练。
- 已知风险：未验证的驱动（ROCKNIX 配置里的大量内置驱动）可能在早期触发外部中止；失败日志将保留，不重复相同实验。

## 执行步骤（获得用户确认后）
1. 读电量和 pstore 现状；`adb reboot bootloader`。
2. `fastboot -s SERIAL boot out/candidates/m1/sky-m1-shim-boot-v4.img`，用户观察屏幕并拍照/描述（用户在场）。
3. 等 120 秒自动回 Android；若未回，长按电源。
4. 回到 Android 后：读 /sys/fs/pstore、确认槽位与分区未变，保存证据到 private/E004/。

## 结果（2026-11-09，用户在场观察）
**PASS（屏幕判据）**。fastboot boot 接受镜像（Sending 36580 KB OKAY，Booting OKAY）；用户报告屏幕出现企鹅（fbcon logo，每核一只，说明 simpledrm+fbcon 与 SMP 起来了）、内核日志、`userspace PID 1 reached`、心跳，120 秒后设备自行重启，无需长按电源。
回到 Android：约 140 秒后 adb 在线，sys.boot_completed=1，仍为 B 槽；没有刷写、改槽或改分区。
用户陈述为主要证据；未保存屏幕照片。
**未通过（加分项）**：回到 Android 后 /sys/fs/pstore 为空，无 console-ramoops。ramoops 路径作为取证通道目前不可用。可能原因（均未验证）：ABL/重启过程清了该 RAM；Android 的 ramoops 先于读取覆盖；本内核 ramoops 未成功绑定（未看到内核日志）。后续用 USB 通道取 dmesg，不再在此投入。
证据：private/E004/{pre,boot-time,fastboot-boot,post}.txt。
结论只写到：主线 7.3 + 自制 DTS 在本机经 shim 从 RAM 启动并运行到 PID 1，simple-framebuffer 可用，超时自动回 Android 有效。fastboot boot 路径在本机可行（E002/E003 的不稳定应来自 Android 镜像本身，不是 fastboot boot）。
