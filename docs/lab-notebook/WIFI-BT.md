# WiFi / 蓝牙（WCN6750 "adrastea"）调查

日期：2026-11-10。**只做离线调查与离线准备，未上机**（调查开始时手机已挂死，主机侧 adb/ping/fastboot 均无响应）。
证据标签：[本机] 本机文件/备份/运行时 DT 核对；[第三方] sky-linux 项目（同机型，别人在设备上实测，我没复现）；[源码] 上游或 ROCKNIX 源码；[推测] 未验证。

## 结论（先看这里）
1. **WiFi 芯片是 WCN6750（高通内部名 adrastea，SNOC 总线，不是 PCIe），运行在 WPSS 子系统上。** 厂商固件在本机 `modem_a` 备份里（`image/adrastea/`：wpss 分段镜像、`regdb.bin`、127 个 `bdwlan*` 板级数据文件）。[本机] 芯片身份由 sky-linux 在设备上做 QMI 查询得到（chip_id 0x4130，chip_family 0x4007，固件 `CI_WLAN.HL.3.4.3-00346.1`）。[第三方]
2. **主线 ath11k 在这台机器上走不通**（sky-linux 2026-11-02 结论）：SNOC 版 adrastea 固件下，APSS 只能访问 SR_APSS 段（membase+0x20000..0x52000）和 12 个 CE 影子槽；CE 环基址/大小、UMAC/WBM/REO/TCL 寄存器不可达，ath11k“主机配环”模型无法工作。固件对主线需要的 `QMI_WLANFW_DEVICE_INFO` 回 `NOT_SUPPORTED(94)`。[第三方，代码级分析未复核]
3. **可用的路线 = 厂商 qcacld-3.0 + icnss2 移植到 7.3**（sky-linux 的 `sky-qcacld-3.0-mainline`）：已报告 WPA2 关联、DHCP、ping 通；剩余问题是断开连接时 SSR 恢复失败，且体量很大（树外下游驱动）。[第三方，未在本机复现]
4. **蓝牙 = WCN3950 级（高通 HAL 称 "cherokee"），UART 接 `serial@988000`，主线驱动已有**（本机 Android 日志实测，见“Android 在线核对”）：HAL 读到 Product ID 0x0f、SOC version 0x40070130、ROM 0x0103，下载 `cmbtfw13.tlv` + `cmnv13_cn.bin`——正是 `bluetooth_a` 里的文件；本树的 hci_qca/btqca（含 ROCKNIX 0046–0048 的 WCN3950 支持）对 `qcom,wcn3950-bt` 请求 `qca/cmbtfw%02x.tlv` + `qca/cmnv%02x{,s,t}.bin`，rom_ver 算出 0x13，完全吻合。供电与 swctrl 引脚（gpio56）与 ROCKNIX RG55G1 的 `wcn3950-pmu` 逐项相同。**sky-linux 的“WCN6750 BT”假设被推翻。**
5. **WiFi** 的前提是 WPSS 能作为 remoteproc 起来（IPCC、AOSS QMP、SMP2P、PAS、固件）。这一步完全在主线内核里，现在已离线准备成 **m12 候选**（不含 WiFi 驱动）。

## 结果（2026-11-10 晚，m13 上机，E015）
- **蓝牙配对已通过（用户在桌面 blueman 中与另一台手机配对，SSP 数字比较，bluetoothctl 显示 Paired/Bonded，E015 补充）。用法：`M=m13 RENDERER=gl tools/desktop-up.sh`，blueman 自动打开。**
- **蓝牙在主线上可用（本机验证）**：hci_qca 的 `qcom,wcn3950-bt` 路径、bluetooth_a 的 cmbtfw13.tlv + cmnv13.bin、ROCKNIX 形状的 DT；`btmgmt` 能上电、扫描（LE + BR/EDR）。未测：配对、连接、音频（需要 bluetoothd/PipeWire，且音频还缺 WCD 编解码器）、长时间稳定性、功耗。
- 已知问题：启动时第一次上电间歇性无应答（见 EXPERIMENT-006 E015）；恢复方法是重绑 serdev：`echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/unbind; echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/bind`。
- 经验：geni UART 必须有 `serial` 别名（否则 `Invalid line -19`）；L23B 同时供 USB2 PHY，必须 always-on；btmgmt 的 `find` 需要先 `le on`。

