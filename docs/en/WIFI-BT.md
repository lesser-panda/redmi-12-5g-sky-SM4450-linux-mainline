# WiFi and Bluetooth

## WiFi (works, vendor driver)
The chip is a Qualcomm **WCN6750 ("adrastea") on the SNOC bus**, not PCIe, running on the **WPSS** subsystem. Mainline `ath11k` cannot drive it: with this SNOC firmware the application processor may only reach a small
window of the chip's registers and 12 copy-engine shadow slots, but ath11k needs to program the rings itself. What works is the vendor `qcacld-3.0` stack ported to 7.3 by sky-linux (`icnss2`, `cnss_utils`, `wlan_firmware_service`, `wlan`; built out of tree by `tools/build-wifi-modules.sh`, kernel and modules must match).

What the kernel provides: WPSS as a remoteproc (`qcom,sm4450-wpss-pas`, firmware `adrastea/wpss.mdt`, split image: the `.mdt` name matters, the `bNN` parts are derived from it), IPCC, AOSS QMP, SMP2P, QRTR over SMD/glink, a `qcom,icnss` node, the MSA reserved region and the TLMM reserved pins.
Firmware (WPSS, `regdb.bin`, board data `bdwlan*`) comes from your own `modem_a`. Result: scan, WPA2 association, DHCP, internet, ~96 Mbit/s link.

## Bluetooth (works)
Not the same chip as WiFi: a WCN3950-class controller on UART2 (`/dev/ttyHS0`, hardware flow control, 115200 baud start), mainline `hci_qca` plus small patches to treat WCN3950 like the WCN family.
Firmware `qca/cmbtfw13.tlv` and NVM `qca/cmnv13*.bin` from your `bluetooth_a` partition. The controller needs its supply rail really off for about 0.5 s to reset: the first power-on after boot failed intermittently until the power sequencer was changed to hold a 1 s minimum off time (10/10 cold boots afterwards).
