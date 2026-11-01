import QtQuick
import "../Components"
import "../../"

Column {
    id: page
    property var store
    property var shell
    width: parent ? parent.width : 0
    spacing: Theme.spacingLg

    SectionCard {
        width: parent.width
        title: "System Panel"
        description: "The full-width bar at the top of the screen."

        SettingRow {
            label: "Panel height"
            hint: "Thickness of the top bar"
            SliderRow {
                from: 30; to: 48
                value: shell.panelHeight
                suffix: " px"
                onMoved: (v) => { shell.setPanelHeight(v) }
            }
        }

        SettingRow {
            label: "Show panel"
            hint: "Hides the panel entirely (Super+Shift+P also toggles)"
            ToggleSwitch {
                value: shell.panelVisible
                onToggled: (v) => { shell.setPanelVisible(v) }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "System Tray"
        description: "The vertical pill on the left edge."

        SettingRow {
            label: "Position"
            hint: "Which screen edge the tray sits on"
            ChoiceRow {
                options: ["Left", "Right"]
                current: store.trayPosition === "right" ? 1 : 0
                onActivated: (i) => {
                    const pos = i === 1 ? "right" : "left"
                    shell.setTrayPosition(pos)
                }
            }
        }

        SettingRow {
            label: "Icon size"
            hint: "Glyph size inside the tray pill"
            SliderRow {
                from: 16; to: 28
                value: shell.trayIconSize
                suffix: " px"
                onMoved: (v) => { shell.setTrayIconSize(v) }
            }
        }

        SettingRow {
            label: "Auto-hide"
            hint: "Slide away until the pointer reaches the screen edge"
            ToggleSwitch {
                value: store.trayAutoHide
                onToggled: (v) => { shell.setTrayAutoHide(v) }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Dock"
        description: "The floating application bar at the bottom."

        SettingRow {
            label: "Auto-hide"
            hint: "Hides while windows are open, returns on edge hover"
            ToggleSwitch {
                value: store.dockAutoHide
                onToggled: (v) => { shell.setDockAutoHide(v) }
            }
        }

        SettingRow {
            label: "Alignment"
            hint: "Horizontal placement of the dock"
            ChoiceRow {
                options: ["Left", "Centre", "Right"]
                current: store.dockAlignment === "left" ? 0
                         : (store.dockAlignment === "right" ? 2 : 1)
                onActivated: (i) => {
                    const a = ["left", "center", "right"][i]
                    shell.setDockAlignment(a)
                }
            }
        }

        SettingRow {
            label: "Distance from bottom"
            hint: "Gap between the dock and the screen edge"
            SliderRow {
                from: 0; to: 40
                value: shell.dockMargin
                suffix: " px"
                onMoved: (v) => { shell.setDockMargin(v) }
            }
        }

        SettingRow {
            label: "Icon size"
            hint: "Size of application icons in the dock"
            SliderRow {
                from: 28; to: 56
                value: shell.dockIconSize
                suffix: " px"
                onMoved: (v) => { shell.setDockIconSize(v) }
            }
        }

        SettingRow {
            label: "Hover magnification"
            hint: "Icons grow slightly under the pointer"
            ToggleSwitch {
                value: shell.dockMagnify
                onToggled: (v) => { shell.setDockMagnify(v) }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Pinned applications"
        description: "Click an app below to pin or unpin it. Pinned apps lead the dock and the launcher."

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: shell.pinnedIds
                delegate: Rectangle {
                    width: chipTxt.implicitWidth + 28
                    height: 26
                    radius: 13
                    color: Theme.accent
                    Text {
                        id: chipTxt
                        anchors.centerIn: parent
                        text: modelData + "  \u00D7"
                        color: "white"
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.togglePinned(modelData)
                    }
                }
            }
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: shell.pinnableApps()
                delegate: Rectangle {
                    width: addTxt.implicitWidth + 24
                    height: 26
                    radius: 13
                    color: Theme.darkMode ? "#1FFFFFFF" : "#0D000000"
                    Text {
                        id: addTxt
                        anchors.centerIn: parent
                        text: modelData.name
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.togglePinned(modelData.id)
                    }
                }
            }
        }
    }
}
