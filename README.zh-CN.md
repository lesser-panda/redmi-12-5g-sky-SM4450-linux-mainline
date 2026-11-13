# 在 Redmi 12 5G（sky，SM4450）上运行主线 Linux

[English](README.md) | 简体中文

在 **Redmi 12 5G**（`sky`，型号 23076RN4BI，骁龙 4 Gen 2 / SM4450）上运行 Debian 13 + GNOME（Wayland）桌面，使用**主线 Linux 7.3 内核**，从手机自己的存储启动，Android 仍然保留在旁边。内核是原版 Linux 7.3 加一组很小、有文档的补丁；其余（设备树、initramfs、启动镜像工具、根文件系统脚本）都在本仓库里。

> **状态：它能当作口袋里的 Linux 电脑用；还不是手机。** 显示、触摸、GPU、WiFi、蓝牙、音频、电池/充电、休眠和 USB（设备、主机、DisplayLink 坞）可用。蜂窝（通话、短信、移动数据）、摄像头、传感器和 GPS 不可用。详见 [docs/zh-CN/STATUS.md](docs/zh-CN/STATUS.md)。

## 你得到什么

| | |
|---|---|
| 内核 | Linux 7.3 + [kernel/patches](kernel/patches) 里的 8 个补丁，配置在 [kernel/sky_defconfig](kernel/sky_defconfig) |
| 设备树 | [dts/sm4450-xiaomi-sky.dts](dts/sm4450-xiaomi-sky.dts) |
| 启动 | Android 启动镜像（shim + 内核 + initramfs）。可用 `fastboot boot` 从内存试（不写任何东西），也可写进 `recovery_b` 分区实现免主机启动 |
| 用户态 | Debian trixie arm64、GNOME Wayland、Mesa freedreno/turnip、PipeWire、NetworkManager |
| Android | 仍装在 B 槽；`adb reboot recovery` 启动 Linux，普通重启启动 Android |
| 文档 | 中英文在 [docs/](docs)，完整实验笔记在 [docs/lab-notebook](docs/lab-notebook) |

## 适合我吗？

你需要一台**已解锁 bootloader 的 Redmi 12 5G（23076RN4BI / sky）**、一台 Linux 电脑，以及 B 槽上测试过的 PixelOS 14 版本（`PixelOS_sky-14.0-20240922-0137`）。其他版本和其他 sky 变体（日版、4 GB 版）的分区布局和固件可能不同；脚本会校验哈希，不吻合就停下。

**风险，直说：** 内存启动是安全的（断电重启就回到 Android）。写入 `recovery_b` 只写一个分区，可用 `fastboot` 恢复。持久根需要**新的分区布局，会清除全部 Android 数据**。不提供任何担保，设备由你自己负责。请先读 [docs/zh-CN/RECOVERY.md](docs/zh-CN/RECOVERY.md)。

## 快速开始（内存启动，不写任何东西）

```sh
git clone git@github.com:lesser-panda/redmi-12-5g-sky-SM4450-linux-mainline.git && cd redmi-12-5g-sky-SM4450-linux-mainline
tools/fetch-sources.sh                       # 内核源码包、工具链、shim ...（哈希固定）
tools/extract-vendor-files.sh --rom PixelOS_sky-14.0-20240922-0137.zip --from-phone   # 你自己的固件，留在 vendor/
tools/build-kernel.sh                        # 约 10–30 分钟
adb reboot bootloader && tools/boot-ram.sh   # 手机从内存启动 Linux；ssh root@192.168.7.1
```

完整流程、前提条件和预期现象：[docs/zh-CN/BUILDING.md](docs/zh-CN/BUILDING.md)。安装到存储：[docs/zh-CN/INSTALLING.md](docs/zh-CN/INSTALLING.md)。

## 本仓库里没有什么

专有文件**绝不**在这里分发：固件（GPU、触摸、WiFi、ADSP、蓝牙）、扬声器功放预设、厂商 DisplayLink 驱动、Android 镜像。你从自己的手机和已有的 ROM 里提取它们（[docs/zh-CN/EXTRACTING-VENDOR-FILES.md](docs/zh-CN/EXTRACTING-VENDOR-FILES.md)）；期望的哈希在 [tools/vendor-files.sha256](tools/vendor-files.sha256)。

## 仓库地图

```
kernel/          针对 Linux 7.3 的补丁序列、defconfig、带署名的第三方补丁副本
dts/             板级设备树
initramfs/       init 脚本（USB gadget、ssh、保险重启、autoroot、switch-root 钩子）
tools/           抓取、提取、构建、启动、刷写；根文件系统构建与安装脚本；压力测试
rootfs/          装进 Debian 根的文件（UCM 音频配置、服务、GNOME 默认值、DisplayLink 胶水）
docs/en, docs/zh-CN    文档
docs/lab-notebook      原始实验记录（E001–E034），带日期，失败也保留
LICENSES/        许可证文本
```

## 致谢

本工作建立在 [ROCKNIX](https://github.com/ROCKNIX/distribution)（SM4450 内核补丁队列）、[orange200213/sky-linux](https://github.com/orange200213/sky-linux)（shim 启动方法与 sky 的首次 bring-up）以及 Linux、Mesa、Debian、linux-msm 社区之上。见 [docs/zh-CN/CREDITS.md](docs/zh-CN/CREDITS.md) 和 [kernel/third-party/README.md](kernel/third-party/README.md)。

## 许可证

内核补丁与驱动：GPL-2.0-only（设备树保留各自的 SPDX 标签，多数为 BSD-3-Clause）。脚本、rootfs 文件和文档：MIT。第三方部分保留各自许可证。以逐文件的 SPDX 标签为准。与小米、高通、Debian、PixelOS 项目无隶属或背书关系；产品名仅用于标识硬件。
