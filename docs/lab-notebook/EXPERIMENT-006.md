# E006：DSI 面板接管（里程碑 3，m3 候选）

状态：候选已构建并离线验证编译，**未上机**，等待用户确认。

## 目的
用主线 DRM/MSM（DPU + DSI + DSI PHY）加自写面板驱动取代 ABL 留下的 simple-framebuffer，在本机面板上显示 fbcon；USB ACM shell（来自 m2）作为取证和回退观察通道。

## 输入（out/candidates/m3/SHA256SUMS）
```
71fa8614e988801ba0da6b8027c9adf6ca48aa3f970d0bba7610b23b2acc8aa4  Image
17ac19fa1b0ff0c61b37e0397e228fa5e7b208467c94feb7200ae40a78dab3d2  sky-m3.dtb
25fc7e42182a06a348ed97447ed015dfce60b4d6100f15a7d955cd0c5476593f  sky-m3-shim-boot-v4.img
```
- 内核：同 E004/E005 的补丁基线，加 ROCKNIX 0009（SM4450 显示；ubwc_config.c 手工改一行）、自写 drivers/gpu/drm/panel/panel-xiaomi-sky.c（kernel-local/ 有副本和全量 diff linux-7.3-local.diff，配置 kernel-local/sky-m3.config）。DRM_MSM/DPU/DSI/7nm DSI PHY 全部内置，关闭 MDP4/5/HDMI/DP 与旧 PHY。
- DTS：dts/sm4450-xiaomi-sky-m3.dts 由 tools/gen-m3-dts.py 生成：m2 + apps_smmu + mdss/dpu/dsi/phy（ROCKNIX，BSD-3）+ sky 面板节点与三条 GPIO 固定调压器（GPIO 11/12/127，boot-on，见 PANEL.md）+ 复位 GPIO 92。
- 省略（待补）：interconnect 带宽投票、DSI/PHY 的 RPMh 电源（保持 ABL 状态）、PHY 调参、面板 pinctrl。
- 启动参数增加 `arm-smmu.disable_bypass=0`（未知主设备放行，避免 SMMU 拦截 USB）。
- 复现：tools/build-m3.sh。

## 预期与判据
通过：屏幕经短暂闪烁/黑屏后重新显示 fbcon（企鹅/文本），主机 shell 里 `dmesg | grep -iE 'dsi|panel|dpu|msm'` 显示 DRM msm 绑定、panel 探测成功、无超时/欠载报错；`ls /sys/class/drm /sys/class/backlight` 有 card/connector 和背光。
部分：屏幕保持 simple-framebuffer 显示但 msm 未绑定（探测延期/失败）→ 日志定位缺的资源。
失败：黑屏或灰屏：看 USB shell 的 dmesg（若内核仍活）；若 USB 也失效，等 15 分钟自动重启或长按电源。

## 回退与风险
同前：fastboot boot，不写分区；15 分钟自动 reboot -f；长按电源 10–15 秒强制重启。电量上机前读。
新增风险：
- SMMU 驱动接管后，已被固件设置为 bypass 的流保持 bypass，其它未知流因 disable_bypass=0 放行；USB 仍按 m2 无 iommus 运行，若 USB 断开，记录 SMMU 日志后单变量排查。
- DSI PLL/时钟重编程会让屏幕暂时无显示，属预期；面板初始化序列来自 dtbo（0b 变体），ABL 实际选中哪个覆盖层未核实；2 字节 DCS 命令以短写类型发送（厂商为 0x39 长写），如面板不认，需改驱动发长写。
- 面板电压由 GPIO 固定调压器控制，参数取自本机运行时 DT，与厂商一致。风险低，但属首次由 Linux 驱动面板。

## 运行 1（2026-11-09，用户在场）
fastboot boot 接受；USB ACM 照常枚举（/dev/ttyACM1），shell 可读 dmesg。屏幕先正常，约 31 秒后变黑：用户报告 `display_panel_vddio: disabling`、avdd、extvdd 均被关闭。
dmesg（private/E006/dmesg-filtered.txt）：
- `platform 15000000.iommu: deferred probe pending: arm-smmu: qcom_scm not ready` —— DTS 缺 firmware/scm 节点，SMMU 无法探测。
- `msm-mdss ae00000.display-subsystem: deferred probe timeout`，10.2 s 后 `probe with driver msm-mdss failed with error -110`。
- 31.7 s regulator late cleanup 关掉三条面板轨（无消费者），所以屏幕变黑。
结论：失败发生在更早的层（SMMU 依赖 SCM），不是面板驱动本身；面板驱动尚未被探测。黑屏是副作用，不是面板被损坏。
运行 2 修改（单变量组）：加 firmware/scm 节点；三条面板轨加 regulator-always-on（调试期保险，避免再次黑屏，登记为技术债）。

## 运行 2–4（2026-11-09，用户在场，均 fastboot boot，不写分区）
- 运行 2（Image 0a75d391…，boot 4f60b369…）：加大字体成功（`scripts/config -e FONT_TER16x32` 无效的原因：它把符号名转大写，改用 sed 写 `CONFIG_FONT_TER16x32=y`）。SMMU 探测通过；msm-mdss 仍因 DISPCC 驱动是 `=m`（initramfs 无模块）而 -110。
- 运行 3（Image b770f3d5…，boot cea9fc24…）：`CONFIG_SM_DISPCC_4450=y`，dispcc 探测；mdss 仍延期（reason unknown）。原因：DTS 缺 smem 节点，`qcom_ubwc_config_get_data()` 等 SMEM 可用。
- 运行 4（Image 96b27c16…，DTB 0b8978da…，boot fdcff2e6…）：加 smem 保留区 0x80900000/2 MiB + `qcom,smem`（hwlock tcsr_mutex 3，取自运行时 DT）。结果：DPU 版本 0x80060000，DSI 绑定，msm DRM 1.13 初始化，`fb0: msmdrmfb`，DSI-1 connected 1080x2460，字体 TER16x32（67x76 字符）。dmesg 仅有 `[dpu error] INTF_1: boot scanout did not stop`，无面板/DSI 命令错误（ISR 无错误位）。
- 用户目视：字体变大，屏幕保持点亮，但整屏紫绿闪烁带噪点，文字几乎看不清。整屏填白（`/dev/fb0` 全 0xff）仍闪烁带噪点，遍及全屏 → 与画面内容无关，指向 DSI 链路/DSC 解码/DPU 取数（欠载）层，不是 fbcon。
- 寄存器取证（tools/mmio-rd.c 自由站立小程序经串口 base64 送入，/dev/mem 的 read 在 arm64 对 IO 返回 EFAULT，需 mmap；原始转储在 private/E006/run4-regdump*.txt）：INTF_1 定时已按压缩宽度（htotal 500、vtotal 2500、周期 0x1312d0）；DSC 编码器寄存器已写入（1080x2460、切片 540x20、chunk 540）；DSI 活动区 360 像素（压缩）、2460 行，总周期与之一致；时钟 pclk 112.5 MHz，byte 84.375 MHz（bit 675 MHz），esc 19.2 MHz；`interconnect_summary` 为空（无带宽投票）。
- 已排除：面板 DSC 参数与 PPS 顺序（host 在 mode_set 计算 RC 参数，早于面板 prepare）、时序（与厂商 htotal 1220/vtotal 2500 一致）。
- 未排除假设（按嫌疑排序）：(1) MDSS 到 DDR 无 interconnect 投票，DPU 欠载（underrun IRQ 未启用，未观测）；(2) DSI 链路速率零余量（byte 时钟恰好等于像素数据率，厂商用 burst 且 PHY 时序为 [00 18 06 06 15 20 06 06 07 02 04 00 15 0b]，未与 Linux 计算的 PHY 时序比对）；(3) 面板解码器与 DPU 编码器参数不一致（PPS 实际字节未抓取）；(4) ABL 的 boot scanout 未停（`did not stop`）；(5) 2 字节命令以短写发送。
- 事故：对 mmio-rd 误传 `0x100` 作为十进制计数，程序长时间读取；约 15 分钟计时器到点后手机自行 `reboot -f` 回到 Android（电量/槽位未变，仍为 B）。mmio-rd 已知不校验参数。

## 参考仓库发现与运行 5–9（2026-11-09）
- 运行 5：面板 DCS 回读正常（0x0a=0x9c，0x0f=0xc0；0xda/db/dc=80 41 00，与参考仓库的 0a 变体 c0 11 00 不同；Android cmdline 为 `msm_drm.dsi_display0=…m19_42_03_0b…`，故 0b 变体正确）。`long_writes` 切换无变化。DSI 自带测试图案（TEST_PATTERN_GEN，经 tools/mmio-wr）→ 稳定黑屏、无噪点 → 链路/PHY/面板解码稳定，噪点来自 DPU DSC 编码一侧。
- 事故：mmio-rd 读 0xae6a1c0（无效偏移）导致整机挂死，需长按电源；rd/wr 只读已确认范围。
- 参考仓库 orange200213/sky-linux（sources/sky-linux，docs/m5-display.md、docs/handoff/HANDOFF.md §0）：同一症状的根因是 `_dsc_calc_output_buf_max_addr()` 2400/num_softslice，SM4450 的 DSC 块只有 600 字节 → 应为 600/num_softslice-1=299；另需 initial_xmit_delay=170（其 0a 变体，Xiaomi lut_v1）、厂商 PHY 时序、init 用长写、NO_EOT、DSC_ALL_SLICES_IN_PKT。已在本地内核实现（均标 TECH_DEBT）：dpu_hw_dsc_1_2.c、dsi_host.c、dsi_phy_7nm.c（clk_trail 6/hs_exit 21/hs_rqst 7/clk_pre 21/clk_post 11）、dpu_encoder.c（initial_lines 厂商公式=3）。
- 运行 6（buffer 299 + xmit 170 + 长写 + 标志）：闪烁变为静态噪点。运行 7（+PHY 时序 + initial_lines=3）：ENC_DF_CTRL=04ac0203，与参考仓库“improved state”寄存器一致；用户报告仍有噪点，但能看出控制台在滚动，文字不可读。
- 重要差异：本机是 0b 变体，其面板自带 DSC 参数命令 `b4 00 14 02 00 01 e8 00 07 05 0e 05 16 10 f0` 含 xmit=0x200(512)、dec=0x1e8(488)，而 0a 变体是 xmit 170/dec 526；PPS（170/526）与面板侧寄存器（512/488）可能不一致。厂商仅对 0a 名称做 xmit=170 的特例。
- 运行 8/9：加入运行时旋钮 `/sys/module/msm/parameters/sky_xmit_delay|sky_dsc_buf_bytes|sky_initial_lines`；强制 force off/on 不重跑 DSC 配置；`unbind/bind msm-mdss` 会令整机挂死（两次事故：自引用脚本 + rebind），不要再用。每次实验需重启。

## 运行 10：成功（2026-11-09 18:08，用户在场）
候选：Image fbd58642…，DTB 1899a043…，boot ca29a427…（`msm.sky_xmit_delay=512` 经内核命令行；DSC 缓冲 600 字节→寄存器 299；initial_lines=3；厂商 PHY 时序；面板长写 + NO_EOT + DSC_ALL_SLICES_IN_PKT）。
用户目视：屏幕正常，文字可读（此前运行 7 为静态噪点，运行 4 为紫绿闪烁）。结论（本机验证）：Linux 驱动链 DPU→DSC→DSI→面板 在 0b 变体上输出正确图像。
关键因果（单变量归因不完整，列为已知）：运行 7→10 的唯一差异是 xmit 170→512（其余同运行 7，其中 initial_lines 来自厂商公式在 xmit=512 下为 (540+558+512+78+540+28)/540=4，寄存器未读出，待下次用 udev 规则后读 `rd ae81100 1`）。参考仓库的 0a 变体用 170；0b 变体自带 DDIC 命令 `b4…` 含 512，PPS 必须与之一致。
未验证：运行 10 的实际 ENC_DF_CTRL/HRD 寄存器值（串口无权限）；亮度/背光控制；休眠恢复；长时间稳定性。

## 最终（2026-11-09 18:26）：显示锁定，已消融
消融（均用户目视，同一 xmit=512/buffer 299）：
- initial_lines：厂商公式(4)、3、主线值 2 → 全部正常 ⇒ 不需要覆盖，已删除。
- 厂商 PHY 时序（clk_trail 6/hs_exit 21/hs_rqst 7/clk_pre 21/clk_post 11）开/关 → 都正常 ⇒ 不需要，已删除。
- initial_xmit_delay：0b 变体用主线默认 512（170 是参考仓库 0a 变体的特例，对 0b 反而致噪点）⇒ 覆盖已删除。
- 必需：DSC 速率缓冲 600/num_softslice-1（SM4450 DSC 块 600 字节，主线 2400），smem 节点（UBWC 配置需要 SMEM），SM_DISPCC_4450 内置，scm 节点，面板驱动（长写、NO_EOT、DSC_ALL_SLICES_IN_PKT 未单独消融，保持厂商一致）。
最终候选（out/golden/，哈希见 SHA256SUMS）：Image 73a791ba…，DTB eeb50301…，boot 5d43aca9…。寄存器：ENC_DF_CTRL=04ac0202（lines 2，buf 299），HRD=020e0200（xmit 512/dec 526）；面板 0x0a=0x9c，0x0f=0xc0；fb0=msmdrmfb；用户确认“still good”。
内核差异保存：kernel-local/linux-7.3-local.diff，配置 kernel-local/sky-m3.config，DTS kernel-local/sky-xiaomi-sky-m3.dts。

## 背光（2026-11-09 18:34，用户在场）
- 纠错：m3 DTS 把 vddio/extvdd 的 GPIO 11/12 误挂在 TLMM；运行时 DT 里它们是 PM7250B GPIO（phandle 0x511），avdd 才是 TLMM 127。TLMM 10/11 是 SE1 I2C。已把 vddio/extvdd 改为无 GPIO 的 always-on 固定调压器（沿用 ABL 遗留供电，TECH_DEBT：需要 SPMI + pm7250b-gpio 节点后才能真正控制）。此前“面板轨由 Linux 驱动”的说法对 vddio/extvdd 不成立。
- 背光：KTD3136 在 QUP wrapper0 SE1 I2C（0x984000，gpio10/11）地址 0x36；HWEN 为 PM6450 GPIO6（无 SPMI 节点，保持 ABL 状态）。导入 sky-linux 的 ktd3136.c（Kconfig/Makefile/内置），DT 新增 wrapper0、i2c1、backlight@36。启动：`geni_i2c 984000.i2c`、`ktd3136 0-0036: id=0x01, treating as LM3697`、`probed brightness=1024`；/sys/class/backlight/ktd3136-backlight max=2047。
- 用户目视：150 偏暗但不很暗；10 极暗；2047 最亮；0 全黑；恢复 1024 正常。结论：亮度控制工作（本机验证）。面板自带 DCS 亮度（0x51）已从面板驱动移除（对此 LCD 无作用）。
- 未验证：休眠/唤醒后的背光；HWEN 由 Linux 控制（需要 SPMI）；亮度曲线（0–2047 线性，低亮度区非常暗）；LM3697 与 KTD3136 个体差异（本机 ID 0x01 走 LM3697 路径）。

## 背光修正（2026-11-09 18:42）
上一节的亮度读数有误：导入的 ktd3136.c 的 LM3697 分支把 11 位亮度的高低字节写反（0x23 当低 8 位、0x22 当高 3 位），实际有效码 = ((b&0xff)<<3)|((b>>8)&7)，所以 150→约 1200、10→80、1024→4（几乎全黑，用户报告“very dark”）。改为 0x22=b&7、0x23=(b>>3)&0xff（TI LM3697 BRT_A 寄存器布局）。用户确认：默认 1024 正常，100 偏暗可读，500 中间，（先前 2047 最亮、0 全黑）。golden：Image 7818b5c9…，boot deaa6ee2…。

## M4：USB 网络 RAM 根（2026-11-09，用户要求 "usb networked ram root first"）
- 输入：内核 = 黄金 m3 配置 + initramfs（out/initramfs-m4，Alpine busybox-static、busybox-extras、musl、zlib、skalibs/utmps、dropbear；apk 仅解包，未在主机执行）；DTB = 黄金 sky-m3.dtb（哈希 66a3f9b0…，未变）；启动镜像 3ff287aa…（out/candidates/m4/SHA256SUMS）。init = initramfs-m4/init。
- 预期：ACM+NCM 复合 gadget；usb0 = 192.168.7.1/24；udhcpd 给主机发 192.168.7.10–50；dropbear 仅密钥登录 root，公钥来自 private/ssh（私钥不入镜像）。
- 判据：主机出现 ttyACM 与新网卡并自动获得 IP；`ssh -i private/ssh/id_ed25519 root@192.168.7.1` 成功。
- 回退：只用 fastboot boot，不写分区；init 定时器 3600 s 后 reboot -f（touch /tmp/stay 延长）；panic=15；长按电源 10–15 s。
- 结果：待记录。
- 结果 1（启动 #1）：ACM+NCM、usb0、dropbear 监听均正常；udhcpd 报 can't bind interface usb0: Protocol not available，原因 CONFIG_PACKET 未开。已开启 CONFIG_PACKET=y 重建（config 副本 kernel-local/sky-m3.config 已更新）。
- 更正（启动 #2）：开 PACKET 后同样失败；真因是 CONFIG_NETDEVICES 未设，sock_setbindtodevice() 返回 -ENOPROTOOPT（SO_BINDTODEVICE），udhcpd 报 "Protocol not available"。已 -e NETDEVICES -e PACKET 重建。
- 结果 2（启动 #3，**通过**）：Image 9308c401…，启动镜像 6588a7c4…（快照 out/golden-m4/）。主机 NetworkManager 自动得到 192.168.7.14/24（无需 sudo）；`ssh -i private/ssh/id_ed25519 root@192.168.7.1` 成功（dropbear 仅密钥）；可用内存 451 MiB，无存储写入。本机验证。
- 已知：host key 每次启动重新生成（RAM 根），主机端用 UserKnownHostsFile=private/ssh/known_hosts + StrictHostKeyChecking=no。

## M5 调查：RAM 里的 Wayland 合成器（2026-11-09，仅离线，未动设备）
- 方法：tools/apk-closure.py 对 Alpine v3.24 main+community 的 APKINDEX 算 weston（含 drm 后端、desktop shell、terminal）的依赖闭包（只读索引，未下载包、未执行）。
- 结论：闭包拉入 mesa（12 MB apk）→ llvm22-libs（64 MB apk，解包后数倍）、pipewire、gstreamer、libcamera 等。装进 initramfs 会吃掉大部分可用 451 MiB 内存，且无 GPU 时全靠 llvmpipe。weston 14 的 libweston 对 EGL/GLES 有硬依赖，Alpine 没有 pixman-only 的拆分包。**RAM 根里跑合成器不可行/不划算。**
- 修订路线：触摸先用无依赖的小程序验证（evdev + /dev/fb0 画点，仿 mmio 工具自行编译）；桌面要等持久化 rootfs（存储方案，重分区需用户授权）和更多内存映射。

## E007 / M5：包装器 1 SPI（触摸总线）与互连投票（2026-11-09）
- 来源：厂商 DT（Android /proc/device-tree，本机验证）：四个相关互连节点 reg（clk_virt 无 reg；gem_noc 19100000/0xbc080；cnoc2 1500000/0x6200；cnoc3 1510000/0xf200）、SPI@a84000、gpio 12/13、引脚 26/27/50/51。sky-linux 触摸笔记（网页线索）。
- 假设 H1：包装器 1 的 SE 不执行命令，是因为没有 qup-core / qup-config 互连投票（Android 里 wrap1 core 时钟为 0）。
- 输入：dts/sm4450-xiaomi-sky-m5.dts（tools/gen-m5-dts.py 在 m3 之上加 clk_virt/gem_noc/cnoc2/cnoc3、wrapper 1 的 AHB 时钟更正为 WRAP_1、SE1 SPI 节点含 interconnects、spidev 子节点、TLMM12 reset hog 输出高）；内核加 SPI_QCOM_GENI=y、SPI_SPIDEV=y；initramfs 加 /bin/spi-xfer（tools/spi-xfer.c）与 /bin/rd。候选 out/candidates/m5/SHA256SUMS（Image a89d724f…，DTB 4f3c661f…，镜像 f0d0f6ca…）。
- 预期：互连提供者与 spi_geni 探测成功，出现 /dev/spidev0.0；`spi-xfer /dev/spidev0.0 9f 00 00 00` 能完成并打印 rx（内容不重要，重点是不超时）。
- 判据：通过 = 传输完成；失败 = 超时（-110）或 SE_GENI_STATUS 仍恒 0 → H1 不成立，转查 H2/时钟/固件。
- 风险：新增 NoC 探测或 sync_state 可能丢掉引导加载器的显存带宽投票致屏幕异常；TLMM12 hog 可能触碰受保护 GPIO。
- 回退：fastboot boot（不写分区）；3600 s 计时回 Android；panic=15；长按电源 10–15 s。启动前电量 100%。
- 结果：待记录。
- 结果（M5，启动于 19:46，本机验证）：互连提供者（clk_virt/gem_noc/cnoc2/cnoc3）全部探测成功；SE 持有 qup-core/qup-config 路径，活动时 config 路径投票 1000 kB/s（debugfs interconnect_summary）。但 `spi-xfer /dev/spidev0.0 9f 00 00 00` 仍 -110 超时（dmesg: "spidev spi0.0: SPI transfer timed out"）。**H1（缺互连投票）不是充分解释。**
- **根因线索（寄存器对比，private/touch/se-regs-m5.txt 与 se-regs-i2c-ref.txt）**：SE_FIFO_IF_DISABLE_RO（偏移 0x64）：SPI SE（wrapper 1 SE1，a84000）= 1，正常工作的 I2C SE（wrapper 0 SE1，984000）= 0。该 SE 的 FIFO 接口被硬件禁用，只能用 GPI DMA；我们的 DTS 没有 gpi_dma 节点，驱动打印 "FIFO mode disabled, but couldn't get DMA, fall back to FIFO mode"（dmesg），回退的 FIFO 模式必然不执行。sky-linux 同样缺 gpi_dma，其“命令被接受却不执行”即此原因。FW 版本寄存器 0x68：SPI=0x102，I2C=0x303。
- 下一步：取厂商 DT 的 gpi_dma1（phandle 0x1c1）reg/中断/ee/gpii 掩码，加入 DTS，SE 节点加 dmas/dma-names，内核开 QCOM_GPI_DMA=y，重试。

