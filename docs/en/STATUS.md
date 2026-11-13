# Status: what works

Tested on one Redmi 12 5G (23076RN4BI), Linux 7.3, Debian 13 + GNOME (Wayland), kernel build 2026-11-13. "Verified" means
checked on the phone, with the evidence in the [lab notebook](../lab-notebook/); "by user" means a human saw or heard it.

| Area | State | Notes |
|---|---|---|
| CPU, RAM | works | 8 cores, full 8 GB (memory pattern test, no mismatches). cpufreq works; 22 SoC thermal zones (CPU, GPU, DDR, modem, camera, video) read plausible temperatures and follow a load test (about 60 C with 8 busy cores, back to 31 C in 25 s); the 95 C throttling trips are in the DT but have not been reached |
| Storage (UFS) | works | HS-G3 x2, ~930 MB/s sequential read; ext4 root on the internal flash |
| Display | works (by user) | DSI panel 1080x2460 with DSC, driven by `msm`; brightness via KTD3136 |
| GPU | works | Adreno 613, Mesa freedreno (GLES 3.2) and turnip (Vulkan 1.0); GNOME runs accelerated |
| Touchscreen | works (by user) | FocalTech FT8720 over SPI, multitouch; the host downloads the firmware at every reset |
| WiFi | works | WCN6750 through the vendor `qcacld` driver, built out of tree; WPA2, ~96 Mbit/s link. Mainline ath11k cannot drive this variant |
| Bluetooth | works | WCN3950-class chip on UART2 (mainline `hci_qca`); needs a 1 s power-off to reset reliably |
| Audio | works (by user) | Speaker (FS1599 amplifier, in-kernel driver), earpiece, bottom microphone, PipeWire + UCM. Headphone jack, USB audio class and Bluetooth audio not tested |
| USB | works | device mode (ACM + NCM gadget), host mode, DisplayLink dock (HDMI monitor, keyboard, mouse) via evdi |
| Touch keyboard | works (by user) | GNOME's on-screen keyboard with our layouts: ortholinear portrait keyboard (with Esc/Tab/Ctrl/Alt/arrows) and a Planck-style landscape split keyboard with a click-through gap, see [KEYBOARD.md](KEYBOARD.md) |
| Battery, charging | works | telemetry, charge status, software charge limit (stop at 80 %, resume at 75 %) via a Xiaomi-specific control |
| Keys, RTC | works | power, volume up/down; the PMIC RTC cannot be set from Linux (another subsystem owns it) and reads garbage; the clock comes from NTP, kernel to RTC sync is disabled |
| Suspend | partly | s2idle and deep suspend enter and resume (RTC, power key, volume up); with the dock attached the phone sometimes wakes by itself after 0.1-2 s, source unknown. GNOME is configured not to suspend on idle |
| Stability | verified | 6.5 h synthetic load test (CPU, memory pressure, storage verify, GPU, WiFi) with no kernel errors, OOM kills or data errors |
| Cellular modem | not working | calls, SMS, mobile data not started (modem is firmware on the ADSP/modem subsystem) |
| Cameras | not working | not started |
| Sensors | not working | accelerometer, magnetometer, light, proximity sit on a bus owned by the ADSP/TrustZone; direct access from Linux freezes the SoC. Would need the ADSP sensor stack |
| GPS, NFC, fingerprint reader, vibrator, headphone jack, FM | not investigated | |
| Video encode/decode | not started | software decode only |

## Boot paths

| Path | Writes to the phone? | Use |
|---|---|---|
| `fastboot boot` the built image | no | try a kernel, development. Reboot returns to Android |
| image in the `recovery_b` partition | one partition | `adb reboot recovery` starts Linux without a PC; a normal reboot starts Android |
| Linux root on its own partitions (`sda21`/`sda22`) | repartitions the main flash chip (**erases Android data**) | the desktop system. Without it the same kernel runs from a RAM root |

## What the project does not claim

It is a bring-up, not a distribution: no installer, no OTA updates, no supported upgrade path, and one test device.
Known problems and workarounds are listed in [KNOWN-ISSUES.md](KNOWN-ISSUES.md).
