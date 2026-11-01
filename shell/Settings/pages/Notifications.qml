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
        title: "Notifications"
        description: "Canopy runs its own freedesktop notification server."
               + " If another daemon already owns the name, Canopy steps aside."

        SettingRow {
            label: "Enable notifications"
            hint: "Stops the notification server when disabled"
            ToggleSwitch {
                value: shell.notificationsEnabled
                onToggled: (v) => { shell.notificationsEnabled = v; store.notificationsEnabled = v }
            }
        }

        SettingRow {
            label: "Do Not Disturb"
            hint: "Keeps notifications in history but hides toasts"
            ToggleSwitch {
                value: shell.dnd
                onToggled: (v) => { shell.dnd = v; store.dnd = v }
            }
        }
    }

    SectionCard {
        width: parent.width
        title: "History"
        description: shell.notificationCount + " item(s) kept this session."

        Row {
            spacing: 10
            Rectangle {
                width: 120; height: 30; radius: 9
                color: clrMa.containsMouse ? Theme.danger : (Theme.darkMode ? "#1FFFFFFF" : "#0D000000")
                Text {
                    anchors.centerIn: parent
                    text: "Clear history"
                    color: clrMa.containsMouse ? "white" : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.clearNotifications()
                }
            }
            Rectangle {
                width: 130; height: 30; radius: 9
                color: Theme.darkMode ? "#1FFFFFFF" : "#0D000000"
                Text {
                    anchors.centerIn: parent
                    text: "Send test"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.sendTestNotification()
                }
            }
        }

        ListView {
            width: parent.width
            height: 200
            clip: true
            model: shell.notificationsModel
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds

            delegate: Column {
                width: ListView.view ? ListView.view.width : 280
                spacing: 1
                Text {
                    width: parent.width
                    text: model.title
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSm
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: model.body
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeXs
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }
            }
        }
    }
}
