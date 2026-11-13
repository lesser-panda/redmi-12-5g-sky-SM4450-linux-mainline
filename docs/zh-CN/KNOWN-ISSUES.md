# 已知问题与技术债

对粗糙之处的如实清单。标 (code) 的在树里可见。

## 不可用的硬件
蜂窝、摄像头、传感器、GPS、NFC、指纹、振动：见 [STATUS.md](STATUS.md)。

## 行为
- **坞 + 休眠：** 接着 DisplayLink 坞时，手机有时休眠 0.1–2 秒就自己醒；键盘唤醒和按电源键可能再次触发唤醒。唤醒源未确定（内核带 `PM_DEBUG`，`pm_wakeup_irq` 测试还没做）。因此默认关闭 GNOME 空闲休眠和电源键休眠。
- **USB 主机在位时恢复：** 见过一次约 35 秒的 xHCI 恢复超时，需要重绑 `dwc3-qcom` 才恢复（补丁 0008 里有恢复修复，假设未完全证实）。
- **Debian 里 `reboot -f`** 曾让手机失联一次；请用 `systemctl reboot`。
- **glmark2** 在负载测试的某些时段得分下降约 15 %，原因未找到。
- **PMIC RTC** 不保持时间（开机靠 NTP）；SPMI RTC 驱动日志很吵。
- **蓝牙** 需要 1 秒最短断电补丁，冷启动后才能可靠起来。
- **WLAN 驱动** 在 debug 级别日志很多；厂商 `qcacld` 驱动是树外的，必须与内核完全匹配。

## 代码与配置债
- (code) 内核树里留有 GPU 调试代码（CP 初始化失败时的寄存器转储、固件回读检查）。
- (code) A613 目录项报告 `revn = 612`，让 Mesa 26.1.x 接受它。Mesa 认识该 id 后改回 613。
- (code) 为了让树与测试过的一致，保留了这台手机不用的 ROCKNIX 文件：`rsinput.c`、`aw88166.c`、一处 ath10k 修改。
- (code) 设备树还没有 SoC 温度区和较低的 CPU 最大频率限制。
- (code) 启动镜像里的 Android header 花样（v2 header、原厂 DTB blob、`recovery_dtbo`）只是为了满足 ABL。
- (rootfs) `rootfs/` 脚本面向 Debian trixie，用的是自制的 `debootstrap --foreign` 替代品，不是为复用设计的。
- **树外模块与内核构建绑定。** `qcacld`（WiFi）和 `evdi`（坞）必须针对你构建的每个内核重新编译；别的构建出的模块会报 "Invalid module format"，`sky-wifi.service` / `sky-evdi.service` 会失败。根文件系统脚本针对 `sources/linux-7.3` 构建它们。
- (tools) `evdi` 是 DisplayLink 坞用的树外内核模块；DisplayLink 驱动是专有下载。
- initramfs 里的 Alpine 包在构建时解析为当前版本（签名已验证，但版本会漂移）。
- Linux 7.3 是开发内核；除 [UPSTREAMING.md](UPSTREAMING.md) 里的候选项外，这里没有东西走在上游路径上。
