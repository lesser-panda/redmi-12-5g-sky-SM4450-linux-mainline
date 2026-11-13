# 电池、充电、休眠、按键

## 电池与充电
电池遥测（容量、电压、健康、循环次数）和 USB-C 充电经 `pmic_glink` 由 ADSP 提供（`qcom_battmgr`、UCSI）。没有 ADSP 固件这一切都不可用。

**充电上限。** 这套固件没有实现标准的充电阈值属性，但实现了小米私有的 `input_suspend` 控制（电池管理器属性 3，opcode 0x51）。补丁 0008 在 `qcom_battmgr` 里加了软件限制器：内核暴露 `charge_control_start_threshold` / `charge_control_end_threshold`（默认 75 / 80 %），在结束阈值停止充电，在起始阈值恢复。它扛过了 6.5 小时负载测试（22 次切换）。`rootfs/61-sky-battery.hwdb` 告诉 UPower 这台手机支持阈值，让 GNOME 设置显示该选项（UPower 对此还没有通用规则）。

## 按键、时钟
电源、音量加、音量减可用（PDC 唤醒范围需要用手机运行时的值覆盖）。PMIC RTC 能工作，但完全断电后不保持时间；靠 NTP 校时。

## 休眠
`s2idle` 与 deep（PSCI）休眠都能进入并恢复；唤醒源 RTC、电源键、音量加。重新应用 `dwc3-qcom` 的 UTMI 时钟选择后，USB gadget 网络在恢复后回来（补丁 0008）。
时间提示：**内核时间戳不含休眠时间**；判断休眠要用墙上时钟，不要用 `dmesg` 差值（早期"40 毫秒就醒"的结论就是这个误读）。接着 DisplayLink 坞时，有些休眠 0.1–2 秒就自己结束（唤醒源未知，见 [KNOWN-ISSUES.md](KNOWN-ISSUES.md)）。默认镜像里 GNOME 电源键动作为只熄屏/唤醒屏幕，空闲休眠关闭。

## USB
设备模式：ACM 串口 + NCM 网络（开发用链路）。主机模式：xHCI，已启用存储、UAS、HID、USB 以太网、USB 声卡类。USB PHY 的供电轨（L5B/L23B/L25B）必须声明，否则 ADSP 起来后 gadget 会死。USB 走 SMMU（`iommus = <&apps_smmu 0x540 0x0>`）；原因见 [GPU.md](GPU.md)。
