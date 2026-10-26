#!/usr/bin/env python3
"""Battery levels of devices that UPower does not know about, as JSON.

Used by the DMS plugin "Device Batteries". Phones and Bluetooth devices are
read directly from UPower by the plugin; this helper adds:

  - Razer devices via OpenRazer (openrazer-daemon must be running)
  - USB headsets via HeadsetControl (e.g. Logitech/Astro, SteelSeries, HyperX)

Both sources are optional; missing tools are skipped silently.
Output: [{"name", "icon", "percent", "charging", "source"}]

  device-batteries.py               # print once
  device-batteries.py --watch 60    # keep running: one JSON line per change,
                                    # re-read at once on udev events (device
                                    # plugged in, mouse docked) and every 60 s
"""
import json
import shutil
import subprocess
import sys
import time


def collect():
    out = []

    # Razer via OpenRazer
    try:
        from openrazer.client import DeviceManager
        razer = list(DeviceManager().devices)
    except Exception:
        razer = []
    for d in razer:
        try:
            if not d.capabilities.get("battery"):
                continue
            typ = str(d.type).lower()
            out.append({
                "name": d.name.replace(" (Receiver)", "").replace(" (Wireless)", ""),
                "icon": "mouse" if "mouse" in typ else ("keyboard" if "keyboard" in typ else
                                                        "headphones" if "headset" in typ else "devices"),
                "percent": round(d.battery_level),
                "charging": bool(d.is_charging),
                "source": "openrazer",
            })
        except Exception:
            pass  # device asleep or switched off

    # Headsets via HeadsetControl
    if shutil.which("headsetcontrol"):
        try:
            r = subprocess.run(["headsetcontrol", "-b", "-o", "json"],
                               capture_output=True, text=True, timeout=8)
            data = json.loads(r.stdout or "{}")
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            data = {}
        for d in data.get("devices", []):
            b = d.get("battery") or {}
            status = b.get("status", "")
            if status not in ("BATTERY_AVAILABLE", "BATTERY_CHARGING"):
                continue
            out.append({
                "name": d.get("device") or d.get("product") or "Headset",
                "icon": "headphones",
                "percent": int(b.get("level", 0)),
                "charging": status == "BATTERY_CHARGING",
                "source": "headsetcontrol",
            })

    return out


def watch(interval):
    """Print a JSON line whenever the result changes; wake early on udev events."""
    try:
        import pyudev
        mon = pyudev.Monitor.from_netlink(pyudev.Context())
        for sub in ("usb", "hidraw", "power_supply"):
            mon.filter_by(sub)
        mon.start()
    except Exception:
        mon = None   # no pyudev: plain polling
    last = None
    while True:
        cur = json.dumps(collect(), ensure_ascii=False)
        if cur != last:
            print(cur, flush=True)
            last = cur
        deadline = time.time() + interval
        while time.time() < deadline:
            if mon is None:
                time.sleep(deadline - time.time())
                break
            if mon.poll(timeout=deadline - time.time()) is not None:
                # let the device settle, then swallow the rest of the burst
                time.sleep(1.5)
                while mon.poll(timeout=0) is not None:
                    pass
                break


if "--watch" in sys.argv:
    i = sys.argv.index("--watch")
    secs = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 else 60
    try:
        watch(max(5, secs))
    except (KeyboardInterrupt, BrokenPipeError):
        pass
else:
    print(json.dumps(collect(), ensure_ascii=False))
