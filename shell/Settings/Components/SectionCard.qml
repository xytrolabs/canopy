import QtQuick
import "../../"

// A titled card that groups related settings rows.
Item {
    id: root
    property string title: ""
    property string description: ""
    default property alias content: body.data
    width: parent ? parent.width : 0

    implicitHeight: layout.height
    height: implicitHeight

    Column {
        id: layout
        width: parent.width
        spacing: Theme.spacingXs

        Text {
            visible: root.title !== ""
            width: parent.width
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            font.family: Theme.fontFamily
        }
        Text {
            visible: root.description !== ""
            width: parent.width
            text: root.description
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeXs
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: Math.max(48, body.implicitHeight + Theme.spacingLg * 2)
            radius: Theme.radiusMedium
            color: Theme.darkMode ? "#14FFFFFF" : "#0A000000"
            border.color: Theme.darkMode ? "#1FFFFFFF" : "#0F000000"
            border.width: 1

            Column {
                id: body
                x: Theme.spacingMd
                y: Theme.spacingMd
                width: parent.width - Theme.spacingMd * 2
                spacing: Theme.spacingSm
            }
        }
    }
}
