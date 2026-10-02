# IntelHDA for OPENSTEP

IntelHDA is an OPENSTEP 4.2 driver for Intel High Definition Audio controllers.
It provides analog playback through one codec and output path, supporting
16-bit PCM mono/stereo. The driver probes 8, 16, 22.05, 32, 44.1 and 48 kHz
while stopped and verifies the selected codec's format register. If the codec
supports 44.1 kHz but not 22.05 kHz, the driver converts 22.05 kHz playback to
44.1 kHz so OS sound effects remain available. Other available rates depend
on the codec.
Recording, 8-bit PCM and 11.025 kHz playback are unsupported.

## Requirements

- OPENSTEP 4.2 for Intel processors
- A compatible Intel HDA controller and analog codec; conventional MSI capability is required for the default mode
- [PCIMSI](https://github.com/turbolent/PCIMSI) 0.32 installed and loaded before IntelHDA for MSI

| `Interrupt Mode` | Requirement |
| --- | --- |
| `MSI` (default) | PCIMSI 0.32 |
| `Polling` (recovery) | No PCIMSI allocation required |

Polling must be selected explicitly; MSI setup failures do not switch modes.
Legacy INTx and MSI-X are not supported.

## Installation

First, install PCIMSI 0.32 unless you will use Polling mode.
On the ALC889 system, install the required BusMasterIDE update as well.

Open `IntelHDA.config`.
Configure.app should open and confirm the driver was installed.
Click Add, select `Intel High Definition Audio`, and add the driver.
If the driver is not shown, check `Show All Installed Drivers` and select it.

If the controller is not automatically detected, click Expert and set `Location`
to the controller's PCI coordinates using this exact syntax:

```text
Dev:<device> Func:<function> Bus:<bus>
```

For example, PCI bus 0, device 27, function 0 is `Dev:27 Func:0 Bus:0`.
Use the coordinates reported for your audio controller.
Keep `Interrupt Mode` set to `MSI`, or explicitly set it to `Polling` if needed.
Do not add IRQ resources. Click Done, click Save, and Quit.

Verify the `Location` and `Interrupt Mode` values in
`/private/Drivers/i386/IntelHDA.config/Instance0.table`.
For Polling, set `"Interrupt Mode" = "Polling";` in that file.

In `/private/Drivers/i386/System.config/Instance0.table`, verify that `PCIMSI`
appears after `PCIBus` in `Boot Drivers` when using MSI. IntelHDA must appear
in **`Active Drivers`**, not `Boot Drivers`, so OPENSTEP registers its SoundKit
audio server. Preserve the other driver entries. Other drivers may still
require PCIMSI when IntelHDA uses Polling.

Restart OPENSTEP to load the driver, then check playback through the connected
analog output. To update an existing installation, back up `IntelHDA.config`
and the System table, replace the bundle, and preserve your `Instance0.table`
settings before restarting. The driver does not support live unloading or
replacement.

To check the loaded driver, selected output and interrupt status, run:

```sh
/private/Drivers/i386/IntelHDA.config/intelhda-status
```
