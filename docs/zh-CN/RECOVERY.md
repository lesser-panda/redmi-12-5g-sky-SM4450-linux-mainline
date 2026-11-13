# 安全与恢复

## 项目遵守的规则（你也应该遵守）

1. **先从内存启动。** `fastboot boot` 不写任何东西。每次内核改动都先这样试。
2. **镜像内置保险。** initramfs 在 7 分钟后重启（手机默认启动 Android），除非被延长；`panic=15` 让内核 panic 后自动重启。
3. **离开 Android 前读电量**，保持高于 50 %。
4. **一次只写一个分区。** `tools/flash-recovery-b.sh` 只写 `recovery_b`（PixelOS 的 B 槽 recovery，别的东西不用它），先保存旧内容并回读校验。
5. **保留回退。** 上一个可用镜像留在你的磁盘上；Android 自己的 boot、vendor_boot、dtbo 从不触碰。

## 出问题时

| 情况 | 怎么办 |
|---|---|
| 写 `recovery_b` 后手机陷入 bootloader（fastboot）循环 | `fastboot boot out/boot/sky-boot-v4.img`（内存启动）进入 Linux shell，然后 `reboot`。或还原保存的镜像：`fastboot flash recovery_b vendor/backup/recovery_b-<时间>.img`，或刷 ROM 里的原厂 `recovery.img` |
| 手机黑屏、无 USB | 长按电源 10–15 秒（硬重启）；之后手机从默认槽启动 Android，可在 Android 里 `adb reboot bootloader` 进 fastboot |
| Linux 卡死 | 长按电源 10–15 秒，下次启动是 Android。Debian 里 `reboot -f` 曾让手机失联一次：请用 `systemctl reboot` |
| 重分区后 Android 数据没了 | 预期行为（见 INSTALLING.md）；恢复办法是保存的 GPT 加恢复出厂 |
| 想完全回到 Android | `fastboot flash recovery_b` 刷回 ROM 里的原厂 recovery；你加的分区可以闲置，或用保存的 GPT 合并回去 |

## 已知的危险点

- `cat /sys/kernel/debug/gpio`，或通过 `/dev/mem` 读未知的 TLMM/PMIC 寄存器，可能让 SoC 硬死。不要这么做。
- 向 `recovery_b` 刷错 header 版本的启动镜像，bootloader 会拒绝并回落到 fastboot，原因见 [ARCHITECTURE.md](ARCHITECTURE.md)。可按上表恢复。
- `adb reboot bootloader` 加 `fastboot reboot` 不会留下持久的启动标志；Android 仍是默认启动。
- 这里没有任何东西会重新锁定 bootloader。运行改过启动链的设备不要重新上锁。
