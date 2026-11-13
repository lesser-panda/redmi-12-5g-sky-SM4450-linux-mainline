# 来源与复用调查

核查日期：2026-11-09。网页可访问不等于本机支持；尚未固定源码提交，不能用于可复现构建。

| 来源 | 已确认的内容 | 使用限制 / 下一步 |
|---|---|---|
| https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm4450.dtsi | 上游存在 SM4450 SoC 设备树 | 需固定提交、核对 USB/PHY、时钟、PMIC 和板级 DTS；不能推断 sky 能启动 |
| https://linux-msm.github.io/mainline-status/ | 社区维护 SoC 功能状态表，含 SM4450 | 状态表仅作定位线索，逐项以当前源码为准 |
| https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/sky-t-oss | 小米官方 sky-t-oss 分支可访问 | 后续清点设备树、面板、触控及启动配置；当前 PixelOS 是否使用相同基线未知 |
| https://github.com/once-human/pixelos-sky | 社区 PixelOS sky 项目线索 | 不是已安装的 2023 PixelOS 来源证明，不作为恢复镜像依据 |

待确认：本机 product/SoC 身份；实际 PixelOS build；匹配的 boot/vendor_boot/dtbo/vbmeta 获取路径；sky 主线板级移植是否已有可复用实现。

## 用户指定的首要参考

https://github.com/orange200213/sky-linux — 已下载并固定 d78c42a27e403f8207e813e051f3b1e142ffb101；详见 SKY-LINUX-REVIEW.md。迁移时应包含 sources/sky-linux 或按此提交重新获取。

## 匹配当前系统的恢复来源

设备 ro.modversion=PixelOS_sky-14.0-20240922-0137（private/recovery-investigation/android-build.txt）。
- ROM：https://sourceforge.net/projects/pixelos-releases/files/fourteen/sky/PixelOS_sky-14.0-20240922-0137.zip/download
- 页面公布 SHA-256：f37e76809187646b24408fda323f8f11851d347f30969fc17d295b19bc8e3b48
- recovery：https://sourceforge.net/projects/pixelos-releases/files/fourteen/sky/recovery/recovery-sky-20240922.img/download
- 官方设备页：https://pixelos.net/download/sky
版本字符串匹配不等于本机分区逐字节匹配，下载和解包后仍需验证。

ROM 获取状态更新：完整文件已由用户提供并于 2026-11-09 独立复核哈希通过；提取镜像、工具版本和验证边界见 RECOVERY.md。
