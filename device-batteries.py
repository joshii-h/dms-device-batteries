#!/usr/bin/env python3
"""Battery levels of devices that UPower does not know about, as JSON.

Used by the DMS plugin "Device Batteries". Phones and Bluetooth devices are
read directly from UPower by the plugin; this helper adds:

  - Razer devices via OpenRazer (openrazer-daemon must be running)
  - USB headsets via HeadsetControl (e.g. Logitech/Astro, SteelSeries, HyperX)

Both sources are optional; missing tools are skipped silently.
Output: [{"key", "name", "icon", "percent", "charging", "source"}]
Unknown levels (-1) and sleeping Razer mice (0 % and not charging) are left out.

  device-batteries.py               # print once
  device-batteries.py --watch 60    # keep running: one JSON line per change,
                                    # re-read at once on udev events (device
                                    # plugged in, mouse docked) and every 60 s
"""
import json
import os
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
            level, charging = d.battery_level, bool(d.is_charging)
            # -1 = unknown; a sleeping wireless mouse reports 0 % (not charging)
            if level < 0 or (level == 0 and not charging):
                continue
            typ = str(d.type).lower()
            out.append({
                "name": d.name.replace(" (Receiver)", "").replace(" (Wireless)", ""),
                "icon": "mouse" if "mouse" in typ else ("keyboard" if "keyboard" in typ else
                                                        "headphones" if "headset" in typ else "devices"),
                "percent": round(level),
                "charging": charging,
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
            level = int(b.get("level", -1))
            if status not in ("BATTERY_AVAILABLE", "BATTERY_CHARGING") or level < 0:
                continue
            out.append({
                "name": d.get("device") or d.get("product") or "Headset",
                "icon": "headphones",
                "percent": level,
                "charging": status == "BATTERY_CHARGING",
                "source": "headsetcontrol",
            })

    # stable, unique keys (two identical headsets must not share a warning)
    seen = {}
    for d in out:
        base = d["source"] + ":" + d["name"]
        seen[base] = seen.get(base, 0) + 1
        d["key"] = base if seen[base] == 1 else f"{base}#{seen[base]}"
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
    parent = os.getppid()
    while True:
        # the shell went away (restart/crash): stop instead of lingering on
        if os.getppid() != parent:
            return
        cur = json.dumps(collect(), ensure_ascii=False)
        if cur != last:
            print(cur, flush=True)
            last = cur
        deadline = time.time() + interval
        while (left := deadline - time.time()) > 0:
            if os.getppid() != parent:
                return
            left = min(left, 10)
            if mon is None:
                time.sleep(left)
                continue
            if mon.poll(timeout=left) is not None:
                # let the device settle, then swallow the rest of the burst
                time.sleep(1.5)
                while mon.poll(timeout=0) is not None:
                    pass
                break


if "--watch" in sys.argv:
    i = sys.argv.index("--watch")
    try:
        secs = int(sys.argv[i + 1])
    except (IndexError, ValueError):
        secs = 60
    try:
        watch(max(5, secs))
    except (KeyboardInterrupt, BrokenPipeError):
        pass
else:
    print(json.dumps(collect(), ensure_ascii=False))
