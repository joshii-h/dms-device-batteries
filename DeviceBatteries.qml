import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

// Bar widget (one per monitor): display only. The daemon collects the
// devices, sends the warnings and shares the sorted list as global "devices".
PluginComponent {
    id: root

    readonly property int warnLevel: parseInt(pluginData.warnLevel) || 20
    property var devices: PluginService.getGlobalVar("deviceBatteries", "devices", [])
    property var problems: PluginService.getGlobalVar("deviceBatteries", "problems", [])
    readonly property var lowest: devices.length > 0 ? devices[0] : null

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId !== "deviceBatteries")
                return;
            if (varName === "devices")
                root.devices = PluginService.getGlobalVar("deviceBatteries", "devices", []);
            else if (varName === "problems")
                root.problems = PluginService.getGlobalVar("deviceBatteries", "problems", []);
        }
    }

    // no device: hide the pill completely (an invisible Row keeps its width)
    onLowestChanged: setVisibilityOverride(lowest !== null)
    Component.onCompleted: setVisibilityOverride(lowest !== null)

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

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

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
    popoutHeight: 90 + Math.max(1, devices.length) * 44 + problems.length * 64

    popoutContent: Component {
        PopoutComponent {
            headerText: I18n.trFor("deviceBatteries", "Device Batteries")
            detailsText: root.devices.length === 0 && root.problems.length === 0
                         ? I18n.trFor("deviceBatteries", "No devices with a battery level found") : ""

            Column {
                width: parent.width
                spacing: Theme.spacingS

                // setup problems (e.g. Razer driver missing) above the devices
                Repeater {
                    model: root.problems
                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        spacing: Theme.spacingM

                        DIcon {
                            name: "warning"
                            size: 22
                            color: Theme.warning
                        }
                        StyledText {
                            width: parent.width - 22 - Theme.spacingM
                            text: modelData.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.warning
                        }
                    }
                }

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