### E007 运行 2：加 GPI DMA（2026-11-09）
- 来源：厂商 DT qcom,gpi-dma@a00000（reg a00000/0x60000，中断 GIC SPI 279–284、293–298，ee-offset 0x10000，gpii-mask 0x3f，iommus smmu 0x416，dma-cells 5；本机 /proc/device-tree，private/touch/dt-gpi.txt）。
- 输入：DTS m5 加 gpi_dma1（compatible qcom,sm6350-gpi-dma）与 SE 的 dmas/dma-names；内核 QCOM_GPI_DMA=y。候选 Image d0e07078…，DTB 130cd5c8…，镜像 3e383843…。
- 预期：spi_geni 不再打印 "FIFO mode disabled…"，spi-xfer 的传输完成并回显 rx。
- 判据：通过 = 传输完成；失败 = 仍超时或 GPI/SMMU 报错/挂死。
- 回退同 E007 运行 1；电量 100%（Android 读取）。
- 结果（E007 运行 2，失败，本机观察）：gpi_dma1 探测成功（"Adding to iommu group 1"），"FIFO mode disabled" 警告消失；但执行 `spi-xfer /dev/spidev0.0 9f 00 00 00` 后整机挂死（USB gadget 消失，约 2 分钟内未自动重启，panic=15 未生效 → 不是可处理的 panic，是总线/死锁级挂死）。需要用户长按电源恢复。下一步：用户恢复后，从 pstore/串口之外的证据判断挂死点（GPI/SMMU 0x416 流、SE DMA 传输），先试不带 DMA 传输的 SE 空操作、检查 SMMU 故障日志。

### E007 运行 3：带日志流的复现（2026-11-09）
- 动机：运行 2 挂死无 panic、pstore 为空。改为：内核加 DYNAMIC_DEBUG、SOFTLOCKUP_DETECTOR+BOOTPARAM_SOFTLOCKUP_PANIC、DETECT_HUNG_TASK（CPU 自旋则 panic→15 s 重启并留痕）；上机后先开 dyndbg（gpi.c、spi-geni-qcom.c、qcom-geni-se.c），再用 ssh 把 `dmesg -w` 实时流到 private/touch/stream-run3.log，然后触发 spi-xfer；挂死点看流里最后几行。
- 其余输入同运行 2（DTS 不变）。回退同前。
- 候选（运行 3）：见 out/candidates/m5/SHA256SUMS（Image 36afe837…，镜像 4c4a53c7…）。
- 结果（运行 3，复现挂死，本机验证，日志流 private/touch/stream-run3.log）：dyndbg 显示 `geni_spi: req 1000000=>1000000 sclk 32000000, div 32`，然后 gpi 依次排入 RX TRE（dc541000…）和 TX 的 3 个 TRE（config、go、dma），日志到此为止，整机再次挂死。softlockup_panic 未触发，说明是总线级停摆而非 CPU 自旋。dc541000 是物理地址型 DMA 地址（SMMU 对该流实际是直通/恒等）。下一个动作应是 gpi_issue_pending 里的通道门铃写（gpi_write_ch_db）。
- 运行 4 计划：在 gpi_write_ch_db 前后加 dev_info+mdelay(150) 标记（临时，登记于 TECH_DEBT），重新触发，看流里最后一行是写前还是写后，区分“门铃写本身”与“门铃之后 GPI 引擎开始运行”。候选：Image b63b6836…，镜像 d23f5783…。
- 结果（运行 4，本机验证，private/touch/stream-run4.log）：RX 通道门铃写完成；TX 通道门铃写（reg=…2000，val=0xfffff030）打印后无 "done"，整机挂死 → 挂死发生在 TX 引擎启动时。同时日志显示 RX 缓冲在 TRE 里是物理地址 dc680000，而环地址是 IOVA（0xffffe010/0xfffff030）。
- 源码证据：spi-geni-qcom.c:1122 `spi->dma_map_dev = dev->parent`（缓冲区由 SE 的父节点即 QUP 包装器映射）；sm8450.dtsi 的 geniqup 节点都有 `iommus = <&apps_smmu … 0x0>`。我们的包装器 ac0000 没有 iommus → 缓冲区得到物理地址，而 SE 的 DMA 主设备走 SMMU，没有该映射 → SMMU 故障/总线挂死。**根因待验证：给包装器 1 加上厂商 DT 的 iommus。**
- 下一步：用户长按电源回 Android → 读厂商 DT 的 qupv3 包装器（phandle 0x1bd）iommus → 加入 DTS（运行 5）。

### E007 运行 5：包装器 1 加 iommus（2026-11-09）
- 来源：厂商 DT qcom,qupv3_1_geni_se@ac0000：iommus = <smmu 0x403 0x0>，dma-coherent，iommu-dma-addr-pool 0x40000000+0x10000000（本机 /proc/device-tree，private/touch/dt-qup-wrapper.txt）。
- 输入：DTS 给 &qupv3_id_0（ac0000）加 iommus = <&apps_smmu 0x403 0x0>、dma-coherent；其余同运行 4（保留门铃标记与 dyndbg）。
- 预期：TRE 里的缓冲地址变成 IOVA（不再是 dc…物理地址），TX 门铃之后传输完成，spi-xfer 回显 rx。
- 判据：通过=传输完成；失败=再次挂死（则怀疑别的因素，如核心时钟/供电）。
- 回退：同前，必要时长按电源。电量 100%。
- **结果（运行 5，通过，本机验证，private/touch/stream-run5.log）**：包装器 1 加 iommus 0x403 + dma-coherent 后，ac0000.geniqup 进入 IOMMU 组 0；GPI 传输完成（两个通道 "Transaction Success"、"spi_master spi0: DMA txn completed"），`spi-xfer /dev/spidev0.0 9f 00 00 00` 返回 rc=0，rx = 03 03 03 03，整机未挂死。快照 out/golden-m5-spi/（Image eed5159a…，DTB c88c71fb…，镜像 6cfa821f…）。
- 至此 SPI 总线（SE1 经 GPI DMA）可用。三处必要条件：互连提供者（含 qup-core/config 路径）、gpi_dma1 节点 + SE 的 dmas、包装器 1 的 iommus/dma-coherent。（互连投票是否必要尚未做消融。）
- rx=03 03 03 03 的含义未知：可能是浮空/IC 未应答，也可能是 FocalTech 协议要求不同的帧（命令、哑字节、CS 时序）。下一步需要 FTS 的 SPI 帧格式（厂商驱动源码）与 IC 上电/复位状态（供电未知）。

### E008：FocalTech SPI 探测（2026-11-09，M5 运行 5 的同一次启动）
- 协议来源（网页线索，MIT，只用线上事实）：sources/dl-fts/unixnu-ft8719（FT8719；包字节 0x05 状态/0xC0 命令/0x3F 数据；读控制 0xA0|长度；读数据后跟 CRC16-Kermit；首字节后 30 µs，包间 150 µs；固件运行时命令后附 2 字节长度）。FT8719 是近亲，FT8720 的差异待本机验证。
- 工具：tools/fts-probe.c（out/fts-probe，经 ssh 复制到 /tmp，未重启）。
- 观察 1（本机）：boot 模式首次：状态包回 0b 00（boot idle），读 0xA3/0x9F 均得 00、CRC 0000（错）。fw 模式：状态恒为 ef e1，等不到 idle → 超时。状态在两次运行间变化，说明第一次命令序列改变了芯片状态。读 ID 失败：芯片大概处于 ROM/boot 状态，或固件未起；这是 TDDI（触摸与显示同一芯片），触摸固件可能随显示复位后才启动。
- 事故（本机）：随后经 /dev/mem 把 TLMM12（触摸复位，0xf10c004）拉低 10 ms 再拉高，并在 200 ms 后跑 fts-probe，整机随即失去响应（USB 掉线，ping 全丢）。挂死点未确定（可能是复位触发 TDDI/显示侧故障、SPI/GPI 传输中遇复位、或寄存器访问本身）；事先未向用户说明风险，不应重复。需要用户长按电源恢复。
- 教训：碰复位线这类可能影响显示 IC 的动作，要先说明并在有日志流（tools/stream-dmesg.sh）的情况下做。
- 取证（Android，只读，2026-11-09；private/touch/android-dmesg-fts.txt）：厂商驱动 fts_8720.ko（Focaltech V3.4）开机序列：fts_reset_proc → 约 54 ms 后读到 chip id 0x8720 → 请求固件 focaltech_ts_fw_.bin（/vendor/firmware，270336 字节，sha256 前缀 9b48ac72，已拷入 private/touch/fw/，**不入库**）→ fts_fw_download：reset、读 boot id 0x87 0x20、写 PRAM 65212 字节（ECC f6da 对）、写 DRAM 4644 字节（偏移 65212，ECC 8732 对）、remap 启动 PRAM（总计约 110 ms）→ fw 版本 0x018，IC=FT8720 模块 HX → 触摸数据开始上报。**也就是说芯片每次开机都需要主机下载固件，ROM 态下读不到应用寄存器（正是我们看到的零）。**
- 下一步（无需复位）：fts-probe 新增 bootid 模式，ROM 握手 0x55/0xAA 后用命令 0x90 读 2 字节，期望 87 20；成功后再做 PRAM/DRAM 下载（协议参考 sources/dl-fts/unixnu-ft8719 的 ROMBOOT_* 命令，近亲芯片，需本机验证）。复位脉冲暂缓，直到弄清 E008 的挂死原因。
- E008 续（运行 6，本机验证，无挂死；private/touch/stream-run6.log）：只用 SPI，不碰复位线。(1) 新启动后 fts-probe bootid：状态包恒回 03 d3（d3&0x81≠0，不 idle），超时。(2) 软复位序列（寄存器 0xFC←0xAA，再←0x55，两种成帧）之后：状态变为 03 00（boot idle 值），但读 0x90 的结果全是 0（试了命令长度 1/4、数据长度 2/3、带/不带 0xAA 数据），原始字节 03 00 00 00 00。可能：芯片已进 ROM 但 0x55 握手必须在复位后几毫秒窗口内（厂商先硬件复位再 8 ms 发 0x55）；也可能全零只是没有设备在驱动 MISO（需要 MISO 对照）。结论：不用硬件复位走不下去。
- 待决：硬件复位脉冲（TLMM12）曾伴随整机挂死（E008）。拟做分步实验隔离原因：A. 开日志流，只拉低/拉高复位线，不做 SPI，3 秒后看手机是否还活；B. A 若安全，再做 8 ms 后 0x55 握手 + 读 boot id。A 若挂死则复位线本身（很可能牵动显示 IC）是根因。需要用户同意并可能再长按电源一次。
- E008 续（运行 7，本机验证；private/touch/stream-run7*.log）：**分步实验结果**：A. 只拉低/拉高 TLMM12 复位线（不做 SPI）：手机无恙，日志无错误 → 复位线本身安全，E008 的挂死不是复位脉冲造成的（具体原因仍未知，可能与当时芯片在异常状态下的 SPI 事务有关，或偶发）。B. 复位后 8 ms 内握手：fts-probe 的 reset 模式（工具内部经 /dev/mem 拉 TLMM12，1 ms 低、8 ms 后发 0x55、再读 0x90）8 轮，状态包恒 00（boot idle），读 ID 全 0（期望 87 20）。其间有过一次状态 00 22、读到 22 45 的不稳定值。结论未定：芯片可能已在 ROM 但握手细节不同（FT8720 对比 FT8719），或 MISO 采样/引脚电气配置不对（我们的引脚 bias-disable、drive 6，与 Android 未比对）。
- 事故（运行 7 末，本机观察）：为比对引脚电气配置，经 /dev/mem 读 TLMM 焊盘寄存器 0xf11a000/0xf11b000/0xf132000/0xf133000（gpio 26/27/50/51），整机挂死（USB 掉线）。这些焊盘属受保护区域（参考仓库早有 TZ 保护 GPIO 的提示）。**规则：不再读未经确认的 TLMM 焊盘地址；改用 Android 侧 debugfs pinconf-pins 对比，或在 Linux 用 pinctrl 子系统读。** 需用户长按电源。

### E008 运行 8：引脚电气配置对齐厂商（2026-11-09）
- 取证（Android，只读；private/touch/dt-spi-pins.txt）：厂商 SPI 引脚 active 态：gpio50=miso(qup1_se1_l0)、gpio51=mosi(l1)、gpio26=clk(l2)、gpio27=cs(l3)，全部 drive-strength 6、**bias-pull-down**；sleep 态为 gpio 功能、drive 2，其中 CS 为 pull-up。我们原来用 bias-disable。
- 改动：tools/gen-m5-dts.py 的 qup_spi1_default 改为 bias-pull-down。
- 预期：MISO 状态更稳定；复位后握手 `fts-probe … reset` 能读到 boot id 87 20。判据：读到 87 20 且 CRC 对。
- 结果（运行 8，本机验证，无挂死；private/touch/stream-run8.log）：引脚改 bias-pull-down 后，reset+握手 8 轮：状态包恒为 fd，读 ID 回 `00/03 fd c3 00 91`，每轮完全相同、与命令无关 → 芯片（或总线）在输出固定模式，不是 ROM 的 87 20。仍未读到 boot id。下一步：抓 Android 驱动的真实 SPI 字节（tracefs 的 spi 事件），按字节对照我们的帧，而不是继续猜。

### E008 突破：Android 实际 SPI 字节（2026-11-09，本机验证，private/touch/android-spi-trace1.txt、…trace2.txt）
- 方法：Android tracefs `events/spi/spi_transfer_stop`（bus 0），读驱动 sysfs（fts_fw_version、fts_driver_info）和读 fts_hw_reset（该 sysfs 读即执行硬复位）。
- **真实帧格式（FT8720，驱动 V3.4）= 单次传输，不是 FT8719 的多包**：读寄存器 = 一次 SPI 传输 `[reg][0xA0][len_hi][len_lo] + 3 个哑字节 + len 字节数据位 + 2 字节 CRC`，tx 其余为 0；rx 前 7 字节是填充（0x01/0x09 交替），数据从偏移 7 开始，后接 CRC16-Kermit（低字节在前，已用 5 组抓包逐一核对）。例：reg 0xA3 → 87，reg 0xA6 → 0x12（固件版本），触摸报告 = reg 0x01、len 0x5a（90 字节），总长 99。写：`[reg][0x00][len_hi][len_lo]+数据`（例 b6 00 00 01 00…）。
- **硬复位后芯片约 40 ms 自启应用**（reg 0xA3 读到 0x87，0x9A/0x9B 等读先回 0），**不需要主机下载固件就能工作**；开机时的 270336 字节下载只是升级/恢复。
- 我们之前所有失败（零、固定模式、状态不空闲）都是用了错误的成帧（FT8719 多包协议）。
- 下一步：fts-probe 新增 app 模式用正确成帧在复位后读 0xA3/0x9F/0xA6，并读一帧触摸报告；成功后写主线驱动（input、IRQ、MT 协议）。
- 结果（运行 9，本机验证，无挂死；private/touch/stream-run9.log）：正确成帧下，fts-probe app 模式（无复位与复位脉冲后）所有寄存器读 CRC 全对，值都是 0xEF（包括触摸报告前 12 字节）。**成帧已确认正确**；0xEF 是 ROM/bootloader（无应用）状态的标志。结论：冷启动后芯片没有应用，必须由主机下载固件（Android 开机时就在下载）；此前 Android 里看到“复位后 40 ms 就读到 0x87”是因为那时 RAM 里仍有上一次下载的应用。
- 下一步：在 Android 里触发一次固件升级并抓 SPI 字节（reset→boot id→PRAM 写→ECC→DRAM→启动），按字节复刻到 fts-probe（固件在 private/touch/fw，不入库）。

### E008 运行 10：固件下载复刻（2026-11-09）
- 来源：Android 抓包 private/touch/android-spi-trace3.txt（fts_force_upgrade 触发，本机验证）。全部命令同一帧型 `[cmd][ctrl][len_hi][len_lo]+3 哑字节+载荷`（写 ctrl=0x00；读 0xA0，数据在偏移 7 后接 CRC16-Kermit 低字节在前）。序列：硬复位 → `55 00 00 00` → 约 8 ms → 读 `90`（2 字节）得 87 20 → `ad`（载荷 3 字节地址）+ `ae`（载荷数据，len=块长）按块写 PRAM（文件 0..65212 → 地址 0）→ `cc`（载荷 00 00 00 + 长度 3 字节）→ 轮询 `ce` 读 1 字节直到 0xA5 → 读 `cd` 2 字节得 ECC（f6da）→ 写 DRAM（文件 65212..69856 → 地址 0xd00000，ECC 8732）→ `08 00 00 00` 启动应用 → 约 17 ms 后 reg 0xA3 = 0x87、0xA6 = 版本。固件内容与抓包数据逐字节核对一致（PRAM = 文件前 65212 字节，DRAM = 其后 4644 字节）。
- 实现：tools/fts-probe.c `d` 模式（块 4080 字节以适应 spidev 默认 4096 缓冲；SPI 1 MHz）。固件文件仅经 ssh 复制到手机 /tmp（RAM），不入库、不入镜像。
- 预期：boot id 87 20 通过；PRAM ECC f6da、DRAM ECC 8732；启动后 reg A3=0x87，触摸报告 CRC 对。判据：以上全部成立。回退：失败只会让触摸芯片留在 bootloader，不影响其它；再来一次复位即可。
- **结果（运行 10，通过，本机验证；private/touch/stream-run10.log）**：fts-probe `d` 模式在 Linux 下复刻 Android 的固件下载：硬复位（TLMM12，经 /dev/mem）后 boot id = 87 20；PRAM 65212 字节 ECC = f6da（与 Android 日志一致）；DRAM 4644 字节 ECC = 8732（一致）；启动应用后 reg A3 = 0x87、A9F = 0x20、A6 = 0x12（固件版本，与 Android 一致），触摸报告 CRC 正确（首字节 0x90，无触摸时后面为 ff）。整机未挂死。至此 **主线下 FocalTech FT8720 已能启动并通信**。快照 out/golden-m5-touchfw/（固件文件不在其中，在 private/touch/fw）。
- 下一步：加载后立刻读触摸帧（Android 在启动后做了 b5 读、b6 写 0x00 的恢复步骤），在屏幕上按手指验证坐标；然后写主线驱动（spi_driver：复位/下载固件/IRQ/MT 上报），固件走 request_firmware。

## E009 — 主线 FT8720 SPI 触摸驱动（m6，2026-11-09，上机前记录）
- 来源：drivers/input/touchscreen/focaltech-ft8720-spi.c（本项目自写，GPL-2.0；协议来自 Android 的 SPI 字节追踪与 Dracen-W/FT8719 的事实性参考，无厂商源码）。固件头 0x100/0x108 的大端字对（值与按位取反各一，×2 字节）给出 PRAM=65212、DRAM=4644，与此前重放一致（本机验证）。
- 输入：Image/DTB/boot（Image/DTB/boot 前 8 位 hash：4d6285d1… ec13eee3… d931c392…，完整见 out/candidates/m6/SHA256SUMS）；固件 private/touch/fw/focaltech_ts_fw_.bin sha256 9b48ac72…（只进 initramfs，不入库）；DTS 由 tools/gen-m6-dts.py 生成（去掉 spidev 与 TLMM12 hog，加 touchscreen@0：9.6 MHz，IRQ TLMM13 下降沿，reset TLMM12 低有效，1080x2460）。
- 预期：内核日志出现 "FT8720 ready, firmware version 0x12"，/dev/input/event0 存在，触摸时有 ABS_MT 事件。
- 判据：probe 成功且触摸事件坐标落在 0..1079 / 0..2459 内；失败则看 dmesg 的 probe 错误（boot id / ECC / 应用 ID）。
- 回退：init 3600 s 定时 reboot -f；panic=15；长按电源 10–15 s。启动用 fastboot boot，不写分区。
- 结果（m6 运行 11，本机验证；private/touch/m6-boot-dmesg.log）：开机 0.35 s 内 probe 成功：`FT8720 ready, firmware version 0x12`，输入设备 "FocalTech FT8720 touchscreen"（event0，MT 槽 10），IRQ TLMM13 边沿（200 s 内 2 次中断），空闲无事件。驱动内的固件长度解析（头 0x100/0x108 取反字对）、ECC 校验、复位时序均有效，不需要 DT 长度属性。**未验证**：真实手指事件、坐标范围与方向（用户已睡，待测）；interconnect 是否必需仍未消融。工具：tools/touch-events.py（主机解码 input_event）。
- 结果（m6 运行 12，本机验证 + 用户触摸；private/touch/m6-touch-run1.log，2026-11-10）：主线驱动在 120 s 内上报约 3170 帧，最多 4 指同时，ABS_MT 坐标 x 0–1069、y 0–2459（触及屏幕全高，宽度近满），与 1080x2460 竖屏一致；无 probe 之外的错误。**未验证**：与显示画面的方向对应（需屏上画点工具）、x 右边缘 1070–1079 未触及。

