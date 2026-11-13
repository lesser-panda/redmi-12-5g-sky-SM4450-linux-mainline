# 恢复材料与备份路径

## 已取得的材料（2026-11-09）

用户下载并校验 ROM，本会话独立 SHA-256 复核通过：
`private/rom/PixelOS_sky-14.0-20240922-0137.zip`
`f37e76809187646b24408fda323f8f11851d347f30969fc17d295b19bc8e3b48`

OTA metadata 的 product=sky, skyin、incremental=eng.celest.20240922.033554、安全补丁=2024-09-05 与已采集设备信息匹配。包内 kernel 的完整版本及构建时间也与当前运行内核一致。
这是匹配版本的恢复材料，不是从本机读取的分区备份；尚未验证恢复演练，不能声称本机镜像逐字节相同。

## 提取与验证

工具：payload-dumper-go 官方 2.1.0 Linux amd64，sources/payload-dumper-go-2.1.0/。
发布包 SHA-256：bbbb53a71955c69272afdef7bc7e83a1bb1770f453d0c21dcaf61a3ba0463c11，与官方 checksums.txt 一致。
来源：https://github.com/ssut/payload-dumper-go/releases/tag/2.1.0 （Apache-2.0，许可证随工具保留）。
提取时保持工具默认 operation/final image hash 校验，未使用 -no-verify，进程成功退出。

```
sources/payload-dumper-go-2.1.0/payload-dumper-go -p boot,vendor_boot,dtbo,recovery,vbmeta,vbmeta_system -o private/rom/extracted private/rom/PixelOS_sky-14.0-20240922-0137.zip
```

| 镜像 | 文件长度 | 结构 |
|---|---:|---|
| boot | 96 MiB | Android header v4；kernel 40090112 B；ramdisk 1783176 B |
| vendor_boot | 96 MiB | vendor header v4；DTB 413007 B；含 vendor ramdisk 与 bootconfig |
| recovery | 100 MiB | Android header v4；kernel_size=0；ramdisk 18159941 B |
| dtbo | 23 MiB | 带 AVB footer 的 DTBO 镜像 |
| vbmeta | 8192 B | SHA256_RSA4096；Flags=3；含 boot/dtbo/vendor_boot hash descriptor |
| vbmeta_system | 4096 B | 已提取，详情见 AVB 解析 |

每个镜像哈希：private/rom/extracted/SHA256SUMS（在该目录运行 sha256sum -c SHA256SUMS）。
头部与组件：private/rom/unpacked/{boot,vendor_boot,recovery}/。
AVB 结构：private/rom/extracted/*.avb.txt。结构解析并不等于设备侧验签或恢复成功。

## recovery 的限制

离线读取 ramdisk（tools/inspect-recovery.py；无执行包内程序）：包含 adbd、sh 和 root service stanza，但 prop.default 为 ro.secure=1、ro.adb.secure=1、ro.debuggable=0，adbd 默认 disabled。不能据此保证 recovery 下可直接获得 root ADB shell。
recovery 不含内核；不能把单个 recovery.img 当作已验证可 fastboot boot 的自包含镜像。
因此当前不盲目重启 recovery：需要先准备能够只读取分区、具有可用 ADB 与回退机制的临时启动方案。

## 下一步与边界

唯一下一步：评估 sky 的临时 recovery/启动镜像方案，优先复用已验证实现，明确 Android v4 的 kernel/vendor_boot/recovery 组合与 ABL 的 RAM 启动限制。
满足启动前提后才请求新的上机重启授权。首次备份建议覆盖启动镜像集的两个槽、GPT 与恢复所需本机唯一分区；具体范围与存储量先给用户审阅，不采集 userdata 内容。
既有 Android 和数据继续保留，不使用 format、unlock、flash、set_active 或 OTA sideload。本文件不是刷写操作清单。
