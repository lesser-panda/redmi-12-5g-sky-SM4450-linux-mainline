# EXPERIMENT-007（E028）：脱离 PC 的 Linux 启动（recovery_b 路线）

授权：2026-11-12 用户明确允许“set up booting from phone”，要求先告知方案。此授权覆盖写 recovery_b；不覆盖 boot_a/boot_b、vbmeta、改活动槽、清数据（需另行确认）。

## 方案
- Android 保持默认启动（B 槽，boot_b = Magisk 修补镜像，不动）。Linux 放进 **recovery_b**（sde51，100 MiB；镜像 ~71 MB 可容纳）。`adb reboot recovery` / Vol-Up+电源 / Debian 里 `reboot recovery` 进 Linux；普通重启回 Android。
- Linux 镜像 m19 = m18 + 自动 root：initramfs 带 `/etc/autoroot`，init 等 `/dev/sda22`（PARTNAME=linuxroot）后自行 mount 并 switch_root，`touch /run/sky-keep` 关掉 Debian 的 50 分钟 failsafe；失败则 init 的 420 s 定时器 `reboot -f` 回 Android。
- 未验证的前提：abl 在 recovery 模式下是否把 recovery 分区当完整 boot 镜像（含自带 kernel）加载。ROM 自带 recovery.img 的 kernel_size=0，说明原厂 recovery 可能借用 boot 的内核——这正是第一次测试要回答的问题。
- 回退：`fastboot flash recovery_b private/rom/extracted/recovery.img`（sha256 7d208cd1…，ROM 20240922；上机前再读出 recovery_b 比对哈希）。若 abl 不加载自带内核，改试 boot_a 路线（另行告知用户）。

## 步骤与判据
1. 用户运行 `! tools/build-m19.sh`（产出 out/candidates/m19/，SHA256SUMS）。
2. 上机前：电量 ≥50%；root 读 recovery_b 的 sha256 == 7d208cd1…（只读）；记录 m19 boot 镜像哈希。
3. 先 `fastboot boot` m19（RAM）验证 autoroot：不 ssh 触发，等 ≤3 分钟，手机应自己进 Debian（WiFi ssh 可达，/run/sky-keep 存在）。
4. `fastboot flash recovery_b <m19 boot 镜像>`，`adb reboot recovery`：预期同上；失败（回 Android/停在 fastboot/黑屏）→ 记录并回退。
5. 无线缆测试：拔线，从 Android `reboot recovery`，WiFi ssh 确认；再从 Debian `reboot` 回 Android。
## 运行 1（2026-11-12）：m19 RAM 启动验证 autoroot
- 输入：Image 3d69157e…；DTB c0b3a0bd…；boot d3299b5f…（out/candidates/m19/SHA256SUMS）。`tools/cycle-boot-m17.sh m19`（只 fastboot boot，不 ssh 触发）。预期：≤3 分钟内手机自己进 Debian，WiFi ssh 可达，/run/sky-keep 存在。回退：失败则 init 420 s 定时器重启回 Android。电量 100%。
- 运行 1 结果：通过。不经 host ssh，Debian 约 1 分钟内自己起来（WiFi ssh 可达，root=/dev/sda22，/run/sky-keep 存在，systemd running）。
## 运行 2：刷 recovery_b
- 前置核对：recovery_b 当前哈希 == ROM recovery.img（7d208cd1…，2026-11-12 10:0x root 读出）；回退镜像 private/rom/extracted/recovery.img。写入：`fastboot flash recovery_b out/candidates/m19/sky-m19-shim-boot-v4.img`（71340032 B < 100 MiB，sha256 d3299b5f…）。之后正常重启确认 Android 不受影响，再 `adb reboot recovery`。
- 运行 2 结果：fastboot flash recovery_b OKAY（69668 KB），Android 正常启动（B 槽，boot_completed=1）；写入前缀哈希核对见下。
- 运行 2 前缀哈希：recovery_b 前 71340032 B == 镜像 d3299b5f…（一致）。
## 运行 3：`adb reboot recovery` with m19 in recovery_b（2026-11-12）— 失败，并留下 fastboot 循环
- 结果：`adb reboot recovery` 后手机 13 s 内进入 fastboot，没有进 Linux。abl 不把 recovery_b 里的 m19 当可启动镜像（原因未证明；ROM 自带 recovery.img kernel_size=0，推测 abl 的 recovery 路径需要借用 boot 的内核/其他组件，我们的完整 boot v4 镜像不被接受；猜测，未验证）。
- **副作用（重要）**：此后每次启动（`fastboot reboot`、`fastboot continue`、换回 ROM recovery_b 之后也一样）都停在 fastboot；`fastboot continue` 报 `Failed to load image from partition: Not Found`。`fastboot getvar all` 里 slot-unbootable:a/b 都是 yes、slot-retry-count 6、slot-successful yes（此前无记录可对照，不据此下结论）。
- 当时的判断（**后被运行 4 更正，见下**）：misc 分区（sda3，第 0 字节起）里有 BCB 命令 `bootonce-bootloader`（19 字节，其后全 0），我以为它是循环原因；运行 4 证明该命令单独不会让手机进 fastboot。`fastboot fetch` 在此 abl 不可用，所以当时读不到 misc。
- 恢复步骤（本次实际用的，全部在授权范围的邻近动作内，misc 的写入事先已备份并向用户说明）：
  1. `fastboot flash recovery_b private/rom/extracted/recovery.img`（ROM recovery，sha256 7d208cd1…）— 不是解开循环的关键，但恢复了原状。
  2. `fastboot boot out/candidates/m19/sky-m19-shim-boot-v4.img`（RAM 启动，不写任何分区；autoroot 进 Debian，ssh 可达）。
  3. 备份 misc 到 private/e028/misc-before-clear.img（1 MiB，sha256 c27210da…），只把前 32 字节（BCB command 字段）清零：`dd if=/dev/zero of=/dev/sda3 bs=32 count=1 conv=notrunc,fsync`，回读哈希与预期一致（c0df50d9…）。0x8000 之后的其他非零字节（厂商数据）未动。
  4. `systemctl reboot` → Android（B 槽）正常启动，boot_completed=1，电量 100%，Magisk su 可用。