## E010 — SPMI/PMIC GPIO + 触摸画点工具（m7，2026-11-10 离线准备，**未上机**）
- 目的：让 Linux 真正拥有 PM7250B GPIO11/12（面板 vddio/extvdd）和 PM6450 GPIO6（KTD3136 HWEN），并上机核对触摸方向。
- 输入（未上机，哈希 out/candidates/m7/SHA256SUMS）：Image 87eb48d7…，DTB 8287d4ba…，boot 4facd208…；DTS 由 tools/gen-m7-dts.py 生成（= m6 + `spmi@c400000` 仲裁器 [reg/名称/中断取自运行时 DT qcom,spmi@c42d000，ee 0，channel 0]，pmic@1 的 pm6450-gpio@8800 和 pmic@2 的 pm7250b-gpio@c000；vddio/extvdd 固定调压器加 gpio 并保留 always-on/boot-on；ktd3136 加 `enable-gpios` = PM6450 gpio6）；config 额外开 SPMI_MSM_PMIC_ARB/PINCTRL_QCOM_SPMI_PMIC/MFD_SPMI_PMIC（已 =y）；initramfs 含 /bin/touch-paint（freestanding，`touch-paint /dev/input/event0 60`，四角红/绿/蓝/黄方块，期望触摸红块左上、绿块右上……）。
- 预期：dmesg 出现 `spmi-pmic-arb` 版本、pm6450/pm7250b gpio 注册、ktd3136 probe（enable gpio 获取成功）、屏幕和背光保持；touch-paint 的方向与角点对应。
- 判据：ssh 可达；dmesg 无 SPMI 错误（若有 -EIO/超时则 ee/channel 或 TZ 保护问题，立即停用 SPMI）；屏幕不黑。
- 风险：SPMI 仲裁器首次启用，读错误通道可能挂死整机（类 TLMM 读）；因此**只在用户在场时上机**。回退：init 3600 s 定时 reboot -f，panic=15，长按电源 10–15 s；`fastboot boot` 不写分区。已知担心：panel 驱动与 ktd3136 现在依赖 GPIO 控制器，若 SPMI probe 失败，背光驱动将一直 defer（屏幕内容可能无背光）。
- 分步建议：先只开 SPMI+pm6450（不改 vddio/extvdd），再开 pm7250b。若出问题，退到 m6（已验证）。

## E011 — 全 8 GB 内存映射（m8）与 RAM 桌面路线（2026-11-10 离线准备，**未上机**）
- 来源（本机验证，离线）：运行时 DT 的 /memory 共 7 个 bank（8008 MiB）+ 31 个静态 no-map 保留区；tools/memmap.py 算“bank 减去 no-map”= **7609 MiB / 14 段，与 Android /proc/iomem 的 System RAM 逐字节一致**（无多无少），所以映射有据，而不是猜的。当前内核只给 0xc0000000 起的 518 MiB。
- m8 候选（= m6 + 全内存）：tools/gen-m8-dts.py（memory@80000000 七个 bank；其余 30 个 no-map 保留区按运行时 DT 写成 reserved-memory 节点，已排除 sm4450.dtsi 的 cmd-db 与 m3 的 smem；另加 splash@b8000000 no-map，保护 ABL 屏幕扫描区）；tools/build-m8.sh；tools/cycle-boot-m8.sh；initramfs 带 /bin/memfill（RAM 写读校验）、/bin/touch-paint。哈希见 out/candidates/m8/SHA256SUMS。
- 预期：dmesg 里 `Memory: …K/8…K available`，/proc/meminfo MemTotal ≈ 7.4 GiB；`memfill 6000 2` 每 256 MiB 打印进度、末行 `mismatches=0`；m6 的触摸/屏幕行为不变。
- 判据：无挂死/重启；memfill 0 不一致。若在 memfill 中途挂死，最后一行进度给出大致物理区间（页分配顺序不保证，需结合 /proc/iomem 与 kpagecount 再定位）。
- 回退：init 3600 s 定时 `reboot -f`、panic=15、长按电源；m6 是已验证的回退点。
- 风险：触及固件保护区会触发安全中止/整机重启（但 no-map 列表与 Android 一致，预期不会）；ABL 把 boot 镜像/ramdisk 放在低地址，shim 已把内核复制到 0xc0000000，旧位置变为可用内存，理论上无影响；32 位 DMA 设备通过 swiotlb。
- RAM 桌面路线（修订 E007 末的结论“RAM 根里跑合成器不可行”）：不再塞进 initramfs，而是启动小镜像后用 USB 网络把 rootfs 推进 tmpfs：tools/apk-fetch.py 取得 Alpine v3.24 aarch64 的 weston+foot+eudev+libinput+字体闭包（123 个包，113 MB apk，解包 322 MiB）；**APKINDEX 的 RSA-SHA1 签名已用 Alpine 官方密钥验证（Python 整数实现，因 Fedora OpenSSL 拒绝 SHA-1；负对照通过），每个 apk 的控制段 SHA-1 与大小对照索引，通过**（只下载，不在主机执行）。tools/build-desktop-rootfs.sh 解包并打成 out/rootfs-desktop.tar（311 MiB，sha256 2536c8ee…）；tools/push-desktop.sh 在手机上挂 tmpfs、推送、挂载 proc/sys/dev 并 chroot 运行 desktop/start-desktop（busybox applet、eudev、weston --backend=drm，pixman 渲染，desktop/weston.ini，scale=2，输出名 DSI-1 待核实）。均未在手机上运行。
- 未验证：weston 的 DRM 原子提交在本机 msm/DPU 上是否可翻页（只验证过 fbdev）；DSI-1 输出名；触摸经 libinput/udev 的方向；musl+Alpine 包在本机内核上的兼容；无 GPU（Adreno 未启用），只有 pixman。
- 运行 1（m8，2026-11-10 约 08:45，用户授权“Boot it”，本机验证）：`fastboot boot` OKAY（电量 100%），之后 **USB 上没有任何设备枚举（gadget 不出现，也没有 adb/fastboot）**，持续 5 分钟以上；无法区分“内核存活但 USB 失效”与“整机挂死”（用户不在场看不到屏幕）。init 定时器 3600 s 后若内核存活会自行回 Android，以此判别。
- 假设（源码/运行时 DT 证据，未验证）：Android 的 DWC3 经 SMMU 流 0x540（iommus <0x2f 0x540 0>，IOVA 池 0x90000000+0x60000000）；我们的 DT 无 iommus，控制器收到的是物理地址。m6 只有 518 MiB（全在 4 GiB 下）所以没事；m8 映射 8 GB 后 GFP_KERNEL/dma_alloc_coherent 优先落在 4 GiB 以上，控制器够不到。
- 应对（m9，已构建未上机）：tools/gen-m9-dts.py = m8 + `&soc { dma-ranges = <0 0 0 0 0x1 0>; }`（所有 soc 设备 DMA 限 4 GiB；一致性缓冲落 ZONE_DMA32，流式走 swiotlb）。治本是给 usb_1 加 `iommus = <&apps_smmu 0x540 0x0>`。
- 运行 2（m9，2026-11-10，init 计时器改为 420 s，ssh 里 touch /tmp/stay 延至 3600 s）：m8 运行 1 到 3600 s 时手机自行回到 Android（9:40，电量 100%）→ 内核存活，仅 USB 失效，支持上面的 DMA 假设；pstore 为空（已知）。上机 m9：Image 1ec98273…，DTB e6164ae7…，boot 0d9e7d5c…；预期 gadget 出现、MemTotal≈7.4 GiB；判据 ssh 可达；回退 420 s 计时器。
- 结果（m9 运行 2，本机验证；private/touch/m9-memfill-dmesg.log）：**m9 启动成功**：gadget 出现，ssh 可达，MemTotal 7465696 kB（≈7.1 GiB），触摸 probe 正常。与失败的 m8 只差 soc dma-ranges 4 GiB，单变量对照 → m8 失败原因确认为 USB 的高于 4 GiB 的 DMA。`memfill 6800 2`：两遍（正/反码）写读校验 6800 MiB，**mismatches=0**，内核日志无错误（4.2 s）。
- 结果（m9 运行 2 续，本机验证 + 日志；private/touch/m9-desktop-dmesg.log）：**RAM 桌面跑起来了**。tools/push-desktop.sh 把 311 MiB rootfs 经 USB NCM 推进 tmpfs（41 s）；chroot 里 weston 14.0.2 / foot 1.27 / eudev 可运行。迭代修复三处：① Alpine 的 libseat 没有 builtin 后端 → 加 seatd（apk-fetch 验证后推送，start-desktop 先起 `seatd -g root`）；② chroot 无 /etc/passwd /etc/group（seatd 解析不到 root 组）→ start-desktop 补；③ /dev 要 `--rbind`（devpts 才可见，否则终端 “failed to create pty”）。结果：`using /dev/dri/card1`，DRM atomic 模式设置、Pixman 渲染器、`DSI-1` 1080x2460@90.0，触摸（event0，udev 标记 Touchscreen）经 libinput 关联到 DSI-1；weston-desktop-shell、weston-keyboard、foot（运行 /bin/sh）、weston-terminal 均已运行；内核日志无 DRM/DPU 错误（仅 udev 组名警告）；空闲负载 0.04。**未验证**：我看不到屏幕（用户不在），因此画面内容/触摸响应/方向/翻页是否稳定都未验证。工具：tools/desktop-up.sh（一条命令完成 m9 启动+推送+启动）。

## E012 — Adreno 613 GPU（m10，2026-11-10 离线准备，**未上机**）
- 背景/证据：见 docs/GPU.md。本机运行时 DT：`qcom,chipid = <0x6010300>`（A613）；内核已含 ROCKNIX 的 A613 目录项和 gpucc-sm4450 补丁；Mesa main 设备表含 `GPUId(613)`。
- 固件（来源 = 本机 PixelOS OTA 的 vendor 镜像，payload-dumper-go 提取，debugfs 导出；私有，存 private/gpu/，不提交）：`a630_sqe.fw`（vendor 版 32504 B，与 linux-firmware 版 34188 B 不同，用 vendor 版；sha256 413dbae6…）、`a610_zap.elf`（vendor 里唯一的低端 Adreno zap；14384 B，sha256 d278ab36…；单文件 ELF，段 0x3000+0x830，装得进保留区 gpu-microcode@89c1a000 的 0x2000；在 initramfs 里命名为 `qcom/sm4450/a613_zap.mbn`）。注意：这是「vendor 里只有 a610_zap 可对应 A613」的推断，未在 Android 运行态核对 kgsl 实际加载的文件名；zap 由 TZ 验签，错了表现为 GPU 初始化失败，不是挂死。
- 输入哈希（m10，已 sha256 -c 通过）：Image `4be0700d…`、DTB `ea7919d2…`、boot 镜像 `667fdafe…`（out/candidates/m10/SHA256SUMS）。基于 m9（8 GB + 4 GiB DMA 限制）单一新增：gpu/gmu_wrapper/adreno_smmu/qfprom(speed bin)/gpucc 电源域（tools/gen-m10-dts.py 从 ROCKNIX 切片；去掉 interconnects，zap 保留区换成本机 0x89c1a000），内核 `SM_GPUCC_4450=y`，initramfs 带 GPU 固件。桌面 rootfs 增加 mesa-vulkan-freedreno、vulkan-loader/tools、mesa-demos、kmscube（sha256 b39e713b…，APKINDEX 签名验证）。
- 预期：dmesg 出现 adreno/zap 相关信息，`/dev/dri/renderD128` 出现，`eglinfo -B` 报 freedreno / Adreno 613，`vulkaninfo --summary` 列出 turnip 设备（版本不预设）；显示（DSI-1）和 USB 不受影响。
- 判据：通过 = SSH 可达，`tools/gpu-test.sh` 日志里有 render node 且 EGL 初始化成功；部分通过 = 有 render node 但 zap/固件/GMU 报错（记录原因，GPU 回退 pixman）；失败 = 起机即无 USB/屏幕异常（GPU 时钟或 GDSC 操作挂死）。
- 回退：init 计时器 420 s（`touch /tmp/stay` 延长）自行回到 Android；`panic=15`；电源键长按 10–15 s。桌面仍可用 `RENDERER=pixman`（默认）。
- 未建模/风险：interconnect 带宽投票（DDR 沿用 bootloader 设置）、speed bin 从 qfprom 0x119 读取（Android 同样读，ROCKNIX 同值）、GPU 挂起后 SMMU 上下文、turnip 在 A613 的功能缺口。首次上机需用户在场并流式看 dmesg（tools/stream-dmesg.sh）。
- 上机步骤：`tools/cycle-boot-m10.sh` → 等 ssh → `tools/push-desktop.sh --no-start`（先不启 Weston）→ `tools/gpu-test.sh` → 有 render node 再 `RENDERER=gl tools/push-desktop.sh`（或手动在 chroot 内起 Weston gl）。

### E012 运行记录（2026-11-10，用户授权无人值守上机；日志 private/gpu/m10-run*-dmesg.log，不提交）
- 运行 1（m10 初版）：USB/ssh 正常、显示回到 simpledrm 之外失败：`adreno … opp key field not found` -> `msm_dpu: failed to load adreno gpu`。原因：我去掉了 interconnects 但 OPP 表仍有 `opp-peak-kBps`（路径数不符 -> -EINVAL）。
- 运行 2–5：去掉 opp-peak 后 GPU 能 probe、SQE 加载，但 `cp_init` 超时（`timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C`）。加调试输出（E012-DEBUG）：INT0=CP_HW_ERROR+HANG_DETECT，CP_INTERRUPT_STATUS=0x80（CP 非法指令），ROQ 空。加回 interconnects（含新增 mc_virt 提供者）后 ROQ 有数据但仍失败。a660_sqe.fw 单变量试验：非法指令消失但 CP 仍不前进（回退 a630）。只保留最低 OPP（340 MHz）也无改善。
- 运行 6–11 的关键发现：同一镜像不同次启动，固件 BO 的 CPU 回读不一致（`version 0` / 非法指令随机出现）；memcpy 后立即回读固件 BO，8125 个 dword 里 32–96 个与源不同（整条缓存行）。DRM 设备和 GPU 均非一致性（coherent 0/0）。根因（推断，运行 12 证明）：m9 的 soc `dma-ranges` 4 GiB 权宜之计让 DRM 设备对 4 GiB 以上的 GEM 页走 swiotlb 反弹缓冲，原页的 CPU 缓存清理被跳过，旧缓存行事后覆盖写合并映射里的数据。
- 运行 12：去掉 4 GiB dma-ranges，改 `usb_1` 加 `iommus = <&apps_smmu 0x540 0x0>`（Android 的 USB SMMU 流）。USB/ssh 正常（权宜之计的治本方案成立，TECH_DEBT 对应项在 m10 起关闭），固件 BO 回读 0 不一致，CP 初始化通过；下一个错误是 zap：`error -22 initializing firmware qcom/sm4450/a613_zap.mbn`（TZ 拒绝）。
- 运行 13–14：-22 与是否拆分无关（元数据相同）；真正原因是我之前推断错了文件：vendor 的 `a610_zap.*` 是 test 签名遗留（证书 "SecTools Test User/Generated Test Attestation CA"），本机 A613 的 zap 是 `firmware/gen6_3_26_0_zap.mbn`（证书 Xiaomi Root CA；我最初的 debugfs 列表只看了前 64 行漏掉了它）。换成它（sha256 eec5e45a…）：GPU 硬件初始化无错误。
- 运行 15–16：Mesa 看到 `gpu_id 0` 不认；设 `.revn=613` 后 `unsupported GPU id 0x265`：Alpine 的 Mesa 26.1.6 设备表有 608/612 但没有 613（613 在 main 里后加）。权宜之计 `.revn = 612`（Mesa 里 608/612/613 是同一份配置）：EGL `OpenGL ES profile renderer: FD612`，OpenGL 4.6 core / ES 3.2；`vulkaninfo`：`Turnip Adreno (TM) 612`，Vulkan apiVersion **1.0.354**，conformanceVersion 1.2.7.1（turnip 在 gen1_low 上只暴露 1.0 API）。
- 运行 17（负载）：`kmscube -D /dev/dri/card1`（GBM/EGL，freedreno FD612）运行 12 s 无 GPU 故障；之后以 `renderer=gl` 启动 Weston：`GL renderer: FD612`，`Using GL renderer`，识别 FT8720 触摸屏与 DSI-1，foot 在其上运行，内核日志无 adreno/smmu 错误，仅 `devfreq 3d00000.gpu: Couldn't update frequency transition information.`（无害，GPU 频率只有 340 MHz 一档）。
- 结论（已验证 / 未验证）：已验证 = A613 在主线内核 + 本机 SMMU/zap/固件下完成硬件初始化，freedreno GLES 3.2 与 turnip（Vulkan 1.0）可用，Weston GL 合成器在其上运行。未验证 = 画面是否在屏幕上正确显示（需要人眼）、性能与稳定性（没有长时间负载）、更高 GPU 频率档、GPU 休眠/唤醒。金件：out/golden-m10-gpu/（Image/DTB/boot 哈希前缀 Image 08982362…、DTB ef71bcec…、boot 45552f09…）。

### E012 补充：GPU 全频率档（2026-11-10 晚，无人值守）
- 输入：m10 + 完整 OPP 表（gen-m10-dts.py 默认；`M10_LOW_OPP=1` 回到只有 340 MHz）。speed bin 读出 201（bin 1），表里 765/850/955 MHz 的 `opp-supported-hw` 对该 bin 有效，1010 MHz 档不适用。devfreq 可用档：340/500/605/765/850/955 MHz，governor simple_ondemand。
- 做法：把 devfreq min=max 钉在每一档，运行 `kmscube -D /dev/dri/card1 -c 600`（stdin 必须保持打开，见下），读 cur_freq 与内核日志。
- 结果：六档全部 cur_freq 与目标一致，600 帧 6.655 s = 90.00 fps（面板刷新率，vsync 限速），内核日志无 adreno/smmu/fault/hang。**仅证明各档时钟/电压配置可稳定出帧**；kmscube 太轻，不是压力测试（没有 glmark2 类负载）。
- 坑：kmscube 会 poll stdin，stdin 一读到 EOF（ssh 无 tty）就当作 “user interrupted” 立刻退出（0 帧）；`tail -f /dev/null | kmscube` 会让管道永远不结束。可用的做法：`mkfifo f; exec 3<>f; kmscube <&3`。之前 E012 里 “kmscube 12 秒” 的那次其实**没有证明持续渲染**（很可能是立刻退出）；以本节 90 fps 结果为准。

## E013 — SPMI 仲裁器 + PM6450/PM7250B GPIO（m11 = m10 + SPMI，2026-11-10 晚，用户授权“挂了也无妨”）
- 目的：让 Linux 拥有 PMIC GPIO（面板 vddio/extvdd = PM7250B gpio11/12，KTD3136 HWEN = PM6450 gpio6），为将来休眠断电、关屏打基础。E010 的 m7 是基于 m6 的（518 MiB、无 GPU），现在改为基于 m10，并分阶段。
- 阶段 A（本次）：只加 `spmi@c400000` 仲裁器（值取自运行时 DT）和 pm6450-gpio@8800 / pm7250b-gpio@c000；面板和背光**不**依赖它们（SPMI probe 失败不影响显示）。阶段 B（A 通过后）：vddio/extvdd 与 ktd3136 enable-gpios 接到 PMIC GPIO（仍 always-on）。
- 输入（stage A，已 sha256 记录于 out/candidates/m11/SHA256SUMS）：Image 9111f24f…、DTB 7d98ee87…、boot 1b3707cc…；config 额外 SPMI_MSM_PMIC_ARB / PINCTRL_QCOM_SPMI_PMIC / MFD_SPMI_PMIC =y。
- 预期：dmesg 出现 `spmi-pmic-arb c400000.spmi: PMIC arbiter version …`，pm6450/pm7250b gpio 注册，debugfs `gpio` 列出 PMIC GPIO；PM7250B gpio11/12 读到 “out high”（panel 供电，ABL 已开）；显示、USB、GPU 不受影响。
- 判据：通过 = ssh 可达，arbiter 版本行 + GPIO 控制器注册，debugfs 中 gpio11/12 为高。部分 = arbiter 探测到但读取失败（-EIO/超时，TZ 保护通道/ee 号不对）。失败 = 整机挂死/无 USB。
- 回退：init 计时器 420 s（stay 延长），panic=15，长按电源 10–15 s；`fastboot boot` 不写分区；退回 m10（金件 out/golden-m10-gpu/）。
- 风险：首次启用 SPMI 仲裁器，错误的通道可能令整机挂死（类 TLMM 读）。用户已说明“挂了也没关系”；仍先做 A 阶段以便定位。

### E013 运行记录（2026-11-10 晚）
- 运行 A（m11 stage A，PM7250B 按节点名写成 SID 2）：**手机没有挂死**。`spmi_pmic_arb c400000.spmi: PMIC arbiter version v7 (0x70000001)`；pmic@1（PM6450）探测正常；pmic@2 读 0x104 失败：`pmic_arb_check_chnl_status_v1: 0x2 0x104: transaction failed (0x3)`（DONE|FAILURE，SID 2 上没有从设备），`pmic-spmi 0-02: probe failed -5`。原因：运行时 DT 节点名是 `qcom,pm7250b@2`，但其 `reg = <0x08 0x00>`，**真实 SID 是 8**（第二颗 pm7250b 是 SID 9）；节点名里的数字不是 SID。tools/gen-m7-dts.py（m7 同样写错）和 gen-m11 已改成 pmic@8。
- 运行 A2（SID 8）：无 SPMI 错误，`/sys/bus/spmi/devices/` 有 0-01、0-08；debugfs pinctrl 出现 `c400000.spmi:pmic@1:gpio@8800` 与 `c400000.spmi:pmic@8:gpio@c000`。即：**arbiter + 两个 PMIC GPIO 控制器注册成功**（阶段 A 的 probe 层面通过）。
- 之后我在 RAM 系统里 `cat /sys/kernel/debug/gpio`（会遍历所有 gpiochip，含 TLMM 和两个 PMIC）：先是 busybox grep 段错误，随后下一条 ssh 命令发出后手机从 USB 上消失，ping 不通，60+ 秒内没有恢复 = **硬挂死**（内核死了，init 计时器也无法触发，需长按电源 10–15 s）。**挂死原因未定**：候选 (a) 遍历 TLMM 的受保护引脚（早期已知会挂，sky-linux 的 nofault 补丁只覆盖部分路径）；(b) PMIC GPIO 寄存器经 SPMI 读（debugfs show 会读每个引脚的多个寄存器）。没有区分它们的数据。**下次**：只读单个 PMIC 控制器的 pinctrl debugfs（`/sys/kernel/debug/pinctrl/c400000.spmi:pmic@8:gpio@c000/pinconf-pins`），不要读 `/sys/kernel/debug/gpio`；并在读之前用 `tools/stream-dmesg.sh` 之类让日志实时落盘（本次读之前没有）。
- 状态：手机需要用户在场长按电源键恢复。m11 stage B（vddio/extvdd/KTD3136 接 PMIC GPIO）未做。

