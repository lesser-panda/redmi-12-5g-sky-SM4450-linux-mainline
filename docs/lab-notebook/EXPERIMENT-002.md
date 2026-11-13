# E002：匹配 PixelOS boot 的 Magisk RAM 启动

用户授权永久 root；本次先尝试不刷分区的 fastboot boot。
输入：已校验 PixelOS boot + 官方 Magisk 31.1，由目标设备 ARM64 官方 boot_patch.sh 修补。
候选：private/root-session/magisk-boot.img，哈希见 private/root-session/SHA256SUMS。
离线核验：header v4，内核与原包 cmp 完全一致；KEEPVERITY=true、KEEPFORCEENCRYPT=true、PATCHVBMETAFLAG=false。设备工具检测 preinit=sda12（metadata）。
patch.log 中三条 Failed to patch 是官方脚本可选 Samsung kernel hexpatch 未命中；内核 cmp 相同，ramdisk 修补和 repack 成功。
预期：Fastboot 接受后进入同版本 Android，Magisk 提供受授权的 root；返回原 boot 普通重启可撤销临时内核侧 root。Magisk/app 会产生持久数据，不视为全程只读。
回程：拒绝启动则 fastboot reboot；若启动后 ADB 可见但 root 不可用，采集信息后普通重启；早期硬挂需用户长按电源，不能承诺自动恢复。
不执行 flash/set_active/erase。本轮 root 成功后先读取本机 boot 链，再讨论是否有必要永久写 boot。

结果：失败，未获得可用 root shell。Fastboot accepted，ADB 恢复、magiskd 和 /debug_ramdisk/.magisk 存在，但 Android 未完成启动，activity 服务最初缺失、system_server 后启动，出现 pre-watchdog，su id 返回 Permission denied。不能判为 Magisk 成功。
已保存 private/root-session/{boot.log,crash.txt,system-tail.txt,failed-boot-logcat.txt}，随后 adb reboot 回未修改 boot。未 flash、未切槽。
待区分：Magisk 与当前系统兼容问题，还是 fastboot boot 路径本身导致原包镜像不能完整启动。唯一有区分力的下一次启动实验是同一个未修改 boot 的 RAM 负对照；不得直接刷失败候选。