## 实用性判断
- **蓝牙反而更便宜**：不依赖 WPSS，主线驱动已具备，固件已在手，DT 可近乎照抄 ROCKNIX RG55G1；建议排在 m12 之前或并行（m13）。
- 对“手机上跑桌面”来说，USB 网络已经有了；WiFi 的价值是脱线使用，成本是整套下游驱动。建议路线：先 m12 把 WPSS 与 QMI 服务打通（便宜、验证平台前提），再决定是否引入 sky-qcacld（GPL/ISC 混合，第三方，需保留许可与作者）。BT 要先弄清芯片再谈。
- 没有 WiFi 时，用户可见的最大缺口是联网（目前靠主机 USB NCM）。

## 本机证据

### 固件（来自本机自己的备份，哈希核对一致）
- `private/backup-unique-20261109T142656Z/modem_a.img`、`bluetooth_a.img`，`SHA256SUMS` 校验 OK（2026-11-10 复核）。
- 提取到 `private/wifi/fw/`（WPSS：`wpss.mdt`、`wpss.b00–b08`、`b10`，`regdb.bin`，`bdwlan*`）和 `private/wifi/bt/image/`（30 个文件）。哈希：`private/wifi/SHA256SUMS-wpss`、`SHA256SUMS-bt`。**私有，不提交。**
- 没有 `wlanmdsp.mbn`（那是 WCN3990 的 ath10k 路线），印证不是 WCN3990 WiFi。[本机]
- BDF 选择：sky-linux 在原厂日版 ROM 下用的是 `bdwlant_jp.bin`（由 DT 的 project-info 决定）。[第三方] 本机 PixelOS 用哪个未知；后面上机若走 qcacld，需要决定（`bdwlan.bin` 通用版 vs 区域版）。

### 运行时 DT（PixelOS 在跑，`private/runtime-20261109T142413Z/runtime.dts`）
- WPSS remoteproc：`remoteproc-wpss@8a00000`，compatible `qcom,ravelin-wpss-pas`，`firmware-name = "adrastea/wpss.mdt"`，cx/mx 两路供电，`qcom,qmp`，smp2p 中断，glink-edge 用 **smem 传输**、ipcc 客户端 24（WPSS）信号 0，IPCRTR 通道。保留内存 `wpss_moselle_region@85300000` 大小 0x1900000，与 m8+ 的保留区一致。
- IPCC `ed18000`（SPI 229）、AOSS QMP `c300000`（客户端 0 信号 0）、`smp2p-wpss`（smem 617/616，remote-pid 13，客户端 24 信号 2）：与 ROCKNIX 的 RG55G1 DTS 逐项一致，因此 ROCKNIX 的节点可直接作为 m12 的来源。
- WiFi 相关节点（`qcom,wcn6750` icnss2、`qcom,cnss-qca6490`）在这份运行时 DT 里全是 `status = "disabled"`，且**没有** `qcom,icnss@22800000`。蓝牙有 `bt_wcn3990`（无 status，即启用）、`bt_qca6490`（disabled）、`bt_wcn6750`（disabled）。

### 修正：上面那份 runtime.dts 是基础 DTB（/sys/fdt），不含覆盖层
`private/runtime-20261109T142413Z/runtime.dts` 来自 `/sys/firmware/fdt`，是 bootloader 合并覆盖层**之前**的基础 DTB，所以 WiFi 节点全是 disabled。内核实际使用的树在 `/sys/firmware/devicetree/base`，含覆盖层。以后取运行时 DT 应两份都取。（我最初把这当成“矛盾证据”，是错的；在线核对后已澄清。）

