# 音频

可用：扬声器、听筒、底部麦克风、带 UCM 配置的 PipeWire/WirePlumber。未测：耳机孔、USB 声卡、蓝牙音频。

## 信号通路

```
ADSP（AudioReach：GPR、q6apm、q6prm）  --SoundWire-->  LPASS macro（RX、TX、VA）  -->  WCD9370 编解码器
   声卡：sc8280xp 风格的 machine 驱动，卡型号 "Redmi-12-5G"
   听筒 ：RX macro INT0 -> HPHL / EAR
   扬声器：RX macro INT2 -> WCD9370 的 AUX 输出 -> FS1599 功放（I2C 0x34）-> 扬声器
   麦克风：底部麦克风 -> WCD9370 TX -> TX macro（两条 decimator 通道）
```

- ADSP 固件来自你自己的 `modem_a` 分区。AudioReach **拓扑**（`qcom/sm8450/Redmi-12-5G-tplg.bin`）由 `tools/build-topology.sh` 从上游 `SM8450-HDK` 拓扑构建，并内置进内核镜像。
- **FS1599 功放**（FourSemi，I2C 0x34，与背光同一条 QUP 总线；寄存器 8 位、值 16 位大端）。主线没有驱动。`sound/soc/codecs/fs1599.c`（补丁 0007）注册一个 ASoC component，widget 为 `IN -> AMP -> OUT`。`AMP` widget 在上电路径上给功放上电（复位、载入 `foursemi/fs1599.fsm` 的场景 6 预设、start-up 序列），在下电路径上关闭。声卡把它列为 `aux-dev`，并路由 `"Spk Amp IN" <- "AUX"`，因此 DAPM 只在扬声器通路（WCD AUX 输出）激活时给它上电；听筒通路让它保持关闭。寄存器序列取自厂商 `fs15xx` 模块并经读回验证。早先一个跟随 PipeWire sink 状态的用户态 watcher 会削掉声音开头约 0.1 秒，而且 root 的用户管理器会再跑一份把它搞坏；它已被删除。
- 扬声器曾长期无声，原因是上游 `lpass-rx-macro` 的一个 bug：对 codec 版本 >= 2.5，INT2 的 DSM 时钟寄存器步长错了，扬声器内插器时钟从未启动（补丁 0007；可上游，见 [UPSTREAMING.md](UPSTREAMING.md)）。
- 不要在设备树里加非上游的 `qcom,*-channel-mapping` 属性；它们会把听筒的 SoundWire 通道掩码改错。
- UCM 配置在 `rootfs/ucm2/Xiaomi/sky/`：Speaker 设备打开 AUX_RDAC/LO/CLSH 开关和 RX macro 路由，Earpiece 走 INT0 通路。

## 检查

```sh
aplay -l                       # 声卡 "Redmi-12-5G"
wpctl status                   # sink "Speaker"、"Earpiece"；source "Bottom microphone"
# 功放状态：播放时 reg 0x11 = 0x00c0，空闲时 0x0000
i2ctransfer -f -y 0 w1@0x34 0x11 r2@0x34
```

用内置麦克风做回环测响度在我们的测试里不可靠；请用耳朵或外接麦克风。
