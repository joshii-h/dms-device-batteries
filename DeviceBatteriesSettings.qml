import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "deviceBatteries"

    SelectionSetting {
        settingKey: "warnLevel"
        label: I18n.trFor("deviceBatteries", "Low battery warning")
        description: I18n.trFor("deviceBatteries", "Warn once per device at or below this level; the bar turns orange, red at 10 % or less")
        options: [
            { label: "10 %", value: "10" },
            { label: "15 %", value: "15" },
            { label: "20 %", value: "20" },
            { label: "30 %", value: "30" }
        ]
        defaultValue: "20"
    }

    ToggleSetting {
        settingKey: "notify"
        label: I18n.trFor("deviceBatteries", "Desktop notification")
        description: I18n.trFor("deviceBatteries", "Send a desktop notification when a device runs low")
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "pollSeconds"
        label: I18n.trFor("deviceBatteries", "Refresh interval")
        description: I18n.trFor("deviceBatteries", "How often Razer, headset and BlueFerry levels are read (UPower devices update live)")
        options: [
            { label: I18n.trFor("deviceBatteries", "30 seconds"), value: "30" },
            { label: I18n.trFor("deviceBatteries", "1 minute"), value: "60" },
            { label: I18n.trFor("deviceBatteries", "5 minutes"), value: "300" }
        ]
        defaultValue: "60"
    }
}