### Android 在线核对（2026-11-10 17:00–17:45 UTC，只读 adb+su，serial 已脱敏；输出：private/wifi/android/readonly*.txt）[本机]
手机已恢复到 Android（AC 供电，电量 100%）。
- **活动 DT**（`/sys/firmware/devicetree/base/soc`）：`qcom,icnss@22800000` 启用（compatible `qcom,icnss`）；`qcom,wcn6750`（PCIe 型）、`qcom,cnss-qca6490`、`bt_wcn6750`、`bt_qca6490` 均 disabled；`bt_wcn3990`（compatible `qcom,wcn3990`）启用；`remoteproc-wpss@8a00000` 的 firmware-name = `adrastea/wpss.mdt`。
- **WiFi 实际在跑**：Android 加载 `icnss2.ko` + `qca_cld3_adrastea.ko`（驱动 v2.0.9.17N，`vendor.wlan.firmware.version = FW:3.4.3.0.346.0`，`wlan.driver.status = ok`，`wlan0` 存在）；`qca_cld3_qca6750/6490` 加载失败（无关）。remoteproc：adsp、mss、wpss 均 running。**WPSS 由内核直接从 `adrastea/wpss.mdt` 拉起（vendor 的 qcom_q6v5_pas），与 m12 的做法一致**；固件通过 ueventd 的 sysfs fallback 加载 `wpss.mdt/b01/b10…`。固件 build 346 与 sky-linux 报告一致，**第三方“WCN6750 adrastea / icnss2 / qcacld”结论得到本机印证**（ath11k 不可行的结论仍未复核）。
- **蓝牙**：`btpower.ko` + `bt_fm_slim.ko`（btfm slimbus，`217:221`）；`vendor.qcom.bluetooth.soc = cherokee`；HAL 打开 `/dev/ttyHS0`（sysfs 路径 `/sys/devices/platform/soc/988000.qcom,qup_uart`，即 uart2/SE2），HW 流控，115200 起步；`PatchVerReq`: Product ID 0x0f，Patch 0x0001，ROM build 0x0103，SOC version 0x40070130；按板号 `S88019BP1` 选区域 NVM `cmnv13_cn.bin`（原名 `cmnv13.bin`），补丁 `/vendor/bt_firmware/image/cmbtfw13.tlv`（TLV 20347 B，83 段）；Android 里 `/sys/class/bluetooth` 为空是因为 HAL 走 ttyHS0 而非内核 hci。
- 蓝牙 DT：`bt_wcn3990`：swctrl 引脚 tlmm 56；供电 io = pm6450 **L21B**（1.8 V），core/rf = pm6450 **L14B**（1.15–1.3 V），pa/ch0 = pm8010 **L7E**（3.0–3.3 V），xtal = pm6450 **L23B**（1.8 V）；与 ROCKNIX RG55G1 的 `wcn3950-pmu`（vddio=l21b、vddxo=l23b、vddrf=l14b、vddch0=l7e、swctrl-gpios=tlmm 56）一致。

## 内核侧现状 [源码]
- 主线 7.3 有 `qcom,sm4450-wpss-pas`？本树里有：ROCKNIX 补丁 0003 已应用（`pas_id=6`、`crash_reason_smem=626`、`ssctl_id=0x19`、proxy PD cx/mx、`auto_boot = true`，默认 `firmware_name = "wpss.mbn"`，由 DT 的 `firmware-name` 覆盖）。`CONFIG_QCOM_SMP2P=y`、`QCOM_AOSS_QMP=y`、`QCOM_IPCC=y`、`RPMSG_QCOM_GLINK_SMEM=y`、`QCOM_SMEM=y` 已内置；`QCOM_Q6V5_PAS` 原为 `=m`（m12 改内置）。`QRTR`/`QRTR_SMD` 原未开（m12 开）。
- 运行时 DT 的 compatible 是 `qcom,ravelin-wpss-pas`（下游名）；主线名是 `qcom,sm4450-wpss-pas`，用后者。
- ROCKNIX 的 0045–0048 是 **WCN3950**（Retroid/Anbernic 掌机的 WiFi/BT 组合：ath10k + hci_qca）相关：用 SoC 序列号生成 BD_ADDR/MAC、WCN3950 识别、跳过 baudrate vendor 事件、关闭 IBS。**与本机芯片不同**，不能照搬；但它们示范了“没有 NV 地址的板子如何由序列号生成 MAC/BD_ADDR”。BD_ADDR/MAC 属私有信息，别写进公开文档。
- 重要差异：vendor 的 WPSS 镜像是**分段 mdt**（`wpss.mdt` + `wpss.b00…b10`），`qcom_mdt_load` 用 `.mdt` 文件名推导 `bNN` 名，因此 DT 的 `firmware-name` 必须以 `.mdt` 结尾（sky-linux 2.1 节同样的坑）。

