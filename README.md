# Device Batteries

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin
that shows the battery levels of all your wireless peripherals in one place.
Other plugins cover a single device (one mouse model, controllers, ZMK
keyboards, a phone); this one combines UPower, OpenRazer and HeadsetControl
in one widget. It is meant for external hardware only – the laptop battery
already has its own DMS widget.

![popout](assets/popout.png)

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
bundled helper `device-batteries.py`, which keeps running and re-reads at once
when a device is plugged in or docked (udev, needs `pyudev`), otherwise at the
configured interval. With several monitors only one helper runs and all bars
share its result. Every source is optional – whatever is not installed is
skipped.

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
| Refresh interval for OpenRazer/HeadsetControl (plug-in events update at once) | 1 minute |

## Translations

English and German (`translations/de.json`). Contributions welcome.

## License

MIT
