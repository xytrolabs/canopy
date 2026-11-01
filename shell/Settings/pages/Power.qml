import QtQuick
import Quickshell.Services.UPower
import "../Components"
import "../../"

Column {
    id: page
    property var store
    property var shell
    width: parent ? parent.width : 0
    spacing: Theme.spacingLg

    readonly property var battery: UPower.displayDevice

    SectionCard {
        width: parent.width
        title: "Battery"
        description: battery !== null && battery.percentage > 0
                     ? "Read from UPower."
                     : "No battery detected on this system. Controls are hidden."

        SettingRow {
            visible: battery !== null && battery.percentage > 0
            label: "Charge level"
            hint: UPower.onBattery ? "Running on battery" : "Connected to power"
            Text {
                text: Math.round(battery ? battery.percentage : 0) + "%"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMd
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
            }
        }

        SettingRow {
            visible: battery !== null && battery.timeToEmpty > 0
            label: "Time remaining"
            hint: "Estimated by UPower"
            Text {
                text: Math.round(battery ? battery.timeToEmpty / 3600 : 0) + " h"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSm
                font.family: Theme.fontFamily
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Power profile"
        description: "Requires power-profiles-daemon. Greyed out when unavailable."

        SettingRow {
            label: "Profile"
            hint: PowerProfiles.hasPerformanceProfile ? "Daemon available" : "Only balanced/saver available"
            ChoiceRow {
                options: ["Saver", "Balanced", "Performance"]
                current: PowerProfiles.profile === PowerProfile.PowerSaver ? 0
                         : (PowerProfiles.profile === PowerProfile.Performance ? 2 : 1)
                enabled: true
                onActivated: (i) => {
                    PowerProfiles.profile = [PowerProfile.PowerSaver,
                                             PowerProfile.Balanced,
                                             PowerProfile.Performance][i]
                }
            }
        }
    }
}
