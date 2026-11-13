# 安装到手机

分两级。先做第一级；第二级只用于持久桌面系统，并且**会清除 Android 的用户数据**。

## 第一级：从 `recovery_b` 免主机启动（一个分区，可恢复）

前提：[BUILDING.md](BUILDING.md) 走通，`out/boot/sky-recovery_b-v2.img` 存在，内存启动能进 shell。

```sh
# 手机：Android，B 槽，USB 调试，root，电量 > 50 %
tools/flash-recovery-b.sh
```

脚本在槽位不对或电量低时拒绝，先把当前 `recovery_b` 存到 `vendor/backup/`，要求确认，用 `fastboot` 刷入，回读分区并比较哈希。然后：

```sh
adb reboot recovery     # 启动 Linux
ssh -i vendor/ssh/id_ed25519 root@192.168.7.1
# 在 Linux 里：  systemctl reboot   -> 回到 Android（busybox 镜像里用 reboot）
```

没有 Linux 根分区时，这会启动小 initramfs 系统，7 分钟后自动回到 Android。

## 第二级：Debian + GNOME 装到内部存储（破坏性）

会发生什么：手机主闪存换新分区表，Android 数据分区从约 108 GiB 缩到 40 GiB 并被清空（Android 会重新走首次开机设置），并为 Linux 新增两个分区。启动链分区、`modem`、`persist` 和 A 槽不动。先备份你在乎的一切，并按 [EXTRACTING-VENDOR-FILES.md](EXTRACTING-VENDOR-FILES.md) 保存 GPT。

1. **规划布局。** `tools/gpt-split-sda.py <gpt-head.bin> <gpt-tail.bin> <outdir> [userdata_gib] [boot_gib]` 读 `sda` 的首尾 1 MiB（取自你的手机），把新的 GPT 块和计划写到 `<outdir>`，不碰任何设备。用 `sfdisk` 检查计划（22 个分区、无重叠、无空隙）。我们**不提供自动写入器**：写三个 GPT 块（主表、备份表项、备份头）是唯一一步写错就会毁掉手机分区表的操作，所以请手工完成，在内存启动的 Linux 里，先把设备上的实际块与你的备份逐字节比对。测试机上用的完整序列和检查见实验笔记（E025）。
2. **重置 Android 数据。** 在内存启动的 Linux 里把 `metadata`（`sda12`）和 `userdata` 开头清零，然后让 Android 走首次开机设置（重新打开 USB 调试）。
3. **构建 Debian 根。** `tools/deb-fetch.py` 和 `tools/build-debian-stage1.py` 组装经过验证的 Debian trixie arm64 基础系统（`debootstrap --foreign` 风格：包里的任何东西都不在你电脑上运行）。`tools/push-debian.sh` 把它推到内存启动的手机上，运行第二阶段（`dpkg --configure`，20–40 分钟），应用 `rootfs/customize.sh`（用户、GNOME 自动登录、服务、电源默认值、UCM 音频配置），在 `PERSIST=1` 时创建 ext4 文件系统（`sda21`/`sda22` 的 GPT 名字不是 `linuxboot`/`linuxroot` 就拒绝）并把根拷过去。
4. **WiFi 和坞（可选）。** `tools/fetch-sources.sh --rootfs`，然后在第 3 步之前运行 `tools/build-wifi-modules.sh`（厂商 `qcacld` 驱动，树外，必须与启动镜像里的内核匹配）；DisplayLink 需要厂商驱动压缩包以及 `tools/build-evdi.sh` + `tools/displaylink-stage.sh`（见 [DOCK.md](DOCK.md)）。
5. **启动。** 镜像里有 `/etc/autoroot`（默认），`adb reboot recovery` 会挂载 `sda22` 并切换进去。登录：桌面用户 `user`（屏幕上自动登录）、用你的密钥经 USB 以 root ssh、GNOME。WiFi 凭据不随仓库发布：`push-debian.sh` 会读 `vendor/wifi/credentials.txt`（含 `ssid=`/`psk=` 行），也可在 GNOME 设置里配。

**第二级的状态：** 这些脚本构建出了项目运行并测试了数天的系统，但发布后**尚未从干净检出重跑**（每次都依赖在线手机，约一小时）。预计需要修一些小问题，欢迎提交修复。