## E014 — WPSS（WiFi/BT 子系统）remoteproc + QRTR 服务可见（m12 = m11 stage A + IPCC/AOSS QMP/SMP2P/WPSS，2026-11-10，离线准备，**未上机**）
- 背景与证据：docs/WIFI-BT.md（芯片 WCN6750 adrastea/SNOC；ath11k 走不通；厂商 qcacld 路线；固件在 modem_a 备份）。
- 目的：回答平台前提——WPSS 能否由主线 remoteproc 从厂商分段镜像 `adrastea/wpss.mdt` 拉起，并在 QRTR 上注册 WLFW（service 0x45）。不含任何 WiFi/BT 驱动，不改显示/GPU/USB/SPMI 路径。
- 输入（out/candidates/m12/SHA256SUMS）：Image 221e4a0b…、DTB a9cf063f…、boot 4eae3351…（sky-m12-shim-boot-v4.img）。DTS 由 tools/gen-m12-dts.py 生成；构建 tools/build-m12.sh；config 额外 `QCOM_Q6V5_PAS=y QRTR=y QRTR_SMD=y`。
- 固件来源：private/backup-unique-20261109T142656Z/modem_a.img（SHA256SUMS 复核 OK）→ `7z x image/adrastea/*` → private/wifi/fw/（哈希 private/wifi/SHA256SUMS-wpss）；initramfs 只装 wpss.mdt + b00–b08 + b10；`qrtr-lookup` 来自 Alpine v3.24 `qrtr-1.2-r1` + `qrtr-libs`（tools/apk-fetch.py，签名与控制段哈希已验证，sources/dl-wifi）。
- 预期（第三方同机型结果，本机未复现）：dmesg `remoteproc … powering up wpss` / `Booting fw image adrastea/wpss.mdt` / `remote processor wpss is now up`；`/tmp/wpss-obs.log` 中 remoteproc 状态 running，`qrtr-lookup` 出现 node 13 的 service 0x45（WLFW）及 0xf/0x2b/0x42/0x33。
- 判据：通过 = running 且 0x45 可见；部分 = running 但无服务（glink/IPCRTR）；失败 = 固件 -ENOENT / PAS 认证失败 / 起后即 wdog、fatal / 整机挂死。每类的含义见 WIFI-BT.md。
- 回退：`fastboot boot` 不写分区；init 420 s 计时器 `reboot -f`（touch /tmp/stay 延长）；退回 m10/m11 金件。手机挂死则长按电源 10–15 s。
- 风险：auto_boot=true，驱动内置，所以 WPSS 会在内核启动早期（initramfs 解包后，设备初始化时）就被拉起；动用 CX/MX 电源域与 AOSS QMP。SCM 失败通常只是返回错误；若 TZ 重置整机，则回到 bootloader/Android（可接受）。首次上机建议用户在场并流式看 dmesg（tools/stream-dmesg.sh）。
- 状态：构建与静态核对完成（DTB 含 remoteproc@8a00000；initramfs 清单含固件与 qrtr-lookup）；**没有任何设备证据**。手机当时挂死，等用户恢复。

## E015 — 蓝牙（m13 = m10 + WCN3950 级 BT on UART2，2026-11-10 晚，用户授权“go with 2”，用户在场）
- 依据：docs/WIFI-BT.md “Android 在线核对”（HAL：ttyHS0 = 988000 qup_uart，Product 0x0f / ROM 0x0103，cmbtfw13.tlv + cmnv13*.bin；活动 DT bt_wcn3990 的引脚与供电）。基线 m10（刚经用户人眼确认的桌面/触摸），不含 SPMI/WPSS（显式 `-d QCOM_Q6V5_PAS -d QRTR`，避免共享 .config 带入 m12 的改动）。
- 改动：`&apps_rsc` pm6450 L14B(1.304 V)/L21B(1.8 V)/L23B(1.8 V, always-on)、pm8010 L7E(3.0 V)；`wcn3950-pmu`（swctrl tlmm 56）；`geniqup@9c0000`（iommus 0x163、dma-coherent）+ `serial@988000`（SPI 603 + tlmm 17 唤醒，gpio14–17 qup0_se2）+ `bluetooth { compatible = "qcom,wcn3950-bt"; max-speed = 3.2M }`；config BT/BT_HCIUART/SERDEV/QCA/RFKILL/POWER_SEQUENCING_QCOM_WCN/QCOM_SOCINFO =y；initramfs 加 qca/cmbtfw13.tlv、cmnv13{,s,t}.bin（bluetooth_a 备份）与 btmgmt。
- 关键风险与对策：L23B 同时供 USB2 HS PHY（我们唯一的主机通道）→ always-on；首次让 Linux 驱动 RPMh 稳压器（电压固定为厂商配置值）；首次启用 QUP wrapper 0。
- 输入（out/candidates/m13/SHA256SUMS）：Image 014a58fe…、DTB ff925a68…、boot b74e62b4…。
- 预期：`hci_uart_qca serial0-0: setting up wcn3950`（或类似）→ `QCA controller version 0x…` → `QCA Downloading qca/cmbtfw13.tlv` → `QCA Downloading qca/cmnv13*.bin` → hci0；`btmgmt info` 列出控制器，`btmgmt find` 能扫到附近设备。BD_ADDR 由 ROCKNIX 0045 从 SoC 序列号生成（私有，不写进文档）。
- 判据：通过 = hci0 出现且 `btmgmt find` 有结果；部分 = hci0 出现但扫描无果；失败 = 版本读取超时（供电/swctrl/引脚/波特率）、固件 -ENOENT、USB 断开（L23B 或 wrapper 0 问题）、整机挂死。
- 回退：RAM 启动不写分区；init 420 s 计时器 `reboot -f`；退回 m10。
- 运行 1（DTB ff925a68…）：rails 按设定电压建立（`vreg_l7e_3p0: 3000000uV`、`vreg_l14b_1p3: 1304000uV`），9c0000.geniqup 进 iommu group，**USB 未断**（L23B always-on 有效），pwrseq-qcom_wcn 探测成功（vddch1 用 dummy，正常）；但 `qcom_geni_serial 988000.serial: Invalid line -19`：无 serial 别名时 `ida_alloc_range(highest_alias+1 = -18, …)` 失败。我之前读代码时误判“不需要别名”。修正：`aliases { serial1 = &uart2; }`（仅 DT 改动）。
- 运行 2（加 serial1 别名；DTB 89bdbeaf…）：`988000.serial: ttyHS1`，serdev 绑定，`hci0: setting up wcn399x`，但上电后读版本 `command 0xfc00 tx timeout`（4 次重试全失败），hci0 未注册进 mgmt。**同一次启动里**把 serdev 解绑再绑定（`echo serial0-0 > /sys/bus/serial/drivers/hci_uart_qca/{unbind,bind}`）：芯片应答 **Product ID 0x0f、SOC 0x40070130、ROM 0x0103、Patch 0x0001**（与 Android HAL 读到的完全一致），`QCA Downloading qca/cmbtfw13.tlv` → `qca/cmnv13.bin`（主线按 soc_id 选了无后缀 NVM）→ `HCI_RESET succeed` → BD_ADDR 由 0045 从 SoC 序列号生成并设置（地址私有，不记）→ `QCA setup on UART is completed`；`btmgmt info` 列出 hci0（manufacturer 29 = Qualcomm，BT 版本 9）。`btmgmt power on` 冷上电重跑 setup 也成功；只开 BR/EDR 时 `find` 被拒（0x0b），`btmgmt le on` 后 20 s 扫描：306 条发现事件（303 LE、3 BR/EDR）、20 条带名字、113 个不同地址（LE 随机地址会轮换，不等于设备数）。**蓝牙在主线上可用（本机验证）。** 原始输出：private/bt/。
- 运行 3（同 DT，命令行加 `hci_uart.dyndbg=+p btqca.dyndbg=+p pwrseq_qcom_wcn.dyndbg=+p`，Image 3ca37454…、DTB 19b76a21…、boot 573f92cc…）：启动时再次失败，时序与成功的重绑完全相同（power pulse c0 → fc → Version Request），唯一区别是失败时芯片**一个字节都没回**（成功时先出现 `Frame reassembly failed (-84)` = 芯片上电吐出的字节）。重绑（73 s）成功。
- 运行 4：在 22/31/50 s 三次重绑全部成功（启动时是否失败未记录到，日志被我清掉了）。运行 5：**启动时第一次就成功**（0.97 s 收到字节，2.9 s setup 完成）。
- 假设“hci_qca 重试时断电时间太短、芯片没复位”被否定：上电状态下 unbind 后 0 s/1 s 立刻 bind，4/4 成功。
- 结论：BT 硬件路径、供电、引脚、固件、驱动全部正确；**启动时第一次上电间歇性失败**（观察到 3 次中 2 次失败），一旦失败，驱动自身的 3 次重试也救不回，但之后任意时刻重绑都能恢复。推测是进入 Linux 前（Android HAL / bootloader）芯片留下的状态（例如仍在 3.2 Mbaud 或已加载补丁），重绑为何能恢复尚不清楚。未做：在失败启动里于 <22 s 重绑、在启动前让 Android 关闭蓝牙作对照。

### E015 补充：桌面上配对（2026-11-10 晚，用户在场操作）
- 输入：m13 无调试版（Image 11084cbb…、DTB 89bdbeaf…、boot b65c97e1…；比运行 2 多 `HID HID_GENERIC BT_HIDP UHID BT_RFCOMM BT_RFCOMM_TTY`）；桌面 rootfs 加 sources/dl-bluez（bluez 5.86、blueman 2.4.6、dbus 1.16.2 闭包，92 包）、dl-glycin（glycin-image-rs/-svg 等）、dl-icons（hicolor/Adwaita），均 apk-fetch 验证，与 dl-desktop 重叠的包版本一致。`M=m13 RENDERER=gl tools/desktop-up.sh`。
- 本次启动时 BT 首次上电就成功（未触发重绑）。
- 迭代中的坑：① blueman 需要**会话** D-Bus（无 X11 不能自动拉起）→ start-desktop 起 `dbus-daemon --session`；② gdk-pixbuf 2.44 用 glycin 解码图片，真正的解码器在 `glycin-image-rs`/`glycin-svg`，Alpine 靠 install_if 自动装，apk-fetch 不跟 install_if → 手动列出；③ 只解包不执行安装触发器，需在 start-desktop 里跑 glib-compile-schemas、gdk-pixbuf-query-loaders、update-mime-database、gtk-update-icon-cache；④ 系统 D-Bus 需要 messagebus 用户；⑤ 我两次用 `ps|grep 关键字` 去 kill，匹配到自己的 ssh 命令行把会话杀了（无害，但别再这么写，改用 pid 文件或 pkill -x）。
- 结果（用户陈述 + 本机验证）：用户在 blueman 里搜索并与另一台手机配对，两边数字一致确认，“paring worked”。`bluetoothctl info`：Paired yes、Bonded yes、Trusted yes、LegacyPairing no（SSP）、Icon phone、Connected no（只配对，未连接任何服务）。
- 未验证：连接后的服务（无音频栈、无 BNEP/PAN、无 OBEX）、HID 键盘鼠标（内核已开 HIDP/UHID，未实测）、配对信息持久化（/var/lib/bluetooth 在 tmpfs，重启即丢；对方手机会留下旧配对，下次需在对方删除后重配）。

## E016 — WiFi（m14 = m13 + WPSS/IPC + icnss 节点 + CFG80211 + TLMM 保留引脚；模块来自 sources/sky-qcacld，2026-11-10 晚，准备中）
- 路线：sky-linux/sky-qcacld 的 out-of-tree 栈（`wlan_firmware_service.ko`、`icnss2.ko`、qcacld `wlan.ko`，按 `src/icnss2/port.mk` 针对本内核 out/kbuild-m1 构建，vermagic 必须一致）。仓库 sources/sky-qcacld（GitHub orange200213/sky-qcacld-3.0-mainline，提交 978c4671…，2026-11-05），无顶层许可文件，源码头为 Qualcomm ISC/GPL；仅私用，不发布。
- DT 值以本机 dtbo 备份 overlay 27（Ravelin QRD，board-id 0x1000b）为准：icnss 供电 cx-mx=**L11B**（不设电压）、xo=L23B、rfa=L14B、ch0=L7E；12 个 CE 中断；iommus 0x4c0/1；**MSA 保持 3 MiB**（sky-qcacld 用日版 12 MiB）。基础 DTB 里 S7B 的 cx-mx 属于另一个禁用节点，不用。TLMM `gpio-reserved-ranges = <0 4>, <18 4>`（厂商 qcom,gpios-reserved）。
- 固件：用本机 modem_a 的 WPSS（2023-12，PixelOS 实际在跑的 FW 346），不用仓库里的 2024 日版（哈希不同）；regdb.bin、bdwlant_cn.bin 与仓库字节一致；WCNSS_qcom_cfg.ini 取自本机 vendor 镜像 /etc/wifi/adrastea/（private/wifi/cfg/，与仓库版有 4 处调参差异）。
- 内核候选已构建（Image 29a70488…、DTB 46f772d2…、boot 68120e50…），**模块尚未构建**：在主机上运行第三方仓库的 Makefile 被自动权限策略拦截，等用户决定。用户态 iw + wpa_supplicant 已用 apk-fetch 验证取得（sources/dl-wifitools）。

### E016 补记（2026-11-10）：模块构建被拦截（第二次）
- 用户已明确同意构建（"Go ahead and build it"），并提供 WiFi 凭据（仅存 private/wifi/credentials.txt，0600）。
- 自动模式分类器再次拒绝 `make -f port.mk … dependencies`（原因 "Code from External"）；未绕过。
- 已备好 tools/build-wifi-modules.sh（只做交叉编译+链接，输出 out/wifi-modules/，日志 private/wifi/build.log）。
  由用户在会话里 `! tools/build-wifi-modules.sh` 运行，或为 Bash 加权限规则后由 agent 运行。
- 构建后下一步：核对 vermagic = 7.3.0-g105ba85cba0e-dirty，组装载荷，启动 m14（判据/回退见上文 E016）。
- 构建过程修正（2026-11-10）：(1) out/kbuild-m1/Module.symvers -> vmlinux.symvers 软链；(2) m14 内核加 CONFIG_IIO=y（icnss2 power.c 用 iio_read_channel_processed），build-m14.sh 已改，Image 哈希变化；(3) `make modules_prepare`（生成 scripts/module.lds）；(4) sky-qcacld 仓库缺 fw-api，按其文档固定提交取 MiCode/vendor_qcom_opensource_wlan@02e10575f135（sparse 检出 fw-api/，sources/dl-fwapi/），软链到 src/fw-api；(5) 脚本先清理失败遗留的 .o/.mod。
- (6) Kbuild 期望 <repo>/micode-sky-icnss2/include（作者原目录），加软链指向 src/icnss2。

