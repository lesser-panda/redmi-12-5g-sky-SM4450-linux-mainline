# 触摸屏

FocalTech FT8720（显示一体化控制器），SPI mode 0，9.6 MHz；复位在 TLMM 12（低有效），中断在 TLMM 13（下降沿）。

- 冷启动的控制器处于 ROM 态；每次复位后主机必须下载固件（PRAM 在 0x000000，DRAM 在 0xd00000；长度来自固件头里"字数 + 按位取反副本"）。驱动通过 `request_firmware("focaltech/ft8720-sky.bin")` 完成。
- 帧格式、命令序列和 CRC16-Kermit 取自厂商驱动并在总线上验证；驱动为 `drivers/input/touchscreen/focaltech-ft8720-spi.c`（补丁 0005），绑定文档在 `Documentation/devicetree/bindings/input/touchscreen/`。
- 该设备的 QUP 串行引擎走 GPI-DMA 模式，wrapper 需要 `iommus` 和 `dma-coherent`；否则 DMA 地址错误、总线挂死。
- 结果：最多 4 指同时触控，x 0–1069，y 0–2459，GNOME 下可用。
- `edt-ft5x06` 跟随面板电源状态（导入的改动），与这台手机上的这颗控制器无关。
