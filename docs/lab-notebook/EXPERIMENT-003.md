# E003：原包 boot 的 RAM 启动对照

目的：区分 E002 是 Magisk 改动导致，还是 fastboot boot/原包 boot 与当前启动环境的不一致。
输入：private/rom/extracted/boot.img，SHA-256 5c36ecdd2ffdb216bb1136dd8e136122fb0c3923cea40099eeeae1746da40c84；无任何修改。
同样 B 槽、同样 fastboot boot，判据 sys.boot_completed=1 且 activity 可用；失败保存日志并 adb reboot 返回原系统。
E002 回退已确认 sys.boot_completed=1、B 槽、无运行中 Magisk（rollback-status.txt）。
本次不 flash、不切槽。若同样失败，则停止重复 RAM 试验，改为离线检查 bootloader/启动输入差异，不自动刷 Magisk。
