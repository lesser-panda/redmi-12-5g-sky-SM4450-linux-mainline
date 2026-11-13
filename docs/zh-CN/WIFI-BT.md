# WiFi 与蓝牙

## WiFi（可用，厂商驱动）
芯片是高通 **WCN6750（"adrastea"），挂在 SNOC 总线上**，不是 PCIe，运行在 **WPSS** 子系统上。主线 `ath11k` 驱动不了它：这份 SNOC 固件下应用处理器只能访问芯片寄存器的一小段窗口和 12 个 copy-engine 影子槽，而 ath11k 需要自己配置环。能用的是 sky-linux 移植到 7.3 的厂商 `qcacld-3.0` 栈（`icnss2`、`cnss_utils`、`wlan_firmware_service`、`wlan`；由 `tools/build-wifi-modules.sh` 树外构建，内核与模块必须匹配）。

内核提供的部分：作为 remoteproc 的 WPSS（`qcom,sm4450-wpss-pas`，固件 `adrastea/wpss.mdt`，分段镜像：`.mdt` 的名字很重要，`bNN` 部分由它推导）、IPCC、AOSS QMP、SMP2P、基于 SMD/glink 的 QRTR、`qcom,icnss` 节点、MSA 保留区和 TLMM 保留引脚。固件（WPSS、`regdb.bin`、板级数据 `bdwlan*`）来自你自己的 `modem_a`。结果：扫描、WPA2 关联、DHCP、上网，链路约 96 Mbit/s。

## 蓝牙（可用）
与 WiFi 不是同一颗芯片：UART2 上的 WCN3950 级控制器（`/dev/ttyHS0`，硬件流控，起始 115200 波特），主线 `hci_qca` 加几个让 WCN3950 按 WCN 家族处理的小补丁。固件 `qca/cmbtfw13.tlv` 与 NVM `qca/cmnv13*.bin` 来自你的 `bluetooth_a` 分区。控制器需要供电轨真正断开约 0.5 秒才能复位：改成电源时序保持 1 秒最短断电之前，开机后首次上电间歇性失败（之后 10/10 次冷启动通过）。
