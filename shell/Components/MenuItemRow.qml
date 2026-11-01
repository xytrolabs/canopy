import QtQuick
import ".."

// MenuItemRow - a single row inside a Canopy context menu.
// Data comes from a plain JS object (see MenuController for the schema).
Item {
    id: root

    property var item: null
    property bool hovered: false
    property int iconSize: 16

    readonly property bool isSep: !!(item && item.sep === true)
    readonly property bool disabled: !!(item && item.enabled === false)

    height: isSep ? 9 : 32
    width: parent ? parent.width : 220

    Rectangle {
        visible: !root.isSep
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: 7
        color: (root.hovered && !root.disabled) ? Theme.hoverBg : "transparent"
    }

    Rectangle {
        visible: root.isSep
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 1
        color: Theme.hairline
    }

    Row {
        visible: !root.isSep
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        // Fixed icon column so labels line up whether or not a row has an icon.
        Item {
            width: root.iconSize
            height: root.iconSize

            CanopyIcon {
                visible: root.item && root.item.icon !== undefined && root.item.icon !== null && root.item.icon !== ""
                anchors.centerIn: parent
                size: root.iconSize
                iconName: (root.item && root.item.icon) ? root.item.icon : ""
                tint: root.item && root.item.danger ? Theme.danger : Theme.textPrimary
                opacity: root.disabled ? 0.45 : 1.0
            }
        }

        Text {
            width: root.width - 74
            anchors.verticalCenter: parent.verticalCenter
            text: root.item ? (root.item.label || "") : ""
            color: root.item && root.item.danger ? Theme.danger
                 : (root.disabled ? Theme.textMuted : Theme.textPrimary)
            font.pixelSize: Theme.fontSizeSm
            font.family: Theme.fontFamily
            elide: Text.ElideRight
        }
    }

    CanopyIcon {
        visible: !root.isSep && root.item && root.item.checked === true
        size: 13
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        iconName: "emblem-ok-symbolic"
        tint: Theme.accent
    }
}