## m12：WPSS 起来 + QMI 服务可见（已离线构建，**未上机**）
目标：回答“平台前提是否满足”，不带任何 WiFi 驱动。
- DTS：`tools/gen-m12-dts.py` → `dts/sm4450-xiaomi-sky-m12.dts` = m11（stage A）+ `ipcc@ed18000` + `aoss_qmp@c300000` + `smp2p-wpss` + `remoteproc@8a00000`（`qcom,sm4450-wpss-pas`，`firmware-name = "adrastea/wpss.mdt"`，`memory-region` 指向 m8+ 已保留的 `wpss-moselle@85300000`）。节点形状来自 ROCKNIX RG55G1 DTS，数值与运行时 DT 逐项核对（见上）。
- 构建：`tools/build-m12.sh`（`-e QCOM_Q6V5_PAS -e QRTR -e QRTR_SMD`）；固件 `private/wifi/fw/wpss.*` 进 initramfs 的 `/lib/firmware/adrastea/`；Alpine `qrtr`/`qrtr-libs`（`sources/dl-wifi`，tools/apk-fetch.py 验证签名）提供 `qrtr-lookup`（内核自带 QRTR 名字服务，不需要 qrtr-ns）。
- init：`initramfs-m12/init` 在 m11 基础上多一个观察循环，120 s 内每 5 s 把 remoteproc 状态、相关 dmesg、`qrtr-lookup` 输出追加到 `/tmp/wpss-obs.log`。
- 预期（来自 sky-linux 在同机型的结果，**未复现**）：`remoteproc … powering up wpss` → `Booting fw image adrastea/wpss.mdt` → `remote processor wpss is now up`，随后 `qrtr-lookup` 里出现 **service 0x45（WLFW）instance 1，node 13**，以及 0xf/0x2b/0x42/0x33。
- 判据：通过 = remoteproc 状态 running，且 qrtr-lookup 里有 node 13 的 0x45。失败分类：固件加载 -ENOENT（路径/名字）；`qcom_scm_pas_init_image`/`auth_and_reset` 失败（TZ 拒绝，PAS id 不对，或 DT 的 memory-region 与 mdt 不符）；起来后随即 wdog/fatal（供电/QMP/smp2p 配错）；起来但无服务（glink/IPCRTR 配错）。
- 风险：WPSS 起/停动用 CX/MX 域与 AOSS QMP，**sky-linux 在本机型已经成功做过**（第三方证据），但我的 DT 是另一份。首次上机应有人在场，流式看 dmesg。
- 回退：cycle-boot 不写任何分区，`fastboot boot` 的 RAM 映像；init 的 420 s 定时器自动 `reboot -f`。
- 哈希、预期与回退记录在 `EXPERIMENT-006.md` 的 E014。

