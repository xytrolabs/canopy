import QtQuick
import Quickshell
import Quickshell.Networking
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
        title: "Wi-Fi"
        description: Networking.devices && Networking.devices.values.length > 0
                     ? "Managed through NetworkManager."
                     : "No network device reported by NetworkManager."

        SettingRow {
            label: "Wi-Fi radio"
            hint: Networking.wifiEnabled ? "Enabled" : "Disabled"
            ToggleSwitch {
                value: Networking.wifiEnabled
                onToggled: (v) => Networking.wifiEnabled = v
            }
        }

        Repeater {
            model: Networking.devices
            delegate: Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: modelData.networks ? modelData.networks.values : []
                    delegate: Rectangle {
                        width: parent.width
                        height: 38
                        radius: 8
                        color: netHover.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent"

                        HoverHandler { id: netHover }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            CanopyIcon {
                                size: 16
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "network-wireless"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 220
                                text: modelData.name
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 88; height: 24; radius: 8
                            color: modelData.connected ? Theme.accent
                                                       : (joinMa.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                                                                               : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: modelData.connected ? "Connected" : "Connect"
                                color: modelData.connected ? "white" : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeXs
                                font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: joinMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.connected) modelData.disconnect()
                                    else modelData.connect()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
