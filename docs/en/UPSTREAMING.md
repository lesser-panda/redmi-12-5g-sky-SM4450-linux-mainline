# Upstreaming candidates

Nothing from this project has been submitted yet. Candidates, roughly from easiest to hardest:

| Change | Where | Why it should go upstream | Work left |
|---|---|---|---|
| `lpass-rx-macro`: DSM clock register stride for codec >= 2.5 | patch 0007 | real bug: the INT2 speaker path never gets its clock on affected codecs | write a clean commit message, test on a second device |
| `pwrseq-qcom-wcn`: minimum power-off time | patch 0006 | WCN controllers need ~0.5 s with the rail off to reset | make the delay a property, check other users |
| UPower hwdb entry for charge thresholds | `rootfs/61-sky-battery.hwdb` | lets GNOME show the charge limit for devices that expose the threshold properties | upstream UPower has no generic rule; draft kept in the lab notebook (`UPSTREAM-upower-charge-limit-hwdb.md`) |
| `focaltech-ft8720-spi` touch driver + binding | patch 0005 | no mainline driver for this controller | clean up, split binding, firmware loading policy |
| `fs1599` amplifier driver | patch 0007 | no mainline driver for FourSemi FS1599 | binding, drop the hard-coded scene default, review the sequences against the vendor source |
| Xiaomi sky panel | patch 0004 | board-specific; only useful with the DT | submit with the DT |
| SM4450 platform pieces (clocks, interconnect, SMMU, PAS, regulators) | patch 0001 | mostly ROCKNIX work; SM4450 support is upstream in part | rebase on the upstream SM4450 series, credit the authors |
| `qcom_battmgr` Xiaomi software charge limit | patch 0008 | vendor-specific property | probably stays out of tree |
| WCN6750 WiFi | out of tree | the SNOC/ath11k limitation is in firmware | nothing without Qualcomm |
