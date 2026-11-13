# sky-linux 复用审阅

来源：https://github.com/orange200213/sky-linux
用户于 2026-11-09 指定优先参考。浅克隆位于 sources/sky-linux（约 2.6 MiB）。
固定提交：d78c42a27e403f8207e813e051f3b1e142ffb101。
本次仅阅读，未运行该项目脚本，未启动或刷入其镜像。

## 已核对的差异与限制
- README 的验证设备是日本版、4 GB、HyperOS OS1.0.13.0.UMWJPXM；本机为 23076RN4BI、约 8 GB、PixelOS Android 14。板级电源、内存保留区、面板和固件需本机核对。
- 启动文档走 Android v4 boot.img 内的 shim，自带内核与 DTB；示例写 boot_a，要求 active slot a。本机为 B 槽，不能直接套用命令。
- 当前克隆 dts/ 只有 README.md，文档引用的 sm4450-xiaomi-sky.dts 不存在于该目录；不能宣称仓库开箱可复现。生成器依赖未随仓库提供的相邻 sky-mainline 树。
- initramfs/init 第 110 行起寻找 linuxroot，未找到时回退 /dev/sda21，以默认读写挂载 ext4 并写日志；不适合本项目首次只读 RAM 实验。
- install-and-usage.md 同时声称不写存储和挂载 userdata 写日志；与当前 init 也有差异。以实际代码为准。
- shim 没有 watchdog；未找到首次启动独立超时回退的充分证据。
- kernel/README.md 指向 ROCKNIX SM4450 补丁，但未固定该来源提交；需要补齐可复现输入。

## 决定
作为优先源码与经验参考，不直接刷现成镜像。先取得本机启动备份、DT、保留内存及面板证据；复用前将首次 initramfs 改为 RAM-only、块设备只读并加入回退。直接 ABL fastboot boot 能否工作尚未验证，不能把它等同于项目的持久 boot_a 启动路径。
