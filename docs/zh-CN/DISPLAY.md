# 显示与背光

- **面板：** 小米 "m19_42_03_0b"，1080x2460，4 条 DSI lane，视频模式 + DSC。时序、DSC 参数和 DCS 初始化/关闭序列从手机自己的 `dtbo` 读出（运行时设备树里只有占位面板）。驱动：`drivers/gpu/drm/panel/panel-xiaomi-sky.c`，为本项目所写，结构参照 `panel-visionox-r66451.c`。
- **显示管线：** MDSS/DPU 8.6（`dpu_8_6_sm4450.h`）、DSC、DSI 控制器与 PHY，由 `msm` 驱动。ABL 让面板亮着并显示 splash 帧缓冲（continuous splash）；补丁让驱动接管该帧缓冲并停止启动扫描输出。
- **背光：** I2C 0x36 上的 KTD3136（`ktd3136.c`，从 sky-linux 导入）。sky-linux 里的芯片初始化表（取自另一款手机）会让满亮度偏暗；改用本机 Android 的值（寄存器 0x13/0x17/0x18/0x1a/0x1c/0x24）后正常。
- **刷新率：** 驱动只暴露一个模式，1080x2460 @ 90 Hz（像素时钟 274.5 MHz）。厂商设备树里还列有 60、49、30 Hz 变体，未实现。
- **光标：** 外接 DisplayLink 显示器时 GNOME 需要软件光标，见 [DOCK.md](DOCK.md)。

为什么 bootloader 很重要：只有 ABL 让面板保持点亮，显示才能起来。没有有效 `recovery_dtbo` 的启动镜像会让 ABL 关掉面板，驱动无法冷启动它（[ARCHITECTURE.md](ARCHITECTURE.md)）。

## 旋转
Linux 读不到加速度计（见 [STATUS.md](STATUS.md) 的传感器一行），屏幕不会自动旋转。`sky-rotate` GNOME Shell 扩展（`rootfs/sky-rotate/`）在顶栏加一个下拉按钮：**Portrait**（竖屏）、**Landscape left**（手机顶部朝左，前置摄像头孔在左边）、**Landscape right**（顶部朝右），当前选项带圆点。
它通过 Mutter 的 `org.gnome.Mutter.DisplayConfig` D-Bus 服务只修改内置屏的旋转（缩放、模式和扩展坞显示器保持不变）。配置按临时配置应用，可避免 Mutter 的“保留这些显示设置？”倒计时，所以扩展把选择记在 `~/.config/sky-rotate/orientation`，登录后两秒再应用一次。
触屏键盘会跟随方向（竖屏布局或分体布局，见 [KEYBOARD.md](KEYBOARD.md)）。安装：`tools/push-debian.sh` 把它放进根文件系统并默认启用；在已运行的手机上，把 `rootfs/sky-rotate/` 复制到 `~/.local/share/gnome-shell/extensions/sky-rotate@redmi-12-5g.local`，再重新登录（Wayland 只在新会话里发现新扩展）。