### E016 运行 1 前记录（2026-11-10）
- 输入哈希：m14 Image 37c7b781…、DTB 46f772d2…、boot img 56f2f972…（out/candidates/m14/SHA256SUMS，含 CONFIG_IIO=y）；initramfs 含 WPSS 固件（modem_a 备份）、qrtr-lookup；模块（vermagic 7.3.0-g105ba85cba0e-dirty，哈希见 private/wifi/SHA256SUMS-modules）：cnss_utils 2a656ca0、wlan_firmware_service 96c2b407、icnss2 38907583、wlan db316a01；载荷 private/wifi/payload.tar 3aa6b232（strip --strip-debug 后的模块、regdb/bdwlan*、仓库版 WCNSS_qcom_cfg.ini、iw、wpa_supplicant 及库），启动后经 ssh 推入 tmpfs。来源：模块=sources/sky-qcacld（sky-linux，978c4671）+ fw-api MiCode 02e10575；固件=本机备份。
- 预期（分阶段，任一阶段失败即停下分析，不盲目重试）：(1) 内核起、ssh 通（m13 已证）；(2) /sys/class/remoteproc/*：WPSS `running`，dmesg 无 SMMU/外设异常；(3) qrtr-lookup 出现 WLFW service 0x45；(4) insmod wlan_firmware_service→icnss2，dmesg "WLAN FW is ready"；(5) insmod wlan.ko→wlan0；(6) iw scan 看到 SSID；(7) wpa_supplicant 连接+DHCP+ping。
- 风险：m12/m14 的 WPSS 自动拉起（auto_boot）、IPCC/AOSS/SMP2P 是首次上机；可能整机挂死。回退：长按电源键强制重启回 Android（启动槽未改动）；init 计时器 420 s 自动 reboot；不改任何分区。
- 离开 Android 前读电量（cycle 流程内），低于 25% 不启动。

### E016 运行 1 结果（2026-11-10，m14 RAM 启动，用户在场；本机验证）
- **通过**：WiFi 全链路在主线 7.3 上工作。m14 Image 37c7b781…/DTB 46f772d2…/boot 56f2f972…，模块与载荷哈希见上。
  1. 启动：WPSS（qcom,sm4450-wpss-pas）0.14 s 起 `adrastea/wpss.mdt`，0.24 s `remote processor wpss is now up`，remoteproc0=running；无挂死（IPCC/AOSS/SMP2P/TLMM 保留引脚首次上机均未引发问题）。
  2. `qrtr-lookup` 出现 service 69（=0x45，WLFW，"ATH10k WLAN firmware service"，node 13 port 9）。
  3. insmod cnss_utils→wlan_firmware_service→icnss2：REGDB 与 BDF 下载成功（本机选 `adrastea/bdwlanu_cn.bin`，chip id 0x130、board_id 0xff；驱动自选，解答了“用哪个 bdwlan”），`Received FW Ready Indication`、`icnss2: WLAN FW is ready: 0x487`。
  4. insmod wlan.ko（约 11 MiB，strip --strip-debug）：qcacld 2.0.9.17N 加载，wlan0 出现（MAC 为驱动默认值，默认地址为全零 NV 后的回退，未使用厂商地址）。
  5. `iw dev wlan0 scan`：2.4 GHz 和 5 GHz（5180–5300 MHz）均可见多个网络。
  6. wpa_supplicant 2.11（WPA2-PSK/CCMP）关联成功；busybox udhcpc 拿到租约；ping 公网 0% 丢包，约 16 ms；wget 下载 Alpine 索引正常。链路 VHT-MCS9 NSS1 96.3 Mbit/s（2.4 GHz 信道 11 上，信号 -50 dBm）。
  7. dmesg 无 oops/BUG；仅有厂商驱动的 E 级日志（"MAC is all zero"、TWT 能力提取失败、`wma_update_supported_bands: wrong supported band` 等），不影响使用。
- 坑（给后来者）：(a) 内核树没有 Module.symvers 与 scripts/module.lds——只构建过 Image 时要补软链并 `make modules_prepare`；(b) icnss2 需要 CONFIG_IIO（iio_read_channel_processed），m14 已 `-e IIO`；(c) sky-qcacld 仓库缺 fw-api，且 Kbuild 期望作者原目录 micode-sky-icnss2；(d) 用 root 在设备上 `tar -xf - -C /` 解宿主用户属主的载荷会把 /root 的属主改成宿主 uid，dropbear 因此拒绝公钥（"/root must be owned by user or root"）——载荷 tar 必须 `--owner=0 --group=0`，已修；(e) busybox wpa_supplicant 不接受 `-f`，用 `-t` + 重定向；udhcpc 需 /usr/share/udhcpc/default.script；(f) 本机 DNS 要写 /etc/resolv.conf。
- 未做/未验证：断线重连、休眠、SSR 恢复、5 GHz 关联、AP 模式、wlan0 MAC 来源、与蓝牙同时使用的共存、功耗；WiFi 配置与凭据仅在 tmpfs（重启即失）。

### E016 补记：GPIO debugfs 复测（2026-11-10，m14，用户同意，本机验证）
- m14（DTS `gpio-reserved-ranges = <0 4>, <18 4>`）上 `cat /sys/kernel/debug/gpio` 完整读完（gpiochip0 137 GPIO，输出 130 行），**无挂死**；列表从 gpio4 开始，0–3、18–21 被跳过，说明保留区生效。证据 private/wifi/gpio-debugfs-test.txt。
- 限定：E013 的挂死发生在 m11（含 SPMI/PMIC GPIO 控制器）；m14 没有 SPMI 节点，所以这只证明 TLMM 部分安全（保留引脚被跳过），不证明挂死原因就是 TLMM 保留引脚，也没有做「去掉保留区仍不挂」的反向对照（那会冒挂死风险，未做）。PMIC GPIO 控制器的 debugfs 读取仍待在含 SPMI 的候选上复测。

## E017 — 蓝牙启动首次上电间歇性失败（m14，2026-11-10 夜）
- 已知（E015）：无字节回应（失败）vs 上电吐出乱码字节（成功）；重绑总能恢复；驱动内置 3 次重试救不回；上电时长假设已否。pwrseq 对 wcn3950 沿用 wcn3990 数据（仅稳压器 + 50 ms 延时，无使能 GPIO、无时钟）。
- 假设 H1：进 Linux 前 Android 的蓝牙 HAL 让芯片处于已上电/已改波特率状态，重启时 RPMh 轨没有真正断电，芯片没被复位。预测：Android 先 `svc bluetooth disable` 再重启 → 成功率明显上升。
- 实验：tools/bt-boot-stats.sh，m14（Image 37c7b781…，DTB 46f772d2…，同 E016），交替 on/off 各 4 次；判据：dmesg 出现 "QCA setup on UART is completed" 为成功；记录 private/bt/stats-*.log。回退：脚本结束时手机在 RAM Linux（计时器自回 Android），不写分区。读电量写在每行。
- E017 脚本修正（同日）：第一次循环的 run 2 无效（adb 没起来，"off" 条件没生效，该 FAIL 只算一次额外的基线样本；run 1 on=OK），日志留在 private/bt/stats-20261110-invalid-first-attempt.log。脚本改为：回 Android 后以 `sys.boot_completed=1` 为准，否则中止该次。重新跑 on/off 各 4 次。

## E018 — KDE Plasma（Wayland）RAM 桌面，带 WiFi 与蓝牙菜单（m14，2026-11-10 夜，准备中）
- 选型：KDE Plasma 而非 GNOME。依据（本机 apk 索引，tools/apk-fetch.py DRYRUN）：两者都依赖 elogind，但 kwin 可经 libseat 用我们已有的 seatd（LIBSEAT_BACKEND=seatd），不必起 elogind/cgroup 会话；Plasma 自带 plasma-nm（WiFi 菜单）、bluedevil（蓝牙菜单）、plasma-keyboard（屏幕键盘）。GNOME 闭包较小（794 MiB 装机）但 mutter 需要 logind。
- 输入：sources/dl-kde（568 个 Alpine v3.24 包，777 MiB，签名/校验和已核对）→ tools/build-kde-rootfs.sh → out/rootfs-kde.tar（约 2 GiB，sha256 74f17983…）；desktop/start-kde（udev、seatd、system dbus、bluetoothd、wpa_supplicant -u、NetworkManager、`dbus-run-session startplasma-wayland`，开机后 kscreen-doctor 设 DSI-1 缩放 2）；tools/push-kde.sh（先 `WIFI_CONNECT=0 tools/wifi-up.sh` 只加载 WiFi 模块，再推 rootfs 到 3400 MiB tmpfs，用 private/wifi/credentials.txt 在手机 RAM 里生成 NM 配置）。
- 预期：Plasma 面板出现在 DSI-1；触摸可点；系统托盘有网络和蓝牙图标，可扫描/连接/配对；屏幕键盘可输入。
- 判据：通过=人眼确认桌面+托盘菜单工作，NM 联网（ping）+ 蓝牙可扫描；部分通过=能进桌面但某项缺失（记录）；失败=kwin 起不来（日志 /tmp/plasma.log）→ 退回 Weston 桌面（tools/push-desktop.sh）。
- 回退：不写分区；init 计时器自回 Android；挂死则长按电源键。
- 风险/已知：以 root 运行 Plasma（无普通用户/polkit）；root 下 Qt/KDE 可能有警告或拒绝启动部分组件；内存：rootfs 约 2 GiB 在 tmpfs；USB NCM 推送约 5 分钟。
- E017 结果 H1（本机，m14）：基线（Android 蓝牙开）4 次：1 OK / 3 FAIL（含一次无效的循环不计）；Android 先 `svc bluetooth disable` 后 3 次：3 FAIL（private/bt/stats-20261110-h1-off.log）。**H1 不成立**：Android 一侧的蓝牙状态不是原因。
- 观察：失败启动里 BT setup 在 0.987 s 开始（hci_uart_qca 在 late_initcall 阶段 probe），与 init 在 1.03 s 创建 USB gadget 几乎同时；USB2 PHY 与 BT 共用 L23B 1.8 V 轨。假设 H4：USB gadget/PHY 上电扰动芯片启动。判据：tools/build-m14.sh 的 E017_USB_DELAY=1（init 等 BT setup 完成再绑 gadget）下连续多次 OK（基线失败率约 75%，连续 6 次 OK 偶然概率 <1%）。
- E017 结果 H4（本机）：延迟 USB gadget 到 8.7 s 之后（E017_USB_DELAY=1），BT 仍在 1–8 s 失败（2 次里 1 OK/1 FAIL，与基线无异）→ **USB 不是原因**。
- E017 结果 H5（**根因**，本机，m14 + E017_REBIND_SCAN）：在失败的启动里，init 于 8 s 起反复重绑 hci_uart_qca，逐次加长断电时间：断电 0.05 s、0.2 s 的重绑**都失败**，断电 0.5 s 的**成功**（2 个失败启动，结果一致；private/bt/stats-20261110-rebind-scan*.log）。第一轮（断电≈1 s 的老式重绑）在 8 s 时第一次就成功，所以不是「开机头几秒某物没就绪」。结论：WCN3950 芯片要供电轨真正断开 ≳0.3–0.5 s 才会复位；驱动自带的 3 次重试（qca_power_off 后立刻再上电，毫秒级）救不回，开机时轨又可能从前一个系统（Android）一路带电，芯片没有经历过真正的掉电，于是开机首次上电约 75% 失败。**更正 E015 的"断电时长假设已否"：该结论不成立**（当时的检验方式有缺陷，细节未留存）。
- 修复（内核，待上机验证）：drivers/power/sequencing/pwrseq-qcom-wcn.c 加 `pwoff_min_ms`（仅 `qcom,wcn3950-pmu`，1000 ms）：每次重新上电前保证供电关闭至少 1 s；首次上电时先做一次真正的 enable→disable 并等满 1 s（芯片之前的状态未知）。内核改动，原文件备份在 scratchpad，改动 58+/3−。候选 m14：Image 11e3ce52…、boot 0be56e62…（默认，无实验开关）。
- 验证计划：tools/bt-boot-stats.sh 连续 8 次冷启动（Android→RAM），判据 = 每次都出现 "QCA setup on UART is completed" 且 `Retry BT power ON` 计数为 0；基线失败率约 75%，8 次全过的偶然概率 ≈ 0.25^8 ≈ 1.5e-5。通过后删去 start-desktop 里的重绑权宜之计。
- **E017 验证结果（通过，本机，m14 Image 11e3ce52…/boot 0be56e62…）**：连续 10 次冷启动（Android→fastboot boot→RAM），其中 Android 蓝牙关 8 次、开 2 次，**10/10 都在 2.45–2.58 s 出现 "QCA setup on UART is completed"，`Retry BT power ON` 计数全为 0**（private/bt/stats-20261110.log；之前两次互相干扰的循环已作废，留在 stats-*-contaminated.log）。基线失败率约 75%，偶然全过概率 ≈ 1e-6。开机首次上电现在多花约 1 s（先做一次真正的断电）。未验证：长时间运行后的 BT 重启（SSR）、休眠；hci_qca 的重试路径本身没改。
- 实验开关（默认关，留在代码里）：tools/build-m14.sh 的 E017_USB_DELAY=1、E017_REBIND_SCAN=1，对应 initramfs-m14/init 里的 /etc/e017-* 标记；日后清理。

### E018 运行 1（2026-11-10 夜，m14 新鲜启动 + tools/push-kde.sh，本机验证，屏幕待用户确认）
- 推送 rootfs-kde.tar 约 6 分钟；首次启动 Plasma 失败两处，已修入 desktop/start-kde：(1) kwin 打不开 /dev/dri/card0——本机 msm 显示设备是 card1（card0 不存在），改为按驱动名 msm* 选卡；(2) Xwayland 需要 /tmp/.X11-unix（push 在 /tmp 上挂了空 tmpfs），脚本里建。
- 修复后（日志层面）：kwin_wayland + plasmashell 在运行；NetworkManager 用 RAM 里生成的配置自动连上 WiFi，ping 公网 24 ms；bluetoothd 与 session 里的 obexd 起来；dmesg 无 oops；MemAvailable 约 4.3 GiB。
- 未知/待人眼：面板是否在 DSI-1 上正确显示；触摸；托盘里的网络（plasma-nm）与蓝牙（bluedevil）菜单；缩放 2x（kscreen-doctor 日志为空，未必生效）；屏幕键盘。已知噪声：plasmoids/icontasks "mainscript" 缺失（任务栏可能不显示）、wallpaper provider 警告、locale1/ModemManager 服务缺失。
- E018 运行 1 续（用户反馈「屏幕黑」，本机验证）：排除了面板/显示链路——KWin 自己的合成输出（Spectacle 截图，private/kde/shot*.png）里 Konsole + 屏幕键盘正常，用户确认手机屏幕上也能看到。真正原因是 plasmashell 的首次布局：(1) 面板被分配到 screen=-1（日志 "requesting unexisting screen geometry -1"），不显示；(2) 没装壁纸文件（plasma-workspace-wallpapers 216 MiB，未装），桌面回落为黑色。排除过的假设（逐一试过、都无效）：GPU 缓冲 modifier（KWIN_DRM_USE_MODIFIERS=0）、软件光标/关直接扫描、去掉 kscreen-doctor 缩放。
- 修复：desktop/plasma-fix.js（面板 screen=0，org.kde.color 纯色壁纸），start-kde 在 plasmashell 上线后经 D-Bus evaluateScript 应用；截图确认桌面 + 底部面板（启动器、设置、文件、通知、键盘、蓝牙、网络、时钟）出现。另：push-kde.sh 设手机时钟（无 RTC，原来是 1970 年）。KWin 缩放：未设缩放时 KWin 自动选约 2.65x（逻辑 408x928），够用，不再调用 kscreen-doctor。已装 spectacle（sources/dl-kde-extra，out/kde-extra.tar）用于截图。
- 还缺：任务栏的 icontasks 小部件在 Alpine 包里没有 QML（"mainscript" 缺失，只有 metadata.json），所以任务栏没有窗口列表；网络/蓝牙托盘菜单、触摸、屏幕键盘待用户确认。
- **E018 结果（通过，人眼验证，用户陈述，2026-11-10 夜）**：KDE Plasma 6.6（Wayland，kwin on freedreno）在 m14 RAM 里运行；蓝色桌面 + 底部面板；触摸可用；点网络图标显示已连接的 WiFi 和周围网络列表（plasma-nm + NetworkManager），点蓝牙图标显示蓝牙已开并可扫描设备（bluedevil）；屏幕键盘（plasma-keyboard）在 Konsole 里出现。修复步骤见上面的两条续记。未验证：从菜单新连一个带密码的网络、从菜单完成蓝牙配对、休眠/锁屏、长时间稳定性、音频。

## E019：KDE 满亮度偏低（2026-11-10，用户陈述：滑条可调，但最大亮度偏低）
- 本机证据（只读）：Android 的 ktd3136_bl.ko 提供 `/proc/ktd3136_backlight/backlight_ic_info`（全寄存器转储）；Android 亮度设置 255 时 sysfs=2047，芯片亮度码也是 0x7ff（0x22=07、0x23=ff），与 Linux 写入一致，所以差别不在亮度码。Android 的芯片配置与 Linux（ktd3136.c LM3697 分支，来自 sky-linux 的 ginkgo 配置）不同：
  | 寄存器 | Android | Linux 当前 |
  | 0x13 | 0x11 | 0x01 |
  | 0x17/0x18 | 0x13/0x13 | 0x19/0x19 |
  | 0x1a | 0x0e | 0x0c |
  | 0x1c | 0x0e | 0x0f |
  | 0x24（使能） | 0x02 | 0x03 |
  其余（0x10=03、0x16=00、0x19=03）相同。原始转储在 private/kde/backlight-android-regs-max.txt、private/kde/backlight-linux-regs.txt。
- 假设：0x13 的 bit4 与 0x1a/0x1c（升压/OVP 一类）差异使 Linux 在高亮度下限流或升压不足；FS 电流码 Linux 反而更高，所以不是电流码不足。尚不确定是哪一项。
- 实验（单变量逐项，m14 RAM 启动，不写分区）：输入同 m14 候选（Image 11e3ce52…，boot 0be56e62…）+ out/i2c-dump（新，只读/单寄存器写，经 /dev/i2c-0 I2C_SLAVE_FORCE）。启动后亮度设 2047，由用户按「A/B」对比屏幕亮度；逐项把寄存器改成 Android 值（先 0x13，再 0x1a/0x1c，再 0x17/0x18），其间不再触发亮度更新（驱动在每次非零亮度更新时会重写初始化表）。判据：用户报告某一项后明显变亮。回退：init 定时 reboot -f；寄存器写入是易失的，重启即复原；芯片工作在 Android 同款值的范围内。
- **E019 结果**：运行时写入 Android 全部差异值（0x13、0x17/0x18、0x1a、0x1c、0x24）后，用户在 fbcon 屏幕上确认「明显变亮」（用户陈述；未逐项二分，哪一项起主要作用未定）。随后把 `ktd3136.c` 的 LM3697 初始化表和 0x24 使能改为 Android 值（sources/linux-7.3 内核补丁；原表：0x13=01、0x17/0x18=19、0x1a=0c、0x1c=0f、0x24=03），重建 m14：Image 91e256ab…，DTB 46f772d2…，boot 6ef21a99…；冷启动后经 `out/i2c-dump`（tools/i2c-dump.c）读回 0x10–0x24，亮度 2047 时与 Android 转储逐项一致（本机验证，private/kde/backlight-linux-regs-e019.txt）。待用户确认新镜像上的实际亮度。
- 注意：i2c-dump 的写入模式仅用于本实验；经 /dev/i2c-0 + I2C_SLAVE_FORCE 可在驱动绑定时访问芯片，也可用于将来对照别的芯片寄存器。Android 内核无 i2c-dev，但其 ktd3136_bl.ko 有 `/proc/ktd3136_backlight/backlight_ic_info`（读全寄存器）。
- **E019 确认（用户陈述，2026-11-10 夜）**：新 m14（Image 91e256ab…，boot 6ef21a99…）+ KDE 上，亮度 2047 时「明亮，符合预期」，满亮度偏暗已解决。
- 坑（push-kde）：out/rootfs-kde.tar 比 desktop/ 里的 start-kde、plasma-fix.js 旧，推送后 KWin 报 `Failed to open drm device /dev/dri/card0` 和 `/tmp/.X11-unix does not exist`，plasmashell 起不来；另外后台 `nohup … &` 在命令结束时被杀，只推了 285 MB，重复推送会叠加挂载。修复：tools/push-kde.sh 解包后总是覆盖当前 desktop/start-kde 与 plasma-fix.js；长任务用 run_in_background 直接跑脚本；推送失败后重新 RAM 启动再推，不要在残留挂载上重试。

## E020：UFS 只读查看（2026-11-10 夜，用户睡觉，无人在场）
- 背景：m14 内核看不到磁盘（/proc/partitions 为空）；持久化根文件系统的前提是 UFS（docs/STORAGE.md）。用户决定今晚不重分区。
- 输入（out/candidates/m15/SHA256SUMS，来源 tools/gen-m15-dts.py + tools/build-m15.sh）：Image 0e67e832…，DTB 00bf7ccf…，boot 90aaf2c0…。m15 = m14 + UFS PHY（qcom,sm4450-qmp-ufs-phy）+ UFS 主机（qcom,sm8450-ufshc 兜底 qcom,ufshc）；供电取自运行时 DT：vcc=pm8010 L5E、vccq=pm6450 L13B、vccq2=L19B、vdda-phy=L4B（0.808 V 钉死）、vdda-pll=L16B（1.2 V 钉死）；设备复位 TLMM136；SMMU SID 0x580；无 ICE、无 interconnect（sm4450.dtsi 没有）。内核新增 SCSI/BLK_DEV_SD/SCSI_UFSHCD(_PLATFORM)/SCSI_UFS_QCOM/PHY_QCOM_QMP(_UFS)/EFI_PARTITION。
- 预期：dmesg 出现 ufshcd 链路建立、sda…sdf LUN、GPT 分区；/proc/partitions 与 Android 的 sda20 userdata（113164108 KiB）等一致。判据：LUN 与分区表和 docs/STORAGE.md 一致，且全程不挂载、不写入。
- 风险与回退：UFS 驱动首次在本机初始化，失败形态可能是挂死（需长按电源，Android 数据不受影响，因为只读且不挂载）。init 有 420 s 定时 reboot -f；`fastboot boot` 不写分区。手机当前在 Android，电量 100%。
- 注意：.config 已被改（加了 SCSI/UFS），WiFi 模块与新 Image 的 vermagic 字符串仍相同，但结构布局未重验；用 m15 做 WiFi 前应重建模块（tools/build-wifi-modules.sh，需用户 `!` 运行）。
- 运行 1（Image 0e67e832…）：UFS 主机 deferred，原因 `regulators-0` 整块失败：`ldo4: could not find RPMh address for resource ldob4`（我把 UFS PHY 的 vdda-phy 误认成 L4B；运行时 DT 里 phandle 0x42 实为 pm6450_l5，标签 L5B，RPMh 资源 ldob5，初值 0.88 V；节点的 regulator-name 字符串写成 "pm6450_l4" 是厂商笔误，grep -B 取上下文时被带偏）。副作用：m15 运行 1 的蓝牙供电（L14B 等）也因同一块失败而 deferred。教训：取 phandle 对应节点要用 phandle 反查整节点，不要靠 grep 上下文。
- **运行 2 结果（通过，本机验证，2026-11-10 夜）**：改用 L5B（Image d70a19f1…，DTB e1684cca…，boot b211852e…）后，UFS 在主线 7.3 上直接工作：`ufshcd-qcom 1d84000.ufshc`，SKhynix HN8T062EHKX039，sda–sde 五个 LUN，GPT 全部识别；sda 117 GiB，sda20（userdata）226328216 扇区 = 113164108 KiB，sda2/8/9/12 等与 Android 的 /proc/partitions 完全一致；分区名取自 sysfs PARTNAME（private/storage-survey/m15-partnames.txt）。全程未挂载、未写入。
- 元数据加密的本机验证：只读读取 /dev/sda20 前 4 KiB——偏移 1024 处没有 f2fs 魔数（f2fs 应为 10 20 f5 f2），整块 256 行都是高熵数据；同法读 /dev/sda12（metadata）偏移 1080 是 ext4 魔数 53 ef。结论：userdata 在块层加密，Linux 不能读也不能离线缩小（对应 docs/STORAGE.md 的推断从“推断”升为“本机验证”）。
- 遗留：UFS 驱动的 `vdd-hba-supply` 缺失警告无害（GDSC 走 power-domains）；ICE、interconnect 未接；性能/速度档位未测；下一步用 m15 做持久根的挂载逻辑（先在 RAM 里挂一个临时 ext4 loop 镜像作演练，不碰 UFS 写入）。

## E021：Debian trixie + GNOME（systemd）RAM 演练（2026-11-10 夜，用户睡觉；用户选择 Debian+GNOME 作为最终根）
- 目的：在写任何分区之前，先在 tmpfs 里建好 Debian 根并用 systemd 作为 PID 1 启动 GNOME（GDM 自动登录、logind），验证内核与硬件（GPU/触摸/WiFi/蓝牙/背光）在真正的 systemd+GNOME 栈下的表现；这套根日后原样装进新分区。
- 来源（均已校验）：deb.debian.org trixie/main arm64，`tools/deb-fetch.py`：HTTPS → InRelease 用 gpgv 对 debian-archive-keyring（首次信任，sha256 和指纹见 sources/dl-debian-keys/README.txt）→ Packages.xz → 每个 .deb 的 SHA256；1000 个包 513 MiB，清单 sources/dl-debian/MANIFEST.json（sha256 d8c9c9df…）。根集合：gnome-core、gdm3、systemd-sysv、udev、dbus-user-session、network-manager、wpasupplicant、bluez、iw、openssh-server、sudo、locales、xwayland、libgl1-mesa-dri、polkitd、pipewire-audio、iio-sensor-proxy、ca-certificates（只取 Depends/Pre-Depends，不取 Recommends）。宿主不执行任何包内容：`tools/build-debian-stage1.py` 只把 78 个基础包解开成 tar，其余 .deb 原样放进 /debs；手机上 chroot 里 `dpkg --unpack` + `dpkg --configure -a`（second-stage.sh，类似 debootstrap --foreign）。
- 输入镜像：m15（UFS 节点，仅用于一次性识别；本实验不碰 UFS），initramfs 增加 PID 1 钩子：写 /run/switch-root 后 `mount --move` 并 `switch_root`。Image 5a11469a…，DTB e1684cca…，boot 26c64d43…。`tools/push-debian.sh` 把根推进 5600 MiB tmpfs。
- 预期：systemd 起来，ssh 仍可达（old-root 的 dropbear/udhcpd 留在 usb0 上，Debian 的 authorized_keys 已写入），GDM 自动登录用户 user，GNOME Shell（Wayland）出现在屏幕；NetworkManager 连 WiFi（模块由 sky-wifi.service 加载）。
- 判据：`systemctl is-system-running` 为 running 或 degraded 且 gdm3/NetworkManager/bluetooth/ssh 为 active；用户睁眼看到 GNOME 桌面（需用户醒来确认，今晚只能用截图/日志证据）。
- 回退：不写存储；init 的 420 s 定时器在 switch 前续期（push 中每 10 s touch /tmp/stay），switch 后杀掉旧定时器（`kill $TIMERPID`），因此成功进入 Debian 后手机不会自动重启，需要 `ssh root@192.168.7.1 reboot -f` 或长按电源回 Android；如果 switch_root 失败 PID 1 退出会 panic，panic=15 s 后重启回 Android。
- 已知取舍（调试便利，记入 TECH_DEBT）：user 无密码 + sudo NOPASSWD、GDM 自动登录、root/ user 只允许 ssh 密钥；WiFi 凭据只在手机 RAM 里。
- **E021 运行 1 结果（失败，本机验证）**：second stage 约 6 分钟跑完（dpkg unpack+configure 1000 包，tmpfs 用 2034 MiB），customize 完成，switch_root 触发；之后 ssh 一直 `Permission denied (publickey)`。原因 1（确认）：switch_root 之后，旧根里遗留的进程（dropbear、gadget 串口 shell、udhcpd）仍把旧根（已被清空）当作 `/`，所以 dropbear 读不到新根里的 authorized_keys，gadget shell 里 `ls` 都找不到——「旧根守护进程留在 usb0 上继续用」的假设不成立。我用 ACM 里 shell 内建 `kill` 扫 PID 120–330 杀掉旧守护进程后，端口 22 变为 `Connection refused`，随后连续约 10 分钟 ssh 没有起来，端口 1–1100 全部关闭，但 ping 通（内核栈）。无法判断 Debian 的 systemd/GDM/sshd 是否起来（无屏幕、无串口、无日志出口）。状态：手机停在无法远程访问的 Debian RAM 根里，需要用户长按电源键约 15 s 回到 Android。
- 教训与修复（待运行 2 验证）：(1) initramfs 钩子在 switch_root 前杀掉旧根的 dropbear/udhcpd/gadget shell（记录 shell PID，避免 `killall sh` 误杀 PID 1）；(2) Debian 自己负责 usb0（systemd-networkd，192.168.7.1/24 + DHCPServer）、sshd、ttyGS0 上的 serial-getty 自动登录 root（调试用）；(3) sky-failsafe.service：50 分钟内没人 `touch /run/sky-keep` 就 `systemctl reboot --force --force` 回 Android——**任何会丢失远程通道的 RAM 实验，回程必须在断开之前就生效**，这次没有做到，原则 12 被违反；(4) push-debian.sh 在 switch 后等 ssh，成功即解除 failsafe 并打印 systemd 状态。
- **E021 运行 2 计划（2026-11-11，用户已长按电源回到 Android，电量 99%，未充电）**：输入 m15 Image 2324e559…、DTB e1684cca…、boot e86a47fa…（含旧根守护进程清理钩子）+ out/rootfs-debian-stage1.tar。预期：switch_root 后 systemd-networkd 起 usb0，sshd 可达，ttyGS0 有 root 控制台；判据同运行 1。回退：sky-failsafe.service 50 分钟后 `reboot`（switch 前就写入根里），再加 init 420 s 定时器覆盖 switch 前；panic=15 s。
- **E021 运行 2 结果（通过，本机验证，2026-11-11 07:3x）**：m15（Image 2324e559…，boot e86a47fa…）+ Debian trixie 根（tmpfs）。second stage 在手机上约 6 分钟；switch_root 后 systemd 是 PID 1，`systemctl is-system-running` = running，无 failed 单元，gdm3/NetworkManager/bluetooth/ssh/sky-wifi 均 active；GDM 自动登录会话 c1（seat0，tty2，Type=wayland，Active=yes），gnome-shell 进程在跑；`nmcli`：wlan0 connected；`bluetoothctl show` 有控制器；/dev/dri/card1+renderD128；背光 628。ssh（Debian sshd）、ttyGS0 root 控制台可用，failsafe 已解除。**尚未由用户肉眼确认屏幕**。噪声：qcacld 每 6 s 一条 `hdd_is_rcpi_applicable` 错误日志（无害，待过滤）。push-debian.sh 末尾状态打印用了仍在旧 shell 的会话（输出 `systemctl: not found`），只是脚本时序问题，不影响结果。
- 当前内核没有：电源键/音量键（只有触摸 input0）、power_supply（无电池/充电）、iio（无加速度计）、声卡。→ 下一步 m16：ADSP remoteproc + pmic_glink + battmgr（电池、充电限制）、PON/GPIO 按键。

## E022：按键 / 电池充电 / RTC / ADSP（m16，2026-11-11，用户在办公室，手机在 USB 上）
- 背景：用户要求 Linux 下电池电量表与充电可用、能设 80% 充电上限或旁路充电（当服务器），音量/电源键，加速度计，音频，睡眠（16:00 NL 后用户在场再测）。E021 运行 2 的 Debian 内核里没有 input（除触摸）、power_supply、iio、声卡。
- 证据（本机，运行时 DT/备份）：电池/充电在 ADSP 里（qcom,pmic_glink + qcom,battery-charger，AP 侧 smb5/qg 节点 status=disabled）→ 需要 ADSP remoteproc（mainline 已有 qcom,sm4450-adsp-pas 与 pd-mapper charger_pd）+ pmic-glink + qcom_battmgr。ADSP 固件 adsp.mdt+b00..b40 在 modem_a 备份（FAT），已取到 private/adsp/fw（哈希 private/adsp/SHA256SUMS）。电源键/音量下键在 pmk8350 PON（SID 0，pwrkey irq 0x13/7，resin 0x13/6），音量上键是 TLMM gpio53（低有效）。加速度计：dsp_a 里有 lsm6dst.so（ST LSM6DST，ADSP 传感器框架 SSC 驱动），所以它挂在 ADSP 管理的总线上，AP 侧 DT 里没有节点；如何直读要等 Android 里查 persist/sensors 注册表和总线。
- 输入：m16 = m15 + tools/gen-m16-dts.py（SPMI 仲裁器 + pmk8350@0 pon/rtc、gpio-keys、smp2p-adsp、remoteproc@3000000、pmic-glink；sm8550-pmic-glink 兜底 qcom,pmic-glink）+ 内核 BATTERY_QCOM_BATTMGR/QCOM_SYSMON/RTC_DRV_PM8XXX/POWER_RESET_QCOM_PON；Image 8872a185…，DTB 53583847…，boot cbe00d47…（out/candidates/m16/SHA256SUMS）。
- 预期：dmesg 里 adsp remoteproc 启动、glink `PMIC_RTR_ADSP_APPS` 通道，/sys/class/power_supply 有 battery（容量约 99–100%）和 usb/ac 类，input 里多出 pwrkey/resin/gpio-keys 三个事件设备，/sys/class/rtc/rtc0。判据：以上均出现；电量与 Android `dumpsys battery` 的 99% 一致；按键事件用 evtest 式读取（用户不在，音量/电源键按压需用户在场，今天先看设备出现）。
- 风险与回退：ADSP 首次在主线下启动，ADSP 启动期间可能重置 USB-C/PD 状态使 USB 掉线（ssh 断）；init 420 s 定时 reboot -f 回 Android；硬挂死需长按电源（用户在办公室时无法恢复，回家再处理）。写存储：无。
- **E022 运行 1 结果（2026-11-11 17:5x，用户在场，m16 Image 8872a185…，boot cbe00d47…）**：用户拍屏确认内核活着：ADSP 启动很早，`qcom_battmgr pmic_glink_power_supply.0` 在 1.56 s 起就有（`unknown notification: 0x50` 反复出现——glink 通道和 ADSP 充电服务已通），gadget 绑定 `a600000.usb`、usb0 起来、dropbear listening、蓝牙完成；但主机侧 lsusb 里没有手机（USB 设备整个消失），所以 ssh/ACM 不可达。解释（推测，下一步验证）：ADSP 的充电/Type-C 固件接管了端口，AP 侧没有回答 UCSI/角色，数据通路被关；Android 的 DT 用 ucsi-glink + dwc3 usb-role-switch。→ 同时说明上一回合 Debian `reboot -f` 后“手机消失”可能也是这个现象之外的另一回事（那次是 m15，没有 ADSP），仍未解释。
- **E022 运行 2 计划**：m16 + dwc3 改 otg + usb-role-switch，pmic-glink 加 usb-c-connector，内核 TYPEC_UCSI/UCSI_PMIC_GLINK。预期：主机重新看到 gadget；`/sys/class/typec/port0` 出现；power_supply 有 battery 项。判据：ssh 可达，`cat /sys/class/power_supply/*/capacity` ≈ 99。回退：init 420 s 定时 reboot -f（若 USB 仍不可见，用户可从屏幕读 dmesg）。
- **E022 运行 2 结果（2026-11-11 18:04，m16 + otg/usb-role-switch/UCSI，Image 1b5cfbe0…，boot f6170204…）**：用户拍屏：与运行 1 完全相同（ADSP/glink/gadget/BT 都正常，无 panic，无 ucsi/typec 报错），主机仍看不到 USB 设备；420 s 后自动回 Android（用户先前说的“黑屏”是回到 Android 后息屏，更正）。屏幕只显示最后约 40 行，看不到 role/ucsi 信息。
- **运行 3**：init 加屏上观察器（25 s/70 s 清屏后打印过滤的 dmesg、udc 状态、usb_role、typec、power_supply、input、rtc）；Image a0d3cf9f…，boot e0d8fc1f…。
- **E022 运行 3 结果（2026-11-11 18:07，m16 Image a0d3cf9f…，用户拍屏，本机验证）**：ADSP（remoteproc1）0.39 s 起来，PDR 收到 `msm/adsp/charger_pd`；power_supply：`battery`（cap=98，status=Not charging）、`qcom-battmgr-usb`（online=1）、`qcom-battmgr-wls`、`ucsi-source-psy-pmic_glink.ucsi.01`（Charging）；`/sys/class/typec/port0`+`port0-partner` 出现（UCSI 工作）；usb_role=device；input：pmic_pwrkey、pmic_resin、触摸、gpio-keys；rtc0；**但 `udc: not attached`**，主机仍看不到设备。
- 分析（读 dwc3-qcom.c）：otg+role-switch 模式下，初始 current_role 被置为 DEVICE 且不开 VBUS override（只有 dr_mode=peripheral 才在 probe 时开）；UCSI 通知 DEVICE 时 `current_role == next_role` 直接返回，VBUS_VALID override 不会打开 → 控制器认为无 VBUS，gadget 不连接。**运行 4**：观察器在 25 s 时先打印，再用 /dev/mem 把 QSCRATCH HS_PHY_CTRL(0xa6f8810) 置 bit20|bit28、SS_PHY_CTRL(0xa6f8830) 置 bit24（即 dwc3-qcom 的 vbus_override_enable(true)），4 s 后打印 udc 状态。预期 udc 变为 configured/addressed，主机出现设备，ssh 可达。boot 8c9df2d0…。
- **E022 运行 4 结果（2026-11-11 18:15，boot 8c9df2d0…）**：VBUS override 写入生效（读回 HS_PHY_CTRL=10100000、SS_PHY_CTRL=01000000），但 `udc: not attached`、主机无设备 → VBUS 不是缺的东西。结合运行 1（forced peripheral，override 已开，ADSP 在，USB 照样消失）与 m15（无 ADSP，USB 正常）：ADSP 的充电/Type-C 固件切断了 D+/D- 到 SoC 的数据通路（推测：ADSP 开机时重跑线缆检测，与 AP 在 1.6 s 拉起的 gadget 冲突）。**运行 5**：观察器 25 s 打印 typec 角色/usb psy 属性；70 s 依次试 soft_connect 断/连、UDC 解绑/绑定、usb_role none→device；主机后台每秒记录 lsusb，捕捉任何短暂出现。
- **E022 运行 5 结果（2026-11-11 18:21，boot e7742017…，用户拍屏）**：soft_connect 断/连、UDC 解绑/绑定、usb_role none→device 三项均无效（udc 始终 not attached）；主机 lsusb 全程（232 秒记录，private/kde/usbwatch.log）没有 Linux gadget 出现。→ D+/D- 数据通路被切断，非控制器软状态。
- **运行 6 计划**：假设：ADSP 开机时的线缆检测（BC1.2/APSD）与 AP 在 1.6 s 就拉起的 gadget 冲突，ADSP 把线缆当作充电器、不给数据通路；Android 的 USB 栈在检测完成后才起。验证：70 s 时先解绑 UDC，屏幕提示用户拔插线缆（25 s 内），再绑定 UDC，观察主机是否出现设备。预期：出现设备 → 假设成立（对策：延迟 gadget 到 ADSP 就绪或由 ucsi 事件触发）；不出现 → 数据通路由别的因素切断。
- **E022 运行 6 结果（2026-11-11 18:27，boot b592cb3d…，用户在 5 s 内拔插线缆）**：整个 25 s 窗口里 `typec port0-partner`、`usbpsy.online=1` 始终不变，只在拔插时刻（约 100–110 s）出现几条 battmgr `unknown notification: 0x50`；绑定后 udc 仍 not attached，主机仍无设备。→ ADSP 用 0x50 报告线缆事件，而主线 battmgr 不认（该固件的通知号与主线不同），拔插假设不成立。
- **新线索（读运行时 DT，用 phandle 解析）**：厂商 hsphy@88e3000 的供电 vdd=L5B(0.88 V)、vdda18=L23B(1.8 V)、vdda33=L25B(3.3 V)，而我的 DT 里 USB PHY 节点没有任何供电：这三路只靠 ABL 的投票开着；L25B 在 DT 里根本没有定义。ADSP 启动后可能撤掉这些投票（m15 无 ADSP 时 USB 正常，m16 有 ADSP 时数据通路消失）。**运行 7**：hsphy 加 vdda-pll=L5B、vdda33=L25B（新定义，3.0–3.3 V，always-on/boot-on）、vdda18=L23B；预期主机重新出现 gadget；判据 ssh 可达/udc 状态变化。boot fca3879b…，DTB ac9330ad…。
- **E022 运行 7 结果（通过，2026-11-11 18:31，boot fca3879b…，本机验证）**：加了 USB PHY 三路供电（L5B/L23B/L25B）后，ADSP 在位时 USB gadget 正常（configured），ssh 可达 → 之前“数据通路被 ADSP 切断”的推测错误，真因是 DT 里 USB PHY 供电没声明，靠 ABL 的投票，ADSP 启动后这些投票被撤销。
  - 电池（battmgr，经 ADSP）：capacity=98、voltage_now≈4.45 V、voltage_ocv 4.33 V、health=Good、state_of_health=100、型号 NVT_WINGTECH_S88019AA1_5000MAH、cycle_count=1、temp=23.0 °C；usb psy：online=1、usb_type 含 PD/PD_PPS、current_max=2 A；ucsi-source-psy：Charging，usb_type=C [PD] PD_PPS；typec port0 data_role=device，power_role=sink。状态 "Not charging"（电量 98–99%，与 Android 同）。证据 private/kde/e022-powersupply.txt。
  - 充电上限：`charge_control_end_threshold`/`start_threshold` 可写（写入 rc=0）但读回恒为 0 → 该固件不实现主线的阈值通道；80% 上限或旁路充电要用厂商私有 opcode（待从 Android 的 battery_charger 模块/小米接口逆出）。
  - 按键：电源键（KEY_POWER 0x74）和音量下（resin，KEY_VOLUMEDOWN 0x72）按下/释放事件正确（用户按键，本机验证）；音量上 gpio53 物理电平正确（按下读 low，松开 high）但 `/proc/interrupts` 中断计数恒为 0。原因：gpio53 经 PDC 路由（pdc pin 114），而上游 sm4450.dtsi 的 `qcom,pdc-ranges = <0 480 94>, <94 494 31>, <125 63 1>` 与本机运行时 DT（<0 480 94>, <94 609 31>, <125 63 1>, <126 716 12>，与 sm8450 相同）不符；上游补丁候选。
  - RTC：rtc0 在，初始 1970 年（需要时间同步）。
- **运行 8**：DT 里覆盖 pdc-ranges 为运行时值；预期音量上有事件。
- **E022 运行 8 结果（通过，2026-11-11 18:4x，本机验证）**：覆盖 `qcom,pdc-ranges` 为运行时值后，音量上（gpio53，KEY_VOLUMEUP 0x73）按下/释放事件正常，`/proc/interrupts` 计数增加（17）。三个硬件键全部可用（电源、音量下、音量上）。上游补丁候选：sm4450.dtsi 的 pdc-ranges 与本机/ sm8450 不符。

## E023：睡眠（s2idle / deep）（2026-11-11 晚，用户在场）
- 运行 1（m16 boot 30b94214…，本机验证）：ssh 里 `echo freeze > /sys/power/state`，RTC 闹钟 25 s：手机在闹钟后醒来（用户确认“回来了”，屏幕可见），但 USB 在 suspend 前后掉线且**没有恢复**：屏幕上有 `dwc3-qcom a600000.usb: port-1 HS-PHY not in L2`、`failed to enable ep0out`，udc 一直 `not attached`，ssh 丢失；init 计时器当时被我延长（touch /tmp/stay），无法自动回 Android，需用户长按电源。结论：s2idle 本身能进能出（RTC 唤醒有效），失败点是带连接的 gadget 做 suspend 时 dwc3 不恢复。对策：suspend 前解绑 UDC，resume 后重新绑定（initramfs-m14/sleeptest）；Debian/WiFi 系统不依赖 USB gadget，影响小。
- 运行 2 计划：`sleeptest freeze 25`，再 `sleeptest mem 25`（deep/PSCI），结果在 /tmp/sleep.log 和屏幕；不 touch /tmp/stay 以外多余操作。判据：resumed rc=0、slept_rtc≈SEC、udc 重新 configured、ssh 回来；deep 失败（挂死）则需用户长按电源，init 计时器 420 s 会重启回 Android。
- **E023 运行 2 结果（2026-11-11 18:5x，boot f6c5b4f8…，用户拍屏，本机验证）**：`sleeptest freeze 25`：`PM: suspend entry (s2idle)` → `suspend exit`，`resumed rc=0 slept_rtc=25s`，用户空间冻结/恢复正常，RTC 闹钟唤醒有效；面板驱动在 suspend 里做了 DCS 读（调试读）。但 USB 仍不恢复：suspend 时 `dwc3-qcom: port-1 HS-PHY not in L2`，resume 时 `failed to enable ep0out`，即使 suspend 前已解绑 UDC、resume 后重绑 UDC，`udc=not attached`，ssh 丢失（Hangup）。→ s2idle 本体通过，USB gadget 路径是 dwc3 恢复问题（开发通道问题，不影响 Debian+WiFi 的使用）。
- **运行 3 计划**：`sleeptest` 在 resume 后解绑/绑定 dwc3-qcom 驱动再绑 UDC 并重设 usb0 IP；然后测 deep（`sleeptest mem 25`）。不再 touch /tmp/stay。
- **E023 运行 3 结果（通过，2026-11-11 18:52，boot d8bffe04…，本机验证）**：`sleeptest mem 25`：内核日志 `PM: suspend entry (deep)` → `PM: suspend exit`，`resumed rc=0 slept_rtc=25s`，resume 后脚本解绑/绑定 dwc3-qcom + 重绑 UDC + 重设 usb0 IP，ssh 回来（deep sleep 与 s2idle 都不再丢通道）。键唤醒：`sleeptest mem 90`，用户按电源键 → `slept_rtc=22s`（早于 90 s 闹钟，电源键唤醒）；`sleeptest mem 60`，用户按音量上 → `slept_rtc=21s`（音量上唤醒，gpio-keys wakeup-source + PDC 修复起作用）。
- 未验证：睡眠期间的实际功耗（需要不插线测量，USB 在位时电量状态不具参考性）；Debian/GNOME 下 `systemctl suspend` 全流程（显示关/开、WiFi 重连、蓝牙、触摸）；WiFi/ADSP 在 deep sleep 中的行为；Debian 里 `reboot -f` 后手机消失的问题仍未解释。USB gadget 不能自己恢复（dwc3 恢复缺陷），只能脚本重绑驱动。

## E024：充电上限 / 旁路（小米充电固件的私有属性，2026-11-11 晚）
- 事实（本机，从 Android 取出的 vendor/lib/modules/qti_battery_charger_main.ko 反汇编，文件在 private/android-e022/，不提交）：小米在 qcom battery_charger 上加了第四组「xm」属性：get opcode 0x50，set opcode 0x51（偏移 600 处 opcode_set=0x51，15 个属性）；主线 battmgr 日志里反复出现的 `unknown notification: 0x50` 就是这组属性的通知。`input_suspend`（Android 类属性）的实现：发送 {owner 0x800a, type 1, opcode 0x51, battery 0, property 3, value 0/1}。同一模块还有 StartCharging_Test/StopCharging_Test、restrict_chg、restrict_cur、fake_soc、quick_charge_type、shipmode 等类属性（属性号待逐个反汇编）。主线标准的 charge_control_end/start_threshold 此固件不实现（读回 0）。
- 实验：qcom_battmgr.c 加一个本地调试属性 `xm_set`（"prop value" → opcode 0x51 请求，`pmic_glink.power-supply.0/xm_set`，标注不上游）。步骤：写 `3 1`（input suspend）→ 读 usb psy online / battery status / 电压电流 → 写 `3 0` 恢复；预期：充电输入被挂起，usb online 变 0 或 battery status 变 Discharging，写回 0 后恢复。判据：状态变化可观测，且写回后恢复；失败形态：无变化（则 property 编号/格式不对）。回退：写 `3 0`；重启后 ADSP 重新初始化。
- 用途：80% 上限可以由用户态守护程序用 input_suspend 做滞回（例如 ≥80% 挂起、≤75% 恢复）；真正的“旁路”（电池不循环、系统直接由适配器供电）需要固件支持，input_suspend 下系统由电池供电，不算旁路——待验证。
- **E024 结果（通过，2026-11-11 19:2x，boot b9c7ee84…，本机验证）**：`echo "3 1" > …/xm_set`：battery status Not charging→Discharging，usb psy online 1→0，battery current_now 0→−148 mA（手机整机由电池供电约 0.15 A），电压 4.449→4.427 V；`echo "3 0"`：回到 Not charging/online=1。dmesg 里两次 `xm_set prop 3 … -> 0`（请求被固件接受，ack 在 1 s 内）。→ 小米充电固件的 input_suspend 可在主线下用。80% 上限 = 用户态守护程序做滞回（desktop-debian/sky-charge-limit）。注意：input_suspend 下系统用电池，不是旁路；电池一直在 75–80% 之间浅循环（比一直 100% 好，但仍有循环）。真正的旁路（适配器直供）待查（restrict_chg/StopCharging_Test 等属性号）。

## E021 运行 3（Debian + m16 全栈，2026-11-11 晚，用户在场）
- 目的：在 systemd+GNOME 下验证 m16 的新东西：电池/充电限制服务（sky-charge-limit，80/75）、三个硬件键（logind/GNOME 的处理）、WiFi/BT/GPU/触摸、Debian 下 suspend（`systemctl suspend`，WiFi 重连、显示开关）。输入：m16 boot b9c7ee84…（含 ADSP、UCSI、USB PHY 供电、pdc-ranges、xm_set），out/rootfs-debian-stage1.tar，tools/push-debian.sh（新：安装 sky-charge-limit、ADSP 固件）。预期同运行 2 + 电池/键。回退：50 min failsafe 重启；返回 Android 用 `systemctl reboot`，不再用 `reboot -f`（上次 Debian `reboot -f` 后手机消失，疑与 WiFi/WPSS 在跑时硬复位有关，未证实）。
- **E021 运行 3 结果（通过，2026-11-11 19:0x，本机验证 + 用户陈述）**：Debian + m16：systemd running，gdm3/NetworkManager/bluetooth/ssh/sky-wifi/sky-charge-limit 全部 active；充电限制服务按 80% 把充电输入挂起（97% ≥ 80%，state=1，电池放电）。用户在 GNOME 里按电源键睡眠、再按电源键唤醒——**用户确认「睡眠和唤醒都正常」**；journal：`Power key pressed short` → `The system will suspend now!` → NetworkManager 休眠、WiFi 主动 deauth → `PM: suspend entry (deep)` → `suspend exit`，WiFi 回连、ssh（WiFi）回来。遗留：一次 `systemd-suspend.service` failed（第一次 deep 进入后约 2 s 就退出、另一次 deep 立即退出后落到 s2idle 才睡成，原因未查，疑似某个唤醒源/WiFi 固件），启动后 `systemctl is-system-running`=degraded；蓝牙日志 `unknown advertising packet type: 0x05` 刷屏；WiFi 驱动 `sky-dbg*` 调试输出很多（我的 E016 调试旋钮，应清理）。睡眠功耗、续航仍未测。

## E025：重分区 sda（Android 40 GiB / Linux 68 GiB）（2026-11-11 晚）
- 授权：用户 2026-11-11 晚明确说 "Let's partition!"（此前已决定接受清数据、保留 Android、Debian+GNOME、Android 40 / Linux 68 GiB 的方案；用户自行检查并备份了需要保留的东西）。这是本项目第一次写存储。
- 范围：只写 sda 的 GPT 元数据（主表 LBA 1–2、备份表项 LBA 30693371、备份头 LBA 30693375），不写任何分区内容。sda 上只有 Android 的 persist/misc/cust/super/metadata/userdata 等；启动链（xbl/abl 等）在 sdb–sde，不受影响，所以最坏情况也能进 fastboot。
- 新布局（tools/gpt-split-sda.py 生成，写入前用 sfdisk 4096 扇区独立校验：22 个分区、无重叠、0 空闲）：userdata LBA 2402344–12888103（40.00 GiB，原 107.92 GiB，起点不变），linuxboot 12888104–13150247（1 GiB，Linux filesystem 类型），linuxroot 13150248–30693370（66.92 GiB）。dry-run 产物 private/partition/dry/。
- 输入哈希：旧 GPT = private/backup-unique-20261109T142656Z/gpt-sda-{head,tail}.bin；写入前先把设备当前 LBA 0–5 与最后 5 个块与备份逐字节比对，不一致就停。
- 预期：写完回读与生成文件一致，内核重读分区表后出现 sda21/sda22，sda20 大小 10485760 块。判据：以上全成立。
- 后果（已告知用户）：userdata 缩小后里面的 f2fs（按旧大小）已不能挂载，Android 在清除 userdata 之前不能正常启动；随后需做恢复出厂（recovery 的 wipe data，或 fastboot erase userdata+metadata），Android 首次启动会按新大小重建。
- 回退：把 gpt-sda-head/tail 备份的 LBA 1–2 与备份表项/头写回即还原分区表（userdata 内容在 40 GiB 以外那部分会因我们随后的清除而不复存在，所以在清除前才可逆）。
- 结果（2026-11-11 晚）：写前比对：LBA 0–5 与最后 5 块（备份表项+头）与备份逐字节一致（头部 1 MiB 备份中 LBA 8 起有 228 字节差异，是 Android 之后写过的分区内容，与 GPT 无关）。先写备份表项/备份头，再写主表；三处回读均一致；`blockdev --rereadpt` 后出现 sda21、sda22，sda20 = 83886080 个 512B 扇区（40 GiB），sda22 = 140344984（66.92 GiB）。这也是第一次成功写 UFS（LUN0 GPT 块，fsync 后回读一致）。
- 擦除（同夜）：从 m16 RAM Linux 把 metadata（sda12，16 MiB）全部清零、userdata（sda20）前 256 MiB 清零，回读为零。普通 `reboot` 在 m16 initramfs 里无效（busybox 信号 init 不处理），要用 `reboot -f`（init 自带的超时回退也是它）。重启后主机看到 18d1:4ee1（Android MTP）而 adb 无设备——符合已被清空、USB 调试尚未重新打开的出厂状态；是否完成首次开机引导需用户看屏幕确认。
- 结果：用户重新完成安卓开机引导并开启 adb。`/data` 为 40G（f2fs 在新大小上重建），`ro.crypto.state=encrypted`，boot_completed=1，电量 97%。清除后 Magisk/root 也没了（`su` 不存在），boot 槽本身未动；需要 root 时重新修补当前 boot。E025 完成。

## E026：Debian 根持久化到 sda22（2026-11-11 晚）
- 路径：m16 RAM → tools/push-debian.sh（stage1 + 第二阶段，~35 min，在 tmpfs）→ 在 chroot 里 mke2fs（`PERSIST=1` 分支）→ 复制到 UFS。授权：用户「Let's go!」（接上一步重分区后的安装）。写入范围仅 sda21/sda22，写前核对 PARTNAME。
- 坑：stage1 根里只有 libext2fs2t64，没有 e2fsprogs。已从 deb.debian.org trixie 取 e2fsprogs/libss2/logsave 1.47.2-3+b12 arm64（SHA256 与 Packages 索引一致，缓存在 out/extra-debs/），在 RAM 根里 dpkg -i 后才有 mke2fs。**这三个包还没进 build-debian-stage1.py，下次完整构建前要加**（否则 PERSIST 失败；persist 后的根已含它们）。busybox tar 无 --one-file-system，改用 --exclude ./dev/* ./proc/* ./sys/* ./run/*。push-debian.sh 的 PERSIST 分支已按此修正但**整体未重跑**（本次是手工执行同样命令）。
- 结果：sda21 linuxboot（ext4，1 GiB）、sda22 linuxroot（ext4，66.9 GiB，已用 2089 MiB）；文件数 usr/var 与 RAM 根一致；抽样 3000 个文件 sha256 全部一致；`e2fsck -fn` 两个分区均干净。这是首次文件系统级 UFS 写入验证（写回读一致，约 2 GiB）。fstab 用 LABEL=linuxroot / LABEL=linuxboot。
- 还没做：从 sda22 启动（initramfs 直接 mount+switch_root）、冷启动验证、写入吞吐测量。
- 启动自 sda22：不需要改 init——在 m16 RAM 里 `mount -t ext4 /dev/sda22 /mnt/root; echo /mnt/root > /run/switch-root`（E021 hook）。结果：`findmnt /` = /dev/sda22 ext4 rw,noatime，systemd `running`，Debian 13，touch /run/sky-keep 解除 50 分钟保险。UFS 吞吐（ext4，页缓存绕过）：顺序读 1 GiB 932 MB/s，写 direct 64 MiB 422 MB/s、512 MiB 344 MB/s；内核无 UFS 错误。**E026 判据通过；未做：冷启动（fastboot boot 直接进 sda22）与 Android↔Linux 来回切换。**
- 往返验证（同夜）：`tools/boot-linux.sh`（新）= 读电量 → cycle-boot-m16 → ssh 让 init 挂载 sda22 并 switch_root。Linux → Android：`systemctl reboot`，约 2 分钟回到 Android（`reboot -f` 不用）；Android 重新开机完成，/data 40G 正常。Android → Linux：冷启动 fastboot boot → sda22 ext4 → systemd running，无 failed unit，无 UFS/ext4 错误。**Android↔Linux 双向切换通过。** 仍依赖主机跑脚本（init 里的自动挂载 sda22 要重编 initramfs，留待用户 `! tools/build-m16.sh` 时一并做；boot_a 免主机启动是单独决定）。

## E027：音频（2026-11-11 晚，离线准备）
用户「Alright let's try audio」。资料、方案、预期/判据/回退见 docs/AUDIO.md。产物（未提交）：tools/gen-m17-dts.py（DTS 编译通过，仅有已存在的 simple_bus_reg 告警）、tools/build-m17.sh、tools/cycle-boot-m17.sh、private/audio/android/（vendor mixer_paths/resourcemanager/acdb，从 Android 无需 root 取得）、private/audio/tplg/…/Redmi-12-5G-tplg.bin、sources/audioreach-topology（BSD-3-Clause 克隆，d6bb205a）、out/alsatplg（Fedora alsa-topology-utils 解包）。尚未构建、尚未上机。
- 构建（用户运行 tools/build-m17.sh，成功）：Image 2df443ed…，sky-m17.dtb 1fd76e6d…，boot sky-m17-shim-boot-v4.img 631084e0…（out/candidates/m17）。内核配置确认内建：SND_SOC_SC8280XP、QCOM_APR、QDSP6_APM/PRM(+LPASS_CLOCKS)、WCD937X_SDW、LPASS RX 宏、SOUNDWIRE_QCOM、PINCTRL_SM8450_LPASS_LPI、AW87390。
- 上机 run 1（RAM，不写存储）：预期/判据/回退见 docs/AUDIO.md；回退 = init 420 s 超时 `reboot -f` 回 Android，手机 Android 状态 97%，Debian 在 sda22 不受影响。
- **E027 run 1 结果（m17，RAM，2026-11-11 20:38）**：ADSP audio_pd 上线（PDR 0.37 s）、GPR 设备 gprsvc:service:2:1/2:2 出现；两个 WCD9370 SoundWire 从机枚举成功（sdw:2:0:0217:010a:00:4、sdw:3:0:0217:010a:00:3）并被 wcd937x 绑定——**编解码器硬件在线**。失败：(1) q6apm 首次命令 [1001021]（GET_SPF_STATE）等待 5 s 超时；(2) `qcom-prm: DSP returned error[100100f] 1`（PRM_CMD_REQUEST_HW_RSC → ADSP_EFAILED）使 lpi-pinctrl 与 va/rx/tx 宏 `__pm_clk_enable ... -22`；(3) 声卡路由 WCD_TX_OUTPUT→TX SWR_INPUT 添加失败 → 无声卡。线索：运行时 DT 里 lpass_core_hw_vote（核心 hw 投票）status=disabled，只有 lpass_audio_hw_vote 启用。run 2 假设：ADSP 不支持 LPASS_HW_MACRO_VOTE（hw block 1），用 fixed-clock 占位；同时补 dmic 采样率（va 600000/tx 2400000）和 mbhc 阈值。无关告警：swr1 din-ports(0)≠控制器(1)（sm8450 同样覆盖）。I2C 只读：fs15xx@0x34 应答（reg2=0x24，其余 0），aw87xxx@0x58 全部无应答（未上电/使能，使能脚未在 DT 里找到）。
- run 2 候选 m17b（tools/repack-dtb.sh，只换 DTB，Image 2df443ed… 不变）：DTB 75005d05…，boot f342440b…。
- **E027 run 2–4（m17b/c/d，仅换 DTB）**：m17b 用 fixed-clock 占位 LPASS_HW_MACRO_VOTE 后 PRM 报错和 `__pm_clk_enable -22` 消失（DCODEC 投票正常）。声卡路由失败是我写错了 mic 路由：sm8450 的 TX 宏变体（lpass_ver_9_2）的 widget 是 `TX SWR_INPUT0/1`，不是 `TX SWR_INPUT`/`TX SWR_ADC0`。m17d（路由改为 `TX SWR_INPUT0←ADC1_OUTPUT`、`TX SWR_INPUT1←ADC2_OUTPUT`，DTB 179170cc…，boot d9133b63…，Image 不变）：**声卡 `0 [Redmi125G]: sm8450 - Redmi-12-5G` 注册成功，出现 "Redmi-12-5G Headset Jack" 输入设备**（本机验证，21:13）。APM 的 GET_SPF_STATE 首次命令仍 5 s 超时但之后正常。待测：PCM 设备、播放。
- 教训：`ssh … 'reboot -f'` 会让 ssh 会话挂住（对端没关连接），要用 `timeout 10 ssh …` 或在手机端 `(reboot -f &)`；此前每次“等 Android”其实在等 ssh 超时。
- **E027 run 5（m17d 内核 + Debian sda22，2026-11-11 21:16）**：Debian 里 apt 源原先缺失（rootfs 是用 tools/deb-fetch.py 解包的），已加 `/etc/apt/sources.list.d/debian.sources`（http://deb.debian.org/debian trixie + trixie-updates，keyring debian-archive-keyring.pgp；https 失败是因为手机时钟错，`date -s` 后可用，仍用 http，apt 自己验签）并装了 alsa-utils。PCM：MultiMedia1/2 播放、MultiMedia3/4 录音。按 Android `headphones` 路径设置 mixer 后 `speaker-test -D hw:0,0` 播放成功完成（stream 启动/结束，dmesg 仅一条 `wcd937x_codec: clk already disabled`，无 DSP 错误）。**听感未验证**（需要耳机/用户）。喇叭：AUX_RDAC 通路已有 mixer 控件，但 aw87xxx@0x58 在 WCD 起来后仍无 I2C 应答（使能脚/供电未知，待查 Android 的 aw87xxx 驱动）。

### E027 扬声器（2026-11-11 夜，用户：「耳机现在没人用了，扬声器呢？」）
- **离线结论（源码证据：vendor fs15xx_dlkm.ko 反汇编 + fs1599.fsm 解析，细节在 docs/AUDIO.md）**：扬声器 = WCD9370 的 AUX 模拟输出（Android 后端 CODEC_DMA-LPAIF_RXTX-RX-1，单声道，无 I2S）→ **FourSemi FS1599（AP I2C 0，0x34）**；aw87xxx@0x58 从未应答（这块板没焊/没用）。FS1599 寄存器 8 位、值 16 位大端；开机序列 = reset/ready(reg0x10←2,15 ms,←1，读 reg0x0e 要 0x0003/0x0300) → 解锁 reg0x1f←0x0091 → 预设表（公共表 10 项 + 场景表，Android 用场景 6=掩码 0x40）→ 锁 → start_up（0x1f←0xca91, 0xc0←0x10, 0x10←0, 0x11←0xc0, 10 ms, 0xc0←0, 0x1f←0）；关 = 0x11←0, 20 ms, 0x10←1。工具 tools/fs1599.py（`plan` 离线打印完整序列；`probe` 只读；`on`/`off`）。
- 只读核验（本机，2026-11-11 夜，m17d 内核 + Debian，手机 97%→95%）：probe 读 reg 0x0e=0x0003（就绪）、0x10=1、0x11=0（掉电态）、0xbc=0x113e、0x02=0x24a1；各寄存器是上电默认值（预设尚未写入）。
- 上机步骤与预期：输入 tools/fs1599.py sha256 34561086…、fs1599.fsm sha256 9c2ae240…（私有）；内核 m17d（Image 2df443ed…，DTB 179170cc…，boot d9133b63…，RAM 启动，不写存储）。(1) `fs1599.py on --scene 6` → 之后 probe 读回的寄存器等于预设表值（0x3e=0x8500、0x58=0x8250、0x21=0x0511、0x22=0x02xx、0x18=0x000c、0x11=0x00c0、0x10=0）；(2) 设 mixer（AIF1_PB 的第 2 声道 RX1 → RX INT2_1 → AUX_RDAC，不改 DT：RX_CODEC_DMA_RX_0 的 RX0/RX1 车道可以接 INT2）；(3) 播放 440 Hz、约 −30 dBFS 单音 3 s，用户听。判据：用户陈述「扬声器有声音」；失败时按层查：amp 状态寄存器 → WCD AUX_PA 寄存器 → SDW 端口 → ADSP 流。风险：只用 vendor 预设值，音量先低；不改任何存储。回退：`fs1599.py off`；`systemctl reboot` 回 Android。
- **E027 扬声器 run 1 结果（m17d + Debian sda22，2026-11-11 夜，本机验证；听感待用户陈述）**：`fs1599.py on --scene 6` 后读回 reg 0x3e=0x8500、0x3f=0x1100、0x58=0x8250、0x59=0x084f、0x5a=0x00cd、0x18=0x000c、0x11=0x00c0、0x10=0（与预设表一致），0x03/0x04 变为 0x000d/0x0500（状态位，含义未查），0x00=0（无故障位？未确认）。首次播放失败两次，原因见 docs/AUDIO.md「路由坑」：(a) FE→BE 开关 `RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1` 开机后默认关 → open EINVAL；(b) 只把 RX1 车道接到 INT2 → DSP codec DMA 停转（hw_ptr=0），把 RX0+RX1 都接进 `RX INT2_1 MIX1` 后 hw_ptr 立刻走动、`aplay` 播完 6 s 单音（−30 dBFS，440 Hz，两路相加约 −24 dBFS）rc=0，DAPM 通路 AUX 全链 On，内核无错误。耳机路径（Android headphones 组合）同一内核上播放正常（对照）。**待用户报告是否听到声音。**
- **E027 事故（2026-11-11 夜，m17d + Debian，本机观察）**：用户反馈「你操作时每次听到连续两声短促的爆音」（没提到音调，说明放大器和扬声器接通、开/关通路有声，但 440 Hz 音调是否出声未确认）。为了读 WCD/宏寄存器，我在手机上执行了 `for d in /sys/kernel/debug/regmap/*; do wc -l $d/registers; done`（没有在播放时、没有限定某一个 regmap）。该命令 60 s 超时挂住，随后手机从 USB 上完全消失（ping 不通、ssh 不通、adb/fastboot/lsusb 均无设备，等了 >4 分钟）。假设（未证实）：读 LPASS 宏/SoundWire 从机 regmap 时对应时钟已关（无流），总线访问挂起并触发看门狗复位或整机挂死。教训：**不要整目录读 regmap debugfs `registers`；只在流在播放（时钟开）时读单个 regmap，并先用 `timeout` 包住；或用 `cat /sys/kernel/debug/regmap/<name>/range` 先看范围、用 `dd` 读单个偏移。** 手机恢复方式待用户配合（长按电源键强制重启）。
- **E027 扬声器 run 2：用户只听到爆音（2026-11-11 夜，用户陈述）**：扬声器（1 kHz，约 −14 dBFS）和听筒（1 kHz −30 dBFS）都只有「连续两声短促的爆音」（开/关通路），没有音调。本机诊断：(1) SoundWire 数据面异常：播放时 slave 的 DP1(HPH) ChannelEn 与 master 端口 1 的 EN_CHAN 对不上——只开 HPHL：master 0x8、slave 0；只开 HPHR：master 0x2、slave 0x2；CLSH/LO（单声道端口）正常（master 1、slave 1）。(2) 捕获也失败：TX_CODEC_DMA_TX_3 经 swr2 录音 `read error: EIO`（master 端口 1 EN=1，slave 的 DP1 与 DP2 都 EN=1，tx-port-mapping <1 1 2 3> 把两个 slave 端口并到 master 端口 1）；VA_CODEC_DMA_TX_0 + VA DMIC（不经 SoundWire）能录满 3 s（全零，板上可能没有 DMIC），说明 DSP↔宏通路本身正常，故障集中在 SoundWire 数据面。(3) 我加的 `qcom,rx-channel-mapping`/`qcom,tx-channel-mapping` 不是上游（HDK、FP5、RB3 Gen2 都没有），它们会改写 master_ch_mask。**run 3 假设（单变量）：去掉这两个属性（m17e：仅 DTB，Image 2df443ed… 不变，DTB 7b0eb3cf…，boot 491b5974…）。预期：HPHL 单开时 master EN_CHAN=1 与 slave 一致，录音不再 EIO。判据：`/root/sdwprobe.sh` 读回 master/slave 使能一致；arecord hw:0,2 能读满。回退：同前，Android 不受影响。**
- 另：整目录读 debugfs regmap 之后手机消失（见上「事故」）；之后在播放中单独读 `sdw:*` 的 debugfs `registers` 和 `master-*/qualcomm-sdw/qualcomm-registers` 是安全的（多次通过，只触发无害的 `SWR read FIFO underflow` 日志）。
- **E027 run 3 结果（m17e，2026-11-11 22:0x，本机验证 + 用户陈述）**：去掉 `qcom,*-channel-mapping` 后 SoundWire RX 使能一致：HPHL 单开 master EN_CHAN=1/slave ChannelEn=1，HPHR=2/2，两路=3/3（此前 HPHL 被映射成 0x8，slave 收不到）。**用户陈述：听筒（top earpiece）能听到清晰的音调（1 kHz，−30 dBFS 两路相加）；底部扬声器仍只有爆音。** → 编解码器、SoundWire RX、宏、DSP 通路、听筒路径整体可用（首次在本机真正出声）。扬声器（AUX→FS1599）仍无声：FS1599 已按 vendor 序列上电，AUX_PA 寄存器置位（0x3128=0x90，ANA_RX_SUPPLIES=0xc1），LO 端口 master/slave 使能一致（master 端口 4 EN=1，slave DP4 ChannelEn=1），但无音。已排除：路由停转（已修）、SoundWire 掩码（已修）。未排除：(a) INT2→LO 端口→codec RX3 的数据通路本身（下一个单变量实验：`RDAC3_MUX=RX3` + `EAR_RDAC=on`，让 AUX 的数据通路改走听筒，听筒出声就证明 RX3 数据到了，问题在 AUX PA/FS1599；不出声则 RX3 数据没到）；(b) FS1599 的输入模式/路径（vendor 预设里有 reg0x3f bit15 等位域）；(c) AUX PA 的模拟增益/保护。FS1599 reg 0x3e 在首次播放后由 0x8500 变 0x8580 并保持（与静音/有信号无关，含义未知）。
- 捕获（麦克风）仍失败：TX_CODEC_DMA_TX_3 经 swr2 读 EIO；原因线索：`qcom,tx-port-mapping=<1 1 2 3>` 把 slave 端口 1、2（ADC1、ADC2）并到 master 端口 1，master 只使能 EN_CHAN=1，两个 slave 端口都使能；留待麦克风阶段。
- 时钟/网络（用户要求，2026-11-11 22:09）：WiFi 已连（wlan0 <phone-wifi-ip>），ping 1.1.1.1 23 ms、apt update 与 DNS 正常 → 外网可用；系统时钟原为 2026-04-13，已按主机时间校正，并 `apt install systemd-timesyncd iproute2 iputils-ping`，timesyncd 已与 pool.ntp.org 同步（stratum 2）。PMIC RTC（rtc-pm8xxx）读回 1970-12-27，不保存时间（未查是否可写）：断网冷启动时间会错，联网后 NTP 校正。

### E027 run 4 计划：m17f（单变量：`qcom,tx-port-mapping` `<1 1 2 3>` → `<1 2 3 4>`；2026-11-11 22:3x）
- 目的：修复捕获（麦克风）EIO，得到一个**无人值守的声学传感器**（底部麦克风能听到听筒/扬声器），以便不靠人耳迭代扬声器。
- 依据（源码+社区+原厂）：上游 binding 说明 tx-port-mapping 按设备端口序（adc1_port、adc23_port、dmic03_mbhc_port、dmic46_port）给出主控端口；<1 1 2 3> 把 ADC1 与 ADC2/3 并到主控端口 1，正是 run 3 中观察到的“主控 EN=1、slave DP1/DP2 都使能”；sc7280-qcard.dtsi 用 <1 2 3 4>（端口分开）；原厂 `ADC2 ChMap SWRM_TX2_CH2` 表明 ADC2/3 在主控端口 2。
- 输入：Image 2df443ed48c0…（同 m17e，未改）；DTB sky-m17f.dtb 299525ae56de…；boot 3ba7d41638fa…（`out/candidates/m17f`，仅 tx-port-mapping 一处不同）。
- 预期：启动无新增错误；arecord -D hw:0,2? 对 TX_CODEC_DMA_TX_3（以 `aplay -l/arecord -l` 为准）能读到数据；amic3 mixer 食谱（原厂 `amic3`）：TX DEC2 MUX=SWR_MIC、TX SMIC MUX2=SWR_MIC5、TX_AIF1_CAP Mixer DEC2=1、ADC2 MUX=INP3、ADC2_MIXER Switch=1、ADC2 Switch=1、MultiMedia3 Mixer TX_CODEC_DMA_TX_3=1。
- 判据：通过 = arecord 不再 EIO 且听筒播放时录音 RMS 明显高于静音底噪；失败 = 仍 EIO（记 sdwprobe 的 master/slave 使能）。
- 回退：RAM 启动，`systemctl reboot` 回 Android（默认启动 Android）；电量 95%；不写存储；失败自动回退 failsafe <50 min。
- **E027 run 4 结果（m17f，本机验证）**：tx-port-mapping <1 2 3 4> 生效后，用大缓冲（`arecord -B 8000000 -F 1000000`，默认缓冲只有 ~0.6 s 超时，EIO 其实是“DMA 超时无数据”）可保持流运行：TX 主控端口 1、2 的 EN_CHAN=1，slave DP1/DP2 ChannelEn=1，DAPM 全 On，但 avail 恒 0 → 无数据。原因（源码+原厂）：`SMIC MUX2=SWR_MIC5`（原厂 amic3）和我 DT 里 `TX SWR_INPUT1 ← ADC2_OUTPUT` 不一致；硬件上 SWR_MICn = 主控端口 (n/4+1) 的第 n%4+1 通道（原厂 `ADC2 ChMap SWRM_TX2_CH1 → SWR_MIC4`），ADC2/3 在 slave 端口 2 的通道 BIT(0) 即 master 端口 2 ch1 = SWR_MIC4。→ m17g：`TX SWR_INPUT4 ← ADC2_OUTPUT`，`TX SMIC MUX2=SWR_MIC4`。
### E027 run 5 计划：m17g（单变量：audio-routing `TX SWR_INPUT1`→`TX SWR_INPUT4`）
- 输入：Image 2df443ed48c0…，DTB sky-m17g.dtb b2e78b76d0fc…，boot 0b8413627702…（`out/candidates/m17g`）。预期：`tools/mic-on.sh` 后 `arecord -D hw:0,2 -B 8000000 -F 1000000` 有数据；判据：听筒播放时录音 RMS ≫ 静音；回退：RAM 启动，`systemctl reboot` 回 Android；电量 95%。
- **E027 run 5 结果（m17g，本机验证）**：捕获要点：(1) CODEC DMA 是 2 声道，消费 TX 宏的 DEC0 与 DEC1 两条车道，只开 DEC1+DEC2 时 `avail` 恒 0（和播放的“两条车道都要消费”同一类停转）；改 DEC0=SWR_MIC4、DEC1=SWR_MIC0 后录音有数据。(2) 但 ch0（master 端口 2，lane 2，SWR_MIC4）只有起始瞬态后恒 0；ch1（master 端口 1，lane 1，SWR_MIC0，ADC1/AMIC1）有真实底噪（±11 LSB）→ 端口 1/lane 1 通，端口 2/lane 2 不通（lane 2 或 ADC2 路径问题，未细查）。(3) 上游 qcm6490-idp（同为 WCD9370）用 `tx-port-mapping <1 1 2 3>` + 只走 ADC2（slave 端口 2 → master 端口 1）。→ m17h：映射回 <1 1 2 3>，`TX SWR_INPUT0 ← ADC2_OUTPUT`，ADC1 关闭。
### E027 run 6 计划：m17h（映射 <1 1 2 3>，ADC2→SWR_INPUT0；单变量相对 m17g：端口映射与路由）
- 输入：Image 2df443ed48c0…（未改）；DTB/boot 见 `out/candidates/m17h/SHA256SUMS`。预期：`mic-on.sh`（改为 ADC2→SWR_MIC0，ADC1 Switch 关）后底部麦克风 ch0/ch1 有真实底噪；判据：RMS 明显高于数字零，敲击/播放听筒音调时变大；回退：RAM 启动，`systemctl reboot` 回 Android；电量 96%。
- **E027 run 6 结果（m17h，本机验证）**：
  - 麦克风：`tx-port-mapping <1 1 2 3>` + `TX SWR_INPUT0 ← ADC2_OUTPUT`，ADC1/ADC3 Switch 关，DEC0+DEC1 都开（均选 SWR_MIC0），`arecord -B 8000000 -F 1000000` 得到真实数据（底噪 −89 dBFS）。**声学环回传感器建立**：听筒播放 1 kHz（−30 dBFS）时底部麦克风 1 kHz 分量 −88 dBFS，静音时 −131 dBFS；脚本 `tools/mic-on.sh`、`route.sh`、`loop.sh`、`tone-detect.py`、`poke-test.sh`。
  - **扬声器客观无声**：spk 路径 1 kHz 分量 −123 dBFS（低于静音底噪），同幅度听筒 −88 dBFS。
  - 读码证据（vendor wcd937x_dlkm.ko 反汇编，来自 ROM 的 vendor_dlkm.img，只读）：vendor 的 AUX 路径与上游基本等价（RX3 PRE_PMU 连 SDW 端口 14=LO；aux_dac_event 设 ANA_CLK bit2、DIG_CLK bit2、AUX_GAIN bit0；aux_pa 里才调用 fsm_speaker_onn）；上游多设了 AUXPA bit4（运行时清掉无变化）。
  - 判别实验：`route.sh ear3`（INT2→LO 端口→码解码器 RX3→RDAC3_MUX=RX3→听筒，并 poke DIG_CLK_CTL bit2）无声 → **经 LO 端口的 RX3 数字数据没有到达 DAC**，问题在 AUX 前级（SoundWire LO 端口），不在 FS1599/AUX PA。
  - SoundWire 配置对比：master 端口 4（0x1424=0x01000107）与 slave DP4（SampleCtrl1=7、Offset1=1、ChannelEn=1）一致；**但 LO 端口的字长为 0（BLOCKCTRL1=0，即 1 bit/采样）**，对比 HPH 端口 2 bit、CLSH 8 bit、COMP 5 bit：原因是 sm8450.dtsi 里 `qcom,ports-word-length` 端口 4 为 0xff（不编程），而 `wcd937x_hw_params` 设 `sconfig.bps = 1`。→ m17i：把端口 4 字长设为 0x0f（16 bit）。运行时 poke master/slave 的 BLOCKCTRL1 不生效（读回 0），所以走 DT。
### E027 run 7 计划：m17i（单变量：swr1 `qcom,ports-word-length` 端口 4 0xff→0x0f）
- 输入：Image 2df443ed48c0…；DTB/boot 见 `out/candidates/m17i/SHA256SUMS`。预期：`loop.sh ear3` / `loop.sh spk` 的 1 kHz 分量明显升高；判据：高于静音底噪 ≥20 dB；失败则记下 master 0x142c 与 slave 0x403 读回值，换 0x07/0x17 等字长再试；回退：RAM 启动，`systemctl reboot` 回 Android；电量 97%。
- **E027 run 7 结果（m17i，本机验证，2026-11-11 22:5x）**：DT 里把 swr1 `qcom,ports-word-length` 端口 4 改成 0x0f 后，内核确实读到 `01 07 04 0f ff 0f`，但 master 端口 4 的 BLOCK_CTRL_1（0x…142c）仍为 0、slave DP4 BLOCKCTRL1（0x403）仍为 0；通过 /dev/mem 直接往 0x03211{4,6}2c 写值：端口 6 能保持写入值，**端口 4 写什么读回都是 0**（端口 4 是固定 1 bit 的 PDM 端口，上述“字长不对”的假设**被否定**）。已从 gen-m17-dts.py 撤回该改动；m17i 候选（Image 2df443ed…，DTB 651be49c…）仅作记录。
- **E027 阶段结论（2026-11-11 23:0x）**：
  - 已通：听筒（用户听到清晰音调）、底部麦克风采集（用 DEC0+DEC1 两条车道；见 AUDIO.md）、声学环回传感器（`tools/loop.sh`）。
  - 扬声器仍无声，且已定位到**FS1599 之前**：`route.sh ear3`（AUX 数字路径 INT2→SDW LO 端口 4→codec RX3→RDAC3_MUX=RX3→听筒，并补上 DIG_CLK_CTL bit2）也无声，而同一台听筒走 INT0/HPHL 路径有声。已排除：路由停转、SoundWire 掩码、master/slave 端口 4 参数不一致（si=8、offset1=1、EN=1 两端一致）、字长（端口 4 固定 1 bit）、AUXPA bit4、DIG/ANA 时钟位、RX macro INT2 路径寄存器（与 INT0 对称）、AUX PDM 看门狗（每次起播触发 1 次后不再触发）。
  - 未排除（按成本排序）：(1) 取得 Android 在线的同路径寄存器基线（macro 0x3200000、SWR master 0x3210000、codec 0x3xxx、FS1599）做逐项对比——需要 Android 里 root（adb shell su 目前 “inaccessible or not found”，STATUS.md 记载的 Magisk 状态与现状不符，需要用户在场确认/重新授权）；(2) 反汇编 vendor swr_ctrl_dlkm.ko 的 `swrm_copy_data_port_config` 取出 RX 端口 4 的真实传输参数（vendor 的 RX 参数不在 DT 里，写在驱动中）；(3) 内核加 pr_info 看端口 4 的 p_rt 参数（需要用户 `! script` 构建）。
  - 工具（device 侧，已在 tools/ 里）：`mic-on.sh`、`route.sh ear|spk|ear3|none`、`loop.sh`、`tone-detect.py`、`poke-test.sh`（运行时在 t=5 s 执行 poke，比较前后 1 kHz 电平）、`swrpoke.sh`/`swrpeek.sh`/`swrdump.sh`（通过 SoundWire debugfs 读写 WCD9370 寄存器，`SLV=rx` 选 RX slave）、`mmio.py`（/dev/mem，仅在对应块有时钟、即流在运行时使用）。

## E027 run 8：Android 基线对比（2026-11-12，本机验证 + 源码证据）
- 前提：用户 11-12 早上重新 root（Magisk 31.1 app + private/rom/magisk_patched-boot.img 刷入 boot_b，LOG.md 有记录）。在 Android 用 com.android.music 播 1 kHz wav（扬声器输出），读 debugfs regmap（wcd937x-slave …223、lpass-cdc）存入 private/audio/android-base/（wcd-spk.txt、cdc-spk.txt）。Android 没有 soundwire debugfs、/dev/mem，SWR master 寄存器不可读。
- 发现（lpass-cdc，RX macro 基址 0x1000，v2.5 布局）：Android INT2/RX2 路径 DSM_CTL（0x5cc）=0x01、SEC7（0x5c0）=0x02；Linux 同一状态 0x5cc=0、0x5c0=0x01、0x5b4=0x02。
- 根因假设（源码）：lpass-rx-macro.c 对 codec version ≥2.5 设 `rxn_reg_stride=0xc0, rxn_reg_stride2=0x0`，于是 `CDC_RX_RXn_RX_PATH_DSM_CTL(rx,2)=0x440+0x180=0x5c0`、`SEC7(rx,2)=0x5b4`，但 v2.5 的 RX2 实际是 0x5cc/0x5c0（头文件里 CDC_2_5_RX_RX2_RX_PATH_DSM_CTL=0x05cc、SEC7=0x05c0）→ INT2(AUX) 的 DSM 时钟从未打开，DSM_OUT_DELAY 写到了错误寄存器。对 INT0/INT1 无影响，所以听筒（INT0）正常、扬声器（INT2）无声。应为 stride2=0xc。
- 预期：运行时在播放中向 macro 0x5cc 写 0x01（再 0x5c0=0x02、0x5b4=0x00）后，`route.sh ear3`/`spk` 的传感器 1 kHz 电平升高（ear3 听筒有声）。判据：>−100 dBFS（静音 −131，听筒 −88）。回退：重启（RAM 内核，默认启动是 Android）。输入：RAM 内核 m17i（Image 2df443ed…，DT 与基线仅差已撤回改动），无持久写入。
- run 8 结果（2026-11-12）：RX2 DSM/SEC7/CFG 值（0x5cc=1、0x5c0=2、0x5b4=0、0x584=18、0x588=64、0x590=03）在播放中写入，ear3 与 spk 路径传感器均无变化（1 kHz ≈ −135 dBFS）。DSM 时钟 stride 错误仍是真实的上游缺陷（需补丁、建议上游），但不是静音的单独原因。
- **run 8 续（Android SWR master 基线，2026-11-12，本机验证）**：Android 的 `/sys/kernel/debug/rx_swr_ctrl/swrm_reg_dump`（vendor swr_ctrl，debugfs 需 `mount -t debugfs`）在扬声器播放时与 Linux spk 模式（tools/swrmaster-dump.py，/dev/mem 读 0x3210000）对比：端口 2（CLSH）、4（LO）的 PORT_CTRL（EN_CHAN=1、offset、si）、帧结构（50 行 × 16 列）、BLOCK_CTRL 完全一致（活动 bank 不同：Android bank1/Linux bank0，内容相同）；只剩 vendor 专有寄存器（0x200/0x220/0x254/0x1044 等）不同。结论：**master 侧不是原因**，假设 (b) 作废。codec 0x3000–0x34ff 与 Android 仅差 TX/mic 相关位、AUXPA 的 CLK_EN(bit4)、PDM_WD_CTL2（Android 仅 EN，Linux EN|TIMEOUT_SEL|HOLD_OFF），均已试过无效或无关。剩余差异：Android 用 RX_CODEC_DMA_RX_1 + `RX_MACRO RX2 MUX=AIF2_PB`（INT2 输入=RX2，单声道），我们用 RX_CODEC_DMA_RX_0 的 RX0/RX1 车道。下一实验 m17j：只改 DT，加第二条 DAI link（RX_CODEC_DMA_RX_1 ↔ wcd9370 0 + swr1 0 + rxmacro 1），按 Android 的 mixer 路径播放。
### E027 run 9 计划：m17j（DT 单变量：加第二条 DAI link，RX_CODEC_DMA_RX_1 ↔ wcd9370 0 + swr1 0 + rxmacro 1）
- 输入：Image 2df443ed…（同 m17i）；DTB 3e305014…；boot db8434d9…（out/candidates/m17j/SHA256SUMS）；由 `M17_RX1=1 tools/gen-m17-dts.py` 生成（默认不加），无内核重编。
- 预期：声卡多一个 playback PCM（MultiMedia2 ↔ RX_CODEC_DMA_RX_1）；按 Android 路径（`RX_MACRO RX2 MUX=AIF2_PB`、`RX INT2_1 MIX1 INP0=RX2`、AUX_RDAC=1、LO Switch=1、FS1599 scene 6）播放，传感器 1 kHz 高于静音底噪 ≥20 dB，用户可听到。风险：同一个 codec DAI（wcd9370 AIF1_PB）被两条 link 使用，声卡可能 probe 失败或 SDW stream 互相覆盖；失败则记录 dmesg。回退：RAM 启动，`systemctl reboot` 回 Android；电量 ≥97%。
- **E027 run 9 结果（2026-11-12，本机验证，传感器）— 扬声器出声，根因找到**：`lpass-rx-macro.c` 对 codec version ≥2.5 设 `rxn_reg_stride2=0`，使 INT2（n=2）的 DSM_CTL/SEC7 写到 0x5c0/0x5b4，而 v2.5 的 RX2 真实寄存器是 DSM_CTL=0x5cc、SEC7=0x5c0。运行时让 RX2 的 DSM 时钟（0x5cc bit0）在路径使能前已为 1，并在播放中写 0x5c0=0x02（DSM_OUT_DELAY=2 采样）、0x5b4=0x00：`route.sh spk` 的 1 kHz 电平从 −133…−143 dBFS 升到 **−36 dBFS**（听筒路径 −88 dBFS，约 +50 dB），两次重复（−36.2/−36.0）。仅开 DSM 时钟而不修 0x5c0/0x5b4 → 4.6 kHz 附近宽带噪声（rms −55）；都不做 → 静音。这是 Linux 7.3 上游 bug（stride2 对 2.5+ 应为 0xc：`0x440+0x180+0xc=0x5cc`、`0x434+0x180+0xc=0x5c0`，与头文件 `CDC_2_5_RX_RX2_RX_PATH_DSM_CTL/SEC7` 一致）；INT0/INT1 不受影响，所以听筒/耳机一直正常。
- 内核补丁：`kernel-local/` 里补丁 + 需要重编内核（用户运行构建脚本）。运行时验证配方：`mmio.py 0x32005cc 1`（在 `route.sh spk` 之前），播放中 `mmio.py 0x32005c0 2; mmio.py 0x32005b4 0`。
### E027 run 10 计划：m18（内核补丁 rxn_reg_stride2=0xc，DT 同 m17h）
- 输入：Image 3ab666e2…（含补丁）；DTB c0b3a0bd…（同 m17h）；boot 877bdd23…（out/candidates/m18/SHA256SUMS）。
- 预期：无需任何 mmio poke，`mic-on.sh; poke-test.sh spk "true"` 的 1 kHz 电平 > −60 dBFS（运行时 poke 版 −36 dBFS）；听筒路径（route.sh ear）不退化（≈ −88 dBFS）。判据同上；失败则读 0x32005cc/0x32005c0/0x32005b4 对照 Android（01/02/00）。回退：RAM 启动，`systemctl reboot` 回 Android；电量 ≥97%。
- **E027 run 10 结果（m18，2026-11-12，本机验证）**：不做任何 poke，`poke-test.sh spk "true"`：1 kHz −41.8 dBFS（静音 −130…−143；运行时 poke 版 −36）；0x5c0=0x02、0x5b4=0x00（驱动自己写对了）；听筒路径 −94 dBFS（不退化）。**补丁有效。**
### E027 run 12 计划：冷启动音频（m18，Debian 无人手工设置）
- 输入：Image 3ab666e2…、boot 877bdd23…（m18）；rootfs 里已装 UCM/sky-fs1599/udev 规则（tools/install-audio.sh）。步骤：`ssh … systemctl reboot` 回 Android → `KERNEL=m18 tools/boot-linux.sh` → 等 GNOME 自动登录。预期：不跑任何脚本，`wpctl status` 有 Speaker 与 Bottom microphone；`pw-play` 1 kHz + `pw-record` 回采 > −70 dBFS；FS1599 在选中 Speaker 时为开。判据同上；失败读 journalctl（wireplumber、sky-fs1599）。回退：重启回 Android；电量 ≥97%。
- **E027 run 12 结果（冷启动，m18，2026-11-12，本机验证）**：Android → `KERNEL=m18 tools/boot-linux.sh` → GNOME 自动登录后不跑任何脚本：`wpctl status` 有 “Built-in Audio Speaker playback” 和 “Built-in Audio Bottom microphone”；`pw-play` 1 kHz（音量 0.4）+ `pw-record` 回采 1 kHz −54.4 dBFS；FS1599 0x11=0xc0（开）；/dev/i2c-0 属 audio 组。通过。
