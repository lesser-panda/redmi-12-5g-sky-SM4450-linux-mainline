# DisplayLink 坞（外接显示器、键盘、鼠标）

本内核没有尝试经 USB-C 口原生输出视频；但 **DisplayLink** USB 坞可用：HDMI 显示器 1920x1080@60（走 USB 2）、键盘、鼠标。用户已确认。

- 需要树外的 `evdi` 内核模块（必须针对启动镜像里的同一个内核构建：`tools/build-evdi.sh`）和 Synaptics 专有的 DisplayLink 驱动（`DisplayLinkManager`，请自行从厂商下载 "USB Graphics Software for Ubuntu 6.4"；它不可再分发，也不在本仓库里）。`tools/displaylink-stage.sh` 打包各部分，`rootfs/displaylink/` 是我们的胶水（服务单元、安装脚本）。
- **光标：** 外接屏上硬件光标几乎透明。GNOME 通过 `/etc/environment.d/90-sky-sw-cursor.conf` 以 `MUTTER_DEBUG_DISABLE_HW_CURSORS=1`（软件光标）启动。代价：每次指针移动都要重绘部分画面。evdi 光标平面的根因未调查。
- evdi 必须在 gnome-shell 启动之前就位，否则 Mutter 的显示器列表是过期的；`sky-evdi.service` 提前加载它。会话运行期间重新插拔坞可以正常工作。
- 坞上休眠的已知问题见 [KNOWN-ISSUES.md](KNOWN-ISSUES.md)。
