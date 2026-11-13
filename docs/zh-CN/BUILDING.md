# 构建并从内存启动

本页构建到可启动镜像为止，并**从内存启动**。不会向手机写入任何东西。

## 需要什么

**手机：** Redmi 12 5G（23076RN4BI），bootloader 已解锁，B 槽运行 PixelOS 14 `PixelOS_sky-14.0-20240922-0137`，已开启 USB 调试；若要让脚本自己读 modem/蓝牙分区，需要 root（Magisk）。电量高于 50 %。线要好。

**主机：** x86-64 Linux，约 30 GB 空闲磁盘，首次抓取需要联网。

| 工具 | 用途 | Fedora / Debian 包 |
|---|---|---|
| gcc、make、flex、bison、bc、openssl 与 libelf 头文件、perl、cpio | 内核构建 | `gcc make flex bison bc openssl-devel elfutils-libelf-devel perl cpio` / `build-essential flex bison bc libssl-dev libelf-dev perl cpio` |
| git、curl、python3、openssl | 抓取、辅助脚本 | `git curl python3 openssl` |
| m4、alsatplg | 音频拓扑（`alsatplg` 不在 `PATH` 时用 `ALSATPLG=/path/to/alsatplg tools/build-kernel.sh`） | `m4 alsa-utils` |
| adb、fastboot、mkbootimg、unpack_bootimg | 启动镜像、与手机通信 | `android-tools` / `android-tools-adb android-tools-fastboot mkbootimg` |
| 7z、debugfs | 解固件分区 | `p7zip e2fsprogs` / `p7zip-full e2fsprogs` |

交叉编译器（kernel.org 的 GCC 15.2.0 `nolibc` 版）由抓取脚本下载。

## 步骤

```sh
# 1. 输入，哈希校验（内核源码包、工具链、sky-linux shim、音频拓扑源、payload-dumper-go）
tools/fetch-sources.sh

# 2. 你自己的专有文件（见 EXTRACTING-VENDOR-FILES.md）；留在 vendor/，永不提交
tools/extract-vendor-files.sh --rom ~/Downloads/PixelOS_sky-14.0-20240922-0137.zip --from-phone

# 3. 构建：打补丁的内核树、拓扑、initramfs、内核、设备树、启动镜像 -> out/boot/
tools/build-kernel.sh

# 4. 从内存启动（手机在 fastboot 模式）
adb reboot bootloader
tools/boot-ram.sh
ssh -i vendor/ssh/id_ed25519 root@192.168.7.1
```

`build-kernel.sh` 依次：解开 Linux 7.3 并 `git apply` `kernel/patches/` 里的补丁；构建音频拓扑；准备 initramfs（busybox、dropbear、你的 ssh 公钥、固件）；按 `kernel/sky_defconfig` 配置；构建 `Image`；编译 `dts/sm4450-xiaomi-sky.dts`；用 sky-linux 的 shim 打成 Android 启动镜像（`out/boot/sky-boot-v4.img`）；若存在 `vendor/rom/`，再生成 `recovery_b` 用的版本（`out/boot/sky-recovery_b-v2.img`，header v2，见 [ARCHITECTURE.md](ARCHITECTURE.md)）。`out/boot/SHA256SUMS` 列出结果。内核带构建时间戳，所以即使输入相同，不同次构建的哈希也不同。

## 预期现象

- 几秒后屏幕显示内核控制台；随后 USB 枚举成带串口和以太网的 gadget。
- 电脑从手机的 DHCP 服务器得到 `192.168.7.x`，手机是 `192.168.7.1`。用 `vendor/ssh/` 里的密钥登录。
- initramfs 在 7 分钟后重启手机，除非你在手机上 `touch /tmp/stay`（每次延长一小时）。这是保险：卡死不会让你无路可退。
- 没有根文件系统时进入一个小的 busybox 系统，显示、触摸、GPU、WiFi（加载模块后）、音频等都可用。完整桌面需要 [INSTALLING.md](INSTALLING.md) 里的根文件系统步骤。

## 在干净检出上验证过什么

内核补丁序列能应用到全新的 Linux 7.3 源码包，并逐文件还原出测试过的树；defconfig 精确还原测试过的 `.config`；设备树逐字节编译出测试过的 blob；音频拓扑逐字节重建。专有文件提取脚本用原 ROM 与分区转储跑过，296 个文件全部吻合。完整的 `tools/build-kernel.sh` 产物（默认选项，手机上已装 Debian 根）已从内存启动：进入 Debian，加载扬声器功放预设，显示、GPU、输入、声卡和蓝牙正常（实验笔记 E035）。仅 initramfs 的变体（`AUTOROOT=0`）能构建，但没有启动过。树外模块（`qcacld` WiFi、`evdi`）与内核构建一一绑定：自己构建内核后要重建它们（见 [KNOWN-ISSUES.md](KNOWN-ISSUES.md)），旧模块会报 "Invalid module format"。可选的根文件系统脚本（Debian 构建、WiFi 模块构建、DisplayLink）是原始安装用的脚本，尚未从干净检出重跑，请当作参考。见 [KNOWN-ISSUES.md](KNOWN-ISSUES.md)。

## 排错

| 现象 | 可能原因 |
|---|---|
| `fetch-sources.sh` 哈希不符 | 上游变了或下载被截断；删除 `sources/dl/<文件>` 重试 |
| `build-kernel.sh` 里 `git apply` 失败 | `sources/linux-7.3` 被改过；删掉让脚本重建 |
| fastboot 看不到设备 | `adb reboot bootloader`；检查线；手机应显示 fastboot 界面 |
| `fastboot boot` 成功但没有 `192.168.7.1` | 等 90 秒；看屏幕；电脑上应出现 `enx...` 接口（NetworkManager 可能要设为"共享"，或手动加 `192.168.7.2/24`） |
| 写入 `recovery_b` 后手机进 fastboot 或不进 Linux | 见 [RECOVERY.md](RECOVERY.md)；Android 槽未动，`fastboot boot out/boot/sky-boot-v4.img` 永远可用 |
