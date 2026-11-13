# Battery, charging, suspend, keys

## Battery and charging
Battery telemetry (capacity, voltage, health, cycle count) and USB-C charging come from the ADSP through `pmic_glink` (`qcom_battmgr`, UCSI). The ADSP firmware is required for any of it.

**Charge limit.** The standard charge-threshold properties are not implemented by this firmware, but Xiaomi's private `input_suspend` control (battery-manager property 3, opcode 0x51) is.
Patch 0008 adds a software limiter inside `qcom_battmgr`: the kernel exposes `charge_control_start_threshold` / `charge_control_end_threshold`
(default 75 / 80 %) and stops charging at the end threshold, resuming at the start threshold. It held through a 6.5 h load test (22 transitions).
`rootfs/61-sky-battery.hwdb` tells UPower the phone supports thresholds so that GNOME Settings can show the option (UPower has no generic rule for this yet).

## Keys, clock
Power, volume up and volume down work (the PDC wake ranges had to be overridden with the phone's runtime values). The PMIC RTC works but does not keep the time across a full power loss; NTP sets it.

## Suspend
Both `s2idle` and deep (PSCI) suspend enter and resume; wake sources RTC, power key, volume up. USB-gadget networking returns after the `dwc3-qcom` UTMI clock selection is re-applied on resume (patch 0008).
A time warning: **kernel time does not include suspended time**; measure suspend with wall-clock stamps, not `dmesg` deltas (an early "wakes in 40 ms" result was this mistake).
With the DisplayLink dock attached, some suspends end after 0.1-2 s by themselves (wake source unknown, see [KNOWN-ISSUES.md](KNOWN-ISSUES.md)). The GNOME power key action is "nothing/screen only" and idle suspend is off in the default image.

## USB
Peripheral mode: ACM serial + NCM network (the development link). Host mode: xHCI with storage, UAS, HID, USB Ethernet, USB audio class enabled. The USB PHY supply rails (L5B/L23B/L25B) must be declared or the gadget dies when the ADSP comes up.
USB goes through the SMMU (`iommus = <&apps_smmu 0x540 0x0>`); see [GPU.md](GPU.md) for why that matters.
