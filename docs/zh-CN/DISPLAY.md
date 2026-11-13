# 显示与背光

- **面板：** 小米 "m19_42_03_0b"，1080x2460，4 条 DSI lane，视频模式 + DSC。时序、DSC 参数和 DCS 初始化/关闭序列从手机自己的 `dtbo` 读出（运行时设备树里只有占位面板）。驱动：`drivers/gpu/drm/panel/panel-xiaomi-sky.c`，为本项目所写，结构参照 `panel-visionox-r66451.c`。
- **显示管线：** MDSS/DPU 8.6（`dpu_8_6_sm4450.h`）、DSC、DSI 控制器与 PHY，由 `msm` 驱动。ABL 让面板亮着并显示 splash 帧缓冲（continuous splash）；补丁让驱动接管该帧缓冲并停止启动扫描输出。
- **背光：** I2C 0x36 上的 KTD3136（`ktd3136.c`，从 sky-linux 导入）。sky-linux 里的芯片初始化表（取自另一款手机）会让满亮度偏暗；改用本机 Android 的值（寄存器 0x13/0x17/0x18/0x1a/0x1c/0x24）后正常。
- **刷新率：** 驱动只暴露一个模式，1080x2460 @ 90 Hz（像素时钟 274.5 MHz）。厂商设备树里还列有 60、49、30 Hz 变体，未实现。
- **光标：** 外接 DisplayLink 显示器时 GNOME 需要软件光标，见 [DOCK.md](DOCK.md)。

为什么 bootloader 很重要：只有 ABL 让面板保持点亮，显示才能起来。没有有效 `recovery_dtbo` 的启动镜像会让 ABL 关掉面板，驱动无法冷启动它（[ARCHITECTURE.md](ARCHITECTURE.md)）。
