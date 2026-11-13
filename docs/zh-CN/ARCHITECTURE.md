# 怎么启动，以及为什么是这个样子

## 启动链

```
上电 -> 高通 boot ROM -> XBL -> ABL（Android bootloader，已解锁）
              |                                   |
              |                       默认：boot_b -> Android（PixelOS）
              |                       adb reboot recovery：recovery_b -> 我们的镜像
              v
        我们的启动镜像（Android boot image header v2）
              kernel   = "shim"（sky-linux）：一个很小的 arm64 程序，搬运 payload 并跳转
              payload  = Linux 7.3 Image（内置 initramfs）+ 我们的设备树
              dtb      = 手机原厂 vendor_boot 的 DTB（shim 忽略它，但 ABL 要求有一个）
              recovery_dtbo = 原厂 dtbo.img
```

- **shim。** 原厂 ABL 期望 Android 内核加厂商设备树，并自己叠加覆盖层。shim（来自 [sky-linux](https://github.com/orange200213/sky-linux)）把控制权拿回来：自带我们的设备树，把 Linux 7.3 装到 0xC0000000 然后交接。屏幕由 bootloader 保持点亮（continuous splash），所以最初几帧是固件的帧缓冲，之后才由 `msm` 驱动接管。
- **为什么用 `recovery_b` 和 header v2。** `fastboot boot` 需要电脑。要不接电脑启动，镜像得放在 bootloader 自己会加载的分区里。`recovery_b` 里带内核时，ABL 只加载 vbmeta、recovery 镜像和 dtbo 分区，**不读** `vendor_boot`。所以 header v4 的镜像没有 DTB，ABL 回落到 fastboot（"LoadImageAndAuthVB2() Not Found"）。header v2 自带 DTB（我们嵌入原厂 vendor_boot 的 DTB）。它还需要 `recovery_dtbo`：没有的话 ABL 报 dtbo header 错误，不设置 splash 区域并关掉面板，显示驱动只能冷启动面板而失败。可用的组合是 v2 + 原厂 DTB blob + 原厂 dtbo 作 `recovery_dtbo`（试了七次才成；见实验笔记 E028）。
- **Android 仍是默认。** B 槽的 `boot` 没有被修改。`adb reboot recovery` 启动 Linux，普通重启启动 Android，Linux 里 `systemctl reboot` 回 Android。A 槽未使用。
- **保险重启。** initramfs 的 `init` 在 7 分钟后重启，除非被延长，所以起来了但连不上的镜像会自己回到 Android。内置的 `autoroot` 标记让它挂载 Linux 根并 `switch_root`，同时关闭这个计时器。

## initramfs

busybox（静态）、dropbear（仅密钥 ssh）、DHCP 服务器，以及带 ACM 串口和 NCM 以太网的 USB gadget（`192.168.7.1`）。驱动早期请求的厂商固件放在这里（`/lib/firmware`）：GPU、触摸、ADSP、WiFi 处理器、蓝牙。有两个固件文件改为内置进**内核**：音频拓扑和 FS1599 功放预设（`CONFIG_EXTRA_FIRMWARE`）。原因：声卡在约 7 秒时 probe，而免主机的 `init` 在几毫秒内就切到了真正的根，此时 initramfs 里的固件已不可达，声卡报 "No soundcards found"。内置固件没有这种竞争。

## 存储布局（持久安装）

`sda` 是主 UFS LUN。安装时把 `userdata`（`sda20`，f2fs，被 Android 加密所以不能离线缩小）从约 108 GiB 缩到 40 GiB，并新增 `linuxboot`（`sda21`，1 GiB ext4，`/boot`）和 `linuxroot`（`sda22`，约 67 GiB ext4）。Android 在更小的 `userdata` 上恢复出厂状态。启动链分区在别的 LUN 上，不受影响。`init` 只在 `sda22` 的 GPT 名字是 `linuxroot` 时才挂载。

## 设备树

`dts/sm4450-xiaomi-sky.dts` 是按手机自己的运行时设备树（内存 bank、保留区、GPIO、稳压器、SMMU stream ID）和 dtbo（面板时序、DSC、初始化序列）写的板级文件。SoC 节点来自上游 `sm4450.dtsi` 加补丁。板级数值从未从别的 SM4450 设备照抄（它们不同：例如 GPU zap shader 的保留区）。

## 内核补丁序列

| 补丁 | 内容 |
|---|---|
| 0001 platform | 时钟、电源域、互连、SMMU、PAS remoteproc、RPMh 稳压器、pd-mapper、TLMM、UFS PHY、`sm4450.dtsi` |
| 0002 display | SM4450 的 DPU（含 DSC）、启动扫描输出处理 |
| 0003 gpu | Adreno 613 |
| 0004 panel-backlight | 小米 sky DSI 面板、KTD3136 背光 |
| 0005 touch-input | FocalTech FT8720 SPI 触摸驱动、edt-ft5x06 跟随电源 |
| 0006 bluetooth-wifi | WCN3950 蓝牙、电源时序最短断电时间 |
| 0007 audio | RX macro 步长修复、FS1599 功放驱动 |
| 0008 power-usb | 电池软件充电上限、dwc3-qcom 恢复修复 |
