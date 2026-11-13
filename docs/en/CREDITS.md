# Credits

- **ROCKNIX** ([github.com/ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)): the SM4450 kernel patch queue (GPU, display, clocks, interconnect, remoteprocs, regulators, Bluetooth, battery). Authors are preserved in `kernel/third-party/rocknix/`.
- **orange200213 / sky-linux** ([github.com/orange200213/sky-linux](https://github.com/orange200213/sky-linux)): first mainline bring-up of the sky, the shim boot method, the `ktd3136` driver, and the WiFi driver port that is used as is.
- **Linux kernel, linux-msm, Linaro, Qualcomm** upstream developers: `sm8450` audio, `sc8280xp` sound card, AudioReach topologies (`linux-msm/audioreach-topology`, BSD-3-Clause), `panel-visionox-r66451`.
- **Mesa** freedreno/turnip authors; **Debian** and **GNOME** projects; **Alpine Linux** for the small initramfs userland; **DisplayLink/Synaptics** (`evdi` is GPL-2.0, the manager binary is proprietary and not distributed).
- **PixelOS** project for the ROM the tested firmware comes from. Xiaomi's GPL kernel source and the phone's own device trees were used as references for protocols and numbers. Some drivers are derived from downstream vendor code (for example the SM4450 interconnect driver, which says so in its header); original copyright and SPDX headers are kept.
- Written in this repository: the panel, touch and FS1599 drivers, board device tree, initramfs, scripts and documents. The work was done by Andy Zhang with Claude (Anthropic) as the coding assistant.

If you contributed something that is used here and is not credited correctly, please open an issue.
