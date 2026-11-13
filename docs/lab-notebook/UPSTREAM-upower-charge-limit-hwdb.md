# Draft (not sent, nothing published): UPower charge limit on devicetree-only machines

Status: draft for the user to review. No publication is authorised; nothing has been sent anywhere.

## Problem
UPower 1.90.x sets `ChargeThresholdSupported` only when the udev property `CHARGE_LIMIT="<start>,<end>"` exists on the battery
(src/linux/up-device-supply-battery.c, `up_device_supply_battery_get_charge_control_limits`). The property comes from
`60-upower-battery.rules` → hwdb key `battery:<kernel>:<model_name>:<dmi modalias>`; the shipped generic entry is `battery:*:*:dmi:*`
(`CHARGE_LIMIT=75,80`). On a machine without DMI (devicetree: Qualcomm laptops, phones) the last key part is empty, the key ends in `:`
and `battery:*:*:dmi:*` never matches, although the kernel driver exposes `charge_control_{start,end}_threshold`. Measured on this
phone (Debian trixie, upower 1.90.9): `systemd-hwdb query "battery:battery:<model>:"` → no match; with `dmi:x` appended → `CHARGE_LIMIT=75,80`.

## Options for upstream
1. hwdb: add a second generic entry that matches the empty-DMI key, e.g. `battery:*:*:` (still gated by the rule's
   `ATTR{charge_control_start_threshold}!=""`, so only batteries whose driver offers thresholds are affected).
2. rules: build the key with a placeholder when `[dmi/id]modalias` is absent.
3. Per-model entry (what this project does locally): `battery:battery:NVT_WINGTECH_S88019AA1*:` → `CHARGE_LIMIT=75,80`
   (desktop-debian/61-sky-battery.hwdb).

Option 1 or 2 fixes every devicetree machine at once; to be checked against UPower's own tests before proposing.
