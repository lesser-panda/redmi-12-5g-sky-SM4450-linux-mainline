# 存储布局与持久化根文件系统的前提（2026-11-10 只读调查）

来源：Android（槽 B，Magisk root）下的只读命令，原始输出 private/storage-survey/out.txt（本机验证）。没有写入任何分区。

## 事实
- 槽位 `_b`；UFS 控制器 1d84000.ufshc；sda 总容量约 117 GiB（122773504 KiB）。
- userdata = sda20，113164108 KiB（≈107.9 GiB），是 sda 的最后一个分区；/data 已用约 25 GiB，可用约 82 GiB。
- /data 挂载设备是 `/dev/block/dm-40`，`/dev/block/mapper/userdata` 存在，fstab 里 userdata 带 `inlinecrypt`，属性 `ro.crypto.type=file`：f2fs 位于 dm 加密层（元数据加密，推断为 dm-default-key，未读 dm 表）之上，另有文件级加密（FBE）。密钥由 Android 的 keystore/TEE 路径解开，RAM 里的 Linux 读不到（E020 本机验证：m15 只读读 /dev/sda20 前 4 KiB 为高熵、无 f2fs 魔数；/dev/sda12 有 ext4 魔数）。
- 其它 sda 分区：persist sda2（32 MiB）、misc sda3、cust sda8（2 GiB）、super sda9（6.5 GiB，动态分区，当前挂载的是 *_b 组）、metadata sda12（16 MiB）。
- 槽相关分区在 sde：boot_a sde13 / boot_b sde39，vendor_boot_a sde23 / _b sde49，recovery_a sde25 / _b sde51，dtbo、vbmeta 同理。
- `/data/unencrypted`、`/data/local` 存在，但 /data 整体在加密块层之内，所以「在 /data 里放 loop 镜像再由 Linux 读」不可行。
- 主线 7.3 + m15（E020）已能识别 UFS（SKhynix HN8T062EHKX039，sda–sde），分区名/大小与 Android 一致。
- 没有读到 dm 表（无 dmsetup）、`reboot recovery` 实际加载哪个镜像（recovery_x 还是 vendor_boot）未验证。

## 结论
- 要给 Linux 一块内部分区，必须缩小 userdata，而元数据加密意味着不能离线缩小 f2fs：只能重建 userdata（出厂重置，Android 数据全清，需要用户明确授权）。
- 不想清数据的话，内部存储没有空闲空间（cust 仅 2 GiB）。可选外部存储（microSD/USB 盘，尚未确认本机有可用的读卡槽和上游驱动）。

## UFS 运行状态（本机验证，2026-11-11，Debian 内核 m15 上）
- 链路 HS-G3、2 lane、HS_RATE_B（`power_info`），SKhynix HN8T062EHKX039，health_descriptor eol=0x01（正常）。
- 一致性：同一 2 GiB（sda9 起始）两次 direct 顺序读，sha256 相同（cb64a630…）；吞吐约 156 MB/s（QD1，1 MiB 块，未接 interconnect/ICE，只是下限，不是链路上限）。
- 写入未验证（没有可安全写入的分区；等重分区后在新分区上测），所以“UFS 完全可用”目前只到只读+链路层。
