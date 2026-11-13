# Third-party work in the kernel patches

`kernel/patches/` is the exact difference between a clean Linux 7.3 tree and the tree this project built and tested.
A large part of it was not written here. This directory keeps the original patch files so authorship and
history stay visible. They are reference copies; the working code is in `kernel/patches/`
(several of them needed manual fixes for 7.3, so they do not apply unchanged).

| Source | Pinned at | What we took | License |
|---|---|---|---|
| [ROCKNIX distribution](https://github.com/ROCKNIX/distribution), `projects/ROCKNIX/devices/SM4450/patches/linux/` | `e0fb1430ceaf7a7144be06751730c3d06325fe54` | 37 of the 49 SM4450 patches: A613 catalog, gpucc/dispcc fixes, rpmhpd, interconnect, SMMU, PAS remoteproc, RPMh regulators, pd-mapper, UFS PHY, Bluetooth WCN3950, battmgr, LPG, edt-ft5x06, rsinput, aw88166 and others (`rocknix/`). The 12 patches that did not apply or were not needed are not included. Authors are preserved in each file's `From:` line; see the log in `docs/lab-notebook/` for which applied cleanly. | GPL-2.0 (kernel patches) |
| [sky-linux](https://github.com/orange200213/sky-linux) (orange200213) | `d78c42a27e403f8207e813e051f3b1e142ffb101` | `ktd3136.c` backlight driver, the pinctrl TZ-protected-GPIO patch (`sky-linux/`), the shim boot method (fetched at build time, not copied), WiFi vendor-driver port (fetched at build time) | GPL-2.0 (see `sky-linux/LICENSE`) |
| Linaro / Qualcomm upstream | Linux 7.3 | `sm8450` audio and SoC node shapes the DTS and the sc8280xp sound card build on; `panel-visionox-r66451.c` as the structure model for the panel driver | GPL-2.0 / BSD-3-Clause |

Written for this project (authors: Andy Zhang and contributors): `panel-xiaomi-sky.c`, `focaltech-ft8720-spi.c`, `fs1599.c`,
the lpass-rx-macro stride fix, the qcom_battmgr software charge limit, the dwc3-qcom resume fix, the DTS and all scripts.

If you are an author of anything listed here and want it credited differently, open an issue.
