# EXPERIMENT-012 (E036): log cleanup and SoC thermal zones (m25, prepared 2026-11-13)

## Goal
Remove the two things that make the kernel log and journal unusable and add the missing SoC temperature sensing, without touching anything that works (audio, display, dock, charge limit).

## Findings (m24 on the phone, 2026-11-13)
- **Journal size:** `/var/log/journal` had grown to 2 GB with no limit. Fixed live and in the rootfs build: `desktop-debian/10-sky-journal.conf` (SystemMaxUse=200M, KeepFree 2G, file size 16M, retention 2 weeks) installed by `customize.sh`/`push-debian.sh`; on the phone the cap took effect on the journald restart (2 GB → 137 MB).
- **SPMI spam root cause (verified on the phone):** `spmi spmi-0: disallowed SPMI write to sid=0, addr=0x6146` appears ~60 times per second, starting at the moment `systemd-timesyncd` first synchronises the clock (63 s after boot) and continuing for minutes. Address 0x6146 is the control register of the PMK8350 RTC block (`pmk8350_regs.ctrl`); the SPMI arbiter refuses the write because that peripheral belongs to another execution environment. Cause chain: DT has `allow-set-time` → `pm8xxx_rtc_set_time()` writes the RTC → kernel NTP "11-minute mode" (`CONFIG_RTC_SYSTOHC`, `sync_hw_clock`) tries after every sync and retries on error. **Test:** setting the kernel clock to unsynchronised (`adjtimex` STA_UNSYNC, from python/ctypes) took the rate from ~400 lines per 6 s to 0 immediately, with timesyncd stopped; with timesyncd stopped before the flag it stayed 0. (Side effect of the experiment: the phone's NTP sync flag was cleared; timesyncd is stopped until the next boot, the clock itself is right.)
- The RTC reads garbage (1970-12-28) and cannot be set by Linux; the system time comes from the network (timesyncd) or the pushed clock. That does not change.
- **WLAN noise:** the out-of-tree `qcacld` prints ~50 debug traces with `pr_err("sky-dbg…")`/`sky-c2…` from the earlier disconnect-crash investigation (tx completions, disconnect state machine, init steps) plus one error line every 6 s (`hdd_is_rcpi_applicable: mac addr is different from bssid connected`, raised by the periodic RCPI query).
- **Thermal:** `/sys/class/thermal` only has the battery zone. Mainline has no `sm4450-tsens` compatible but `qcom,tsens-v2` as the fallback is used by ROCKNIX for the same SoC; `CONFIG_QCOM_TSENS=y` is already set.

## m25 changes
1. `CONFIG_RTC_SYSTOHC` off (tools/build-m25.sh). The RTC stays registered for reading (`HCTOSYS` unchanged).
2. `drivers/spmi/spmi-pmic-arb.c`: the three "disallowed SPMI write" messages use `dev_err_ratelimited` (safety net: any other denied writer no longer floods the log).
3. DT: `tsens0` (c263000, 16 sensors) and `tsens1` (c265000, 6 sensors) plus 22 thermal zones, passive 95 °C with cpufreq cooling on the CPU zones, critical 115 °C. Source: ROCKNIX SM4450 board file (BSD-3-Clause), cross-checked with this phone's Android runtime DT (same two sensor blocks; zones aoss-0, cpu-0-0…cpu-0-5, cpuss-0/1, cpu-1-0…cpu-1-3, gpuss, camera, video, aoss-1, ddr, mdmss-0…3; Android's own trips: CPUs 110/115 °C, GPU 95 °C, hardware limit 125 °C). Fragment `dts/sky-thermal.dtsi.frag`, appended by `tools/gen-m17-dts.py`. DTB compiles (61676 bytes).
4. `qcacld` (third-party, `sources/sky-qcacld`): all `pr_err("sky-dbg…/sky-c2…")` traces became `pr_debug` (dynamic debug stays available), except the "failed to queue osif disconnect notify" error; the RCPI line became `hdd_debug`. Needs a module rebuild (`tools/build-wifi-modules.sh`, user-run), then `wlan.ko` goes to the phone like before. The kernel vermagic must stay `7.3.0-g105ba85cba0e-dirty` (same git tree); check with `modinfo`.

## Input / how to build (user runs builds)
`! tools/build-m25.sh`, then `! tools/build-wifi-modules.sh` (module vermagic check), then `tools/mk-recovery-v2.sh m25` only after the RAM boot passes. Boot test first with `fastboot boot out/candidates/m25/sky-m25-shim-boot-v4.img` (battery read in Android first); nothing is written. recovery_b keeps m24 (d8e0770e…).

