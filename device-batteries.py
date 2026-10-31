#!/usr/bin/env python3
"""Battery levels of devices that UPower does not know about, as JSON.

Used by the DMS plugin "Device Batteries". Bluetooth devices with a BlueZ
battery are read directly from UPower by the plugin; this helper adds:

  - Razer devices via OpenRazer (openrazer-daemon must be running)
  - USB headsets via HeadsetControl (e.g. Logitech/Astro, SteelSeries, HyperX)
  - the iPhone via BlueFerry (BlueZ does not export its battery to UPower)
  - AirPods/Beats (left, right, case) via the BlueFerry plugin
    blueferry-plugin-airpods, read passively from their Bluetooth adverts

All sources are optional; missing tools are skipped silently.
Output: {"devices": [{"key", "name", "icon", "percent", "charging", "source",
                      "warn" (optional, false = someone else warns already)}],
         "problems": [{"key", "id"}]}
Unknown levels (-1) and sleeping Razer mice (0 % and not charging) are left out.
"problems" lists setup issues the plugin explains to the user:
  razer-driver  a Razer device is plugged in, but no OpenRazer kernel driver
                is bound to it (module missing or not loaded)
  razer-daemon  the driver is bound, but openrazer-daemon does not answer

  device-batteries.py               # print once
  device-batteries.py --watch 60    # keep running: one JSON line per change,
                                    # re-read at once on udev events (device
                                    # plugged in, mouse docked), when the
                                    # AirPods plugin signals Changed, and
                                    # every 60 s
"""
import glob
import json
import os
import select
import shutil
import subprocess
import sys
import time


BLUEFERRY = ("io.weirdware.BlueFerry", "/io/weirdware/BlueFerry", "io.weirdware.BlueFerry.Messages1")
# blueferry-plugin-airpods: its own bus name (D-Bus activated), see its README
ACCESSORIES_PLUGIN = "io.weirdware.blueferry.airpods"
ACCESSORIES = ("io.weirdware.BlueFerry.Plugin." + ACCESSORIES_PLUGIN,
               "/io/weirdware/BlueFerry/Plugin", "io.github.joshii_h.BlueFerryAccessories1")
# AirPods only advertise while out of the case or with the lid open; older
# readings are left out instead of showing a level that may be long gone
ACCESSORY_MAX_AGE = 600


def razer_hid_drivers():
    """Drivers bound to the Razer HID interfaces (vendor 1532) right now."""
    drivers = []
    for dev in glob.glob("/sys/bus/hid/devices/*:1532:*"):
        link = os.path.join(dev, "driver")
        drivers.append(os.path.basename(os.readlink(link)) if os.path.islink(link) else "")
    return drivers


def blueferry_phone():
    """The iPhone battery from the BlueFerry daemon
    (https://github.com/erikwb/blueferry). BlueZ does not export the iPhone's Battery Service to
    UPower, and BlueFerry already holds the GATT subscription, so the level is
    taken from its status instead of reading the phone a second time."""
    try:
        import dbus
        bus = dbus.SessionBus()
        status = json.loads(str(dbus.Interface(bus.get_object(*BLUEFERRY[:2]), BLUEFERRY[2])
                                .GetStatus(timeout=5)))
    except Exception:
        return []   # BlueFerry not installed or not running
    level = status.get("phone_battery_level")
    if status.get("phone_reconnect_state") != "connected" or not isinstance(level, int) \
            or isinstance(level, bool) or not 0 <= level <= 100:
        return []
    name, key = "iPhone", "blueferry:phone"
    try:
        sysbus = dbus.SystemBus()
        objects = dbus.Interface(sysbus.get_object("org.bluez", "/"),
                                 "org.freedesktop.DBus.ObjectManager").GetManagedObjects()
        for ifaces in objects.values():
            dev = ifaces.get("org.bluez.Device1")
            if dev and dev.get("Connected") and str(dev.get("Icon", "")) == "phone":
                if "org.bluez.Battery1" in ifaces:
                    return []   # BlueZ exports it after all: UPower shows it already
                name = str(dev.get("Alias") or dev.get("Name") or name)
                key = "blueferry:" + str(dev.get("Address"))
                break
    except Exception:
        pass
    return [{
        "name": name,
        "icon": "smartphone",
        "percent": level,
        "charging": False,   # BlueFerry reports no charging state
        "source": "blueferry",
        "key": key,
        # BlueFerry sends its own low-battery warning; do not warn twice
        "warn": not status.get("phone_battery_warning", False),
    }]


def blueferry_plugin_disabled(plugin_id):
    """Whether the user disabled a plugin in BlueFerry (its plugins.json)."""
    home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    try:
        with open(os.path.join(home, "blueferry", "plugins.json"), encoding="utf-8") as f:
            value = json.loads(f.read(1024 * 1024))
    except (OSError, ValueError):
        return False
    disabled = value.get("disabled") if isinstance(value, dict) else None
    return isinstance(disabled, list) and plugin_id in disabled