## 后续阶段（m12 通过后）
1. **WiFi（qcacld 路线）**：评估 `sky-qcacld-3.0-mainline`（许可、体量、对 7.3 的补丁）；需要 icnss2 的 DT（membase 0x22800000，iommu 流 0x4c0，中断列表，smp2p 的 wlan/wlan_soc_wake/wlan_ep_power_save 三项，MSA 保留区 0x82a00000）、`wlfw_*_msg_v01_ei` 符号、配置 ini（`WCNSS_qcom_cfg.ini` 必须放 `wlan/qca_cld/` 下，sky-linux 的坑 2）、`bdwlan*`/`regdb.bin`。其中“把 BDF 固件文件传输完整”是已知坑（USB 链路出错会让文件内容全零；逐文件哈希校验）。
2. **WiFi（ath11k 路线）**：不推荐，除非高通固件的行为改变。若将来要重试，先复核 sky-linux 的 APSS 孔径测量。
3. **蓝牙（m13 计划，不依赖 WPSS）**：BT 是独立的 WCN3950 级芯片，走 uart2，**不需要 WPSS/IPC 栈**，反而更容易。需要：① 启用 pm6450（L14B/L21B/L23B）与 pm8010（L7E）的 RPMh 稳压器（`&apps_rsc` regulators，ROCKNIX 补丁 0021/0022 已在树中，需核对 compatible；当前 m10–m12 只有面板固定调压器，没有这些）；② ROCKNIX 的 `wcn3950-pmu`（`pwrseq-qcom-wcn` 当前 `=m`，改内置或进 initramfs）+ `serial@988000` 的 `bluetooth { compatible = "qcom,wcn3950-bt" ... max-speed = <3200000>; }` + `qup_uart2_default/sleep` pinctrl（gpio14–17，已知形状）；③ 内核配置 `BT`、`BT_HCIUART`、`BT_HCIUART_QCA`、`BT_QCA`、`RFKILL`（本树的构建配置里目前都未设）；④ 固件 `qca/cmbtfw13.tlv`、`qca/cmnv13.bin`（及 `cmnv13s/t.bin`，mainline 按 soc_id 选 s/t 变体）取自 `bluetooth_a` 备份（哈希 private/wifi/SHA256SUMS-bt），放 rootfs/initramfs 的 `/lib/firmware/qca/`；⑤ BD_ADDR：Android 里是 NV/HAL 提供；mainline 需要 `local-bd-address` 或用 ROCKNIX 0045 的序列号法——**地址属私有**，只放 private/。风险：首次启用这些 RPMh 稳压器与 UART2 的 pinctrl；SoC 序列号补丁（0045）要审。预期：`Bluetooth: hci0: QCA controller version 0x…`，`QCA Downloading qca/cmbtfw13.tlv`，`hci0` 出现，`btmgmt`/`hcitool` 可扫描。
## 给后来移植者的通用经验
- 先分清 WiFi 的**总线类型**（SNOC vs PCIe）与**驱动路线**，同名芯片在设备树里有三种写法，指向三条互不兼容的驱动路线（参见 sky-linux 的 wifi-handoff/FINDINGS-dt-references…）。
- 不要假设 WiFi 与 BT 是同一颗组合芯片：本机 WiFi 是 WCN6750（WPSS 上），BT 是独立的 WCN3950 级 UART 芯片。先在**在线的原厂系统**里读 HAL/驱动日志（芯片 ID、ROM 版本、实际下载的固件名）再选主线驱动，比读 DT 或第三方笔记可靠得多。WPSS 仍应作为 WiFi 的独立里程碑先打通。
- 固件在**分区备份**里（`modem`/`bluetooth`/`persist`），OTA 镜像里往往没有。做备份时一并把它们取下来，既是恢复依据也是固件来源。
- 基础 DTB（/sys/firmware/fdt）里 disabled 的节点不等于“芯片不存在”：覆盖层（dtbo）按板号注入，要核对**实际启用**的覆盖层。
- 第三方项目的结论要标注“没复现”，并在使用前以最便宜的只读判据复核。

## 未决问题
- ~~`bdwlan*` 该用哪一个~~ 已解：qcacld/icnss2 按芯片 ID 0x130 + board_id 0xff 自选 `adrastea/bdwlanu_cn.bin`（E016 运行 1，本机验证）。
- ~~路线取舍~~ 已解：qcacld+icnss2 路线在本机工作（E016）；ath11k 不可行的结论仍是第三方的，未复核，也不再需要。
- BT 的 BD_ADDR 来源与 `cmnv13*` 变体（s/t/_cn）是否影响射频性能。
- 同一颗 SoC 上 BT 有独立芯片（WCN3950 级）而 WiFi 是 WCN6750，二者不共用电源轨——之前“WiFi 与 BT 共用 WPSS/电源轨”的说法对本机不成立（已在下方通用经验里更正）。


## 结果：WiFi 在主线上可用（2026-11-10 晚，E016，本机验证）
m14 = m13 + WPSS 远端处理器 + IPCC/AOSS/SMP2P + qcom,icnss 节点 + TLMM 保留引脚 + IIO；out-of-tree 模块 cnss_utils/wlan_firmware_service/icnss2/wlan（sky-qcacld，fw-api@MiCode 02e10575）。扫描、WPA2 连接、DHCP、公网 ping/下载通过，96 Mbit/s 链路（2.4 GHz）。步骤和坑见 EXPERIMENT-006 E016。
