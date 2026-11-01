import QtQuick
import Quickshell
import "../Components"
import "../../"

Column {
    id: page
    property var store
    property var shell
    width: parent ? parent.width : 0
    spacing: Theme.spacingLg

    // ---- Software updates ----
    // Canopy ships its own updater (scripts/canopy-update.sh) because no
    // distribution packages it: check the release host, verify the payload's
    // SHA-256, install, restart. Auto-check is daily; auto-install is not a
    // thing - the user presses the button.
    SectionCard {
        width: parent.width
        title: "Software updates"
        description: "Canopy updates itself from its own release channel."

        SettingRow {
            label: "Version"
            hint: shell.installedVersion !== "" ? ("Installed · " + shell.installedVersion)
                                                : "Version stamp not found"

            Text {
                text: shell.updateAvailable ? (shell.availableVersion + " available")
                                            : (shell.updateStatus !== "" ? shell.updateStatus : "—")
                color: shell.updateAvailable ? Theme.accent : Theme.textSecondary
                font.pixelSize: Theme.fontSizeSm
                font.family: Theme.fontFamily
            }
        }

        Row {
            spacing: 8

            // Check now
            Rectangle {
                width: 118; height: 30; radius: 9
                color: checkMa.containsMouse && !shell.updateChecking
                       ? (Theme.darkMode ? "#26FFFFFF" : "#14000000")
                       : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                Text {
                    anchors.centerIn: parent
                    text: shell.updateChecking ? "Checking…" : "Check now"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: checkMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !shell.updateChecking
                    onClicked: shell.checkForUpdates(false)
                }
            }

            // Install — only meaningful when there is something to install.
            Rectangle {
                width: 128; height: 30; radius: 9
                visible: shell.updateAvailable || shell.updateInstalling
                color: shell.updateInstalling ? Theme.accentPressed
                       : (installMa.containsMouse ? Theme.accentHover : Theme.accent)
                Text {
                    anchors.centerIn: parent
                    text: shell.updateInstalling ? "Installing…" : ("Install " + shell.availableVersion)
                    color: "white"
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Font.DemiBold
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: installMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !shell.updateInstalling
                    onClicked: shell.installUpdate()
                }
            }
        }

        SettingRow {
            label: "Check automatically"
            hint: "Once a day, in the background. Installing always needs a click."

            ToggleSwitch {
                value: shell.autoUpdate
                onToggled: (on) => shell.setAutoUpdate(on)
            }
        }

        Text {
            visible: shell.updateError !== ""
            width: parent.width
            text: shell.updateError
            color: Theme.danger
            font.pixelSize: Theme.fontSizeXs
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
        }
    }

    SectionCard {
        width: parent.width
        title: "Session"
        description: "Current Canopy session details."

        Repeater {
            model: [
                "Compositor: Labwc (wlroots)",
                "Shell: Quickshell 0.3.2",
                "Toolkit: Qt 6 / QML",
                "Desktop: Canopy",
                "Screens: " + Quickshell.screens.length
            ]
            delegate: Text {
                text: modelData
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeXs
                font.family: Theme.fontFamily
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Maintenance"
        description: "These actions affect the running shell."

        SettingRow {
            label: "Restart Canopy shell"
            hint: "Reloads the shell, keeping persisted settings"
            Rectangle {
                width: 120; height: 30; radius: 9
                color: rMa.containsMouse ? Theme.accent : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                Text {
                    anchors.centerIn: parent
                    text: "Restart"
                    color: rMa.containsMouse ? "white" : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: rMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.restartShell()
                }
            }
        }

        SettingRow {
            label: "Reset all preferences"
            hint: "Restores every Canopy setting to its default"
            Rectangle {
                width: 120; height: 30; radius: 9
                color: dMa.containsMouse ? Theme.danger : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                border.color: Theme.danger
                border.width: dMa.containsMouse ? 0 : 1
                Text {
                    anchors.centerIn: parent
                    text: shell.confirmReset ? "Confirm?" : "Reset"
                    color: dMa.containsMouse ? "white" : Theme.danger
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: dMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.requestReset()
                }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "About Canopy"
        description: "Mac functionality. Windows simplicity. Canopy identity."

        Text {
            text: "Canopy"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeTitle
            font.weight: Font.Bold
            font.family: Theme.fontFamily
        }
        Text {
            text: "A lightweight, modular Linux desktop environment by Xytro Labs."
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSm
            font.family: Theme.fontFamily
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Text {
            text: "Shell: QML / Quickshell · Compositor: Labwc · Theme engine: Canopy tokens"
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeXs
            font.family: Theme.fontFamily
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Text {
            text: "Acknowledgements: Quickshell (LGPL-3.0), Kora icon theme, Cantarell typeface."
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeXs
            font.family: Theme.fontFamily
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Text {
            text: "Licensed under the MIT License."
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeXs
            font.family: Theme.fontFamily
        }
    }
}