- 以后避免：不要再用 `adb reboot recovery` 试 recovery_b 里的 Linux。若手机又陷入 fastboot 循环：RAM 启动任一带 ssh 的候选（上面第 2 步），读 /dev/sda3 前 32 字节，若是 `bootonce-bootloader` 就按第 3 步清零。需要时也可以让用户在 Android 里用 `reboot` 之外的方式不依赖 PC，但 Linux 在手时上面这条最直接。
- 状态：recovery_b 现在是 ROM 原版。E028 的 recovery_b 路线不通；备选是 boot_a 路线（会改 boot_a，超出用户授权，需先征得同意；a 槽目前未启用，改它不影响当前 b 槽 Android，但仍要先问用户）。
## 运行 4：对照与取证（2026-11-12）
- 对照（本机验证）：recovery_b 放 ROM 原版、misc 已清，`adb reboot recovery` → 约 15 s 进入 PixelOS recovery（adb 状态 unauthorized），说明触发方式和 abl 的 recovery 路径可用，问题在我们的镜像。退出 recovery 后 misc 保持干净（command 字段全 0）。
- **abl 自己的日志可读**：`logfs` 分区（FAT12，8 MiB）里有最近 5 次启动的 UefiLog0..4.txt（root 读 /dev/block/by-name/logfs；副本放 private/e028/，含序列号，不公开）。ROM 原版 recovery 那次的日志显示：`Get Reboot reason: 0x1` → `KeyPress:0, BootReason:1`、`Fastboot=0, Recovery:1` → `Booting from slot (_b)` → `Booting into Recovery Mode via Boot`（recovery 无内核时用 boot 的内核）→ 依次载入 vbmeta_b、boot_b、dtbo_b、vendor_boot_b、recovery_b → `vbmeta_b: Public key used to sign data rejected`，但 `boot state: orange`，继续启动。即 AVB 不拦截（已解锁）。
- 局限：每次启动（含 fastboot）都会写一份日志，只留最近 5 份，第一次失败（m19）的日志已被覆盖。
- 实验（上机前记录）：重新刷 m19 到 recovery_b（输入 out/candidates/m19/sky-m19-shim-boot-v4.img，sha256 d3299b5f…，71340032 B）；`adb reboot recovery`。预期：很可能再次落入 fastboot（上次结果）；判据：失败后立刻（≤3 次启动内）RAM 启动 m19 进 Debian，读 logfs 的 UefiLog，找到 abl 对 recovery 镜像的拒绝原因；若这次居然进了 Linux，记为成功。回退：RAM 启动 Debian → 备份并清零 misc 前 32 字节 → 刷回 ROM recovery.img（7d208cd1…）→ 重启 Android（运行 3 的步骤）。电量 100%。
- 运行 4 结果（失败，但拿到原因，本机验证，abl 日志见 private/e028/run4/）：m19 在 recovery_b 时，abl 走 `Recovery:1 → Booting Into Recovery Mode`（recovery 自带内核的路径），只载入 vbmeta_b、recovery_b、dtbo_b（**不载入 boot_b 和 vendor_boot_b**），然后 `Err: line:1376 LoadImageAndAuthVB2() status: Not Found` → `Alternate slot not Found / No bootable slots found enter fastboot mode` → 进 fastboot。对照：`fastboot boot` 同一镜像走 Mission Mode，载入 vbmeta_b、dtbo_b、**vendor_boot_b**，成功——v4 镜像没有自带 DTB，DTB 在 vendor_boot 里。所以“Not Found”的最可能解释是 recovery 自带内核路径没有 vendor_boot，找不到 DTB（推断，尚未用 v2 镜像验证）。ROM 原版 recovery（无内核）走 `Booting into Recovery Mode via Boot`：载入 boot_b、dtbo_b、vendor_boot_b、recovery_b，不是我们要的（会用 Android 的内核）。
- **更正运行 3 的因果**：misc 里的 `bootonce-bootloader` 是 `adb reboot bootloader`（刷写时）写的；运行 4 里它又出现了，但 Android 照常启动，所以它本身不会让手机进 fastboot。运行 3 里的“fastboot 循环”真正的退出条件是 RAM 启动 Debian 后用 `systemctl reboot`（整机复位）——清 misc 与否不是已证明的关键。也就是说：清零 misc 是无害的，但不是已证明有效的修复；可靠的恢复步骤是 `fastboot boot` 进 Linux 后 `systemctl reboot`（待下次再确认：失败后 `fastboot reboot` 为什么回 fastboot，可能是 abl 用的 PMIC 重启原因寄存器没被清除）。
- 下一步实验（上机前）：recovery_b 放 header v2 镜像（kernel=shim Image，ramdisk=同一个 512 B cpio，dtb=ROM vendor_boot 的 DTB，让 abl 的 recovery 路径自带 DTB）。
## 运行 5：header v2 镜像放 recovery_b（2026-11-12）— 内核从 recovery 启动成功；Debian 阶段异常
- 输入：out/candidates/m19r/sky-m19-shim-boot-v2.img（sha256 1e8065bf…，71753728 B；header v2，kernel=shim Image（同 m19），ramdisk=同一个 512 B cpio，dtb=ROM vendor_boot 的 DTB（私有，734eb4b8…），base 0、kernel_offset 0x8000、ramdisk_offset 0x1000000、tags 0x100、dtb_offset 0x1f00000，os 14.0.0/2024-09）。构建命令见本节末。fastboot flash recovery_b OKAY，读回哈希一致，Android 正常启动，电量 100%。
- 结果（本机验证）：`adb reboot recovery` 后约 16 s，192.168.7.1:22 响应（initramfs 的 sshd）——**abl 的 recovery 路径接受了带自带 DTB 的 v2 镜像并启动了我们的内核**，推断（运行 4）成立：v4 镜像失败是因为这条路径不载入 vendor_boot，没有 DTB。
- 异常：之后主机再也连不上：192.168.7.1 “No route to host”，WiFi <phone-wifi-ip> 不通，手机的 IPv6 链路本地地址 fe80::5c:6dff:fe00:2 能 ping（8–10 ms），但 TCP 1–2047 全无监听。ACM 口上的旧 shell 还活着但已无命令（switch_root 清空了 initramfs，说明已切到 Debian）。即：内核活着，autoroot 已切根，但 Debian 的 sshd/网络没起来（原因未知）。对照：同一个 m19 内核/DTB 用 `fastboot boot` 时 Debian 约 1 分钟内起来（运行 1）。猜测差异来自 abl 在 recovery 路径下的环境（未验证）。
- 无法远程取证：autoroot 设了 /run/sky-keep，所以没有定时回 Android；需要人在场按住电源键约 10 s（手机会重启回 Android；recovery_b 里的镜像不影响正常启动）。
- **运行 5 事后分析（本机验证，Debian 日志 private/e028/run5/journal，用 `journalctl --directory=…` 读）**：手机并没有挂死：Debian 在 15:10:36 启动（对应测试时刻），但进了 emergency 模式（`dev-ttyGS0.device`、`dev-disk-by-label-linuxboot.device` 等待 90 s 超时 → local-fs.target 失败；sshd 从未启动；整个启动慢到 23 分钟），原因是内核日志里 3167 条 `msm_dpu … vblank wait timed out`、2917 条 soft lockup（CPU#7 卡 79 s），起点是 `DSI PLL(0) lock failed`。同一内核/DTB 用 `fastboot boot`（前三次启动，无此错误）时日志里是 `[dpu error]INTF_1: boot scanout did not stop`——内核接管的是 abl 已点亮并在扫描的屏幕。**结论：我们的原生显示（msm_dsi/dpu）只在 abl 已初始化 DSI 时才工作；recovery 路径下 DSI 是冷的，PLL 锁不上，vblank 等待把 CPU 拖死。**（recovery 路径下 abl 为何没留下点亮的 DSI：未查明。）日志在 17:50:47 突然结束，手机随后关机（原因未知，不是电量：恢复后 100%）。
- 技术债：原生显示依赖 abl 先点亮 DSI（冷 PLL 初始化有问题）。
## 运行 6：recovery_b + header v2 + 不启用原生显示（2026-11-12）
- 输入：`M17_NODISPLAY=1 tools/mk-dtb-candidate.sh m19nd m19`（DT 与 m19 只差 `&mdss { status = "disabled"; }`，Image 同 m19 3d69157e…，DTB 5870731d…）；`tools/mk-recovery-v2.sh m19nd` → out/candidates/m19nd/sky-m19nd-shim-boot-v2.img（71753728 B，sha256 6f13c013…）。
- 预期：`adb reboot recovery` 后 ≤2 分钟 Debian 起来，192.168.7.1 或 WiFi 可 ssh，无 emergency；屏幕保持 abl 的画面（无原生显示/GPU，GNOME 若起来走 simpledrm）。判据：ssh 可达且 `systemctl is-system-running` 为 running/degraded、journal 无 vblank/soft lockup。失败回退：用户长按电源键约 10 s（手机回 Android）；之后读 Debian 日志。电量 100%，用户在家。
- **运行 6 结果（失败，无数据）**：`adb reboot recovery` 后手机在 USB 上完全消失（无 Linux gadget、无 adb、无 fastboot），用户在场观察：屏幕从未亮过，手机一直是冷的；长按电源后回 Android。Debian 日志里没有新的一次启动（最后一次仍是 15:10–17:50 那次），abl 日志显示 abl 走到了 `Shutting Down UEFI Boot Services`（已跳转内核）。所以 m19nd 在内核早期就死了/停了（原因未知；它与 m19 的唯一差别是 `&mdss` 关闭——是否相关未证明）。
- **abl 日志里的关键发现（本机验证，run5/run6 的 UefiLog2）**：recovery 自带内核的路径上：`Dtbo hdr magic mismatch 52444E41, with D7B7AB1E`（它在 recovery 镜像里找 recovery_dtbo，读到的是 "ANDROID!" 的头）→ `DTB offset is incorrect, kernel image does not have appended DTB` → `Splash region not found in device tree, powering down the display and controller` → `M19_Panel_LCD_PowerDown!`。正常路径会 `Load Image dtbo_b` 并 `Apply Overlay`（运行时 DT 里的 cont_splash 区域来自 dtbo）；recovery 路径不读 dtbo_b 分区，改读镜像头里的 recovery_dtbo 字段（header v1/v2），我们的镜像该字段为空。结果：abl 把屏幕和面板关了，内核的原生显示冷启动 DSI 失败（运行 5 的 PLL lock failed 和 vblank 卡死）。
## 运行 7：recovery_b + header v2 + recovery_dtbo=ROM 的 dtbo.img，显示保持启用（2026-11-12）
- 输入：m19 候选（Image 3d69157e…，DTB c0b3a0bd…，v4 镜像 d3299b5f…）经 `tools/mk-recovery-v2.sh m19`（已改为附带 `--recovery_dtbo private/rom/extracted/dtbo.img`，ROM 20240922，与设备 dtbo_b 比对哈希见下）→ out/candidates/m19/sky-m19-shim-boot-v2.img。
- 预期：abl 日志出现 `Apply Overlay`/不再有 `Dtbo hdr magic mismatch`、不再 `powering down the display`；屏幕保持点亮；Linux 进 Debian，ssh 192.168.7.1 或 WiFi 可达，journal 无 vblank/PLL 失败；判据同运行 6。回退：用户长按电源键 10 s；之后读 abl 日志（logfs）和 Debian 日志。
- **运行 7 结果（通过，本机验证，2026-11-12 18:5x）**：recovery_b = out/candidates/m19/sky-m19-shim-boot-v2.img（95870976 B，sha256 b552541c…，读回一致）。`adb reboot recovery` → 32 s 内 192.168.7.1 的 initramfs sshd 响应，约 1 分钟后 Debian：`uname -r` 7.3.0 m19，root=/dev/sda22，/run/sky-keep 存在，`systemctl is-system-running` = running，失败单元 0，WiFi <phone-wifi-ip> 可 ssh，gdm3 active，电量 100%，内核日志无 vblank/soft lockup/PLL 失败，且出现 `boot scanout did not stop`（abl 把屏幕留亮，原生显示正常接管）。abl 日志（private/e028/run7/）：`Recovery:1 → Booting Into Recovery Mode`，有 `Apply Overlay total time: 249 ms`，不再有 `Dtbo hdr magic mismatch`、`powering down the display`。从 Debian `systemctl reboot` → Android（B 槽）约 42 s，不会回到 recovery。
- 根因总结（运行 3–7）：recovery 自带内核的路径不读 dtbo_b 和 vendor_boot_b。v4 镜像没有 DTB → `Not Found` → fastboot；改 v2 后 abl 找不到 recovery_dtbo（头里为空）→ DT 缺 splash 区域 → 关屏 → 我们的 DSI 冷启动失败 → 内核卡死/进 emergency；把 ROM 的 dtbo.img 放进 v2 的 recovery_dtbo 字段后一切正常。运行 6（m19nd，无原生显示、无 recovery_dtbo）手机一直不亮、冷着，原因未查明，未再追。
- **手机独立启动 Linux 的方法（已在“有线缆、主机辅助观察”条件下验证）**：Android 里 root 执行 `reboot recovery`（或 `adb reboot recovery`）→ 约 1 分钟进 Debian；回 Android：Debian 里 `systemctl reboot`（或长按电源）。**未验证**：拔线后（只靠 WiFi/屏幕）、按键组合进入、从 Android 本机终端发起。
- 注意：recovery_b 现在是我们的镜像（不是 ROM 原版）；ROM 原版在 private/rom/extracted/recovery.img（7d208cd1…），回退 `fastboot flash recovery_b …`。镜像含 Xiaomi 的 vendor_boot DTB 和 dtbo（只在 private 构建，不发布）。如果以后在 Android 里用系统“重启到恢复模式”，会进 Linux 而不是 PixelOS recovery。
