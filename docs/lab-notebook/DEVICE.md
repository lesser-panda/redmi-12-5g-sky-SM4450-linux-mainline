# 本机证据

采集：2026-11-09，Android 正常运行、USB ADB shell uid=2000；工具 tools/collect-device.sh。
原始证据：private/20261109T104149Z-android/，目录内含命令、退出状态和 SHA256SUMS。
未读取启动镜像，镜像哈希及完整源码提交未知。

| 项目 | 实测 |
|---|---|
| 型号 / product | 23076RN4BI / sky |
| SoC | ro.soc.model=SM4450；soc_id=568；machine=RAVELIN；revision=1.0；platform=parrot |
| 系统 | Android 14；build fingerprint 日期 20240922；安全补丁 2024-09-05 |
| 内核 | 5.10.218-AtomX-gki-android12-9-g125f50a5cae7-dirty；2024-06-19 构建 |
| 内存 | MemTotal 7616784 kB |
| 当前槽 | Android 属性 _b |
| 电池 | 60%，27°C，服务报告正在充电；计数值异常，不作为容量依据 |
| 启动分区 | boot/vendor_boot/dtbo/recovery/vbmeta 均有 a/b；有 super；列表未见 init_boot |
| 解锁状态 | Android 属性 locked/green/flash.locked=1，与用户陈述冲突；需 Fastboot 核验，可能为 ROM 属性修改，尚无证明 |
| 访问限制 | /proc/cmdline、/proc/bootconfig、FDT、DT model/compatible、input devices 均 Permission denied |

本次未取得 root、分区备份、运行时 DT 或实际启动镜像。分区名称可见不等于内容可读。旧系统安装日期不能作为恢复包版本依据。

## Bootloader 侧核验（E001）

证据：private/20261109T104300Z-fastboot/transcript.txt。
`oem device-info` 报告 Device unlocked=true、Device critical unlocked=true；bootloader 已解锁。
Android 的 locked 属性与此不一致，实际操作以 bootloader 证据为准；属性不一致的具体来源尚未调查。
槽位数 2；is-userspace=no，确认为 bootloader Fastboot。
boot_a=128 MiB，vendor_boot_a=96 MiB，dtbo_a=24 MiB；max-download-size=354789376 字节。
这些是分区容量，不是实际镜像长度或格式。未更改槽位或写入分区。

## Root 后补充（2026-11-09）
- Magisk 31.1 运行，su uid=0。cmdline 见 private/runtime-20261109T142413Z/runtime.dts：console=ttyMSM0,115200n8，mem=6249512960B，bootconfig，init=/init，kvm-arm.mode=protected。
- 运行时 DT：model "Qualcomm Technologies, Inc. Ravelin QRD"，compatible qcom,ravelin-qrd/qcom,ravelin/qcom,qrd。
- 存储：UFS（1d84000.ufshc），sdhci 7c4000/8804000；分区 /dev/block/by-name（abl_a/b、boot、dtbo、modem、persist、modemst1/2、fsg、fsc 等，均为 a/b 与 sda…sdf 映射）。
- 显示：DSI，面板 m19_42_03_0b_fhd_dsc_vid（DSC，命令来自原厂 DT）。背光 panel0-backlight。触摸：focaltech/novatek-ts-spi，reset gpio 0x0c、irq gpio 0x0d。
