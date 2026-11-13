# EXPERIMENT-008（E029）：加速度计/传感器总线探测

## 证据（本机 + 厂商配置）
- Android sensorservice：BOSCH bma4xy 加速度计（I2C 0x18，bus_instance 1，DRI 中断 GPIO 61，vddio 由 ADSP 的 PMIC client 管）；Memsic mmc56x3x 磁力计；ROHM bu27030 光感；备选 lis2hh12（0x1e）、sx933x。原始配置在 private/sensors/（私有）。
- AP 侧 DT 看不到这些传感器；Linux 的 i2c-0（984000）上 0x18/0x1e 无应答（NACK，本机验证）。
- 运行时 DT：tlmm `qcom,gpios-reserved = <0 1 2 3 0x12 0x13 0x14 0x15>` = GPIO0-3（qup1_se0，a80000）与 GPIO18-21（qup0_se3，98c000）保留给 ADSP，推断传感器总线在这两个 SE 之一（推测）。

## 实验 1（m17k，DT 单变量，RAM 启动）
- 输入：Image 3ab666e2…（m18）；DTB e92e4aaf…；boot 3dbd8a5e…（out/candidates/m17k/SHA256SUMS）；`M17_SENSORS=1 tools/mk-dtb-candidate.sh m17k m18`：把 se3、se5 启用为裸 I2C 主机（GPIO18/19、GPIO0/1，100 kHz，无从设备）。
- 预期：多出 /dev/i2c-1、/dev/i2c-2；`i2cget` 读 0x18 reg 0x00（BMA4xx 芯片 ID）/0x1e reg 0x0f（应为 0x41）/0x30 reg 0x39（MMC5603 产品 ID 0x10）任一应答即找到总线。
- 风险：SE 被 TZ/ADSP 划给 ADSP，AP 访问可能触发 xPU 错误→重启；传感器电源（ADSP 管）可能未供电→全 NACK（此时需要找供电）。回退：重启（默认回 Android；挂死则长按电源键）。电量 100%。
- **实验 1 结果（m17k，2026-11-12）**：失败，pinctrl `-EINVAL`：我们自己的 DTS 把 GPIO0-3、18-21 设为 `gpio-reserved-ranges`（厂商 TZ 持有），所以 se3/se5 没有启用。
### 实验 2（m17l）：同 m17k，但删除 gpio-reserved-ranges（仅本实验）
- 输入：Image 3ab666e2…；DTB/boot 见 out/candidates/m17l/SHA256SUMS。预期/判据同实验 1；额外风险：这些引脚由 TZ 持有，AP 写 TLMM 可能被 xPU 拒绝（RAZ/WI → 全 NACK）或触发错误重启。回退同上。
- **实验 2 结果（m17l，2026-11-12，本机验证）**：失败且有副作用：RAM 启动后手机没有出现在 USB/WiFi，约 7 分钟后自行回到 Android（init 的 420 s 定时器或看门狗重启；没有取得内核日志）。结论：AP 去动 TZ 持有的 GPIO0-3/18-21（或对应 SE）会让系统失联；**不要再这样做**。
- **阶段结论**：加速度计（BMA4xy）、磁力计、光感、SAR 都挂在 ADSP/TZ 持有的传感器总线上，AP 无法直接访问。可行路线只有两条：(1) 通过 ADSP 的传感器栈（SNS/QSH，QMI/FastRPC，protobuf 消息）读数据——工作量大、无上游支持，需要先查 sscrpcd/libsensor 用户态协议；(2) 让 TZ/ADSP 释放这条总线给 AP（需改 ADSP 固件配置，不可行）。优先级低，转去做 E028 与功放节电。
