# E001：Fastboot 身份与解锁状态只读核验

授权：2026-11-09 用户允许现在重启检查。
输入：当前已安装 Android；不下载或启动任何外部镜像。
目的：区分 Android 属性伪装与 bootloader 真正锁定，读取启动布局参数。
步骤：复查电量 → adb reboot bootloader → 以固定 serial 等待 Fastboot → getvar 与 oem device-info → fastboot reboot → 等待 ADB。
边界：不执行 flash/erase/flashing unlock/set_active/boot；所有输出保存在 private/。
判据：Fastboot 解锁输出为 bootloader 侧证据；返回 ADB 并 sys.boot_completed=1 为 Android 恢复证据。
回程：主机可见 Fastboot 后无论查询是否支持均发 fastboot reboot；若 USB 不可见则停止并请用户长按电源恢复，不盲目写入。

结果：通过。bootloader 确认 unlocked=true / critical unlocked=true；所有查询完成并执行 fastboot reboot。Android ADB 恢复后 sys.boot_completed=1，槽位仍为 _b。
证据：private/20261109T104300Z-fastboot/transcript.txt 和 android-return.txt。
