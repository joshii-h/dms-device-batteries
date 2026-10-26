import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Runs exactly once (DMS daemon surface): collects all devices, sends the
// low-battery warnings and shares the sorted list with every bar widget via
// the plugin global variable "devices".
PluginComponent {
    id: root

    readonly property int warnLevel: parseInt(pluginData.warnLevel) || 20
    readonly property bool notify: pluginData.notify !== undefined ? pluginData.notify : true
    readonly property int pollSeconds: Math.max(5, parseInt(pluginData.pollSeconds) || 60)
    readonly property string helper: pluginService ? pluginService.getPluginPath(pluginId) + "/device-batteries.py" : ""

    property var extraDevices: []
    property var warned: ({})
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
            } else if (d.percent <= warnLevel && !w[d.key]) {
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

    // helper keeps running: one JSON line per change, re-read at once on udev
    // events (device plugged in, mouse docked) and every pollSeconds otherwise
    Process {
        id: helperProc
        running: root.helperWanted && root.helper !== ""
        command: ["python3", root.helper, "--watch", String(root.pollSeconds)]
        stdout: SplitParser {
            onRead: line => {
                try { root.extraDevices = JSON.parse(line || "[]"); }
                catch (e) { /* ignore partial lines */ }
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

    Component.onCompleted: PluginService.setGlobalVar("deviceBatteries", "devices", devices)
    Component.onDestruction: PluginService.setGlobalVar("deviceBatteries", "devices", [])
}
