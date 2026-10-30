import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Runs exactly once (DMS daemon surface): collects all devices, sends the
// low-battery warnings and shares the sorted list with every bar widget via
// the plugin global variable "devices" (setup problems via "problems").
PluginComponent {
    id: root

    readonly property int warnLevel: parseInt(pluginData.warnLevel) || 20
    readonly property bool notify: pluginData.notify !== undefined ? pluginData.notify : true
    readonly property int pollSeconds: Math.max(5, parseInt(pluginData.pollSeconds) || 60)
    readonly property string helper: pluginService ? pluginService.getPluginPath(pluginId) + "/device-batteries.py" : ""

    property var extraDevices: []
    property var problems: []
    property var warned: ({})
    property var problemsShown: ({})
    property bool helperWanted: true

    // external devices from UPower only – the laptop battery has its own DMS widget
    readonly property var upowerDevices: UPower.devices.values
        .filter(d => d.ready && !d.isLaptopBattery && d.percentage > 0
                && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Ups)
        .map(d => ({
            key: "upower:" + d.nativePath,
            name: d.model || UPowerDeviceType.toString(d.type),
            icon: iconFor(d.type),
            percent: Math.round(d.percentage * 100),
            charging: d.state === UPowerDeviceState.Charging,
            source: "upower"
        }))

    readonly property var devices: upowerDevices.concat(extraDevices)
        .sort((a, b) => a.percent - b.percent)

    function iconFor(t) {
        switch (t) {
        case UPowerDeviceType.Phone: return "smartphone";
        case UPowerDeviceType.Mouse: return "mouse";
        case UPowerDeviceType.Keyboard: return "keyboard";
        case UPowerDeviceType.Headset:
        case UPowerDeviceType.Headphones: return "headphones";
        case UPowerDeviceType.GamingInput: return "sports_esports";
        case UPowerDeviceType.Tablet: return "tablet";
        case UPowerDeviceType.Wearable: return "watch";
        default: return "bluetooth";
        }
    }

    // one warning per device, re-armed once it has been charged
    onDevicesChanged: {
        PluginService.setGlobalVar("deviceBatteries", "devices", devices);
        const w = Object.assign({}, warned);
        for (const d of devices) {
            if (d.charging || d.percent > warnLevel + 5) {
                delete w[d.key];
            } else if (d.percent <= warnLevel && !w[d.key] && d.warn !== false) {
                w[d.key] = true;
                if (notify)
                    Quickshell.execDetached(["dms", "notify", "-a", I18n.trFor("deviceBatteries", "Device Batteries"),
                        "-i", "battery-caution",
                        I18n.trFor("deviceBatteries", "%1: battery low").arg(d.name),
                        I18n.trFor("deviceBatteries", "%1 % left – please charge.").arg(d.percent)]);
            }
        }
        warned = w;
    }

    function problemText(id) {
        switch (id) {
        case "razer-driver":
            return I18n.trFor("deviceBatteries", "A Razer device is plugged in, but the OpenRazer kernel driver is not loaded – rebuild or load the openrazer driver for the running kernel.");
        case "razer-daemon":
            return I18n.trFor("deviceBatteries", "The OpenRazer driver is loaded, but openrazer-daemon does not answer – start it.");
        default:
            return id;
        }
    }

    // one notification per problem until it is gone again
    onProblemsChanged: {
        const list = problems.map(p => ({ key: p.key, id: p.id, text: problemText(p.id) }));
        PluginService.setGlobalVar("deviceBatteries", "problems", list);
        const shown = {};
        for (const p of list) {
            if (!problemsShown[p.key] && notify)
                Quickshell.execDetached(["dms", "notify", "-a", I18n.trFor("deviceBatteries", "Device Batteries"),
                    "-i", "dialog-warning", I18n.trFor("deviceBatteries", "Battery level unavailable"), p.text]);
            shown[p.key] = true;
        }
        problemsShown = shown;
    }

    // helper keeps running: one JSON line per change, re-read at once on udev
    // events (device plugged in, mouse docked) and every pollSeconds otherwise
    Process {
        id: helperProc
        running: root.helperWanted && root.helper !== ""
        command: ["python3", root.helper, "--watch", String(root.pollSeconds)]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line || "[]");
                    // older helpers printed a plain device list
                    root.extraDevices = Array.isArray(data) ? data : (data.devices || []);
                    root.problems = Array.isArray(data) ? [] : (data.problems || []);
                } catch (e) { /* ignore partial lines */ }
            }
        }
        onExited: {
            // unexpected exit: retry in 10 s; planned restart: right away
            if (root.helperWanted) {
                root.helperWanted = false;
                restartTimer.interval = 10000;
            }
            restartTimer.start();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root.helperWanted = true
    }

    // new interval: restart the helper with it
    onPollSecondsChanged: {
        if (helperProc.running) {
            restartTimer.interval = 200;
            helperWanted = false;   // stops the process, onExited restarts it
        }
    }

    Component.onCompleted: {
        PluginService.setGlobalVar("deviceBatteries", "devices", devices);
        PluginService.setGlobalVar("deviceBatteries", "problems", []);
    }
}