## Expectation / pass criteria (RAM boot, ~5 min after boot, NTP synced)
- `dmesg | grep -c "disallowed SPMI"` ≤ 10 (was ~9000 after 5 min); `timedatectl` shows "System clock synchronized: yes".
- `ls /sys/class/thermal` shows 22 zones plus the battery; temperatures read plausible (20–60 °C at idle, no zone at 0 or absurd) and move under load (`stress`/yes loop on the CPU raises cpu zones, falls afterwards). tsens probe messages in dmesg without errors. **Risk:** a TSENS block owned by TrustZone could hang the SoC on first access (like debugfs gpio did); the RAM boot's safety timer / power-cycle returns to Android. If it hangs, drop the tsens nodes (zones not reached) and record the failure.
- No regression: card present + `fs1599` preset line, dock/evdi, charge limit, WiFi (after the module swap), Bluetooth; 0 failed units.
- journal for the boot < 2 MB for the first 10 minutes; `journalctl -b -k | grep -c sky-dbg` = 0 with the new wlan.ko.
- **Fallback:** the phone is not modified; power-cycle/`systemctl reboot` returns to Android; recovery_b is untouched.

## Build result (2026-11-13 13:40)
- `tools/build-m25.sh` exit 0 (log out/build-m25.log). out/candidates/m25: Image e6451c45…, sky-m25.dtb 96d6188b…, sky-m25-shim-boot-v4.img f260a67d…. `.config`: `# CONFIG_RTC_SYSTOHC is not set`, `CONFIG_QCOM_TSENS=y`. Kernel release `7.3.0-g105ba85cba0e-dirty` (same as m24, so modules keep loading).
- `tools/build-wifi-modules.sh` exit 0: wlan.ko b29cc7aa7e48…, wlan_firmware_service.ko 96c2b407…, icnss2.ko 38907583…, cnss_utils.ko 2a656ca0…, vermagic `7.3.0-g105ba85cba0e-dirty SMP preempt mod_unload aarch64`. Installed to /root/wifi on the phone (old m24 set backed up in /root/wifi.m24); they replace the old ones only after the next boot, the running WiFi is unaffected.
- Run 1: RAM boot of the v4 image (see below).

## Run 1 result: RAM boot of m25 (2026-11-13 13:5x, battery 80 % read in Android, `fastboot boot`, v4 image f260a67d…): PASS
- `uname -v`: `#111 SMP PREEMPT Fri Nov 13 13:40:31 CET 2026`; system running, 0 failed units. New wlan modules loaded (vermagic equal), WiFi connected, Bluetooth powered, `timedatectl`: synchronized yes.
- After 242 s of uptime (NTP synced at ~63 s): `disallowed SPMI` lines **0** (m24: ~9,000 after 5 min); `sky-dbg`/`sky-c2` lines 0; dmesg 820 lines; journal 147 MB total, 1663 lines for the whole boot (m24 boot: spam was 92 % of the log).
- Thermal: 22 new zones registered (aoss0/1, cpu0-5, cpu6-0/6-1/7-0/7-1, cpuss0/1, gpu, camera, video, ddr, modem0-3) + battery; no tsens/thermal errors in dmesg; the SoC did not hang on the TSENS access. Idle 29-31 °C (zones 36-46 °C right after boot). 8 busy loops for 60 s: cpu0 59, cpu4 54, cpu6-0 56, cpu7-1 62, gpu 43, ddr 47 °C at 40 s; 43 °C right after, 31 °C 25 s later. No throttling (trips at 95 °C not reached), cpufreq cooling not exercised.
- Not tested on m25: audio (amp), dock/evdi, charge limit; they were not touched by this change set. The phone was not moved to recovery_b: **recovery_b still holds m24 (d8e0770e…)**.
- Process note: while measuring I cleared the kernel's NTP sync flag and stopped timesyncd on the running m24 system (reboot restores both); `nmcli` output printed the WiFi network name once on screen, nothing was saved.

## Next
Persist m25 into recovery_b (same recipe as E034: `tools/mk-recovery-v2.sh m25`, readback, 3 cold boots, then check audio/dock/charge-limit) — waiting for the user's go. Also open: thermal trips tuning/GPU cooling (needs a hotter load than the phone reached), `hctosys` reading the garbage RTC at boot (harmless).
