# Touchscreen

FocalTech FT8720 (display-integrated controller) on SPI, mode 0, 9.6 MHz; reset on TLMM 12 (active low), interrupt on TLMM 13 (falling edge).

- A cold controller is in ROM state; after every reset the host must download the firmware (PRAM at 0x000000, DRAM at 0xd00000; lengths come from the firmware header as word counts with an inverted copy). The driver does this with `request_firmware("focaltech/ft8720-sky.bin")`.
- Frame format, command sequence and CRC16-Kermit were read from the vendor driver and validated on the bus; the driver is `drivers/input/touchscreen/focaltech-ft8720-spi.c` (patch 0005), with a binding in `Documentation/devicetree/bindings/input/touchscreen/`.
- The QUP serial engine runs in GPI-DMA mode for this device, which needs `iommus` and `dma-coherent` on the wrapper; without them DMA addresses are wrong and the bus hangs.
- Result: up to 4 simultaneous fingers, x 0-1069, y 0-2459, in GNOME.
- `edt-ft5x06` follows the panel power state (imported change) and is unrelated to this controller on this phone.
