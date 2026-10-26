import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

// Device Batteries: UPower (phones, Bluetooth) + device-batteries.py (Razer, USB headsets)
PluginComponent {
    id: root

    readonly property int warnLevel: parseInt(pluginData.warnLevel || "20")
    readonly property bool notify: pluginData.notify !== undefined ? pluginData.notify : true
    readonly property int pollSeconds: parseInt(pluginData.pollSeconds || "60")
    readonly property string helper: pluginService.pluginDirectory + "/deviceBatteries/device-batteries.py"
    // one helper for all bar instances (one per monitor): the first instance
    // owns it and shares the result via plugin global variables; another
    // instance takes over if the owner goes away (monitor unplugged)
    readonly property string instanceId: Math.random().toString(36).slice(2)
    property string owner: ""
    property var extraDevices: []
    property var warned: ({})
    readonly property bool isOwner: owner === instanceId

    function syncGlobals() {
        owner = PluginService.getGlobalVar("deviceBatteries", "helperOwner", "");
        extraDevices = PluginService.getGlobalVar("deviceBatteries", "extraDevices", []);
        if (!owner) {
            PluginService.setGlobalVar("deviceBatteries", "helperOwner", instanceId);
            owner = instanceId;
        }
    }
    Component.onCompleted: syncGlobals()
    Component.onDestruction: if (isOwner) PluginService.setGlobalVar("deviceBatteries", "helperOwner", "")
    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === "deviceBatteries")
                root.syncGlobals();
        }
    }

    // external devices from UPower only – the laptop battery has its own DMS widget
    readonly property var upowerDevices: UPower.devices.values
        .filter(d => d.ready && !d.isLaptopBattery && d.percentage > 0
                && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Ups)
        .map(d => ({
            name: d.model || I18n.trFor("deviceBatteries", "Device"),
            icon: iconFor(d.type),
            percent: Math.round(d.percentage * 100),
            charging: d.state === UPowerDeviceState.Charging,
            source: "upower"
        }))

    readonly property var devices: upowerDevices.concat(extraDevices)
        .sort((a, b) => a.percent - b.percent)
    readonly property var lowest: devices.length > 0 ? devices[0] : null

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

    function levelColor(dev) {
        if (!dev) return Theme.surfaceText;
        if (dev.charging) return Theme.primary;
        if (dev.percent <= 10) return Theme.error;
        if (dev.percent <= warnLevel) return Theme.warning;
        return Theme.surfaceText;
    }

    function batteryIcon(dev) {
        if (dev.charging) return "battery_charging_full";
        const steps = ["battery_0_bar", "battery_1_bar", "battery_2_bar", "battery_3_bar",
                       "battery_4_bar", "battery_5_bar", "battery_6_bar", "battery_full"];
        return steps[Math.min(7, Math.floor(dev.percent / 12.5))];
    }

    // one warning per device, re-armed once it has been charged (owner only,
    // otherwise every monitor's bar would send its own notification)
    onDevicesChanged: {
        if (!isOwner)
            return;
        const w = Object.assign({}, warned);
        for (const d of devices) {
            if (d.charging || d.percent > warnLevel + 5) {
                delete w[d.name];
            } else if (d.percent <= warnLevel && !w[d.name]) {
                w[d.name] = true;
                if (notify)
                    Quickshell.execDetached(["notify-send", "-a", I18n.trFor("deviceBatteries", "Device Batteries"),
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
        id: extraProc
        running: root.isOwner
        command: ["python3", root.helper, "--watch", String(root.pollSeconds)]
        stdout: SplitParser {
            onRead: line => {
                try { PluginService.setGlobalVar("deviceBatteries", "extraDevices", JSON.parse(line || "[]")); }
                catch (e) { /* ignore partial lines */ }
            }
        }
        onExited: if (root.isOwner) restartTimer.start()
    }

    Timer {
        id: restartTimer
        interval: 10000
        onTriggered: if (root.isOwner) extraProc.running = true
    }

    // new interval: restart the helper with it
    onPollSecondsChanged: if (extraProc.running) { extraProc.running = false; }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            visible: root.lowest !== null

            DIcon {
                name: root.lowest ? root.lowest.icon : "battery_unknown"
                size: root.iconSize
                color: root.levelColor(root.lowest)
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.lowest ? root.lowest.percent + "%" : ""
                font.pixelSize: root.textSize
                color: root.levelColor(root.lowest)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            visible: root.lowest !== null

            DIcon {
                name: root.lowest ? root.lowest.icon : "battery_unknown"
                size: root.iconSize
                color: root.levelColor(root.lowest)
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.lowest ? root.lowest.percent : ""
                font.pixelSize: root.textSize
                color: root.levelColor(root.lowest)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 340
    popoutHeight: 90 + Math.max(1, devices.length) * 44

    popoutContent: Component {
        PopoutComponent {
            headerText: I18n.trFor("deviceBatteries", "Device Batteries")
            detailsText: root.devices.length === 0 ? I18n.trFor("deviceBatteries", "No devices with a battery level found") : ""

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.devices
                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        height: 36
                        spacing: Theme.spacingM

                        DIcon {
                            name: modelData.icon
                            size: 22
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            width: parent.width - 22 - 110 - Theme.spacingM * 2
                            text: modelData.name
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Row {
                            width: 110
                            spacing: Theme.spacingXS
                            layoutDirection: Qt.RightToLeft
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText {
                                text: modelData.percent + "%"
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.levelColor(modelData)
                            }
                            DIcon {
                                name: root.batteryIcon(modelData)
                                size: 20
                                color: root.levelColor(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
