# Audio

Working: loudspeaker, earpiece, bottom microphone, PipeWire/WirePlumber with a UCM profile. Not tested: headphone jack, USB audio, Bluetooth audio.

## Signal path

```
ADSP (AudioReach: GPR, q6apm, q6prm)  --SoundWire-->  LPASS macros (RX, TX, VA)  -->  WCD9370 codec
   sound card: sc8280xp-style machine driver, card model "Redmi-12-5G"
   earpiece : RX macro INT0 -> HPHL / EAR
   speaker  : RX macro INT2 -> AUX output of the WCD9370 -> FS1599 amplifier (I2C 0x34) -> speaker
   mic      : bottom microphone -> WCD9370 TX -> TX macro (two decimator lanes)
```

- The ADSP firmware comes from your own `modem_a` partition. The AudioReach **topology** (`qcom/sm8450/Redmi-12-5G-tplg.bin`) is built from the
  upstream `SM8450-HDK` topology by `tools/build-topology.sh` and built into the kernel image.
- **FS1599 amplifier** (FourSemi, I2C 0x34 on the same QUP bus as the backlight; 8-bit registers, 16-bit big-endian values). Mainline has no driver.
  `sound/soc/codecs/fs1599.c` (patch 0007) registers an ASoC component with widgets `IN -> AMP -> OUT`. The `AMP` widget powers the amplifier
  on its way up (reset, load the vendor preset for scene 6 from `foursemi/fs1599.fsm`, start-up sequence) and shuts it down on the way
  down. The sound card lists it as an `aux-dev` and routes `"Spk Amp IN" <- "AUX"`, so DAPM powers it only while the speaker path (WCD AUX output) is active;
  the earpiece path leaves it off. The register sequences were taken from the vendor `fs15xx` module and verified by reading back.
  An earlier userspace watcher that followed the PipeWire sink state clipped the first ~0.1 s of sounds and could be broken by a second copy running for root's user manager; it is gone.
- The speaker was silent for a long time because of a bug in upstream `lpass-rx-macro`: for codec versions >= 2.5 the DSM clock registers of INT2 are at the wrong stride, so the speaker interpolator clock never started
  (patch 0007; a candidate for upstream, see [UPSTREAMING.md](UPSTREAMING.md)).
- Do not add the non-upstream `qcom,*-channel-mapping` properties to the device tree; they mangle the SoundWire channel mask of the earpiece.
- The UCM profile is in `rootfs/ucm2/Xiaomi/sky/` and enables the AUX_RDAC/LO/CLSH switches and the RX macro routing for the Speaker device and the INT0 path for the Earpiece.

## Checking it

```sh
aplay -l                       # card "Redmi-12-5G"
wpctl status                   # sinks "Speaker", "Earpiece"; source "Bottom microphone"
# amplifier state: reg 0x11 = 0x00c0 while playing, 0x0000 when idle
i2ctransfer -f -y 0 w1@0x34 0x11 r2@0x34
```

Measuring loudness with the built-in microphone (loopback) was unreliable in our tests; use your ears or an external microphone.
