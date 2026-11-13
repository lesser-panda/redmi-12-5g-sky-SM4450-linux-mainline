# 持久根文件系统：方案与前置条件（草案，2026-11-10）

状态：**未执行任何存储写入**。本页只是计划，所有标「需授权」的步骤在用户明确同意前不做。

## 已确定（用户陈述）
- 根发行版：Debian + GNOME（RAM 演练见 EXPERIMENT-006 E021）。
- 保留 Android 作行为参考（用户陈述）。
- 内部分割倾向：Android 约 40 GiB / Linux 约 68 GiB（用户 2026-11-10 选择；含 60 GiB 根 + ~8 GiB home/swap）。重分区的授权尚未给出（用户睡前明确「先不重分区」）。

## 本机事实（见 STORAGE.md）
- userdata = sda20，约 107.9 GiB，位于 sda 最后；块层加密（本机验证），不能离线缩小，只能重建。
- 主线 7.3 已能只读识别 UFS（E020）。
- 槽 B 是当前 Android；boot_b 是用户修补的 Magisk 镜像（无原版）；备份见 RECOVERY.md。

## 步骤与授权
1. 备份用户数据到宿主（`adb pull /sdcard`、应用列表）——只读，需用户在场确认范围。
2. 重建 userdata 为更小（需授权：出厂重置 + GPT 修改）；先对 sda 的 GPT 头尾做三方哈希备份（已有 6 个 LUN 的头尾，见 STATUS）。
3. 在 sda 末尾新增 Linux 分区（需授权）：根 ext4（或 f2fs）约 60 GiB，其后 home/swap；分区名固定（如 `linux_root`、`linux_home`）。
4. 启动路径三选一（需用户选，见对话）：A）继续 `fastboot boot`（无写入）；B）另一槽 boot_a 放 Linux 启动镜像并切槽（需授权，且槽 B 的 Android 不动）；C）recovery 分区放 Linux 启动镜像，`adb reboot recovery` 进 Linux、普通重启回 Android（未验证本 ROM 的 recovery 加载路径）。
5. 把 E021 的根（debootstrap 式 second stage）装进新分区，initramfs 以 PARTLABEL 找根并 switch_root，替换 /run/switch-root 演练钩子。
6. 冷启动与回切验证：Linux 与 Android 来回切换各 N 次，记录。

## 未决
- microSD/USB 外置存储方案未调查。
- 休眠（sleep）与相机尚未开始，不依赖持久根，但持久根能节省每次 6 分钟的推送并保留日志。
