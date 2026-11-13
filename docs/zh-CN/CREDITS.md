# 致谢

- **ROCKNIX**（[github.com/ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)）：SM4450 内核补丁队列（GPU、显示、时钟、互连、remoteproc、稳压器、蓝牙、电池）。作者信息保留在 `kernel/third-party/rocknix/`。
- **orange200213 / sky-linux**（[github.com/orange200213/sky-linux](https://github.com/orange200213/sky-linux)）：sky 的首次主线 bring-up、shim 启动方法、`ktd3136` 驱动，以及原样使用的 WiFi 驱动移植。
- **Linux 内核、linux-msm、Linaro、高通** 上游开发者：`sm8450` 音频、`sc8280xp` 声卡、AudioReach 拓扑（`linux-msm/audioreach-topology`，BSD-3-Clause）、`panel-visionox-r66451`。
- **Mesa** freedreno/turnip 作者；**Debian** 与 **GNOME** 项目；**Alpine Linux**（小 initramfs 用户态）；**DisplayLink/Synaptics**（`evdi` 是 GPL-2.0，manager 二进制是专有的，不随仓库分发）。
- **PixelOS** 项目：测试用固件所在的 ROM。小米的 GPL 内核源码和手机自己的设备树被用作协议与数值的参考。部分驱动派生自下游厂商代码（例如 SM4450 互连驱动，其文件头有说明）；原版版权与 SPDX 头均保留。
- 本仓库里自己写的：面板、触摸和 FS1599 驱动，板级设备树，initramfs，脚本和文档。工作由 Andy Zhang 完成，Claude（Anthropic）作为编程助手。

如果你的贡献被用在这里但署名不准确，请开 issue。
