# E005：USB gadget 串口 shell（里程碑 2）

状态：候选已构建，**待用户确认上机**。方式与 E004 相同（fastboot boot，不写分区）。

## 目的
主线内核从 RAM 启动后，通过 USB 2.0 peripheral 枚举为 CDC ACM，主机得到 /dev/ttyACM*，能在设备上执行命令（dmesg、cat /proc/*、ls /sys），为后续取证和调试提供不依赖屏幕的通道。

## 输入（out/candidates/m2/SHA256SUMS）
| 文件 | SHA-256 |
|---|---|
| sky-m2-shim-boot-v4.img（38510592 B） | fae018bf14086a7010be9a00d7f922d5a6f83a273f16ee77e94e511e8f4a7352 |
| Image | ed434464790696896a5189c4b386366eb2c8f4ac0d9e832f3314e3dd566886f9 |
| sky-m2.dtb（dts/sm4450-xiaomi-sky-m2.dts） | 64bc44ca1998ff84581c1c3929aa83d9c424c217a53b53b34f1db5b58b82b8d8 |
内核补丁、配置、shim 同 E004。initramfs：Alpine busybox-static 1.37.0-r31（HTTPS 取自 dl-cdn.alpinelinux.org，包大小与 APKINDEX 的 S 一致，控制段 SHA-1 与 APKINDEX 的 C 一致；未验证 APKINDEX 签名；二进制 sha256 999cb969…）+ initramfs-m2/init。复现：tools/build-m2.sh。

## DTS 增量（相对 m1）
USB：dwc3 @a600000 + HS PHY @88e3000，peripheral，maximum-speed=high-speed。寄存器、中断（SPI133、PDC 14/15/17）、SMMU stream 0x540（未使用）、dma-coherent、high-speed 与本机运行时 DT 一致；时钟/复位/GDSC 编号和 PHY compatible 取自 ROCKNIX（社区，本机未验证）。省略：电源 supply（保持 ABL 状态）、interconnect、iommus（假设 ABL 留下 bypass）、QMP SS PHY、PHY 调参（本机下游有 param-override-seq 66@6c 0a@70 1c@74，未翻译）。这些省略都是可证伪的假设：若 UDC 不出现或枚举失败，按此顺序排查。

## 预期与判据
通过：屏幕出现 `gadget bound to a600000.usb`，主机出现 1d6b:0104 设备和 /dev/ttyACM*，`tools/acm-console.py 'uname -a' 'dmesg | tail'` 返回内容。
部分：屏幕显示 UDC 但主机看不到设备 → PHY/供电/调参；屏幕显示 NO UDC → dwc3 未绑定（看 dmesg 行，已打印在屏幕上）。
失败：内核在 USB 探测处挂死/重启 → 回退 m1 镜像并去掉 USB 节点。
超时：15 分钟自动 reboot -f，回到 B 槽 Android；/tmp/stay 文件延长一轮；ACM 上 `reboot -f` 可立即回退。

## 回退与风险
同 E004：不 flash、不 set_active、不改 vbmeta。卡死则长按电源 10–15 秒。电量上机前再读。新增风险：USB 控制器被主线重新初始化，若与 ABL 遗留的 SMMU/电源状态不一致可能挂死（屏幕会停在最后一行）。

## 主机准备
需 /dev/ttyACM* 的读写权限。一次性 udev 规则（需 sudo，用户执行）：
`echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="1d6b", ATTRS{idProduct}=="0104", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/90-sky-gadget.rules && sudo udevadm control --reload`

## 运行 1（2026-11-09，用户在场）
fastboot boot 接受（Sending 37608 KB OKAY）。屏幕：UDC 存在、gadget 已绑定，状态 `udc=not attached`；主机 lsusb 无 1d6b:0104，无 /dev/ttyACM*。即 dwc3 探测成功、UDC 注册、configfs 绑定成功，但控制器没有检测到连接。
根因假设：缺 `qcom,select-utmi-as-pipe-clk`（无 SS PHY 时核心等不到 pipe 时钟）。dwc3-qcom 在 peripheral 模式已强制 VBUS override（源码 dwc3-qcom.c:690-692），故不是 VBUS。待运行 2 验证。
注：本次主机未装 udev 规则（/etc/udev/rules.d/90-sky-gadget.rules 不存在），权限仍待处理。
证据：private/E005/。
用户补充的屏幕日志（运行 1）：`UDC list: [a600000.usb]`；`dwc3-qcom a600000.usb: failed to enable ep0out`。ep0 启用失败说明核心的端点命令超时，与"核心时钟（pipe）缺失"一致；运行 2 若仍出现该错误，则转查 PHY 复位/时钟编号、ABL 遗留的 SMMU 或 interconnect 状态。

## 运行 2（用户在场，加入 qcom,select-utmi-as-pipe-clk）
屏幕：`gadget bound to a600000.usb`，`udc=default`；另有 `gcc-sm4450 100000.clock-controller: sync_state() pending`（clk_ignore_unused 下的正常提示）。`failed to enable ep0out` 未再出现，说明时钟假设正确。
主机 journalctl -k：新出现 high-speed 设备，随后 `device descriptor read/64, error -110/-71`、`Device not responding to setup address`、`unable to enumerate USB device`。链路和 PHY（HS 握手）正常，ep0 不应答。
假设：DTS 里照抄 Android 的 `dma-coherent`，但本机 SMMU 未被主线配置，处于 ABL 遗留的 bypass，USB DMA 并不一致 → CPU 读到事件缓冲/TRB 的旧缓存行。运行 3：去掉 dma-coherent（单变量）。同时把 init 的自动重启缩短到 240 秒以便调试迭代；ACM 通后用 /tmp/stay 延长。

## 运行 3（用户在场，去掉 dma-coherent）
**USB 枚举通过**：主机出现 1d6b:0104 "Redmi 12 5G mainline m2"、cdc_acm 创建 /dev/ttyACM0（journalctl -k 16:11:57）。dma-coherent 假设成立（单变量）。
遗留：/dev/ttyACM0 为 root:dialout，无 ACL；用户用 sudo setfacl 加 ACL 时，我的 acm-console.py 因 termios.cfmakeraw 缺失（已改 tty.setraw）而失败，随后 240 秒超时重启，shell 没来得及用。init 超时恢复为 900 秒。

## 运行 4 与结果（2026-11-09）
**PASS**：主机得到 /dev/ttyACM1（1d6b:0104），gadget 状态 `configured`，在设备上执行 `uname -a`、`cat /proc/cmdline`、`dmesg` 成功（private/E005/first-shell.txt、dmesg-raw.txt）。
设备内核：Linux 7.3.0-g105ba85cba0e-dirty #6，aarch64-linux-gcc 15.2.0 构建；8 个 CPU 全部上线（PSCI 1.1，GICv3，arch_timer 19.2 MHz）；simpledrm 注册 fb0；ramoops 注册成功（Linux 侧 pstore 可用；E004 回到 Android 后读不到日志的原因仍未定位）。
touch /tmp/stay 延长计时器可用。
原因链（单变量，均已验证）：缺 qcom,select-utmi-as-pipe-clk → ep0out 启用失败；加上后链路起来但 ep0 不应答；去掉 dma-coherent 后枚举成功。本机 USB DMA 非一致（SMMU 为 ABL 遗留 bypass）。
遗留问题：
- udev uaccess 规则已装（TAGS 含 uaccess），但没给 ACL；每次重新枚举仍需 `sudo setfacl -m u:$USER:rw /dev/ttyACMn`（设备号会递增）。原因待查（logind 会话是否 active/seat）。
- PHY 三路 supply 为 dummy、无 interconnect、无 iommus、无 PHY 调参：依赖 ABL 遗留状态，已在 TECH_DEBT 登记。