def blueferry_accessories(activate=False):
    """AirPods and Beats from the BlueFerry plugin blueferry-plugin-airpods
    (https://github.com/joshii-h/blueferry-plugin-airpods): one entry per pod
    and one for the case (headphones like the AirPods Max: one entry). The
    plugin only reports the user's own devices; levels come in 10 % steps.

    The plugin is D-Bus activated. It is only started when ``activate`` is
    set (once per helper run) and never while it is disabled in BlueFerry;
    otherwise it is asked only while it runs anyway."""
    if blueferry_plugin_disabled(ACCESSORIES_PLUGIN):
        return []
    try:
        import dbus
        bus = dbus.SessionBus()
        if not activate and not bus.name_has_owner(ACCESSORIES[0]):
            return []
        data = json.loads(str(dbus.Interface(bus.get_object(*ACCESSORIES[:2]), ACCESSORIES[2])
                              .GetBatteries(timeout=5)))
    except Exception:
        return []   # plugin not installed, disabled or not answering
    if not isinstance(data, dict) or data.get("version") != 1:
        return []
    out = []
    for dev in data.get("devices") or []:
        if not isinstance(dev, dict):
            continue
        age = dev.get("age_seconds")
        if not isinstance(age, int) or age > ACCESSORY_MAX_AGE:
            continue
        name = str(dev.get("name") or "AirPods")
        ident = str(dev.get("id") or name)
        if dev.get("kind") == "headphones":
            parts = [("battery", name, "headphones")]
        else:
            parts = [("left", name + " (L)", "earbuds"), ("right", name + " (R)", "earbuds"),
                     ("case", name + " (Case)", "earbuds_battery")]
        for field, label, icon in parts:
            b = dev.get(field)
            if not isinstance(b, dict):
                continue
            level = b.get("percent")
            if not isinstance(level, int) or isinstance(level, bool) or not 0 <= level <= 100:
                continue
            out.append({
                "name": label,
                "icon": icon,
                "percent": level,
                "charging": bool(b.get("charging")),
                "source": "blueferry-airpods",
                "key": f"blueferry-airpods:{ident}:{field}",
            })
    return out


def collect(activate=False):
    out, problems = [], []

    # Razer via OpenRazer
    razer, have_openrazer, daemon_ok = [], True, True
    try:
        from openrazer.client import DeviceManager
    except Exception:
        have_openrazer = False
    if have_openrazer:
        try:
            razer = list(DeviceManager().devices)
        except Exception:
            daemon_ok = False
    # explain a Razer device without battery data – only if OpenRazer is
    # installed at all (otherwise the user does not use it on purpose)
    drivers = razer_hid_drivers() if have_openrazer and not razer else []
    if drivers:
        if not any(d.startswith("razer") for d in drivers):
            problems.append({"key": "openrazer:driver", "id": "razer-driver"})
        elif not daemon_ok:
            problems.append({"key": "openrazer:daemon", "id": "razer-daemon"})
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
                "key": "openrazer:" + str(d.serial),   # stable per device
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

    # iPhone via BlueFerry
    out.extend(blueferry_phone())

    # AirPods/Beats via the BlueFerry plugin blueferry-plugin-airpods
    out.extend(blueferry_accessories(activate))

    # unique keys for sources without a serial (two identical headsets must
    # not share a warning); Razer devices already have their serial as key
    seen = {}
    for d in out:
        if "key" in d:
            continue
        base = d["source"] + ":" + d["name"]
        seen[base] = seen.get(base, 0) + 1
        d["key"] = base if seen[base] == 1 else f"{base}#{seen[base]}"
    return {"devices": out, "problems": problems}


def accessory_events():
    """A pipe that becomes readable when the AirPods plugin signals Changed
    or comes and goes on the bus; None without dbus-python and PyGObject.
    Listening never starts the plugin."""
    try:
        import threading
        import dbus
        from dbus.mainloop.glib import DBusGMainLoop
        from gi.repository import GLib
        bus = dbus.SessionBus(mainloop=DBusGMainLoop(), private=True)
        r, w = os.pipe()
        os.set_blocking(w, False)

        def wake(*_args):
            try:
                os.write(w, b"x")
            except BlockingIOError:
                pass   # a wake-up is pending already

        bus.add_signal_receiver(wake, "Changed", ACCESSORIES[2], ACCESSORIES[0], ACCESSORIES[1])
        bus.add_signal_receiver(wake, "NameOwnerChanged", "org.freedesktop.DBus",
                                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                                arg0=ACCESSORIES[0])
        def run():
            # holds the private connection: it would be collected otherwise
            listener = bus
            GLib.MainLoop().run()
            listener.close()

        threading.Thread(target=run, daemon=True).start()
        return r
    except Exception:
        return None   # plain polling


def watch(interval):
    """Print a JSON line whenever the result changes; wake early on udev
    events and on the AirPods plugin's Changed signal."""
    try:
        import pyudev
        mon = pyudev.Monitor.from_netlink(pyudev.Context())
        for sub in ("usb", "hidraw", "power_supply"):
            mon.filter_by(sub)
        mon.start()
    except Exception:
        mon = None   # no pyudev: plain polling
    events = accessory_events()
    last = None
    parent = os.getppid()
    activate = True   # start the AirPods plugin once, then only follow it
    while True:
        # the shell went away (restart/crash): stop instead of lingering on
        if os.getppid() != parent:
            return
        cur = json.dumps(collect(activate), ensure_ascii=False)
        activate = False
        if cur != last:
            print(cur, flush=True)
            last = cur
        deadline = time.time() + interval
        while (left := deadline - time.time()) > 0:
            if os.getppid() != parent:
                return
            left = min(left, 10)
            sources = [s for s in (mon, events) if s is not None]
            if not sources:
                time.sleep(left)
                continue
            ready = select.select(sources, [], [], left)[0]
            if not ready:
                continue
            if mon is not None and mon in ready:
                # let the device settle, then swallow the rest of the burst
                time.sleep(1.5)
                while mon.poll(timeout=0) is not None:
                    pass
            if events is not None and events in ready:
                time.sleep(0.3)   # pods and case change in quick succession
                os.read(events, 4096)
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
    print(json.dumps(collect(activate=True), ensure_ascii=False))
