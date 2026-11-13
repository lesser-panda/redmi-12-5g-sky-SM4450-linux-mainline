# 从你自己的手机提取专有文件

内核需要属于小米、高通等公司的二进制固件。它们**不在**本仓库里，也不能公开发布。`tools/extract-vendor-files.sh` 从你已经拥有的两个来源收集它们：

1. **PixelOS ROM 压缩包** `PixelOS_sky-14.0-20240922-0137.zip`（sha256 `f37e76809187646b24408fda323f8f11851d347f30969fc17d295b19bc8e3b48`，来自 PixelOS 的 `sky` 下载页）。脚本用 `payload-dumper-go` 解包，取出 `vendor_boot.img`、`dtbo.img`、`recovery.img` 以及 `vendor.img` 里的 `/firmware` 目录。
2. **手机自己的 `modem_a` 与 `bluetooth_a` 分区**，里面是你这台机器的 ADSP、WiFi 处理器、WiFi 校准和蓝牙固件（ROM 里没有）。用 `--from-phone` 读取（需要 root，如 Magisk；脚本只读），或用 `--modem` / `--bluetooth` 传入之前做好的转储。

```sh
tools/extract-vendor-files.sh --rom PixelOS_sky-14.0-20240922-0137.zip --from-phone
# 或者用现成转储
tools/extract-vendor-files.sh --rom ... --modem modem_a.img --bluetooth bluetooth_a.img
```

## 文件去向

| `vendor/` 下的路径 | 来源 | 用途 |
|---|---|---|
| `rom/vendor_boot.img`、`rom/dtbo.img` | ROM | `recovery_b` 启动镜像（bootloader 要求这里有 DTB blob 和 dtbo 覆盖层） |
| `rom/recovery.img` | ROM | 原厂 recovery，用来还原 `recovery_b` |
| `fw/a630_sqe.fw`、`fw/gen6_3_26_0_zap.mbn` | ROM `vendor.img:/firmware` | Adreno 613 微码与带签名的 zap shader |
| `fw/focaltech_ts_fw_.bin` | ROM `vendor.img:/firmware` | FT8720 触摸控制器固件（驱动每次复位后下载） |
| `fw/fs1599.fsm` | ROM `vendor.img:/firmware` | FS1599 扬声器功放预设，内置进内核镜像 |
| `fw/modem/adsp.*` | `modem_a` | ADSP remoteproc（音频、电池、USB-C） |
| `fw/modem/adrastea/*` | `modem_a` | WiFi 处理器（`wpss.*`）、`regdb.bin`、WiFi 板级数据 `bdwlan*` |
| `fw/bt/*` | `bluetooth_a` | 蓝牙固件与 NVM |

每个文件都与 [tools/vendor-files.sha256](../../tools/vendor-files.sha256)（项目测试时用的文件哈希）比对。不一致会报告但不致命（别的固件版本可能能用，也可能不能）。ROM 的哈希是严格检查的。

## 先备份你的手机

动手之前，把启动链分区和 GPT 头从手机拷出来（只读，在带 root 的 Android 里）：两个槽的 `boot`、`vendor_boot`、`dtbo`、`recovery`、`vbmeta*`，以及 `modem`、`bluetooth`、`persist`、`modemst1/2`、`fsg`、`fsc`，还有 `sda` 的首尾各 1 MiB（GPT）。持久安装会给 `sda` 重分区，这些 GPT 备份是让你能把旧分区表写回去的依据。实验笔记 E003 记录了备份了什么、怎么校验（设备端哈希等于主机端哈希）。
音频拓扑固件**不是**专有文件：它由 `tools/build-topology.sh` 从上游源码构建。
