# Device Batteries

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin
that shows the battery levels of all your wireless peripherals in one place.

![bar widget](assets/bar.png)

- **Bar pill** shows the device with the lowest battery (icon + percent),
  orange below the warning level, red below 10 %, accent color while charging
- **Popout** lists every device with its level
- **Low battery warning**: one desktop notification per device, re-armed after
  charging

## Sources

| Source | Devices | Needs |
|---|---|---|
| UPower | phones (iPhone/Android over Bluetooth), Bluetooth mice, keyboards, headphones, controllers | `upower` (already used by DMS) |
| [OpenRazer](https://openrazer.github.io/) | Razer wireless mice, keyboards, headsets | `openrazer-daemon` running |
| [HeadsetControl](https://github.com/Sapd/HeadsetControl) | USB wireless headsets (Logitech/Astro, SteelSeries, HyperX, Corsair, …) | `headsetcontrol` ≥ 4.2 for the Astro A50 Gen 5 |

UPower devices update live. OpenRazer and HeadsetControl are read by the
bundled helper `device-batteries.py` at the configured interval. Every source
is optional – whatever is not installed is skipped.

## Installation

```sh
cd ~/.config/dms/plugins
git clone https://github.com/joshii-h/dms-device-batteries deviceBatteries
```

Then enable **Device Batteries** in DMS Settings → Plugins and add it to a bar
section in Settings → DankBar Layout.

## Settings

| Setting | Default |
|---|---|
| Low battery warning | 20 % |
| Desktop notification (`notify-send`) | on |
| Refresh interval for OpenRazer/HeadsetControl | 1 minute |

## Translations

English and German (`translations/de.json`). Contributions welcome.

## License

MIT
