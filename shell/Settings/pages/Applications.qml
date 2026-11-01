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
        title: "Launcher"
        description: "How the application launcher behaves."

        SettingRow {
            label: "Show recommended section"
            hint: "Adds a second column of suggestions under Pinned"
            ToggleSwitch {
                value: shell.showRecommended
                onToggled: (v) => { shell.showRecommended = v; store.showRecommended = v }
            }
        }

        SettingRow {
            label: "Open launcher"
            hint: "Test the launcher without leaving Settings"
            Rectangle {
                width: 110; height: 30; radius: 9
                color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "Open"
                    color: "white"
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { shell.launcherOpen = true; shell.settingsOpen = false }
                }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "Installed applications"
        description: shell.appCount + " desktop entries found in the XDG data directories."

        ListView {
            width: parent.width
            height: 300
            clip: true
            model: shell.allApps()
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2

            delegate: Rectangle {
                width: ListView.view ? ListView.view.width : 300
                height: 38
                radius: 8
                color: rowMa.containsMouse ? (Theme.darkMode ? "#1FFFFFFF" : "#0D000000") : "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    CanopyIcon {
                        size: 22
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: modelData.icon ? modelData.icon : ""
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 260
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
                    width: 74; height: 24; radius: 8
                    color: pinMa.containsMouse ? Theme.accent : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                    Text {
                        anchors.centerIn: parent
                        text: shell.isPinned(modelData.id) ? "Unpin" : "Pin"
                        color: pinMa.containsMouse ? "white" : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        id: pinMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.togglePinned(modelData.id)
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    anchors.rightMargin: 90
                    hoverEnabled: true
                    onClicked: modelData.execute()
                }
            }
        }
    }
}
